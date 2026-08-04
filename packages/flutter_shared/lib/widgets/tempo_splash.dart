import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The Tempo launch mark: a ring that draws itself, then keeps a beat.
///
/// ## The idea
///
/// The brand is called Tempo, so the launch moment is built around a pulse
/// rather than a logo that simply fades up. Three things happen in sequence
/// and then one of them keeps going:
///
///  1. **The sweep.** A dot starts at twelve o'clock and runs a full lap,
///     drawing the ring behind it — a stopwatch hand completing a revolution.
///     This is the whole mark being *made* in front of the user rather than
///     appearing pre-formed, which is what stops a splash reading as a static
///     image someone forgot to remove.
///  2. **The glyph.** As the lap closes, a navigation cursor scales into the
///     centre on a slight overshoot, so the mark lands with weight.
///  3. **The beat.** Once the ring is closed the dot retires and concentric
///     pulses take over the rhythm, expanding and fading on a steady cycle.
///     The screen is alive for the whole hold instead of freezing after its
///     entrance — the failure mode of most splash animations.
///
/// ## Why it is painted rather than shipped as an asset
///
/// The previous launch screen was a raster PNG with animations layered on top.
/// That meant a decode before the first meaningful frame, an aspect ratio that
/// had to be fought, and a second asset to re-cut for every density and every
/// future brand tweak. A painted mark has none of those: it is resolution-free,
/// it costs nothing to decode, it recolours itself from the token ramp, and it
/// is the same handful of vectors at 48px in a header as at 132px on launch.
///
/// ## Motion accessibility
///
/// Flutter does not consult the platform reduce-motion flag for you. When
/// [reduceMotion] is set, no controller is created at all — the mark paints
/// its completed state on the first frame and never animates. That is a real
/// code path, not a shortened duration.
class TempoSplashMark extends StatefulWidget {
  const TempoSplashMark({
    super.key,
    this.size = 132,
    this.reduceMotion = false,
    this.color,
    this.glyphColor,
  });

  /// Overall diameter of the mark, in logical pixels.
  final double size;

  /// When true the mark paints its resolved state and no ticker is started.
  final bool reduceMotion;

  /// Ring, dot and pulse colour. Defaults to the theme's action colour, which
  /// is brand blue in daylight and the brighter night blue after dark.
  final Color? color;

  /// Navigation cursor colour. Defaults to [color].
  final Color? glyphColor;

  @override
  State<TempoSplashMark> createState() => _TempoSplashMarkState();
}

class _TempoSplashMarkState extends State<TempoSplashMark>
    with TickerProviderStateMixin {
  /// Runs once: the sweep, the glyph, and the dot's retirement.
  AnimationController? _intro;

  /// Runs forever: the pulse rhythm and the ring's ambient breathing.
  AnimationController? _ambient;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _startMotion();
  }

  @override
  void didUpdateWidget(covariant TempoSplashMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The platform flag can flip while the screen is up.
    if (widget.reduceMotion && _intro != null) {
      _stopMotion();
    } else if (!widget.reduceMotion && _intro == null) {
      _startMotion();
    }
  }

  void _startMotion() {
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    // 2200ms per pulse: slow enough to read as a heartbeat rather than a
    // loading spinner, which is the line a splash animation must not cross.
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  void _stopMotion() {
    _intro?.dispose();
    _ambient?.dispose();
    _intro = null;
    _ambient = null;
  }

  @override
  void dispose() {
    _intro?.dispose();
    _ambient?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final color = widget.color ?? go.action;
    final glyphColor = widget.glyphColor ?? color;

    final intro = _intro;
    final ambient = _ambient;

    if (intro == null || ambient == null) {
      // Reduce-motion: the resolved mark, painted once.
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _MarkPainter(
          sweep: 1,
          dotAngle: 0,
          dotOpacity: 0,
          glyph: 1,
          pulseA: 0,
          pulseB: 0,
          pulseOpacity: 0,
          breathe: 0.5,
          color: color,
          glyphColor: glyphColor,
        ),
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge([intro, ambient]),
      builder: (_, __) {
        final t = intro.value;

        // The lap. easeInOutCubic gives it a push off twelve o'clock and a
        // settle at the top again, which a linear sweep does not.
        final sweep = _interval(t, 0.00, 0.62, Curves.easeInOutCubic);

        // The cursor arrives while the lap is still closing, so the two read
        // as one gesture rather than two queued animations.
        final glyph = _interval(t, 0.34, 0.78, Curves.easeOutBack);

        // The dot rides the head of the sweep, then hands the rhythm over to
        // the pulses. Fading it out avoids a discontinuity when the lap ends.
        final dotOpacity = 1.0 - _interval(t, 0.62, 0.80, Curves.easeOut);

        // Pulses only start once there is a closed ring for them to leave.
        final pulseOpacity = _interval(t, 0.58, 0.95, Curves.easeIn);
        final pulseA = ambient.value;
        final pulseB = (ambient.value + 0.5) % 1.0;

        // Ambient breathing, as a 0..1 triangle wave.
        final phase = ambient.value;
        final breathe = phase < 0.5 ? phase * 2 : (1 - phase) * 2;

        return CustomPaint(
          size: Size.square(widget.size),
          painter: _MarkPainter(
            sweep: sweep,
            dotAngle: sweep,
            dotOpacity: dotOpacity,
            glyph: glyph,
            pulseA: pulseA,
            pulseB: pulseB,
            pulseOpacity: pulseOpacity,
            breathe: breathe,
            color: color,
            glyphColor: glyphColor,
          ),
        );
      },
    );
  }

  /// Maps a global 0..1 timeline position onto a sub-interval, curved.
  static double _interval(double t, double begin, double end, Curve curve) {
    if (t <= begin) return 0;
    if (t >= end) return 1;
    return curve.transform((t - begin) / (end - begin));
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.sweep,
    required this.dotAngle,
    required this.dotOpacity,
    required this.glyph,
    required this.pulseA,
    required this.pulseB,
    required this.pulseOpacity,
    required this.breathe,
    required this.color,
    required this.glyphColor,
  });

  final double sweep;
  final double dotAngle;
  final double dotOpacity;
  final double glyph;
  final double pulseA;
  final double pulseB;
  final double pulseOpacity;
  final double breathe;
  final Color color;
  final Color glyphColor;

  static const _twoPi = math.pi * 2;
  static const _top = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final stroke = size.width * 0.055;
    // Leave room for the pulses to expand into without clipping.
    final radius = (size.width / 2) - stroke - (size.width * 0.10);

    _paintPulses(canvas, centre, radius);
    _paintRing(canvas, centre, radius, stroke);
    _paintDot(canvas, centre, radius, stroke);
    _paintGlyph(canvas, centre, size);
  }

  void _paintPulses(Canvas canvas, Offset centre, double radius) {
    if (pulseOpacity <= 0) return;
    for (final p in [pulseA, pulseB]) {
      // Expand to 1.75x and fade out; the fade is squared so the ring spends
      // most of its life faint rather than winking out at the end.
      final r = radius * (1 + p * 0.75);
      final fade = (1 - p) * (1 - p);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.035 * (1 - p) + 0.4
        ..color = color.withOpacity(0.30 * fade * pulseOpacity);
      canvas.drawCircle(centre, r, paint);
    }
  }

  void _paintRing(Canvas canvas, Offset centre, double radius, double stroke) {
    if (sweep <= 0) return;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // A soft bloom under the stroke so the ring sits in light rather than
    // being drawn on top of the background.
    final bloom = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 2.2
      ..strokeCap = StrokeCap.round
      ..color = color.withOpacity(0.10 + breathe * 0.10)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.1);
    canvas.drawArc(rect, _top, _twoPi * sweep, false, bloom);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, _top, _twoPi * sweep, false, line);
  }

  void _paintDot(Canvas canvas, Offset centre, double radius, double stroke) {
    if (dotOpacity <= 0 || sweep <= 0) return;
    final angle = _top + _twoPi * dotAngle;
    final at = Offset(
      centre.dx + math.cos(angle) * radius,
      centre.dy + math.sin(angle) * radius,
    );

    final halo = Paint()
      ..color = color.withOpacity(0.45 * dotOpacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 1.4);
    canvas.drawCircle(at, stroke * 1.25, halo);

    final core = Paint()..color = Colors.white.withOpacity(dotOpacity);
    canvas.drawCircle(at, stroke * 0.62, core);
  }

  void _paintGlyph(Canvas canvas, Offset centre, Size size) {
    if (glyph <= 0) return;
    // The navigation cursor: a triangle with a notched base, the shape every
    // map app uses for "you, heading that way".
    final h = size.width * 0.155;
    final w = size.width * 0.125;

    final path = Path()
      ..moveTo(0, -h)
      ..lineTo(w, h * 0.82)
      ..lineTo(0, h * 0.34)
      ..lineTo(-w, h * 0.82)
      ..close();

    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(glyph.clamp(0.0, 1.4));
    // A few degrees off-axis so the cursor reads as travelling rather than
    // sitting still pointing north.
    canvas.rotate(0.30);
    canvas.drawPath(
      path,
      Paint()..color = glyphColor.withOpacity(glyph.clamp(0.0, 1.0)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.sweep != sweep ||
      old.dotAngle != dotAngle ||
      old.dotOpacity != dotOpacity ||
      old.glyph != glyph ||
      old.pulseA != pulseA ||
      old.pulseB != pulseB ||
      old.pulseOpacity != pulseOpacity ||
      old.breathe != breathe ||
      old.color != color ||
      old.glyphColor != glyphColor;
}

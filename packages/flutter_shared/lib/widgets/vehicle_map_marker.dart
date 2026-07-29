import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A vehicle on the map, drawn the way riders know it from Uber and inDrive:
/// a small top-down car with a soft drop shadow, rotated to its heading.
///
/// This widget paints the car in code (a [CustomPainter]) rather than loading
/// an image asset, for three reasons:
///  * it renders at any size with no pixelation, on any density;
///  * it recolours itself from the brand tokens, so one widget serves the
///    light map, the dark map, the rider app and the captain app;
///  * no asset bundling, no decoding cost on every marker frame.
///
/// The silhouette points **up** at 0° — pass the vehicle's bearing in degrees
/// clockwise from north and the painter rotates around the car's centre.
class VehicleMapMarker extends StatelessWidget {
  const VehicleMapMarker({
    super.key,
    this.heading,
    this.color,
    this.size = 40,
    this.showShadow = true,
  });

  /// Degrees clockwise from north. Null draws the car pointing up.
  final double? heading;

  /// Car body colour. Defaults to the GoDrive green; pass a muted colour for
  /// an offline or stale vehicle.
  final Color? color;

  /// Logical square size of the whole marker (including shadow space).
  final double size;

  /// A soft elliptical ground shadow under the car, as in the Uber map.
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final body = color ?? AppTokens.primary;
    final angle = (heading ?? 0) * math.pi / 180;

    return SizedBox(
      width: size,
      height: size,
      child: Transform.rotate(
        angle: angle,
        child: CustomPaint(
          painter: _CarPainter(body: body, showShadow: showShadow),
        ),
      ),
    );
  }
}

/// Paints the top-down sedan. Everything is computed from the paint bounds so
/// the car scales cleanly from a 24px admin dot to a 56px own-vehicle marker.
class _CarPainter extends CustomPainter {
  const _CarPainter({required this.body, required this.showShadow});

  final Color body;
  final bool showShadow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Car proportions inside the square: a sedan is longer than it is wide.
    final carW = w * 0.62;
    final carH = h * 0.86;
    final left = (w - carW) / 2;
    final top = (h - carH) / 2;

    // ── Ground shadow ─────────────────────────────────────────────────
    if (showShadow) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w / 2, top + carH * 0.94),
          width: carW * 1.05,
          height: carH * 0.16,
        ),
        shadowPaint,
      );
    }

    final bodyPaint = Paint()..color = body;
    final glass = Paint()..color = _shade(Colors.white, 0.82);
    final dark = Paint()..color = const Color(0xFF23262B);
    final light = Paint()..color = const Color(0xFFFFF7D6);

    // ── Body silhouette (rounded rectangle, slightly tapered nose) ────
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, carW, carH),
      Radius.circular(carW * 0.30),
    );
    canvas.drawRRect(bodyRect, bodyPaint);

    // A subtle darker rim gives the car depth against pale streets.
    final rimPaint = Paint()
      ..color = _shade(body, 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.018;
    canvas.drawRRect(bodyRect, rimPaint);

    // ── Roof / cabin glass ────────────────────────────────────────────
    final cabinW = carW * 0.74;
    final cabinH = carH * 0.34;
    final cabin = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        w / 2 - cabinW / 2,
        top + carH * 0.30,
        cabinW,
        cabinH,
      ),
      Radius.circular(cabinW * 0.22),
    );
    canvas.drawRRect(cabin, glass);

    // Windshield band at the top of the cabin, slightly darker.
    final windshield = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        w / 2 - cabinW / 2,
        top + carH * 0.30,
        cabinW,
        cabinH * 0.34,
      ),
      Radius.circular(cabinW * 0.22),
    );
    canvas.drawRRect(windshield, Paint()..color = _shade(Colors.white, 0.70));

    // ── Headlights (two pale ovals at the nose = top of the painting) ─
    final lightW = carW * 0.20;
    final lightH = carH * 0.045;
    for (final dx in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w / 2 + dx * carW * 0.27, top + carH * 0.075),
          width: lightW,
          height: lightH,
        ),
        light,
      );
    }

    // ── Taillights (two red slits at the rear) ────────────────────────
    final tail = Paint()..color = const Color(0xFFE4572E);
    for (final dx in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w / 2 + dx * carW * 0.27, top + carH * 0.94),
          width: carW * 0.16,
          height: carH * 0.035,
        ),
        tail,
      );
    }

    // ── Wheels (four dark nubs peeking from the flanks) ───────────────
    final wheelW = w * 0.055;
    final wheelH = carH * 0.13;
    for (final (dx, dy) in [
      (-1.0, 0.24),
      (1.0, 0.24),
      (-1.0, 0.76),
      (1.0, 0.76),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(w / 2 + dx * (carW / 2 + wheelW * 0.28), top + carH * dy),
            width: wheelW,
            height: wheelH,
          ),
          Radius.circular(wheelW * 0.5),
        ),
        dark,
      );
    }
  }

  /// Lightens [c] towards white by [f] (0–1).
  Color _shade(Color c, double f) => Color.lerp(c, Colors.white, 1 - f)!;

  @override
  bool shouldRepaint(covariant _CarPainter old) =>
      old.body != body || old.showShadow != showShadow;
}

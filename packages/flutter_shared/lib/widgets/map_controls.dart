import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A round control that floats above the map.
///
/// Map chrome in the category is consistently a soft white puck with a real
/// shadow — never a flat Material FAB — so it stays legible over both pale
/// streets and dark parkland without a heavy border.
///
/// The puck takes its fill and icon from [GoTheme]. It previously branched on
/// `Theme.of(context).brightness` and reached for the legacy `dark*` scale,
/// which put a blue-leaning `#121A2B` puck on top of the neutral charcoal
/// basemap the night tiles actually render.
class MapCircleButton extends StatelessWidget {
  const MapCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 46,
    this.iconColor,
    this.background,
    this.iconSize = 22,
    this.badgeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final Color? iconColor;
  final Color? background;
  final double iconSize;

  /// When set, paints a small status dot on the corner of the puck.
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final bg = background ?? go.panel;
    final fg = iconColor ?? go.text;

    final button = Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppTokens.shadowFloating,
      ),
      child: badgeColor == null
          ? button
          : Stack(
              clipBehavior: Clip.none,
              children: [
                button,
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: bg, width: 2),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The captain's own position on the map.
///
/// A soft accuracy halo plus a solid brand puck, optionally rotated to the
/// device heading so the captain can tell at a glance which way they face.
class CaptainMapMarker extends StatelessWidget {
  const CaptainMapMarker({
    super.key,
    this.heading,
    this.online = true,
  });

  /// Degrees clockwise from north. Null when the platform has no fix.
  final double? heading;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppTokens.primary : AppTokens.lightMuted;

    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Accuracy halo
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.16),
            ),
          ),
          // Heading cone
          if (heading != null)
            Transform.rotate(
              angle: heading! * 3.1415926535 / 180,
              child: Align(
                alignment: Alignment.topCenter,
                child: CustomPaint(
                  size: const Size(20, 12),
                  painter: _HeadingConePainter(color: color),
                ),
              ),
            ),
          // Puck
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.45),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.navigation_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadingConePainter extends CustomPainter {
  const _HeadingConePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [color.withOpacity(0.55), color.withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HeadingConePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A pickup / dropoff pin. Teardrop silhouette so the two endpoints read as
/// destinations rather than as another vehicle.
class TripEndpointMarker extends StatelessWidget {
  const TripEndpointMarker({
    super.key,
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: AppTokens.shadowFloating,
          ),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
        // Stem, so the pin points at its exact coordinate.
        Container(
          width: 2.5,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

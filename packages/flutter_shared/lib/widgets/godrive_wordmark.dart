import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The GoDrive wordmark, drawn as live text rather than shipped as a bitmap.
///
/// Why not just use `assets/images/godrive_logo.png`? That asset is the *app
/// icon*: a white rounded-square tile with the wordmark inside it and
/// transparent margin around it. Dropped into a small on-screen slot it paints
/// its own white tile over whatever is behind it and shrinks the wordmark to
/// the point of illegibility — which is exactly what happened to the bottom
/// bar's centre button.
///
/// Rendering the lockup as text fixes all of that at once: it inherits the
/// surface it sits on, scales to any size without a second asset, picks up the
/// theme's contrast, and stays crisp at every density.
///
/// The two halves are one [Text.rich] on purpose — a Row of two Texts lets
/// "Go" and "Drive" drift apart under different text scale factors.
class GoDriveWordmark extends StatelessWidget {
  const GoDriveWordmark({
    super.key,
    this.fontSize = 16,
    this.goColor,
    this.driveColor,
  });

  final double fontSize;

  /// Colour of "Go". Defaults to the theme's primary text colour.
  final Color? goColor;

  /// Colour of "Drive". Defaults to brand green, lightened on dark surfaces
  /// where the AA-tuned [AppTokens.primary] reads too dim.
  final Color? driveColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final go = goColor ?? (isDark ? AppTokens.darkText : AppTokens.lightText);
    final drive =
        driveColor ?? (isDark ? AppTokens.primaryLight : AppTokens.primary);

    // Tight tracking: the lockup should read as one mark, not two words.
    final base = AppTokens.font(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.0,
      letterSpacing: -0.3,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Go', style: base.copyWith(color: go)),
          TextSpan(text: 'Drive', style: base.copyWith(color: drive)),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      // The mark is decorative; a user's text-scale preference should not be
      // able to burst it out of a fixed-size button.
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
  }
}

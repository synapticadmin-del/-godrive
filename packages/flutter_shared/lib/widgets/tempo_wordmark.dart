import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Tempo wordmark, drawn as live text rather than shipped as a bitmap.
///
/// Why not just use `assets/images/tempo_logo.png`? That asset is the *app
/// icon*: a rounded-square tile with the mark inside it and transparent margin
/// around it. Dropped into a small on-screen slot it paints its own tile over
/// whatever is behind it and shrinks the mark to the point of illegibility —
/// which is exactly what happened to the bottom bar's centre button.
///
/// Rendering the lockup as text fixes all of that at once: it inherits the
/// surface it sits on, scales to any size without a second asset, picks up the
/// theme's contrast, and stays crisp at every density.
///
/// ## Why the trailing "o" carries the accent
///
/// This replaced a two-tone `GoDrive` lockup, where the split fell naturally
/// between two words. "Tempo" is one word, so there is no seam to colour along
/// — and a single-colour wordmark loses the focal point the old mark had.
///
/// The split lands on the final "o" instead. It is the only round counter in
/// the word, so tinting it reads as a deliberate mark rather than a letter
/// that got the wrong colour; and against a name that means *pace*, a single
/// accented beat at the end of the word is the idea the brand is already
/// making. It also keeps the lockup's two-tone DNA, so the mark still reads as
/// a logo at 13px on the wallet card, where a flat word would just look like
/// body copy that wandered in.
///
/// The two spans are one [Text.rich] on purpose — a Row of two Texts lets
/// "Temp" and "o" drift apart under different text scale factors.
class TempoWordmark extends StatelessWidget {
  const TempoWordmark({
    super.key,
    this.fontSize = 16,
    this.textColor,
    this.accentColor,
  });

  final double fontSize;

  /// Colour of "Temp". Defaults to the theme's primary text colour.
  final Color? textColor;

  /// Colour of the trailing "o". Defaults to brand blue, lightened on dark
  /// surfaces where the AA-tuned [AppTokens.primary] reads too dim.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final body = textColor ?? (isDark ? AppTokens.darkText : AppTokens.lightText);
    final accent =
        accentColor ?? (isDark ? AppTokens.primaryLight : AppTokens.primary);

    // Tight tracking: the lockup should read as one mark, not a word.
    final base = AppTokens.font(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      height: 1.0,
      letterSpacing: -0.3,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Temp', style: base.copyWith(color: body)),
          TextSpan(text: 'o', style: base.copyWith(color: accent)),
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

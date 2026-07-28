import 'package:flutter/widgets.dart';

/// Centralised, type-safe UI copy for the GoDrive apps.
///
/// ## Why this exists instead of (for now) gen-l10n
///
/// The apps carry most of their Arabic copy as inline string literals with
/// `isAr ? '…' : '…'` ternaries scattered through the screens. That works,
/// but it means every label lives in exactly one screen, can never be reused,
/// and drifts the moment two screens phrase the same idea differently.
///
/// The long-term home for copy is the ARB + `gen-l10n` pipeline (the
/// scaffolding already exists under `lib/l10n/`). Moving 400+ literals onto
/// it in one pass without a Flutter SDK to regenerate and analyse is unsafe,
/// so this class is the **incremental, compile-safe bridge**:
///
///  * one place to read and review copy for both languages;
///  * resolved from the ambient locale, so screens drop their `isAr` ternaries;
///  * identical call-site shape to what `AppLocalizations.of(context)` will
///    later provide, so swapping the implementation underneath the call sites
///    is a one-file change.
///
/// ## Usage
///
/// ```dart
/// final strings = AppStrings.of(context);
/// Text(strings.netEarnings);
/// Text(strings.tripsLast7Days(12));
/// ```
///
/// ## Adding copy
///
/// Add the getter to [AppStrings], then implement it in BOTH [AppStringsAr]
/// and [AppStringsEn] — the compiler refuses to build until both languages
/// exist, so a missing translation is impossible to ship. Strings with
/// dynamic values are methods with named placeholders, never string
/// concatenation, so translators see the full sentence in one place.
///
/// When a screen is migrated, delete its inline literals and ternaries and
/// read from here. `earnings_screen.dart` in the Captain app is the reference
/// migration — copy its pattern.
abstract class AppStrings {
  const AppStrings._();

  /// Resolves the copy bundle for the ambient locale. Falls back to Arabic —
  /// the app's primary market — when the locale is neither Arabic nor English
  /// so a screen never renders an empty label mid-trip.
  static AppStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'en' ? const AppStringsEn() : const AppStringsAr();
  }

  // ──────────────────────────────────────────────────────────────────
  // Common — shared across screens and apps
  // ──────────────────────────────────────────────────────────────────

  /// Currency suffix shown after money amounts (Egyptian pound).
  String get egp;

  /// Generic pull-to-refresh / retry tooltip.
  String get refresh;

  /// Fallback error headline when a load fails with no specific message.
  String get genericLoadError;

  // ──────────────────────────────────────────────────────────────────
  // Captain — Earnings screen (reference migration)
  // ──────────────────────────────────────────────────────────────────

  /// App-bar title of the earnings summary.
  String get earningsTitle;

  /// Error body when the earnings payload fails to load.
  String get earningsLoadError;

  /// Label above the hero net figure.
  String get netEarnings;

  /// "N trips • last 7 days" chip under the hero figure.
  String tripsLast7Days(int count);

  /// Gross-income breakdown row label.
  String get grossIncome;

  /// Platform-commission breakdown row label.
  String get platformCommission;

  /// Net payout breakdown row label ("your share").
  String get netForYou;

  /// Button that navigates to the wallet / payout screen.
  String get walletAndWithdraw;
}

/// Egyptian-Arabic copy — the app's primary language.
class AppStringsAr extends AppStrings {
  const AppStringsAr();

  @override
  String get egp => 'ج.م';

  @override
  String get refresh => 'تحديث';

  @override
  String get genericLoadError => 'حدث خطأ، حاول مرة أخرى';

  @override
  String get earningsTitle => 'الأرباح';

  @override
  String get earningsLoadError => 'خطأ في تحميل بيانات الأرباح';

  @override
  String get netEarnings => 'صافي الأرباح';

  @override
  String tripsLast7Days(int count) => '$count رحلة • آخر ٧ أيام';

  @override
  String get grossIncome => 'إجمالي الدخل';

  @override
  String get platformCommission => 'عمولة المنصة';

  @override
  String get netForYou => 'الصافي لك';

  @override
  String get walletAndWithdraw => 'المحفظة والسحب';
}

/// English copy.
class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  String get egp => 'EGP';

  @override
  String get refresh => 'Refresh';

  @override
  String get genericLoadError => 'Something went wrong, try again';

  @override
  String get earningsTitle => 'Earnings';

  @override
  String get earningsLoadError => 'Could not load earnings data';

  @override
  String get netEarnings => 'Net earnings';

  @override
  String tripsLast7Days(int count) =>
      '$count ${count == 1 ? 'trip' : 'trips'} • last 7 days';

  @override
  String get grossIncome => 'Gross income';

  @override
  String get platformCommission => 'Platform commission';

  @override
  String get netForYou => 'Your net';

  @override
  String get walletAndWithdraw => 'Wallet & payout';
}

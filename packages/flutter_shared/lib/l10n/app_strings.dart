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
/// Text(strings.statusLabel('completed'));
/// Text(strings.acceptWithFare(85));
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
/// read from here. `earnings_screen.dart`, `settings_screen.dart`,
/// `trips_tab.dart` and `offer_card.dart` in the Captain app are the
/// reference migrations — copy their pattern.
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

  /// Generic cancel action in dialogs and sheets.
  String get cancelAction;

  /// Localised label for a trip status key coming from the API
  /// (searching / offered / assigned / arrived / in_progress / completed /
  /// cancelled). Centralised so every screen that renders a trip status —
  /// history, home, active panel — speaks one vocabulary.
  String statusLabel(String status);

  // ──────────────────────────────────────────────────────────────────
  // Captain — Offer card (the highest-stakes card in the product)
  // ──────────────────────────────────────────────────────────────────

  /// Header label when the countdown expired before the captain acted.
  String get offerExpired;

  /// Header label when the fare shown is the rider's own proposal.
  String get riderOfferedPrice;

  /// Header label when the fare shown is a system estimate (no rider bid).
  String get estimatedPrice;

  /// Meta chip: distance from the captain to the pickup point.
  String pickupDistanceKm(String km);

  /// Meta chip: total trip distance.
  String tripDistanceKm(String km);

  /// Meta chip: estimated trip duration in minutes.
  String aboutMinutes(int min);

  /// Fallback when an offer has no pickup address.
  String get pickupPoint;

  /// Fallback when an offer has no dropoff address.
  String get destinationPoint;

  /// Primary button — accept the trip at the shown fare.
  String acceptWithFare(String fare);

  /// Secondary button — open the counter-offer price picker.
  String get counterOffer;

  /// Quiet button — dismiss the offer without acting.
  String get skipLabel;

  /// Toast shown after a counter-offer is posted to the server.
  String bidSentToast(String amount);

  /// In-card banner after a bid is sent — the trip stays open for the rider.
  String bidSentBanner(String amount);

  /// After a bid is sent, the fallback action that accepts the original fare.
  String acceptInsteadWithFare(String fare);

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

  // ──────────────────────────────────────────────────────────────────
  // Captain — Trips history tab
  // ──────────────────────────────────────────────────────────────────

  /// Header title of the trips history tab.
  String get tripsTabTitle;

  /// "N trips recorded" summary under the header.
  String tripsRecorded(int count);

  /// Empty-state title when the captain has no trips yet.
  String get noTripsYet;

  /// Empty-state subtitle under [noTripsYet].
  String get noTripsYetSubtitle;

  /// Fallback when a trip has no pickup address.
  String get unknownPickup;

  /// Fallback when a trip has no dropoff address.
  String get unknownDropoff;

  /// Route origin label ("from").
  String get fromLabel;

  /// Route destination label ("to").
  String get toLabel;

  // ──────────────────────────────────────────────────────────────────
  // Captain — Settings / profile screen
  // ──────────────────────────────────────────────────────────────────

  /// Fallback display name when the captain's name has not loaded yet.
  String get captainFallbackName;

  /// Online status chip (captain is accepting offers).
  String get online;

  /// Offline status chip (captain is not accepting offers).
  String get offline;

  /// Status shown while the account awaits admin approval.
  String get pendingApproval;

  /// Stat card label for the captain's average rating.
  String get ratingLabel;

  /// Stat card label for the captain's trip count.
  String get tripsLabel;

  /// Stat card label for the approval state.
  String get statusLabelKey;

  /// Stat card value when the account is approved.
  String get approvedValue;

  /// Stat card value when the account is under review.
  String get underReviewValue;

  /// Section heading for the vehicle information card.
  String get vehicleInfoTitle;

  /// Row label for the vehicle make/model.
  String get vehicleLabel;

  /// Row label for the vehicle licence plate.
  String get plateLabel;

  /// Section heading for the documents card.
  String get documentsTitle;

  /// Navigation row that opens the document upload flow.
  String get uploadDocuments;

  /// Subtitle listing the required documents (licence, ID, background check).
  String get uploadDocumentsSubtitle;

  /// Section heading for the safety card.
  String get safetyTitle;

  /// Navigation row that opens the SOS emergency screen.
  String get sosButton;

  /// Subtitle explaining what the SOS button does.
  String get sosSubtitle;

  /// Section heading for appearance and language settings.
  String get appearanceTitle;

  /// Toggle label for dark mode.
  String get darkMode;

  /// Row label for the language picker.
  String get languageLabel;

  /// Arabic language name as shown in the picker.
  String get arabicLanguage;

  /// English language name as shown in the picker.
  String get englishLanguage;

  /// Section heading for the about card.
  String get aboutTitle;

  /// Row label for app version info.
  String get aboutApp;

  /// Row label for the privacy policy link.
  String get privacyPolicy;

  /// Logout button label (also used as the confirmation dialog title).
  String get logout;

  /// Logout confirmation dialog body.
  String get logoutConfirmMessage;

  /// Destructive confirm action in the logout dialog.
  String get exitAction;
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
  String get cancelAction => 'إلغاء';

  @override
  String statusLabel(String status) {
    switch (status) {
      case 'searching':
        return 'بحث';
      case 'offered':
        return 'عرض';
      case 'assigned':
        return 'مُعيّن';
      case 'arrived':
        return 'وصل';
      case 'in_progress':
        return 'جارية';
      case 'completed':
        return 'مكتملة';
      case 'cancelled':
        return 'ملغية';
      default:
        return status;
    }
  }

  // ── Offer card ────────────────────────────────────────────────────

  @override
  String get offerExpired => 'انتهت مهلة العرض';

  @override
  String get riderOfferedPrice => 'سعر العميل المقترح';

  @override
  String get estimatedPrice => 'السعر التقديري';

  @override
  String pickupDistanceKm(String km) => 'الوصول $km كم';

  @override
  String tripDistanceKm(String km) => 'الرحلة $km كم';

  @override
  String aboutMinutes(int min) => '~$min دقيقة';

  @override
  String get pickupPoint => 'نقطة الالتقاط';

  @override
  String get destinationPoint => 'الوجهة';

  @override
  String acceptWithFare(String fare) => 'قبول بـ $fare ج.م';

  @override
  String get counterOffer => 'سعر معدّل';

  @override
  String get skipLabel => 'تخطي';

  @override
  String bidSentToast(String amount) =>
      'تم إرسال عرضك بمبلغ $amount ج.م — بانتظار رد العميل';

  @override
  String bidSentBanner(String amount) =>
      'أرسلت عرضًا بمبلغ $amount ج.م — بانتظار رد العميل';

  @override
  String acceptInsteadWithFare(String fare) => 'قبول بـ $fare ج.م بدلاً منه';

  // ── Earnings ──────────────────────────────────────────────────────

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

  // ── Trips ─────────────────────────────────────────────────────────

  @override
  String get tripsTabTitle => 'رحلاتي';

  @override
  String tripsRecorded(int count) =>
      '$count ${count == 1 ? 'رحلة' : 'رحلات'} مسجّلة';

  @override
  String get noTripsYet => 'لا توجد رحلات بعد';

  @override
  String get noTripsYetSubtitle => 'ستظهر رحلاتك المكتملة هنا';

  @override
  String get unknownPickup => 'موقف غير محدد';

  @override
  String get unknownDropoff => 'وجهة غير محددة';

  @override
  String get fromLabel => 'من';

  @override
  String get toLabel => 'إلى';

  // ── Settings ──────────────────────────────────────────────────────

  @override
  String get captainFallbackName => 'كابتن';

  @override
  String get online => 'متصل';

  @override
  String get offline => 'غير متصل';

  @override
  String get pendingApproval => 'بانتظار الموافقة';

  @override
  String get ratingLabel => 'التقييم';

  @override
  String get tripsLabel => 'رحلات';

  @override
  String get statusLabelKey => 'الحالة';

  @override
  String get approvedValue => 'معتمد';

  @override
  String get underReviewValue => 'مراجعة';

  @override
  String get vehicleInfoTitle => 'معلومات المركبة';

  @override
  String get vehicleLabel => 'المركبة';

  @override
  String get plateLabel => 'اللوحة';

  @override
  String get documentsTitle => 'المستندات';

  @override
  String get uploadDocuments => 'رفع المستندات';

  @override
  String get uploadDocumentsSubtitle => 'رخصة + بطاقة + فيش';

  @override
  String get safetyTitle => 'الأمان';

  @override
  String get sosButton => 'زر الطوارئ SOS';

  @override
  String get sosSubtitle => 'تنبيه فوري للدعم';

  @override
  String get appearanceTitle => 'المظهر واللغة';

  @override
  String get darkMode => 'الوضع الداكن';

  @override
  String get languageLabel => 'اللغة';

  @override
  String get arabicLanguage => 'العربية';

  @override
  String get englishLanguage => 'English';

  @override
  String get aboutTitle => 'معلومات';

  @override
  String get aboutApp => 'عن التطبيق';

  @override
  String get privacyPolicy => 'سياسة الخصوصية';

  @override
  String get logout => 'تسجيل الخروج';

  @override
  String get logoutConfirmMessage => 'هل أنت متأكد أنك تريد تسجيل الخروج؟';

  @override
  String get exitAction => 'خروج';
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
  String get cancelAction => 'Cancel';

  @override
  String statusLabel(String status) {
    switch (status) {
      case 'searching':
        return 'Searching';
      case 'offered':
        return 'Offered';
      case 'assigned':
        return 'Assigned';
      case 'arrived':
        return 'Arrived';
      case 'in_progress':
        return 'In progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  // ── Offer card ────────────────────────────────────────────────────

  @override
  String get offerExpired => 'Offer expired';

  @override
  String get riderOfferedPrice => "Rider's offer";

  @override
  String get estimatedPrice => 'Estimated price';

  @override
  String pickupDistanceKm(String km) => 'Pickup $km km';

  @override
  String tripDistanceKm(String km) => 'Trip $km km';

  @override
  String aboutMinutes(int min) => '~$min min';

  @override
  String get pickupPoint => 'Pickup point';

  @override
  String get destinationPoint => 'Destination';

  @override
  String acceptWithFare(String fare) => 'Accept $fare EGP';

  @override
  String get counterOffer => 'Counter';

  @override
  String get skipLabel => 'Skip';

  @override
  String bidSentToast(String amount) =>
      'Bid of $amount EGP sent — waiting for the rider';

  @override
  String bidSentBanner(String amount) =>
      'You bid $amount EGP — waiting for the rider';

  @override
  String acceptInsteadWithFare(String fare) => 'Accept $fare EGP instead';

  // ── Earnings ──────────────────────────────────────────────────────

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

  // ── Trips ─────────────────────────────────────────────────────────

  @override
  String get tripsTabTitle => 'My trips';

  @override
  String tripsRecorded(int count) =>
      '$count ${count == 1 ? 'trip' : 'trips'} recorded';

  @override
  String get noTripsYet => 'No trips yet';

  @override
  String get noTripsYetSubtitle => 'Your completed trips will appear here';

  @override
  String get unknownPickup => 'Unknown pickup';

  @override
  String get unknownDropoff => 'Unknown destination';

  @override
  String get fromLabel => 'From';

  @override
  String get toLabel => 'To';

  // ── Settings ──────────────────────────────────────────────────────

  @override
  String get captainFallbackName => 'Captain';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get pendingApproval => 'Pending approval';

  @override
  String get ratingLabel => 'Rating';

  @override
  String get tripsLabel => 'Trips';

  @override
  String get statusLabelKey => 'Status';

  @override
  String get approvedValue => 'Approved';

  @override
  String get underReviewValue => 'In review';

  @override
  String get vehicleInfoTitle => 'Vehicle information';

  @override
  String get vehicleLabel => 'Vehicle';

  @override
  String get plateLabel => 'Plate';

  @override
  String get documentsTitle => 'Documents';

  @override
  String get uploadDocuments => 'Upload documents';

  @override
  String get uploadDocumentsSubtitle => 'Licence + ID + background check';

  @override
  String get safetyTitle => 'Safety';

  @override
  String get sosButton => 'SOS emergency button';

  @override
  String get sosSubtitle => 'Instant alert to support';

  @override
  String get appearanceTitle => 'Appearance & language';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get languageLabel => 'Language';

  @override
  String get arabicLanguage => 'العربية';

  @override
  String get englishLanguage => 'English';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutApp => 'About the app';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get logout => 'Log out';

  @override
  String get logoutConfirmMessage =>
      'Are you sure you want to log out?';

  @override
  String get exitAction => 'Log out';
}

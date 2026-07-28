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
/// read from here. Every Captain screen is now a reference migration —
/// `earnings_screen`, `settings_screen`, `trips_tab`, `offer_card`,
/// `home_tab`, `active_trip_panel`, `wallet_screen`, `document_upload_screen`,
/// `document_status_screen`, and `trip_chat_screen`. Copy their pattern.
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
  // Captain — Home tab (status header + offers sheet)
  // ──────────────────────────────────────────────────────────────────

  /// Status header state label when the account awaits approval.
  String get homeAwaitingApproval;

  /// Status header state label when online and ready for trips.
  String get homeOnlineReady;

  /// Status header state label when offline.
  String get homeOffline;

  /// Tooltip when the live socket is connected.
  String get homeSocketLive;

  /// Tooltip when the live socket is reconnecting.
  String get homeSocketReconnecting;

  /// Idle-sheet title while searching for nearby trips.
  String get homeSearchingTitle;

  /// Idle-sheet subtitle advising the captain to stay in a busy area.
  String get homeSearchingSubtitle;

  /// Idle-sheet title when approved but offline.
  String get homeOfflineTitle;

  /// Idle-sheet title when the account is still under review.
  String get homeUnderReviewTitle;

  /// Idle-sheet subtitle prompting the captain to go online.
  String get homeGoOnlineHint;

  /// Idle-sheet subtitle promising a notification on approval.
  String get homeApprovalHint;

  // ──────────────────────────────────────────────────────────────────
  // Captain — Active trip panel (in-trip control)
  // ──────────────────────────────────────────────────────────────────

  /// Heading while en route to the rider.
  String get tripHeadingToRider;

  /// Heading while waiting for the rider at pickup.
  String get tripWaitingForRider;

  /// Heading while the trip is underway.
  String get tripInProgress;

  /// Fallback heading for an active trip in an unknown stage.
  String get tripActiveFallback;

  /// Fallback rider display name when none has loaded.
  String get riderFallbackName;

  /// Fare label when the trip's final fare is settled.
  String get finalFareLabel;

  /// Fare label when only the estimate is available.
  String get estimatedFareLabel;

  /// Tooltip / label for the in-app rider chat button.
  String get riderChatLabel;

  /// Toast when the device cannot open a dialler for the call button.
  String get callOpenError;

  /// Navigation button while heading to the pickup point.
  String get navToRider;

  /// Navigation button while heading to the destination.
  String get navToDestination;

  /// Primary action in the assigned stage (mark arrival).
  String get arrivedAtPickupAction;

  /// Primary action in the arrived stage (start the trip).
  String get startTripAction;

  /// Primary action in the in-progress stage (complete the trip).
  String get endTripAction;

  /// Disabled action label while the trip state is refreshing.
  String get tripUpdatingAction;

  /// Stepper label: en route stage.
  String get stageEnRoute;

  /// Stepper label: arrived stage.
  String get stageArrived;

  /// Stepper label: underway stage.
  String get stageUnderway;

  /// Stepper label: done stage.
  String get stageDone;

  /// Complete-trip confirmation dialog title.
  String get endTripConfirmTitle;

  /// Complete-trip confirmation dialog body question.
  String get endTripConfirmQuestion;

  /// Fare line inside the complete-trip confirmation dialog.
  String tripFareLine(String fare);

  /// Confirm action in the complete-trip dialog.
  String get endTripConfirmYes;

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
  // Captain — Wallet / payout screen
  // ──────────────────────────────────────────────────────────────────

  /// App-bar title of the wallet screen.
  String get walletTitle;

  /// Error body when the wallet payload fails to load.
  String get walletLoadError;

  /// Toast when payout is requested with no withdrawable balance.
  String get noBalanceToWithdraw;

  /// Payout sheet title.
  String get payoutSheetTitle;

  /// Available-balance line in the payout sheet.
  String availableBalanceLine(String balance);

  /// Payout method: Vodafone Cash mobile wallet.
  String get vodafoneCashMethod;

  /// Payout method: InstaPay bank transfer.
  String get instaPayMethod;

  /// Account-field hint for the Vodafone Cash wallet number.
  String get vodafoneCashHint;

  /// Account-field hint for the InstaPay payment address / account.
  String get instaPayHint;

  /// Payout account dialog title ("Withdraw via {method}").
  String payoutViaTitle(String method);

  /// Payout account dialog body ("{amount} will be withdrawn").
  String payoutAmountLine(String amount);

  /// Confirm action in the payout account dialog.
  String get confirmPayoutAction;

  /// Toast when the entered account info fails validation.
  String get invalidAccountError;

  /// Toast after a payout request is submitted successfully.
  String payoutSuccessToast(String method);

  /// Toast when a payout request fails.
  String payoutFailedToast(String error);

  /// Balance hero label above the big number.
  String get availableBalanceHero;

  /// Payout-window line under the balance hero.
  String payoutWindowLine(String window);

  /// Weekly-trips chip inside the balance hero.
  String weekTripsChip(int count);

  /// Weekly-commission chip inside the balance hero.
  String weekCommissionChip(String amount);

  /// Primary "withdraw now" button on the balance hero.
  String get withdrawNowAction;

  /// Transaction history section title.
  String get transactionHistoryTitle;

  /// Empty-state title when the wallet has no transactions yet.
  String get noTransactionsYet;

  /// Fallback note for a credit transaction with no note.
  String get creditNoteFallback;

  /// Fallback note for a debit transaction with no note.
  String get debitNoteFallback;

  /// Pending marker appended to a transaction date.
  String get pendingMarker;

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
  // Captain — Documents (upload checklist + status view)
  // ──────────────────────────────────────────────────────────────────

  /// App-bar title of the document upload checklist.
  String get documentsRequiredTitle;

  /// Tooltip opening the read-through document status view.
  String get documentsStatusTooltip;

  /// Tooltip refreshing the account approval state.
  String get refreshAccountTooltip;

  /// Document type: driving licence.
  String get docTypeLicense;

  /// Document type: national ID card.
  String get docTypeNationalId;

  /// Document type: vehicle registration.
  String get docTypeVehicleReg;

  /// Document type: criminal record check.
  String get docTypeCriminalRecord;

  /// Document status badge: approved.
  String get docStatusApproved;

  /// Document status badge: under review.
  String get docStatusPending;

  /// Document status badge: rejected, needs re-upload (upload screen).
  String get docStatusRejectedReupload;

  /// Document status badge: rejected (status screen).
  String get docStatusRejected;

  /// Document status badge: not uploaded yet (upload screen).
  String get docStatusNotUploaded;

  /// Document status badge: not uploaded (status screen).
  String get docStatusMissing;

  /// Badge text while an upload is in flight.
  String get docUploading;

  /// Upload action on a missing document.
  String get docUploadAction;

  /// Re-upload action on a rejected document.
  String get docReuploadAction;

  /// Image-source sheet: take a photo with the camera.
  String get sourceCamera;

  /// Image-source sheet: pick from the gallery.
  String get sourceGallery;

  /// Toast after a document uploads successfully.
  String docUploadedToast(String title);

  /// Toast when the file upload step fails.
  String get docUploadFailed;

  /// Error when the upload response carries no file key.
  String get docUploadInvalidResponse;

  /// Generic error prefix for document actions.
  String docErrorPrefix(String error);

  /// Header title when some documents still need uploading.
  String get docHeaderIncomplete;

  /// Header title when every document is uploaded and under review.
  String get docHeaderAllUploaded;

  /// Header subtitle while documents are incomplete.
  String get docHeaderIncompleteSubtitle;

  /// Header subtitle once all documents are under review.
  String get docHeaderAllUploadedSubtitle;

  /// Progress line: approved count out of total.
  String docProgressLine(int approved, int total);

  /// Progress line when all documents are uploaded.
  String get docProgressAllUploaded;

  /// Onboarding step: upload documents.
  String get docStepUpload;

  /// Onboarding step: team review (up to 24h).
  String get docStepReview;

  /// Onboarding step: start accepting trips.
  String get docStepStartTrips;

  /// Rejection alert title — singular (upload screen).
  String get docRejectedAlertTitleSingle;

  /// Rejection alert title — plural (upload screen).
  String get docRejectedAlertTitlePlural;

  /// Rejection alert body instruction (upload screen).
  String get docRejectedAlertBody;

  /// Rejection alert title — singular (status screen).
  String get docRejectedTitleSingle;

  /// Rejection alert title with count (status screen).
  String docRejectedTitleCount(int count);

  /// Fallback when the admin gave no specific rejection reason.
  String get docNoReasonFallback;

  /// Account banner: approved title.
  String get accountApprovedTitle;

  /// Account banner: approved subtitle.
  String get accountApprovedSubtitle;

  /// Account banner: rejected title.
  String get accountRejectedTitle;

  /// Account banner: rejected subtitle.
  String get accountRejectedSubtitle;

  /// Account banner: under-review title.
  String get accountUnderReviewTitle;

  /// Account banner: under-review subtitle.
  String get accountUnderReviewSubtitle;

  // ──────────────────────────────────────────────────────────────────
  // Captain — In-trip chat
  // ──────────────────────────────────────────────────────────────────

  /// App-bar title of the in-trip chat screen.
  String get chatTitle;

  /// Empty-state body when the thread has no messages yet.
  String get chatEmptyBody;

  /// Composer hint text.
  String get chatComposerHint;

  /// Typing-indicator bubble label.
  String get chatTyping;

  // ──────────────────────────────────────────────────────────────────
  // Rider — Trip screen (searching → offered → assigned → in_progress → done)
  // ──────────────────────────────────────────────────────────────────

  /// Error body when the trip payload fails to load.
  String get tripLoadError;

  /// Fallback captain display name when none has loaded.
  String get riderCaptainFallback;

  /// Panel title while searching for a captain.
  String get tripSearchingTitle;

  /// Panel subtitle while searching.
  String get tripSearchingSubtitle;

  /// Button that cancels the trip request.
  String get tripCancelAction;

  /// Panel title when captain offers have arrived.
  String get tripOffersArrivedTitle;

  /// Panel subtitle telling the rider to pick an offer.
  String get tripOffersArrivedSubtitle;

  /// Button that reopens the captain offers sheet.
  String get tripViewOffersAction;

  /// Panel title when the captain is en route to the rider.
  String get tripCaptainEnRoute;

  /// Panel title when the captain has arrived at pickup.
  String get tripCaptainArrived;

  /// Panel title while the trip is underway.
  String get tripUnderway;

  /// Panel title when the trip completed successfully.
  String get tripCompletedTitle;

  /// Panel title when the trip was cancelled.
  String get tripCancelledTitle;

  /// Dismiss button on the cancelled panel.
  String get tripDoneButton;

  /// Button that opens the rating sheet.
  String get tripRateAction;

  /// Button that opens the in-trip chat (single).
  String get tripMessageAction;

  /// Button that opens the in-trip chat (addressed to captain).
  String get tripMessageCaptainAction;

  /// "Fare" row label on the assigned/in-progress panels.
  String get tripFareRowLabel;

  /// "Final fare" label on the completed panel.
  String get tripFinalFareLabel;

  /// Status badge: searching.
  String get tripBadgeSearching;

  /// Status badge: offers available.
  String get tripBadgeOffered;

  /// Status badge: captain en route.
  String get tripBadgeAssigned;

  /// Status badge: captain arrived.
  String get tripBadgeArrived;

  /// Status badge: trip underway.
  String get tripBadgeInProgress;

  /// Status badge: arrived / completed.
  String get tripBadgeCompleted;

  /// Status badge: cancelled.
  String get tripBadgeCancelled;

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

  // ── Home tab ──────────────────────────────────────────────────────

  @override
  String get homeAwaitingApproval => 'بانتظار الموافقة';

  @override
  String get homeOnlineReady => 'متصل ومستعد للرحلات';

  @override
  String get homeOffline => 'غير متصل';

  @override
  String get homeSocketLive => 'الاتصال المباشر يعمل';

  @override
  String get homeSocketReconnecting => 'إعادة الاتصال…';

  @override
  String get homeSearchingTitle => 'جاري البحث عن رحلات قريبة…';

  @override
  String get homeSearchingSubtitle => 'ابقَ في منطقة مزدحمة لزيادة فرص الطلبات';

  @override
  String get homeOfflineTitle => 'أنت غير متصل حالياً';

  @override
  String get homeUnderReviewTitle => 'حسابك قيد المراجعة';

  @override
  String get homeGoOnlineHint => 'اضغط لبدء استقبال الرحلات والأرباح';

  @override
  String get homeApprovalHint => 'سنخطرك فور اعتماد مستنداتك';

  // ── Active trip panel ─────────────────────────────────────────────

  @override
  String get tripHeadingToRider => 'في الطريق إلى الراكب';

  @override
  String get tripWaitingForRider => 'في انتظار الراكب';

  @override
  String get tripInProgress => 'الرحلة جارية';

  @override
  String get tripActiveFallback => 'رحلة نشطة';

  @override
  String get riderFallbackName => 'راكب';

  @override
  String get finalFareLabel => 'الأجرة النهائية';

  @override
  String get estimatedFareLabel => 'الأجرة المقدرة';

  @override
  String get riderChatLabel => 'محادثة الراكب';

  @override
  String get callOpenError => 'تعذّر فتح تطبيق الاتصال';

  @override
  String get navToRider => 'تنقّل إلى الراكب';

  @override
  String get navToDestination => 'تنقّل إلى الوجهة';

  @override
  String get arrivedAtPickupAction => 'وصلت لنقطة الالتقاط';

  @override
  String get startTripAction => 'بدء الرحلة';

  @override
  String get endTripAction => 'إنهاء الرحلة';

  @override
  String get tripUpdatingAction => 'جارٍ التحديث…';

  @override
  String get stageEnRoute => 'في الطريق';

  @override
  String get stageArrived => 'وصلت';

  @override
  String get stageUnderway => 'جارية';

  @override
  String get stageDone => 'اكتملت';

  @override
  String get endTripConfirmTitle => 'تأكيد إنهاء الرحلة';

  @override
  String get endTripConfirmQuestion => 'هل وصلت بالفعل إلى نقطة الوصول؟';

  @override
  String tripFareLine(String fare) => 'الأجرة: $fare ج.م';

  @override
  String get endTripConfirmYes => 'نعم، إنهاء';

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

  // ── Wallet ────────────────────────────────────────────────────────

  @override
  String get walletTitle => 'المحفظة';

  @override
  String get walletLoadError => 'خطأ في تحميل المحفظة';

  @override
  String get noBalanceToWithdraw => 'لا يوجد رصيد كافٍ للسحب';

  @override
  String get payoutSheetTitle => 'طلب سحب الأرباح';

  @override
  String availableBalanceLine(String balance) => 'الرصيد المتاح: $balance ج.م';

  @override
  String get vodafoneCashMethod => 'فودافون كاش';

  @override
  String get instaPayMethod => 'انستا باي (InstaPay)';

  @override
  String get vodafoneCashHint => 'رقم محفظة فودافون كاش';

  @override
  String get instaPayHint => 'عنوان الدفع (IPA) أو رقم الحساب';

  @override
  String payoutViaTitle(String method) => 'السحب عبر $method';

  @override
  String payoutAmountLine(String amount) => 'سيتم سحب $amount ج.م';

  @override
  String get confirmPayoutAction => 'تأكيد السحب';

  @override
  String get invalidAccountError => 'برجاء إدخال بيانات حساب صحيحة';

  @override
  String payoutSuccessToast(String method) =>
      'تم إرسال طلب السحب بنجاح إلى $method';

  @override
  String payoutFailedToast(String error) => 'فشل طلب السحب: $error';

  @override
  String get availableBalanceHero => 'الرصيد المتاح للسحب';

  @override
  String payoutWindowLine(String window) => 'موعد الصرف: $window';

  @override
  String weekTripsChip(int count) => 'رحلات هذا الأسبوع: $count';

  @override
  String weekCommissionChip(String amount) => 'عمولة: $amount ج.م';

  @override
  String get withdrawNowAction => 'سحب الآن';

  @override
  String get transactionHistoryTitle => 'سجل المعاملات';

  @override
  String get noTransactionsYet => 'لا توجد معاملات سابقة بالمحفظة حتى الآن';

  @override
  String get creditNoteFallback => 'إضافة رصيد';

  @override
  String get debitNoteFallback => 'خصم معاملة';

  @override
  String get pendingMarker => 'قيد التنفيذ';

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

  // ── Documents ─────────────────────────────────────────────────────

  @override
  String get documentsRequiredTitle => 'المستندات المطلوبة';

  @override
  String get documentsStatusTooltip => 'حالة المستندات';

  @override
  String get refreshAccountTooltip => 'تحديث حالة الحساب';

  @override
  String get docTypeLicense => 'رخصة القيادة';

  @override
  String get docTypeNationalId => 'البطاقة الشخصية';

  @override
  String get docTypeVehicleReg => 'رخصة السيارة';

  @override
  String get docTypeCriminalRecord => 'فيش جنائي';

  @override
  String get docStatusApproved => 'مقبول';

  @override
  String get docStatusPending => 'قيد المراجعة';

  @override
  String get docStatusRejectedReupload => 'مرفوض — أعد الرفع';

  @override
  String get docStatusRejected => 'مرفوض';

  @override
  String get docStatusNotUploaded => 'لم يتم الرفع بعد';

  @override
  String get docStatusMissing => 'لم يتم الرفع';

  @override
  String get docUploading => 'جاري الرفع...';

  @override
  String get docUploadAction => 'رفع';

  @override
  String get docReuploadAction => 'إعادة الرفع';

  @override
  String get sourceCamera => 'التقاط صورة';

  @override
  String get sourceGallery => 'اختيار من المعرض';

  @override
  String docUploadedToast(String title) => 'تم رفع $title بنجاح — قيد المراجعة';

  @override
  String get docUploadFailed => 'فشل رفع الملف';

  @override
  String get docUploadInvalidResponse => 'استجابة الرفع غير صالحة';

  @override
  String docErrorPrefix(String error) => 'خطأ: $error';

  @override
  String get docHeaderIncomplete => 'أكمل ملفك المهني';

  @override
  String get docHeaderAllUploaded => 'مستنداتك قيد المراجعة';

  @override
  String get docHeaderIncompleteSubtitle =>
      'ارفع مستنداتك ليتمكن فريقنا من مراجعة حسابك والموافقة عليه.';

  @override
  String get docHeaderAllUploadedSubtitle =>
      'سيتواصل معك فريقنا خلال 24 ساعة عند إقرار الحساب.';

  @override
  String docProgressLine(int approved, int total) =>
      'تمت الموافقة على $approved من أصل $total مستندات';

  @override
  String get docProgressAllUploaded => 'جميع المستندات مرفوعة';

  @override
  String get docStepUpload => 'ارفع مستنداتك';

  @override
  String get docStepReview => 'مراجعة الفريق (حتى 24 ساعة)';

  @override
  String get docStepStartTrips => 'ابدأ قبول الرحلات';

  @override
  String get docRejectedAlertTitleSingle => 'مستند مرفوض — يلزم إعادة رفعه';

  @override
  String get docRejectedAlertTitlePlural =>
      'بعض المستندات مرفوضة — يلزم إعادة رفعها';

  @override
  String get docRejectedAlertBody =>
      'راجع سبب الرفض بجانب كل مستند بالأسفل ثم اضغط "إعادة الرفع".';

  @override
  String get docRejectedTitleSingle => 'مستند مرفوض';

  @override
  String docRejectedTitleCount(int count) => 'مستندات مرفوضة ($count)';

  @override
  String get docNoReasonFallback =>
      'لم يذكر المشرف سبباً محدداً — يرجى رفع صورة أوضح وسليمة.';

  @override
  String get accountApprovedTitle => 'تم اعتماد حسابك';

  @override
  String get accountApprovedSubtitle =>
      'يمكنك الآن استقبال الرحلات والبدء في الكسب.';

  @override
  String get accountRejectedTitle => 'تم رفض الطلب';

  @override
  String get accountRejectedSubtitle =>
      'عالج المستندات المرفوضة بالأسفل وأعد رفعها لإعادة المراجعة.';

  @override
  String get accountUnderReviewTitle => 'حسابك قيد المراجعة';

  @override
  String get accountUnderReviewSubtitle => 'سنخطرك فور اكتمال مراجعة مستنداتك.';

  // ── Chat ──────────────────────────────────────────────────────────

  @override
  String get chatTitle => 'محادثة الراكب';

  @override
  String get chatEmptyBody => 'لا توجد رسائل بعد.\nابدأ المحادثة مع الراكب.';

  @override
  String get chatComposerHint => 'اكتب رسالة...';

  @override
  String get chatTyping => 'جاري الكتابة…';

  // ── Rider — Trip screen ───────────────────────────────────────────

  @override
  String get tripLoadError => 'تعذّر تحميل بيانات الرحلة';

  @override
  String get riderCaptainFallback => 'كابتن';

  @override
  String get tripSearchingTitle => 'جارٍ البحث عن كابتن…';

  @override
  String get tripSearchingSubtitle => 'سنبلغك فور قبول كابتن لرحلتك';

  @override
  String get tripCancelAction => 'إلغاء الرحلة';

  @override
  String get tripOffersArrivedTitle => 'وصلت عروض من الكباتن';

  @override
  String get tripOffersArrivedSubtitle => 'اختار العرض اللي يناسبك من القايمة';

  @override
  String get tripViewOffersAction => 'عرض العروض';

  @override
  String get tripCaptainEnRoute => 'الكابتن في الطريق إليك';

  @override
  String get tripCaptainArrived => 'وصل الكابتن — تفضّل بالنزول';

  @override
  String get tripUnderway => 'الرحلة جارية';

  @override
  String get tripCompletedTitle => 'وصلت بسلامة!';

  @override
  String get tripCancelledTitle => 'تم إلغاء الرحلة';

  @override
  String get tripDoneButton => 'حسنًا';

  @override
  String get tripRateAction => 'قيّم رحلتك';

  @override
  String get tripMessageAction => 'مراسلة';

  @override
  String get tripMessageCaptainAction => 'مراسلة الكابتن';

  @override
  String get tripFareRowLabel => 'الأجرة';

  @override
  String get tripFinalFareLabel => 'الأجرة النهائية';

  @override
  String get tripBadgeSearching => 'جارٍ البحث';

  @override
  String get tripBadgeOffered => 'عروض متاحة';

  @override
  String get tripBadgeAssigned => 'كابتن في الطريق';

  @override
  String get tripBadgeArrived => 'وصل الكابتن';

  @override
  String get tripBadgeInProgress => 'الرحلة جارية';

  @override
  String get tripBadgeCompleted => 'وصلت';

  @override
  String get tripBadgeCancelled => 'ملغية';

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

  // ── Home tab ──────────────────────────────────────────────────────

  @override
  String get homeAwaitingApproval => 'Pending approval';

  @override
  String get homeOnlineReady => 'Online and ready';

  @override
  String get homeOffline => 'Offline';

  @override
  String get homeSocketLive => 'Live connection active';

  @override
  String get homeSocketReconnecting => 'Reconnecting…';

  @override
  String get homeSearchingTitle => 'Searching for nearby trips…';

  @override
  String get homeSearchingSubtitle => 'Stay in a busy area to get more requests';

  @override
  String get homeOfflineTitle => 'You are currently offline';

  @override
  String get homeUnderReviewTitle => 'Your account is under review';

  @override
  String get homeGoOnlineHint => 'Tap to start receiving trips and earnings';

  @override
  String get homeApprovalHint => "We'll notify you once your documents are approved";

  // ── Active trip panel ─────────────────────────────────────────────

  @override
  String get tripHeadingToRider => 'Heading to the rider';

  @override
  String get tripWaitingForRider => 'Waiting for the rider';

  @override
  String get tripInProgress => 'Trip in progress';

  @override
  String get tripActiveFallback => 'Active trip';

  @override
  String get riderFallbackName => 'Rider';

  @override
  String get finalFareLabel => 'Final fare';

  @override
  String get estimatedFareLabel => 'Estimated fare';

  @override
  String get riderChatLabel => 'Rider chat';

  @override
  String get callOpenError => 'Could not open the dialler';

  @override
  String get navToRider => 'Navigate to rider';

  @override
  String get navToDestination => 'Navigate to destination';

  @override
  String get arrivedAtPickupAction => 'Arrived at pickup';

  @override
  String get startTripAction => 'Start trip';

  @override
  String get endTripAction => 'End trip';

  @override
  String get tripUpdatingAction => 'Updating…';

  @override
  String get stageEnRoute => 'En route';

  @override
  String get stageArrived => 'Arrived';

  @override
  String get stageUnderway => 'Underway';

  @override
  String get stageDone => 'Done';

  @override
  String get endTripConfirmTitle => 'Confirm end of trip';

  @override
  String get endTripConfirmQuestion =>
      'Have you actually reached the destination?';

  @override
  String tripFareLine(String fare) => 'Fare: $fare EGP';

  @override
  String get endTripConfirmYes => 'Yes, end trip';

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

  // ── Wallet ────────────────────────────────────────────────────────

  @override
  String get walletTitle => 'Wallet';

  @override
  String get walletLoadError => 'Could not load wallet';

  @override
  String get noBalanceToWithdraw => 'Not enough balance to withdraw';

  @override
  String get payoutSheetTitle => 'Request payout';

  @override
  String availableBalanceLine(String balance) => 'Available balance: $balance EGP';

  @override
  String get vodafoneCashMethod => 'Vodafone Cash';

  @override
  String get instaPayMethod => 'InstaPay';

  @override
  String get vodafoneCashHint => 'Vodafone Cash wallet number';

  @override
  String get instaPayHint => 'Payment address (IPA) or account number';

  @override
  String payoutViaTitle(String method) => 'Withdraw via $method';

  @override
  String payoutAmountLine(String amount) => '$amount EGP will be withdrawn';

  @override
  String get confirmPayoutAction => 'Confirm payout';

  @override
  String get invalidAccountError => 'Please enter valid account details';

  @override
  String payoutSuccessToast(String method) =>
      'Payout request sent to $method';

  @override
  String payoutFailedToast(String error) => 'Payout failed: $error';

  @override
  String get availableBalanceHero => 'Available to withdraw';

  @override
  String payoutWindowLine(String window) => 'Payout window: $window';

  @override
  String weekTripsChip(int count) => 'Trips this week: $count';

  @override
  String weekCommissionChip(String amount) => 'Commission: $amount EGP';

  @override
  String get withdrawNowAction => 'Withdraw now';

  @override
  String get transactionHistoryTitle => 'Transaction history';

  @override
  String get noTransactionsYet => 'No wallet transactions yet';

  @override
  String get creditNoteFallback => 'Balance added';

  @override
  String get debitNoteFallback => 'Transaction debit';

  @override
  String get pendingMarker => 'Pending';

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

  // ── Documents ─────────────────────────────────────────────────────

  @override
  String get documentsRequiredTitle => 'Required documents';

  @override
  String get documentsStatusTooltip => 'Document status';

  @override
  String get refreshAccountTooltip => 'Refresh account status';

  @override
  String get docTypeLicense => 'Driving licence';

  @override
  String get docTypeNationalId => 'National ID';

  @override
  String get docTypeVehicleReg => 'Vehicle registration';

  @override
  String get docTypeCriminalRecord => 'Criminal record';

  @override
  String get docStatusApproved => 'Approved';

  @override
  String get docStatusPending => 'Under review';

  @override
  String get docStatusRejectedReupload => 'Rejected — re-upload';

  @override
  String get docStatusRejected => 'Rejected';

  @override
  String get docStatusNotUploaded => 'Not uploaded yet';

  @override
  String get docStatusMissing => 'Not uploaded';

  @override
  String get docUploading => 'Uploading…';

  @override
  String get docUploadAction => 'Upload';

  @override
  String get docReuploadAction => 'Re-upload';

  @override
  String get sourceCamera => 'Take a photo';

  @override
  String get sourceGallery => 'Choose from gallery';

  @override
  String docUploadedToast(String title) => '$title uploaded — under review';

  @override
  String get docUploadFailed => 'File upload failed';

  @override
  String get docUploadInvalidResponse => 'Invalid upload response';

  @override
  String docErrorPrefix(String error) => 'Error: $error';

  @override
  String get docHeaderIncomplete => 'Complete your professional profile';

  @override
  String get docHeaderAllUploaded => 'Your documents are under review';

  @override
  String get docHeaderIncompleteSubtitle =>
      'Upload your documents so our team can review and approve your account.';

  @override
  String get docHeaderAllUploadedSubtitle =>
      'Our team will contact you within 24 hours once approved.';

  @override
  String docProgressLine(int approved, int total) =>
      '$approved of $total documents approved';

  @override
  String get docProgressAllUploaded => 'All documents uploaded';

  @override
  String get docStepUpload => 'Upload your documents';

  @override
  String get docStepReview => 'Team review (up to 24h)';

  @override
  String get docStepStartTrips => 'Start accepting trips';

  @override
  String get docRejectedAlertTitleSingle => 'Document rejected — re-upload needed';

  @override
  String get docRejectedAlertTitlePlural =>
      'Some documents rejected — re-upload needed';

  @override
  String get docRejectedAlertBody =>
      'Review the rejection reason next to each document below, then tap "Re-upload".';

  @override
  String get docRejectedTitleSingle => 'Document rejected';

  @override
  String docRejectedTitleCount(int count) => 'Documents rejected ($count)';

  @override
  String get docNoReasonFallback =>
      'The admin gave no specific reason — please upload a clearer, valid photo.';

  @override
  String get accountApprovedTitle => 'Your account is approved';

  @override
  String get accountApprovedSubtitle =>
      'You can now receive trips and start earning.';

  @override
  String get accountRejectedTitle => 'Application rejected';

  @override
  String get accountRejectedSubtitle =>
      'Fix the rejected documents below and re-upload them for another review.';

  @override
  String get accountUnderReviewTitle => 'Your account is under review';

  @override
  String get accountUnderReviewSubtitle =>
      "We'll notify you as soon as the review is complete.";

  // ── Chat ──────────────────────────────────────────────────────────

  @override
  String get chatTitle => 'Rider chat';

  @override
  String get chatEmptyBody => 'No messages yet.\nStart the conversation with the rider.';

  @override
  String get chatComposerHint => 'Type a message…';

  @override
  String get chatTyping => 'Typing…';

  // ── Rider — Trip screen ───────────────────────────────────────────

  @override
  String get tripLoadError => 'Could not load trip data';

  @override
  String get riderCaptainFallback => 'Captain';

  @override
  String get tripSearchingTitle => 'Searching for a captain…';

  @override
  String get tripSearchingSubtitle =>
      "We'll notify you as soon as a captain accepts";

  @override
  String get tripCancelAction => 'Cancel trip';

  @override
  String get tripOffersArrivedTitle => 'Captain offers arrived';

  @override
  String get tripOffersArrivedSubtitle => 'Pick the offer that suits you';

  @override
  String get tripViewOffersAction => 'View offers';

  @override
  String get tripCaptainEnRoute => 'Captain is on the way to you';

  @override
  String get tripCaptainArrived => 'Captain arrived — hop in';

  @override
  String get tripUnderway => 'Trip in progress';

  @override
  String get tripCompletedTitle => 'Arrived safely!';

  @override
  String get tripCancelledTitle => 'Trip cancelled';

  @override
  String get tripDoneButton => 'Done';

  @override
  String get tripRateAction => 'Rate your trip';

  @override
  String get tripMessageAction => 'Message';

  @override
  String get tripMessageCaptainAction => 'Message captain';

  @override
  String get tripFareRowLabel => 'Fare';

  @override
  String get tripFinalFareLabel => 'Final fare';

  @override
  String get tripBadgeSearching => 'Searching';

  @override
  String get tripBadgeOffered => 'Offers available';

  @override
  String get tripBadgeAssigned => 'Captain en route';

  @override
  String get tripBadgeArrived => 'Captain arrived';

  @override
  String get tripBadgeInProgress => 'Trip in progress';

  @override
  String get tripBadgeCompleted => 'Arrived';

  @override
  String get tripBadgeCancelled => 'Cancelled';

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

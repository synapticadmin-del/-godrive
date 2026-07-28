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

  // ── Rider — Wallet & top-up

  /// Label above the wallet balance amount.
  String get availableBalance;

  /// Fallback title for a wallet transaction with no description.
  String get transactionFallback;

  /// App-bar title of the top-up screen and wallet top-up button.
  String get topUpTitle;

  /// App-bar title of the Paymob payment WebView screen.
  String get paymentTitle;

  /// Instruction above the top-up amount text field.
  String get topUpAmountPrompt;

  /// Primary button that starts the Paymob top-up flow.
  String get continuePayment;

  // ── Rider — Trip history

  /// App-bar title of the ride history screen.
  String get tripHistoryTitle;

  /// Empty-state body when the rider has no trip history.
  String get noPastTrips;

  /// Status chip for a completed trip in history.
  String get tripCompleted;

  /// Status chip for a cancelled trip in history.
  String get tripCancelled;

  /// App-bar title of the trip detail screen.
  String get tripDetailTitle;

  /// Empty-state title when the requested trip does not exist.
  String get tripNotFound;

  /// Section heading for the trip route card.
  String get tripRouteTitle;

  /// Route-card meta showing the trip distance in kilometres.
  String tripDistanceKmLine(String km);

  /// Route-card meta showing the trip duration in minutes.
  String tripDurationMinutes(int minutes);

  /// Section heading for the fare breakdown card.
  String get tripFareDetailsTitle;

  /// Fare-breakdown row for the applied discount.
  String get tripDiscountLabel;

  /// Fare-breakdown row for the final total.
  String get tripTotalLabel;

  // ── Rider — Safety & SOS

  /// Title of the SOS confirmation dialog.
  String get sosWarningTitle;

  /// Body of the SOS confirmation dialog.
  String get sosConfirmMessage;

  /// Destructive confirm button in the SOS dialog.
  String get sosConfirmAction;

  /// Error when device location services are disabled during SOS.
  String get sosLocationServiceError;

  /// Error when location permission is denied during SOS.
  String get sosLocationPermissionError;

  /// Error when GPS position cannot be resolved during SOS.
  String get sosLocationUnavailableError;

  /// Snack-bar after a successful SOS post.
  String get sosSentSuccess;

  /// Error when the share-trip endpoint returns no URL.
  String get shareTripError;

  /// Prefix of the share sheet message; the URL is appended.
  String get shareTripMessage;

  /// Hint under the SOS panic button.
  String get sosEmergencyOnlyHint;

  /// Button that shares the live-trip tracking link.
  String get shareTripDetails;

  // ── Rider — Notifications

  /// App-bar title of the notifications center.
  String get notificationsTitle;

  /// Action that clears all unread notification badges.
  String get markAllRead;

  /// Empty-state title when there are no notifications.
  String get noNotifications;

  /// Empty-state subtitle under noNotifications.
  String get notificationsWillAppearHere;

  // ── Rider — Saved places

  /// App-bar title of the saved places screen.
  String get savedPlacesTitle;

  /// Fallback label when a saved place has no name.
  String get placeFallback;

  /// Empty-state title when no places are saved.
  String get noSavedPlaces;

  /// Empty-state subtitle prompting to add home/work.
  String get addHomeWorkHint;

  /// App-bar title of the map-based location picker.
  String get pickLocationTitle;

  /// Hint inside the place-name text field.
  String get placeNameHint;

  /// Hint shown before the reverse-geocoded address resolves.
  String get moveMapToPick;

  /// Primary button that confirms the picked place.
  String get savePlace;

  /// Snack-bar when the device-location action in the search sheet fails.
  String get locationPermissionDenied;

  // ── Rider — Captain offers (bids sheet)

  /// Generic retry action shown after a failed load (e.g. the bids sheet error state).
  String get retryAction;

  /// Offline error body shown when a network call fails with no connectivity.
  String get checkConnectionError;

  /// Toast shown when a request fails due to a connection problem.
  String get connectionRetryError;

  /// Bids-sheet error when the offers request returns a non-200 status; {code} is the HTTP status code.
  String bidsLoadErrorWithCode(String code);

  /// Fallback toast when accepting a captain's bid fails and the server sent no message.
  String get bidAcceptFailedError;

  /// Header title of the captain offers (bids) sheet.
  String get bidsChooseCaptainTitle;

  /// Subtitle under the bids-sheet title reassuring the rider about captain verification.
  String get bidsAllCaptainsVerified;

  /// Destructive button in the bids-sheet header that cancels the whole trip request.
  String get bidsCancelRequestAction;

  /// Fallback captain display name on a bid card when the API sends no name.
  String get bidsCaptainFallback;

  /// Bid-card chip showing how many minutes until the captain can arrive.
  String bidsEtaMinutes(String minutes);

  /// Bid-card meta showing the captain's completed trip count next to the rating.
  String bidsTripCount(int count);

  /// Primary button on a bid card that accepts the captain's offer.
  String get bidAcceptAction;

  /// Secondary button on a bid card that dismisses the captain's offer.
  String get bidDeclineAction;

  /// Bids-sheet title while waiting for the first captain offer to arrive.
  String get bidsSearchingTitle;

  /// Bids-sheet subtitle under the searching title.
  String get bidsSearchingSubtitle;

  // ── Rider — Payment methods

  /// App-bar title of the payment methods screen.
  String get paymentMethodsTitle;

  /// Payment method row: pay the captain in cash.
  String get paymentCashTitle;

  /// Subtitle under the cash payment method row.
  String get paymentCashSubtitle;

  /// Payment method row: pay from the in-app wallet balance.
  String get paymentWalletTitle;

  /// Subtitle under the wallet payment method showing the current balance.
  String paymentWalletBalanceLine(String balance);

  /// Button on the wallet payment row that navigates to the wallet top-up screen.
  String get paymentTopUpAction;

  /// Payment method row: pay with a bank card.
  String get paymentCardTitle;

  /// Subtitle under the bank-card payment method row.
  String get paymentCardSubtitle;

  /// Button on the bank-card payment row that starts the add-card flow.
  String get paymentAddAction;

  /// Toast shown when the rider taps add-card before the Paymob flow is live.
  String get paymentCardComingSoonToast;

  /// Section heading above the payment methods explanatory note.
  String get paymentNoteTitle;

  /// Explanatory note at the bottom of the payment methods screen.
  String get paymentNoteBody;

  // ── Rider — Promo codes

  /// App-bar title of the promo codes screen.
  String get promoTitle;

  /// Hint text inside the promo-code entry field.
  String get promoCodeHint;

  /// Button that validates and applies the entered promo code.
  String get promoApplyAction;

  /// Success toast after a promo code validates; {amount} is the discount.
  String promoAppliedToast(String amount);

  /// Error toast when the entered promo code fails validation.
  String get promoInvalidToast;

  /// Empty-state title when the rider has no active promo codes.
  String get promoEmptyTitle;

  /// Empty-state subtitle prompting the rider to enter a code.
  String get promoEmptySubtitle;

  /// Promo card value line for a percentage discount.
  String promoDiscountPercent(int percent);

  /// Promo card value line for a fixed-amount discount.
  String promoDiscountFixed(String amount);

  /// Promo card line showing the code's expiry date.
  String promoExpiresLine(String date);

  // ── Rider — Rating sheet

  /// Title of the post-trip rating sheet.
  String get ratingTitle;

  /// Subtitle under the rating title naming the captain being rated.
  String ratingCaptainLine(String name);

  /// Hint text inside the optional rating comment field.
  String get ratingCommentHint;

  /// Primary button that submits the star rating.
  String get ratingSubmitAction;

  /// Quiet button that dismisses the rating sheet without rating.
  String get ratingSkipAction;

  /// Quick rating tag: the captain drove safely.
  String get ratingTagSafeDriving;

  /// Quick rating tag: the captain was polite.
  String get ratingTagPoliteCaptain;

  /// Quick rating tag: the car was clean.
  String get ratingTagCleanCar;

  /// Quick rating tag: the captain was punctual.
  String get ratingTagOnTime;

  /// Quick rating tag: the in-car music was pleasant.
  String get ratingTagComfortableMusic;

  /// Toast prefix when submitting a rating fails; {error} is the exception.
  String ratingErrorPrefix(String error);

  // ── Rider — Schedule a ride

  /// App-bar title of the ride scheduling screen.
  String get scheduleTitle;

  /// Help text on the date picker when scheduling a ride.
  String get schedulePickDateHelp;

  /// Help text on the time picker when scheduling a ride.
  String get schedulePickTimeHelp;

  /// Info card explaining how scheduled rides are dispatched.
  String get scheduleInfoNote;

  /// Label above the date selector on the scheduling screen.
  String get scheduleDateLabel;

  /// Label above the time selector on the scheduling screen.
  String get scheduleTimeLabel;

  /// Summary line showing the chosen scheduled date and time.
  String scheduleSummaryLine(String dateTime);

  /// Primary button that confirms the scheduled ride.
  String get scheduleConfirmAction;

  // ── Rider — Home & map picking

  /// Label for the option that resolves the pickup from the device GPS fix.
  String get currentLocationGps;

  /// Name of the language the toggle will switch TO (shown in the current locale's other language).
  String get otherLanguageName;

  /// Tooltip on the floating theme-toggle button (home + login).
  String get toggleThemeTooltip;

  /// Tooltip for the floating button that recentres the map on the device location.
  String get myLocationTooltip;

  /// Tooltip for back buttons.
  String get backTooltip;

  /// Tooltip/helper for the pickup field on the home screen.
  String get setPickupPoint;

  /// Tooltip/helper for the destination field on the home screen.
  String get setDestinationPoint;

  /// Hint shown in the empty pickup field on the home screen.
  String get whereFromHint;

  /// Hint shown in the empty destination field on the home screen.
  String get whereToHint;

  /// Tooltip for the button that swaps the two trip endpoints.
  String get swapLocationsTooltip;

  /// Primary action that confirms the point being set via map pan.
  String get continueAction;

  /// Inline status while the route between the two points is being fetched.
  String get calculatingRoute;

  /// Marker for values (distance/ETA/fare) that are approximate.
  String get approximateLabel;

  /// Instruction banner shown while the map-pan point-selection mode is active.
  String get moveMapToSetPoint;

  /// SnackBar shown after confirming the pickup point on the map.
  String get confirmPickup;

  /// SnackBar shown after confirming the destination point on the map.
  String get confirmDestination;

  // ── Rider — Location search sheet

  /// Message shown when the places search endpoint fails.
  String get searchUnavailable;

  /// Label for the pickup end of the trip.
  String get pickupPointLabel;

  /// Label for the destination end of the trip.
  String get destinationLabel;

  /// Hint inside the search sheet field when resolving the pickup.
  String get searchPickupHint;

  /// Hint inside the search sheet field when resolving the destination.
  String get searchDestinationHint;

  /// Empty state when a places query returns no results.
  String get noPlacesFound;

  /// Suggestion shown under the no-results empty state.
  String get trySimplerNameOrMap;

  /// Section heading above the places search results.
  String get resultsSection;

  /// Section heading above the popular-places list in the search sheet.
  String get popularPlacesSection;

  /// Button that switches from search to map-pan point selection.
  String get setOnMapAction;

  /// Sub-line explaining the set-on-map fallback when search cannot find a place.
  String get setOnMapSubtitle;

  /// Address label used for a point resolved from the device GPS fix.
  String get myCurrentLocation;

  /// Button in the search sheet that fills the point from GPS.
  String get useDeviceLocation;

  // ── Rider — Travel mode bar

  /// Tooltip for returning to the rides tab.
  String get backToRidesTooltip;

  /// Bottom-bar tab that opens the trip-planning flow.
  String get travelTabTrip;

  /// Bottom-bar tab that opens the orders/activity list.
  String get travelTabOrders;

  // ── Rider — Login & sign-up

  /// Label on the language chip — names the language it will switch to.
  String get languageChipLabel;

  /// Headline on the sign-in form.
  String get loginWelcomeBackTitle;

  /// Headline on the sign-up form.
  String get loginCreateAccountTitle;

  /// Sub-line under the sign-in headline.
  String get loginSignInSubtitle;

  /// Sub-line under the sign-up headline.
  String get loginSignUpSubtitle;

  /// Hint for the full-name field on the sign-up form.
  String get loginFullNameHint;

  /// Hint for the phone field on the sign-up form.
  String get loginPhoneHint;

  /// Hint for the email field on the login screen.
  String get loginEmailHint;

  /// Hint for the password field on the login screen.
  String get loginPasswordHint;

  /// Checkbox label for accepting the terms on the sign-up form.
  String get loginTermsLabel;

  /// Primary button on the sign-in form.
  String get loginSignInAction;

  /// Primary button on the sign-up form.
  String get loginCreateAccountAction;

  /// Generic sign-up action label.
  String get loginSignUpAction;

  /// Link that switches the sign-up form back to sign-in.
  String get loginAlreadyHaveAccount;

  /// Link that switches the sign-in form to sign-up.
  String get loginNoAccount;

  /// Validation message for the email/password fields.
  String get loginEnterEmailPassword;

  /// Validation message for the name/phone fields.
  String get loginEnterValidNamePhone;

  /// SnackBar shown when signing up without accepting the terms.
  String get loginMustAcceptTerms;
  /// Divider text between the form and social sign-in buttons.
  String get loginOrContinueWith;

  /// Toast when tapping a social sign-in button that is not yet wired.
  String get loginSocialComingSoon;

  /// Hero slide 1 — safety headline.
  String get loginHeroSafetyTitle;

  /// Hero slide 1 — safety supporting copy.
  String get loginHeroSafetyBody;

  /// Hero slide 2 — price negotiation headline.
  String get loginHeroPriceTitle;

  /// Hero slide 2 — price negotiation supporting copy.
  String get loginHeroPriceBody;

  // ── Rider — Fare estimate sheet

  /// Title of the fare-estimate bottom sheet.
  String get tripDetailsTitle;

  /// Label for the payment method row on the fare sheet.
  String get paymentMethodLabel;

  /// Cash payment method label.
  String get paymentCash;

  /// Primary button that dispatches the ride request with the rider's offer.
  String get requestRideAction;

  /// Fallback label when the pickup address is not yet resolved.
  String get pickupPointFallback;

  /// Fallback label when the destination address is not yet resolved.
  String get destinationPointFallback;

  /// Label for the system-suggested fare on the fare sheet.
  String get estimatedLabel;

  /// Status shown while the fare estimate is being fetched.
  String get calculatingFare;

  /// Error shown when the fare estimate request fails.
  String get fareLoadError;

  /// Retry button on the fare error state.
  String get tryAgainAction;

  /// Label above the rider's editable fare offer.
  String get yourOfferLabel;

  /// Button that resets the rider's offer to the suggested fare.
  String get resetToSuggestedAction;

  /// Accessibility label for the offer minus button.
  String get decreasePriceSemantic;

  /// Accessibility label for the offer plus button.
  String get increasePriceSemantic;

  /// Hint shown when no suggested fare is available to anchor the offer.
  String get offerHintNoSuggestion;

  /// Hint when the rider's offer equals the suggested fare.
  String offerHintFairPrice(int s);

  /// Hint when the rider's offer is above the suggested fare.
  String offerHintAbove(int d, int s);

  /// Hint when the rider's offer is below the suggested fare.
  String offerHintBelow(int d, int s);

  // ── Rider — Profile & settings

  /// Title of the edit-profile bottom sheet.
  String get editProfileInfoTitle;

  /// Label for the full-name field in the edit-profile sheet.
  String get fullNameLabel;

  /// Label for the phone field in the edit-profile sheet.
  String get phoneNumberLabel;

  /// Label for the locked email field in the edit-profile sheet.
  String get emailReadOnlyLabel;

  /// SnackBar shown after the profile is saved successfully.
  String get profileUpdatedSuccess;

  /// Primary save button in the edit-profile sheet.
  String get saveChangesAction;

  /// Title of the avatar-picker bottom sheet.
  String get changeProfilePictureTitle;

  /// Button in the avatar picker to choose a new photo.
  String get chooseNewPhotoAction;

  /// Fallback display name when the profile has no name or email.
  String get fallbackUserName;

  /// AppBar title of the profile screen.
  String get profileTitle;

  /// Tooltip for the language toggle action (shows the target language).
  String get toggleLanguageTooltip;

  /// Button under the profile header that opens the edit-profile sheet.
  String get editDetailsAction;

  /// Label over the wallet balance on the profile wallet card.
  String get availableBalanceLabel;

  /// Profile menu item that opens the trip history screen.
  String get myTripsLabel;

  /// Profile menu item that opens the saved-places screen.
  String get savedPlacesLabel;

  /// AppBar title of the settings screen and its profile menu item.
  String get settingsTitle;

  /// Theme-mode dropdown option that follows the device setting.
  String get themeSystem;

  /// Theme-mode dropdown option for the light theme.
  String get themeLight;

  /// Theme-mode dropdown option for the dark theme.
  String get themeDark;

  // ── Rider — Help & invite

  /// AppBar title of the help screen.
  String get helpCenterTitle;

  /// Headline on the help screen contact-support card.
  String get needHelpTitle;

  /// Sub-line under the help contact-support headline.
  String get supportAvailableBody;

  /// Button on the help card that contacts support.
  String get contactAction;

  /// SnackBar shown after tapping the help contact button.
  String get supportContactSoonMessage;

  /// Section heading above the FAQ list on the help screen.
  String get faqTitle;

  /// AppBar title of the invite/referral screen.
  String get inviteFriendsTitle;

  /// Headline on the invite hero card.
  String get inviteHeroTitle;

  /// Sub-line on the invite hero card explaining the reward.
  String get inviteHeroSubtitle;

  /// Label above the referral code value on the invite screen.
  String get referralCodeLabel;

  /// Label for the referral credits stat card.
  String get yourCreditsLabel;

  /// Label for the invited-friends count stat card.
  String get friendsInvitedLabel;

  /// Primary share button on the invite screen.
  String get shareCodeAction;

  /// Share-sheet body on the invite screen; {code} is the referral code.
  String inviteShareMessage(String code);

  // ── Rider — Splash

  /// Tagline under the splash brand mark.
  String get splashTagline;

  /// Attribution line above the studio badge on the splash screen.
  String get createdByLabel;

  /// Studio name on the splash attribution badge.
  String get synapticStudioLabel;
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

  // ── Rider — Wallet & top-up ─────────────────────────────────────

  /// Label above the wallet balance amount.
  @override
  String get availableBalance => 'الرصيد المتاح';

  /// Fallback title for a wallet transaction with no description.
  @override
  String get transactionFallback => 'عملية';

  /// App-bar title of the top-up screen and wallet top-up button.
  @override
  String get topUpTitle => 'شحن المحفظة';

  /// App-bar title of the Paymob payment WebView screen.
  @override
  String get paymentTitle => 'الدفع';

  /// Instruction above the top-up amount text field.
  @override
  String get topUpAmountPrompt => 'أدخل المبلغ المراد شحنه';

  /// Primary button that starts the Paymob top-up flow.
  @override
  String get continuePayment => 'متابعة الدفع';

  // ── Rider — Trip history ────────────────────────────────────────

  /// App-bar title of the ride history screen.
  @override
  String get tripHistoryTitle => 'سجل الرحلات';

  /// Empty-state body when the rider has no trip history.
  @override
  String get noPastTrips => 'لا توجد رحلات سابقة';

  /// Status chip for a completed trip in history.
  @override
  String get tripCompleted => 'مكتملة';

  /// Status chip for a cancelled trip in history.
  @override
  String get tripCancelled => 'ملغاة';

  /// App-bar title of the trip detail screen.
  @override
  String get tripDetailTitle => 'تفاصيل الرحلة';

  /// Empty-state title when the requested trip does not exist.
  @override
  String get tripNotFound => 'الرحلة غير موجودة';

  /// Section heading for the trip route card.
  @override
  String get tripRouteTitle => 'المسار';

  /// Route-card meta showing the trip distance in kilometres.
  @override
  String tripDistanceKmLine(String km) => '$km كم';

  /// Route-card meta showing the trip duration in minutes.
  @override
  String tripDurationMinutes(int minutes) => '$minutes دقيقة';

  /// Section heading for the fare breakdown card.
  @override
  String get tripFareDetailsTitle => 'تفاصيل الأجرة';

  /// Fare-breakdown row for the applied discount.
  @override
  String get tripDiscountLabel => 'الخصم';

  /// Fare-breakdown row for the final total.
  @override
  String get tripTotalLabel => 'الإجمالي';

  // ── Rider — Safety & SOS ────────────────────────────────────────

  /// Title of the SOS confirmation dialog.
  @override
  String get sosWarningTitle => 'تحذير';

  /// Body of the SOS confirmation dialog.
  @override
  String get sosConfirmMessage => 'هل أنت متأكد من تفعيل حالة الطوارئ؟ سيتم إرسال موقعك للسلطات وإدارة التطبيق.';

  /// Destructive confirm button in the SOS dialog.
  @override
  String get sosConfirmAction => 'تأكيد الطوارئ';

  /// Error when device location services are disabled during SOS.
  @override
  String get sosLocationServiceError => 'فعّل خدمة الموقع لإرسال نداء الطوارئ';

  /// Error when location permission is denied during SOS.
  @override
  String get sosLocationPermissionError => 'اسمح للتطبيق بالوصول إلى موقعك لإرسال نداء الطوارئ';

  /// Error when GPS position cannot be resolved during SOS.
  @override
  String get sosLocationUnavailableError => 'تعذّر تحديد موقعك. حاول مجددًا في مكان مفتوح';

  /// Snack-bar after a successful SOS post.
  @override
  String get sosSentSuccess => 'تم إرسال نداء الطوارئ بنجاح مع تحديد موقعك';

  /// Error when the share-trip endpoint returns no URL.
  @override
  String get shareTripError => 'تعذّر إنشاء رابط تتبع الرحلة';

  /// Prefix of the share sheet message; the URL is appended.
  @override
  String get shareTripMessage => 'تتبع رحلتي على GoDrive عبر الرابط التالي:
';

  /// Hint under the SOS panic button.
  @override
  String get sosEmergencyOnlyHint => 'اضغط على الزر أعلاه في حالة الطوارئ القصوى فقط';

  /// Button that shares the live-trip tracking link.
  @override
  String get shareTripDetails => 'مشاركة تفاصيل الرحلة';

  // ── Rider — Notifications ───────────────────────────────────────

  /// App-bar title of the notifications center.
  @override
  String get notificationsTitle => 'الإشعارات';

  /// Action that clears all unread notification badges.
  @override
  String get markAllRead => 'تعليم الكل كمقروء';

  /// Empty-state title when there are no notifications.
  @override
  String get noNotifications => 'لا توجد إشعارات';

  /// Empty-state subtitle under noNotifications.
  @override
  String get notificationsWillAppearHere => 'ستظهر إشعاراتك هنا';

  // ── Rider — Saved places ────────────────────────────────────────

  /// App-bar title of the saved places screen.
  @override
  String get savedPlacesTitle => 'الأماكن المحفوظة';

  /// Fallback label when a saved place has no name.
  @override
  String get placeFallback => 'مكان';

  /// Empty-state title when no places are saved.
  @override
  String get noSavedPlaces => 'لا توجد أماكن محفوظة';

  /// Empty-state subtitle prompting to add home/work.
  @override
  String get addHomeWorkHint => 'أضف منزلك أو عملك لطلب رحلة سريعة';

  /// App-bar title of the map-based location picker.
  @override
  String get pickLocationTitle => 'اختر الموقع';

  /// Hint inside the place-name text field.
  @override
  String get placeNameHint => 'اسم المكان (المنزل، العمل...)';

  /// Hint shown before the reverse-geocoded address resolves.
  @override
  String get moveMapToPick => 'حرّك الخريطة لتحديد الموقع';

  /// Primary button that confirms the picked place.
  @override
  String get savePlace => 'حفظ المكان';

  /// Snack-bar when the device-location action in the search sheet fails.
  @override
  String get locationPermissionDenied => 'فعّل إذن الموقع لاستخدام موقع جهازك';

  // ── Rider — Captain offers (bids sheet) ─────────────────────────

  /// Generic retry action shown after a failed load (e.g. the bids sheet error state).
  @override
  String get retryAction => 'إعادة المحاولة';

  /// Offline error body shown when a network call fails with no connectivity.
  @override
  String get checkConnectionError => 'تحقق من اتصالك بالإنترنت';

  /// Toast shown when a request fails due to a connection problem.
  @override
  String get connectionRetryError => 'تعذّر الاتصال، حاول مرة أخرى';

  /// Bids-sheet error when the offers request returns a non-200 status; {code} is the HTTP status code.
  @override
  String bidsLoadErrorWithCode(String code) => 'تعذّر تحميل العروض ($code)';

  /// Fallback toast when accepting a captain's bid fails and the server sent no message.
  @override
  String get bidAcceptFailedError => 'فشل قبول العرض، حاول مرة أخرى';

  /// Header title of the captain offers (bids) sheet.
  @override
  String get bidsChooseCaptainTitle => 'اختيار سائق';

  /// Subtitle under the bids-sheet title reassuring the rider about captain verification.
  @override
  String get bidsAllCaptainsVerified => 'تم التحقق من جميع السائقين';

  /// Destructive button in the bids-sheet header that cancels the whole trip request.
  @override
  String get bidsCancelRequestAction => 'إلغاء الطلب';

  /// Fallback captain display name on a bid card when the API sends no name.
  @override
  String get bidsCaptainFallback => 'كابتن GoDrive';

  /// Bid-card chip showing how many minutes until the captain can arrive.
  @override
  String bidsEtaMinutes(String minutes) => '$minutes دقيقة';

  /// Bid-card meta showing the captain's completed trip count next to the rating.
  @override
  String bidsTripCount(int count) => '$count رحلة';

  /// Primary button on a bid card that accepts the captain's offer.
  @override
  String get bidAcceptAction => 'قبول';

  /// Secondary button on a bid card that dismisses the captain's offer.
  @override
  String get bidDeclineAction => 'رفض';

  /// Bids-sheet title while waiting for the first captain offer to arrive.
  @override
  String get bidsSearchingTitle => 'جارٍ البحث عن كباتن قريبين';

  /// Bids-sheet subtitle under the searching title.
  @override
  String get bidsSearchingSubtitle => 'هتوصلك عروض الأسعار هنا أول ما يردّوا';

  // ── Rider — Payment methods ─────────────────────────────────────

  /// App-bar title of the payment methods screen.
  @override
  String get paymentMethodsTitle => 'طرق الدفع';

  /// Payment method row: pay the captain in cash.
  @override
  String get paymentCashTitle => 'كاش';

  /// Subtitle under the cash payment method row.
  @override
  String get paymentCashSubtitle => 'ادفع للكابتن مباشرة';

  /// Payment method row: pay from the in-app wallet balance.
  @override
  String get paymentWalletTitle => 'المحفظة';

  /// Subtitle under the wallet payment method showing the current balance.
  @override
  String paymentWalletBalanceLine(String balance) => 'الرصيد: $balance ج.م';

  /// Button on the wallet payment row that navigates to the wallet top-up screen.
  @override
  String get paymentTopUpAction => 'شحن';

  /// Payment method row: pay with a bank card.
  @override
  String get paymentCardTitle => 'بطاقة بنكية';

  /// Subtitle under the bank-card payment method row.
  @override
  String get paymentCardSubtitle => 'إضافة بطاقة عبر Paymob';

  /// Button on the bank-card payment row that starts the add-card flow.
  @override
  String get paymentAddAction => 'إضافة';

  /// Toast shown when the rider taps add-card before the Paymob flow is live.
  @override
  String get paymentCardComingSoonToast => 'سيتم تفعيل الدفع بالبطاقة قريبًا';

  /// Section heading above the payment methods explanatory note.
  @override
  String get paymentNoteTitle => 'ملاحظة';

  /// Explanatory note at the bottom of the payment methods screen.
  @override
  String get paymentNoteBody => 'يمكنك تغيير طريقة الدفع الافتراضية في أي وقت. سيتم استخدامها تلقائيًا في رحلاتك القادمة.';

  // ── Rider — Promo codes ─────────────────────────────────────────

  /// App-bar title of the promo codes screen.
  @override
  String get promoTitle => 'أكواد الخصم';

  /// Hint text inside the promo-code entry field.
  @override
  String get promoCodeHint => 'أدخل كود الخصم';

  /// Button that validates and applies the entered promo code.
  @override
  String get promoApplyAction => 'تطبيق';

  /// Success toast after a promo code validates; {amount} is the discount.
  @override
  String promoAppliedToast(String amount) => 'تم تطبيق الكود! خصم $amount ج.م';

  /// Error toast when the entered promo code fails validation.
  @override
  String get promoInvalidToast => 'كود غير صالح أو منتهي';

  /// Empty-state title when the rider has no active promo codes.
  @override
  String get promoEmptyTitle => 'لا توجد أكواد نشطة';

  /// Empty-state subtitle prompting the rider to enter a code.
  @override
  String get promoEmptySubtitle => 'أدخل كود خصم لتستفيد من العروض';

  /// Promo card value line for a percentage discount.
  @override
  String promoDiscountPercent(int percent) => 'خصم $percent%';

  /// Promo card value line for a fixed-amount discount.
  @override
  String promoDiscountFixed(String amount) => 'خصم $amount ج.م';

  /// Promo card line showing the code's expiry date.
  @override
  String promoExpiresLine(String date) => 'ينتهي $date';

  // ── Rider — Rating sheet ────────────────────────────────────────

  /// Title of the post-trip rating sheet.
  @override
  String get ratingTitle => 'كيف كانت رحلتك؟';

  /// Subtitle under the rating title naming the captain being rated.
  @override
  String ratingCaptainLine(String name) => 'قيّم $name';

  /// Hint text inside the optional rating comment field.
  @override
  String get ratingCommentHint => 'تعليق إضافي (اختياري)';

  /// Primary button that submits the star rating.
  @override
  String get ratingSubmitAction => 'إرسال التقييم';

  /// Quiet button that dismisses the rating sheet without rating.
  @override
  String get ratingSkipAction => 'تخطّي';

  /// Quick rating tag: the captain drove safely.
  @override
  String get ratingTagSafeDriving => 'قيادة آمنة';

  /// Quick rating tag: the captain was polite.
  @override
  String get ratingTagPoliteCaptain => 'موجّه مهذب';

  /// Quick rating tag: the car was clean.
  @override
  String get ratingTagCleanCar => 'سيارة نظيفة';

  /// Quick rating tag: the captain was punctual.
  @override
  String get ratingTagOnTime => 'في الوقت';

  /// Quick rating tag: the in-car music was pleasant.
  @override
  String get ratingTagComfortableMusic => 'موسيقى مريحة';

  /// Toast prefix when submitting a rating fails; {error} is the exception.
  @override
  String ratingErrorPrefix(String error) => 'خطأ: $error';

  // ── Rider — Schedule a ride ─────────────────────────────────────

  /// App-bar title of the ride scheduling screen.
  @override
  String get scheduleTitle => 'جدولة رحلة';

  /// Help text on the date picker when scheduling a ride.
  @override
  String get schedulePickDateHelp => 'اختر تاريخ الرحلة';

  /// Help text on the time picker when scheduling a ride.
  @override
  String get schedulePickTimeHelp => 'اختر وقت الرحلة';

  /// Info card explaining how scheduled rides are dispatched.
  @override
  String get scheduleInfoNote => 'سيتم إرسال كابتن تلقائيًا قبل موعد رحلتك بـ 10 دقائق.';

  /// Label above the date selector on the scheduling screen.
  @override
  String get scheduleDateLabel => 'التاريخ';

  /// Label above the time selector on the scheduling screen.
  @override
  String get scheduleTimeLabel => 'الوقت';

  /// Summary line showing the chosen scheduled date and time.
  @override
  String scheduleSummaryLine(String dateTime) => 'موعد الرحلة: $dateTime';

  /// Primary button that confirms the scheduled ride.
  @override
  String get scheduleConfirmAction => 'جدولة الرحلة';

  // ── Rider — Home & map picking ──────────────────────────────────

  /// Label for the option that resolves the pickup from the device GPS fix.
  @override
  String get currentLocationGps => 'الموقع الحالي (GPS)';

  /// Name of the language the toggle will switch TO (shown in the current locale's other language).
  @override
  String get otherLanguageName => 'English';

  @override
  String get toggleThemeTooltip => 'تغيير المظهر';

  /// Tooltip for the floating button that recentres the map on the device location.
  @override
  String get myLocationTooltip => 'موقعي الحالي';

  /// Tooltip for back buttons.
  @override
  String get backTooltip => 'رجوع';

  /// Tooltip/helper for the pickup field on the home screen.
  @override
  String get setPickupPoint => 'تحديد نقطة الانطلاق';

  /// Tooltip/helper for the destination field on the home screen.
  @override
  String get setDestinationPoint => 'تحديد نقطة الوصول';

  /// Hint shown in the empty pickup field on the home screen.
  @override
  String get whereFromHint => 'من أين؟';

  /// Hint shown in the empty destination field on the home screen.
  @override
  String get whereToHint => 'إلى أين؟';

  /// Tooltip for the button that swaps the two trip endpoints.
  @override
  String get swapLocationsTooltip => 'تبديل نقطتي الانطلاق والوصول';

  /// Primary action that confirms the point being set via map pan.
  @override
  String get continueAction => 'متابعة';

  /// Inline status while the route between the two points is being fetched.
  @override
  String get calculatingRoute => 'جاري حساب المسار…';

  /// Marker for values (distance/ETA/fare) that are approximate.
  @override
  String get approximateLabel => 'تقريبي';

  /// Instruction banner shown while the map-pan point-selection mode is active.
  @override
  String get moveMapToSetPoint => 'حرّك الخريطة لتحديد النقطة';

  /// SnackBar shown after confirming the pickup point on the map.
  @override
  String get confirmPickup => 'تم تحديد نقطة الانطلاق';

  /// SnackBar shown after confirming the destination point on the map.
  @override
  String get confirmDestination => 'تم تحديد نقطة الوصول';

  // ── Rider — Location search sheet ───────────────────────────────

  /// Message shown when the places search endpoint fails.
  @override
  String get searchUnavailable => 'البحث غير متاح حاليًا، تحقق من الاتصال';

  /// Label for the pickup end of the trip.
  @override
  String get pickupPointLabel => 'نقطة الانطلاق';

  /// Label for the destination end of the trip.
  @override
  String get destinationLabel => 'نقطة الوصول';

  /// Hint inside the search sheet field when resolving the pickup.
  @override
  String get searchPickupHint => 'ابحث عن نقطة الانطلاق';

  /// Hint inside the search sheet field when resolving the destination.
  @override
  String get searchDestinationHint => 'ابحث عن الوجهة';

  /// Empty state when a places query returns no results.
  @override
  String get noPlacesFound => 'لم يتم العثور على أماكن';

  /// Suggestion shown under the no-results empty state.
  @override
  String get trySimplerNameOrMap => 'جرّب اسمًا أبسط أو حدّد الموقع على الخريطة';

  /// Section heading above the places search results.
  @override
  String get resultsSection => 'نتائج البحث';

  /// Section heading above the popular-places list in the search sheet.
  @override
  String get popularPlacesSection => 'أماكن شائعة';

  /// Button that switches from search to map-pan point selection.
  @override
  String get setOnMapAction => 'تحديد على الخريطة';

  /// Sub-line explaining the set-on-map fallback when search cannot find a place.
  @override
  String get setOnMapSubtitle => 'حدّد الموقع يدويًا على الخريطة';

  /// Address label used for a point resolved from the device GPS fix.
  @override
  String get myCurrentLocation => 'موقعي الحالي';

  /// Button in the search sheet that fills the point from GPS.
  @override
  String get useDeviceLocation => 'استخدام موقع الجهاز';

  // ── Rider — Travel mode bar ─────────────────────────────────────

  /// Tooltip for returning to the rides tab.
  @override
  String get backToRidesTooltip => 'العودة إلى الرحلات';

  /// Bottom-bar tab that opens the trip-planning flow.
  @override
  String get travelTabTrip => 'رحلة';

  /// Bottom-bar tab that opens the orders/activity list.
  @override
  String get travelTabOrders => 'الطلبات';

  // ── Rider — Login & sign-up ─────────────────────────────────────

  /// Label on the language chip — names the language it will switch to.
  @override
  String get languageChipLabel => 'EN';

  /// Headline on the sign-in form.
  @override
  String get loginWelcomeBackTitle => 'مرحبًا بعودتك';

  /// Headline on the sign-up form.
  @override
  String get loginCreateAccountTitle => 'إنشاء حساب جديد';

  /// Sub-line under the sign-in headline.
  @override
  String get loginSignInSubtitle => 'سجّل الدخول للمتابعة';

  /// Sub-line under the sign-up headline.
  @override
  String get loginSignUpSubtitle => 'أنشئ حسابك وابدأ رحلتك الأولى';

  /// Hint for the full-name field on the sign-up form.
  @override
  String get loginFullNameHint => 'الاسم الكامل';

  /// Hint for the phone field on the sign-up form.
  @override
  String get loginPhoneHint => 'رقم الهاتف';

  /// Hint for the email field on the login screen.
  @override
  String get loginEmailHint => 'البريد الإلكتروني';

  /// Hint for the password field on the login screen.
  @override
  String get loginPasswordHint => 'كلمة المرور';

  /// Checkbox label for accepting the terms on the sign-up form.
  @override
  String get loginTermsLabel => 'أوافق على الشروط والأحكام';

  /// Primary button on the sign-in form.
  @override
  String get loginSignInAction => 'تسجيل الدخول';

  /// Primary button on the sign-up form.
  @override
  String get loginCreateAccountAction => 'إنشاء الحساب';

  /// Generic sign-up action label.
  @override
  String get loginSignUpAction => 'إنشاء حساب';

  /// Link that switches the sign-up form back to sign-in.
  @override
  String get loginAlreadyHaveAccount => 'لديك حساب بالفعل؟ سجّل الدخول';

  /// Link that switches the sign-in form to sign-up.
  @override
  String get loginNoAccount => 'ليس لديك حساب؟ أنشئ حسابًا';

  /// Validation message for the email/password fields.
  @override
  String get loginEnterEmailPassword => 'أدخل بريدًا إلكترونيًا وكلمة مرور صالحين';

  /// Validation message for the name/phone fields.
  @override
  String get loginEnterValidNamePhone => 'أدخل اسمًا ورقم هاتف صالحين';

  /// SnackBar shown when signing up without accepting the terms.
  @override
  String get loginMustAcceptTerms => 'يجب الموافقة على الشروط والأحكام';
  @override
  String get loginOrContinueWith => 'أو المتابعة بواسطة';
  @override
  String get loginSocialComingSoon => 'تسجيل الدخول عبر وسائل التواصل قريباً';
  @override
  String get loginHeroSafetyTitle => 'سلامتك هي أولويتنا';
  @override
  String get loginHeroSafetyBody =>
      'كل كباتننا موثّقون، وزر الطوارئ متاح في كل رحلة';
  @override
  String get loginHeroPriceTitle => 'اختر السعر اللي يناسبك';
  @override
  String get loginHeroPriceBody =>
      'حدّد أجرتك بنفسك، والكباتن يقدموا عروضهم — أنت صاحب القرار';

  // ── Rider — Fare estimate sheet ─────────────────────────────────

  /// Title of the fare-estimate bottom sheet.
  @override
  String get tripDetailsTitle => 'تفاصيل الرحلة';

  /// Label for the payment method row on the fare sheet.
  @override
  String get paymentMethodLabel => 'طريقة الدفع';

  /// Cash payment method label.
  @override
  String get paymentCash => 'كاش';

  /// Primary button that dispatches the ride request with the rider's offer.
  @override
  String get requestRideAction => 'اطلب الرحلة';

  /// Fallback label when the pickup address is not yet resolved.
  @override
  String get pickupPointFallback => 'نقطة الانطلاق';

  /// Fallback label when the destination address is not yet resolved.
  @override
  String get destinationPointFallback => 'نقطة الوصول';

  /// Label for the system-suggested fare on the fare sheet.
  @override
  String get estimatedLabel => 'السعر المقترح';

  /// Status shown while the fare estimate is being fetched.
  @override
  String get calculatingFare => 'جاري حساب السعر…';

  /// Error shown when the fare estimate request fails.
  @override
  String get fareLoadError => 'تعذّر تحميل السعر، حاول مرة أخرى';

  /// Retry button on the fare error state.
  @override
  String get tryAgainAction => 'حاول مرة أخرى';

  /// Label above the rider's editable fare offer.
  @override
  String get yourOfferLabel => 'عرضك';

  /// Button that resets the rider's offer to the suggested fare.
  @override
  String get resetToSuggestedAction => 'إعادة للسعر المقترح';

  /// Accessibility label for the offer minus button.
  @override
  String get decreasePriceSemantic => 'تقليل السعر';

  /// Accessibility label for the offer plus button.
  @override
  String get increasePriceSemantic => 'زيادة السعر';

  /// Hint shown when no suggested fare is available to anchor the offer.
  @override
  String get offerHintNoSuggestion => 'لا يوجد سعر مقترح بعد — أدخل عرضك';

  /// Hint when the rider's offer equals the suggested fare.
  @override
  String offerHintFairPrice(int s) => 'عرضك مطابق للسعر المقترح — سعر عادل';

  /// Hint when the rider's offer is above the suggested fare.
  @override
  String offerHintAbove(int d, int s) => 'عرضك أعلى من المقترح — فرصة أكبر لقبول الكابتن';

  /// Hint when the rider's offer is below the suggested fare.
  @override
  String offerHintBelow(int d, int s) => 'عرضك أقل من المقترح — قد يستغرق القبول وقتًا أطول';

  // ── Rider — Profile & settings ──────────────────────────────────

  /// Title of the edit-profile bottom sheet.
  @override
  String get editProfileInfoTitle => 'تعديل البيانات الشخصية';

  /// Label for the full-name field in the edit-profile sheet.
  @override
  String get fullNameLabel => 'الاسم الكامل';

  /// Label for the phone field in the edit-profile sheet.
  @override
  String get phoneNumberLabel => 'رقم الهاتف';

  /// Label for the locked email field in the edit-profile sheet.
  @override
  String get emailReadOnlyLabel => 'البريد الإلكتروني (غير قابل للتعديل)';

  /// SnackBar shown after the profile is saved successfully.
  @override
  String get profileUpdatedSuccess => 'تم حفظ التعديلات بنجاح';

  /// Primary save button in the edit-profile sheet.
  @override
  String get saveChangesAction => 'حفظ التعديلات';

  /// Title of the avatar-picker bottom sheet.
  @override
  String get changeProfilePictureTitle => 'تغيير الصورة الشخصية';

  /// Button in the avatar picker to choose a new photo.
  @override
  String get chooseNewPhotoAction => 'اختيار صورة جديدة';

  /// Fallback display name when the profile has no name or email.
  @override
  String get fallbackUserName => 'مستخدم';

  /// AppBar title of the profile screen.
  @override
  String get profileTitle => 'الملف الشخصي';

  /// Tooltip for the language toggle action (shows the target language).
  @override
  String get toggleLanguageTooltip => 'English';

  /// Button under the profile header that opens the edit-profile sheet.
  @override
  String get editDetailsAction => 'تعديل البيانات';

  /// Label over the wallet balance on the profile wallet card.
  @override
  String get availableBalanceLabel => 'الرصيد المتاح';

  /// Profile menu item that opens the trip history screen.
  @override
  String get myTripsLabel => 'رحلاتي';

  /// Profile menu item that opens the saved-places screen.
  @override
  String get savedPlacesLabel => 'الأماكن المحفوظة';

  /// AppBar title of the settings screen and its profile menu item.
  @override
  String get settingsTitle => 'الإعدادات';

  /// Theme-mode dropdown option that follows the device setting.
  @override
  String get themeSystem => 'تلقائي';

  /// Theme-mode dropdown option for the light theme.
  @override
  String get themeLight => 'فاتح';

  /// Theme-mode dropdown option for the dark theme.
  @override
  String get themeDark => 'داكن';

  // ── Rider — Help & invite ───────────────────────────────────────

  /// AppBar title of the help screen.
  @override
  String get helpCenterTitle => 'مركز المساعدة';

  /// Headline on the help screen contact-support card.
  @override
  String get needHelpTitle => 'تحتاج مساعدة؟';

  /// Sub-line under the help contact-support headline.
  @override
  String get supportAvailableBody => 'فريق الدعم متاح 24/7';

  /// Button on the help card that contacts support.
  @override
  String get contactAction => 'تواصل';

  /// SnackBar shown after tapping the help contact button.
  @override
  String get supportContactSoonMessage => 'سيتم التواصل معك قريبًا';

  /// Section heading above the FAQ list on the help screen.
  @override
  String get faqTitle => 'الأسئلة الشائعة';

  /// AppBar title of the invite/referral screen.
  @override
  String get inviteFriendsTitle => 'دعوة الأصدقاء';

  /// Headline on the invite hero card.
  @override
  String get inviteHeroTitle => 'ادعُ أصدقاءك واربح';

  /// Sub-line on the invite hero card explaining the reward.
  @override
  String get inviteHeroSubtitle => 'احصل على 20 ج.م لكل صديق يستخدم كودك';

  /// Label above the referral code value on the invite screen.
  @override
  String get referralCodeLabel => 'كود الدعوة';

  /// Label for the referral credits stat card.
  @override
  String get yourCreditsLabel => 'رصيدك';

  /// Label for the invited-friends count stat card.
  @override
  String get friendsInvitedLabel => 'أصدقاء دُعوا';

  /// Primary share button on the invite screen.
  @override
  String get shareCodeAction => 'مشاركة الكود';

  /// Share-sheet body on the invite screen; {code} is the referral code.
  @override
  String inviteShareMessage(String code) => 'حمّل تطبيق GoDrive واستخدم كود الدعوة $code لتحصل على رصيد مجاني:
https://go.synapticstudio.tech';

  // ── Rider — Splash ──────────────────────────────────────────────

  /// Tagline under the splash brand mark.
  @override
  String get splashTagline => 'رحلتك، بسعرك';

  /// Attribution line above the studio badge on the splash screen.
  @override
  String get createdByLabel => 'Created by';

  /// Studio name on the splash attribution badge.
  @override
  String get synapticStudioLabel => 'Synaptic Studio';
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

  // ── Rider — Wallet & top-up ─────────────────────────────────────

  /// Label above the wallet balance amount.
  @override
  String get availableBalance => 'Available balance';

  /// Fallback title for a wallet transaction with no description.
  @override
  String get transactionFallback => 'Transaction';

  /// App-bar title of the top-up screen and wallet top-up button.
  @override
  String get topUpTitle => 'Top up wallet';

  /// App-bar title of the Paymob payment WebView screen.
  @override
  String get paymentTitle => 'Payment';

  /// Instruction above the top-up amount text field.
  @override
  String get topUpAmountPrompt => 'Enter the amount to top up';

  /// Primary button that starts the Paymob top-up flow.
  @override
  String get continuePayment => 'Continue to payment';

  // ── Rider — Trip history ────────────────────────────────────────

  /// App-bar title of the ride history screen.
  @override
  String get tripHistoryTitle => 'Trip history';

  /// Empty-state body when the rider has no trip history.
  @override
  String get noPastTrips => 'No past trips';

  /// Status chip for a completed trip in history.
  @override
  String get tripCompleted => 'Completed';

  /// Status chip for a cancelled trip in history.
  @override
  String get tripCancelled => 'Cancelled';

  /// App-bar title of the trip detail screen.
  @override
  String get tripDetailTitle => 'Trip details';

  /// Empty-state title when the requested trip does not exist.
  @override
  String get tripNotFound => 'Trip not found';

  /// Section heading for the trip route card.
  @override
  String get tripRouteTitle => 'Route';

  /// Route-card meta showing the trip distance in kilometres.
  @override
  String tripDistanceKmLine(String km) => '$km km';

  /// Route-card meta showing the trip duration in minutes.
  @override
  String tripDurationMinutes(int minutes) => '$minutes min';

  /// Section heading for the fare breakdown card.
  @override
  String get tripFareDetailsTitle => 'Fare details';

  /// Fare-breakdown row for the applied discount.
  @override
  String get tripDiscountLabel => 'Discount';

  /// Fare-breakdown row for the final total.
  @override
  String get tripTotalLabel => 'Total';

  // ── Rider — Safety & SOS ────────────────────────────────────────

  /// Title of the SOS confirmation dialog.
  @override
  String get sosWarningTitle => 'Warning';

  /// Body of the SOS confirmation dialog.
  @override
  String get sosConfirmMessage => 'Are you sure you want to activate emergency mode? Your location will be sent to authorities and app administrators.';

  /// Destructive confirm button in the SOS dialog.
  @override
  String get sosConfirmAction => 'Confirm emergency';

  /// Error when device location services are disabled during SOS.
  @override
  String get sosLocationServiceError => 'Enable location services to send the emergency alert';

  /// Error when location permission is denied during SOS.
  @override
  String get sosLocationPermissionError => 'Allow the app to access your location to send the emergency alert';

  /// Error when GPS position cannot be resolved during SOS.
  @override
  String get sosLocationUnavailableError => 'Could not determine your location. Try again in an open area';

  /// Snack-bar after a successful SOS post.
  @override
  String get sosSentSuccess => 'Emergency alert sent successfully with your location';

  /// Error when the share-trip endpoint returns no URL.
  @override
  String get shareTripError => 'Could not create trip tracking link';

  /// Prefix of the share sheet message; the URL is appended.
  @override
  String get shareTripMessage => 'Track my trip on GoDrive via this link:
';

  /// Hint under the SOS panic button.
  @override
  String get sosEmergencyOnlyHint => 'Press the button above only in a real emergency';

  /// Button that shares the live-trip tracking link.
  @override
  String get shareTripDetails => 'Share trip details';

  // ── Rider — Notifications ───────────────────────────────────────

  /// App-bar title of the notifications center.
  @override
  String get notificationsTitle => 'Notifications';

  /// Action that clears all unread notification badges.
  @override
  String get markAllRead => 'Mark all as read';

  /// Empty-state title when there are no notifications.
  @override
  String get noNotifications => 'No notifications';

  /// Empty-state subtitle under noNotifications.
  @override
  String get notificationsWillAppearHere => 'Your notifications will appear here';

  // ── Rider — Saved places ────────────────────────────────────────

  /// App-bar title of the saved places screen.
  @override
  String get savedPlacesTitle => 'Saved places';

  /// Fallback label when a saved place has no name.
  @override
  String get placeFallback => 'Place';

  /// Empty-state title when no places are saved.
  @override
  String get noSavedPlaces => 'No saved places';

  /// Empty-state subtitle prompting to add home/work.
  @override
  String get addHomeWorkHint => 'Add home or work for a quick ride request';

  /// App-bar title of the map-based location picker.
  @override
  String get pickLocationTitle => 'Pick location';

  /// Hint inside the place-name text field.
  @override
  String get placeNameHint => 'Place name (Home, Work...)';

  /// Hint shown before the reverse-geocoded address resolves.
  @override
  String get moveMapToPick => 'Move the map to pick a location';

  /// Primary button that confirms the picked place.
  @override
  String get savePlace => 'Save place';

  /// Snack-bar when the device-location action in the search sheet fails.
  @override
  String get locationPermissionDenied => 'Enable location permission to use your device location';

  // ── Rider — Captain offers (bids sheet) ─────────────────────────

  /// Generic retry action shown after a failed load (e.g. the bids sheet error state).
  @override
  String get retryAction => 'Retry';

  /// Offline error body shown when a network call fails with no connectivity.
  @override
  String get checkConnectionError => 'Check your internet connection';

  /// Toast shown when a request fails due to a connection problem.
  @override
  String get connectionRetryError => 'Could not connect, try again';

  /// Bids-sheet error when the offers request returns a non-200 status; {code} is the HTTP status code.
  @override
  String bidsLoadErrorWithCode(String code) => 'Could not load offers ($code)';

  /// Fallback toast when accepting a captain's bid fails and the server sent no message.
  @override
  String get bidAcceptFailedError => 'Could not accept the offer, try again';

  /// Header title of the captain offers (bids) sheet.
  @override
  String get bidsChooseCaptainTitle => 'Choose a captain';

  /// Subtitle under the bids-sheet title reassuring the rider about captain verification.
  @override
  String get bidsAllCaptainsVerified => 'All captains are verified';

  /// Destructive button in the bids-sheet header that cancels the whole trip request.
  @override
  String get bidsCancelRequestAction => 'Cancel request';

  /// Fallback captain display name on a bid card when the API sends no name.
  @override
  String get bidsCaptainFallback => 'GoDrive Captain';

  /// Bid-card chip showing how many minutes until the captain can arrive.
  @override
  String bidsEtaMinutes(String minutes) => '$minutes min';

  /// Bid-card meta showing the captain's completed trip count next to the rating.
  @override
  String bidsTripCount(int count) => '$count trips';

  /// Primary button on a bid card that accepts the captain's offer.
  @override
  String get bidAcceptAction => 'Accept';

  /// Secondary button on a bid card that dismisses the captain's offer.
  @override
  String get bidDeclineAction => 'Decline';

  /// Bids-sheet title while waiting for the first captain offer to arrive.
  @override
  String get bidsSearchingTitle => 'Searching for nearby captains';

  /// Bids-sheet subtitle under the searching title.
  @override
  String get bidsSearchingSubtitle => 'Price offers will appear here as soon as captains respond';

  // ── Rider — Payment methods ─────────────────────────────────────

  /// App-bar title of the payment methods screen.
  @override
  String get paymentMethodsTitle => 'Payment methods';

  /// Payment method row: pay the captain in cash.
  @override
  String get paymentCashTitle => 'Cash';

  /// Subtitle under the cash payment method row.
  @override
  String get paymentCashSubtitle => 'Pay the captain directly';

  /// Payment method row: pay from the in-app wallet balance.
  @override
  String get paymentWalletTitle => 'Wallet';

  /// Subtitle under the wallet payment method showing the current balance.
  @override
  String paymentWalletBalanceLine(String balance) => 'Balance: $balance EGP';

  /// Button on the wallet payment row that navigates to the wallet top-up screen.
  @override
  String get paymentTopUpAction => 'Top up';

  /// Payment method row: pay with a bank card.
  @override
  String get paymentCardTitle => 'Bank card';

  /// Subtitle under the bank-card payment method row.
  @override
  String get paymentCardSubtitle => 'Add a card via Paymob';

  /// Button on the bank-card payment row that starts the add-card flow.
  @override
  String get paymentAddAction => 'Add';

  /// Toast shown when the rider taps add-card before the Paymob flow is live.
  @override
  String get paymentCardComingSoonToast => 'Card payments are coming soon';

  /// Section heading above the payment methods explanatory note.
  @override
  String get paymentNoteTitle => 'Note';

  /// Explanatory note at the bottom of the payment methods screen.
  @override
  String get paymentNoteBody => 'You can change your default payment method at any time. It will be used automatically on your upcoming trips.';

  // ── Rider — Promo codes ─────────────────────────────────────────

  /// App-bar title of the promo codes screen.
  @override
  String get promoTitle => 'Promo codes';

  /// Hint text inside the promo-code entry field.
  @override
  String get promoCodeHint => 'Enter a promo code';

  /// Button that validates and applies the entered promo code.
  @override
  String get promoApplyAction => 'Apply';

  /// Success toast after a promo code validates; {amount} is the discount.
  @override
  String promoAppliedToast(String amount) => 'Code applied! $amount EGP off';

  /// Error toast when the entered promo code fails validation.
  @override
  String get promoInvalidToast => 'Invalid or expired code';

  /// Empty-state title when the rider has no active promo codes.
  @override
  String get promoEmptyTitle => 'No active codes';

  /// Empty-state subtitle prompting the rider to enter a code.
  @override
  String get promoEmptySubtitle => 'Enter a promo code to benefit from offers';

  /// Promo card value line for a percentage discount.
  @override
  String promoDiscountPercent(int percent) => '$percent% off';

  /// Promo card value line for a fixed-amount discount.
  @override
  String promoDiscountFixed(String amount) => '$amount EGP off';

  /// Promo card line showing the code's expiry date.
  @override
  String promoExpiresLine(String date) => 'Expires $date';

  // ── Rider — Rating sheet ────────────────────────────────────────

  /// Title of the post-trip rating sheet.
  @override
  String get ratingTitle => 'How was your trip?';

  /// Subtitle under the rating title naming the captain being rated.
  @override
  String ratingCaptainLine(String name) => 'Rate $name';

  /// Hint text inside the optional rating comment field.
  @override
  String get ratingCommentHint => 'Additional comment (optional)';

  /// Primary button that submits the star rating.
  @override
  String get ratingSubmitAction => 'Submit rating';

  /// Quiet button that dismisses the rating sheet without rating.
  @override
  String get ratingSkipAction => 'Skip';

  /// Quick rating tag: the captain drove safely.
  @override
  String get ratingTagSafeDriving => 'Safe driving';

  /// Quick rating tag: the captain was polite.
  @override
  String get ratingTagPoliteCaptain => 'Polite captain';

  /// Quick rating tag: the car was clean.
  @override
  String get ratingTagCleanCar => 'Clean car';

  /// Quick rating tag: the captain was punctual.
  @override
  String get ratingTagOnTime => 'On time';

  /// Quick rating tag: the in-car music was pleasant.
  @override
  String get ratingTagComfortableMusic => 'Comfortable music';

  /// Toast prefix when submitting a rating fails; {error} is the exception.
  @override
  String ratingErrorPrefix(String error) => 'Error: $error';

  // ── Rider — Schedule a ride ─────────────────────────────────────

  /// App-bar title of the ride scheduling screen.
  @override
  String get scheduleTitle => 'Schedule a ride';

  /// Help text on the date picker when scheduling a ride.
  @override
  String get schedulePickDateHelp => 'Pick the trip date';

  /// Help text on the time picker when scheduling a ride.
  @override
  String get schedulePickTimeHelp => 'Pick the trip time';

  /// Info card explaining how scheduled rides are dispatched.
  @override
  String get scheduleInfoNote => 'A captain will be dispatched automatically 10 minutes before your trip.';

  /// Label above the date selector on the scheduling screen.
  @override
  String get scheduleDateLabel => 'Date';

  /// Label above the time selector on the scheduling screen.
  @override
  String get scheduleTimeLabel => 'Time';

  /// Summary line showing the chosen scheduled date and time.
  @override
  String scheduleSummaryLine(String dateTime) => 'Trip time: $dateTime';

  /// Primary button that confirms the scheduled ride.
  @override
  String get scheduleConfirmAction => 'Schedule the trip';

  // ── Rider — Home & map picking ──────────────────────────────────

  /// Label for the option that resolves the pickup from the device GPS fix.
  @override
  String get currentLocationGps => 'Current location (GPS)';

  /// Name of the language the toggle will switch TO (shown in the current locale's other language).
  @override
  String get otherLanguageName => 'العربية';

  @override
  String get toggleThemeTooltip => 'Toggle theme';

  /// Tooltip for the floating button that recentres the map on the device location.
  @override
  String get myLocationTooltip => 'My Location';

  /// Tooltip for back buttons.
  @override
  String get backTooltip => 'Back';

  /// Tooltip/helper for the pickup field on the home screen.
  @override
  String get setPickupPoint => 'Set Pickup Point';

  /// Tooltip/helper for the destination field on the home screen.
  @override
  String get setDestinationPoint => 'Set Destination Point';

  /// Hint shown in the empty pickup field on the home screen.
  @override
  String get whereFromHint => 'Where from?';

  /// Hint shown in the empty destination field on the home screen.
  @override
  String get whereToHint => 'Where to?';

  /// Tooltip for the button that swaps the two trip endpoints.
  @override
  String get swapLocationsTooltip => 'Swap pickup and destination';

  /// Primary action that confirms the point being set via map pan.
  @override
  String get continueAction => 'Continue';

  /// Inline status while the route between the two points is being fetched.
  @override
  String get calculatingRoute => 'Calculating route…';

  /// Marker for values (distance/ETA/fare) that are approximate.
  @override
  String get approximateLabel => 'Approximate';

  /// Instruction banner shown while the map-pan point-selection mode is active.
  @override
  String get moveMapToSetPoint => 'Move the map to set the point';

  /// SnackBar shown after confirming the pickup point on the map.
  @override
  String get confirmPickup => 'Pickup point set';

  /// SnackBar shown after confirming the destination point on the map.
  @override
  String get confirmDestination => 'Destination point set';

  // ── Rider — Location search sheet ───────────────────────────────

  /// Message shown when the places search endpoint fails.
  @override
  String get searchUnavailable => 'Search is unavailable right now, check your connection';

  /// Label for the pickup end of the trip.
  @override
  String get pickupPointLabel => 'Pickup point';

  /// Label for the destination end of the trip.
  @override
  String get destinationLabel => 'Destination';

  /// Hint inside the search sheet field when resolving the pickup.
  @override
  String get searchPickupHint => 'Search for pickup';

  /// Hint inside the search sheet field when resolving the destination.
  @override
  String get searchDestinationHint => 'Search for destination';

  /// Empty state when a places query returns no results.
  @override
  String get noPlacesFound => 'No places found';

  /// Suggestion shown under the no-results empty state.
  @override
  String get trySimplerNameOrMap => 'Try a simpler name or set it on the map';

  /// Section heading above the places search results.
  @override
  String get resultsSection => 'Search results';

  /// Section heading above the popular-places list in the search sheet.
  @override
  String get popularPlacesSection => 'Popular places';

  /// Button that switches from search to map-pan point selection.
  @override
  String get setOnMapAction => 'Set on map';

  /// Sub-line explaining the set-on-map fallback when search cannot find a place.
  @override
  String get setOnMapSubtitle => 'Set the location manually on the map';

  /// Address label used for a point resolved from the device GPS fix.
  @override
  String get myCurrentLocation => 'My current location';

  /// Button in the search sheet that fills the point from GPS.
  @override
  String get useDeviceLocation => 'Use device location';

  // ── Rider — Travel mode bar ─────────────────────────────────────

  /// Tooltip for returning to the rides tab.
  @override
  String get backToRidesTooltip => 'Back to rides';

  /// Bottom-bar tab that opens the trip-planning flow.
  @override
  String get travelTabTrip => 'Trip';

  /// Bottom-bar tab that opens the orders/activity list.
  @override
  String get travelTabOrders => 'Orders';

  // ── Rider — Login & sign-up ─────────────────────────────────────

  /// Label on the language chip — names the language it will switch to.
  @override
  String get languageChipLabel => 'عربي';

  /// Headline on the sign-in form.
  @override
  String get loginWelcomeBackTitle => 'Welcome back';

  /// Headline on the sign-up form.
  @override
  String get loginCreateAccountTitle => 'Create a new account';

  /// Sub-line under the sign-in headline.
  @override
  String get loginSignInSubtitle => 'Sign in to continue';

  /// Sub-line under the sign-up headline.
  @override
  String get loginSignUpSubtitle => 'Create your account and start your first trip';

  /// Hint for the full-name field on the sign-up form.
  @override
  String get loginFullNameHint => 'Full name';

  /// Hint for the phone field on the sign-up form.
  @override
  String get loginPhoneHint => 'Phone number';

  /// Hint for the email field on the login screen.
  @override
  String get loginEmailHint => 'Email address';

  /// Hint for the password field on the login screen.
  @override
  String get loginPasswordHint => 'Password';

  /// Checkbox label for accepting the terms on the sign-up form.
  @override
  String get loginTermsLabel => 'I agree to the Terms & Conditions';

  /// Primary button on the sign-in form.
  @override
  String get loginSignInAction => 'Sign in';

  /// Primary button on the sign-up form.
  @override
  String get loginCreateAccountAction => 'Create account';

  /// Generic sign-up action label.
  @override
  String get loginSignUpAction => 'Sign up';

  /// Link that switches the sign-up form back to sign-in.
  @override
  String get loginAlreadyHaveAccount => 'Already have an account? Sign in';

  /// Link that switches the sign-in form to sign-up.
  @override
  String get loginNoAccount => 'No account? Create one';

  /// Validation message for the email/password fields.
  @override
  String get loginEnterEmailPassword => 'Enter a valid email and password';

  /// Validation message for the name/phone fields.
  @override
  String get loginEnterValidNamePhone => 'Enter a valid name and phone number';

  /// SnackBar shown when signing up without accepting the terms.
  @override
  String get loginMustAcceptTerms => 'You must accept the Terms & Conditions';
  @override
  String get loginOrContinueWith => 'Or continue with';
  @override
  String get loginSocialComingSoon => 'Social sign-in coming soon';
  @override
  String get loginHeroSafetyTitle => 'Your safety is our priority';
  @override
  String get loginHeroSafetyBody =>
      'Every captain is verified, and the SOS button is available on every trip';
  @override
  String get loginHeroPriceTitle => 'Name your own price';
  @override
  String get loginHeroPriceBody =>
      'Set your own fare — captains send their offers, you decide';

  // ── Rider — Fare estimate sheet ─────────────────────────────────

  /// Title of the fare-estimate bottom sheet.
  @override
  String get tripDetailsTitle => 'Trip details';

  /// Label for the payment method row on the fare sheet.
  @override
  String get paymentMethodLabel => 'Payment method';

  /// Cash payment method label.
  @override
  String get paymentCash => 'Cash';

  /// Primary button that dispatches the ride request with the rider's offer.
  @override
  String get requestRideAction => 'Request ride';

  /// Fallback label when the pickup address is not yet resolved.
  @override
  String get pickupPointFallback => 'Pickup point';

  /// Fallback label when the destination address is not yet resolved.
  @override
  String get destinationPointFallback => 'Destination';

  /// Label for the system-suggested fare on the fare sheet.
  @override
  String get estimatedLabel => 'Suggested price';

  /// Status shown while the fare estimate is being fetched.
  @override
  String get calculatingFare => 'Calculating fare…';

  /// Error shown when the fare estimate request fails.
  @override
  String get fareLoadError => 'Could not load the fare, try again';

  /// Retry button on the fare error state.
  @override
  String get tryAgainAction => 'Try again';

  /// Label above the rider's editable fare offer.
  @override
  String get yourOfferLabel => 'Your offer';

  /// Button that resets the rider's offer to the suggested fare.
  @override
  String get resetToSuggestedAction => 'Reset to suggested price';

  /// Accessibility label for the offer minus button.
  @override
  String get decreasePriceSemantic => 'Decrease price';

  /// Accessibility label for the offer plus button.
  @override
  String get increasePriceSemantic => 'Increase price';

  /// Hint shown when no suggested fare is available to anchor the offer.
  @override
  String get offerHintNoSuggestion => 'No suggested price yet — enter your offer';

  /// Hint when the rider's offer equals the suggested fare.
  @override
  String offerHintFairPrice(int s) => 'Your offer matches the suggested price — a fair price';

  /// Hint when the rider's offer is above the suggested fare.
  @override
  String offerHintAbove(int d, int s) => 'Your offer is above the suggestion — more likely to be accepted';

  /// Hint when the rider's offer is below the suggested fare.
  @override
  String offerHintBelow(int d, int s) => 'Your offer is below the suggestion — acceptance may take longer';

  // ── Rider — Profile & settings ──────────────────────────────────

  /// Title of the edit-profile bottom sheet.
  @override
  String get editProfileInfoTitle => 'Edit Profile Information';

  /// Label for the full-name field in the edit-profile sheet.
  @override
  String get fullNameLabel => 'Full Name';

  /// Label for the phone field in the edit-profile sheet.
  @override
  String get phoneNumberLabel => 'Phone Number';

  /// Label for the locked email field in the edit-profile sheet.
  @override
  String get emailReadOnlyLabel => 'Email Address (read only)';

  /// SnackBar shown after the profile is saved successfully.
  @override
  String get profileUpdatedSuccess => 'Profile updated successfully';

  /// Primary save button in the edit-profile sheet.
  @override
  String get saveChangesAction => 'Save Changes';

  /// Title of the avatar-picker bottom sheet.
  @override
  String get changeProfilePictureTitle => 'Change Profile Picture';

  /// Button in the avatar picker to choose a new photo.
  @override
  String get chooseNewPhotoAction => 'Choose New Photo';

  /// Fallback display name when the profile has no name or email.
  @override
  String get fallbackUserName => 'User';

  /// AppBar title of the profile screen.
  @override
  String get profileTitle => 'Profile';

  /// Tooltip for the language toggle action (shows the target language).
  @override
  String get toggleLanguageTooltip => 'العربية';

  /// Button under the profile header that opens the edit-profile sheet.
  @override
  String get editDetailsAction => 'Edit Details';

  /// Label over the wallet balance on the profile wallet card.
  @override
  String get availableBalanceLabel => 'Available Balance';

  /// Profile menu item that opens the trip history screen.
  @override
  String get myTripsLabel => 'My Trips';

  /// Profile menu item that opens the saved-places screen.
  @override
  String get savedPlacesLabel => 'Saved Places';

  /// AppBar title of the settings screen and its profile menu item.
  @override
  String get settingsTitle => 'Settings';

  /// Theme-mode dropdown option that follows the device setting.
  @override
  String get themeSystem => 'System';

  /// Theme-mode dropdown option for the light theme.
  @override
  String get themeLight => 'Light';

  /// Theme-mode dropdown option for the dark theme.
  @override
  String get themeDark => 'Dark';

  // ── Rider — Help & invite ───────────────────────────────────────

  /// AppBar title of the help screen.
  @override
  String get helpCenterTitle => 'Help Center';

  /// Headline on the help screen contact-support card.
  @override
  String get needHelpTitle => 'Need help?';

  /// Sub-line under the help contact-support headline.
  @override
  String get supportAvailableBody => 'Support team available 24/7';

  /// Button on the help card that contacts support.
  @override
  String get contactAction => 'Contact';

  /// SnackBar shown after tapping the help contact button.
  @override
  String get supportContactSoonMessage => 'We will contact you soon';

  /// Section heading above the FAQ list on the help screen.
  @override
  String get faqTitle => 'Frequently Asked Questions';

  /// AppBar title of the invite/referral screen.
  @override
  String get inviteFriendsTitle => 'Invite Friends';

  /// Headline on the invite hero card.
  @override
  String get inviteHeroTitle => 'Invite your friends and earn';

  /// Sub-line on the invite hero card explaining the reward.
  @override
  String get inviteHeroSubtitle => 'Get 20 EGP for every friend who uses your code';

  /// Label above the referral code value on the invite screen.
  @override
  String get referralCodeLabel => 'Referral Code';

  /// Label for the referral credits stat card.
  @override
  String get yourCreditsLabel => 'Your Credits';

  /// Label for the invited-friends count stat card.
  @override
  String get friendsInvitedLabel => 'Friends Invited';

  /// Primary share button on the invite screen.
  @override
  String get shareCodeAction => 'Share Code';

  /// Share-sheet body on the invite screen; {code} is the referral code.
  @override
  String inviteShareMessage(String code) => 'Download the GoDrive app and use my invite code $code for free credit:
https://go.synapticstudio.tech';

  // ── Rider — Splash ──────────────────────────────────────────────

  /// Tagline under the splash brand mark.
  @override
  String get splashTagline => 'Your trip, your price';

  /// Attribution line above the studio badge on the splash screen.
  @override
  String get createdByLabel => 'Created by';

  /// Studio name on the splash attribution badge.
  @override
  String get synapticStudioLabel => 'Synaptic Studio';
}

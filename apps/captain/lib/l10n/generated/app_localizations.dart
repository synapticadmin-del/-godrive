import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In ar, this message translates to:
  /// **'GoDrive Captain'**
  String get appTitle;

  /// No description provided for @appSlogan.
  ///
  /// In ar, this message translates to:
  /// **'اربح أكثر، طريقك أخضر'**
  String get appSlogan;

  /// No description provided for @login.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get login;

  /// No description provided for @loginSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رقم موبايلك للدخول'**
  String get loginSubtitle;

  /// No description provided for @phoneNumber.
  ///
  /// In ar, this message translates to:
  /// **'رقم الموبايل'**
  String get phoneNumber;

  /// No description provided for @phoneNumberHint.
  ///
  /// In ar, this message translates to:
  /// **'01xxxxxxxxx'**
  String get phoneNumberHint;

  /// No description provided for @sendOtp.
  ///
  /// In ar, this message translates to:
  /// **'إرسال الرمز'**
  String get sendOtp;

  /// No description provided for @otp.
  ///
  /// In ar, this message translates to:
  /// **'رمز التحقق'**
  String get otp;

  /// No description provided for @otpHint.
  ///
  /// In ar, this message translates to:
  /// **'أدخل الرمز المرسل عبر واتساب'**
  String get otpHint;

  /// No description provided for @verifyOtp.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد'**
  String get verifyOtp;

  /// No description provided for @resendOtp.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إرسال'**
  String get resendOtp;

  /// No description provided for @goOnline.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ العمل'**
  String get goOnline;

  /// No description provided for @goOffline.
  ///
  /// In ar, this message translates to:
  /// **'إنهاء العمل'**
  String get goOffline;

  /// No description provided for @online.
  ///
  /// In ar, this message translates to:
  /// **'متصل'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In ar, this message translates to:
  /// **'غير متصل'**
  String get offline;

  /// No description provided for @earnings.
  ///
  /// In ar, this message translates to:
  /// **'أرباحي'**
  String get earnings;

  /// No description provided for @trips.
  ///
  /// In ar, this message translates to:
  /// **'رحلاتي'**
  String get trips;

  /// No description provided for @profile.
  ///
  /// In ar, this message translates to:
  /// **'حسابي'**
  String get profile;

  /// No description provided for @documents.
  ///
  /// In ar, this message translates to:
  /// **'المستندات'**
  String get documents;

  /// No description provided for @newOffer.
  ///
  /// In ar, this message translates to:
  /// **'رحلة جديدة'**
  String get newOffer;

  /// No description provided for @accept.
  ///
  /// In ar, this message translates to:
  /// **'قبول'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In ar, this message translates to:
  /// **'رفض'**
  String get decline;

  /// No description provided for @arrivingToPickup.
  ///
  /// In ar, this message translates to:
  /// **'في الطريق لموقف الراكب'**
  String get arrivingToPickup;

  /// No description provided for @arrivedAtPickup.
  ///
  /// In ar, this message translates to:
  /// **'وصلت لموقف الراكب'**
  String get arrivedAtPickup;

  /// No description provided for @startTrip.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الرحلة'**
  String get startTrip;

  /// No description provided for @completeTrip.
  ///
  /// In ar, this message translates to:
  /// **'إنهاء الرحلة'**
  String get completeTrip;

  /// No description provided for @riderName.
  ///
  /// In ar, this message translates to:
  /// **'اسم الراكب'**
  String get riderName;

  /// No description provided for @riderRating.
  ///
  /// In ar, this message translates to:
  /// **'تقييم الراكب'**
  String get riderRating;

  /// No description provided for @fare.
  ///
  /// In ar, this message translates to:
  /// **'الأجرة'**
  String get fare;

  /// No description provided for @distance.
  ///
  /// In ar, this message translates to:
  /// **'المسافة'**
  String get distance;

  /// No description provided for @duration.
  ///
  /// In ar, this message translates to:
  /// **'المدة'**
  String get duration;

  /// No description provided for @navigate.
  ///
  /// In ar, this message translates to:
  /// **'تنقل'**
  String get navigate;

  /// No description provided for @walletPayout.
  ///
  /// In ar, this message translates to:
  /// **'تسوية الأرباح'**
  String get walletPayout;

  /// No description provided for @nextPayout.
  ///
  /// In ar, this message translates to:
  /// **'التسوية القادمة'**
  String get nextPayout;

  /// No description provided for @uploadDocument.
  ///
  /// In ar, this message translates to:
  /// **'رفع مستند'**
  String get uploadDocument;

  /// No description provided for @license.
  ///
  /// In ar, this message translates to:
  /// **'رخصة القيادة'**
  String get license;

  /// No description provided for @idCard.
  ///
  /// In ar, this message translates to:
  /// **'بطاقة رقم قومي'**
  String get idCard;

  /// No description provided for @vehicleRegistration.
  ///
  /// In ar, this message translates to:
  /// **'رخصة السيارة'**
  String get vehicleRegistration;

  /// No description provided for @pendingApproval.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار الاعتماد'**
  String get pendingApproval;

  /// No description provided for @approved.
  ///
  /// In ar, this message translates to:
  /// **'معتمد'**
  String get approved;

  /// No description provided for @rejected.
  ///
  /// In ar, this message translates to:
  /// **'مرفوض'**
  String get rejected;

  /// No description provided for @verificationBanner.
  ///
  /// In ar, this message translates to:
  /// **'مستنداتك قيد المراجعة'**
  String get verificationBanner;

  /// No description provided for @loading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التحميل…'**
  String get loading;

  /// No description provided for @errorGeneric.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ، حاول مرة أخرى'**
  String get errorGeneric;

  /// No description provided for @confirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد'**
  String get confirm;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @logout.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get logout;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}

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
  /// **'Tempo'**
  String get appTitle;

  /// No description provided for @appSlogan.
  ///
  /// In ar, this message translates to:
  /// **'طريقك أخضر دايمًا'**
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

  /// No description provided for @home.
  ///
  /// In ar, this message translates to:
  /// **'الرئيسية'**
  String get home;

  /// No description provided for @history.
  ///
  /// In ar, this message translates to:
  /// **'رحلاتي'**
  String get history;

  /// No description provided for @wallet.
  ///
  /// In ar, this message translates to:
  /// **'المحفظة'**
  String get wallet;

  /// No description provided for @profile.
  ///
  /// In ar, this message translates to:
  /// **'حسابي'**
  String get profile;

  /// No description provided for @whereTo.
  ///
  /// In ar, this message translates to:
  /// **'إلى أين؟'**
  String get whereTo;

  /// No description provided for @pickup.
  ///
  /// In ar, this message translates to:
  /// **'موقف النزول'**
  String get pickup;

  /// No description provided for @destination.
  ///
  /// In ar, this message translates to:
  /// **'الوجهة'**
  String get destination;

  /// No description provided for @requestRide.
  ///
  /// In ar, this message translates to:
  /// **'اطلب رحلة'**
  String get requestRide;

  /// No description provided for @searchingCaptain.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث عن كابتن…'**
  String get searchingCaptain;

  /// No description provided for @eta.
  ///
  /// In ar, this message translates to:
  /// **'وقت الوصول'**
  String get eta;

  /// No description provided for @arrivingCaptain.
  ///
  /// In ar, this message translates to:
  /// **'الكابتن في الطريق إليك'**
  String get arrivingCaptain;

  /// No description provided for @tripInProgress.
  ///
  /// In ar, this message translates to:
  /// **'الرحلة جارية'**
  String get tripInProgress;

  /// No description provided for @completed.
  ///
  /// In ar, this message translates to:
  /// **'تم الوصول'**
  String get completed;

  /// No description provided for @cancelTrip.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الرحلة'**
  String get cancelTrip;

  /// No description provided for @fare.
  ///
  /// In ar, this message translates to:
  /// **'الأجرة'**
  String get fare;

  /// No description provided for @estimatedFare.
  ///
  /// In ar, this message translates to:
  /// **'الأجرة المتوقعة'**
  String get estimatedFare;

  /// No description provided for @cash.
  ///
  /// In ar, this message translates to:
  /// **'كاش'**
  String get cash;

  /// No description provided for @walletPay.
  ///
  /// In ar, this message translates to:
  /// **'من المحفظة'**
  String get walletPay;

  /// No description provided for @card.
  ///
  /// In ar, this message translates to:
  /// **'بطاقة'**
  String get card;

  /// No description provided for @payNow.
  ///
  /// In ar, this message translates to:
  /// **'ادفع الآن'**
  String get payNow;

  /// No description provided for @topUp.
  ///
  /// In ar, this message translates to:
  /// **'شحن المحفظة'**
  String get topUp;

  /// No description provided for @walletBalance.
  ///
  /// In ar, this message translates to:
  /// **'رصيد المحفظة'**
  String get walletBalance;

  /// No description provided for @addCredit.
  ///
  /// In ar, this message translates to:
  /// **'إضافة رصيد'**
  String get addCredit;

  /// No description provided for @safetySOS.
  ///
  /// In ar, this message translates to:
  /// **'زر الطوارئ'**
  String get safetySOS;

  /// No description provided for @shareTrip.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة الرحلة'**
  String get shareTrip;

  /// No description provided for @callCaptain.
  ///
  /// In ar, this message translates to:
  /// **'اتصال بالكابتن'**
  String get callCaptain;

  /// No description provided for @messageCaptain.
  ///
  /// In ar, this message translates to:
  /// **'مراسلة الكابتن'**
  String get messageCaptain;

  /// No description provided for @rateTrip.
  ///
  /// In ar, this message translates to:
  /// **'قيّم الرحلة'**
  String get rateTrip;

  /// No description provided for @promoCode.
  ///
  /// In ar, this message translates to:
  /// **'كود خصم'**
  String get promoCode;

  /// No description provided for @applyPromo.
  ///
  /// In ar, this message translates to:
  /// **'تطبيق الكود'**
  String get applyPromo;

  /// No description provided for @savedPlaces.
  ///
  /// In ar, this message translates to:
  /// **'الأماكن المحفوظة'**
  String get savedPlaces;

  /// No description provided for @addPlace.
  ///
  /// In ar, this message translates to:
  /// **'أضف مكانًا'**
  String get addPlace;

  /// No description provided for @vehicleType.
  ///
  /// In ar, this message translates to:
  /// **'نوع المركبة'**
  String get vehicleType;

  /// No description provided for @economy.
  ///
  /// In ar, this message translates to:
  /// **'اقتصادية'**
  String get economy;

  /// No description provided for @comfort.
  ///
  /// In ar, this message translates to:
  /// **'مريحة'**
  String get comfort;

  /// No description provided for @premium.
  ///
  /// In ar, this message translates to:
  /// **'بريميوم'**
  String get premium;

  /// No description provided for @scheduleForLater.
  ///
  /// In ar, this message translates to:
  /// **'جدولة لوقت لاحق'**
  String get scheduleForLater;

  /// No description provided for @scheduledAt.
  ///
  /// In ar, this message translates to:
  /// **'مجدولة في'**
  String get scheduledAt;

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

  /// No description provided for @noConnection.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد اتصال'**
  String get noConnection;

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

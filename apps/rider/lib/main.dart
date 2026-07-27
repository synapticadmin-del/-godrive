import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'services/app_state.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home/home_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Only transparency is set here. Status-bar icon brightness depends on the
  // active theme, so it is applied per-frame in the MaterialApp builder below.
  // Hardcoding `Brightness.light` here left near-invisible white-on-white
  // status icons whenever the rider was on the light theme.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  runApp(const RiderApp());
}

class RiderApp extends StatefulWidget {
  const RiderApp({super.key});

  @override
  State<RiderApp> createState() => _RiderAppState();
}

class _RiderAppState extends State<RiderApp> {
  /// The splash owns the intro; the app shell owns routing. We leave the
  /// splash mounted until it reports that the video has played in full AND
  /// the persisted session has finished restoring — whichever is slower.
  /// Without this the app would cut away mid-animation as soon as
  /// SharedPreferences returned.
  bool _introFinished = false;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(role: 'rider')..bootstrap(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'GoDrive',
            debugShowCheckedModeBanner: false,
            locale: state.locale,
            supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              // Status-bar icons must contrast against the app background, so
              // they invert with the theme: light (white) icons over the dark
              // theme, dark (black) icons over the light theme.
              final isDark = state.isDarkActive;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  statusBarBrightness:
                      isDark ? Brightness.dark : Brightness.light,
                  systemNavigationBarColor:
                      isDark ? AppTokens.nightBg : AppTokens.lightBg,
                  systemNavigationBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                ),
                child: Directionality(
                  textDirection: state.locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                  child: child!,
                ),
              );
            },
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            home: (state.loading || !_introFinished)
                ? SplashScreen(
                    onCompleted: () {
                      if (!_introFinished) {
                        setState(() => _introFinished = true);
                      }
                    },
                  )
                // A restored, non-expired session lands straight on Home;
                // LoginScreen is only reached when there is no valid session.
                : state.token == null
                    ? const LoginScreen()
                    : const HomeScreen(),
          );
        },
      ),
    );
  }
}
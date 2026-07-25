import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'services/captain_state.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home/main_shell.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const CaptainApp());
}

class CaptainApp extends StatelessWidget {
  const CaptainApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CaptainState()..bootstrap(),
      child: Consumer<CaptainState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'GoDrive Captain',
            debugShowCheckedModeBanner: false,
            locale: state.locale,
            supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              return Directionality(
                textDirection: state.locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              );
            },
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            home: state.loading
                ? const SplashScreen()
                : state.token == null
                    ? const LoginScreen()
                    : const MainShell(),
          );
        },
      ),
    );
  }
}
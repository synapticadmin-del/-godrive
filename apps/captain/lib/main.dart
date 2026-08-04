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

  // Draw behind the system bars so the map and the splash run edge to edge.
  // Icon brightness is *not* pinned here: it was previously hardcoded to
  // light, which rendered white status-bar icons on this app's white
  // surfaces and left the clock and battery invisible on most screens. Each
  // screen now declares its own overlay style to match its own canvas.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
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
            title: 'Tempo Captain',
            debugShowCheckedModeBanner: false,
            locale: state.locale,
            supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return Directionality(
                textDirection: state.locale.languageCode == 'ar'
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                // A driver glances at this screen in traffic. Honour the
                // system text scale so captains who need larger type get it,
                // but clamp the top end so the map chrome and the offer card
                // cannot blow their layouts apart.
                child: MediaQuery(
                  data: media.copyWith(
                    textScaler: media.textScaler.clamp(
                      minScaleFactor: 0.9,
                      maxScaleFactor: 1.3,
                    ),
                  ),
                  child: child!,
                ),
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

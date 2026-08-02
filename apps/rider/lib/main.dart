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
import 'screens/trip/trip_screen.dart';

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

  /// Guards the one-shot recovery push in [_maybeRecoverActiveTrip] so a
  /// rebuild cannot stack a second copy of the trip screen.
  bool _recoveryRouted = false;

  /// The app's navigator. Recovery pushes a route from the `Consumer` builder,
  /// which sits *above* the `Navigator` that `MaterialApp` creates and so has
  /// no `Navigator.of(context)` to reach for.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Puts a rider who force-quit mid-trip back into that trip.
  ///
  /// Pushed *on top of* `HomeScreen` rather than replacing it as the root: the
  /// rider must be able to back out to Home, and a root-level trip screen would
  /// make the system back gesture quit the app instead.
  ///
  /// Deferred to after the frame because it mutates the navigator, and called
  /// from `build` because that is where the bootstrap result first becomes
  /// visible. Signing out re-arms it so the next session can recover too.
  void _maybeRecoverActiveTrip(AppState state) {
    if (state.token == null) {
      _recoveryRouted = false;
      return;
    }
    // Wait for the splash to finish, or the push lands under it and the
    // cross-fade in _RootGate reveals Home on top of the trip.
    if (_recoveryRouted || state.loading || !_introFinished) return;

    final tripId = state.activeTripId;
    if (tripId == null) return;

    _recoveryRouted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => TripScreen(tripId: tripId)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(role: 'rider')..bootstrap(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          _maybeRecoverActiveTrip(state);
          return MaterialApp(
            title: 'GoDrive',
            navigatorKey: _navigatorKey,
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
            home: _RootGate(child: _resolveRoot(state)),
          );
        },
      ),
    );
  }

  /// Each destination is wrapped in a keyed subtree so the gate above can tell
  /// them apart. `KeyedSubtree` rather than a key on the screens themselves:
  /// identity belongs to the routing decision, not to the widgets, and this
  /// makes no assumption about the screens' constructors.
  Widget _resolveRoot(AppState state) {
    if (state.loading || !_introFinished) {
      return KeyedSubtree(
        key: const ValueKey('splash'),
        child: SplashScreen(
          onCompleted: () {
            if (!_introFinished) {
              setState(() => _introFinished = true);
            }
          },
        ),
      );
    }
    // A restored, non-expired session lands straight on Home; LoginScreen is
    // only reached when there is no valid session.
    return state.token == null
        ? const KeyedSubtree(key: ValueKey('login'), child: LoginScreen())
        : const KeyedSubtree(key: ValueKey('home'), child: HomeScreen());
  }
}

/// Cross-fades between the app's root destinations.
///
/// The splash used to be swapped out by a bare `setState` at the `home:` level,
/// so the brand mark vanished between two frames — a hard cut that threw away
/// the choreography the splash had just finished playing, and the single most
/// unfinished-feeling moment in the launch. Routing the swap through an
/// `AnimatedSwitcher` lets the splash dissolve while the destination settles in
/// underneath it. Sign-in to Home gets the same treatment for free.
///
/// This lives below `MaterialApp` rather than inline in `home:` because it
/// needs `MediaQuery` to honour the platform's reduce-motion setting, and
/// nothing above `MaterialApp` provides one.
class _RootGate extends StatelessWidget {
  const _RootGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 0 : 560),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // The default layout builder hands its children loose constraints, which
      // lets a full-page Scaffold collapse to nothing for the length of the
      // transition. Expanding the stack keeps both pages at full size while
      // they cross over.
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          // A whisper of scale. The outgoing page runs this in reverse, so the
          // splash eases back as it dissolves and the destination settles
          // forward — a handoff rather than a zoom.
          scale: Tween<double>(begin: 0.985, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:synaptic_go_captain/screens/onboarding/onboarding_screen.dart';
import 'package:synaptic_go_captain/screens/earnings/earnings_screen.dart';
import 'package:synaptic_go_captain/screens/profile/settings_screen.dart';
import 'package:synaptic_go_captain/screens/safety/sos_screen.dart';
import 'home_tab.dart';
import 'nearby_requests_screen.dart';
import 'trips_tab.dart';
import '../login_screen.dart';

/// The captain's main shell: a full-bleed map with floating chrome.
///
/// The map is live: it follows the captain, including heading, instead of
/// freezing on the first fix of the shift. It rides the SAME position stream
/// as [CaptainState]'s server location push (exposed as
/// [CaptainState.positionStream]) rather than opening a second GPS
/// subscription of its own — one GPS radio feeds both the map camera and the
/// server, which is the whole point of the shared stream.
///
/// The route is drawn from the trip's stored OSRM geometry
/// (`route_geometry`), i.e. the actual streets the captain will drive — not
/// a straight line drawn point-to-point between captain, pickup and dropoff
/// the way it used to be. If geometry is missing (an old trip row, or the
/// routing fallback), it degrades to that straight line rather than to no
/// line at all.
///
/// The bottom bar puts the map where a captain's attention already is: the
/// elevated centre slot is now "الخريطة" (the map itself), and "رحلات
/// متاحة" (the browsable queue of nearby requests) moved into the first
/// slot, next to the map, one tap away.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  final MapController _mapController = MapController();

  /// Tab order: 0 = رحلات متاحة (browse queue), 1 = رحلاتي, 2 = محفظة,
  /// 3 = حسابي, 4 = الخريطة (the live map — rendered in the bar's centre
  /// slot, which is where a ride-hailing map belongs).
  static const int _mapIndex = 4;

  /// The captain lands on the map: it is their workplace, not a menu entry.
  int _tabIndex = _mapIndex;
  LatLng? _currentLocation;
  double? _heading;
  bool _locating = true;
  bool _togglingOnline = false;

  /// True while the camera should chase the captain. Any manual pan releases
  /// it, so the map does not fight the captain's own gestures.
  bool _followMe = true;
  bool _mapReady = false;

  /// Parsed drive-route points for the active trip (from route_geometry).
  /// Empty when the trip carries no geometry — in that case the map falls
  /// back to the direct captain → pickup → dropoff polyline.
  List<LatLng> _routePoints = const [];
  String? _routeTripId;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<void>? _navStartSub;

  /// True while in-app turn-by-turn navigation is active — the camera hugs
  /// the captain at a tight zoom and a banner shows the next destination.
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CaptainState>().refreshMe();
    });
    _initLocation();
    _listenForNavigation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _navStartSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Forward app lifecycle transitions to [CaptainState], which pauses the
  /// GPS stream + offers polling while backgrounded and resumes them on
  /// return. The map just re-renders from the shared stream on the next fix.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    context.read<CaptainState>().handleAppLifecycleState(state);
  }

  /// Listen for in-app navigation requests from the active trip panel. When
  /// the captain taps "تنقّل للراكب", the shell flips to the map tab, forces
  /// follow-me at a tighter zoom, and marks the navigation session active so
  /// the camera hugs the captain and a banner shows the destination.
  void _listenForNavigation() {
    _navStartSub = context.read<CaptainState>().navigationStart.listen((_) {
      if (!mounted) return;
      final target = context.read<CaptainState>().navigationTarget;
      if (target == null) return;
      setState(() {
        _tabIndex = _mapIndex;
        _followMe = true;
        _navigating = true;
      });
      // Zoom in tighter than the default follow zoom so the captain sees
      // street-level turns, then keep following as GPS updates arrive.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mapReady && _currentLocation != null) {
          _mapController.move(_currentLocation!, 17.0);
        }
      });
    });
  }

  // -------------------------------------------------------------------
  // Location
  // -------------------------------------------------------------------

  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _locating = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locating = false);
        return;
      }

      // Show the last known fix immediately so the map is never empty while
      // the first fix is still resolving.
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null && mounted) _applyPosition(cached, recenter: true);

      // Seed an immediate fix for the first paint, then ride the shared
      // stream. Medium accuracy is enough here — the precise stream below
      // takes over for live tracking, and a cold high-accuracy fix can block
      // for seconds.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (!mounted) return;
      _applyPosition(position, recenter: true);

      _subscribeToPositionStream();
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _subscribeToPositionStream() {
    _positionSub?.cancel();
    // Subscribe to CaptainState's shared broadcast stream instead of opening
    // a second Geolocator.getPositionStream. The single underlying GPS
    // subscription lives in CaptainState, which also owns its accuracy
    // profile (idle ↔ trip) and lifecycle pausing — the map simply consumes
    // whatever fixes arrive. This removes the second always-on GPS radio the
    // shell used to keep hot just for the camera.
    _positionSub = context.read<CaptainState>().positionStream.listen(
      (position) {
        if (!mounted) return;
        _applyPosition(position, recenter: _followMe);
      },
      onError: (_) {},
    );
  }

  void _applyPosition(Position position, {bool recenter = false}) {
    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentLocation = point;
      // heading is NaN on devices without a compass fix; keep the last good
      // value rather than rotating the marker to an invalid angle.
      if (!position.heading.isNaN && position.heading >= 0) {
        _heading = position.heading;
      }
      _locating = false;
    });
    if (recenter && _mapReady) {
      // In navigation mode hug the captain at the tighter nav zoom; otherwise
      // keep the current zoom so a casual pan is not yanked back.
      final zoom = _navigating ? 17.0 : _mapController.camera.zoom;
      _mapController.move(point, zoom);
    }
  }

  // -------------------------------------------------------------------
  // Route geometry
  // -------------------------------------------------------------------

  /// Parses `route_geometry` — stored on the trip as a JSON string of
  /// `[[lat, lng], ...]` by the API at booking time (OSRM drive route).
  /// Parsed defensively: a bad payload degrades to "fall back to the direct
  /// line" rather than breaking a live trip.
  List<LatLng> _parseRouteGeometry(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String) {
      if (raw.isEmpty) return const [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    final points = <LatLng>[];
    for (final entry in decoded) {
      if (entry is! List || entry.length < 2) continue;
      final lat = (entry[0] as num?)?.toDouble();
      final lng = (entry[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  /// Recompute the route whenever the active trip (or its geometry) changes.
  void _syncRoute(CaptainState state) {
    final trip = state.activeTrip;
    final tripId = trip?['id'] as String?;
    if (tripId == _routeTripId) return;
    _routeTripId = tripId;
    _routePoints =
        trip == null ? const [] : _parseRouteGeometry(trip['route_geometry']);
  }

  // -------------------------------------------------------------------
  // Camera
  // -------------------------------------------------------------------

  void _recenter() {
    setState(() => _followMe = true);
    final target = _currentLocation;
    if (target == null) {
      _initLocation();
      return;
    }
    if (_mapReady) _mapController.move(target, 15.5);
  }

  /// Frames the captain plus the whole trip so the job is visible end to end.
  void _fitActiveTrip(CaptainState state) {
    final points = _framePoints(state);
    if (points.length < 2 || !_mapReady) return;
    setState(() => _followMe = false);
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(60, 140, 60, 320),
        maxZoom: 16,
      ),
    );
  }

  /// Points used for camera framing: the full drive route when available,
  /// otherwise captain + endpoints.
  List<LatLng> _framePoints(CaptainState state) {
    if (_routePoints.length >= 2) {
      return [..._routePoints, if (_currentLocation != null) _currentLocation!];
    }
    return _tripPoints(state, includeCaptain: true);
  }

  List<LatLng> _tripPoints(CaptainState state, {bool includeCaptain = false}) {
    final points = <LatLng>[];
    if (includeCaptain && _currentLocation != null) {
      points.add(_currentLocation!);
    }
    final trip = state.activeTrip;
    if (trip == null) return points;

    final pickup = _coord(trip['pickup_lat'], trip['pickup_lng']);
    if (pickup != null) points.add(pickup);
    final dropoff = _coord(trip['dropoff_lat'], trip['dropoff_lng']);
    if (dropoff != null) points.add(dropoff);
    return points;
  }

  /// Coordinates arrive from D1 as either integers or reals, so they are read
  /// as `num?` — a direct `as double` cast throws on an integer column.
  LatLng? _coord(dynamic lat, dynamic lng) {
    final a = (lat as num?)?.toDouble();
    final b = (lng as num?)?.toDouble();
    if (a == null || b == null) return null;
    return LatLng(a, b);
  }

  // -------------------------------------------------------------------
  // Online toggle
  // -------------------------------------------------------------------

  Future<void> _toggleOnline(bool value) async {
    if (_togglingOnline) return;
    setState(() => _togglingOnline = true);
    HapticFeedback.mediumImpact();

    final state = context.read<CaptainState>();
    final ok = await state.setOnline(value);

    if (!mounted) return;
    setState(() => _togglingOnline = false);

    if (!ok && state.gpsError != null) {
      _showGpsDialog(state.gpsError!);
    } else if (ok) {
      HapticFeedback.selectionClick();
      _recenter();
    }
  }

  void _showGpsDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.gps_off_rounded, color: AppTokens.warning, size: 32),
        title: Text(AppStrings.of(ctx).gpsErrorDialogTitle),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(ctx).gpsErrorOkAction),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, AppTokens.tapTarget),
            ),
            child: Text(AppStrings.of(ctx).gpsOpenSettingsAction),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();

    // Logout from any nested screen clears the token; without this check the
    // shell kept rendering the last frame over a dead session — the black
    // screen captains hit after signing out from the documents page.
    if (state.token == null) return const LoginScreen();

    // A captain who has not been approved yet cannot receive work, so the
    // document queue is the only meaningful screen for them. isApproved is
    // polled by CaptainState every 30s, so an admin approval flips this
    // without a cold restart.
    if (!state.isApproved) return const CaptainOnboardingScreen();

    final go = GoTheme.of(context);
    final onMapTab = _tabIndex == _mapIndex;

    _syncRoute(state);

    // End navigation mode when the trip is gone (completed or cancelled).
    if (_navigating && state.navigationTarget == null) {
      _navigating = false;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: go.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: go.isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: go.bg,
        body: Stack(
          children: [
            if (onMapTab) _buildMap(state, go),
            if (onMapTab && _locating) _buildLocatingVeil(go),

            Positioned.fill(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  // 0 — "رحلات متاحة": the browsable queue of nearby requests,
                  // one slot left of the map so the captain can flip between
                  // watching the road and hunting for work.
                  const NearbyRequestsScreen(),
                  const TripsTab(),
                  const EarningsScreen(),
                  const SettingsScreen(),
                  // 4 — the map itself. Appended after the four original
                  // destinations so their indices stay stable; it is surfaced
                  // in the bottom bar's centre slot via [centerDestination].
                  HomeTab(
                    mapController: _mapController,
                    online: state.online,
                    busy: _togglingOnline,
                    onToggleOnline: _toggleOnline,
                  ),
                ],
              ),
            ),

            if (onMapTab) _buildMapControls(state),
            if (onMapTab && _navigating && state.navigationTarget != null)
              _buildNavigationBanner(state, go),
          ],
        ),
        bottomNavigationBar: MainBottomNav(
          currentIndex: _tabIndex,
          onTap: (index) => setState(() => _tabIndex = index),
          // "رحلات متاحة" takes over the bar's first slot — with its live
          // badge — while the elevated centre destination becomes the map
          // itself (index 4), which is where a ride-hailing map belongs.
          firstDestination: NavFirstDestination(
            index: 0,
            label: AppStrings.of(context).availableTripsTitle,
            icon: Icons.explore_rounded,
            activeIcon: Icons.explore,
            // Live count of waiting offers, shown only while online — offline
            // the tab presents a go-online CTA rather than a list, so a count
            // would mislead. CaptainState clears `offers` when going offline.
            badgeCount: state.online ? state.offers.length : 0,
          ),
          centerDestination: NavCenterDestination(
            index: _mapIndex,
            label: AppStrings.of(context).mapNavLabel,
            icon: Icons.map_rounded,
          ),
        ),
      ),
    );
  }

  Widget _buildMap(CaptainState state, GoTheme go) {
    // Prefer the trip's stored drive route (actual streets). Fall back to the
    // direct captain → pickup → dropoff line only when geometry is absent,
    // so something is always drawn for an active trip.
    final fallback = _tripPoints(state, includeCaptain: true);
    final route = _routePoints.length >= 2 ? _routePoints : fallback;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(30.0444, 31.2357),
        initialZoom: 15.5,
        minZoom: 5,
        maxZoom: 18.5,
        backgroundColor: go.bg,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          if (!mounted) return;
          setState(() => _mapReady = true);
          if (_currentLocation != null) {
            _mapController.move(_currentLocation!, 15.5);
          }
        },
        // Any deliberate pan hands camera control back to the captain.
        onPointerDown: (_, __) {
          if (_followMe) setState(() => _followMe = false);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: AppTokens.mapTilesFor(
            go.isDark ? Brightness.dark : Brightness.light,
          ),
          subdomains: const ['a', 'b', 'c'],
          retinaMode: RetinaMode.isHighDensity(context),
          userAgentPackageName: AppTokens.mapUserAgent,
          tileBuilder: go.isDark ? darkModeTileBuilder : null,
        ),

        // The drive route along real streets. A casing stroke underneath keeps
        // the line legible over both pale streets and dark parkland.
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                strokeWidth: 9,
                color: Colors.white.withOpacity(go.isDark ? 0.22 : 0.9),
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
              Polyline(
                points: route,
                strokeWidth: 5,
                color: AppTokens.routeLine,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),

        MarkerLayer(markers: _buildMarkers(state)),

        RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          showFlutterMapAttribution: false,
          attributions: [TextSourceAttribution(AppTokens.mapAttribution)],
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(CaptainState state) {
    final markers = <Marker>[];

    final trip = state.activeTrip;
    if (trip != null) {
      final pickup = _coord(trip['pickup_lat'], trip['pickup_lng']);
      if (pickup != null) {
        markers.add(Marker(
          point: pickup,
          width: 40,
          height: 44,
          alignment: Alignment.topCenter,
          child: const TripEndpointMarker(
            color: AppTokens.primary,
            icon: Icons.person_rounded,
          ),
        ));
      }

      final dropoff = _coord(trip['dropoff_lat'], trip['dropoff_lng']);
      if (dropoff != null) {
        markers.add(Marker(
          point: dropoff,
          width: 40,
          height: 44,
          alignment: Alignment.topCenter,
          child: const TripEndpointMarker(
            color: AppTokens.danger,
            icon: Icons.flag_rounded,
          ),
        ));
      }
    }

    // Drawn last so the captain is never hidden under a trip pin.
    //
    // The marker is the shared top-down car (Uber-style) rather than the old
    // compass puck: rider, captain and admin now show the same vehicle
    // silhouette, and the GPS bearing still rotates it.
    if (_currentLocation != null) {
      markers.add(Marker(
        point: _currentLocation!,
        width: 54,
        height: 54,
        child: VehicleMapMarker(
          heading: _heading,
          color: state.online ? AppTokens.primary : AppTokens.lightMuted,
          size: 54,
        ),
      ));
    }

    return markers;
  }

  Widget _buildLocatingVeil(GoTheme go) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: (go.isDark ? Colors.black : Colors.white).withOpacity(0.45),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceLg,
                vertical: AppTokens.spaceMd,
              ),
              decoration: BoxDecoration(
                color: go.panel,
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                boxShadow: AppTokens.shadowFloating,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    AppStrings.of(context).locatingYou,
                    style: AppTokens.font(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: go.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A slim banner pinned to the top of the map during in-app navigation,
  /// naming the destination and offering a way out. It stays clear of the
  /// trip panel at the bottom so both are readable at a glance.
  Widget _buildNavigationBanner(CaptainState state, GoTheme go) {
    final target = state.navigationTarget!;
    final toPickup = target['toPickup'] == true;
    final strings = AppStrings.of(context);
    final label = toPickup ? strings.navBannerToRider : strings.navBannerToDestination;

    return PositionedDirectional(
      top: AppTokens.spaceMd,
      start: AppTokens.spaceMd,
      end: AppTokens.spaceMd,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: go.panel,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(color: go.border),
            boxShadow: AppTokens.shadowFloating,
          ),
          child: Row(
            children: [
              // go.action because this is an interactive indicator, not a brand mark
              Icon(Icons.navigation_rounded, color: go.action, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  label,
                  style: AppTokens.font(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  context.read<CaptainState>().stopInAppNavigation();
                  setState(() => _navigating = false);
                },
                child: Text(
                  strings.navEndAction,
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.danger,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Map chrome, stacked bottom-end above the sheet — within thumb reach of a
  /// phone in a dashboard mount, rather than in the far top corner.
  Widget _buildMapControls(CaptainState state) {
    final hasTrip = state.activeTrip != null;
    final go = GoTheme.of(context);

    return PositionedDirectional(
      end: AppTokens.spaceMd,
      bottom: hasTrip ? 300 : 190,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MapCircleButton(
            icon: Icons.sos_rounded,
            tooltip: AppStrings.of(context).sosTooltip,
            background: AppTokens.sos,
            iconColor: Colors.white,
            size: 50,
            iconSize: 24,
            onTap: () {
              HapticFeedback.heavyImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SosScreen()),
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceSm),
          if (hasTrip) ...[
            MapCircleButton(
              icon: Icons.route_rounded,
              tooltip: AppStrings.of(context).showFullTripTooltip,
              onTap: () => _fitActiveTrip(state),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
          MapCircleButton(
            icon: _followMe ? Icons.my_location_rounded : Icons.location_searching_rounded,
            tooltip: AppStrings.of(context).myLocationTooltip,
            // go.action for active/selected state, not a brand mark
            iconColor: _followMe ? go.action : null,
            onTap: _recenter,
          ),
        ],
      ),
    );
  }
}

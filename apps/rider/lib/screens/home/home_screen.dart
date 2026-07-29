import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/app_state.dart';
import '../../services/location_service.dart';
import '../history/history_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';
import 'fare_estimate_sheet.dart';
import 'location_search_sheet.dart';
import 'travel_mode_bottom_bar.dart';
import 'vehicle_selector.dart';

/// Which point the rider is currently choosing on the map.
enum PickMode { none, pickup, dropoff }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  int _tabIndex = 0;
  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

  String _pickupText = '';
  String _dropoffText = '';

  /// The driving route returned by the backend. When present we draw the real
  /// street-following geometry instead of a straight line.
  RoutePreview? _route;
  bool _loadingRoute = false;

  /// Centre-pin picking state.
  PickMode _pickMode = PickMode.none;
  String _pinAddress = '';
  bool _resolvingPin = false;

  /// Counter identifying the most recent reverse-geocode request.
  ///
  /// The debouncer stops us firing a request per frame, but it cannot recall
  /// one already in flight. Pan, pause, pan again and two lookups race: if the
  /// first is slower than the second it lands last and the rider ends up
  /// looking at the previous street name while the pin sits somewhere else.
  /// Each request captures the counter and only writes if it is still current.
  int _pinRequestId = 0;

  /// Online captains near the rider, drawn as cars on the map (Uber-style).
  ///
  /// Populated from `POST /trips/estimate`, which already returns the live
  /// nearby-captain list. We request a zero-length estimate anchored at the
  /// rider's position purely as a proximity probe — no trip is created and
  /// the fare fields are ignored. Refreshed on a slow timer so the cars drift
  /// as drivers move, without keeping a GPS or socket hot just for ambience.
  List<dynamic> _nearbyCaptains = const [];
  Timer? _nearbyTimer;

  /// Vehicle category shown in the top strip (رحلة / سفر / الشحن / تروسيكل).
  String _category = 'ride';

  /// True while the rider is arranging an intercity trip rather than a city
  /// ride. Drives which bottom bar is mounted.
  bool get _isTravelMode => _category == 'intercity';

  /// Active tab within travel mode. Ignored outside it.
  TravelTab _travelTab = TravelTab.trip;

  late final AnimationController _pulseController;
  late final LocationService _locations;
  final Debouncer _pinDebouncer = Debouncer(milliseconds: 450);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _locations = LocationService(context.read<AppState>());
    _determinePosition();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pinDebouncer.dispose();
    _nearbyTimer?.cancel();
    super.dispose();
  }

  // ───────────────────────────── location ─────────────────────────────

  /// Acquires the rider's position in two phases so the map is usable almost
  /// immediately instead of sitting on "جارٍ تحديد موقعك" for a full GPS fix.
  ///
  /// Phase 1 — the OS's last known position. This is already cached from
  /// whichever app used location most recently, so it returns in milliseconds
  /// with no radio work. It can be stale by a few streets, which is completely
  /// fine for centring a map, and it means the rider sees their neighbourhood
  /// right away.
  ///
  /// Phase 2 — a real fix, which then quietly corrects phase 1.
  ///
  /// Previously only phase 2 existed, called with no accuracy hint and no
  /// timeout, so a cold start blocked for the 10-30s a full satellite lock can
  /// take (and indefinitely indoors). Now the wait is bounded and never blocks
  /// first paint.
  Future<void> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      // ── Phase 1: instant warm start from the OS cache ──
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null && mounted) {
          _applyPosition(LatLng(cached.latitude, cached.longitude));
        }
      } catch (_) {
        // No cached fix available — phase 2 will supply the first position.
      }

      // ── Phase 2: authoritative fix, bounded so it cannot hang forever ──
      final position = await Geolocator.getCurrentPosition(
        // `medium` resolves far faster than the default `best` because it can
        // be served from wifi/cell triangulation instead of waiting on
        // satellites, and it is well within tolerance for a pickup pin.
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;

      _applyPosition(LatLng(position.latitude, position.longitude));
    } on TimeoutException {
      // A slow fix is not an error: phase 1 has very likely already centred
      // the map, and the rider can search or drop a pin regardless.
    } catch (_) {
      // Location is best-effort; the rider can still search or drop a pin.
    }
  }

  /// Centres the map on [latLng] and resolves a street name for it.
  ///
  /// Shared by both acquisition phases. The pickup pin is only *defaulted*
  /// (`??=`) so a refined phase-2 fix can never yank a pickup the rider has
  /// already chosen by hand out from under them.
  void _applyPosition(LatLng latLng) {
    final hadFix = _currentLocation != null;
    setState(() {
      _currentLocation = latLng;
      _pickupLocation ??= latLng;
    });
    _mapController.move(latLng, 15.5);

    // Resolve a human-readable address for the default pickup so the rider
    // sees a street name rather than "موقعي الحالي" with no context.
    if (_pickupText.isEmpty) {
      _resolvePickupLabel(latLng);
    }

    // First fix only: start the slow nearby-captains heartbeat so the cars
    // around the rider appear on the map (Uber-style). Skipped while the
    // rider is mid-pin-pick — the probe writes state and must not fight the
    // picking overlay.
    if (!hadFix) {
      _refreshNearbyCaptains(latLng);
      _nearbyTimer ??= Timer.periodic(
        const Duration(seconds: 45),
        (_) {
          final here = _currentLocation;
          if (here != null && mounted && _pickMode == PickMode.none) {
            _refreshNearbyCaptains(here);
          }
        },
      );
    }
  }

  /// Probes the backend for online captains around [at] and draws them as
  /// cars. Uses the estimate endpoint with a zero-length route — it already
  /// returns the nearby list, so no new endpoint is needed.
  Future<void> _refreshNearbyCaptains(LatLng at) async {
    try {
      final res = await context.read<AppState>().estimateTrip(
            pickupLat: at.latitude,
            pickupLng: at.longitude,
            dropoffLat: at.latitude,
            dropoffLng: at.longitude,
          );
      if (!mounted) return;
      final list = res['nearbyCaptains'];
      if (list is List) {
        setState(() => _nearbyCaptains = list);
      }
    } catch (_) {
      // Nearby cars are ambient context — a failed probe must never surface
      // an error to the rider.
    }
  }

  Future<void> _resolvePickupLabel(LatLng latLng) async {
    final address = await _locations.reverseGeocode(latLng);
    if (!mounted) return;
    // Guard against a slow phase-1 lookup overwriting a label that phase 2
    // (or the rider) has since set.
    if (_pickupText.isNotEmpty) return;
    final isAr = _isArabic;
    setState(() {
      _pickupText =
          address ?? (isAr ? 'موقعي الحالي (GPS)' : 'Current location (GPS)');
    });
  }

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  // ───────────────────────────── routing ─────────────────────────────

  /// Fetches the real driving route and fits the camera around it.
  ///
  /// This is the fix for the core bug: previously the app drew a straight line
  /// between two points. Now we ask the backend (which calls OSRM) for the
  /// actual path the driver will take through the street network.
  Future<void> _refreshRoute({bool openBooking = false}) async {
    final pickup = _pickupLocation;
    final dropoff = _dropoffLocation;
    if (pickup == null || dropoff == null) {
      setState(() => _route = null);
      return;
    }

    setState(() => _loadingRoute = true);

    final route = await _locations.fetchRoute(
      origin: pickup,
      destination: dropoff,
    );
    if (!mounted) return;

    setState(() {
      _route = route;
      _loadingRoute = false;
    });

    _fitToRoute();
    if (openBooking) _showBookingFlow();
  }

  /// Frames the whole journey, leaving room for the top bar and bottom sheet
  /// so the route is never hidden behind the UI.
  void _fitToRoute() {
    final points = _route?.points ??
        [
          if (_pickupLocation != null) _pickupLocation!,
          if (_dropoffLocation != null) _dropoffLocation!,
        ];
    if (points.length < 2) return;

    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.only(
          left: 56,
          right: 56,
          top: 160,
          bottom: 280,
        ),
        maxZoom: 16,
      ),
    );
  }

  void _swapLocations() {
    setState(() {
      final tempLoc = _pickupLocation;
      _pickupLocation = _dropoffLocation;
      _dropoffLocation = tempLoc;

      final tempText = _pickupText;
      _pickupText = _dropoffText;
      _dropoffText = tempText;
    });
    _refreshRoute();
  }

  // ─────────────────────── centre-pin picking ───────────────────────

  /// Enters the inDrive-style picking mode: a pin is anchored to the centre of
  /// the screen and the map moves beneath it.
  ///
  /// This is far more accurate than tapping, because a fingertip covers ~40px
  /// of map — on a city street that is a whole block. Anchoring to the centre
  /// lets the rider fine-tune the exact doorway.
  void _startPicking(PickMode mode) {
    final seed = mode == PickMode.pickup
        ? (_pickupLocation ?? _currentLocation)
        : (_dropoffLocation ?? _currentLocation);

    setState(() {
      _pickMode = mode;
      _pinAddress = '';
      _tabIndex = 0;
    });

    if (seed != null) _mapController.move(seed, 16.5);
    _resolvePinAddress(seed ?? _mapController.camera.center);
  }

  void _cancelPicking() {
    _pinDebouncer.cancel();
    // Retire any in-flight lookup so it cannot land on the next pick session.
    _pinRequestId++;
    setState(() {
      _pickMode = PickMode.none;
      _pinAddress = '';
      _resolvingPin = false;
    });
  }

  /// Called continuously as the map moves. Debounced so we only geocode once
  /// the rider stops panning — the backend rate-limits to 20 req/min.
  void _onMapMoved(MapPosition position, bool hasGesture) {
    if (_pickMode == PickMode.none || !hasGesture) return;
    final centre = position.center;
    if (centre == null) return;

    if (!_resolvingPin) setState(() => _resolvingPin = true);
    _pinDebouncer.run(() => _resolvePinAddress(centre));
  }

  Future<void> _resolvePinAddress(LatLng point) async {
    if (_pickMode == PickMode.none) return;
    final requestId = ++_pinRequestId;
    setState(() => _resolvingPin = true);

    final address = await _locations.reverseGeocode(point);
    if (!mounted || _pickMode == PickMode.none) return;
    // A newer pan already started its own lookup — that one owns the label now.
    if (requestId != _pinRequestId) return;

    setState(() {
      _pinAddress = address ?? LocationService.coordinateLabel(point);
      _resolvingPin = false;
    });
  }

  /// Commits the centre pin as the chosen pickup or dropoff.
  void _confirmPin() {
    final centre = _mapController.camera.center;
    final label = _pinAddress.isNotEmpty
        ? _pinAddress
        : LocationService.coordinateLabel(centre);
    final mode = _pickMode;

    // The point is committed — a lookup still in flight is now irrelevant.
    _pinDebouncer.cancel();
    _pinRequestId++;

    setState(() {
      if (mode == PickMode.pickup) {
        _pickupLocation = centre;
        _pickupText = label;
      } else {
        _dropoffLocation = centre;
        _dropoffText = label;
      }
      _pickMode = PickMode.none;
      _pinAddress = '';
    });

    _refreshRoute(openBooking: _pickupLocation != null && _dropoffLocation != null);
  }

  // ───────────────────────────── search ─────────────────────────────

  void _openSearch(bool isPickup) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationSearchSheet(
        isPickup: isPickup,
        currentLocation: _currentLocation,
        locations: _locations,
        onSelectLocation: (label, latLng) {
          setState(() {
            if (isPickup) {
              _pickupLocation = latLng;
              _pickupText = label;
            } else {
              _dropoffLocation = latLng;
              _dropoffText = label;
            }
          });
          _mapController.move(latLng, 16);
          _refreshRoute(
            openBooking: _pickupLocation != null && _dropoffLocation != null,
          );
        },
        onPickOnMap: () => _startPicking(
          isPickup ? PickMode.pickup : PickMode.dropoff,
        ),
      ),
    );
  }

  void _showBookingFlow() {
    final pickup = _pickupLocation;
    final dropoff = _dropoffLocation;
    if (pickup == null || dropoff == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FareEstimateSheet(
        pickup: pickup,
        dropoff: dropoff,
        pickupAddress: _pickupText,
        dropoffAddress: _dropoffText,
        initialRoute: _route,
      ),
    );
  }

  void _onCenterTap() {
    if (_tabIndex != 0) {
      setState(() => _tabIndex = 0);
      return;
    }
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
    } else {
      _determinePosition();
    }
  }

  // ───────────────────────────── build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final go = GoTheme.of(context);
    final picking = _pickMode != PickMode.none;

    return Scaffold(
      backgroundColor: go.bg,
      body: Stack(
        children: [
          if (_tabIndex == 0) _buildMap(go),

          // Tab content sits above the map. The home tab is a transparent
          // overlay so the map stays visible and interactive beneath it.
          Positioned.fill(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                _buildHomeOverlay(appState, go),
                const HistoryScreen(),
                const WalletScreen(),
                const ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      // The bottom bar is hidden while picking so the confirm button owns the
      // bottom of the screen — one clear action at a time.
      //
      // Otherwise the bar follows the service the rider is arranging: intercity
      // ("سفر") is a booking-and-offers flow that only needs two destinations,
      // while a city ride keeps the full four-destination nav.
      bottomNavigationBar: picking
          ? null
          : _isTravelMode
              ? TravelModeBottomBar(
                  currentTab: _travelTab,
                  onTabChanged: (tab) => setState(() {
                    _travelTab = tab;
                    // The orders tab reuses the shared history screen, which
                    // lives at index 1 of the IndexedStack; the trip tab is the
                    // map overlay at index 0.
                    _tabIndex = tab == TravelTab.orders ? 1 : 0;
                  }),
                  onExitTravelMode: () => setState(() {
                    _category = 'ride';
                    _travelTab = TravelTab.trip;
                    _tabIndex = 0;
                  }),
                )
              : MainBottomNav(
                  currentIndex: _tabIndex,
                  onTap: (index) => setState(() => _tabIndex = index),
                  onCenterTap: _onCenterTap,
                ),
    );
  }

  Widget _buildMap(GoTheme go) {
    return RepaintBoundary(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _currentLocation ?? const LatLng(30.0444, 31.2357),
          initialZoom: 14,
          minZoom: 3,
          maxZoom: 18.5,
          onPositionChanged: _onMapMoved,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: MapTiles.urlForContext(context),
            subdomains: MapTiles.subdomains,
            retinaMode: RetinaMode.isHighDensity(context),
            userAgentPackageName: 'tech.synapticstudio.godrive.rider',
            tileProvider: NetworkTileProvider(),
          ),
          _buildRouteLayer(go),
          _buildMarkerLayer(go),
        ],
      ),
    );
  }

  /// Draws the driving route as a casing + line pair.
  ///
  /// The dark casing underneath keeps the route legible where it crosses
  /// bright roads or dense labels — the same technique Google and inDrive use.
  Widget _buildRouteLayer(GoTheme go) {
    final route = _route;
    if (route == null || route.points.length < 2) {
      return const SizedBox.shrink();
    }

    return PolylineLayer(
      polylines: [
        Polyline(
          points: route.points,
          strokeWidth: 9,
          color: go.routeCasing,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
        Polyline(
          points: route.points,
          strokeWidth: 5.5,
          color: go.routeLine,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
      ],
    );
  }

  Widget _buildMarkerLayer(GoTheme go) {
    // While picking, the centre pin represents the point being chosen, so we
    // hide that endpoint's marker to avoid showing two pins for one location.
    final hidePickup = _pickMode == PickMode.pickup;
    final hideDropoff = _pickMode == PickMode.dropoff;

    return MarkerLayer(
      markers: [
        // Nearby online captains as top-down cars (Uber-style). Drawn first
        // so the rider's own pulsing dot and pins always sit above them.
        for (final cap in _nearbyCaptains)
          if ((cap['lat'] as num?)?.toDouble() != null &&
              (cap['lng'] as num?)?.toDouble() != null)
            Marker(
              point: LatLng(
                (cap['lat'] as num).toDouble(),
                (cap['lng'] as num).toDouble(),
              ),
              width: 34,
              height: 34,
              child: VehicleMapMarker(
                color: go.isDark ? go.action : AppTokens.primary,
                size: 34,
              ),
            ),
        if (_currentLocation != null)
          Marker(
            point: _currentLocation!,
            width: 64,
            height: 64,
            child: _PulsingLocationDot(controller: _pulseController, go: go),
          ),
        if (!hidePickup &&
            _pickupLocation != null &&
            _pickupLocation != _currentLocation)
          Marker(
            point: _pickupLocation!,
            width: 34,
            height: 34,
            child: _EndpointDot(color: go.pinPickup, go: go),
          ),
        if (!hideDropoff && _dropoffLocation != null)
          Marker(
            point: _dropoffLocation!,
            width: 40,
            height: 48,
            alignment: Alignment.topCenter,
            child: _DestinationFlag(go: go),
          ),
      ],
    );
  }

  Widget _buildHomeOverlay(AppState appState, GoTheme go) {
    if (_pickMode != PickMode.none) return _buildPickingOverlay(go);

    final isAr = _isArabic;
    final topInset = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // Floating utility buttons — kept small so the map dominates.
        Positioned(
          top: topInset + 10,
          left: 14,
          right: 14,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleGlassButton(
                go: go,
                // Keyed off the *visible* brightness, not the enum: in system
                // mode `themeMode` is neither light nor dark, so comparing the
                // enum showed a moon icon on an already-dark screen.
                icon: appState.isDarkActive
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                tooltip: isAr ? 'تغيير المظهر' : 'Toggle theme',
                onTap: appState.toggleTheme,
              ),
              _PillGlassButton(
                go: go,
                icon: Icons.language_rounded,
                label: isAr ? 'English' : 'العربية',
                onTap: appState.toggleLanguage,
              ),
            ],
          ),
        ),

        // Recentre button floats just above the booking panel.
        Positioned(
          bottom: 232,
          left: isAr ? 16 : null,
          right: isAr ? null : 16,
          child: _CircleGlassButton(
            go: go,
            icon: Icons.my_location_rounded,
            tooltip: isAr ? 'موقعي' : 'My location',
            onTap: _onCenterTap,
          ),
        ),

        // The booking panel anchors the bottom of the screen, inDrive-style.
        Align(
          alignment: Alignment.bottomCenter,
          child: _BookingPanel(
            go: go,
            isArabic: isAr,
            category: _category,
            onCategoryChanged: (c) => setState(() {
              _category = c;
              // Entering or leaving travel mode swaps the bottom bar, so reset
              // to that mode's first destination rather than leaving a stale
              // index selected in a bar that no longer has it.
              _travelTab = TravelTab.trip;
              _tabIndex = 0;
            }),
            pickupText: _pickupText,
            dropoffText: _dropoffText,
            route: _route,
            loadingRoute: _loadingRoute,
            onTapPickup: () => _openSearch(true),
            onTapDropoff: () => _openSearch(false),
            onSwap: _swapLocations,
            onContinue: _showBookingFlow,
          ),
        ),
      ],
    );
  }

  /// The centre-pin picking UI — a fixed pin, a live address readout, and a
  /// single confirm action.
  Widget _buildPickingOverlay(GoTheme go) {
    final isAr = _isArabic;
    final isPickup = _pickMode == PickMode.pickup;
    final topInset = MediaQuery.of(context).padding.top;

    final title = isPickup
        ? (isAr ? 'تعيين نقطة الانطلاق' : 'Set pickup point')
        : (isAr ? 'تعيين الوجهة' : 'Set destination');

    return Stack(
      children: [
        // Back control + instruction chip.
        Positioned(
          top: topInset + 10,
          left: 14,
          right: 14,
          child: Row(
            children: [
              _CircleGlassButton(
                go: go,
                icon: isAr
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
                tooltip: isAr ? 'رجوع' : 'Back',
                onTap: _cancelPicking,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: go.isDark ? go.panel : Colors.black.withOpacity(0.82),
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    boxShadow: _softShadow(go),
                  ),
                  child: Text(
                    title,
                    style: AppTokens.font(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // The pin itself: anchored to the exact centre of the map viewport.
        // `IgnorePointer` keeps every gesture flowing through to the map.
        IgnorePointer(
          child: Center(
            child: Transform.translate(
              // Lift by half the pin height so the tip — not the middle —
              // marks the chosen coordinate.
              offset: const Offset(0, -26),
              child: _CentrePin(
                color: isPickup ? go.pinPickup : go.pinDropoff,
                busy: _resolvingPin,
              ),
            ),
          ),
        ),

        // Address readout + confirm.
        Align(
          alignment: Alignment.bottomCenter,
          child: _PinConfirmPanel(
            go: go,
            isArabic: isAr,
            isPickup: isPickup,
            address: _pinAddress,
            resolving: _resolvingPin,
            onConfirm: _confirmPin,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════ map decorations ═══════════════════════════

List<BoxShadow> _softShadow(GoTheme go) => [
      BoxShadow(
        color: Colors.black.withOpacity(go.isDark ? 0.5 : 0.14),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];

/// The rider's own position: a solid dot with a slow breathing halo.
class _PulsingLocationDot extends StatelessWidget {
  const _PulsingLocationDot({required this.controller, required this.go});

  final AnimationController controller;
  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 26 + (26 * t),
              height: 26 + (26 * t),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.26 * (1 - t)),
              ),
            ),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A small ringed dot marking a confirmed endpoint.
class _EndpointDot extends StatelessWidget {
  const _EndpointDot({required this.color, required this.go});

  final Color color;
  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: go.panel,
          border: Border.all(color: color, width: 5),
          boxShadow: _softShadow(go),
        ),
      ),
    );
  }
}

/// Destination marker drawn as a flag on a stem, matching the reference app.
class _DestinationFlag extends StatelessWidget {
  const _DestinationFlag({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: go.isDark ? Colors.white : Colors.black,
            borderRadius: BorderRadius.circular(9),
            boxShadow: _softShadow(go),
          ),
          child: Icon(
            Icons.flag_rounded,
            size: 19,
            color: go.isDark ? Colors.black : Colors.white,
          ),
        ),
        Container(
          width: 2.5,
          height: 12,
          color: go.isDark ? Colors.white : Colors.black,
        ),
      ],
    );
  }
}

/// The fixed centre pin used while choosing a point.
class _CentrePin extends StatelessWidget {
  const _CentrePin({required this.color, required this.busy});

  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedScale(
          scale: busy ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.place_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        // Stem + ground shadow give the pin a sense of touching the map.
        Container(width: 2.5, height: 14, color: color),
        Container(
          width: 9,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.28),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════ overlay panels ═══════════════════════════

class _CircleGlassButton extends StatelessWidget {
  const _CircleGlassButton({
    required this.go,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final GoTheme go;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: go.panel,
      shape: const CircleBorder(),
      elevation: go.isDark ? 0 : 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: go.border, width: go.isDark ? 1 : 0),
          ),
          child: Icon(icon, size: 21, color: go.text),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _PillGlassButton extends StatelessWidget {
  const _PillGlassButton({
    required this.go,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final GoTheme go;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: go.panel,
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      elevation: go.isDark ? 0 : 3,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(color: go.border, width: go.isDark ? 1 : 0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: go.text),
              const SizedBox(width: 7),
              Text(
                label,
                style: AppTokens.font(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: go.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom booking panel: category strip, route summary, and the two
/// location fields.
class _BookingPanel extends StatelessWidget {
  const _BookingPanel({
    required this.go,
    required this.isArabic,
    required this.category,
    required this.onCategoryChanged,
    required this.pickupText,
    required this.dropoffText,
    required this.route,
    required this.loadingRoute,
    required this.onTapPickup,
    required this.onTapDropoff,
    required this.onSwap,
    required this.onContinue,
  });

  final GoTheme go;
  final bool isArabic;
  final String category;
  final ValueChanged<String> onCategoryChanged;
  final String pickupText;
  final String dropoffText;
  final RoutePreview? route;
  final bool loadingRoute;
  final VoidCallback onTapPickup;
  final VoidCallback onTapDropoff;
  final VoidCallback onSwap;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final hasBoth = pickupText.isNotEmpty && dropoffText.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(go.isDark ? 0.55 : 0.16),
            blurRadius: 26,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: go.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),

            VehicleCategoryStrip(
              selected: category,
              onChanged: onCategoryChanged,
              isArabic: isArabic,
            ),
            const SizedBox(height: 14),

            if (loadingRoute || route != null) ...[
              _RouteSummary(
                go: go,
                isArabic: isArabic,
                route: route,
                loading: loadingRoute,
              ),
              const SizedBox(height: 12),
            ],

            _LocationField(
              go: go,
              icon: Icons.trip_origin_rounded,
              iconColor: go.pinPickup,
              value: pickupText,
              hint: isArabic ? 'من أين تنطلق؟' : 'Where from?',
              onTap: onTapPickup,
              trailing: IconButton(
                onPressed: onSwap,
                icon: Icon(Icons.swap_vert_rounded, color: go.muted, size: 22),
                tooltip: isArabic ? 'تبديل' : 'Swap',
              ),
            ),
            const SizedBox(height: 8),
            _LocationField(
              go: go,
              icon: Icons.place_rounded,
              iconColor: go.pinDropoff,
              value: dropoffText,
              hint: isArabic ? 'ما الوجهة وما التكلفة؟' : 'Where to?',
              onTap: onTapDropoff,
              emphasise: true,
            ),

            if (hasBoth) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loadingRoute ? null : onContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: go.action,
                    foregroundColor: go.onAction,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusPill),
                    ),
                  ),
                  child: Text(
                    isArabic ? 'متابعة' : 'Continue',
                    style: AppTokens.font(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Distance + duration readout, with an honest label when the backend had to
/// approximate because the routing engine was unreachable.
class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.go,
    required this.isArabic,
    required this.route,
    required this.loading,
  });

  final GoTheme go;
  final bool isArabic;
  final RoutePreview? route;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: go.muted),
          ),
          const SizedBox(width: 10),
          Text(
            isArabic ? 'جارٍ حساب المسار...' : 'Calculating route...',
            style: AppTokens.font(
              fontSize: 13,
              color: go.muted,
            ),
          ),
        ],
      );
    }

    final r = route!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.route_rounded, size: 18, color: go.muted),
          const SizedBox(width: 8),
          Text(
            r.distanceLabel(isArabic: isArabic),
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: go.text,
            ),
          ),
          Text(
            '  ·  ',
            style: TextStyle(color: go.muted),
          ),
          Icon(Icons.schedule_rounded, size: 18, color: go.muted),
          const SizedBox(width: 6),
          Text(
            r.durationLabel(isArabic: isArabic),
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: go.text,
            ),
          ),
          const Spacer(),
          if (r.isApproximate)
            Text(
              isArabic ? 'تقريبي' : 'approx.',
              style: AppTokens.font(
                fontSize: 11.5,
                color: go.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationField extends StatelessWidget {
  const _LocationField({
    required this.go,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.hint,
    required this.onTap,
    this.trailing,
    this.emphasise = false,
  });

  final GoTheme go;
  final IconData icon;
  final Color iconColor;
  final String value;
  final String hint;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final filled = value.isNotEmpty;

    return Material(
      color: go.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: emphasise && !filled
                ? Border.all(color: go.action.withOpacity(0.55), width: 1.4)
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  filled ? value : hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.font(
                    fontSize: 14.5,
                    fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                    color: filled ? go.text : go.muted,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom panel shown during centre-pin picking.
class _PinConfirmPanel extends StatelessWidget {
  const _PinConfirmPanel({
    required this.go,
    required this.isArabic,
    required this.isPickup,
    required this.address,
    required this.resolving,
    required this.onConfirm,
  });

  final GoTheme go;
  final bool isArabic;
  final bool isPickup;
  final String address;
  final bool resolving;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(go.isDark ? 0.55 : 0.16),
            blurRadius: 26,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isPickup ? Icons.trip_origin_rounded : Icons.place_rounded,
                  size: 20,
                  color: isPickup ? go.pinPickup : go.pinDropoff,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: resolving && address.isEmpty
                      ? _AddressSkeleton(go: go)
                      : Text(
                          address.isEmpty
                              ? (isArabic
                                  ? 'حرّك الخريطة لتحديد المكان'
                                  : 'Move the map to set the point')
                              : address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTokens.font(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: address.isEmpty ? go.muted : go.text,
                            height: 1.35,
                          ),
                        ),
                ),
                if (resolving && address.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: go.muted,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: go.action,
                foregroundColor: go.onAction,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                ),
              ),
              child: Text(
                isPickup
                    ? (isArabic ? 'تأكيد نقطة الانطلاق' : 'Confirm pickup')
                    : (isArabic ? 'تأكيد الوجهة' : 'Confirm destination'),
                style: AppTokens.font(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder bars shown while the first address resolves, so the panel does
/// not jump in height when text arrives.
class _AddressSkeleton extends StatelessWidget {
  const _AddressSkeleton({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => Container(
          width: width,
          height: 11,
          decoration: BoxDecoration(
            color: go.surface,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(190), const SizedBox(height: 7), bar(120)],
    );
  }
}

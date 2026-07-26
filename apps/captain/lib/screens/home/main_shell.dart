import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:synaptic_go_captain/screens/documents/document_upload_screen.dart';
import 'package:synaptic_go_captain/screens/earnings/earnings_screen.dart';
import 'package:synaptic_go_captain/screens/profile/settings_screen.dart';
import 'package:synaptic_go_captain/screens/safety/sos_screen.dart';
import 'available_trips_tab.dart';
import 'home_tab.dart';
import 'trips_tab.dart';

/// The captain's main shell: a full-bleed map with floating chrome.
///
/// Reworked in four substantive ways:
///
///  * **The map is now live.** It previously took a single GPS fix in
///    `initState` and never looked again, so the captain's own marker sat
///    frozen at their starting point for the entire shift. It now subscribes
///    to the position stream and follows, including heading.
///  * **The route is drawn.** Pickup and dropoff were lone pins with nothing
///    between them; there is now a polyline from the captain through pickup
///    to dropoff, and the camera can frame the whole trip.
///  * **Tiles follow the theme.** The light basemap was hardcoded, which is
///    blinding at night. Dark mode now gets a dark basemap.
///  * **Controls moved into reach.** SOS sat top-left — the far corner from a
///    right-handed captain's thumb on a mounted phone. Controls are now
///    stacked bottom-end, above the sheet, where the thumb already rests.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  /// The "رحلات متاحة" destination. Appended after the four original tabs so
  /// their indices stay stable, even though it renders in the centre slot.
  static const int _availableTripsIndex = 4;

  final MapController _mapController = MapController();

  int _tabIndex = 0;
  LatLng? _currentLocation;
  double? _heading;
  bool _locating = true;
  bool _togglingOnline = false;

  /// True while the camera should chase the captain. Any manual pan releases
  /// it, so the map does not fight the captain's own gestures.
  bool _followMe = true;
  bool _mapReady = false;

  StreamSubscription<Position>? _positionSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CaptainState>().refreshMe();
    });
    _initLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
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
      // the first high-accuracy fix is still resolving.
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null && mounted) _applyPosition(cached, recenter: true);

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
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
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 8,
      ),
    ).listen(
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
      _mapController.move(point, _mapController.camera.zoom);
    }
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

  /// Frames the captain plus both trip endpoints so the whole job is visible.
  void _fitActiveTrip(CaptainState state) {
    final points = _tripPoints(state, includeCaptain: true);
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
        title: const Text('تعذّر تحديد الموقع'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسنًا'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, AppTokens.tapTarget),
            ),
            child: const Text('فتح الإعدادات'),
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
    final isApproved =
        (state.captain?['approval_status'] ?? state.captain?['status']) == 'approved';

    // A captain who has not been approved yet cannot receive work, so the
    // document queue is the only meaningful screen for them.
    if (!isApproved) return const DocumentUploadScreen();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onMapTab = _tabIndex == 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: isDark ? AppTokens.darkBg : AppTokens.lightBg,
        body: Stack(
          children: [
            if (onMapTab) _buildMap(state, isDark),
            if (onMapTab && _locating) _buildLocatingVeil(isDark),

            Positioned.fill(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  HomeTab(
                    mapController: _mapController,
                    online: state.online,
                    busy: _togglingOnline,
                    onToggleOnline: _toggleOnline,
                  ),
                  const TripsTab(),
                  const EarningsScreen(),
                  const SettingsScreen(),
                  // Index 4, appended rather than inserted at the centre's
                  // visual position, so the four existing destinations keep
                  // the indices the rest of the app already passes around.
                  AvailableTripsTab(
                    online: state.online,
                    busy: _togglingOnline,
                    onToggleOnline: _toggleOnline,
                  ),
                ],
              ),
            ),

            if (onMapTab) _buildMapControls(state),
          ],
        ),
        bottomNavigationBar: MainBottomNav(
          currentIndex: _tabIndex,
          onTap: (index) => setState(() => _tabIndex = index),
          // The centre slot is a real destination in the Captain app. The
          // recentre shortcut it replaces is not lost — it is still a
          // dedicated floating control on the map (see _buildMapControls),
          // which is where a captain's thumb already goes for it.
          centerDestination: NavCenterDestination(
            index: _availableTripsIndex,
            label: 'رحلات متاحة',
            icon: Icons.explore_rounded,
            // Only meaningful while online; offline the tab shows a CTA
            // rather than a list, so a count would be a lie.
            badgeCount: state.online ? state.offers.length : 0,
          ),
        ),
      ),
    );
  }

  Widget _buildMap(CaptainState state, bool isDark) {
    final route = _tripPoints(state, includeCaptain: true);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation ?? const LatLng(30.0444, 31.2357),
        initialZoom: 15.5,
        minZoom: 5,
        maxZoom: 18.5,
        backgroundColor: isDark ? AppTokens.darkBg : AppTokens.lightSurface,
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
            isDark ? Brightness.dark : Brightness.light,
          ),
          subdomains: const ['a', 'b', 'c'],
          retinaMode: RetinaMode.isHighDensity(context),
          userAgentPackageName: AppTokens.mapUserAgent,
          tileBuilder: isDark ? darkModeTileBuilder : null,
        ),

        // Route: captain → pickup → dropoff. A casing stroke underneath keeps
        // the line legible over both pale streets and dark parkland.
        if (route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route,
                strokeWidth: 9,
                color: Colors.white.withOpacity(isDark ? 0.22 : 0.9),
              ),
              Polyline(
                points: route,
                strokeWidth: 5,
                color: AppTokens.routeLine,
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
    if (_currentLocation != null) {
      markers.add(Marker(
        point: _currentLocation!,
        width: 54,
        height: 54,
        child: CaptainMapMarker(heading: _heading, online: state.online),
      ));
    }

    return markers;
  }

  Widget _buildLocatingVeil(bool isDark) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: (isDark ? Colors.black : Colors.white).withOpacity(0.45),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceLg,
                vertical: AppTokens.spaceMd,
              ),
              decoration: BoxDecoration(
                color: isDark ? AppTokens.darkPanel : Colors.white,
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
                    'جارٍ تحديد موقعك…',
                    style: AppTokens.font(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppTokens.darkText : AppTokens.lightText,
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

  /// Map chrome, stacked bottom-end above the sheet — within thumb reach of a
  /// phone in a dashboard mount, rather than in the far top corner.
  Widget _buildMapControls(CaptainState state) {
    final hasTrip = state.activeTrip != null;

    return PositionedDirectional(
      end: AppTokens.spaceMd,
      bottom: hasTrip ? 300 : 190,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MapCircleButton(
            icon: Icons.sos_rounded,
            tooltip: 'الطوارئ',
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
              tooltip: 'عرض الرحلة كاملة',
              onTap: () => _fitActiveTrip(state),
            ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
          MapCircleButton(
            icon: _followMe ? Icons.my_location_rounded : Icons.location_searching_rounded,
            tooltip: 'موقعي',
            iconColor: _followMe ? AppTokens.primary : null,
            onTap: _recenter,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
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
import 'home_tab.dart';
import 'trips_tab.dart';

/// Main shell for the Captain app with bottom navigation bar matching input_file_3.png
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final MapController _mapController = MapController();
  int _tabIndex = 0;
  LatLng? _currentLocation;
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CaptainState>().refreshMe();
    });
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _locating = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locating = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _locating = false;
      });
      _mapController.move(_currentLocation!, 14);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onCenterTap() {
    final state = context.read<CaptainState>();
    if (_tabIndex != 0) {
      setState(() => _tabIndex = 0);
    } else {
      if (_currentLocation != null) {
        _mapController.move(_currentLocation!, 14);
      }
      final isApproved = (state.captain?['approval_status'] ?? state.captain?['status']) == 'approved';
      if (isApproved) {
        // setOnline now returns false + sets gpsError if GPS is off
        state.setOnline(!state.online).then((ok) {
          if (!ok && mounted && state.gpsError != null) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('تنبيه'),
                content: Text(state.gpsError!),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('حسنًا'),
                  ),
                ],
              ),
            );
          }
        });
      }
    }
  }

  void _recenter() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 14);
    } else {
      _determinePosition();
    }
  }

  /// Builds every map pin: the captain's own position plus the active trip's
  /// pickup/dropoff. Coordinates arrive from the API as JSON numbers, so they
  /// are read defensively via `num?` — a raw `as double` cast would throw when
  /// D1 returns an integer-valued column.
  List<Marker> _buildMarkers(CaptainState state) {
    final markers = <Marker>[];

    if (_currentLocation != null) {
      markers.add(Marker(
        point: _currentLocation!,
        width: 48,
        height: 48,
        child: const _CaptainLocationMarker(),
      ));
    }

    final trip = state.activeTrip;
    if (trip != null) {
      final pickupLat = (trip['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (trip['pickup_lng'] as num?)?.toDouble();
      if (pickupLat != null && pickupLng != null) {
        markers.add(Marker(
          point: LatLng(pickupLat, pickupLng),
          width: 40,
          height: 40,
          child: const Icon(Icons.location_on, color: AppTokens.primary, size: 36),
        ));
      }

      final dropLat = (trip['dropoff_lat'] as num?)?.toDouble();
      final dropLng = (trip['dropoff_lng'] as num?)?.toDouble();
      if (dropLat != null && dropLng != null) {
        markers.add(Marker(
          point: LatLng(dropLat, dropLng),
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: AppTokens.accent, size: 36),
        ));
      }
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final isApproved = (state.captain?['approval_status'] ?? state.captain?['status']) == 'approved';

    // Requirement #6: If captain account is newly registered and pending approval,
    // show DocumentUploadScreen first for uploading the 4 Egyptian documents.
    if (!isApproved) {
      return const DocumentUploadScreen();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Map Background (Only active on Home Tab)
          if (_tabIndex == 0)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation ?? const LatLng(30.0444, 31.2357),
                initialZoom: 14,
                minZoom: 10,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                // Captain position + active-trip pickup/dropoff pins. These
                // must be FlutterMap children — a MarkerLayer looks up
                // MapCamera.of(context) and throws outside a map ancestor.
                MarkerLayer(markers: _buildMarkers(state)),
              ],
            ),

          // Loading overlay
          if (_locating && _tabIndex == 0)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.2),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTokens.primary),
                ),
              ),
            ),

          // Tab content
          Positioned.fill(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                HomeTab(mapController: _mapController),
                const TripsTab(),
                const EarningsScreen(),
                const SettingsScreen(),
              ],
            ),
          ),

          // Floating SOS button (home tab only)
          if (_tabIndex == 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              child: FloatingActionButton(
                heroTag: 'sos',
                backgroundColor: AppTokens.sos,
                elevation: 6,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SosScreen()),
                ),
                child: const Icon(Icons.sos, color: Colors.white, size: 26),
              ),
            ),

          // Floating recenter button (home tab only)
          if (_tabIndex == 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                backgroundColor: Colors.white,
                onPressed: _recenter,
                child: const Icon(Icons.my_location, color: AppTokens.primary, size: 20),
              ),
            ),
        ],
      ),
      bottomNavigationBar: MainBottomNav(
        currentIndex: _tabIndex,
        onTap: (index) => setState(() => _tabIndex = index),
        onCenterTap: _onCenterTap,
      ),
    );
  }
}

class _CaptainLocationMarker extends StatelessWidget {
  const _CaptainLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTokens.primary.withOpacity(0.15),
      ),
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTokens.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(color: AppTokens.primary.withOpacity(0.4), blurRadius: 8),
            ],
          ),
          child: const Icon(Icons.directions_car, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
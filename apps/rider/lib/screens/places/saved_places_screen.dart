import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/app_state.dart';
import '../../services/location_service.dart';

/// Saved places screen — lets the rider add Home/Work/custom places by
/// picking a real location on the map (or using current GPS location).
/// Coordinates are always real — never hardcoded.
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  List<dynamic> _places = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPlaces();
  }

  Future<void> _fetchPlaces() async {
    try {
      final res = await context.read<AppState>().apiGet('/user/saved-places');
      if (mounted) {
        setState(() {
          _places = res['places'] ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPlace(String name, double lat, double lng, String address) async {
    try {
      await context.read<AppState>().apiPost('/user/saved-places', {
        'label': name,
        'address': address,
        'lat': lat,
        'lng': lng,
      });
      _fetchPlaces();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deletePlace(String id) async {
    try {
      await context.read<AppState>().apiDelete('/user/saved-places/$id');
      _fetchPlaces();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PickLocationScreen(
          onConfirm: (lat, lng, address) {
            _addPlace(nameCtrl.text.isEmpty ? AppStrings.of(context).placeFallback : nameCtrl.text, lat, lng, address);
          },
          nameController: nameCtrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.savedPlacesTitle, style: AppTokens.font()),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: go.action,
        foregroundColor: go.onAction,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const SkeletonList(count: 4)
          : _places.isEmpty
              ? EmptyState(
                  icon: Icons.place_outlined,
                  title: strings.noSavedPlaces,
                  subtitle: strings.addHomeWorkHint,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _places.length,
                  itemBuilder: (context, index) {
                    final place = _places[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: go.panel,
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppTokens.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                          ),
                          child: Icon(
                            place['label'] == 'المنزل' || place['label'] == 'Home'
                                ? Icons.home
                                : (place['label'] == 'العمل' || place['label'] == 'Work' ? Icons.work : Icons.place),
                            color: AppTokens.primary, size: 20,
                          ),
                        ),
                        title: Text(place['label'] ?? strings.placeFallback, style: AppTokens.font(color: go.text, fontWeight: FontWeight.w700, fontSize: 15)),
                        subtitle: Text(place['address'] ?? '', style: AppTokens.font(color: go.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTokens.danger, size: 20),
                          onPressed: () => _deletePlace(place['id']),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Map-based location picker.
///
/// Uses the same fixed centre-pin interaction as the home screen: the pin
/// stays anchored to the middle of the viewport and the map moves beneath it.
/// Tapping to place a pin was replaced because a fingertip covers roughly 40
/// logical pixels — at street zoom that is most of a block, so riders were
/// saving a point near, but not at, the doorway they meant.
class _PickLocationScreen extends StatefulWidget {
  final TextEditingController nameController;
  final void Function(double lat, double lng, String address) onConfirm;

  const _PickLocationScreen({required this.nameController, required this.onConfirm});

  @override
  State<_PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<_PickLocationScreen> {
  final MapController _mapController = MapController();
  final Debouncer _debouncer = Debouncer(milliseconds: 450);

  /// The map centre is the chosen point, so this is only used to seed the
  /// initial camera position.
  LatLng? _initialCentre;
  String _address = '';
  bool _geocoding = false;
  bool _ready = false;

  late final LocationService _locations;

  @override
  void initState() {
    super.initState();
    _locations = LocationService(context.read<AppState>());
    _initToCurrentLocation();
  }

  @override
  void dispose() {
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _initToCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _finishInit(null);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _finishInit(null);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _finishInit(null);
        return;
      }

      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      _finishInit(LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      _finishInit(null);
    }
  }

  void _finishInit(LatLng? location) {
    if (!mounted) return;
    final centre = location ?? const LatLng(30.0444, 31.2357);
    setState(() {
      _initialCentre = centre;
      _ready = true;
    });
    if (location != null) _mapController.move(location, 16);
    _reverseGeocode(centre);
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _geocoding = true);
    final address = await _locations.reverseGeocode(point);
    if (!mounted) return;
    setState(() {
      _address = address ?? LocationService.coordinateLabel(point);
      _geocoding = false;
    });
  }

  /// Re-resolves the address once the rider stops panning.
  void _onMapMoved(MapPosition position, bool hasGesture) {
    if (!hasGesture) return;
    final centre = position.center;
    if (centre == null) return;
    if (!_geocoding) setState(() => _geocoding = true);
    _debouncer.run(() => _reverseGeocode(centre));
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;
    final surface = go.surface;
    final accent = go.isDark ? go.action : AppTokens.primary;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.pickLocationTitle, style: AppTokens.font(fontWeight: FontWeight.w700)),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCentre ?? const LatLng(30.0444, 31.2357),
              initialZoom: 15,
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
              ),
            ],
          ),

          // Fixed centre pin. IgnorePointer lets every gesture reach the map.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: _geocoding ? 0.9 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.place_rounded,
                          color: go.isDark ? go.onAction : Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    Container(width: 2.5, height: 14, color: accent),
                    Container(
                      width: 9,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.28),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: widget.nameController,
                      decoration: InputDecoration(
                        hintText: strings.placeNameHint,
                        hintStyle: AppTokens.font(color: muted, fontSize: 14),
                        filled: true, fillColor: surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.label_outline, color: AppTokens.primary, size: 20),
                      ),
                      style: AppTokens.font(color: text, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_geocoding)
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                        else
                          Icon(Icons.location_on, color: accent, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _address.isEmpty ? strings.moveMapToPick : _address,
                            style: AppTokens.font(color: muted, fontSize: 13),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: ElevatedButton(
                        // The map centre is always a valid point once the
                        // camera is ready, so this only guards the first frame.
                        onPressed: !_ready
                            ? null
                            : () {
                                final centre = _mapController.camera.center;
                                final label = _address.isNotEmpty
                                    ? _address
                                    : LocationService.coordinateLabel(centre);
                                widget.onConfirm(centre.latitude, centre.longitude, label);
                                Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: go.action,
                          foregroundColor: go.onAction,
                          disabledBackgroundColor: go.surface,
                          disabledForegroundColor: go.muted,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusPill)),
                        ),
                        child: Text(strings.savePlace, style: AppTokens.font(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

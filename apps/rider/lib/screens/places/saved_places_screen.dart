import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/app_state.dart';
import '../../services/location_service.dart';

/// Saved places screen — lets the rider add Home/Work/custom places by
/// picking a real location on the map (or using current GPS location).
/// Coordinates are always real — never hardcoded.
///
/// Two presentation modes:
///  * Standalone (pushed from the profile): full Scaffold with AppBar and FAB,
///    managing places is the whole job of the screen.
///  * Embedded (a tab on the home screen): [embedded] strips the Scaffold,
///    AppBar and FAB so it composes inside the home IndexedStack, and
///    [onSelectAsDestination] turns each row into a quick-reorder action —
///    one tap sets the place as the trip destination and returns to the map
///    with the fare estimate ready.
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({
    super.key,
    this.embedded = false,
    this.onSelectAsDestination,
  });

  /// True when rendered as a tab inside the home screen's IndexedStack rather
  /// than pushed as its own route.
  final bool embedded;

  /// Quick-reorder callback: the rider tapped "go here" on a saved place.
  /// Receives the place's coordinates and display label so the home screen
  /// can set the destination and open the booking flow. When null, rows are
  /// management-only (standalone behaviour).
  final void Function(double lat, double lng, String label)? onSelectAsDestination;

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

  Future<void> _updatePlace(String id, String name, double lat, double lng, String address) async {
    try {
      await context.read<AppState>().apiPatch('/user/saved-places/$id', {
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

  void _showAddDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PickLocationScreen(
          onConfirm: (name, lat, lng, address) {
            _addPlace(name, lat, lng, address);
          },
        ),
      ),
    );
  }

  /// Edit flow reuses the same centre-pin picker as the add flow, seeded with
  /// the place's current name and coordinates. The rider can rename only,
  /// move the pin only, or do both in one save.
  void _showEditDialog(Map<String, dynamic> place) {
    final lat = (place['lat'] as num?)?.toDouble();
    final lng = (place['lng'] as num?)?.toDouble();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PickLocationScreen(
          initialName: place['label']?.toString(),
          initialAddress: place['address']?.toString(),
          initialLocation: (lat != null && lng != null) ? LatLng(lat, lng) : null,
          onConfirm: (name, newLat, newLng, address) {
            _updatePlace(place['id'].toString(), name, newLat, newLng, address);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final body = _loading
        ? const SkeletonList(count: 4)
        : _places.isEmpty
            ? EmptyState(
                icon: Icons.place_outlined,
                title: isAr ? 'لا توجد أماكن محفوظة' : 'No saved places',
                subtitle: isAr
                    ? 'أضف منزلك أو عملك لطلب رحلة سريعة'
                    : 'Add your home or work for a quick reorder',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _places.length,
                itemBuilder: (context, index) {
                  final place = _places[index];
                  final label = place['label'] ?? (isAr ? 'مكان' : 'Place');
                  final address = place['address'] ?? '';
                  final lat = (place['lat'] as num?)?.toDouble();
                  final lng = (place['lng'] as num?)?.toDouble();
                  final canGo = widget.onSelectAsDestination != null &&
                      lat != null &&
                      lng != null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    ),
                    child: ListTile(
                      onTap: canGo
                          ? () => widget.onSelectAsDestination!(lat, lng, label)
                          : null,
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
                      title: Text(label, style: GoogleFonts.ibmPlexSansArabic(color: text, fontWeight: FontWeight.w700, fontSize: 15)),
                      subtitle: Text(address, style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: canGo
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Edit sits beside go-here in the embedded tab
                                // too — a mistyped name should not force the
                                // rider out to the profile screen to fix it.
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, color: muted, size: 19),
                                  tooltip: isAr ? 'تعديل' : 'Edit',
                                  onPressed: () => _showEditDialog(place),
                                ),
                                Icon(
                                  // The row's whole job is "go here" — point
                                  // the way in the reading direction.
                                  isAr
                                      ? Icons.arrow_back_ios_new_rounded
                                      : Icons.arrow_forward_ios_rounded,
                                  color: AppTokens.primary,
                                  size: 17,
                                ),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: AppTokens.primary, size: 20),
                                  tooltip: isAr ? 'تعديل' : 'Edit',
                                  onPressed: () => _showEditDialog(place),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppTokens.danger, size: 20),
                                  tooltip: isAr ? 'حذف' : 'Delete',
                                  onPressed: () => _deletePlace(place['id']),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              );

    if (widget.embedded) {
      // Tab mode: no Scaffold of our own — the home screen supplies it. A
      // lightweight header keeps the destination readable without an AppBar,
      // and the add button floats above the list instead of a FAB.
      return Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isAr ? 'الأماكن المحفوظة' : 'Saved places',
                  style: GoogleFonts.ibmPlexSansArabic(
                    color: text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Material(
                  color: panel,
                  shape: const CircleBorder(),
                  elevation: go.isDark ? 0 : 3,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _showAddDialog,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: go.border, width: go.isDark ? 1 : 0),
                      ),
                      child: Icon(Icons.add_rounded, size: 23, color: go.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(isAr ? 'الأماكن المحفوظة' : 'Saved places', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: go.action,
        foregroundColor: go.onAction,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: body,
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
///
/// The picker owns its own name controller (created and disposed here) so a
/// text field is never leaked across a route boundary.
class _PickLocationScreen extends StatefulWidget {
  final void Function(String name, double lat, double lng, String address) onConfirm;

  /// Edit-mode seeds. All optional — nulls produce the original "add place"
  /// behaviour (blank name, camera on the rider's current GPS fix).
  final String? initialName;
  final String? initialAddress;
  final LatLng? initialLocation;

  const _PickLocationScreen({
    required this.onConfirm,
    this.initialName,
    this.initialAddress,
    this.initialLocation,
  });

  @override
  State<_PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<_PickLocationScreen> {
  final MapController _mapController = MapController();
  final Debouncer _debouncer = Debouncer(milliseconds: 450);
  final TextEditingController _nameCtrl = TextEditingController();

  /// The map centre is the chosen point, so this is only used to seed the
  /// initial camera position.
  LatLng? _initialCentre;
  String _address = '';
  bool _geocoding = false;
  bool _ready = false;

  /// The centre that [_address] was geocoded FROM. Kept in lockstep with the
  /// address so tapping "حفظ المكان" mid-pan never pairs fresh coordinates
  /// with a stale street name.
  LatLng? _resolvedCentre;
  int _addrRequestId = 0;

  late final LocationService _locations;

  @override
  void initState() {
    super.initState();
    _locations = LocationService(context.read<AppState>());
    // Seed the name field synchronously so the edit screen never flashes an
    // empty field before the async location work finishes.
    _nameCtrl.text = widget.initialName ?? '';
    _initToCurrentLocation();
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _initToCurrentLocation() async {
    // Edit mode: the saved coordinates are the starting point — no GPS lookup
    // at all, which also means the picker works fully offline and never yanks
    // the pin away from the place being edited.
    final seed = widget.initialLocation;
    if (seed != null) {
      _finishInit(seed);
      return;
    }

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
    // The stored address is already correct for the stored pin — re-geocoding
    // here would replace a known-good label with whatever the geocoder says
    // today, and the rider might only be here to fix a typo in the name.
    if (widget.initialAddress != null && widget.initialAddress!.isNotEmpty) {
      setState(() {
        _address = widget.initialAddress!;
        _resolvedCentre = centre;
      });
    } else {
      _reverseGeocode(centre);
    }
  }

  Future<void> _reverseGeocode(LatLng point) async {
    final requestId = ++_addrRequestId;
    setState(() => _geocoding = true);
    final address = await _locations.reverseGeocode(point);
    if (!mounted || requestId != _addrRequestId) return;
    setState(() {
      _address = address ?? LocationService.coordinateLabel(point);
      _resolvedCentre = point;
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
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;
    final surface = go.surface;
    final accent = go.isDark ? go.action : AppTokens.primary;

    final isEditing = widget.initialLocation != null;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          isEditing ? 'تعديل المكان' : 'اختر الموقع',
          style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
        ),
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
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'اسم المكان (المنزل، العمل...)',
                        hintStyle: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 14),
                        filled: true, fillColor: surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.label_outline, color: AppTokens.primary, size: 20),
                      ),
                      style: GoogleFonts.ibmPlexSansArabic(color: text, fontSize: 15),
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
                            _address.isEmpty ? 'حرّك الخريطة لتحديد الموقع' : _address,
                            style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 13),
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity, height: 48,
                      child: ElevatedButton(
                        // Use the centre that the displayed address was
                        // geocoded from. Falling back to the live camera only
                        // covers the first frame before the reverse geocode
                        // returns; after that, the resolved pair keeps the
                        // saved coordinates and the shown address in sync even
                        // if the rider pans and taps quickly.
                        onPressed: !_ready
                            ? null
                            : () {
                                final centre = _resolvedCentre ?? _mapController.camera.center;
                                final label = _address.isNotEmpty
                                    ? _address
                                    : LocationService.coordinateLabel(centre);
                                final name = _nameCtrl.text.trim().isEmpty ? 'مكان' : _nameCtrl.text.trim();
                                widget.onConfirm(name, centre.latitude, centre.longitude, label);
                                Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: go.action,
                          foregroundColor: go.onAction,
                          disabledBackgroundColor: go.surface,
                          disabledForegroundColor: go.muted,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusPill)),
                        ),
                        child: Text(
                          isEditing ? 'حفظ التعديلات' : 'حفظ المكان',
                          style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
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

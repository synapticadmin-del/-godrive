import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/app_state.dart';

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
        'name': name,
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
            _addPlace(nameCtrl.text.isEmpty ? 'مكان' : nameCtrl.text, lat, lng, address);
          },
          nameController: nameCtrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;

    return Scaffold(
      appBar: AppBar(
        title: Text('الأماكن المحفوظة', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTokens.primary,
        onPressed: _showAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const SkeletonList(count: 4)
          : _places.isEmpty
              ? EmptyState(
                  icon: Icons.place_outlined,
                  title: 'لا توجد أماكن محفوظة',
                  subtitle: 'أضف منزلك أو عملك لطلب رحلة سريعة',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _places.length,
                  itemBuilder: (context, index) {
                    final place = _places[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: panel,
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
                            place['name'] == 'المنزل' || place['name'] == 'Home'
                                ? Icons.home
                                : (place['name'] == 'العمل' || place['name'] == 'Work' ? Icons.work : Icons.place),
                            color: AppTokens.primary, size: 20,
                          ),
                        ),
                        title: Text(place['name'] ?? 'مكان', style: GoogleFonts.ibmPlexSansArabic(color: text, fontWeight: FontWeight.w700, fontSize: 15)),
                        subtitle: Text(place['address'] ?? '', style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// Map-based location picker — opens a full-screen map, lets the user pan
/// to a location, tap to confirm, then returns lat/lng + reverse-geocoded
/// address. Falls back to "موقع محدد" if geocoding fails.
class _PickLocationScreen extends StatefulWidget {
  final TextEditingController nameController;
  final void Function(double lat, double lng, String address) onConfirm;

  const _PickLocationScreen({required this.nameController, required this.onConfirm});

  @override
  State<_PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<_PickLocationScreen> {
  final MapController _mapController = MapController();
  LatLng? _picked;
  String _address = '';
  bool _geocoding = false;

  @override
  void initState() {
    super.initState();
    _initToCurrentLocation();
  }

  Future<void> _initToCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final loc = LatLng(pos.latitude, pos.longitude);
      setState(() => _picked = loc);
      _mapController.move(loc, 15);
      _reverseGeocode(loc);
    } catch (_) {}
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _geocoding = true);
    try {
      final state = context.read<AppState>();
      final res = await state.apiGet('/geocode/reverse?lat=${point.latitude}&lng=${point.longitude}');
      final addr = res['display_name'] ?? res['address'] ?? 'موقع محدد';
      if (mounted) setState(() {
        _address = addr;
        _geocoding = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _address = 'موقع محدد';
        _geocoding = false;
      });
    }
  }

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() => _picked = point);
    _reverseGeocode(point);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileUrl = isDark
        ? 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png'
        : 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final surface = isDark ? AppTokens.darkSurface : AppTokens.lightSurface;

    return Scaffold(
      appBar: AppBar(
        title: Text('اختر الموقع', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700)),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked ?? const LatLng(30.0444, 31.2357),
              initialZoom: 14,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(urlTemplate: tileUrl, subdomains: const ['a', 'b', 'c']),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 40, height: 40,
                      child: const Icon(Icons.location_on, color: AppTokens.primary, size: 40),
                    ),
                  ],
                ),
            ],
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
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTokens.primary))
                        else
                          const Icon(Icons.location_on, color: AppTokens.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _address.isEmpty ? 'اضغط على الخريطة لتحديد الموقع' : _address,
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
                        onPressed: _picked == null
                            ? null
                            : () {
                                widget.onConfirm(_picked!.latitude, _picked!.longitude, _address);
                                Navigator.pop(context);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTokens.primary, foregroundColor: Colors.white,
                          disabledBackgroundColor: AppTokens.primary.withOpacity(0.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                        ),
                        child: Text('حفظ المكان', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700, fontSize: 15)),
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
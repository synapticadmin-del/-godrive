import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../../services/app_state.dart';
import '../history/history_screen.dart';
import '../wallet/wallet_screen.dart';
import '../profile/profile_screen.dart';
import 'fare_estimate_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  int _tabIndex = 0;
  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  LatLng? _dropoffLocation;

  String _pickupText = '';
  String _dropoffText = '';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _determinePosition();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

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

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = latLng;
        _pickupLocation = latLng;
        _pickupText = 'موقعي الحالي (GPS)';
      });
      _mapController.move(latLng, 15);
    } catch (_) {}
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

    if (_pickupLocation != null && _dropoffLocation != null) {
      _fitMapToPoints();
    }
  }

  void _fitMapToPoints() {
    if (_pickupLocation == null || _dropoffLocation == null) return;
    final bounds = LatLngBounds.fromPoints([_pickupLocation!, _dropoffLocation!]);
    _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)));
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _dropoffLocation = point;
      _dropoffText = '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    });
    if (_pickupLocation != null) {
      _showBookingFlow();
    }
  }

  void _showBookingFlow() {
    final pickup = _pickupLocation ?? _currentLocation ?? const LatLng(30.0444, 31.2357);
    final dropoff = _dropoffLocation ?? const LatLng(30.0444, 31.2357);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FareEstimateSheet(
        pickup: pickup,
        dropoff: dropoff,
      ),
    );
  }

  void _onCenterTap() {
    if (_tabIndex != 0) {
      setState(() => _tabIndex = 0);
    } else {
      if (_currentLocation != null) {
        _mapController.move(_currentLocation!, 15);
      } else {
        _determinePosition();
      }
    }
  }

  void _openLocationSearchModal(bool isPickup) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationSearchSheet(
        isPickup: isPickup,
        currentLocation: _currentLocation,
        onSelectLocation: (address, latLng) {
          setState(() {
            if (isPickup) {
              _pickupLocation = latLng;
              _pickupText = address;
            } else {
              _dropoffLocation = latLng;
              _dropoffText = address;
            }
          });
          _mapController.move(latLng, 15);
          if (_pickupLocation != null && _dropoffLocation != null) {
            _fitMapToPoints();
            _showBookingFlow();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      body: Stack(
        children: [
          // Map View (Home Tab)
          if (_tabIndex == 0)
            RepaintBoundary(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: _currentLocation ?? const LatLng(30.0444, 31.2357),
                  initialZoom: 14,
                  onTap: _onMapTap,
                ),
                children: [
                  TileLayer(
                    urlTemplate: isDark
                        ? 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png'
                        : 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c'],
                  ),
                  if (_pickupLocation != null && _dropoffLocation != null)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: [_pickupLocation!, _dropoffLocation!],
                          strokeWidth: 4.5,
                          color: AppTokens.primary,
                        ),
                      ],
                    ),
                  MarkerLayer(
                    markers: [
                      // User Current Location Glowing Ripple Marker
                      if (_currentLocation != null)
                        Marker(
                          point: _currentLocation!,
                          width: 60,
                          height: 60,
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 40 + (16 * _pulseController.value),
                                    height: 40 + (16 * _pulseController.value),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTokens.primary.withOpacity(0.3 * (1 - _pulseController.value)),
                                    ),
                                  ),
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppTokens.primary,
                                      border: Border.all(color: Colors.white, width: 3),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(Icons.person, color: Colors.white, size: 14),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                      // Custom Pickup Marker (if different from GPS)
                      if (_pickupLocation != null && _pickupLocation != _currentLocation)
                        Marker(
                          point: _pickupLocation!,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.circle_outlined, color: Colors.white, size: 20),
                          ),
                        ),

                      // Dropoff Marker (Red Pin)
                      if (_dropoffLocation != null)
                        Marker(
                          point: _dropoffLocation!,
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 44),
                        ),
                    ],
                  ),
                ],
              ),
            ),

          // IndexedStack for Main Screen Tabs
          Positioned.fill(
            child: IndexedStack(
              index: _tabIndex,
              children: [
                _buildHomeOverlay(appState),
                const HistoryScreen(),
                const WalletScreen(),
                const ProfileScreen(),
              ],
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

  Widget _buildHomeOverlay(AppState appState) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Top Action Bar: Theme Switcher & Language Switcher
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Theme Switcher Button
              Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                child: IconButton(
                  icon: Icon(
                    appState.themeMode == ThemeMode.dark ? Icons.wb_sunny : Icons.nightlight_round,
                    color: AppTokens.primary,
                  ),
                  tooltip: isAr ? 'تغيير المظهر' : 'Toggle Theme',
                  onPressed: () => appState.toggleTheme(),
                ),
              ),

              // Language Switcher Button
              Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(20),
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                child: InkWell(
                  onTap: () => appState.toggleLanguage(),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.language, size: 18, color: AppTokens.primary),
                        const SizedBox(width: 6),
                        Text(
                          isAr ? 'English' : 'العربية',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : AppTokens.lightText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Pickup & Destination Search Box (Matching Screenshot 2)
        Positioned(
          top: MediaQuery.of(context).padding.top + 64,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                // Swap Icon (⇅) on left
                IconButton(
                  onPressed: _swapLocations,
                  icon: const Icon(Icons.swap_vert, size: 26, color: Color(0xFF334155)),
                  tooltip: isAr ? 'تبديل الأماكن' : 'Swap locations',
                ),
                const SizedBox(width: 8),

                // Main Text Inputs Column
                Expanded(
                  child: Column(
                    children: [
                      // Pickup Input Field Box
                      GestureDetector(
                        onTap: () => _openLocationSearchModal(true),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? const Color(0xFF475569) : const Color(0xFF64748B)),
                          ),
                          child: Align(
                            alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                            child: Text(
                              _pickupText.isNotEmpty
                                  ? _pickupText
                                  : (isAr ? 'اختر نقطة بداية، أو انقر على الخريطة...' : 'Choose starting point...'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 13,
                                color: _pickupText.isNotEmpty
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Destination Input Field Box
                      GestureDetector(
                        onTap: () => _openLocationSearchModal(false),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? const Color(0xFF475569) : const Color(0xFF64748B)),
                          ),
                          child: Align(
                            alignment: isAr ? Alignment.centerRight : Alignment.centerLeft,
                            child: Text(
                              _dropoffText.isNotEmpty
                                  ? _dropoffText
                                  : (isAr ? 'اختر الوجهة...' : 'Choose destination...'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 13,
                                color: _dropoffText.isNotEmpty
                                    ? (isDark ? Colors.white : Colors.black87)
                                    : (isDark ? Colors.grey[400] : Colors.grey[600]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Circle (O) + Dots (:) + Red Pin (📍) Column on Right
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Hollow Circle Icon (O)
                    const Icon(Icons.radio_button_unchecked, size: 18, color: Colors.black87),
                    const SizedBox(height: 2),
                    // Dotted Line (:)
                    Text(
                      '⋮',
                      style: TextStyle(
                        fontSize: 14,
                        height: 0.8,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Red Location Pin Icon (📍)
                    const Icon(Icons.location_on, size: 20, color: Color(0xFFEF4444)),
                  ],
                ),
              ],
            ),
          ),
        ),

        // FAB to Recenter GPS on map
        Positioned(
          bottom: 24,
          left: isAr ? 16 : null,
          right: isAr ? null : 16,
          child: FloatingActionButton(
            heroTag: 'recenter_gps',
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            onPressed: _onCenterTap,
            child: const Icon(Icons.my_location, color: AppTokens.primary),
          ),
        ),
      ],
    );
  }
}

/// Location Search Sheet with Live Autocomplete & Quick Egypt Spots Suggestions
class _LocationSearchSheet extends StatefulWidget {
  final bool isPickup;
  final LatLng? currentLocation;
  final Function(String address, LatLng latLng) onSelectLocation;

  const _LocationSearchSheet({
    required this.isPickup,
    this.currentLocation,
    required this.onSelectLocation,
  });

  @override
  State<_LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<_LocationSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];

  // Egyptian Popular Destinations
  final List<Map<String, dynamic>> _popularEgyptSpots = [
    {
      'title': 'ميدان التحرير، وسط البلد',
      'titleEn': 'Tahrir Square, Downtown Cairo',
      'lat': 30.0444,
      'lng': 31.2357,
      'icon': Icons.location_city,
    },
    {
      'title': 'مطار القاهرة الدولي (صالة 3)',
      'titleEn': 'Cairo International Airport (T3)',
      'lat': 30.1219,
      'lng': 31.4056,
      'icon': Icons.flight_takeoff,
    },
    {
      'title': 'سيتي ستارز مول، مدينة نصر',
      'titleEn': 'Citystars Mall, Nasr City',
      'lat': 30.0732,
      'lng': 31.3465,
      'icon': Icons.shopping_bag_outlined,
    },
    {
      'title': 'مول العرب، 6 أكتوبر',
      'titleEn': 'Mall of Arabia, 6th of October',
      'lat': 29.9998,
      'lng': 30.9701,
      'icon': Icons.shopping_cart_outlined,
    },
    {
      'title': 'شارع 9، المعادي',
      'titleEn': 'Road 9, Maadi',
      'lat': 29.9592,
      'lng': 31.2612,
      'icon': Icons.storefront,
    },
    {
      'title': 'برج القاهرة، الزمالك',
      'titleEn': 'Cairo Tower, Zamalek',
      'lat': 30.0459,
      'lng': 31.2243,
      'icon': Icons.attractions,
    },
  ];

  void _onQueryChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _searchResults = [];
        _searching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      setState(() => _searching = true);
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search?format=json&accept-language=ar&countrycodes=eg&q=${Uri.encodeComponent(query)}',
        );
        final res = await http.get(uri, headers: {'User-Agent': 'GoDriveRiderApp/1.0'});
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as List;
          if (mounted) {
            setState(() {
              _searchResults = data.map((item) {
                return {
                  'title': item['display_name'] as String,
                  'lat': double.parse(item['lat']),
                  'lng': double.parse(item['lon']),
                };
              }).toList();
              _searching = false;
            });
          }
        }
      } catch (_) {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _onQueryChanged,
                decoration: InputDecoration(
                  hintText: widget.isPickup
                      ? (isAr ? 'ابحث عن نقطة الانطلاق...' : 'Search starting point...')
                      : (isAr ? 'ابحث عن الوجهة...' : 'Search destination...'),
                  prefixIcon: Icon(
                    widget.isPickup ? Icons.circle_outlined : Icons.location_on,
                    color: widget.isPickup ? AppTokens.primary : const Color(0xFFEF4444),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onQueryChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (_searching)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // If user searched and got results
                    if (_searchResults.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          isAr ? 'نتائج البحث' : 'Search Results',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.bold,
                            color: AppTokens.primary,
                          ),
                        ),
                      ),
                      ..._searchResults.map((item) {
                        return ListTile(
                          leading: const Icon(Icons.place_outlined, color: AppTokens.primary),
                          title: Text(
                            item['title'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.ibmPlexSansArabic(fontSize: 14),
                          ),
                          onTap: () {
                            widget.onSelectLocation(
                              item['title'],
                              LatLng(item['lat'], item['lng']),
                            );
                            Navigator.pop(context);
                          },
                        );
                      }),
                    ] else ...[
                      // Option for current GPS location if pickup
                      if (widget.isPickup && widget.currentLocation != null)
                        ListTile(
                          leading: const Icon(Icons.my_location, color: AppTokens.primary),
                          title: Text(
                            isAr ? 'موقعي الحالي (GPS)' : 'Current Location (GPS)',
                            style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            isAr ? 'استخدام الموقع الحالي بالجهاز' : 'Use current device location',
                            style: GoogleFonts.ibmPlexSansArabic(fontSize: 12),
                          ),
                          onTap: () {
                            widget.onSelectLocation(
                              isAr ? 'موقعي الحالي (GPS)' : 'Current Location (GPS)',
                              widget.currentLocation!,
                            );
                            Navigator.pop(context);
                          },
                        ),
                      const Divider(),

                      // Popular Egypt Places Suggestions
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          isAr ? 'أماكن مقترحة وشائعة' : 'Popular Suggestions',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ),
                      ..._popularEgyptSpots.map((spot) {
                        final title = isAr ? spot['title'] : spot['titleEn'];
                        return ListTile(
                          leading: Icon(spot['icon'] as IconData, color: AppTokens.primary),
                          title: Text(title, style: GoogleFonts.ibmPlexSansArabic(fontSize: 14)),
                          onTap: () {
                            widget.onSelectLocation(
                              title,
                              LatLng(spot['lat'] as double, spot['lng'] as double),
                            );
                            Navigator.pop(context);
                          },
                        );
                      }),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

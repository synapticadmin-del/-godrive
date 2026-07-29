import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:latlong2/latlong.dart';

import '../../services/location_service.dart';

/// Destination search, backed by the GoDrive geocoding endpoint.
///
/// Two things changed versus the previous implementation:
///  1. Queries go to our backend (`/geocode/search`) instead of hitting
///     Nominatim directly from the handset. Calling Nominatim from an end-user
///     app violates their usage policy and risks an IP-range ban; the backend
///     also caches results and rate-limits properly.
///  2. Results are ordered by proximity to the rider and show how far away
///     each one is, so searching "مسجد" surfaces the nearby mosque instead of
///     one in a different governorate.
class LocationSearchSheet extends StatefulWidget {
  const LocationSearchSheet({
    super.key,
    required this.isPickup,
    required this.locations,
    required this.onSelectLocation,
    this.currentLocation,
    this.onPickOnMap,
  });

  final bool isPickup;
  final LatLng? currentLocation;
  final LocationService locations;
  final void Function(String label, LatLng location) onSelectLocation;

  /// Opens the centre-pin picker. The sheet closes first so the rider sees
  /// the map immediately.
  final VoidCallback? onPickOnMap;

  @override
  State<LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<LocationSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  final Debouncer _debouncer = Debouncer(milliseconds: 400);

  List<PlaceResult> _results = const [];
  bool _searching = false;
  String? _error;

  /// Well-known destinations, shown before the rider types anything.
  static const List<_QuickSpot> _quickSpots = [
    _QuickSpot('ميدان التحرير، وسط البلد', 'Tahrir Square, Downtown Cairo',
        30.0444, 31.2357, Icons.location_city_rounded),
    _QuickSpot('مطار القاهرة الدولي (صالة 3)',
        'Cairo International Airport (T3)', 30.1219, 31.4056,
        Icons.flight_takeoff_rounded),
    _QuickSpot('سيتي ستارز، مدينة نصر', 'Citystars, Nasr City', 30.0732,
        31.3465, Icons.shopping_bag_outlined),
    _QuickSpot('مول العرب، 6 أكتوبر', 'Mall of Arabia, 6th of October',
        29.9998, 30.9701, Icons.shopping_cart_outlined),
    _QuickSpot('شارع 9، المعادي', 'Road 9, Maadi', 29.9592, 31.2612,
        Icons.storefront_rounded),
    _QuickSpot('برج القاهرة، الزمالك', 'Cairo Tower, Zamalek', 30.0459,
        31.2243, Icons.attractions_rounded),
  ];

  @override
  void dispose() {
    _controller.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    final q = query.trim();

    if (q.length < 2) {
      _debouncer.cancel();
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }

    setState(() => _searching = true);
    _debouncer.run(() => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await widget.locations.searchPlaces(
        query,
        near: widget.currentLocation,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      final isAr = Localizations.localeOf(context).languageCode == 'ar';
      setState(() {
        _searching = false;
        _results = const [];
        _error = isAr
            ? 'تعذّر البحث الآن. تحقق من الاتصال وحاول مرة أخرى.'
            : 'Search unavailable. Check your connection and try again.';
      });
    }
  }

  void _select(String label, LatLng location) {
    widget.onSelectLocation(label, location);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: BoxDecoration(
          color: go.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: go.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(
                    widget.isPickup
                        ? Icons.trip_origin_rounded
                        : Icons.place_rounded,
                    size: 20,
                    color: widget.isPickup ? go.pinPickup : go.pinDropoff,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.isPickup
                        ? (isAr ? 'نقطة الانطلاق' : 'Pickup point')
                        : (isAr ? 'الوجهة' : 'Destination'),
                    style: AppTokens.font(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: go.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                style: AppTokens.font(
                  fontSize: 15,
                  color: go.text,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: widget.isPickup
                      ? (isAr ? 'ابحث عن نقطة الانطلاق' : 'Search pickup')
                      : (isAr ? 'ابحث عن الوجهة' : 'Search destination'),
                  prefixIcon: Icon(Icons.search_rounded, color: go.muted),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: go.muted),
                          onPressed: () {
                            _controller.clear();
                            _onQueryChanged('');
                          },
                        ),
                  filled: true,
                  fillColor: go.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    borderSide: BorderSide(color: go.action, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),

            Expanded(child: _buildBody(go, isAr)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GoTheme go, bool isAr) {
    if (_searching) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        itemCount: 5,
        itemBuilder: (_, __) => _ResultSkeleton(go: go),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 38, color: go.muted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTokens.font(
                  fontSize: 14,
                  color: go.muted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final query = _controller.text.trim();

    if (query.length >= 2 && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 38, color: go.muted),
              const SizedBox(height: 12),
              Text(
                isAr
                    ? 'لا توجد نتائج لهذا البحث'
                    : 'No places match that search',
                style: AppTokens.font(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: go.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isAr
                    ? 'جرّب اسمًا أبسط، أو حدّد المكان على الخريطة'
                    : 'Try a simpler name, or set the point on the map',
                textAlign: TextAlign.center,
                style: AppTokens.font(
                  fontSize: 13,
                  color: go.muted,
                ),
              ),
              const SizedBox(height: 18),
              _MapPickButton(go: go, isAr: isAr, onTap: _pickOnMap),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        if (_results.isNotEmpty) ...[
          _SectionLabel(go: go, text: isAr ? 'نتائج البحث' : 'Results'),
          ..._results.map(
            (place) => _PlaceTile(
              go: go,
              icon: Icons.place_outlined,
              title: place.label,
              subtitle: place.secondary,
              trailing: place.distanceLabel(isArabic: isAr),
              onTap: () => _select(place.label, place.location),
            ),
          ),
        ] else ...[
          _ActionTile(
            go: go,
            icon: Icons.map_rounded,
            title: isAr ? 'تحديد على الخريطة' : 'Set on map',
            subtitle: isAr
                ? 'حرّك الخريطة لضبط المكان بدقة'
                : 'Move the map to place the pin precisely',
            onTap: _pickOnMap,
          ),
          if (widget.isPickup && widget.currentLocation != null)
            _ActionTile(
              go: go,
              icon: Icons.my_location_rounded,
              title: isAr ? 'موقعي الحالي' : 'My current location',
              subtitle: isAr ? 'استخدام موقع الجهاز' : 'Use device location',
              onTap: () => _select(
                isAr ? 'موقعي الحالي (GPS)' : 'Current location (GPS)',
                widget.currentLocation!,
              ),
            ),
          const SizedBox(height: 10),
          _SectionLabel(
            go: go,
            text: isAr ? 'أماكن شائعة' : 'Popular places',
          ),
          ..._quickSpots.map((spot) {
            final location = LatLng(spot.lat, spot.lng);
            final label = isAr ? spot.ar : spot.en;
            return _PlaceTile(
              go: go,
              icon: spot.icon,
              title: label,
              trailing: _quickSpotDistance(location, isAr),
              onTap: () => _select(label, location),
            );
          }),
        ],
      ],
    );
  }

  String? _quickSpotDistance(LatLng target, bool isAr) {
    final origin = widget.currentLocation;
    if (origin == null) return null;
    const distance = Distance();
    final km = distance.as(LengthUnit.Kilometer, origin, target).toDouble();
    if (km < 1) return isAr ? '${(km * 1000).round()} م' : '${(km * 1000).round()} m';
    return isAr ? '${km.toStringAsFixed(1)} كم' : '${km.toStringAsFixed(1)} km';
  }

  void _pickOnMap() {
    Navigator.pop(context);
    widget.onPickOnMap?.call();
  }
}

class _QuickSpot {
  const _QuickSpot(this.ar, this.en, this.lat, this.lng, this.icon);
  final String ar;
  final String en;
  final double lat;
  final double lng;
  final IconData icon;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.go, required this.text});

  final GoTheme go;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: AppTokens.font(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: go.muted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.go,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final GoTheme go;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: go.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: go.muted),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.font(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: go.text,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.font(
                          fontSize: 12.5,
                          color: go.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Text(
                  trailing!,
                  style: AppTokens.font(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: go.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.go,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final GoTheme go;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 21, color: go.isDark ? go.action : AppTokens.primary),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTokens.font(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: go.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTokens.font(
                          fontSize: 12.5,
                          color: go.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: go.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPickButton extends StatelessWidget {
  const _MapPickButton({
    required this.go,
    required this.isAr,
    required this.onTap,
  });

  final GoTheme go;
  final bool isAr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.map_rounded, size: 19),
      style: ElevatedButton.styleFrom(
        backgroundColor: go.action,
        foregroundColor: go.onAction,
        minimumSize: const Size(220, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
      ),
      label: Text(
        isAr ? 'تحديد على الخريطة' : 'Set on map',
        style: AppTokens.font(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ResultSkeleton extends StatelessWidget {
  const _ResultSkeleton({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: go.surface,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: go.surface,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 13),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [bar(170, 11), const SizedBox(height: 7), bar(110, 9)],
          ),
        ],
      ),
    );
  }
}

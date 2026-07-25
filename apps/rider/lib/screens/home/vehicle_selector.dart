import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// Top-level service categories, shown as a horizontal strip above the search
/// field on the home screen — the pattern riders recognise from inDrive.
///
/// These are *service kinds* (a ride, an intercity trip, freight, a tuk-tuk),
/// which is a different axis from [VehicleSelector] below — that one picks the
/// car class once a fare is being quoted.
class VehicleCategoryStrip extends StatelessWidget {
  const VehicleCategoryStrip({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.isArabic,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool isArabic;

  static const _categories = <_Category>[
    _Category('ride', 'رحلة', 'Ride', Icons.local_taxi_rounded),
    _Category('intercity', 'سفر', 'Intercity', Icons.luggage_rounded),
    _Category('freight', 'الشحن', 'Freight', Icons.local_shipping_rounded),
    _Category('tuktuk', 'تروسيكل', 'Tuk-tuk', Icons.electric_rickshaw_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final c = _categories[index];
          final isSelected = c.id == selected;

          return _CategoryChip(
            go: go,
            icon: c.icon,
            label: isArabic ? c.ar : c.en,
            selected: isSelected,
            onTap: () => onChanged(c.id),
          );
        },
      ),
    );
  }
}

class _Category {
  const _Category(this.id, this.ar, this.en, this.icon);
  final String id;
  final String ar;
  final String en;
  final IconData icon;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.go,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final GoTheme go;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // In dark mode the selected chip uses the lime action colour; in light
    // mode a soft green wash keeps the strip from shouting over the map.
    final selectedBg = go.isDark ? go.action : AppTokens.primaryLight;
    final selectedFg = go.isDark ? go.onAction : AppTokens.primaryDark;

    return Material(
      color: selected ? selectedBg : go.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 86,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(
              color: selected ? Colors.transparent : go.border,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 23,
                color: selected ? selectedFg : go.muted,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.ibmPlexSansArabic(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? selectedFg : go.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Car-class picker shown inside the fare sheet once a route is priced.
///
/// The public API ([fareEstimate], [onSelect]) is unchanged so existing
/// callers keep working; the visuals now follow the active light/dark theme
/// instead of being hardcoded to light surfaces.
class VehicleSelector extends StatefulWidget {
  const VehicleSelector({
    super.key,
    required this.fareEstimate,
    required this.onSelect,
  });

  final Map<String, dynamic>? fareEstimate;
  final Function(String) onSelect;

  @override
  State<VehicleSelector> createState() => _VehicleSelectorState();
}

class _VehicleSelectorState extends State<VehicleSelector> {
  String _selected = 'economy';

  static const _vehicles = <_VehicleClass>[
    _VehicleClass('economy', 'اقتصادي', 'Economy', Icons.directions_car_rounded, 1.0),
    _VehicleClass('comfort', 'كومفورت', 'Comfort', Icons.airport_shuttle_rounded, 1.3),
    _VehicleClass('xl', 'عائلي', 'Family', Icons.airline_seat_recline_normal_rounded, 1.6),
  ];

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final estimate = widget.fareEstimate;
    final fare = estimate?['fare'];
    final basePrice = fare is Map
        ? (fare['total'] as num?)?.toDouble() ?? 0.0
        : (estimate?['estimatedFare'] as num?)?.toDouble() ?? 0.0;

    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: _vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final v = _vehicles[index];
          final isSelected = _selected == v.id;
          final price = (basePrice * v.multiplier).round();

          final selectedBorder = go.isDark ? go.action : AppTokens.primary;
          final selectedTint = go.isDark
              ? go.action.withOpacity(0.14)
              : AppTokens.primaryLight;

          return GestureDetector(
            onTap: () {
              setState(() => _selected = v.id);
              widget.onSelect(_selected);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 112,
              decoration: BoxDecoration(
                color: isSelected ? selectedTint : go.surface,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: isSelected ? selectedBorder : go.border,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    v.icon,
                    size: 34,
                    color: isSelected
                        ? (go.isDark ? go.action : AppTokens.primary)
                        : go.muted,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    isAr ? v.ar : v.en,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 13,
                      color: go.text,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isAr ? '$price ج.م' : '$price EGP',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? (go.isDark ? go.action : AppTokens.primary)
                          : go.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VehicleClass {
  const _VehicleClass(this.id, this.ar, this.en, this.icon, this.multiplier);
  final String id;
  final String ar;
  final String en;
  final IconData icon;
  final double multiplier;
}

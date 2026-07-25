import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';

class VehicleSelector extends StatefulWidget {
  final Map<String, dynamic>? fareEstimate;
  final Function(String) onSelect;

  const VehicleSelector({super.key, required this.fareEstimate, required this.onSelect});

  @override
  State<VehicleSelector> createState() => _VehicleSelectorState();
}

class _VehicleSelectorState extends State<VehicleSelector> {
  String _selected = 'economy';

  @override
  Widget build(BuildContext context) {
    final estimate = widget.fareEstimate;
    final economyPrice = estimate?['estimatedFare'] ?? 0;
    
    final vehicles = [
      {'id': 'economy', 'name': 'اقتصادي', 'icon': Icons.directions_car, 'multiplier': 1.0},
      {'id': 'comfort', 'name': 'كومفورت', 'icon': Icons.airport_shuttle, 'multiplier': 1.3},
      {'id': 'xl', 'name': 'عائلي', 'icon': Icons.car_rental, 'multiplier': 1.6},
    ];

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: vehicles.length,
        itemBuilder: (context, index) {
          final v = vehicles[index];
          final isSelected = _selected == v['id'];
          final price = (economyPrice * (v['multiplier'] as double)).toStringAsFixed(2);

          return GestureDetector(
            onTap: () {
              setState(() => _selected = v['id'] as String);
              widget.onSelect(_selected);
            },
            child: Container(
              width: 110,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppTokens.primary.withOpacity(0.1) : AppTokens.lightSurface,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                border: Border.all(
                  color: isSelected ? AppTokens.primary : AppTokens.lightBorder,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(v['icon'] as IconData, size: 40, color: isSelected ? AppTokens.primary : AppTokens.lightMuted),
                  const SizedBox(height: 8),
                  Text(
                    v['name'] as String,
                    style: GoogleFonts.ibmPlexSansArabic(
                      color: AppTokens.lightText,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    '$price ج.م',
                    style: GoogleFonts.ibmPlexSansArabic(
                      color: isSelected ? AppTokens.primary : AppTokens.lightMuted,
                      fontSize: 12,
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

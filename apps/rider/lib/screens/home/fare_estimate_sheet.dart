import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';
import '../trip/trip_screen.dart';
import 'vehicle_selector.dart';

class FareEstimateSheet extends StatefulWidget {
  final LatLng pickup;
  final LatLng dropoff;

  const FareEstimateSheet({super.key, required this.pickup, required this.dropoff});

  @override
  State<FareEstimateSheet> createState() => _FareEstimateSheetState();
}

class _FareEstimateSheetState extends State<FareEstimateSheet> {
  bool _loading = true;
  Map<String, dynamic>? _estimate;
  String _selectedVehicle = 'economy';
  bool _booking = false;

  @override
  void initState() {
    super.initState();
    _fetchEstimate();
  }

  Future<void> _fetchEstimate() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final res = await context.read<AppState>().estimateTrip(
        pickupLat: widget.pickup.latitude,
        pickupLng: widget.pickup.longitude,
        dropoffLat: widget.dropoff.latitude,
        dropoffLng: widget.dropoff.longitude,
      );
      if (!mounted) return;
      setState(() {
        _estimate = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      navigator.pop();
    }
  }

  Future<void> _bookTrip() async {
    setState(() => _booking = true);
    try {
      final state = context.read<AppState>();
      // Reverse-geocode pickup + dropoff to real street addresses before
      // creating the trip — avoids sending placeholder strings.
      String pickupAddr = '';
      String dropoffAddr = '';
      try {
        final pickupRes = await state.apiGet(
          '/geocode/reverse?lat=${widget.pickup.latitude}&lng=${widget.pickup.longitude}',
        );
        pickupAddr = pickupRes['display_name'] ?? pickupRes['address'] ?? '';
      } catch (_) {}
      try {
        final dropRes = await state.apiGet(
          '/geocode/reverse?lat=${widget.dropoff.latitude}&lng=${widget.dropoff.longitude}',
        );
        dropoffAddr = dropRes['display_name'] ?? dropRes['address'] ?? '';
      } catch (_) {}

      final res = await state.createTrip(
        pickupLat: widget.pickup.latitude,
        pickupLng: widget.pickup.longitude,
        dropoffLat: widget.dropoff.latitude,
        dropoffLng: widget.dropoff.longitude,
        pickupAddress: pickupAddr.isNotEmpty ? pickupAddr : '${widget.pickup.latitude.toStringAsFixed(4)}, ${widget.pickup.longitude.toStringAsFixed(4)}',
        dropoffAddress: dropoffAddr.isNotEmpty ? dropoffAddr : '${widget.dropoff.latitude.toStringAsFixed(4)}, ${widget.dropoff.longitude.toStringAsFixed(4)}',
      );
      // Selected vehicle type: $_selectedVehicle
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => TripScreen(tripId: res['trip']['id'])));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTokens.lightPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
      ),
      padding: const EdgeInsets.all(24),
      child: _loading
          ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: AppTokens.lightBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 24),
                Text('تفاصيل الرحلة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 20, fontWeight: FontWeight.bold, color: AppTokens.lightText)),
                const SizedBox(height: 16),
                VehicleSelector(
                  fareEstimate: _estimate,
                  onSelect: (val) => setState(() => _selectedVehicle = val),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('طريقة الدفع', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
                    Row(
                      children: [
                        const Icon(Icons.money, color: AppTokens.success, size: 20),
                        const SizedBox(width: 8),
                        Text('نقداً', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.success, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _booking ? null : _bookTrip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                  ),
                  child: _booking
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                      : Text('اطلب رحلة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
    );
  }
}

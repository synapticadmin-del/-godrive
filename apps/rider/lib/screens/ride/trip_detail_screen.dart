import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

/// Trip detail screen — shown when a rider taps a completed trip in history.
/// Shows route summary, fare breakdown, captain info, rating, and receipt.
class TripDetailScreen extends StatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Map<String, dynamic>? _trip;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await context.read<AppState>().getTrip(widget.tripId);
      setState(() { _trip = res['trip']; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.tripDetailTitle,
          style: AppTokens.font(fontWeight: FontWeight.w700),
        ),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : _trip == null
                  ? EmptyState(
                      icon: Icons.route_outlined,
                      title: strings.tripNotFound,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // Status + date
                        _headerCard(go, strings),
                        const SizedBox(height: 16),
                        // Route
                        _routeCard(go, strings),
                        const SizedBox(height: 16),
                        // Fare breakdown
                        _fareCard(go, strings),
                        const SizedBox(height: 16),
                        // Captain info
                        if (_trip!['captain_name'] != null)
                          _captainCard(go, strings),
                      ],
                    ),
    );
  }

  Widget _headerCard(GoTheme go, AppStrings strings) {
    final status = _trip!['status'] as String? ?? '';
    final fare = (_trip!['final_fare'] as num?)?.toDouble() ?? (_trip!['estimated_fare'] as num?)?.toDouble() ?? 0;
    final date = (_trip!['created_at'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border),
      ),
      child: Column(children: [
        StatusChip(label: strings.statusLabel(status), variant: _statusVariant(status), icon: _statusIcon(status)),
        const SizedBox(height: 16),
        Text(
          '${fare.toStringAsFixed(0)} ${strings.egp}',
          style: AppTokens.font(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppTokens.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          date.substring(0, date.length >= 16 ? 16 : date.length),
          style: AppTokens.font(fontSize: 13, color: go.muted),
        ),
      ]),
    );
  }

  Widget _routeCard(GoTheme go, AppStrings strings) {
    final pickup = (_trip!['pickup_address'] as String?) ?? strings.unknownPickup;
    final dropoff = (_trip!['dropoff_address'] as String?) ?? strings.unknownDropoff;
    final distance = (_trip!['distance_km'] as num?)?.toDouble();
    final duration = (_trip!['duration_min'] as num?)?.toDouble();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          strings.tripRouteTitle,
          style: AppTokens.font(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: go.text,
          ),
        ),
        const SizedBox(height: 16),
        _routeRow(go, Icons.location_on, AppTokens.primary, pickup),
        if (distance != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Text(
                strings.tripDistanceKmLine(distance.toStringAsFixed(1)),
                style: AppTokens.font(fontSize: 12, color: go.muted),
              ),
              if (duration != null) ...[
                const SizedBox(width: 12),
                Text(
                  strings.tripDurationMinutes(duration.round()),
                  style: AppTokens.font(fontSize: 12, color: go.muted),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 12),
        _routeRow(go, Icons.flag, AppTokens.accent, dropoff),
      ]),
    );
  }

  Widget _fareCard(GoTheme go, AppStrings strings) {
    final fare = (_trip!['final_fare'] as num?)?.toDouble() ?? (_trip!['estimated_fare'] as num?)?.toDouble() ?? 0;
    final discount = (_trip!['discount'] as num?)?.toDouble() ?? 0;
    final commission = (_trip!['commission'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          strings.tripFareDetailsTitle,
          style: AppTokens.font(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: go.text,
          ),
        ),
        const SizedBox(height: 12),
        _fareRow(go, strings, strings.tripFareRowLabel, fare, go.text),
        if (discount > 0) _fareRow(go, strings, strings.tripDiscountLabel, -discount, AppTokens.success),
        const Divider(height: 20),
        _fareRow(go, strings, strings.tripTotalLabel, fare - discount, AppTokens.primary, bold: true),
        if (commission > 0) ...[
          const SizedBox(height: 4),
          _fareRow(go, strings, strings.platformCommission, commission, go.muted, small: true),
        ],
      ]),
    );
  }

  Widget _captainCard(GoTheme go, AppStrings strings) {
    final name = (_trip!['captain_name'] as String?) ?? strings.riderCaptainFallback;
    final plate = _trip!['vehicle_plate'];
    final rating = _trip!['rating_avg'];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppTokens.primary.withOpacity(0.15),
          child: Text(
            name.substring(0, 1),
            style: const TextStyle(
              color: AppTokens.primary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              name,
              style: AppTokens.font(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: go.text,
              ),
            ),
            if (plate != null)
              Text(
                plate,
                style: AppTokens.font(fontSize: 13, color: go.muted),
              ),
          ]),
        ),
        if (rating != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTokens.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star, color: AppTokens.accent, size: 14),
              const SizedBox(width: 4),
              Text(
                '$rating',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.accent,
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _routeRow(GoTheme go, IconData icon, Color color, String label) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          label,
          style: AppTokens.font(fontSize: 14, color: go.text),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }

  Widget _fareRow(GoTheme go, AppStrings strings, String label, double amount, Color color, {bool bold = false, bool small = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(
          label,
          style: AppTokens.font(
            fontSize: small ? 11 : 14,
            color: color.withOpacity(small ? 0.7 : 1),
          ),
        ),
        Text(
          '${amount.toStringAsFixed(0)} ${strings.egp}',
          style: AppTokens.font(
            fontSize: small ? 11 : (bold ? 18 : 14),
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            color: color,
          ),
        ),
      ]),
    );
  }

  StatusVariant _statusVariant(String s) => switch (s) {
    'completed' => StatusVariant.success,
    'cancelled' => StatusVariant.danger,
    'in_progress' || 'assigned' => StatusVariant.info,
    _ => StatusVariant.neutral,
  };
  IconData _statusIcon(String s) => switch (s) {
    'completed' => Icons.check_circle,
    'cancelled' => Icons.cancel,
    _ => Icons.route,
  };
}

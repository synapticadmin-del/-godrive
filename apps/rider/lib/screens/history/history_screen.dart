import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:intl/intl.dart';
import '../../services/app_state.dart';

import '../ride/trip_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final res = await context.read<AppState>().apiGet('/trips');
      if (mounted) {
        setState(() {
          _trips = res['trips'] ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.tripHistoryTitle, style: AppTokens.font(color: go.text)),
        backgroundColor: go.panel,
        foregroundColor: go.text,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTokens.primary))
          : _trips.isEmpty
              ? _EmptyTrips(title: strings.noPastTrips, subtitle: strings.noPastTripsHint)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) {
                    final trip = Map<String, dynamic>.from(_trips[index]);
                    final rawDate = trip['created_at'] ?? trip['createdAt'];
                    final date = DateTime.tryParse(rawDate ?? '');
                    final formattedDate = date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : '';

                    return Card(
                      color: go.panel,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: trip['id']?.toString() ?? '')),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(formattedDate, style: AppTokens.font(color: go.muted)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: trip['status'] == 'completed' ? AppTokens.success.withOpacity(0.2) : AppTokens.danger.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                                    ),
                                    child: Text(
                                      trip['status'] == 'completed' ? strings.tripCompleted : strings.tripCancelled,
                                      style: AppTokens.font(
                                        color: trip['status'] == 'completed' ? AppTokens.success : AppTokens.danger,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Column(
                                    children: [
                                      const Icon(Icons.circle, size: 12, color: AppTokens.primary),
                                      Container(width: 2, height: 20, color: go.border),
                                      const Icon(Icons.place, size: 12, color: AppTokens.accent),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(trip['pickup_address'] ?? trip['pickupAddress'] ?? strings.unknownPickup, style: AppTokens.font(color: go.text)),
                                        const SizedBox(height: 12),
                                        Text(trip['dropoff_address'] ?? trip['dropoffAddress'] ?? strings.unknownDropoff, style: AppTokens.font(color: go.text)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              Divider(color: go.border, height: 32),
                              Text(
                                '${trip['final_fare'] ?? trip['estimated_fare'] ?? trip['finalFare'] ?? trip['estimatedFare'] ?? 0} ${strings.egp}',
                                style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.bold, color: AppTokens.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Branded empty state: the packaged illustration when present, with the
/// shared icon-circle fallback underneath it.
class _EmptyTrips extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyTrips({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/empty_trips.png',
              width: 160,
              height: 160,
              errorBuilder: (_, __, ___) => Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTokens.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.route_outlined, size: 32, color: AppTokens.primary),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700, color: go.text),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTokens.font(fontSize: 13, color: go.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

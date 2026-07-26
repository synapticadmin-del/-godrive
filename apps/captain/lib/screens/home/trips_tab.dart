import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

/// Captain's trip history tab — list of all completed and active trips.
///
/// This sits inside an IndexedStack at index 1, directly above the map tile
/// layer. The Scaffold is kept transparent so the IndexedStack's map child (at
/// index 0) can be retained in the widget tree when the captain switches tabs —
/// it just stays hidden behind this screen. Because the map tiles are visible
/// through a transparent background, every content region gets an explicit
/// opaque backdrop using the theme background colour.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<CaptainState>();
      final res = await state.apiGet('/trips');
      final all = (res['trips'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      // Only trips assigned to this captain — the server returns all trips the
      // authenticated user can see, which may include archived or admin rows.
      final mine = all.where((t) => t['captain_id'] == state.user?['id']).toList();
      setState(() {
        _trips = mine;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Opaque backdrop so history text never renders directly over map tiles.
    final bg = isDark ? AppTokens.darkBg : AppTokens.lightBg;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    return Scaffold(
      // Transparent so the IndexedStack retains the map widget on tab 0.
      backgroundColor: Colors.transparent,
      body: Container(
        // Opaque fill that covers the map tiles underneath — without this,
        // list text would be illegible against the satellite/street imagery.
        color: bg,
        child: Column(
          children: [
            _TripsHeader(
              isDark: isDark,
              tripCount: _loading ? null : _trips.length,
              muted: muted,
              border: border,
            ),
            Expanded(
              child: _loading
                  ? const SkeletonList(count: 6)
                  : _error != null
                      ? ErrorState(message: _error!, onRetry: _load)
                      : _trips.isEmpty
                          ? const EmptyState(
                              icon: Icons.route_outlined,
                              title: 'لا توجد رحلات بعد',
                              subtitle: 'ستظهر رحلاتك المكتملة هنا',
                            )
                          : RefreshIndicator(
                              color: AppTokens.primary,
                              onRefresh: _load,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTokens.spaceMd,
                                  AppTokens.spaceXs,
                                  AppTokens.spaceMd,
                                  AppTokens.space2xl,
                                ),
                                itemCount: _trips.length,
                                itemBuilder: (_, i) => _TripCard(
                                  trip: _trips[i],
                                  isDark: isDark,
                                  text: text,
                                  muted: muted,
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen header with a title and a lightweight trip-count summary.
///
/// The count is omitted during loading and while the list is empty — the
/// skeleton / empty-state widgets communicate that state themselves.
class _TripsHeader extends StatelessWidget {
  const _TripsHeader({
    required this.isDark,
    required this.tripCount,
    required this.muted,
    required this.border,
  });

  final bool isDark;

  /// null while loading so the summary line stays hidden.
  final int? tripCount;

  final Color muted;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;

    return Container(
      color: panel,
      padding: EdgeInsetsDirectional.only(
        start: AppTokens.spaceMd,
        end: AppTokens.spaceMd,
        top: MediaQuery.of(context).padding.top + AppTokens.spaceMd,
        bottom: AppTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: panel,
        border: Border(
          bottom: BorderSide(color: border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'رحلاتي',
            textAlign: TextAlign.start,
            style: AppTokens.font(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: text,
            ),
          ),
          if (tripCount != null) ...[
            const SizedBox(height: AppTokens.space2xs),
            Text(
              // Gives the captain a quick count at a glance — derived entirely
              // from already-loaded data, no extra network call.
              '$tripCount ${tripCount == 1 ? 'رحلة' : 'رحلات'} مسجّلة',
              style: AppTokens.font(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.isDark,
    required this.text,
    required this.muted,
  });

  final Map<String, dynamic> trip;
  final bool isDark;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    final status = trip['status'] as String? ?? '';

    // A completed trip's real payout is final_fare; estimated_fare is only the
    // pre-trip quote, so showing it made finished trips display the wrong
    // amount whenever the fare was adjusted on completion.
    final fare = (trip['final_fare'] as num?)?.toDouble() ??
        (trip['estimated_fare'] as num?)?.toDouble() ??
        0;

    final pickup = (trip['pickup_address'] as String?)?.trim();
    final dropoff = (trip['dropoff_address'] as String?)?.trim();

    // substring(0, 10) throws on any timestamp shorter than 10 characters —
    // guard defensively rather than assume ISO-8601 from the server.
    final rawDate = (trip['created_at'] ?? '').toString();
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: border, width: 1),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: status chip on the trailing side, fare on the leading.
            // Fare leads because it is the most decision-relevant fact on a
            // history card — the captain scans earnings, not labels.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Fare — oversized numeral so it reads at arm's length.
                Text(
                  fare.toStringAsFixed(0),
                  style: AppTokens.money(
                    fontSize: 22,
                    color: AppTokens.primary,
                  ),
                ),
                const SizedBox(width: AppTokens.space2xs),
                Text(
                  'ج.م',
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.primary,
                  ),
                ),
                const Spacer(),
                StatusChip(
                  label: _statusLabel(status),
                  variant: _statusVariant(status),
                ),
              ],
            ),

            const SizedBox(height: AppTokens.spaceMd),

            // Route — dot + connector idiom mirrors offer_card.dart so the
            // captain reads the same visual language across the product.
            _buildRoute(
              pickup: (pickup == null || pickup.isEmpty) ? 'موقف غير محدد' : pickup,
              dropoff: (dropoff == null || dropoff.isEmpty) ? 'وجهة غير محددة' : dropoff,
              text: text,
              muted: muted,
              border: border,
            ),

            const SizedBox(height: AppTokens.spaceSm),

            // Date — quiet footer, smaller than the route text.
            Text(
              date,
              style: AppTokens.font(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoute({
    required String pickup,
    required String dropoff,
    required Color text,
    required Color muted,
    required Color border,
  }) {
    return Column(
      children: [
        _addressRow(
          dotColor: AppTokens.primary,
          label: 'من',
          value: pickup,
          text: text,
          muted: muted,
        ),
        // Vertical connector inset to sit directly under the dot centre.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 5),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 2,
              height: 14,
              color: border,
            ),
          ),
        ),
        _addressRow(
          dotColor: AppTokens.danger,
          label: 'إلى',
          value: dropoff,
          text: text,
          muted: muted,
        ),
      ],
    );
  }

  Widget _addressRow({
    required Color dotColor,
    required String label,
    required String value,
    required Color text,
    required Color muted,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor.withOpacity(0.18),
              border: Border.all(color: dotColor, width: 2.5),
            ),
          ),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTokens.font(fontSize: 11, color: muted),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTokens.font(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: text,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'searching':
        return 'بحث';
      case 'offered':
        return 'عرض';
      case 'assigned':
        return 'مُعيّن';
      case 'arrived':
        return 'وصل';
      case 'in_progress':
        return 'جارية';
      case 'completed':
        return 'مكتملة';
      case 'cancelled':
        return 'ملغية';
      default:
        return s;
    }
  }

  StatusVariant _statusVariant(String s) {
    switch (s) {
      case 'completed':
        return StatusVariant.success;
      case 'in_progress':
      case 'assigned':
      case 'arrived':
        return StatusVariant.info;
      case 'cancelled':
        return StatusVariant.danger;
      default:
        return StatusVariant.neutral;
    }
  }
}

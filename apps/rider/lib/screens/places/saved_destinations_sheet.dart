import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import 'saved_places_screen.dart';

/// A saved destination the rider can leave for in one tap.
@immutable
class SavedDestination {
  const SavedDestination({
    required this.id,
    required this.label,
    required this.address,
    required this.point,
  });

  /// Builds one from a `/user/saved-places` row, or null if the row is missing
  /// usable coordinates — a place we cannot route to is worse than absent,
  /// because tapping it would open a trip to nowhere.
  static SavedDestination? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lng = (raw['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;

    final label = (raw['label'] as String?)?.trim();
    return SavedDestination(
      id: raw['id']?.toString() ?? '',
      label: label == null || label.isEmpty ? 'مكان محفوظ' : label,
      address: (raw['address'] as String?)?.trim() ?? '',
      point: LatLng(lat, lng),
    );
  }

  final String id;
  final String label;
  final String address;
  final LatLng point;

  /// Home and Work get their own glyphs; everything else is a generic pin.
  /// Matched against both locales because the label is free text the rider
  /// typed, and the app has shipped in Arabic and English.
  IconData get icon {
    final l = label.toLowerCase();
    if (label == 'المنزل' || l == 'home') return Icons.home_rounded;
    if (label == 'العمل' || l == 'work') return Icons.work_rounded;
    return Icons.place_rounded;
  }
}

/// The "وجهاتي" sheet — the rider's saved places, each one tappable to start a
/// trip from where they are standing right now to that place.
///
/// This is the shortcut the bottom bar's first slot opens. Before it existed
/// the saved places were buried in the profile menu as a *management* screen:
/// you could add and delete them, but never actually go anywhere with one. The
/// whole point of saving "home" is not having to search for it again.
///
/// Distances shown are straight-line, computed on the device. That is
/// deliberate: drawing the real driving route for every row would mean one
/// routing request per saved place every time the sheet opens. The exact route,
/// duration and fare are resolved once, for the one place the rider actually
/// picks.
class SavedDestinationsSheet extends StatefulWidget {
  const SavedDestinationsSheet({
    super.key,
    required this.currentLocation,
    required this.onSelect,
  });

  /// The rider's position, used for the distance hints. Null while the first
  /// fix is still resolving — rows stay tappable, just without a distance.
  final LatLng? currentLocation;

  /// Fired with the chosen destination. The sheet closes first, so the caller
  /// can immediately open the booking flow without stacking two sheets.
  final ValueChanged<SavedDestination> onSelect;

  @override
  State<SavedDestinationsSheet> createState() => _SavedDestinationsSheetState();
}

class _SavedDestinationsSheetState extends State<SavedDestinationsSheet> {
  static const _distance = Distance();

  List<SavedDestination> _places = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await context.read<AppState>().apiGet('/user/saved-places');
      final raw = res['places'];
      final parsed = <SavedDestination>[];
      if (raw is List) {
        for (final row in raw) {
          final place = SavedDestination.fromJson(row);
          if (place != null) parsed.add(place);
        }
      }

      // Nearest first — the place you are most likely heading to next is
      // usually the one closest to you.
      final from = widget.currentLocation;
      if (from != null) {
        parsed.sort((a, b) => _metresFrom(from, a).compareTo(_metresFrom(from, b)));
      }

      if (!mounted) return;
      setState(() {
        _places = parsed;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الوجهات المحفوظة';
        _loading = false;
      });
    }
  }

  double _metresFrom(LatLng from, SavedDestination place) =>
      _distance.as(LengthUnit.Meter, from, place.point).toDouble();

  String? _distanceLabel(SavedDestination place) {
    final from = widget.currentLocation;
    if (from == null) return null;
    final metres = _metresFrom(from, place);
    if (metres < 950) return '${metres.round()} م';
    return '${(metres / 1000).toStringAsFixed(1)} كم';
  }

  void _choose(SavedDestination place) {
    HapticFeedback.selectionClick();
    // Close before handing back: the caller opens the fare sheet next, and two
    // stacked modals leave the rider tapping "back" twice to escape.
    Navigator.pop(context);
    widget.onSelect(place);
  }

  Future<void> _openManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SavedPlacesScreen()),
    );
    if (mounted) _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildGrabber(go),
            _buildHeader(go),
            Flexible(child: _buildBody(go)),
          ],
        ),
      ),
    );
  }

  Widget _buildGrabber(GoTheme go) => Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(top: AppTokens.spaceSm, bottom: AppTokens.spaceXs),
        decoration: BoxDecoration(
          color: go.border,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        ),
      );

  Widget _buildHeader(GoTheme go) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceXs,
        AppTokens.spaceXs,
        AppTokens.spaceSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'وجهاتي',
                  style: AppTokens.font(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'اختر وجهة وابدأ رحلة فورًا من مكانك',
                  style: AppTokens.font(fontSize: 12.5, color: go.muted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openManager,
            icon: const Icon(Icons.settings_outlined, size: 20),
            color: go.muted,
            tooltip: 'إدارة الوجهات',
          ),
        ],
      ),
    );
  }

  Widget _buildBody(GoTheme go) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
        child: SkeletonList(count: 3),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceLg),
        child: ErrorState(message: _error!, onRetry: _fetch),
      );
    }

    if (_places.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
        child: EmptyState(
          icon: Icons.bookmark_border_rounded,
          title: 'لا توجد وجهات محفوظة',
          subtitle: 'احفظ منزلك أو عملك مرة واحدة، وبعد كده رحلتك بضغطة واحدة',
          actionLabel: 'أضف وجهة',
          onAction: _openManager,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        0,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
      ),
      itemCount: _places.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTokens.spaceXs),
      itemBuilder: (_, i) => _buildRow(go, _places[i]),
    );
  }

  Widget _buildRow(GoTheme go, SavedDestination place) {
    final distance = _distanceLabel(place);
    final subtitle = place.address.isNotEmpty
        ? place.address
        : LocationLabel.coordinates(place.point);

    // Material + InkWell rather than GestureDetector: this row is a
    // navigation commitment (it starts a trip), so it should acknowledge the
    // touch with a ripple.
    return Material(
      color: go.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
      child: InkWell(
        onTap: () => _choose(place),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceSm),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTokens.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(place.icon, color: AppTokens.primary, size: 21),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.font(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.font(fontSize: 12, color: go.muted),
                    ),
                  ],
                ),
              ),
              if (distance != null) ...[
                const SizedBox(width: AppTokens.spaceXs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: go.panel,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    border: Border.all(color: go.border),
                  ),
                  child: Text(
                    distance,
                    style: AppTokens.font(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: go.muted,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              // Points the way the rider reads — RTL-aware rather than a
              // hardcoded chevron_left.
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: go.muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small helper so a place with no stored address still shows something
/// meaningful instead of an empty line.
class LocationLabel {
  const LocationLabel._();

  static String coordinates(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../../services/app_state.dart';

/// Result of a completed search: a resolved point for one end of the trip.
class LocationSearchResult {
  const LocationSearchResult({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  final double latitude;
  final double longitude;
  final String address;
}

/// Full-screen search sheet for choosing a pickup or destination point.
///
/// Opened from the home "from / to" fields. Text search debounces through the
/// backend places autocomplete, popular places are offered below the results,
/// and both the device GPS fix and "set on map" escape hatches live here so
/// the rider never gets stuck on a place the geocoder cannot name.
///
/// Every string routes through [AppStrings] — previously the hints, section
/// headers and the no-results empty state were hardcoded Arabic that
/// disappeared when the rider switched to English.
class LocationSearchSheet extends StatefulWidget {
  const LocationSearchSheet({super.key, required this.isPickup});

  /// Whether we are resolving the pickup (true) or the destination (false).
  final bool isPickup;

  /// Opens the sheet and returns the chosen point, or null when dismissed.
  static Future<LocationSearchResult?> show(
    BuildContext context, {
    required bool isPickup,
  }) {
    return showModalBottomSheet<LocationSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LocationSearchSheet(isPickup: isPickup),
    );
  }

  @override
  State<LocationSearchSheet> createState() => _LocationSearchSheetState();
}

class _LocationSearchSheetState extends State<LocationSearchSheet> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  List<dynamic> _results = [];
  List<dynamic> _popular = [];
  bool _searching = false;
  bool _searchUnavailable = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _loadPopular();
    // Opening the keyboard immediately is what makes this feel like a search
    // sheet rather than a page the rider happened to land on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadPopular() async {
    try {
      final res = await context.read<AppState>().apiGet('/places/popular');
      if (!mounted) return;
      setState(() => _popular = (res['places'] as List?) ?? []);
    } catch (_) {
      // Popular places are a convenience, not a blocker — stay silent.
    }
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _search(query.trim());
    });
  }

  Future<void> _search(String query) async {
    setState(() {
      _searching = true;
      _searchUnavailable = false;
    });
    try {
      final res = await context
          .read<AppState>()
          .apiGet('/places/search?q=${Uri.encodeQueryComponent(query)}');
      if (!mounted) return;
      setState(() {
        _results = (res['places'] as List?) ?? [];
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
        _searchUnavailable = true;
      });
    }
  }

  Future<void> _useDeviceLocation() async {
    final strings = AppStrings.of(context);
    setState(() => _locating = true);
    try {
      final state = context.read<AppState>();
      final position = await state.getCurrentPosition();
      if (!mounted) return;
      Navigator.pop(
        context,
        LocationSearchResult(
          latitude: position.latitude,
          longitude: position.longitude,
          address: strings.currentLocationGps,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.locationPermissionDenied)),
      );
    }
  }

  void _setOnMap() {
    // Dismisses without a result: the home screen then enters map-pan
    // mode, moving its pin and reverse-geocoding the map centre.
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final hasQuery = _searchCtrl.text.trim().length >= 2;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: go.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: AppTokens.spaceSm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: go.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.isPickup
                    ? strings.pickupPointLabel
                    : strings.destinationLabel,
                style: AppTokens.font(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: go.muted,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: strings.backTooltip,
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _focusNode,
                    onChanged: _onQueryChanged,
                    style: AppTokens.font(color: go.text),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (q) {
                      if (q.trim().length >= 2) _search(q.trim());
                    },
                    decoration: InputDecoration(
                      hintText: widget.isPickup
                          ? strings.searchPickupHint
                          : strings.searchDestinationHint,
                      hintStyle: AppTokens.font(color: go.muted),
                      prefixIcon: Icon(
                        widget.isPickup
                            ? Icons.radio_button_checked
                            : Icons.location_on_outlined,
                        color: widget.isPickup
                            ? AppTokens.primary
                            : AppTokens.danger,
                      ),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: go.surface,
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: BorderSide(color: go.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: BorderSide(color: go.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: const BorderSide(color: AppTokens.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Escape hatches: GPS fix + drop the pin on the map.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _locating ? null : _useDeviceLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(
                      _locating ? strings.myCurrentLocation : strings.useDeviceLocation,
                      style: AppTokens.font(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _setOnMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      strings.setOnMapAction,
                      style: AppTokens.font(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Expanded(
            child: hasQuery ? _buildResults(go, strings) : _buildPopular(go, strings),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(GoTheme go, AppStrings strings) {
    if (_searchUnavailable) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, color: go.muted, size: 40),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                strings.searchUnavailable,
                textAlign: TextAlign.center,
                style: AppTokens.font(color: go.muted),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                strings.setOnMapSubtitle,
                textAlign: TextAlign.center,
                style: AppTokens.font(fontSize: 12.5, color: go.muted),
              ),
            ],
          ),
        ),
      );
    }

    if (!_searching && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, color: go.muted, size: 40),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                strings.noPlacesFound,
                textAlign: TextAlign.center,
                style: AppTokens.font(color: go.muted),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                strings.trySimplerNameOrMap,
                textAlign: TextAlign.center,
                style: AppTokens.font(fontSize: 12.5, color: go.muted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      children: [
        if (_results.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppTokens.spaceSm,
            ),
            child: Text(
              strings.resultsSection,
              style: AppTokens.font(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: go.muted,
              ),
            ),
          ),
          ..._results.map((place) => _placeTile(place, go)),
        ],
      ],
    );
  }

  Widget _buildPopular(GoTheme go, AppStrings strings) {
    if (_popular.isEmpty) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: Text(
            strings.popularPlacesSection,
            style: AppTokens.font(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: go.muted,
            ),
          ),
        ),
        ..._popular.map((place) => _placeTile(place, go)),
      ],
    );
  }

  Widget _placeTile(dynamic place, GoTheme go) {
    final name = place['name']?.toString() ?? '';
    final address = place['address']?.toString() ?? '';
    final lat = (place['latitude'] as num?)?.toDouble();
    final lng = (place['longitude'] as num?)?.toDouble();

    return ListTile(
      leading: Icon(Icons.place_outlined, color: go.action),
      title: Text(
        name,
        style: AppTokens.font(fontWeight: FontWeight.w600, color: go.text),
      ),
      subtitle: address.isEmpty
          ? null
          : Text(
              address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.font(fontSize: 12.5, color: go.muted),
            ),
      onTap: lat == null || lng == null
          ? null
          : () => Navigator.pop(
                context,
                LocationSearchResult(
                  latitude: lat,
                  longitude: lng,
                  address: address.isEmpty ? name : address,
                ),
              ),
    );
  }
}

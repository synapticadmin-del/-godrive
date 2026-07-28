import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';
import 'fare_estimate_sheet.dart';
import 'location_search_sheet.dart';
import 'travel_mode_bottom_bar.dart';

/// The rider's home: map-first trip planning.
///
/// The map owns the screen. From/to fields sit on top; tapping one either
/// opens the search sheet or switches the map into "move to set the point"
/// mode, where panning the map and confirming reverse-geocodes the centre
/// into that field. Once both ends exist the route is drawn and the fare
/// sheet opens. Tooltips, hints and confirmations were hardcoded Arabic —
/// everything now resolves through [AppStrings] so the whole flow follows the
/// active locale.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? _mapCtrl;

  /// Which end of the trip map-pan mode is currently setting, if any.
  bool? _settingPickupViaMap;
  bool _calculatingRoute = false;

  static const _cairo = LatLng(30.0444, 31.2357);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _goToMyLocation(animate: false);
    });
  }

  Future<void> _goToMyLocation({bool animate = true}) async {
    try {
      final position = await context.read<AppState>().getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      if (animate) {
        await _mapCtrl?.animateCamera(
          CameraUpdate.newLatLngZoom(target, 15.5),
        );
      } else {
        await _mapCtrl?.moveCamera(
          CameraUpdate.newLatLngZoom(target, 15.5),
        );
      }
    } catch (_) {
      // No fix yet — the map simply stays on the default city view.
    }
  }

  Future<void> _openSearch(bool isPickup) async {
    final result = await LocationSearchSheet.show(context, isPickup: isPickup);
    if (result == null || !mounted) return;
    final state = context.read<AppState>();
    if (isPickup) {
      state.setPickup(result.latitude, result.longitude, result.address);
    } else {
      state.setDestination(result.latitude, result.longitude, result.address);
    }
    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(result.latitude, result.longitude), 15.5),
    );
    _maybeFetchRoute();
  }

  void _enterMapPickMode(bool isPickup) {
    setState(() => _settingPickupViaMap = isPickup);
  }

  Future<void> _confirmMapPoint() async {
    final isPickup = _settingPickupViaMap;
    if (isPickup == null || _mapCtrl == null) return;
    final strings = AppStrings.of(context);
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final region = await _mapCtrl!.getVisibleRegion();
      final center = LatLng(
        (region.northeast.latitude + region.southwest.latitude) / 2,
        (region.northeast.longitude + region.southwest.longitude) / 2,
      );
      final address = await state.reverseGeocode(center) ??
          (isPickup
              ? strings.pickupPointFallback
              : strings.destinationPointFallback);
      if (!mounted) return;
      if (isPickup) {
        state.setPickup(center.latitude, center.longitude, address);
      } else {
        state.setDestination(center.latitude, center.longitude, address);
      }
      setState(() => _settingPickupViaMap = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isPickup ? strings.confirmPickup : strings.confirmDestination,
          ),
        ),
      );
      _maybeFetchRoute();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.searchUnavailable)),
      );
    }
  }

  Future<void> _maybeFetchRoute() async {
    final state = context.read<AppState>();
    if (!state.hasBothPoints) return;
    setState(() => _calculatingRoute = true);
    try {
      await state.fetchRoute();
      if (!mounted) return;
      _showFareSheet();
    } catch (_) {
      // Route fetch failures surface in the fare sheet's error state instead.
    } finally {
      if (mounted) setState(() => _calculatingRoute = false);
    }
  }

  void _showFareSheet() {
    final state = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FareEstimateSheet(
        pickupAddress: state.pickupAddress,
        destinationAddress: state.destinationAddress,
        onConfirm: (offer) {
          Navigator.pop(context);
          context.read<AppState>().requestRide(offer: offer);
        },
      ),
    );
  }

  void _swap() {
    context.read<AppState>().swapPoints();
    _maybeFetchRoute();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final state = context.watch<AppState>();
    final pickingOnMap = _settingPickupViaMap != null;

    return Scaffold(
      backgroundColor: go.bg,
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _cairo,
              zoom: 13,
            ),
            onMapCreated: (ctrl) => _mapCtrl = ctrl,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: state.tripMarkers,
            polylines: state.routePolylines,
          ),
          if (pickingOnMap)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_pin,
                  size: 44,
                  color: AppTokens.danger,
                ),
              ),
            ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Container(
                    padding: const EdgeInsets.all(AppTokens.spaceSm),
                    decoration: BoxDecoration(
                      color: go.panel,
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      boxShadow: AppTokens.cardShadow,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              _pointField(
                                icon: Icons.radio_button_checked,
                                color: AppTokens.primary,
                                hint: strings.whereFromHint,
                                value: state.pickupAddress,
                                fallback: strings.pickupPointFallback,
                                tooltip: strings.setPickupPoint,
                                onTap: () => _openSearch(true),
                                onLongPress: () => _enterMapPickMode(true),
                                go: go,
                              ),
                              Divider(color: go.border, height: 1),
                              _pointField(
                                icon: Icons.location_on,
                                color: AppTokens.danger,
                                hint: strings.whereToHint,
                                value: state.destinationAddress,
                                fallback: strings.destinationPointFallback,
                                tooltip: strings.setDestinationPoint,
                                onTap: () => _openSearch(false),
                                onLongPress: () => _enterMapPickMode(false),
                                go: go,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.swap_vert),
                          tooltip: strings.swapLocationsTooltip,
                          color: go.action,
                          onPressed: state.hasBothPoints ? _swap : null,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                if (_calculatingRoute)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMd,
                      vertical: AppTokens.spaceSm,
                    ),
                    decoration: BoxDecoration(
                      color: go.panel,
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Text(
                          '${strings.calculatingRoute} (${strings.approximateLabel})',
                          style: AppTokens.font(fontSize: 13, color: go.muted),
                        ),
                      ],
                    ),
                  ),
                if (pickingOnMap)
                  Padding(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppTokens.spaceSm),
                          decoration: BoxDecoration(
                            color: go.panel,
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusMd,
                            ),
                          ),
                          child: Text(
                            strings.moveMapToSetPoint,
                            textAlign: TextAlign.center,
                            style: AppTokens.font(
                              fontSize: 13,
                              color: go.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _confirmMapPoint,
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: Text(
                              strings.continueAction,
                              style: AppTokens.font(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTokens.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: AppTokens.spaceMd,
                        bottom: AppTokens.spaceMd,
                      ),
                      child: FloatingActionButton.small(
                        heroTag: 'my_location',
                        tooltip: strings.myLocationTooltip,
                        backgroundColor: go.panel,
                        foregroundColor: go.action,
                        onPressed: _goToMyLocation,
                        child: const Icon(Icons.my_location),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: TravelModeBottomBar(
        currentIndex: 0,
        onTabSelected: (index) {
          if (index == 1) {
            Navigator.pushNamed(context, '/orders');
          }
        },
      ),
    );
  }

  Widget _pointField({
    required IconData icon,
    required Color color,
    required String hint,
    required String value,
    required String fallback,
    required String tooltip,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required GoTheme go,
  }) {
    final display = value.isEmpty ? hint : value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceMd,
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  display,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.font(
                    color: value.isEmpty ? go.muted : go.text,
                    fontWeight:
                        value.isEmpty ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../../services/app_state.dart';

/// Bottom sheet shown once both ends of the trip are known: vehicle picker,
/// fare estimate, and the rider's own price offer.
///
/// GoDrive is a name-your-price marketplace — the suggested fare is only an
/// anchor. The stepper lets the rider nudge their offer above or below it,
/// with semantic labels so screen readers announce what the ± buttons do and
/// a running hint describing how the current offer relates to the suggested
/// price. All of that copy used to be hardcoded Arabic; it now routes through
/// [AppStrings] like every other surface.
class FareEstimateSheet extends StatefulWidget {
  const FareEstimateSheet({
    super.key,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.onConfirm,
  });

  final String pickupAddress;
  final String destinationAddress;

  /// Called with the rider's final offer when they request the ride.
  final ValueChanged<double> onConfirm;

  @override
  State<FareEstimateSheet> createState() => _FareEstimateSheetState();
}

class _FareEstimateSheetState extends State<FareEstimateSheet> {
  double? _suggestedFare;
  double? _offer;
  bool _loading = true;
  String? _error;
  int _vehicleIndex = 0;

  static const _step = 5.0;

  @override
  void initState() {
    super.initState();
    _fetchEstimate();
  }

  Future<void> _fetchEstimate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = context.read<AppState>();
      final res = await state.apiPost('/pricing/estimate', {
        'pickup': state.pickupPoint,
        'destination': state.destinationPoint,
        'vehicle_class': _vehicleIndex,
      });
      if (!mounted) return;
      final suggested = (res['suggested_fare'] as num?)?.toDouble();
      setState(() {
        _suggestedFare = suggested;
        _offer = suggested;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _nudge(double delta) {
    final current = _offer ?? 0;
    setState(() => _offer = (current + delta).clamp(0, 100000));
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final pickup = widget.pickupAddress.isEmpty
        ? strings.pickupPointFallback
        : widget.pickupAddress;
    final destination = widget.destinationAddress.isEmpty
        ? strings.destinationPointFallback
        : widget.destinationAddress;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppTokens.spaceLg),
        decoration: BoxDecoration(
          color: go.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: go.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text(
              strings.tripDetailsTitle,
              style: AppTokens.font(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: go.text,
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            _routeRow(Icons.radio_button_checked, AppTokens.primary, pickup, go),
            const SizedBox(height: AppTokens.spaceSm),
            _routeRow(Icons.location_on, AppTokens.danger, destination, go),
            const SizedBox(height: AppTokens.spaceMd),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  strings.paymentMethodLabel,
                  style: AppTokens.font(color: go.muted),
                ),
                Row(
                  children: [
                    Icon(Icons.payments_outlined, size: 18, color: go.action),
                    const SizedBox(width: AppTokens.space2xs),
                    Text(
                      strings.paymentCash,
                      style: AppTokens.font(
                        fontWeight: FontWeight.w600,
                        color: go.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: AppTokens.spaceLg * 1.5),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        strings.calculatingFare,
                        style: AppTokens.font(color: go.muted),
                      ),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                child: Column(
                  children: [
                    Text(
                      strings.fareLoadError,
                      style: AppTokens.font(color: AppTokens.danger),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                    OutlinedButton(
                      onPressed: _fetchEstimate,
                      child: Text(strings.tryAgainAction),
                    ),
                  ],
                ),
              )
            else
              _buildOffer(go, strings),
            const SizedBox(height: AppTokens.spaceLg),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_loading || _error != null || _offer == null)
                    ? null
                    : () => widget.onConfirm(_offer!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                child: Text(
                  strings.requestRideAction,
                  style: AppTokens.font(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeRow(IconData icon, Color color, String label, GoTheme go) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTokens.font(color: go.text),
          ),
        ),
      ],
    );
  }

  Widget _buildOffer(GoTheme go, AppStrings strings) {
    final suggested = _suggestedFare;
    final offer = _offer;
    if (suggested == null || offer == null) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Text(
          strings.offerHintNoSuggestion,
          textAlign: TextAlign.center,
          style: AppTokens.font(color: go.muted),
        ),
      );
    }

    final String hint;
    final Color hintColor;
    final diff = offer - suggested;
    if (diff.abs() < 0.01) {
      hint = strings.offerHintFairPrice(suggested.round());
      hintColor = AppTokens.success;
    } else if (diff > 0) {
      hint = strings.offerHintAbove(diff.round(), suggested.round());
      hintColor = AppTokens.success;
    } else {
      hint = strings.offerHintBelow(diff.abs().round(), suggested.round());
      hintColor = AppTokens.warning;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              strings.estimatedLabel,
              style: AppTokens.font(color: go.muted),
            ),
            Text(
              '${suggested.toStringAsFixed(0)} ${strings.egp}',
              style: AppTokens.money(color: go.muted, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        Container(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          decoration: BoxDecoration(
            color: go.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: go.border),
          ),
          child: Column(
            children: [
              Text(
                strings.yourOfferLabel,
                style: AppTokens.font(fontSize: 13, color: go.muted),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    label: strings.decreasePriceSemantic,
                    child: IconButton.filledTonal(
                      onPressed: () => _nudge(-_step),
                      icon: const Icon(Icons.remove),
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMd),
                  Text(
                    '${offer.toStringAsFixed(0)} ${strings.egp}',
                    style: AppTokens.money(
                      color: AppTokens.primary,
                      fontSize: 32,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMd),
                  Semantics(
                    label: strings.increasePriceSemantic,
                    child: IconButton.filledTonal(
                      onPressed: () => _nudge(_step),
                      icon: const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: AppTokens.font(fontSize: 12.5, color: hintColor),
              ),
              if (diff.abs() >= 0.01) ...[
                const SizedBox(height: AppTokens.spaceSm),
                TextButton.icon(
                  onPressed: () => setState(() => _offer = suggested),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(
                    strings.resetToSuggestedAction,
                    style: AppTokens.font(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

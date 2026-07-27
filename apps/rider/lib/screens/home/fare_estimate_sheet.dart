import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';

import '../../services/app_state.dart';
import '../../services/location_service.dart';
import '../trip/trip_screen.dart';
import 'vehicle_selector.dart';

/// Fare breakdown and booking confirmation.
///
/// Accepts the addresses and route already resolved by the home screen so we
/// don't repeat work the rider has waited for once: previously this sheet
/// re-fetched the estimate *and* fired two more reverse-geocode calls at
/// booking time, which added visible latency to the most important tap in the
/// app and burned through the endpoint's rate limit.
class FareEstimateSheet extends StatefulWidget {
  const FareEstimateSheet({
    super.key,
    required this.pickup,
    required this.dropoff,
    this.pickupAddress,
    this.dropoffAddress,
    this.initialRoute,
  });

  final LatLng pickup;
  final LatLng dropoff;

  /// Addresses already resolved upstream; used verbatim when present.
  final String? pickupAddress;
  final String? dropoffAddress;

  /// Route already fetched by the home screen. When supplied the sheet opens
  /// instantly with the fare visible instead of showing a spinner.
  final RoutePreview? initialRoute;

  @override
  State<FareEstimateSheet> createState() => _FareEstimateSheetState();
}

class _FareEstimateSheetState extends State<FareEstimateSheet> {
  bool _loading = true;
  Map<String, dynamic>? _estimate;
  RoutePreview? _route;
  String _selectedVehicle = 'economy';
  bool _booking = false;
  String? _error;

  /// Multipliers mirroring VehicleSelector's car classes, so the suggested
  /// price tracks the class the rider actually picked.
  static const Map<String, double> _classMultipliers = {
    'economy': 1.0,
    'comfort': 1.3,
    'xl': 1.6,
  };

  /// Step used by the −/+ buttons, in EGP.
  static const double _priceStep = 5;

  /// Server-side bound from `createTripSchema` (`offeredPrice` is
  /// `.min(1).max(10000)`). Clamping here means an out-of-range number is
  /// caught before the request instead of coming back as a validation error.
  static const double _minOffer = 1;
  static const double _maxOffer = 10000;

  /// The fare the rider is offering, in EGP.
  ///
  /// Seeded from the backend estimate and then owned by the rider. Null only
  /// until the first estimate lands.
  double? _offeredPrice;

  /// True once the rider has moved the price themselves. After that the
  /// suggestion stops overwriting their number — re-seeding on a late estimate
  /// or a class change would silently discard what they typed.
  bool _priceEditedByRider = false;

  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute;
    _fetchEstimate();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  /// The system's fair-price suggestion for the current car class.
  double? get _suggestedPrice {
    final fare = _estimate?['fare'];
    final base = fare is Map ? (fare['total'] as num?)?.toDouble() : null;
    if (base == null || base <= 0) return null;
    return base * (_classMultipliers[_selectedVehicle] ?? 1.0);
  }

  /// Seeds [_offeredPrice] from the suggestion, unless the rider has taken over.
  void _syncSuggestedPrice() {
    if (_priceEditedByRider) return;
    final suggested = _suggestedPrice;
    if (suggested == null) return;
    _setOfferedPrice(suggested, markEdited: false);
  }

  void _setOfferedPrice(double value, {bool markEdited = true}) {
    final rounded = value.roundToDouble().clamp(_minOffer, _maxOffer);
    _offeredPrice = rounded;
    if (markEdited) _priceEditedByRider = true;

    final text = rounded.toStringAsFixed(0);
    if (_priceController.text != text) {
      _priceController.text = text;
    }
  }

  void _nudgePrice(double delta) {
    final current = _offeredPrice ?? _suggestedPrice;
    if (current == null) return;
    setState(() => _setOfferedPrice(current + delta));
  }

  /// Handles free-text entry. The rider may clear the field mid-edit, so an
  /// unparseable value is left alone rather than snapped back to a default.
  void _onPriceTyped(String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) return;
    setState(() {
      _offeredPrice = parsed.clamp(_minOffer, _maxOffer);
      _priceEditedByRider = true;
    });
  }

  Future<void> _fetchEstimate() async {
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
        _route = RoutePreview.fromEstimate(
          res,
          origin: widget.pickup,
          destination: widget.dropoff,
        );
        _loading = false;
        // Seed the rider's offer with the system suggestion now that we have a
        // fare to base it on.
        _syncSuggestedPrice();
      });
    } catch (e) {
      if (!mounted) return;
      // Keep the sheet open and explain what happened rather than popping it
      // out from under the rider with a transient snackbar.
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  Future<void> _bookTrip() async {
    setState(() => _booking = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final state = context.read<AppState>();
      final locations = LocationService(state);

      // Prefer the addresses the rider already saw on screen. Only geocode
      // when they are genuinely missing.
      var pickupAddr = widget.pickupAddress?.trim() ?? '';
      var dropoffAddr = widget.dropoffAddress?.trim() ?? '';

      if (pickupAddr.isEmpty) {
        pickupAddr = await locations.reverseGeocode(widget.pickup) ??
            LocationService.coordinateLabel(widget.pickup);
      }
      if (dropoffAddr.isEmpty) {
        dropoffAddr = await locations.reverseGeocode(widget.dropoff) ??
            LocationService.coordinateLabel(widget.dropoff);
      }

      final res = await state.createTrip(
        pickupLat: widget.pickup.latitude,
        pickupLng: widget.pickup.longitude,
        dropoffLat: widget.dropoff.latitude,
        dropoffLng: widget.dropoff.longitude,
        pickupAddress: pickupAddr,
        dropoffAddress: dropoffAddr,
        // The rider's car-class choice was collected by VehicleSelector and
        // then dropped, so every trip was created with a null
        // vehicle_type_id. Thread it through to the API instead.
        vehicleTypeId: _selectedVehicle,
        // The price the rider is offering. Without this the API falls back to
        // its own estimate and captains only ever see a fixed system price —
        // the rider's number never reached the negotiation.
        offeredPrice: _offeredPrice ?? _suggestedPrice,
      );

      if (!mounted) return;
      navigator.pop();
      navigator.push(
        MaterialPageRoute(
          builder: (_) => TripScreen(tripId: res['trip']['id']),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception:', '').trim())),
      );
      setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    return Container(
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: SafeArea(
        top: false,
        child: _loading
            ? _LoadingBody(go: go, isAr: isAr)
            : _error != null
                ? _ErrorBody(
                    go: go,
                    isAr: isAr,
                    message: _error!,
                    onRetry: () {
                      setState(() {
                        _loading = true;
                        _error = null;
                      });
                      _fetchEstimate();
                    },
                  )
                : _buildContent(go, isAr),
      ),
    );
  }

  Widget _buildContent(GoTheme go, bool isAr) {
    final route = _route;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: go.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 18),

        Text(
          isAr ? 'تفاصيل الرحلة' : 'Trip details',
          style: GoogleFonts.ibmPlexSansArabic(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: go.text,
          ),
        ),
        const SizedBox(height: 14),

        // Journey summary — the two endpoints plus real distance and time.
        _JourneyCard(
          go: go,
          isAr: isAr,
          pickup: widget.pickupAddress,
          dropoff: widget.dropoffAddress,
          route: route,
        ),
        const SizedBox(height: 16),

        VehicleSelector(
          fareEstimate: _estimate,
          onSelect: (val) => setState(() {
            _selectedVehicle = val;
            // A different class implies a different fair price. Only re-seeds
            // while the rider has not set their own number.
            _syncSuggestedPrice();
          }),
        ),
        const SizedBox(height: 18),

        // The rider's price proposal — the heart of the negotiation flow.
        _PriceOfferCard(
          go: go,
          isAr: isAr,
          offeredPrice: _offeredPrice,
          suggestedPrice: _suggestedPrice,
          controller: _priceController,
          onDecrease: () => _nudgePrice(-_priceStep),
          onIncrease: () => _nudgePrice(_priceStep),
          onTyped: _onPriceTyped,
          onResetToSuggested: () => setState(() {
            _priceEditedByRider = false;
            _syncSuggestedPrice();
          }),
        ),
        const SizedBox(height: 18),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isAr ? 'طريقة الدفع' : 'Payment method',
              style: GoogleFonts.ibmPlexSansArabic(
                color: go.muted,
                fontSize: 14,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.payments_rounded,
                  color: go.isDark ? go.action : AppTokens.success,
                  size: 19,
                ),
                const SizedBox(width: 7),
                Text(
                  isAr ? 'نقداً' : 'Cash',
                  style: GoogleFonts.ibmPlexSansArabic(
                    color: go.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),

        ElevatedButton(
          onPressed: _booking ? null : _bookTrip,
          style: ElevatedButton.styleFrom(
            backgroundColor: go.action,
            foregroundColor: go.onAction,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
          ),
          child: _booking
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: go.onAction,
                  ),
                )
              : Text(
                  isAr ? 'اطلب رحلة' : 'Request ride',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Origin → destination summary with the real driving distance and duration.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({
    required this.go,
    required this.isAr,
    required this.pickup,
    required this.dropoff,
    required this.route,
  });

  final GoTheme go;
  final bool isAr;
  final String? pickup;
  final String? dropoff;
  final RoutePreview? route;

  @override
  Widget build(BuildContext context) {
    final hasAddresses =
        (pickup?.isNotEmpty ?? false) || (dropoff?.isNotEmpty ?? false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      child: Column(
        children: [
          if (hasAddresses) ...[
            _endpointRow(
              color: go.pinPickup,
              text: pickup?.isNotEmpty == true
                  ? pickup!
                  : (isAr ? 'نقطة الانطلاق' : 'Pickup'),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 5, top: 4, bottom: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(width: 1.6, height: 16, color: go.border),
              ),
            ),
            _endpointRow(
              color: go.pinDropoff,
              text: dropoff?.isNotEmpty == true
                  ? dropoff!
                  : (isAr ? 'الوجهة' : 'Destination'),
            ),
          ],
          if (route != null) ...[
            if (hasAddresses) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: go.border),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Icon(Icons.route_rounded, size: 17, color: go.muted),
                const SizedBox(width: 7),
                Text(
                  route!.distanceLabel(isArabic: isAr),
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
                const SizedBox(width: 16),
                Icon(Icons.schedule_rounded, size: 17, color: go.muted),
                const SizedBox(width: 7),
                Text(
                  route!.durationLabel(isArabic: isAr),
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
                const Spacer(),
                if (route!.isApproximate)
                  Text(
                    isAr ? 'تقديري' : 'estimated',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 11.5,
                      color: go.muted,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _endpointRow({required Color color, required String text}) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: go.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({required this.go, required this.isAr});

  final GoTheme go;
  final bool isAr;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: go.action),
          const SizedBox(height: 16),
          Text(
            isAr ? 'جارٍ حساب الأجرة...' : 'Calculating fare...',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 14,
              color: go.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.go,
    required this.isAr,
    required this.message,
    required this.onRetry,
  });

  final GoTheme go;
  final bool isAr;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 40, color: go.muted),
          const SizedBox(height: 14),
          Text(
            isAr ? 'تعذّر حساب الأجرة' : 'Could not calculate the fare',
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: go.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 13,
              color: go.muted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: go.action,
              foregroundColor: go.onAction,
              minimumSize: const Size(180, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
            ),
            child: Text(
              isAr ? 'إعادة المحاولة' : 'Try again',
              style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rider's price proposal control.
///
/// This is the inDrive-style negotiation entry point: the backend suggests a
/// fair fare, the rider accepts it or names their own number, and captains then
/// accept that price or counter it. The rider is deliberately *not* clamped to a
/// band around the suggestion — they may offer whatever they like within the
/// API's absolute bounds — because the whole point is that the market, not the
/// pricing table, settles the final figure.
class _PriceOfferCard extends StatelessWidget {
  const _PriceOfferCard({
    required this.go,
    required this.isAr,
    required this.offeredPrice,
    required this.suggestedPrice,
    required this.controller,
    required this.onDecrease,
    required this.onIncrease,
    required this.onTyped,
    required this.onResetToSuggested,
  });

  final GoTheme go;
  final bool isAr;
  final double? offeredPrice;
  final double? suggestedPrice;
  final TextEditingController controller;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final ValueChanged<String> onTyped;
  final VoidCallback onResetToSuggested;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;

    // Only meaningful once we have a suggestion to compare against.
    final suggestion = suggestedPrice;
    final offer = offeredPrice;
    final diff = (suggestion != null && offer != null)
        ? offer - suggestion
        : null;
    final hasDiff = diff != null && diff.abs() >= 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: accent.withOpacity(go.isDark ? 0.30 : 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.local_offer_rounded, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  isAr ? 'السعر الذي تقترحه' : 'Your offer',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
              ),
              if (hasDiff)
                GestureDetector(
                  onTap: onResetToSuggested,
                  child: Text(
                    isAr ? 'السعر المقترح' : 'Reset',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ── stepper: −  [ 45 ج.م ]  + ──
          Row(
            children: [
              _StepButton(
                go: go,
                icon: Icons.remove_rounded,
                onTap: onDecrease,
                semanticLabel: isAr ? 'تقليل السعر' : 'Decrease price',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: TextField(
                    controller: controller,
                    onChanged: onTyped,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: go.text,
                      height: 1.1,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: go.isDark ? go.panel : Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      suffixText: isAr ? 'ج.م' : 'EGP',
                      suffixStyle: GoogleFonts.ibmPlexSansArabic(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: go.muted,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                        borderSide: BorderSide(color: go.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                        borderSide: BorderSide(color: go.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                        borderSide: BorderSide(color: accent, width: 1.8),
                      ),
                    ),
                  ),
                ),
              ),
              _StepButton(
                go: go,
                icon: Icons.add_rounded,
                onTap: onIncrease,
                semanticLabel: isAr ? 'زيادة السعر' : 'Increase price',
              ),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            _hintText(suggestion, diff),
            textAlign: TextAlign.center,
            style: GoogleFonts.ibmPlexSansArabic(
              fontSize: 12,
              color: go.muted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  /// Explains the number in context: the fair suggestion, how far the rider has
  /// moved from it, and what that means for how fast a captain accepts.
  String _hintText(double? suggestion, double? diff) {
    if (suggestion == null) {
      return isAr
          ? 'اقترح السعر الذي يناسبك، والكابتن يوافق أو يقترح سعراً آخر.'
          : 'Name your price — captains can accept it or counter.';
    }

    final s = suggestion.round();
    if (diff == null || diff.abs() < 1) {
      return isAr
          ? 'السعر العادل المقترح $s ج.م. يمكنك تعديله، والكابتن يوافق أو يقترح سعراً آخر.'
          : 'Suggested fair price is $s EGP. Adjust it freely — captains can accept or counter.';
    }

    if (diff > 0) {
      return isAr
          ? 'أعلى بـ ${diff.abs().round()} ج.م من السعر المقترح ($s ج.م) — فرصة أسرع للقبول.'
          : '${diff.abs().round()} EGP above the suggested $s EGP — likely accepted faster.';
    }
    return isAr
        ? 'أقل بـ ${diff.abs().round()} ج.م من السعر المقترح ($s ج.م) — قد يستغرق وقتاً أطول.'
        : '${diff.abs().round()} EGP below the suggested $s EGP — may take longer to match.';
  }
}

/// Square −/+ button used by the price stepper.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.go,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final GoTheme go;
  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final accent = go.isDark ? go.action : AppTokens.primary;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: go.isDark ? go.panel : Colors.white,
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusSm),
              border: Border.all(color: go.border),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
        ),
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    _route = widget.initialRoute;
    _fetchEstimate();
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
          onSelect: (val) => setState(() => _selectedVehicle = val),
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

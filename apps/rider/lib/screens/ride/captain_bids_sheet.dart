import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_shared/flutter_shared.dart';

/// Live list of captain offers for a trip.
///
/// Modelled on the reference app's offer cards: the price is the hero, the
/// captain's identity sits beneath it, and accept/decline are presented as an
/// equal pair so declining is a first-class action rather than a hidden one.
///
/// Offers now poll automatically every few seconds — previously the rider had
/// to press a refresh icon to discover that a captain had responded, which is
/// not something anyone thinks to do while waiting for a car.
class CaptainBidsSheet extends StatefulWidget {
  const CaptainBidsSheet({
    super.key,
    required this.tripId,
    required this.token,
    required this.baseUrl,
    required this.onBidAccepted,
    this.onCancelTrip,
  });

  final String tripId;
  final String token;
  final String baseUrl;
  final Function(Map<String, dynamic> trip) onBidAccepted;

  /// Optional hook for cancelling the whole request from this sheet.
  final VoidCallback? onCancelTrip;

  @override
  State<CaptainBidsSheet> createState() => _CaptainBidsSheetState();
}

class _CaptainBidsSheetState extends State<CaptainBidsSheet> {
  List<Map<String, dynamic>> _bids = [];
  bool _loading = true;
  String? _error;

  /// Offers the rider dismissed locally. The backend keeps them pending (a
  /// decline is not a protocol action), so we hide them client-side to keep
  /// the list focused on live choices.
  final Set<String> _declined = {};

  /// Accept is in flight for this bid — used to disable both buttons so a
  /// double-tap can't fire two accepts.
  String? _accepting;

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _fetchBids();
    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchBids(silent: true),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      };

  Future<void> _fetchBids({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);

    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/trips/${widget.tripId}/bids'),
        headers: _headers,
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _bids = List<Map<String, dynamic>>.from(data['bids'] ?? []);
          _loading = false;
          _error = null;
        });
      } else if (!silent) {
        setState(() {
          _loading = false;
          _error =
              AppStrings.of(context).bidsLoadErrorWithCode('${res.statusCode}');
        });
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = AppStrings.of(context).checkConnectionError;
        _loading = false;
      });
    }
  }

  Future<void> _acceptBid(String bidId) async {
    setState(() => _accepting = bidId);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final strings = AppStrings.of(context);

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/trips/${widget.tripId}/accept-bid'),
        headers: _headers,
        body: jsonEncode({'bidId': bidId}),
      );
      if (!mounted) return;

      if (res.statusCode < 400) {
        final data = jsonDecode(res.body);
        _poller?.cancel();
        widget.onBidAccepted(data['trip']);
        navigator.pop();
        return;
      }

      // A 409 means another rider action or captain change beat us to it —
      // refresh so the rider sees the real current state.
      String message = strings.bidAcceptFailedError;
      try {
        final body = jsonDecode(res.body);
        if (body is Map && body['error'] is String) {
          message = body['error'] as String;
        }
      } catch (_) {}

      setState(() => _accepting = null);
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTokens.danger),
      );
      _fetchBids(silent: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _accepting = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.connectionRetryError),
          backgroundColor: AppTokens.danger,
        ),
      );
    }
  }

  void _decline(String bidId) => setState(() => _declined.add(bidId));

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final visible =
        _bids.where((b) => !_declined.contains(b['id'] as String?)).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72,
        ),
        decoration: BoxDecoration(
          color: go.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
        child: SafeArea(
          top: false,
          child: Column(
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
              const SizedBox(height: 14),

              _Header(
                go: go,
                count: visible.length,
                onCancel: widget.onCancelTrip,
              ),
              const SizedBox(height: 14),

              Flexible(child: _buildBody(go, strings, visible)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
      GoTheme go, AppStrings strings, List<Map<String, dynamic>> visible) {
    if (_loading && _bids.isEmpty) {
      return _SearchingState(go: go);
    }

    if (_error != null && _bids.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 36, color: go.muted),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: AppTokens.font(
                fontSize: 14,
                color: go.muted,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _fetchBids,
              child: Text(
                strings.retryAction,
                style: AppTokens.font(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (visible.isEmpty) return _SearchingState(go: go);

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 6),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final bid = visible[idx];
        final bidId = bid['id'] as String;
        return _BidCard(
          go: go,
          bid: bid,
          busy: _accepting != null,
          accepting: _accepting == bidId,
          onAccept: () => _acceptBid(bidId),
          onDecline: () => _decline(bidId),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.go, required this.count, this.onCancel});

  final GoTheme go;
  final int count;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.bidsChooseCaptainTitle,
                style: AppTokens.font(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: go.text,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.verified_user_rounded,
                    size: 15,
                    color: go.isDark ? go.action : AppTokens.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    strings.bidsAllCaptainsVerified,
                    style: AppTokens.font(
                      fontSize: 12.5,
                      color: go.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (onCancel != null)
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 17),
            style: TextButton.styleFrom(
              foregroundColor: AppTokens.danger,
              backgroundColor: AppTokens.danger.withOpacity(0.10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
            ),
            label: Text(
              strings.bidsCancelRequestAction,
              style: AppTokens.font(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// A single captain's offer.
class _BidCard extends StatelessWidget {
  const _BidCard({
    required this.go,
    required this.bid,
    required this.busy,
    required this.accepting,
    required this.onAccept,
    required this.onDecline,
  });

  final GoTheme go;
  final Map<String, dynamic> bid;
  final bool busy;
  final bool accepting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final price = (bid['counter_price'] as num?)?.toDouble() ?? 0;
    final name = (bid['captain_name'] as String?)?.trim().isNotEmpty == true
        ? bid['captain_name'] as String
        : strings.bidsCaptainFallback;
    final rating = (bid['rating_avg'] as num?)?.toDouble() ?? 5.0;
    final ratingCount = (bid['rating_count'] as num?)?.toInt() ?? 0;
    final make = (bid['vehicle_make'] as String?) ?? '';
    final model = (bid['vehicle_model'] as String?) ?? '';
    final vehicle = '$make $model'.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Price leads — it is what the rider is comparing between offers.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${price.round()} ${strings.egp}',
                style: AppTokens.font(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  color: go.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 12),
              if (bid['eta_min'] != null)
                Text(
                  strings.bidsEtaMinutes('${bid['eta_min']}'),
                  style: AppTokens.font(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: go.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: go.elevated,
                child: Icon(Icons.person_rounded, color: go.muted, size: 23),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTokens.font(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: go.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star_rounded,
                            size: 15, color: Color(0xFFF5B301)),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(2),
                          style: AppTokens.font(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: go.text,
                          ),
                        ),
                        if (ratingCount > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            strings.bidsTripCount(ratingCount),
                            style: AppTokens.font(
                              fontSize: 12,
                              color: go.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (vehicle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        vehicle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTokens.font(
                          fontSize: 12.5,
                          color: go.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Accept and decline get equal visual weight.
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: go.isDark ? go.action : AppTokens.primary,
                    foregroundColor: go.isDark ? go.onAction : Colors.white,
                    disabledBackgroundColor: go.elevated,
                    minimumSize: const Size.fromHeight(46),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                  ),
                  child: accepting
                      ? SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: go.isDark ? go.onAction : Colors.white,
                          ),
                        )
                      : Text(
                          strings.bidAcceptAction,
                          style: AppTokens.font(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: go.text,
                    minimumSize: const Size.fromHeight(46),
                    side: BorderSide(color: go.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                  ),
                  child: Text(
                    strings.bidDeclineAction,
                    style: AppTokens.font(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shown while waiting for the first offer to arrive.
class _SearchingState extends StatelessWidget {
  const _SearchingState({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: go.isDark ? go.action : AppTokens.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            strings.bidsSearchingTitle,
            style: AppTokens.font(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: go.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.bidsSearchingSubtitle,
            style: AppTokens.font(
              fontSize: 13,
              color: go.muted,
            ),
          ),
        ],
      ),
    );
  }
}

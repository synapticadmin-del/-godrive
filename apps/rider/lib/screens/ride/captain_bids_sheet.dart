import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_shared/flutter_shared.dart';

/// Live captain offers for a trip, rendered as a **top-anchored overlay** on
/// the trip map.
///
/// This used to be a modal bottom sheet. The offers are the only decision on
/// screen while a trip is `offered`, and burying them under the fold meant the
/// rider read the map first and the thing they had to act on second. The panel
/// now sits at the top, directly under the map controls, with the price as the
/// hero and accept/decline as an equal pair.
///
/// The class keeps its `...Sheet` name and filename so the single import site
/// and `docs/BIDDING_SYSTEM.md` stay valid; it is a panel, not a route, and no
/// longer pops anything on accept.
///
/// Offers poll every few seconds — previously the rider had to press a refresh
/// icon to discover that a captain had responded, which is not something anyone
/// thinks to do while waiting for a car.
class CaptainBidsSheet extends StatefulWidget {
  const CaptainBidsSheet({
    super.key,
    required this.tripId,
    required this.token,
    required this.baseUrl,
    required this.onBidAccepted,
    this.onCancelTrip,
    this.pickupLat,
    this.pickupLng,
  });

  final String tripId;
  final String token;
  final String baseUrl;
  final Function(Map<String, dynamic> trip) onBidAccepted;

  /// Optional hook for cancelling the whole request from this panel.
  final VoidCallback? onCancelTrip;

  /// Pickup coordinates, used to estimate each captain's arrival time from the
  /// `captain_lat`/`captain_lng` the bids endpoint returns. Optional: when
  /// absent the ETA line is simply omitted rather than guessed.
  final double? pickupLat;
  final double? pickupLng;

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
          _error = 'تعذّر تحميل العروض (${res.statusCode})';
        });
      }
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = 'تحقق من اتصالك بالإنترنت';
        _loading = false;
      });
    }
  }

  Future<void> _acceptBid(String bidId) async {
    setState(() => _accepting = bidId);
    final messenger = ScaffoldMessenger.of(context);

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
        // No pop: this is an inline panel, not a route. The trip screen swaps
        // it out when the status it just received leaves `offered`.
        widget.onBidAccepted(data['trip']);
        return;
      }

      // A 409 means another rider action or captain change beat us to it —
      // refresh so the rider sees the real current state.
      String message = 'فشل قبول العرض، حاول مرة أخرى';
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
        const SnackBar(
          content: Text('تعذّر الاتصال، حاول مرة أخرى'),
          backgroundColor: AppTokens.danger,
        ),
      );
    }
  }

  void _decline(String bidId) => setState(() => _declined.add(bidId));

  /// Minutes until this captain reaches the pickup.
  ///
  /// The real answer comes from the server: `GET /trips/:id/bids` routes each
  /// captain's live position to the pickup over the street network and returns
  /// `eta_min` with an `eta_source`. Across the Nile a straight line is not an
  /// approximation of the drive — the bridge is somewhere else entirely — so
  /// this is worth a round trip the endpoint is already making.
  ///
  /// The haversine below survives only as a fallback for an app pointed at an
  /// API that predates the change, and it is flagged approximate when used.
  _Eta? _eta(Map<String, dynamic> bid) {
    final routed = (bid['eta_min'] as num?)?.toInt();
    if (routed != null && routed > 0) {
      // Anything the server could not route is still an estimate, and says so.
      return _Eta(routed, approximate: bid['eta_source'] != 'osrm');
    }

    final pLat = widget.pickupLat;
    final pLng = widget.pickupLng;
    final cLat = (bid['captain_lat'] as num?)?.toDouble();
    final cLng = (bid['captain_lng'] as num?)?.toDouble();
    if (pLat == null || pLng == null || cLat == null || cLng == null) {
      return null;
    }

    const earthKm = 6371.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(cLat - pLat);
    final dLng = rad(cLng - pLng);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(pLat)) * math.cos(rad(cLat)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final km = earthKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    if (!km.isFinite) return null;
    // `num.clamp` is statically typed `num` even on an int receiver, so the
    // toInt() is load-bearing, not decorative.
    return _Eta(
      (km / 22.0 * 60).round().clamp(1, 90).toInt(),
      approximate: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final visible =
        _bids.where((b) => !_declined.contains(b['id'] as String?)).toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        // Fades the map out behind the heading so white-on-map stays legible
        // in both themes, then releases the map cleanly below the card.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              go.bg.withOpacity(0.94),
              go.bg.withOpacity(0.82),
              go.bg.withOpacity(0.0),
            ],
            stops: const [0.0, 0.60, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(go: go, onCancel: widget.onCancelTrip),
            const SizedBox(height: 14),
            Flexible(child: _buildBody(go, visible)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GoTheme go, List<Map<String, dynamic>> visible) {
    if (_error != null && _bids.isEmpty) {
      return _PanelCard(
        go: go,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 32, color: go.muted),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTokens.font(fontSize: 14, color: go.muted),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _fetchBids,
              child: Text(
                'إعادة المحاولة',
                style: AppTokens.font(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    if (visible.isEmpty) return _SearchingState(go: go);

    return ListView.separated(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final bid = visible[idx];
        final bidId = bid['id'] as String;
        return _BidCard(
          go: go,
          bid: bid,
          eta: _eta(bid),
          baseUrl: widget.baseUrl,
          token: widget.token,
          busy: _accepting != null,
          accepting: _accepting == bidId,
          onAccept: () => _acceptBid(bidId),
          onDecline: () => _decline(bidId),
        );
      },
    );
  }
}

/// Shared card shell — one place for the offer surface, radius and shadow.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.go, required this.child});

  final GoTheme go;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: go.isDark ? go.surface : go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        boxShadow: AppTokens.shadowOffer,
      ),
      child: child,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.go, this.onCancel});

  final GoTheme go;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختيار سائق',
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
                  Flexible(
                    child: Text(
                      'تم التحقق من جميع السائقين',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.font(fontSize: 12.5, color: go.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (onCancel != null) ...[
          const SizedBox(width: 8),
          // Solid fill rather than the old 10% tint: sitting over map tiles,
          // a translucent chip had no reliable contrast to read against.
          TextButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded, size: 17),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor:
                  Color.lerp(AppTokens.danger, Colors.black, 0.28),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
            ),
            label: Text(
              'إلغاء الطلب',
              style: AppTokens.font(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single captain's offer.
class _BidCard extends StatelessWidget {
  const _BidCard({
    required this.go,
    required this.bid,
    required this.eta,
    required this.baseUrl,
    required this.token,
    required this.busy,
    required this.accepting,
    required this.onAccept,
    required this.onDecline,
  });

  final GoTheme go;
  final Map<String, dynamic> bid;
  final _Eta? eta;

  /// Needed to resolve the captain's photo: the API returns it as a path, and
  /// the route that serves it requires the bearer token.
  final String baseUrl;
  final String token;

  final bool busy;
  final bool accepting;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// Arabic plural for the trip counter: 3–10 takes the broken plural
  /// (رحلات), everything else the singular (رحلة). "404 رحلة" is correct;
  /// "404 رحلات" is not.
  static String _tripsLabel(int n) => (n >= 3 && n <= 10) ? 'رحلات' : 'رحلة';

  /// Same rule for minutes — "5 دقيقة" was wrong the same way "404 رحلات" was.
  static String _minutesLabel(int n) => (n >= 3 && n <= 10) ? 'دقائق' : 'دقيقة';

  @override
  Widget build(BuildContext context) {
    final price = (bid['counter_price'] as num?)?.toDouble() ?? 0;
    final name = (bid['captain_name'] as String?)?.trim().isNotEmpty == true
        ? bid['captain_name'] as String
        : 'كابتن Tempo';
    final rating = (bid['rating_avg'] as num?)?.toDouble() ?? 5.0;
    final ratingCount = (bid['rating_count'] as num?)?.toInt() ?? 0;
    final make = (bid['vehicle_make'] as String?) ?? '';
    final model = (bid['vehicle_model'] as String?) ?? '';
    final vehicle = '$make $model'.trim();

    return _PanelCard(
      go: go,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Price leads — it is what the rider is comparing between offers.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${price.round()} ج.م',
                style: AppTokens.money(fontSize: 28, color: go.text),
              ),
              const SizedBox(width: 10),
              if (eta != null)
                // Flexible because the price is the fixed element here: a
                // four-digit fare next to "حوالي 12 دقيقة" would otherwise
                // overflow the row on a narrow phone.
                Flexible(
                  child: Text(
                    '${eta!.approximate ? 'حوالي ' : ''}'
                    '${eta!.minutes} ${_minutesLabel(eta!.minutes)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTokens.font(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: go.muted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _CaptainAvatar(
                go: go,
                name: name,
                baseUrl: baseUrl,
                token: token,
                avatarUrl: bid['captain_avatar_url'] as String?,
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
                            size: 15, color: AppTokens.star),
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
                            '$ratingCount ${_tripsLabel(ratingCount)}',
                            style: AppTokens.font(fontSize: 12, color: go.muted),
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
                        style: AppTokens.font(fontSize: 12.5, color: go.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Accept and decline get equal width; only the fill separates them.
          Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: busy && !accepting ? 0.45 : 1.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // Plain Alignment, not AlignmentDirectional: a
                      // directional gradient needs a TextDirection threaded
                      // through to createShader, and this reads the same in
                      // both directions anyway.
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [go.actionPressed, go.action],
                      ),
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: ElevatedButton(
                      onPressed: busy ? null : onAccept,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        foregroundColor: go.onAction,
                        disabledForegroundColor: go.onAction,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size.fromHeight(48),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                        ),
                      ),
                      child: accepting
                          ? SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: go.onAction,
                              ),
                            )
                          : Text(
                              'قبول',
                              style: AppTokens.font(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : onDecline,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: go.isDark ? go.elevated : go.surface,
                    disabledBackgroundColor: go.isDark ? go.elevated : go.surface,
                    foregroundColor: go.text,
                    shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(48),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: Text(
                    'رفض',
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

/// Captain portrait.
///
/// `GET /trips/:id/bids` returns `captain_avatar_url` as the same API-relative
/// `/user/avatar/<userId>/<file>` path the profile surfaces use, so it needs
/// the base URL prefixed and the bearer token attached — that route sits
/// behind `authMiddleware`, and is readable by any signed-in user precisely so
/// a rider can see who is coming to collect them.
///
/// Initials remain the fallback and stay on screen underneath while the photo
/// loads, so a slow image degrades to the previous behaviour instead of
/// punching a hole in the card. The panel re-polls every 5s; Flutter's image
/// cache keys on the URL, so the photo resolves from memory on every rebuild
/// after the first and does not flicker.
class _CaptainAvatar extends StatelessWidget {
  const _CaptainAvatar({
    required this.go,
    required this.name,
    required this.baseUrl,
    required this.token,
    this.avatarUrl,
  });

  final GoTheme go;
  final String name;
  final String baseUrl;
  final String token;
  final String? avatarUrl;

  static const double _size = 42;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    String head(String s) => s.substring(0, 1).toUpperCase();
    if (parts.length == 1) return head(parts.first);
    return '${head(parts.first)}${head(parts[1])}';
  }

  /// Mirrors `AppState.avatarImage`: an absolute URL passes through, anything
  /// else is an API path that needs the base URL in front of it.
  String? get _photoUrl {
    final raw = avatarUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('http') ? raw : '$baseUrl$raw';
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _initialsCircle();
    final url = _photoUrl;
    if (url == null) return fallback;

    return ClipOval(
      child: Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        headers: token.isEmpty ? null : {'Authorization': 'Bearer $token'},
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : fallback,
        // A deleted photo, an expired token or no signal all land here, and
        // all of them mean the same thing to the rider: show the initials.
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _initialsCircle() {
    final initials = _initials;
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: go.isDark ? go.elevated : go.surface,
      ),
      child: initials.isEmpty
          ? Icon(Icons.person_rounded, color: go.muted, size: 23)
          : Text(
              initials,
              // Latin initials read as letters; Arabic ones need the RTL
              // shaping the surrounding Directionality already provides.
              style: AppTokens.font(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: go.text,
              ),
            ),
    );
  }
}

/// One offer's arrival estimate: the number, and whether it was routed.
///
/// The distinction is not cosmetic — a routed number is a promise about the
/// street network, a fallback is a guess about a straight line, and the card
/// says which one the rider is looking at.
class _Eta {
  const _Eta(this.minutes, {required this.approximate});

  final int minutes;
  final bool approximate;
}

/// Shown while waiting for the first offer to arrive.
class _SearchingState extends StatelessWidget {
  const _SearchingState({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      go: go,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: go.isDark ? go.action : AppTokens.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'جارٍ البحث عن كباتن قريبين',
            textAlign: TextAlign.center,
            style: AppTokens.font(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: go.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'هتوصلك عروض الأسعار هنا أول ما يردّوا',
            textAlign: TextAlign.center,
            style: AppTokens.font(fontSize: 13, color: go.muted),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

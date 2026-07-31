import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';

import '../../services/app_state.dart';

/// Live captain offers for a trip, rendered as an **inline list inside the
/// trip screen's bottom panel**.
///
/// History matters here, because this widget has been the wrong shape twice.
/// It started as a modal bottom sheet, then became a top-anchored overlay that
/// *replaced* the bottom panel outright. That second form is what produced the
/// long-standing "why are there two different waiting screens?" bug: a trip
/// sitting at `searching` drew the bottom panel, and the moment the API flipped
/// it to `offered` the entire surface was swapped for a different-looking card
/// at the opposite end of the screen — different title, different cancel
/// button, different position. Two states of one trip looked like two
/// unrelated products.
///
/// It is now a plain list with no chrome of its own. The trip screen owns the
/// heading, the cancel action and the panel it sits in; this widget owns
/// exactly one thing — the offers — and renders nothing at all when there are
/// none. That is what lets `searching` and `offered` be the same screen.
///
/// The class keeps its `captain_bids_sheet.dart` filename so the single import
/// site and `docs/BIDDING_SYSTEM.md` stay valid.
class CaptainOffersList extends StatefulWidget {
  const CaptainOffersList({
    super.key,
    required this.tripId,
    required this.onBidAccepted,
    this.onOffersChanged,
    this.pickupLat,
    this.pickupLng,
  });

  final String tripId;

  /// Called with the freshly assigned trip once the rider accepts an offer.
  final void Function(Map<String, dynamic> trip) onBidAccepted;

  /// Reports how many offers are currently on screen, so the parent can retitle
  /// its heading and status pill without duplicating the poll. Fired after the
  /// frame, never during build.
  final void Function(int count)? onOffersChanged;

  /// Pickup coordinates, used to estimate each captain's arrival time from the
  /// `captain_lat`/`captain_lng` the bids endpoint returns. Optional: when
  /// absent the ETA line is simply omitted rather than guessed.
  final double? pickupLat;
  final double? pickupLng;

  @override
  State<CaptainOffersList> createState() => _CaptainOffersListState();
}

class _CaptainOffersListState extends State<CaptainOffersList> {
  List<Map<String, dynamic>> _bids = [];
  String? _error;

  /// Offers the rider dismissed locally. The backend keeps them pending (a
  /// decline is not a protocol action), so we hide them client-side to keep
  /// the list focused on live choices.
  final Set<String> _declined = {};

  /// Accept is in flight for this bid — used to disable both buttons so a
  /// double-tap can't fire two accepts.
  String? _accepting;

  /// Last count handed to [CaptainOffersList.onOffersChanged]; guards against
  /// waking the parent every five seconds with a number it already has.
  int _lastReported = -1;

  /// Consecutive failed polls. One flaky tick should not replace a good list
  /// with an error card, but a poll that has been failing for half a minute is
  /// no longer "transient" and the rider deserves to know.
  int _consecutiveFailures = 0;

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

  /// Turns an exception into something a rider can act on.
  ///
  /// `AppState` throws the API's own `error` string when it has one, so most
  /// of these already read as Arabic sentences; the cases below are the ones
  /// that would otherwise surface as a raw Dart exception on screen.
  static String _friendlyError(Object e) {
    final raw = e.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) return 'تعذّر الاتصال، حاول مرة أخرى';
    if (raw.contains('Session expired')) {
      return 'انتهت الجلسة، سجّل الدخول مرة أخرى';
    }
    if (raw.contains('SocketException') ||
        raw.contains('Failed host lookup') ||
        raw.contains('TimeoutException') ||
        raw.contains('ClientException')) {
      return 'تحقق من اتصالك بالإنترنت';
    }
    return raw;
  }

  /// Fetches the current offers.
  ///
  /// Every call goes through [AppState.apiGet] rather than a bare `http.get`.
  /// That is the fix for the failure this panel was famous for: the old code
  /// held its own copy of the bearer token and called `http` directly, so it
  /// bypassed the 401 refresh interceptor entirely. Once the access token
  /// lapsed mid-wait, every poll 401'd, the `catch` swallowed it in silence,
  /// and the rider watched an empty "searching" spinner forever while real
  /// offers piled up server-side.
  Future<void> _fetchBids({bool silent = false}) async {
    try {
      final res = await context.read<AppState>().apiGet(
            '/trips/${widget.tripId}/bids',
          );
      if (!mounted) return;

      final raw = res['bids'];
      final parsed = <Map<String, dynamic>>[
        if (raw is List)
          for (final entry in raw)
            if (entry is Map) Map<String, dynamic>.from(entry),
      ];

      setState(() {
        _bids = parsed;
        _error = null;
        _consecutiveFailures = 0;
      });
      _reportCount();
    } catch (e) {
      if (!mounted) return;
      _consecutiveFailures++;
      // Hold the last good list through a blip; speak up once it is clearly
      // not a blip, or immediately when the rider asked for this fetch.
      final shouldSurface =
          !silent || (_bids.isEmpty && _consecutiveFailures >= 3);
      if (!shouldSurface) return;
      setState(() => _error = _friendlyError(e));
    }
  }

  /// Tells the parent how many offers are visible, after the current frame.
  ///
  /// Post-frame because this runs inside `setState`/`build` paths and the
  /// parent's callback calls `setState` of its own — doing it synchronously
  /// would throw "setState() called during build".
  void _reportCount() {
    final cb = widget.onOffersChanged;
    if (cb == null) return;
    final n = _visible.length;
    if (n == _lastReported) return;
    _lastReported = n;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb(n);
    });
  }

  List<Map<String, dynamic>> get _visible =>
      _bids.where((b) => !_declined.contains(b['id'] as String?)).toList();

  Future<void> _acceptBid(String bidId) async {
    setState(() => _accepting = bidId);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final data = await context.read<AppState>().apiPost(
        '/trips/${widget.tripId}/accept-bid',
        {'bidId': bidId},
      );
      if (!mounted) return;

      _poller?.cancel();
      final trip = data['trip'];
      if (trip is Map) {
        // No pop: this is an inline list, not a route. The trip screen swaps
        // the whole panel over once the status it just received leaves
        // `searching`/`offered`.
        widget.onBidAccepted(Map<String, dynamic>.from(trip));
        return;
      }

      // A 2xx with no trip payload should not strand the rider on a dead
      // panel — restart the poll and let the next tick reconcile.
      setState(() => _accepting = null);
      _poller = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _fetchBids(silent: true),
      );
      _fetchBids(silent: true);
    } catch (e) {
      if (!mounted) return;
      // A 409 means a captain withdrew or another action beat us to it —
      // refresh so the rider sees the real current state.
      setState(() => _accepting = null);
      messenger.showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: AppTokens.danger,
        ),
      );
      _fetchBids(silent: true);
    }
  }

  void _decline(String bidId) {
    setState(() => _declined.add(bidId));
    _reportCount();
  }

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
    final state = context.read<AppState>();
    final visible = _visible;

    // Nothing to show and nothing wrong: render nothing. The trip screen's
    // "جارٍ البحث عن كابتن…" heading is already saying the right thing, and a
    // second spinner underneath it was half of what made this look like a
    // separate screen.
    if (visible.isEmpty) {
      if (_error == null) return const SizedBox.shrink();
      return Directionality(
        textDirection: TextDirection.rtl,
        child: _errorCard(go),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView.separated(
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
            baseUrl: state.baseUrl,
            token: state.token ?? '',
            busy: _accepting != null,
            accepting: _accepting == bidId,
            onAccept: () => _acceptBid(bidId),
            onDecline: () => _decline(bidId),
          );
        },
      ),
    );
  }

  Widget _errorCard(GoTheme go) => _PanelCard(
        go: go,
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 22, color: go.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _error!,
                style: AppTokens.font(fontSize: 13, color: go.muted),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _fetchBids();
              },
              child: Text(
                'إعادة المحاولة',
                style: AppTokens.font(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

/// Shared card shell — one place for the offer surface, radius and border.
///
/// Tuned for sitting *inside* the trip panel rather than floating over map
/// tiles: a tinted fill against `go.panel` instead of the old drop shadow,
/// which read as a second floating layer once the list moved into the sheet.
class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.go, required this.child});

  final GoTheme go;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: go.isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: go.border),
      ),
      child: child,
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
        : 'كابتن GoDrive';
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
                style: AppTokens.money(fontSize: 26, color: go.text),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: go.muted,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

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
          const SizedBox(height: 12),

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
                        minimumSize: const Size.fromHeight(46),
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
                    minimumSize: const Size.fromHeight(46),
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
/// punching a hole in the card. The list re-polls every 5s; Flutter's image
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

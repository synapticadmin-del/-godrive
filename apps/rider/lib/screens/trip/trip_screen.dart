import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
// Imported by path rather than through the package barrel, exactly as the
// captain app's own vehicle layer does (main_shell.dart:15-16). Adding these
// two exports to packages/flutter_shared/lib/flutter_shared.dart would mean
// editing a file this task does not own. Both resolve normally — every file
// under a package's lib/ is importable as package:<name>/<path>.dart.
import 'package:flutter_shared/motion/go_motion.dart';
import 'package:flutter_shared/widgets/animated_vehicle_marker.dart';
import '../../services/app_state.dart';
import '../../services/trip_ws.dart';
import 'trip_chat_screen.dart';
import '../safety/sos_screen.dart';
import '../ride/rating_sheet.dart';
import '../ride/captain_bids_sheet.dart';

/// Rider trip screen — progressive states like Uber/Careem:
/// searching → offered → assigned → arrived → in_progress → completed
/// Each state shows a different bottom panel with contextual info + actions.
class TripScreen extends StatefulWidget {
  final String tripId;
  const TripScreen({super.key, required this.tripId});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  TripWebSocketService? _ws;
  Timer? _poll;
  Map<String, dynamic>? _trip;
  LatLng? _captainLoc;

  /// Which way the car is pointing, in degrees clockwise from north.
  ///
  /// `location.captain` carries `heading` (TripRoom.ts:222 and captain.ts:305
  /// both send `data.heading ?? null`), but the captain's device only supplies
  /// it once it has a compass or course fix — indoors, stationary, or on a
  /// phone with no magnetometer it arrives null for the life of the trip. So
  /// the reported value wins when it is usable and the bearing of the last leg
  /// stands in when it is not.
  ///
  /// Held separately from [_captainLoc] because it must **survive** a fix that
  /// does not move the car: a captain waiting at a light publishes the same
  /// point with no heading, and recomputing from a zero-length delta would
  /// spin a parked car on the spot.
  double? _captainHeading;

  bool _loading = true;
  final MapController _mapController = MapController();

  /// The driving route stored with the trip. `GET /trips/:id` returns the
  /// geometry the backend computed at booking time; previously the screen
  /// ignored it and showed only bare markers, so the rider could not see the
  /// path their driver was taking.
  List<LatLng> _routePoints = const [];

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    try {
      final res = await context.read<AppState>().getTrip(widget.tripId);
      if (!mounted) return;
      setState(() {
        _trip = res['trip'];
        _routePoints = _parseGeometry(res['geometry']);
        _loading = false;
      });
      _fitToRoute();
      _connectWs();
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// The captain-offers panel, or null when the trip is not taking offers.
  ///
  /// `offered` means at least one captain has named a price and is waiting on
  /// an answer, so the offers are the only thing on screen worth acting on.
  /// They render inline at the top of the map rather than in a modal sheet:
  /// declaring them here means a status change simply stops building them —
  /// there is no route to open, latch against double-opening, or pop from the
  /// wrong context, all of which the sheet version needed.
  Widget? _buildOffersPanel() {
    if (_status != 'offered') return null;

    final state = context.read<AppState>();
    final token = state.token;
    // Without a token the panel's requests would 401 in a loop; the auth
    // interceptor will already be logging the rider out in that case.
    if (token == null) return null;

    return CaptainBidsSheet(
      // Keyed so the poller and any locally-declined offers survive the
      // rebuild that every incoming `trip.updated` triggers.
      key: const ValueKey('captain-offers'),
      tripId: widget.tripId,
      token: token,
      baseUrl: state.baseUrl,
      pickupLat: (_trip?['pickup_lat'] as num?)?.toDouble(),
      pickupLng: (_trip?['pickup_lng'] as num?)?.toDouble(),
      onBidAccepted: (trip) {
        if (!mounted) return;
        setState(() => _trip = Map<String, dynamic>.from(trip));
      },
      onCancelTrip: _cancelTrip,
    );
  }

  /// Geometry arrives as `[[lat, lng], ...]`. Parsed defensively so a bad
  /// payload degrades to "no line drawn" rather than crashing a live trip.
  List<LatLng> _parseGeometry(dynamic raw) {
    if (raw is! List) return const [];
    final points = <LatLng>[];
    for (final entry in raw) {
      if (entry is! List || entry.length < 2) continue;
      final lat = (entry[0] as num?)?.toDouble();
      final lng = (entry[1] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  /// Frames the journey once, leaving room for the status bar and the bottom
  /// panel so the route is not hidden behind either.
  void _fitToRoute() {
    if (_routePoints.length < 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.coordinates(
          coordinates: _routePoints,
          padding: const EdgeInsets.only(left: 50, right: 50, top: 140, bottom: 300),
          maxZoom: 16,
        ),
      );
    });
  }

  void _connectWs() {
    final state = context.read<AppState>();
    _ws = TripWebSocketService(
      baseUrl: state.baseUrl,
      tripId: widget.tripId,
      token: state.token!,
      onMessage: (ev) {
        final type = ev['type'] as String?;
        if (type == 'trip.updated' && ev['trip'] is Map) {
          // The backend flips the trip to `offered` the moment a captain bids,
          // and the offers panel is built from that status — so this setState
          // is all it takes for the offers to appear while the rider watches.
          setState(() => _trip = Map<String, dynamic>.from(ev['trip'] as Map));
        } else if (type == 'location.captain') {
          final lat = (ev['lat'] as num?)?.toDouble();
          final lng = (ev['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _onCaptainFix(
              LatLng(lat, lng),
              (ev['heading'] as num?)?.toDouble(),
            );
          }
        }
      },
    )..connect();
  }

  /// Records a captain fix and resolves the bearing to draw it at.
  ///
  /// This is the whole of the state change that used to be a one-line
  /// `setState(() => _captainLoc = LatLng(lat, lng))`. The assignment itself is
  /// unchanged — the marker still renders the newest known position and nothing
  /// here predicts where the car will be next. What is new is that the heading
  /// is resolved alongside it, so the layer below can walk the car to the fix
  /// pointing the way it is travelling.
  ///
  /// Precedence: the reported heading, then the bearing of the leg just
  /// travelled, then whatever we were already showing. The last clause is the
  /// one that matters — it is what stops a stationary car spinning.
  void _onCaptainFix(LatLng fix, double? reported) {
    final derived = _bearingIfMoved(_captainLoc, fix);
    setState(() {
      _captainLoc = fix;
      _captainHeading = _usableHeading(reported) ?? derived ?? _captainHeading;
    });
  }

  /// True when the platform asks for reduced motion.
  ///
  /// `MediaQuery.maybeOf(context)?.disableAnimations` is the house idiom for
  /// this — `login_screen.dart:72`, `splash_screen.dart:80` and
  /// `wallet_screen.dart:342` all read it exactly this way. There is no helper
  /// in `flutter_shared` to call instead; see the PR body.
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void dispose() {
    _poll?.cancel();
    _ws?.dispose();
    super.dispose();
  }

  /// The socket is the fast path, not the only path.
  ///
  /// `TripRoom` has failed closed before: every rider socket died on connect
  /// because the room looked itself up by the wrong id, and this screen sat on
  /// `searching` for the life of the trip because nothing here ever asked the
  /// API a second time. A ten-second poll is the floor — worst case the rider
  /// learns about an assignment ten seconds late instead of never.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_status == 'completed' || _status == 'cancelled') {
        timer.cancel();
        return;
      }
      try {
        final res = await context.read<AppState>().getTrip(widget.tripId);
        if (!mounted || res['trip'] is! Map) return;
        setState(() => _trip = Map<String, dynamic>.from(res['trip'] as Map));
      } catch (_) {
        // Offline, or a transient 5xx. The next tick tries again; surfacing a
        // snackbar every ten seconds would be worse than staying quiet.
      }
    });
  }

  void _cancelTrip() async {
    try {
      await context.read<AppState>().cancelTrip(widget.tripId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _rateTrip() {
    if (_trip == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RatingSheet(
        tripId: widget.tripId,
        captainName: _trip!['captain_name'] ?? 'الكابتن',
        onDone: () => Navigator.pop(context),
      ),
    );
  }

  String get _status => _trip?['status'] as String? ?? 'searching';

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final offersPanel = _buildOffersPanel();

    return Scaffold(
      backgroundColor: go.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trip == null
              ? ErrorState(
                  message: 'تعذّر تحميل بيانات الرحلة',
                  icon: Icons.route_outlined,
                  onRetry: _loadTrip,
                )
              : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    // Safe fallback: Cairo center if pickup coords are null
                    initialCenter: LatLng(
                      (_trip?['pickup_lat'] as num?)?.toDouble() ?? 30.0444,
                      (_trip?['pickup_lng'] as num?)?.toDouble() ?? 31.2357,
                    ),
                    initialZoom: 14,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: MapTiles.urlForContext(context),
                      subdomains: MapTiles.subdomains,
                      retinaMode: RetinaMode.isHighDensity(context),
                      userAgentPackageName: 'tech.synapticstudio.godrive.rider',
                    ),
                    // Casing beneath the route keeps it legible over busy tiles.
                    if (_routePoints.length >= 2)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 9,
                            color: go.routeCasing,
                            strokeCap: StrokeCap.round,
                            strokeJoin: StrokeJoin.round,
                          ),
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 5.5,
                            color: go.routeLine,
                            strokeCap: StrokeCap.round,
                            strokeJoin: StrokeJoin.round,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: _buildMarkers(go)),
                    // The car sits in its own layer, drawn after the endpoint
                    // pins and therefore above them — the same stacking it had
                    // when it was the last entry in `_buildMarkers`. A
                    // flutter_map Marker takes a fixed point, so walking the
                    // car between fixes means rebuilding its layer on every
                    // frame of the tween; keeping it out of that list leaves
                    // the pickup and dropoff pins static and cheap.
                    if (_captainLoc != null) _buildCaptainLayer(go),
                  ],
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      _circleButton(Icons.arrow_back, () => Navigator.pop(context)),
                      const SizedBox(width: 8),
                      Expanded(child: _statusBadge()),
                      const SizedBox(width: 8),
                      _circleButton(Icons.sos, () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SosScreen(tripId: widget.tripId))),
                        color: AppTokens.sos),
                    ],
                  ),
                ),
                // While captains are bidding the offers own the screen: they
                // sit at the top, directly under the map controls, and the
                // bottom panel stands down rather than repeating the same
                // decision twice with the map squeezed between them.
                if (offersPanel != null)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 56,
                    left: 0,
                    right: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.62,
                      ),
                      child: offersPanel,
                    ),
                  )
                else
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: _buildBottomPanel(),
                  ),
              ],
            ),
    );
  }

  List<Marker> _buildMarkers(GoTheme go) {
    final markers = <Marker>[];
    if (_trip != null) {
      final pickupLat = (_trip!['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (_trip!['pickup_lng'] as num?)?.toDouble();
      final dropLat = (_trip!['dropoff_lat'] as num?)?.toDouble();
      final dropLng = (_trip!['dropoff_lng'] as num?)?.toDouble();

      // Origin: a ringed dot, matching the home screen's visual language.
      if (pickupLat != null && pickupLng != null) {
        markers.add(Marker(
          point: LatLng(pickupLat, pickupLng),
          width: 26,
          height: 26,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: go.panel,
              border: Border.all(color: go.pinPickup, width: 5),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6),
              ],
            ),
          ),
        ));
      }

      // Destination: flag on a stem.
      if (dropLat != null && dropLng != null) {
        markers.add(Marker(
          point: LatLng(dropLat, dropLng),
          width: 34,
          height: 46,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: go.isDark ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6),
                  ],
                ),
                child: Icon(Icons.flag_rounded,
                    size: 18, color: go.isDark ? Colors.black : Colors.white),
              ),
              Container(
                width: 2.5,
                height: 12,
                color: go.isDark ? Colors.white : Colors.black,
              ),
            ],
          ),
        ));
      }
    }

    // The captain's car is NOT added here — see [_buildCaptainLayer]. It is
    // still the shared top-down silhouette (the same one the home map and the
    // admin dashboard draw), it just needs a layer of its own to be animated.
    return markers;
  }

  /// The captain's car, walked between fixes rather than teleported.
  ///
  /// E11 paced the captain's publishing to stay inside the server's rate limit
  /// (GeoCell.ts enforces it now), which necessarily means fewer, further-apart
  /// fixes: strictly better data that, drawn by an unchanged marker, looks
  /// **worse** — the gap between fixes is longer, so the jump is bigger. E11
  /// shipped [AnimatedVehicleMarker] so that could not happen and had no way to
  /// call it from here; this is that call. T13 and T28 both recorded that the
  /// two halves have to ship together, and only one of them had until now.
  ///
  /// [AnimatedVehicleMarker] interpolates and never extrapolates: it walks from
  /// where the car currently is to the newest **known** fix and stops. If fixes
  /// stop arriving the car holds its last real position instead of driving on
  /// down an invented road. It also refuses to animate a fix that moved less
  /// than [GoMotion.jitterThresholdMetres] (parked-GPS wander) or one that
  /// arrived after a gap longer than [GoMotion.maxFixTween] (lost signal).
  ///
  /// `fixInterval` is deliberately not passed: this is a live socket, so the
  /// widget measuring the gap on its own clock is exactly right — the last fix
  /// really did arrive when it arrived.
  Widget _buildCaptainLayer(GoTheme go) {
    final point = _captainLoc!;
    final heading = _captainHeading;
    const size = 46.0;

    // Reduce motion: place the car, do not walk it. The tween is skipped
    // entirely rather than run at zero duration — no controller, no per-frame
    // rebuild — and the marker still tracks every fix and still points the
    // right way. Position updates are information, not decoration.
    if (_reduceMotion) {
      return MarkerLayer(
        markers: [
          Marker(
            point: point,
            width: size,
            height: size,
            child: VehicleMapMarker(
              heading: heading,
              color: go.action,
              size: size,
            ),
          ),
        ],
      );
    }

    return AnimatedVehicleMarker(
      position: GoLatLng(point.latitude, point.longitude),
      heading: heading,
      color: go.action,
      size: size,
      builder: (context, animated, animatedHeading) => MarkerLayer(
        markers: [
          Marker(
            point: LatLng(animated.lat, animated.lng),
            width: size,
            height: size,
            child: VehicleMapMarker(
              heading: animatedHeading,
              color: go.action,
              size: size,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {Color? color}) {
    final go = GoTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color ?? go.panel,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)],
        ),
        child: Icon(icon, color: color != null ? Colors.white : go.text, size: 22),
      ),
    );
  }

  Widget _statusBadge() {
    final config = _statusConfig(_status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: config['color'] as Color, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (config['icon'] != null) ...[
          Icon(config['icon'] as IconData, color: Colors.white, size: 16),
          const SizedBox(width: 6),
        ],
        Text(config['label'] as String,
          style: AppTokens.font(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }

  Widget _buildBottomPanel() {
    final go = GoTheme.of(context);
    final bg = go.panel;
    final text = go.text;
    final muted = go.muted;
    return Container(
      decoration: BoxDecoration(color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))]),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: go.border, borderRadius: BorderRadius.circular(999)))),
          ..._buildPanelContent(text, muted),
        ]),
      )),
    );
  }

  List<Widget> _buildPanelContent(Color text, Color muted) {
    switch (_status) {
      case 'searching': return _searchingContent(text, muted);
      case 'offered': return _offeredContent(text, muted);
      case 'assigned': case 'arrived': return _assignedContent(text, muted);
      case 'in_progress': return _inProgressContent(text, muted);
      case 'completed': return _completedContent(text, muted);
      case 'cancelled': return _cancelledContent(text, muted);
      default: return _searchingContent(text, muted);
    }
  }

  List<Widget> _searchingContent(Color text, Color muted) => [
    Center(child: SizedBox(width: 48, height: 48,
      child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(AppTokens.primary)))),
    const SizedBox(height: 16),
    Text('جارٍ البحث عن كابتن…', style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
    const SizedBox(height: 4),
    Text('سنبلغك فور قبول كابتن لرحلتك', style: AppTokens.font(fontSize: 13, color: muted)),
    const SizedBox(height: 20),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _cancelTrip,
      icon: const Icon(Icons.close, size: 18), label: const Text('إلغاء الرحلة'),
      style: OutlinedButton.styleFrom(foregroundColor: AppTokens.danger, side: const BorderSide(color: AppTokens.danger)))),
  ];

  /// Degraded `offered` panel, reached only when the offers panel could not be
  /// built because the session token is missing.
  ///
  /// Normally the offers render at the top of the map and this never runs —
  /// `_buildOffersPanel` returning non-null suppresses the bottom panel
  /// entirely. Without a token the auth interceptor is already signing the
  /// rider out, so all this owes them is an explanation and a way out rather
  /// than a dead screen. It deliberately offers no "view offers" button: there
  /// is no sheet to reopen any more, and fetching them would 401 in a loop.
  List<Widget> _offeredContent(Color text, Color muted) {
    final go = GoTheme.of(context);
    return [
      Row(children: [
        Icon(Icons.local_offer_rounded,
            color: go.action, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('وصلت عروض من الكباتن',
          style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: text))),
      ]),
      const SizedBox(height: 4),
      Text('تعذّر عرض العروض — جرّب تسجيل الدخول مرة أخرى',
        style: AppTokens.font(fontSize: 13, color: muted)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _cancelTrip,
        icon: const Icon(Icons.close, size: 18), label: const Text('إلغاء الرحلة'),
        style: OutlinedButton.styleFrom(foregroundColor: AppTokens.danger, side: const BorderSide(color: AppTokens.danger)))),
    ];
  }

  List<Widget> _assignedContent(Color text, Color muted) {
    final fare = (_trip?['estimated_fare'] as num?)?.toDouble() ?? 0;
    final isArrived = _status == 'arrived';
    return [
      if (_hasCaptain) _driverCard(text, muted),
      const SizedBox(height: 16),
      Row(children: [
        Icon(isArrived ? Icons.access_time : Icons.directions_car, color: AppTokens.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(isArrived ? 'وصل الكابتن — تفضّل بالنزول' : 'الكابتن في الطريق إليك',
          style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700, color: text))),
      ]),
      const SizedBox(height: 12),
      _fareRow(fare, muted),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => TripChatScreen(tripId: widget.tripId))),
          icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('مراسلة'),
          style: OutlinedButton.styleFrom(foregroundColor: AppTokens.primary))),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(onPressed: _cancelTrip,
          icon: const Icon(Icons.close, size: 18), label: const Text('إلغاء'),
          style: OutlinedButton.styleFrom(foregroundColor: AppTokens.danger))),
      ]),
    ];
  }

  List<Widget> _inProgressContent(Color text, Color muted) {
    final fare = (_trip?['estimated_fare'] as num?)?.toDouble() ?? 0;
    return [
      if (_hasCaptain) _driverCard(text, muted),
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.navigation, color: AppTokens.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('الرحلة جارية', style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700, color: text))),
      ]),
      const SizedBox(height: 12),
      _fareRow(fare, muted),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => TripChatScreen(tripId: widget.tripId))),
        icon: const Icon(Icons.chat_bubble_outline, size: 18), label: const Text('مراسلة الكابتن'),
        style: OutlinedButton.styleFrom(foregroundColor: AppTokens.primary))),
    ];
  }

  List<Widget> _completedContent(Color text, Color muted) {
    final fare = (_trip?['final_fare'] as num?)?.toDouble() ?? (_trip?['estimated_fare'] as num?)?.toDouble() ?? 0;
    return [
      const Icon(Icons.check_circle, color: AppTokens.success, size: 48),
      const SizedBox(height: 12),
      Text('وصلت بسلامة!', style: AppTokens.font(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
      const SizedBox(height: 4),
      Text('الأجرة النهائية', style: AppTokens.font(fontSize: 13, color: muted)),
      const SizedBox(height: 4),
      Text('${fare.toStringAsFixed(0)} ج.م', style: AppTokens.font(fontSize: 28, fontWeight: FontWeight.w800, color: AppTokens.primary)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _rateTrip,
        icon: const Icon(Icons.star, size: 20), label: const Text('قيّم رحلتك'),
        style: ElevatedButton.styleFrom(backgroundColor: AppTokens.primary, foregroundColor: Colors.white))),
    ];
  }

  List<Widget> _cancelledContent(Color text, Color muted) => [
    const Icon(Icons.cancel, color: AppTokens.danger, size: 48),
    const SizedBox(height: 12),
    Text('تم إلغاء الرحلة', style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
    const SizedBox(height: 20),
    SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context),
      style: ElevatedButton.styleFrom(backgroundColor: AppTokens.primary, foregroundColor: Colors.white),
      child: const Text('حسنًا'))),
  ];

  /// True once a captain is attached to the trip.
  ///
  /// Deliberately keyed on `captain_id` rather than `captain_name`: the name
  /// is a JOINed convenience that an older API build may not send, and gating
  /// on it meant a rider with an assigned captain saw no card at all.
  bool get _hasCaptain => _trip?['captain_id'] != null;

  /// Arabic takes the broken plural for 3–10 and the singular either side.
  static String _tripsLabel(int n) => (n >= 3 && n <= 10) ? 'رحلات' : 'رحلة';

  /// A swatch for the vehicle colour, so the rider matches the car by sight
  /// rather than by reading a word off a screen in the dark. Unrecognised
  /// names get no dot — guessing a colour is worse than omitting it.
  static const Map<String, Color> _vehicleSwatches = {
    'أبيض': Colors.white, 'ابيض': Colors.white, 'white': Colors.white,
    'أسود': Color(0xFF1A1A1A), 'اسود': Color(0xFF1A1A1A), 'black': Color(0xFF1A1A1A),
    'فضي': Color(0xFFC0C4C8), 'فضى': Color(0xFFC0C4C8), 'silver': Color(0xFFC0C4C8),
    'رمادي': Color(0xFF8A8F94), 'رمادى': Color(0xFF8A8F94), 'gray': Color(0xFF8A8F94), 'grey': Color(0xFF8A8F94),
    'أحمر': Color(0xFFD32F2F), 'احمر': Color(0xFFD32F2F), 'red': Color(0xFFD32F2F),
    'أزرق': Color(0xFF1976D2), 'ازرق': Color(0xFF1976D2), 'blue': Color(0xFF1976D2),
    'أخضر': Color(0xFF388E3C), 'اخضر': Color(0xFF388E3C), 'green': Color(0xFF388E3C),
    'أصفر': Color(0xFFFBC02D), 'اصفر': Color(0xFFFBC02D), 'yellow': Color(0xFFFBC02D),
    'بني': Color(0xFF6D4C41), 'بنى': Color(0xFF6D4C41), 'brown': Color(0xFF6D4C41),
    'ذهبي': Color(0xFFC9A227), 'ذهبى': Color(0xFFC9A227), 'gold': Color(0xFFC9A227),
    'بيج': Color(0xFFD8C9A3), 'بيچ': Color(0xFFD8C9A3), 'beige': Color(0xFFD8C9A3),
  };

  /// Who is coming, how they drive, and which car to look for.
  ///
  /// Every field degrades on its own: a captain with no photo, no recorded
  /// colour or no plate still produces a card that reads as complete rather
  /// than as a row of gaps.
  Widget _driverCard(Color text, Color muted) {
    final go = GoTheme.of(context);
    final state = context.read<AppState>();
    final t = _trip ?? const <String, dynamic>{};

    final name = (t['captain_name'] as String?)?.trim();
    final rating = (t['rating_avg'] as num?)?.toDouble();
    // Completed trips is what a rider reads "عدد الرحلات" to mean. Fall back
    // to the ratings count only when an older API build omits the new field.
    final trips = (t['captain_trips_count'] as num?)?.toInt() ??
        (t['rating_count'] as num?)?.toInt();
    final make = (t['vehicle_make'] as String?)?.trim() ?? '';
    final model = (t['vehicle_model'] as String?)?.trim() ?? '';
    final year = (t['vehicle_year'] as num?)?.toInt();
    final colour = (t['vehicle_color'] as String?)?.trim() ?? '';
    final plate = (t['vehicle_plate'] as String?)?.trim() ?? '';

    final car = <String>[
      make,
      model,
      if (year != null && year > 1950) '$year',
    ].where((p) => p.isNotEmpty).join(' ');
    final swatch = _vehicleSwatches[colour.toLowerCase()];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: go.isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: go.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _CaptainAvatar(
              name: name ?? 'كابتن',
              avatarUrl: t['captain_avatar_url'] as String?,
              baseUrl: state.baseUrl,
              token: state.token ?? '',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (name != null && name.isNotEmpty) ? name : 'كابتن',
                    style: AppTokens.font(
                        fontSize: 16, fontWeight: FontWeight.w800, color: text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (rating != null) ...[
                      const Icon(Icons.star_rounded,
                          color: AppTokens.accent, size: 15),
                      const SizedBox(width: 3),
                      Text(rating.toStringAsFixed(2),
                          style: AppTokens.font(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: text)),
                    ],
                    if (rating != null && trips != null)
                      Text('  •  ',
                          style: AppTokens.font(fontSize: 13, color: muted)),
                    if (trips != null)
                      Text('$trips ${_tripsLabel(trips)}',
                          style: AppTokens.font(fontSize: 13, color: muted)),
                  ]),
                ],
              ),
            ),
            if (plate.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: go.panel,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: go.border, width: 1.5),
                ),
                child: Text(plate,
                    style: AppTokens.font(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: text)),
              ),
          ]),
          if (car.isNotEmpty || colour.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.directions_car_filled_rounded,
                  size: 16, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [car, colour].where((p) => p.isNotEmpty).join('  •  '),
                  style: AppTokens.font(
                      fontSize: 13, fontWeight: FontWeight.w600, color: text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (swatch != null)
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(color: go.border),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _fareRow(double fare, Color muted) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text('الأجرة', style: AppTokens.font(fontSize: 14, color: muted)),
      Text('${fare.toStringAsFixed(0)} ج.م', style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w800, color: AppTokens.primary)),
    ]);

  Map<String, dynamic> _statusConfig(String status) {
    switch (status) {
      case 'searching': return {'label': 'جارٍ البحث', 'color': AppTokens.warning, 'icon': Icons.search};
      case 'offered': return {'label': 'عروض متاحة', 'color': AppTokens.success, 'icon': Icons.local_offer};
      case 'assigned': return {'label': 'كابتن في الطريق', 'color': AppTokens.primary, 'icon': Icons.directions_car};
      case 'arrived': return {'label': 'وصل الكابتن', 'color': AppTokens.primary, 'icon': Icons.location_on};
      case 'in_progress': return {'label': 'الرحلة جارية', 'color': AppTokens.primary, 'icon': Icons.navigation};
      case 'completed': return {'label': 'وصلت', 'color': AppTokens.success, 'icon': Icons.check_circle};
      case 'cancelled': return {'label': 'ملغية', 'color': AppTokens.danger, 'icon': Icons.cancel};
      default: return {'label': status, 'color': AppTokens.lightMuted, 'icon': null};
    }
  }
}


/// A reported heading, or null when the device did not actually have one.
///
/// `geolocator` reports `-1` (and on some Android builds `NaN`) when there is
/// no course or compass fix, and the captain app only forwards a value it has
/// already checked (`main_shell.dart:235`). The server passes whatever it is
/// given straight through — `heading: data.heading ?? null` — so the last
/// place that can tell a real bearing from a placeholder is here.
double? _usableHeading(double? reported) {
  if (reported == null) return null;
  if (reported.isNaN || reported.isInfinite || reported < 0) return null;
  return reported % 360;
}

/// The bearing of the leg [from] → [to], or null when the car has not moved.
///
/// Returning null on a short delta is the whole point: a car waiting at a
/// light still publishes fixes, and consumer GPS wanders a few metres while it
/// does. Recomputing a bearing from that wander makes a parked car rotate on
/// the spot, which reads as a driver doing something they are not.
///
/// The threshold is [GoMotion.jitterThresholdMetres] — the same constant
/// [AnimatedVehicleMarker] uses to decide a fix is not worth animating — so the
/// marker cannot spin during a fix the widget has already chosen to hold still.
/// Neither the distance nor the trigonometry is a second implementation:
/// [GoMotion.metresBetween] is E11's, and `Distance.bearing` is `latlong2`'s,
/// a package this screen already depends on.
double? _bearingIfMoved(LatLng? from, LatLng to) {
  if (from == null) return null;
  final metres = GoMotion.metresBetween(
    GoLatLng(from.latitude, from.longitude),
    GoLatLng(to.latitude, to.longitude),
  );
  if (metres < GoMotion.jitterThresholdMetres) return null;
  return const Distance().bearing(from, to) % 360;
}

/// The captain's photo, matching the treatment in `CaptainBidsSheet` so the
/// person the rider chose looks the same before and after acceptance.
///
/// `captain_avatar_url` is the API-relative path from `users.avatar_url`, and
/// `GET /user/avatar/*` is authenticated, so the bearer token rides along with
/// the image request. A captain with no photo, an expired token and no signal
/// all resolve to the same thing for the rider: initials.
class _CaptainAvatar extends StatelessWidget {
  const _CaptainAvatar({
    required this.name,
    required this.baseUrl,
    required this.token,
    this.avatarUrl,
  });

  final String name;
  final String baseUrl;
  final String token;
  final String? avatarUrl;

  static const double _size = 48;

  String get _initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'ك';
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
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _initialsCircle() => Container(
        width: _size,
        height: _size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTokens.primary.withOpacity(0.15),
          shape: BoxShape.circle,
        ),
        child: Text(
          _initials,
          style: const TextStyle(
            color: AppTokens.primary,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      );
}

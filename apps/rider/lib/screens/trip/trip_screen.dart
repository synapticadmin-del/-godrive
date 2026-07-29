import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
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
  Map<String, dynamic>? _trip;
  LatLng? _captainLoc;
  bool _loading = true;
  final MapController _mapController = MapController();

  /// The driving route stored with the trip. `GET /trips/:id` returns the
  /// geometry the backend computed at booking time; previously the screen
  /// ignored it and showed only bare markers, so the rider could not see the
  /// path their driver was taking.
  List<LatLng> _routePoints = const [];

  /// True while the captain-offers sheet is on screen.
  ///
  /// `trip.updated` can arrive several times in a row (every bid re-broadcasts
  /// the trip), so without this latch each frame would stack another sheet on
  /// top of the last one and the rider would have to dismiss a pile of them.
  bool _bidsSheetOpen = false;

  /// The offers sheet's own context, kept so it can be dismissed by route
  /// rather than by `Navigator.pop(context)` — popping the screen's context
  /// would tear down the trip screen itself if the sheet had already gone.
  BuildContext? _bidsSheetContext;

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
      // A trip can already have offers waiting by the time this screen opens —
      // the captain may have bid while the booking sheet was still closing.
      _syncBidsSheet();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Keeps the captain-offers sheet in step with the trip status.
  ///
  /// `offered` means at least one captain has named a price and is waiting on
  /// an answer. Until now the screen treated that exactly like `searching` and
  /// showed a spinner, so real offers sat unanswered on the server while the
  /// rider assumed nobody had responded. Opening the sheet here is what closes
  /// that gap.
  ///
  /// It also handles the reverse: once the trip leaves `offered` — the rider
  /// accepted, another captain was assigned, or the request was cancelled —
  /// the sheet is stale and gets dismissed so it cannot sit over a live trip.
  void _syncBidsSheet() {
    if (!mounted) return;

    if (_status != 'offered') {
      _dismissBidsSheet();
      return;
    }

    if (_bidsSheetOpen) return;

    final state = context.read<AppState>();
    final token = state.token;
    // Without a token the sheet's requests would 401 in a loop; the auth
    // interceptor will already be logging the rider out in that case.
    if (token == null) return;

    _bidsSheetOpen = true;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Dismissing would hide live offers behind an opaque map, so the rider
      // has to make a decision — accept one, or cancel the request outright.
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        _bidsSheetContext = sheetContext;
        return CaptainBidsSheet(
          tripId: widget.tripId,
          token: token,
          baseUrl: state.baseUrl,
          onBidAccepted: (trip) {
            if (!mounted) return;
            setState(() => _trip = Map<String, dynamic>.from(trip));
          },
          onCancelTrip: () {
            _dismissBidsSheet();
            _cancelTrip();
          },
        );
      },
    ).whenComplete(() {
      // Covers every exit path — accepted, cancelled, or dismissed by
      // `_dismissBidsSheet` — so the latch can never stick shut.
      _bidsSheetOpen = false;
      _bidsSheetContext = null;
    });
  }

  /// Closes the offers sheet if it is still mounted.
  ///
  /// Pops the sheet's own route rather than the screen's, so a status change
  /// arriving just after the rider dismissed the sheet cannot pop the trip
  /// screen out from under them.
  void _dismissBidsSheet() {
    final sheetContext = _bidsSheetContext;
    _bidsSheetOpen = false;
    _bidsSheetContext = null;
    if (sheetContext != null && sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
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
          setState(() => _trip = Map<String, dynamic>.from(ev['trip'] as Map));
          // The backend flips the trip to `offered` the moment a captain bids.
          // React to it here so the offers appear while the rider is watching,
          // instead of only on the next rebuild.
          _syncBidsSheet();
        } else if (type == 'location.captain') {
          final lat = (ev['lat'] as num?)?.toDouble();
          final lng = (ev['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            setState(() => _captainLoc = LatLng(lat, lng));
          }
        }
      },
    )..connect();
  }

  @override
  void dispose() {
    _ws?.dispose();
    _bidsSheetContext = null;
    super.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final go = GoTheme.of(context);

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
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: _buildBottomPanel(isDark),
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

    if (_captainLoc != null) {
      // The captain is now the shared top-down car (Uber-style) — the same
      // silhouette the rider sees on the home map and the admin sees on the
      // live dashboard, so all three surfaces agree on what a car looks like.
      markers.add(Marker(
        point: _captainLoc!,
        width: 46,
        height: 46,
        child: VehicleMapMarker(
          color: go.isDark ? go.action : AppTokens.primary,
          size: 46,
        ),
      ));
    }
    return markers;
  }

  Widget _circleButton(IconData icon, VoidCallback onTap, {Color? color}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color ?? (isDark ? AppTokens.darkPanel : AppTokens.lightPanel),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)],
        ),
        child: Icon(icon, color: color != null ? Colors.white : (isDark ? AppTokens.darkText : AppTokens.lightText), size: 22),
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
          style: GoogleFonts.ibmPlexSansArabic(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }

  Widget _buildBottomPanel(bool isDark) {
    final bg = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    return Container(
      decoration: BoxDecoration(color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, -4))]),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: isDark ? AppTokens.darkBorder : AppTokens.lightBorder, borderRadius: BorderRadius.circular(999)))),
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
    Text('جارٍ البحث عن كابتن…', style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
    const SizedBox(height: 4),
    Text('سنبلغك فور قبول كابتن لرحلتك', style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
    const SizedBox(height: 20),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _cancelTrip,
      icon: const Icon(Icons.close, size: 18), label: const Text('إلغاء الرحلة'),
      style: OutlinedButton.styleFrom(foregroundColor: AppTokens.danger, side: const BorderSide(color: AppTokens.danger)))),
  ];

  /// Panel shown behind the offers sheet while captains are bidding.
  ///
  /// The sheet itself carries the decision, but it can be popped — and on a
  /// cold restart the status may already be `offered` — so this panel keeps a
  /// way back to the offers rather than leaving the rider on a dead screen.
  List<Widget> _offeredContent(Color text, Color muted) {
    final go = GoTheme.of(context);
    return [
      Row(children: [
        Icon(Icons.local_offer_rounded,
            color: go.isDark ? go.action : AppTokens.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('وصلت عروض من الكباتن',
          style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.w700, color: text))),
      ]),
      const SizedBox(height: 4),
      Text('اختار العرض اللي يناسبك من القايمة',
        style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _syncBidsSheet,
        icon: const Icon(Icons.visibility_outlined, size: 18), label: const Text('عرض العروض'),
        style: ElevatedButton.styleFrom(
          backgroundColor: go.isDark ? go.action : AppTokens.primary,
          foregroundColor: go.isDark ? go.onAction : Colors.white))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _cancelTrip,
        icon: const Icon(Icons.close, size: 18), label: const Text('إلغاء الرحلة'),
        style: OutlinedButton.styleFrom(foregroundColor: AppTokens.danger, side: const BorderSide(color: AppTokens.danger)))),
    ];
  }

  List<Widget> _assignedContent(Color text, Color muted) {
    final fare = (_trip?['estimated_fare'] as num?)?.toDouble() ?? 0;
    final isArrived = _status == 'arrived';
    return [
      if (_trip?['captain_name'] != null) _driverCard(text, muted),
      const SizedBox(height: 16),
      Row(children: [
        Icon(isArrived ? Icons.access_time : Icons.directions_car, color: AppTokens.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(isArrived ? 'وصل الكابتن — تفضّل بالنزول' : 'الكابتن في الطريق إليك',
          style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700, color: text))),
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
      if (_trip?['captain_name'] != null) _driverCard(text, muted),
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.navigation, color: AppTokens.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('الرحلة جارية', style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700, color: text))),
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
      Text('وصلت بسلامة!', style: GoogleFonts.ibmPlexSansArabic(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
      const SizedBox(height: 4),
      Text('الأجرة النهائية', style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
      const SizedBox(height: 4),
      Text('${fare.toStringAsFixed(0)} ج.م', style: GoogleFonts.ibmPlexSansArabic(fontSize: 28, fontWeight: FontWeight.w800, color: AppTokens.primary)),
      const SizedBox(height: 20),
      SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _rateTrip,
        icon: const Icon(Icons.star, size: 20), label: const Text('قيّم رحلتك'),
        style: ElevatedButton.styleFrom(backgroundColor: AppTokens.primary, foregroundColor: Colors.white))),
    ];
  }

  List<Widget> _cancelledContent(Color text, Color muted) => [
    const Icon(Icons.cancel, color: AppTokens.danger, size: 48),
    const SizedBox(height: 12),
    Text('تم إلغاء الرحلة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
    const SizedBox(height: 20),
    SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context),
      style: ElevatedButton.styleFrom(backgroundColor: AppTokens.primary, foregroundColor: Colors.white),
      child: const Text('حسنًا'))),
  ];

  Widget _driverCard(Color text, Color muted) => Row(children: [
    CircleAvatar(radius: 24, backgroundColor: AppTokens.primary.withOpacity(0.15),
      child: Text((_trip?['captain_name'] as String?)?.substring(0, 1) ?? 'C',
        style: const TextStyle(color: AppTokens.primary, fontWeight: FontWeight.bold, fontSize: 18))),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_trip?['captain_name'] ?? 'كابتن', style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
      if (_trip?['vehicle_plate'] != null)
        Text(_trip!['vehicle_plate'], style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
    ])),
    if (_trip?['rating_avg'] != null)
      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppTokens.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.star, color: AppTokens.accent, size: 14),
          const SizedBox(width: 4),
          Text('${_trip!['rating_avg']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTokens.accent)),
        ])),
  ]);

  Widget _fareRow(double fare, Color muted) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text('الأجرة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, color: muted)),
      Text('${fare.toStringAsFixed(0)} ج.م', style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.w800, color: AppTokens.primary)),
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

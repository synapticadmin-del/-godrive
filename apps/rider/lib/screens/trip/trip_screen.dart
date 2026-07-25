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

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    try {
      final res = await context.read<AppState>().getTrip(widget.tripId);
      setState(() {
        _trip = res['trip'];
        _loading = false;
      });
      _connectWs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
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
    final tileUrl = isDark
        ? 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png'
        : 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png';

    return Scaffold(
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
                    TileLayer(urlTemplate: tileUrl, subdomains: const ['a', 'b', 'c']),
                    MarkerLayer(markers: _buildMarkers()),
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

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    if (_trip != null) {
      final pickupLat = (_trip!['pickup_lat'] as num?)?.toDouble();
      final pickupLng = (_trip!['pickup_lng'] as num?)?.toDouble();
      final dropLat = (_trip!['dropoff_lat'] as num?)?.toDouble();
      final dropLng = (_trip!['dropoff_lng'] as num?)?.toDouble();
      if (pickupLat != null && pickupLng != null) {
        markers.add(Marker(point: LatLng(pickupLat, pickupLng), width: 40, height: 40,
          child: const Icon(Icons.location_on, color: AppTokens.primary, size: 36)));
      }
      if (dropLat != null && dropLng != null) {
        markers.add(Marker(point: LatLng(dropLat, dropLng), width: 40, height: 40,
          child: const Icon(Icons.flag, color: AppTokens.accent, size: 36)));
      }
    }
    if (_captainLoc != null) {
      markers.add(Marker(point: _captainLoc!, width: 44, height: 44,
        child: Container(
          decoration: BoxDecoration(color: AppTokens.primary, shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: AppTokens.primary.withOpacity(0.4), blurRadius: 8)]),
          child: const Icon(Icons.directions_car, color: Colors.white, size: 20),
        )));
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
      case 'searching': case 'offered': return _searchingContent(text, muted);
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
      case 'searching': case 'offered': return {'label': 'جارٍ البحث', 'color': AppTokens.warning, 'icon': Icons.search};
      case 'assigned': return {'label': 'كابتن في الطريق', 'color': AppTokens.primary, 'icon': Icons.directions_car};
      case 'arrived': return {'label': 'وصل الكابتن', 'color': AppTokens.primary, 'icon': Icons.location_on};
      case 'in_progress': return {'label': 'الرحلة جارية', 'color': AppTokens.primary, 'icon': Icons.navigation};
      case 'completed': return {'label': 'وصلت', 'color': AppTokens.success, 'icon': Icons.check_circle};
      case 'cancelled': return {'label': 'ملغية', 'color': AppTokens.danger, 'icon': Icons.cancel};
      default: return {'label': status, 'color': AppTokens.lightMuted, 'icon': null};
    }
  }
}
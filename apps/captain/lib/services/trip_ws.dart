import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for the captain's live trip room (`/ws/trips/:id`).
///
/// Mirrors the rider app's TripWebSocketService: same endpoint, same auth,
/// same event shapes. The captain opens this the moment a trip is assigned so
/// rider-side events — cancellations, status flips, and in-trip chat
/// messages — arrive in real time instead of on the next offers poll, which
/// was the root of the "الرسايل مش بتظهر" complaint: the messages were saved,
/// but the captain's app never listened for them.
class CaptainTripWebSocketService {
  CaptainTripWebSocketService({
    required this.baseUrl,
    required this.tripId,
    required this.token,
  });

  final String baseUrl;
  final String tripId;
  final String token;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  int _reconnectAttempts = 0;

  /// Broadcast stream of every parsed event from the room.
  final StreamController<Map<String, dynamic>> _messagesCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messagesCtrl.stream;

  /// Currently-used trip id (lets CaptainState keep reconnects idempotent).
  String get currentTripId => tripId;

  void connect() {
    if (_disposed) return;
    final wsBase = baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsBase/ws/trips/$tripId');
    try {
      _channel = WebSocketChannel.connect(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
      _reconnectAttempts = 0;
      _startPing();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    if (_disposed || raw is! String) return;
    try {
      final ev = jsonDecode(raw) as Map<String, dynamic>;
      if (!_messagesCtrl.isClosed) _messagesCtrl.add(ev);
    } catch (_) {
      /* malformed frame — ignore */
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _pingTimer?.cancel();
    _sub?.cancel();
    _channel = null;
    if (_reconnectAttempts >= 8) return;
    final delay = Duration(seconds: 1 << _reconnectAttempts.clamp(0, 5));
    _reconnectAttempts++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }
}

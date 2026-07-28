import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for the captain's live trip room (`/ws/trips/:id`).
///
/// Mirrors the rider app's TripWebSocketService exactly: same endpoint, same
/// auth style, same reconnect behaviour. Two details matter here:
///
///  * **Auth rides in the query string, not headers.** `web_socket_channel`
///    on mobile cannot attach custom headers reliably (the `headers:` arg is
///    silently ignored on the dart:io backend), and the API accepts
///    `?token=` precisely because of this. An earlier cut of this file passed
///    an Authorization header and the socket died with a 401 on every
///    connect — which would have disabled the captain's live chat/cancel
///    feed entirely.
///  * The captain opens this the moment a trip is assigned so rider-side
///    events — cancellations, status flips, and in-trip chat messages —
///    arrive in real time instead of on the next offers poll, which was the
///    root of the "الرسايل مش بتظهر" complaint: the messages were saved,
///    but the captain's app never listened for them.
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
  final Random _random = Random();

  /// Broadcast stream of every parsed event from the room.
  final StreamController<Map<String, dynamic>> _messagesCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messagesCtrl.stream;

  /// Currently-used trip id (lets CaptainState keep reconnects idempotent).
  String get currentTripId => tripId;

  String get _wsUrl {
    final http = baseUrl.replaceAll(RegExp(r'/$'), '');
    final ws = http.startsWith('https')
        ? http.replaceFirst('https', 'wss')
        : http.replaceFirst('http', 'ws');
    return '$ws/ws/trips/$tripId?token=${Uri.encodeComponent(token)}';
  }

  void connect() {
    _disposed = false;
    _open();
  }

  void _open() {
    _disposeSocketOnly();
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _sub = _channel!.stream.listen(
        (event) {
          _reconnectAttempts = 0;
          if (event is String) {
            try {
              final ev = jsonDecode(event) as Map<String, dynamic>;
              if (!_messagesCtrl.isClosed) _messagesCtrl.add(ev);
            } catch (_) {
              /* malformed frame — ignore */
            }
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();

    // Exponential backoff with randomized jitter, matching the other socket
    // clients in the monorepo, so a server blip doesn't get hammered by every
    // app at once.
    final baseSeconds = (1 << _reconnectAttempts.clamp(0, 4)); // 1,2,4,8,16
    final jitterMs = _random.nextInt(1000);
    _reconnectAttempts++;
    _reconnectTimer =
        Timer(Duration(seconds: baseSeconds, milliseconds: jitterMs), _open);
  }

  void _disposeSocketOnly() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _disposeSocketOnly();
  }
}

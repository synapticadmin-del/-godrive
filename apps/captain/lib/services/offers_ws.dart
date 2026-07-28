import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WsMessageHandler = void Function(Map<String, dynamic> message);

/// Captain offers inbox WebSocket with auto-reconnect & randomized jitter backoff.
class OffersWebSocketService {
  OffersWebSocketService({
    required this.baseUrl,
    required this.token,
    this.onMessage,
    this.onStatus,
  });

  final String baseUrl;
  final String token;
  final WsMessageHandler? onMessage;
  final void Function(String status)? onStatus;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _closed = false;
  int _attempt = 0;
  final Random _random = Random();

  String get _wsUrl {
    final http = baseUrl.replaceAll(RegExp(r'/$'), '');
    final ws = http.startsWith('https')
        ? http.replaceFirst('https', 'wss')
        : http.replaceFirst('http', 'ws');
    // Query-token auth (`?token=`) is deprecated: it leaks the JWT into
    // access logs and proxy history. The token now travels as the first
    // message after the socket opens (see _open). The server stays backwards
    // compatible with `?token=` during rollout, so old builds keep working.
    return '$ws/ws/captain/offers';
  }

  void connect() {
    _closed = false;
    _open();
  }

  void _open() {
    disposeSocketOnly();
    onStatus?.call('connecting');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      // First-message auth: authenticate before anything else is sent or
      // received. This must be the very first frame on the socket.
      try {
        _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      } catch (_) {}
      _sub = _channel!.stream.listen(
        (event) {
          _attempt = 0;
          onStatus?.call('connected');
          if (event is String) {
            try {
              final data = jsonDecode(event) as Map<String, dynamic>;
              onMessage?.call(data);
            } catch (_) {}
          }
        },
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
        cancelOnError: true,
      );
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        try {
          _channel?.sink.add(jsonEncode({'type': 'ping'}));
        } catch (_) {}
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    onStatus?.call('reconnecting');
    _heartbeat?.cancel();
    _reconnect?.cancel();

    // Exponential backoff with randomized jitter to prevent Thundering Herd problem
    final baseSeconds = (1 << _attempt.clamp(0, 4)); // 1, 2, 4, 8, 16
    final jitterMs = _random.nextInt(1000); // 0-999ms jitter
    final delay = Duration(seconds: baseSeconds, milliseconds: jitterMs);

    _attempt++;
    _reconnect = Timer(delay, _open);
  }

  void disposeSocketOnly() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void dispose() {
    _closed = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    disposeSocketOnly();
    onStatus?.call('closed');
  }
}

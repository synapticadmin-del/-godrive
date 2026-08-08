import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:tempo_captain/services/captain_state.dart';

/// The captain's in-trip chat with the rider.
///
/// Until now only the rider app had this screen: messages the rider sent were
/// stored on the server and a push was fired, but the captain had no surface
/// that read them back — so rider texts effectively disappeared. This screen
/// is the captain-side counterpart of the rider's TripChatScreen and talks to
/// the same `/safety/chat/:tripId` endpoints.
///
/// Two delivery paths keep the thread current while it is open:
///  * The trip WebSocket (`CaptainState.activeTripWsMessages`) relays a chat
///    event the moment it is broadcast, so the new message appears instantly.
///  * A light 6s poll backstops the socket, because a chat that silently
///    freezes is worse than one that is a few seconds behind.
///
/// The socket also carries `chat.typing` events, which drive the
/// "جاري الكتابة…" bubble above the composer: typing signals are emitted
/// (throttled) while the captain types and cleared on send/dispose, and the
/// rider's signals render here with a self-expiring timer so a lost "stop"
/// signal can never wedge the bubble open.
class CaptainTripChatScreen extends StatefulWidget {
  const CaptainTripChatScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<CaptainTripChatScreen> createState() => _CaptainTripChatScreenState();
}

class _CaptainTripChatScreenState extends State<CaptainTripChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  /// Typing indicator state. [_riderTyping] is what the bubble renders;
  /// [_typingClearTimer] self-expires it when no further signal arrives (the
  /// server stores nothing, so a dropped "stop" must not wedge the UI).
  bool _riderTyping = false;
  Timer? _typingClearTimer;

  /// Outgoing typing signals are throttled so a fast typist does not turn
  /// into a request stream — at most one POST per window.
  DateTime? _lastTypingSentAt;
  static const _typingThrottle = Duration(seconds: 2);
  static const _typingExpiry = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _fetchMessages(initial: true);

    // Live path: the trip room relays chat events as they happen.
    final state = context.read<CaptainState>();
    _wsSub = state.activeTripWsMessages.listen((ev) {
      if (!mounted) return;
      final type = ev['type'] as String?;
      if (type == 'chat.message' || type == 'trip.chat') {
        // A real message supersedes the typing hint.
        if (ev['senderRole'] != 'captain') _setRiderTyping(false);
        _fetchMessages();
      } else if (type == 'chat.typing' && ev['senderRole'] != 'captain') {
        _setRiderTyping(ev['typing'] == true);
      }
    });

    // Backstop path: refresh quietly so a dropped socket never freezes chat.
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) _fetchMessages();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _wsSub?.cancel();
    _typingClearTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    // Tell the rider this composer is gone. The endpoint is ephemeral and
    // errors are meaningless here, so it is fire-and-forget.
    _sendTyping(false);
    super.dispose();
  }

  void _setRiderTyping(bool typing) {
    _typingClearTimer?.cancel();
    if (typing) {
      _typingClearTimer = Timer(_typingExpiry, () {
        if (mounted) setState(() => _riderTyping = false);
      });
    }
    if (_riderTyping != typing && mounted) {
      setState(() => _riderTyping = typing);
    } else if (!typing && mounted && _riderTyping) {
      setState(() => _riderTyping = false);
    }
  }

  /// POSTs the typing signal server-side. Swallows every error — a typing
  /// hint is never worth a snackbar.
  void _sendTyping(bool typing) {
    final state = context.read<CaptainState>();
    state
        .apiPost('/safety/chat/${widget.tripId}/typing', {'typing': typing})
        .catchError((_) => <String, dynamic>{});
  }

  void _onMessageChanged(String _) {
    final now = DateTime.now();
    if (_lastTypingSentAt == null ||
        now.difference(_lastTypingSentAt!) > _typingThrottle) {
      _lastTypingSentAt = now;
      _sendTyping(true);
    }
  }

  Future<void> _fetchMessages({bool initial = false}) async {
    final state = context.read<CaptainState>();
    try {
      final res = await state.apiGet('/safety/chat/${widget.tripId}');
      if (!mounted) return;
      final incoming = (res['messages'] as List?) ?? [];
      // Newest-first from the API; flip so the list reads top → bottom and
      // only scroll to the end when a genuinely new message arrived.
      final changed = incoming.length != _messages.length ||
          (incoming.isNotEmpty &&
              (_messages.isEmpty || incoming.first['id'] != _messages.first['id']));
      setState(() {
        _messages = incoming;
        _loading = false;
      });
      if (changed) _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      if (initial) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    _msgCtrl.clear();
    setState(() => _sending = true);
    // The composer is empty now — stop advertising typing immediately.
    _sendTyping(false);

    // Captured before the await so the error path never touches a disposed
    // context.
    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.apiPost('/safety/chat/${widget.tripId}', {'body': text});
      if (!mounted) return;
      await _fetchMessages();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception:', '').trim())),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.chatTitle,
          style: AppTokens.font(
            fontWeight: FontWeight.w800,
            color: go.text,
          ),
        ),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: go.text),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTokens.spaceLg),
                          child: Text(
                            strings.chatEmptyBody,
                            textAlign: TextAlign.center,
                            style: AppTokens.font(
                              color: go.muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.all(AppTokens.spaceMd),
                        // +1 when the typing bubble rides at the bottom.
                        itemCount: _messages.length + (_riderTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          // The list is reversed: index 0 is the visual
                          // bottom, which is exactly where "جاري الكتابة…"
                          // belongs — just above the composer.
                          if (_riderTyping && index == 0) {
                            return _TypingBubble(
                              surface: go.surface,
                              border: go.border,
                              muted: go.muted,
                            );
                          }
                          final msg = _messages[_riderTyping ? index - 1 : index];
                          // From the captain's perspective, mine == captain.
                          final isMine = msg['sender_role'] == 'captain';
                          return Align(
                            // AlignmentDirectional mirrors correctly in RTL:
                            // outgoing (mine) → end, incoming → start.
                            alignment: isMine
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.74,
                              ),
                              decoration: BoxDecoration(
                                // go.action: cyan in dark mode — white-on-cyan
                                // is ~1.8:1 (near-illegible); go.onAction fixes this.
                                color: isMine ? go.action : go.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusMd,
                                ),
                                border: isMine
                                    ? null
                                    : Border.all(color: go.border),
                              ),
                              child: Text(
                                msg['body']?.toString() ?? '',
                                style: AppTokens.font(
                                  color: isMine ? go.onAction : go.text,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              AppTokens.spaceSm,
              AppTokens.spaceMd,
              AppTokens.spaceMd,
            ),
            decoration: BoxDecoration(
              color: go.panel,
              border: Border(top: BorderSide(color: go.border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      onChanged: _onMessageChanged,
                      style: AppTokens.font(color: go.text),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: strings.chatComposerHint,
                        hintStyle: AppTokens.font(color: go.muted),
                        filled: true,
                        fillColor: go.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          borderSide: BorderSide(color: go.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          borderSide: BorderSide(color: go.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          // go.action for the focus ring — cyan in dark mode
                          // so the outline is visible on near-black surfaces.
                          borderSide: BorderSide(color: go.action),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceXs),
                  Material(
                    // go.action: cyan in dark mode — white-on-cyan is ~1.8:1.
                    color: go.action,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _sending ? null : _sendMessage,
                      child: SizedBox(
                        width: AppTokens.tapTarget,
                        height: AppTokens.tapTarget,
                        child: _sending
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: go.onAction,
                                ),
                              )
                            : Icon(
                                Icons.send_rounded,
                                color: go.onAction,
                                size: 20,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "جاري الكتابة…" bubble: three dots + label in an incoming-style
/// bubble, shown just above the composer while the other party is typing.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble({
    required this.surface,
    required this.border,
    required this.muted,
  });

  final Color surface;
  final Color border;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Align(
      // Incoming bubble must sit on the start edge in RTL (right side in Arabic).
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dot(), _dot(), _dot(),
            const SizedBox(width: 8),
            Text(
              strings.chatTyping,
              style: AppTokens.font(color: muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot() => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(shape: BoxShape.circle, color: muted),
      );
}

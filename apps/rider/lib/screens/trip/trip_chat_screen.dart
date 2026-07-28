import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';
import '../../services/trip_ws.dart';

/// The rider's in-trip chat with the captain.
///
/// Colour was the bug here: the message text and the input were hardwired to
/// `Colors.white`, which is invisible on the light theme's white cards — the
/// "الخطوط البيضاء مش بتظهر" complaint. Everything now resolves through the
/// active theme: white only on the brand-coloured bubble, the theme's text
/// colour everywhere else.
///
/// Liveness comes from two paths: the trip WebSocket relays new messages and
/// `chat.typing` events the moment they are broadcast (this screen owns a
/// direct socket connection), and a light 6s poll backstops it so a dropped
/// socket never freezes the thread. The typing events drive the
/// "جاري الكتابة…" bubble above the composer; outgoing signals are throttled
/// and the bubble self-expires, so a lost "stop" signal never wedges it.
class TripChatScreen extends StatefulWidget {
  final String tripId;
  const TripChatScreen({super.key, required this.tripId});

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  Timer? _pollTimer;

  /// Direct room socket for this thread. The screen previously rode only the
  /// 6s poll; the socket makes messages and typing hints appear the moment
  /// the server broadcasts them.
  TripWebSocketService? _ws;

  /// Typing indicator state — see the captain screen for the full contract:
  /// server stores nothing, the bubble self-expires, outgoing signals are
  /// throttled to one POST per window.
  bool _captainTyping = false;
  Timer? _typingClearTimer;
  DateTime? _lastTypingSentAt;
  static const _typingThrottle = Duration(seconds: 2);
  static const _typingExpiry = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _fetchMessages(initial: true);
    // Poll quietly so new captain messages appear while the rider is in the
    // thread, without requiring them to leave and re-enter.
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) _fetchMessages();
    });
    _connectWs();
  }

  void _connectWs() {
    final state = context.read<AppState>();
    final token = state.token;
    if (token == null) return;
    _ws = TripWebSocketService(
      baseUrl: state.baseUrl,
      tripId: widget.tripId,
      token: token,
      onMessage: (ev) {
        if (!mounted) return;
        final type = ev['type'] as String?;
        if (type == 'chat.message' || type == 'trip.chat') {
          if (ev['senderRole'] != 'rider') _setCaptainTyping(false);
          _fetchMessages();
        } else if (type == 'chat.typing' && ev['senderRole'] != 'rider') {
          _setCaptainTyping(ev['typing'] == true);
        }
      },
    )..connect();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _typingClearTimer?.cancel();
    _ws?.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _sendTyping(false);
    super.dispose();
  }

  void _setCaptainTyping(bool typing) {
    _typingClearTimer?.cancel();
    if (typing) {
      _typingClearTimer = Timer(_typingExpiry, () {
        if (mounted) setState(() => _captainTyping = false);
      });
    }
    if (_captainTyping != typing && mounted) {
      setState(() => _captainTyping = typing);
    }
  }

  void _sendTyping(bool typing) {
    final state = context.read<AppState>();
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
    final appState = context.read<AppState>();
    try {
      final res = await appState.apiGet('/safety/chat/${widget.tripId}');
      // Leaving the chat while the fetch is in flight would otherwise call
      // setState on a disposed State.
      if (!mounted) return;
      final incoming = (res['messages'] as List?) ?? [];
      final changed = incoming.length != _messages.length ||
          (incoming.isNotEmpty &&
              (_messages.isEmpty || incoming.first['id'] != _messages.first['id']));
      setState(() {
        _messages = incoming;
        _loading = false;
      });
      if (changed) _scrollToBottom();
    } catch (e) {
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
    _sendTyping(false);

    // Captured before the await so the error path does not touch a
    // BuildContext that may no longer be mounted.
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.apiPost('/safety/chat/${widget.tripId}', {'body': text});
      if (!mounted) return;
      await _fetchMessages();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Theme-resolved palette. The previous version hardcoded light-theme
    // tokens AND white text, so in light mode it drew white-on-white and in
    // dark mode it kept a light background. Both directions now follow the
    // active theme.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.darkBg : AppTokens.lightBg;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final surface = isDark ? AppTokens.darkSurface : AppTokens.lightSurface;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          'المحادثة',
          style: GoogleFonts.ibmPlexSansArabic(
            fontWeight: FontWeight.w800,
            color: text,
          ),
        ),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: text),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'لا توجد رسائل بعد.\nابدأ المحادثة مع الكابتن.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.ibmPlexSansArabic(
                              color: muted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_captainTyping ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_captainTyping && index == 0) {
                            return _TypingBubble(
                              surface: surface,
                              border: border,
                              muted: muted,
                            );
                          }
                          final msg =
                              _messages[_captainTyping ? index - 1 : index];
                          final isMine = msg['sender_role'] == 'rider';
                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
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
                                // My bubble keeps the brand colour, so ITS
                                // text is white. Their bubble is the themed
                                // surface, so ITS text is the themed ink —
                                // this is the line that was always white and
                                // vanished against the light cards.
                                color: isMine ? AppTokens.primary : surface,
                                borderRadius: BorderRadius.circular(
                                  AppTokens.radiusMd,
                                ),
                                border: isMine
                                    ? null
                                    : Border.all(color: border),
                              ),
                              child: Text(
                                msg['body']?.toString() ?? '',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  color: isMine ? Colors.white : text,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: panel,
              border: Border(top: BorderSide(color: border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      onChanged: _onMessageChanged,
                      // The input text itself also used to be forced white —
                      // unreadable while typing in light mode.
                      style: GoogleFonts.ibmPlexSansArabic(color: text),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة...',
                        hintStyle: GoogleFonts.ibmPlexSansArabic(color: muted),
                        filled: true,
                        fillColor: surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          borderSide: BorderSide(color: border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          borderSide: BorderSide(color: border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                          borderSide:
                              const BorderSide(color: AppTokens.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppTokens.primary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _sending ? null : _sendMessage,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
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

/// The "جاري الكتابة…" bubble, mirrored from the captain app: three dots +
/// label in an incoming-style bubble just above the composer.
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
    return Align(
      alignment: Alignment.centerLeft,
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
              'جاري الكتابة…',
              style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 12.5),
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

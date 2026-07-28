import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

/// The rider's in-trip chat with the captain.
///
/// Colour was the bug here: the message text and the input were hardwired to
/// `Colors.white`, which is invisible on the light theme's white cards — the
/// "الخطوط البيضاء مش بتظهر" complaint. Everything now resolves through the
/// active theme: white only on the brand-coloured bubble, the theme's text
/// colour everywhere else.
///
/// A light 6s poll keeps the thread current while the screen is open (the
/// trip WebSocket drives the map screen, not this one).
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

  @override
  void initState() {
    super.initState();
    _fetchMessages(initial: true);
    // Poll quietly so new captain messages appear while the rider is in the
    // thread, without requiring them to leave and re-enter.
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) _fetchMessages();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
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

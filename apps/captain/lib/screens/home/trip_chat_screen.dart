import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

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
        _fetchMessages();
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
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final surface = isDark ? AppTokens.darkSurface : AppTokens.lightSurface;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    return Scaffold(
      backgroundColor: isDark ? AppTokens.darkBg : AppTokens.lightBg,
      appBar: AppBar(
        title: Text(
          'محادثة الراكب',
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
                          padding: const EdgeInsets.all(AppTokens.spaceLg),
                          child: Text(
                            'لا توجد رسائل بعد.\nابدأ المحادثة مع الراكب.',
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
                        padding: const EdgeInsets.all(AppTokens.spaceMd),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          // From the captain's perspective, mine == captain.
                          final isMine = msg['sender_role'] == 'captain';
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
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              AppTokens.spaceSm,
              AppTokens.spaceMd,
              AppTokens.spaceMd,
            ),
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
                  const SizedBox(width: AppTokens.spaceXs),
                  Material(
                    color: AppTokens.primary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _sending ? null : _sendMessage,
                      child: SizedBox(
                        width: AppTokens.tapTarget,
                        height: AppTokens.tapTarget,
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

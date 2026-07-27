import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

class TripChatScreen extends StatefulWidget {
  final String tripId;
  const TripChatScreen({super.key, required this.tripId});

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final _msgCtrl = TextEditingController();
  List<dynamic> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
  }

  Future<void> _fetchMessages() async {
    final appState = context.read<AppState>();
    try {
      final res = await appState.apiGet('/safety/chat/${widget.tripId}');
      // Leaving the chat while the fetch is in flight would otherwise call
      // setState on a disposed State.
      if (!mounted) return;
      setState(() {
        _messages = res['messages'] ?? [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_msgCtrl.text.isEmpty) return;
    final text = _msgCtrl.text;
    _msgCtrl.clear();

    // Captured before the await so the error path does not touch a
    // BuildContext that may no longer be mounted.
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await appState.apiPost('/safety/chat/${widget.tripId}', {'body': text});
      if (!mounted) return;
      _fetchMessages();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('المحادثة', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: AppTokens.lightPanel,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMine = msg['sender_role'] == 'rider';
                      return Align(
                        alignment: isMine ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMine ? AppTokens.primary : AppTokens.lightSurface,
                            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                          ),
                          child: Text(
                            msg['body']?.toString() ?? '',
                            style: GoogleFonts.ibmPlexSansArabic(color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTokens.lightPanel,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة...',
                      hintStyle: const TextStyle(color: AppTokens.lightMuted),
                      filled: true,
                      fillColor: AppTokens.lightSurface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: AppTokens.primary),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

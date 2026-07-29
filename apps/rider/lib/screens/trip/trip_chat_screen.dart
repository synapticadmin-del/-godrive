import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
    final go = GoTheme.of(context);
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text('المحادثة', style: AppTokens.font()),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
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
                            color: isMine ? go.action : go.surface,
                            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                            border: isMine ? null : Border.all(color: go.border),
                          ),
                          child: Text(
                            msg['body']?.toString() ?? '',
                            style: AppTokens.font(
                              color: isMine ? go.onAction : text,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: panel,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    style: TextStyle(color: text),
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة...',
                      hintStyle: TextStyle(color: muted),
                      filled: true,
                      fillColor: go.surface,
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

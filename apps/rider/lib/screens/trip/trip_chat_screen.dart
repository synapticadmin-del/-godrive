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
    try {
      final res = await context.read<AppState>().apiGet('/safety/chat/${widget.tripId}');
      setState(() {
        _messages = res['messages'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    if (_msgCtrl.text.isEmpty) return;
    final text = _msgCtrl.text;
    _msgCtrl.clear();
    try {
      await context.read<AppState>().apiPost('/safety/chat/${widget.tripId}', {'content': text});
      _fetchMessages();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
                      final isMine = msg['sender'] == 'rider';
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
                            msg['content'],
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

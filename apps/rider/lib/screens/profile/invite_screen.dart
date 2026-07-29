import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/app_state.dart';

/// Invite screen — referral code + share button + rewards balance.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});
  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  Map<String, dynamic>? _referral;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = context.read<AppState>();
      final res = await state.apiGet('/user/profile');
      setState(() => _referral = res);
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _share() {
    final code = _referral?['referral_code'] ?? 'GODRIVE';
    Share.share(
      'جرّب GoDrive — تطبيق التوصل في مصر! استخدم كودي $code واحصل على خصم على أول رحلة.\n'
      'حمّل التطبيق الآن: https://godrive.app',
    );
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;
    final border = go.border;

    final code = _referral?['referral_code'] as String? ?? 'GODRIVE';
    final credits = (_referral?['credits'] as num?)?.toDouble() ?? 0;
    final invited = (_referral?['invited_count'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text('دعوة الأصدقاء', style: AppTokens.font(fontWeight: FontWeight.w700))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Hero card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTokens.primary, AppTokens.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(AppTokens.radiusXl),
                  ),
                  child: Column(children: [
                    const Icon(Icons.card_giftcard, color: Colors.white, size: 48),
                    const SizedBox(height: 12),
                    Text('ادعُ أصدقاءك واربح', style: AppTokens.font(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('احصل على 20 ج.م لكل صديق يستخدم كودك', style: AppTokens.font(fontSize: 13, color: Colors.white70)),
                  ]),
                ),
                const SizedBox(height: 24),
                // Referral code
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
                  child: Column(children: [
                    Text('كود الدعوة', style: AppTokens.font(fontSize: 13, color: muted)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(color: AppTokens.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                      child: Text(code, style: AppTokens.font(fontSize: 28, fontWeight: FontWeight.w800, color: AppTokens.primary, letterSpacing: 2)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                // Stats
                Row(children: [
                  Expanded(child: _statCard('رصيدك', '${credits.toStringAsFixed(0)} ج.م', panel, text, muted, border)),
                  const SizedBox(width: 10),
                  Expanded(child: _statCard('أصدقاء دُعوا', '$invited', panel, text, muted, border)),
                ]),
                const SizedBox(height: 24),
                // Share button
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share, size: 20),
                    label: Text('مشاركة الكود', style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTokens.primary, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd))),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _statCard(String label, String value, Color panel, Color text, Color muted, Color border) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Column(children: [
        Text(label, style: AppTokens.font(fontSize: 12, color: muted)),
        const SizedBox(height: 4),
        Text(value, style: AppTokens.font(fontSize: 20, fontWeight: FontWeight.w800, color: AppTokens.primary)),
      ]),
    );
  }
}
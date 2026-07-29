import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';
import 'topup_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  List<dynamic> _transactions = [];

  @override
  void initState() {
    super.initState();
    _fetchWallet();
  }

  Future<void> _fetchWallet() async {
    try {
      final res = await context.read<AppState>().fetchWallet();
      setState(() {
        _transactions = res['transactions'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = context.watch<AppState>().walletBalance ?? 0.0;
    final go = GoTheme.of(context);
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        // Inherits appBarTheme.titleTextStyle, so the title matches every other
        // AppBar in the app instead of pinning its own typeface.
        title: const Text('المحفظة'),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    // Neutral card: pure white in light, near-black panel in
                    // dark — no brand gradient, so the balance page stays in
                    // the monochrome ramp the rider expects from the wallet.
                    color: panel,
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    border: Border.all(color: go.border),
                    boxShadow: AppTokens.shadowCard,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('الرصيد المتاح', style: AppTokens.font(color: muted, fontSize: 16)),
                      const SizedBox(height: 8),
                      // Neutral ink, not the brand colour. At 36sp the balance is
                      // already the loudest thing on the page through sheer size;
                      // setting it in lime as well made the dark card read as neon
                      // — the same figure and the full-width button both in
                      // #C1F11D on near-black. Money is authoritative, not
                      // decorative, so the brand stays on the action below it.
                      Text(
                        '${balance.toStringAsFixed(2)} ج.م',
                        style: AppTokens.money(fontSize: 36, color: text),
                      ),
                      const SizedBox(height: 24),
                      // Colours come from elevatedButtonTheme (go.action /
                      // go.onAction), which is the same pairing this was
                      // hardcoding — one less place to drift.
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const TopupScreen())).then((_) => _fetchWallet());
                        },
                        child: Text('شحن المحفظة', style: AppTokens.font(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      final isCredit = tx['type'] == 'credit';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                          border: Border.all(color: go.border),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: isCredit ? AppTokens.success.withOpacity(0.2) : AppTokens.danger.withOpacity(0.2),
                            child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? AppTokens.success : AppTokens.danger),
                          ),
                          title: Text(tx['description'] ?? 'عملية', style: AppTokens.font(color: text)),
                          subtitle: Text(tx['createdAt'] ?? '', style: AppTokens.font(color: muted, fontSize: 12)),
                          trailing: Text(
                            '${isCredit ? '+' : '-'}${tx['amount']} ج.م',
                            style: AppTokens.font(
                              color: isCredit ? AppTokens.success : text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

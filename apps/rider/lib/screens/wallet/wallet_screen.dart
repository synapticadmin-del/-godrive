import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final isDark = go.isDark;
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text('المحفظة', style: GoogleFonts.ibmPlexSansArabic()),
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
                      Text('الرصيد المتاح', style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(
                        '${balance.toStringAsFixed(2)} ج.م',
                        style: GoogleFonts.ibmPlexSansArabic(
                          color: isDark ? AppTokens.lime : AppTokens.primary,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const TopupScreen())).then((_) => _fetchWallet());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? AppTokens.lime : AppTokens.primary,
                          foregroundColor: isDark ? AppTokens.onLime : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusSm)),
                        ),
                        child: Text('شحن المحفظة', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.bold)),
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
                          title: Text(tx['description'] ?? 'عملية', style: GoogleFonts.ibmPlexSansArabic(color: text)),
                          subtitle: Text(tx['createdAt'] ?? '', style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 12)),
                          trailing: Text(
                            '${isCredit ? '+' : '-'}${tx['amount']} ج.م',
                            style: GoogleFonts.ibmPlexSansArabic(
                              color: isCredit ? AppTokens.success : text,
                              fontWeight: FontWeight.bold,
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

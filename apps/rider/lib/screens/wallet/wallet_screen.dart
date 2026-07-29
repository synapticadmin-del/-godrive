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
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final gradientEnd = go.isDark ? const Color(0xFF1E3306) : const Color(0xFFF1FBE2);
    final balance = context.watch<AppState>().walletBalance ?? 0.0;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.walletTitle, style: AppTokens.font()),
        backgroundColor: go.panel,
        foregroundColor: go.text,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTokens.primary, gradientEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: AppTokens.primary.withOpacity(go.isDark ? 0.18 : 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(strings.availableBalance, style: AppTokens.font(color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('${balance.toStringAsFixed(2)} ${strings.egp}', style: AppTokens.font(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
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
                  child: _transactions.isEmpty
                      ? EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: strings.noTransactionsYet,
                          subtitle: strings.transactionsWillAppearHere,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _transactions.length,
                          itemBuilder: (context, index) {
                            final tx = _transactions[index];
                            final isCredit = tx['type'] == 'credit';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: isCredit ? AppTokens.success.withOpacity(0.2) : AppTokens.danger.withOpacity(0.2),
                                child: Icon(isCredit ? Icons.arrow_downward : Icons.arrow_upward, color: isCredit ? AppTokens.success : AppTokens.danger),
                              ),
                              title: Text(tx['description'] ?? strings.transactionFallback, style: AppTokens.font(color: go.text)),
                              subtitle: Text(tx['createdAt'] ?? '', style: AppTokens.font(color: go.muted, fontSize: 12)),
                              trailing: Text(
                                '${isCredit ? '+' : '-'}${tx['amount']} ${strings.egp}',
                                style: AppTokens.font(
                                  color: isCredit ? AppTokens.success : go.text,
                                  fontWeight: FontWeight.bold,
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

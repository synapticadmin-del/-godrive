import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

/// Manage payment methods: cash, wallet, cards. Add card via Paymob flow.
class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});
  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  String _selected = 'cash';
  double _walletBalance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = context.read<AppState>();
      final res = await state.apiGet('/user/wallet');
      setState(() {
        _walletBalance = (res['balance'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.paymentMethodsTitle,
          style: AppTokens.font(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const SkeletonList(count: 3)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _methodCard(
                  go: go,
                  strings: strings,
                  icon: Icons.payments_outlined,
                  title: strings.paymentCashTitle,
                  subtitle: strings.paymentCashSubtitle,
                  value: 'cash',
                ),
                const SizedBox(height: 10),
                _methodCard(
                  go: go,
                  strings: strings,
                  icon: Icons.account_balance_wallet_outlined,
                  title: strings.paymentWalletTitle,
                  subtitle: strings.paymentWalletBalanceLine(
                      _walletBalance.toStringAsFixed(0)),
                  value: 'wallet',
                  trailing: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/wallet'),
                    child: Text(strings.paymentTopUpAction),
                  ),
                ),
                const SizedBox(height: 10),
                _methodCard(
                  go: go,
                  strings: strings,
                  icon: Icons.credit_card_outlined,
                  title: strings.paymentCardTitle,
                  subtitle: strings.paymentCardSubtitle,
                  value: 'card',
                  trailing: TextButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.paymentCardComingSoonToast)),
                    ),
                    child: Text(strings.paymentAddAction),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  strings.paymentNoteTitle,
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: go.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  strings.paymentNoteBody,
                  style: AppTokens.font(
                    fontSize: 12,
                    color: go.muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _methodCard({
    required GoTheme go,
    required AppStrings strings,
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
    Widget? trailing,
  }) {
    final selected = _selected == value;
    return GestureDetector(
      onTap: () => setState(() => _selected = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: go.panel,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(
            color: selected ? AppTokens.primary : go.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? AppTokens.primary.withOpacity(0.1)
                  : (go.muted.withOpacity(0.08)),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Icon(icon,
                color: selected ? AppTokens.primary : go.muted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTokens.font(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTokens.font(fontSize: 12, color: go.muted),
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing
          else
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTokens.primary : go.muted,
              size: 22,
            ),
        ]),
      ),
    );
  }
}

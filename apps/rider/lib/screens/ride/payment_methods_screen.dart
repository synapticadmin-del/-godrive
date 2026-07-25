import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    return Scaffold(
      appBar: AppBar(title: Text('طرق الدفع', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700))),
      body: _loading
          ? const SkeletonList(count: 3)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _methodCard(
                  icon: Icons.payments_outlined,
                  title: 'كاش',
                  subtitle: 'ادفع للكابتن مباشرة',
                  panel: panel,
                  text: text,
                  muted: muted,
                  border: border,
                  value: 'cash',
                ),
                const SizedBox(height: 10),
                _methodCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'المحفظة',
                  subtitle: 'الرصيد: ${_walletBalance.toStringAsFixed(0)} ج.م',
                  panel: panel,
                  text: text,
                  muted: muted,
                  border: border,
                  value: 'wallet',
                  trailing: TextButton(onPressed: () => Navigator.pushNamed(context, '/wallet'), child: const Text('شحن')),
                ),
                const SizedBox(height: 10),
                _methodCard(
                  icon: Icons.credit_card_outlined,
                  title: 'بطاقة بنكية',
                  subtitle: 'إضافة بطاقة عبر Paymob',
                  panel: panel,
                  text: text,
                  muted: muted,
                  border: border,
                  value: 'card',
                  trailing: TextButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('سيتم تفعيل الدفع بالبطاقة قريبًا')),
                    ),
                    child: const Text('إضافة'),
                  ),
                ),
                const SizedBox(height: 24),
                Text('ملاحظة', style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, fontWeight: FontWeight.w700, color: muted)),
                const SizedBox(height: 4),
                Text(
                  'يمكنك تغيير طريقة الدفع الافتراضية في أي وقت. سيتم استخدامها تلقائيًا في رحلاتك القادمة.',
                  style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: muted, height: 1.5),
                ),
              ],
            ),
    );
  }

  Widget _methodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color panel,
    required Color text,
    required Color muted,
    required Color border,
    required String value,
    Widget? trailing,
  }) {
    final selected = _selected == value;
    return GestureDetector(
      onTap: () => setState(() => _selected = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          border: Border.all(color: selected ? AppTokens.primary : border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: selected ? AppTokens.primary.withOpacity(0.1) : (muted.withOpacity(0.08)),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            ),
            child: Icon(icon, color: selected ? AppTokens.primary : muted, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.ibmPlexSansArabic(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.ibmPlexSansArabic(fontSize: 12, color: muted)),
          ])),
          if (trailing != null) trailing
          else Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppTokens.primary : muted, size: 22),
        ]),
      ),
    );
  }
}
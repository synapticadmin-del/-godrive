import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _wallet;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = context.read<CaptainState>();
      final res = await state.apiGet('/captain/wallet');
      if (mounted) {
        setState(() {
          _wallet = res['wallet'];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _requestPayout() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTokens.lightPanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTokens.radiusXl)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('طلب سحب الأرباح', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTokens.lightText)),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.phone_android, color: AppTokens.primary),
              title: const Text('فودافون كاش', style: TextStyle(color: AppTokens.lightText)),
              tileColor: AppTokens.lightSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب السحب بنجاح')));
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.account_balance, color: AppTokens.accent),
              title: const Text('انستا باي (InstaPay)', style: TextStyle(color: AppTokens.lightText)),
              tileColor: AppTokens.lightSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب السحب بنجاح')));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.lightBg,
      appBar: AppBar(
        title: const Text('المحفظة'),
        backgroundColor: AppTokens.lightPanel,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTokens.primary))
          : _wallet == null
              ? const Center(child: Text('خطأ في تحميل المحفظة', style: TextStyle(color: AppTokens.danger)))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTokens.success, AppTokens.success.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                        boxShadow: [
                          BoxShadow(color: AppTokens.success.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text('الرصيد المتاح للسحب', style: TextStyle(color: Colors.white70, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text(
                            '${_wallet!['balance'] ?? 0} ج.م',
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _requestPayout,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTokens.success,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                              minimumSize: const Size(double.infinity, 50),
                            ),
                            child: const Text('سحب الآن', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ).animate().scale(duration: 400.ms),
                    const SizedBox(height: 32),
                    const Text('سجل المعاملات', style: TextStyle(color: AppTokens.lightText, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ...List.generate(3, (index) => _buildTransactionCard(index)).animate(interval: 100.ms).fade().slideX(begin: 0.1),
                  ],
                ),
    );
  }

  Widget _buildTransactionCard(int index) {
    return Card(
      color: AppTokens.lightSurface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: AppTokens.lightBorder),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppTokens.success.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.arrow_downward, color: AppTokens.success),
        ),
        title: const Text('أرباح رحلة', style: TextStyle(color: AppTokens.lightText)),
        subtitle: const Text('منذ يومين', style: TextStyle(color: AppTokens.lightMuted, fontSize: 12)),
        trailing: const Text('+ 45 ج.م', style: TextStyle(color: AppTokens.success, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }
}

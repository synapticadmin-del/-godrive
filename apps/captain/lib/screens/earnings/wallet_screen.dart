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
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// GET /captain/wallet returns a flat payload
  /// `{balance, currency, weekTrips, weekCommission, nextPayoutWindow}` — there
  /// is no `wallet` envelope and no transaction list on that route. The ledger
  /// lives on GET /user/wallet/transactions, so both are fetched here.
  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final state = context.read<CaptainState>();
      final res = await state.apiGet('/captain/wallet');

      // The ledger is a secondary concern: a failure there must not blank out
      // the balance the captain came here to read.
      List<Map<String, dynamic>> txs = [];
      try {
        final txRes = await state.apiGet('/user/wallet/transactions?limit=50');
        txs = (txRes['transactions'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      } catch (_) {}

      if (mounted) {
        setState(() {
          _wallet = res;
          _transactions = txs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _loading = false;
        });
      }
    }
  }

  double get _balance => (_wallet?['balance'] as num?)?.toDouble() ?? 0;

  void _requestPayout() {
    if (_balance < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد رصيد كافٍ للسحب')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
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
            const SizedBox(height: 4),
            Text(
              'الرصيد المتاح: ${_balance.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontSize: 13, color: AppTokens.lightMuted),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.phone_android, color: AppTokens.primary),
              title: const Text('فودافون كاش', style: TextStyle(color: AppTokens.lightText)),
              tileColor: AppTokens.lightSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _collectAccountAndSubmit(
                  method: 'vodafone_cash',
                  label: 'فودافون كاش',
                  hint: 'رقم محفظة فودافون كاش',
                  keyboardType: TextInputType.phone,
                );
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.account_balance, color: AppTokens.accent),
              title: const Text('انستا باي (InstaPay)', style: TextStyle(color: AppTokens.lightText)),
              tileColor: AppTokens.lightSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _collectAccountAndSubmit(
                  method: 'instapay',
                  label: 'انستا باي',
                  hint: 'عنوان الدفع (IPA) أو رقم الحساب',
                  keyboardType: TextInputType.text,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// POST /captain/wallet/payout requires `account_info` (min 3 chars) next to
  /// `amount` and `method`; omitting it made every payout fail validation, so
  /// the destination account is collected before submitting.
  Future<void> _collectAccountAndSubmit({
    required String method,
    required String label,
    required String hint,
    required TextInputType keyboardType,
  }) async {
    final controller = TextEditingController();
    final account = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('السحب عبر $label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'سيتم سحب ${_balance.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              autofocus: true,
              decoration: InputDecoration(labelText: hint),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
            child: const Text('تأكيد السحب'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || account == null) return;
    if (account.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء إدخال بيانات حساب صحيحة'), backgroundColor: AppTokens.danger),
      );
      return;
    }

    // Captured before the await so the async gap cannot invalidate it.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final state = context.read<CaptainState>();
      await state.apiPost('/captain/wallet/payout', {
        'method': method,
        'amount': _balance,
        'account_info': account,
      });
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('تم إرسال طلب السحب بنجاح إلى $label')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('فشل طلب السحب: ${e.toString().replaceAll('Exception:', '').trim()}'),
          backgroundColor: AppTokens.danger,
        ),
      );
    }
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
              ? ErrorState(
                  message: _error ?? 'خطأ في تحميل المحفظة',
                  onRetry: _load,
                )
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
                            '${_balance.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          ),
                          if (_wallet!['nextPayoutWindow'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'موعد الصرف: ${_wallet!['nextPayoutWindow']}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
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
                    if (_transactions.isEmpty)
                      const EmptyState(icon: Icons.account_balance_wallet_outlined, title: 'لا توجد معاملات سابقة بالمحفظة حتى الآن')
                    else
                      ..._transactions.map(_buildTransactionCard),
                  ],
                ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final isCredit = tx['direction'] == 'credit';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final note = tx['note'] ?? (isCredit ? 'شحن رصيد' : 'خصم معاملة');
    // substring(0, 10) throws on any timestamp shorter than 10 chars, so the
    // date is trimmed by length instead.
    final rawDate = tx['created_at']?.toString() ?? '';
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    final pending = tx['status'] == 'pending';

    return Card(
      color: AppTokens.lightSurface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: const BorderSide(color: AppTokens.lightBorder),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isCredit ? AppTokens.success : AppTokens.danger).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            color: isCredit ? AppTokens.success : AppTokens.danger,
          ),
        ),
        title: Text(note, style: const TextStyle(color: AppTokens.lightText, fontWeight: FontWeight.w600)),
        subtitle: Text(
          pending ? '$date • قيد التنفيذ' : date,
          style: TextStyle(
            color: pending ? AppTokens.accent : AppTokens.lightMuted,
            fontSize: 12,
          ),
        ),
        trailing: Text(
          '${isCredit ? "+" : "-"} ${amount.toStringAsFixed(0)} ج.م',
          style: TextStyle(
            color: isCredit ? AppTokens.success : AppTokens.danger,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

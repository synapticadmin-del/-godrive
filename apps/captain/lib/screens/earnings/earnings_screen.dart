import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'wallet_screen.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final state = context.read<CaptainState>();
      final res = await state.earnings();
      if (mounted) {
        setState(() {
          _data = res;
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

  /// GET /captain/earnings responds with a flat payload:
  /// `{from, to, trips, gross, commission, net, currency}`.
  /// Amounts are formatted to two decimals because the server returns raw
  /// REAL sums (e.g. 137.5), which previously rendered as "137.5 ج.م".
  String _money(String key) {
    final value = (_data?[key] as num?)?.toDouble() ?? 0;
    return value.toStringAsFixed(2);
  }

  String _count(String key) => ((_data?[key] as num?)?.toInt() ?? 0).toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.lightBg,
      appBar: AppBar(
        title: const Text('الأرباح'),
        backgroundColor: AppTokens.lightPanel,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTokens.primary))
          : _data == null
              ? ErrorState(
                  message: _error ?? 'خطأ في تحميل بيانات الأرباح',
                  onRetry: _load,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTokens.primary, AppTokens.primary.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                        boxShadow: [
                          BoxShadow(color: AppTokens.primary.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text('صافي الأرباح', style: TextStyle(color: Colors.white70, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text(
                            '${_money('net')} ج.م',
                            style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'آخر ٧ أيام',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ).animate().scale(duration: 400.ms),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard('الرحلات', _count('trips'), Icons.directions_car, AppTokens.accent),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildStatCard('إجمالي الدخل', '${_money('gross')} ج', Icons.attach_money, AppTokens.success),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildStatCard('العمولة المخصومة', '${_money('commission')} ج', Icons.pie_chart, AppTokens.danger),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                      icon: const Icon(Icons.account_balance_wallet, color: Colors.white),
                      label: const Text('المحفظة والسحب', style: TextStyle(color: Colors.white, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTokens.lightSurface,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                        side: BorderSide(color: AppTokens.lightBorder),
                      ),
                    ).animate().slideY(begin: 0.5),
                  ],
                ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTokens.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: AppTokens.lightMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: AppTokens.lightText, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    ).animate().fade().slideY(begin: 0.2);
  }
}

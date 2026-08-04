import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:tempo_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'wallet_screen.dart';

/// The captain's earnings summary.
///
/// Earnings are the reason the captain opens this app, so the net figure is
/// treated as the hero and everything else supports it. The previous version
/// set every number in bare `TextStyle`, which meant the app's own font was
/// never applied here and the figures rendered in the fallback face.
///
/// It also adds a breakdown the old screen only implied: gross minus
/// commission equals net. A driver who cannot see where the deduction went
/// does not trust the number.
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
      final res = await context.read<CaptainState>().earnings();
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

  /// `GET /captain/earnings` responds with a flat payload:
  /// `{from, to, trips, gross, commission, net, currency}`. Amounts are
  /// formatted to two decimals because the server returns raw REAL sums
  /// (e.g. 137.5), which would otherwise render as "137.5 EGP".
  double _value(String key) => (_data?[key] as num?)?.toDouble() ?? 0;
  String _money(String key) => _value(key).toStringAsFixed(2);
  int _countInt(String key) => (_data?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    // Localised copy — the screen reads every label from here instead of
    // inline literals, so Arabic and English are guaranteed to exist in pairs
    // and the screen carries no `isAr ? … : …` ternaries.
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.earningsTitle),
        backgroundColor: go.bg,
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: strings.refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? ErrorState(
                  message: _error ?? strings.earningsLoadError,
                  onRetry: _load,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    children: [
                      _buildHero(strings),
                      const SizedBox(height: AppTokens.spaceMd),
                      _buildBreakdown(go, strings),
                      const SizedBox(height: AppTokens.spaceMd),
                      _buildWalletCta(strings),
                      const SizedBox(height: AppTokens.spaceMd),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHero(AppStrings strings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceLg,
        vertical: AppTokens.spaceXl,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppTokens.primaryLight, AppTokens.primaryDark],
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusXl),
        boxShadow: AppTokens.glow(AppTokens.primary, opacity: 0.28),
      ),
      child: Column(
        children: [
          Text(
            strings.netEarnings,
            style: AppTokens.font(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _money('net'),
                  style: AppTokens.money(fontSize: 44, color: Colors.white),
                ),
                const SizedBox(width: 6),
                Text(
                  strings.egp,
                  style: AppTokens.font(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceSm,
              vertical: 5,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.local_taxi_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
                const SizedBox(width: 6),
                Text(
                  strings.tripsLast7Days(_countInt('trips')),
                  style: AppTokens.font(
                    color: Colors.white.withOpacity(0.95),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.1, end: 0);
  }

  /// Gross → commission → net, stated plainly. The arithmetic is the point:
  /// the captain should be able to check the platform's maths themselves.
  Widget _buildBreakdown(GoTheme go, AppStrings strings) {
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: go.border),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Column(
        children: [
          _row(
            icon: Icons.payments_rounded,
            tone: AppTokens.success,
            label: strings.grossIncome,
            value: '${_money('gross')} ${strings.egp}',
            go: go,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: Divider(color: go.border, height: 1),
          ),
          _row(
            icon: Icons.pie_chart_rounded,
            tone: AppTokens.accent,
            label: strings.platformCommission,
            value: '− ${_money('commission')} ${strings.egp}',
            go: go,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: Divider(color: go.border, height: 1),
          ),
          _row(
            icon: Icons.account_balance_wallet_rounded,
            tone: AppTokens.primary,
            label: strings.netForYou,
            value: '${_money('net')} ${strings.egp}',
            go: go,
            emphasise: true,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.12, end: 0);
  }

  Widget _row({
    required IconData icon,
    required Color tone,
    required String label,
    required String value,
    required GoTheme go,
    bool emphasise = false,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tone.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppTokens.radiusSm),
          ),
          child: Icon(icon, color: tone, size: 19),
        ),
        const SizedBox(width: AppTokens.spaceSm),
        Expanded(
          child: Text(
            label,
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
              color: emphasise ? go.text : go.muted,
            ),
          ),
        ),
        Text(
          value,
          style: AppTokens.money(
            fontSize: emphasise ? 19 : 16,
            color: emphasise ? AppTokens.primary : go.text,
            fontWeight: emphasise ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildWalletCta(AppStrings strings) {
    return SizedBox(
      height: AppTokens.primaryActionHeight,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WalletScreen()),
        ),
        icon: const Icon(Icons.account_balance_wallet_rounded, size: 21),
        label: Text(strings.walletAndWithdraw),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0);
  }
}

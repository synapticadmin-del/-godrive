import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:provider/provider.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

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
    final strings = AppStrings.of(context);
    if (_balance < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.noBalanceToWithdraw)),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final strings = AppStrings.of(sheetCtx);
        final go = GoTheme.of(sheetCtx);
        return Container(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            AppTokens.spaceXs,
            AppTokens.spaceMd,
            AppTokens.spaceLg,
          ),
          decoration: BoxDecoration(
            color: go.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusXl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sheet handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: go.border,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                ),
              ),
              Text(
                strings.payoutSheetTitle,
                style: AppTokens.font(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: go.text,
                ),
              ),
              const SizedBox(height: AppTokens.space2xs),
              Text(
                strings.availableBalanceLine(_balance.toStringAsFixed(2)),
                style: AppTokens.font(
                  fontSize: 13,
                  color: go.muted,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              _PayoutMethodTile(
                icon: Icons.phone_android_rounded,
                iconColor: AppTokens.primary,
                surface: go.surface,
                label: strings.vodafoneCashMethod,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _collectAccountAndSubmit(
                    method: 'vodafone_cash',
                    label: strings.vodafoneCashMethod,
                    hint: strings.vodafoneCashHint,
                    keyboardType: TextInputType.phone,
                  );
                },
              ),
              const SizedBox(height: AppTokens.spaceSm),
              _PayoutMethodTile(
                icon: Icons.account_balance_rounded,
                iconColor: AppTokens.accent,
                surface: go.surface,
                label: strings.instaPayMethod,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _collectAccountAndSubmit(
                    method: 'instapay',
                    label: strings.instaPayMethod,
                    hint: strings.instaPayHint,
                    keyboardType: TextInputType.text,
                  );
                },
              ),
            ],
          ),
        );
      },
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
      builder: (dialogCtx) {
        final strings = AppStrings.of(dialogCtx);
        return AlertDialog(
          title: Text(strings.payoutViaTitle(label)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.payoutAmountLine(_balance.toStringAsFixed(2)),
                style: AppTokens.font(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: controller,
                keyboardType: keyboardType,
                autofocus: true,
                decoration: InputDecoration(labelText: hint),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(strings.cancelAction),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
              child: Text(strings.confirmPayoutAction),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (!mounted || account == null) return;
    final strings = AppStrings.of(context);
    if (account.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.invalidAccountError),
          backgroundColor: AppTokens.danger,
        ),
      );
      return;
    }

    // Capture the messenger before the async gap so it stays valid.
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
        SnackBar(content: Text(strings.payoutSuccessToast(label))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.payoutFailedToast(e.toString().replaceAll('Exception:', '').trim()),
          ),
          backgroundColor: AppTokens.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.walletTitle,
          style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: go.text),
        ),
        backgroundColor: go.panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: strings.refresh,
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTokens.primary))
          : _wallet == null
              ? ErrorState(
                  message: _error ?? strings.walletLoadError,
                  onRetry: _load,
                )
              : ListView(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  children: [
                    _buildBalanceHero().animate().scale(
                          duration: 380.ms,
                          curve: Curves.easeOutBack,
                        ),
                    const SizedBox(height: AppTokens.spaceXl),
                    Text(
                      strings.transactionHistoryTitle,
                      style: AppTokens.font(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    if (_transactions.isEmpty)
                      EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        title: strings.noTransactionsYet,
                      )
                    else
                      ..._transactions.map(
                        (tx) => _buildTransactionRow(tx, go.panel, go.text, go.muted, go.border),
                      ),
                  ],
                ),
    );
  }

  /// The balance hero is the most important number on screen — it gets a
  /// gradient card, an oversized numeral via AppTokens.money, and the single
  /// primary action at exactly primaryActionHeight.
  Widget _buildBalanceHero() {
    final strings = AppStrings.of(context);
    final nextPayout = _wallet?['nextPayoutWindow']?.toString();
    final weekTrips = (_wallet?['weekTrips'] as num?)?.toInt();
    final weekCommission = (_wallet?['weekCommission'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTokens.primary, AppTokens.primaryDark],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        boxShadow: AppTokens.glow(AppTokens.primary, opacity: 0.28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.availableBalanceHero,
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          // Money uses w900 and tight tracking — readable in a glance at any
          // screen brightness or viewing angle.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _balance.toStringAsFixed(2),
                style: AppTokens.money(fontSize: 44, color: Colors.white),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Text(
                strings.egp,
                style: AppTokens.font(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
            ],
          ),
          if (nextPayout != null) ...[
            const SizedBox(height: AppTokens.space2xs),
            Text(
              strings.payoutWindowLine(nextPayout),
              style: AppTokens.font(
                fontSize: 12,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ],
          // Weekly summary chips give context — how much of that balance
          // arrived this week versus sitting from before.
          if (weekTrips != null || weekCommission != null) ...[
            const SizedBox(height: AppTokens.spaceMd),
            Wrap(
              spacing: AppTokens.spaceXs,
              children: [
                if (weekTrips != null)
                  _HeroChip(label: strings.weekTripsChip(weekTrips)),
                if (weekCommission != null)
                  _HeroChip(
                    label: strings.weekCommissionChip(weekCommission.toStringAsFixed(0)),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMd),
          ] else
            const SizedBox(height: AppTokens.spaceLg),
          // Primary action at the required 56dp touch target height.
          SizedBox(
            width: double.infinity,
            height: AppTokens.primaryActionHeight,
            child: ElevatedButton.icon(
              onPressed: _requestPayout,
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 20),
              label: Text(
                strings.withdrawNowAction,
                style: AppTokens.font(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTokens.primary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTokens.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(
    Map<String, dynamic> tx,
    Color panel,
    Color text,
    Color muted,
    Color border,
  ) {
    final strings = AppStrings.of(context);
    final isCredit = tx['direction'] == 'credit';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final note = tx['note']?.toString() ??
        (isCredit ? strings.creditNoteFallback : strings.debitNoteFallback);

    // substring(0,10) throws on timestamps shorter than 10 chars, so trim by
    // length rather than blindly slicing.
    final rawDate = tx['created_at']?.toString() ?? '';
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    final pending = tx['status'] == 'pending';

    final amountColor = isCredit ? AppTokens.success : AppTokens.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          // Direction indicator — filled circle keeps credit/debit visually
          // distinct even for colour-blind users via the different icons.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: amountColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: amountColor,
              size: 20,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note,
                  style: AppTokens.font(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  pending ? '$date  •  ${strings.pendingMarker}' : date,
                  style: AppTokens.font(
                    fontSize: 12,
                    color: pending ? AppTokens.accent : muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceXs),
          // The amount in money-weight numerals so it pops against the label.
          Text(
            '${isCredit ? "+" : "−"} ${amount.toStringAsFixed(0)} ${strings.egp}',
            style: AppTokens.money(
              fontSize: 16,
              color: amountColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Payout method tile — extracted so each row is consistently shaped.
class _PayoutMethodTile extends StatelessWidget {
  const _PayoutMethodTile({
    required this.icon,
    required this.iconColor,
    required this.surface,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color surface;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
            vertical: AppTokens.spaceSm,
          ),
          child: Row(
            children: [
              Container(
                width: AppTokens.tapTarget,
                height: AppTokens.tapTarget,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: AppTokens.spaceMd),
              Text(
                label,
                style: AppTokens.font(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: go.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill chip used inside the balance hero card.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      ),
      child: Text(
        label,
        style: AppTokens.font(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

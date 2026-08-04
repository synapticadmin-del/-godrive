import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tempo_captain/services/captain_state.dart';

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

  /// Numeric-only pattern deliberately: a pattern with month or day *names*
  /// needs `intl` locale symbol data for the active locale, which throws a
  /// `LocaleDataException` if it was never initialised. Digits and slashes
  /// need nothing beyond the built-in fallback and read the same in Arabic.
  /// Identical to the rider ledger's pattern.
  static final DateFormat _stamp = DateFormat('dd/MM/yyyy • HH:mm');

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
                    _BalanceCard(
                      balance: _balance,
                      onWithdraw: _requestPayout,
                    ),
                    ..._buildPayoutMeta(strings),
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

  /// The captain-only figures that used to sit *inside* the balance card,
  /// between the number and the action. They are still worth showing, but
  /// stacking them there stretched the card well past the rider's and buried
  /// the two things the captain opens this screen for, so they moved directly
  /// underneath it.
  ///
  /// Returned as a list so the whole block — including its leading gap —
  /// disappears when the payload carries none of them, rather than leaving a
  /// stray `SizedBox` behind the card.
  List<Widget> _buildPayoutMeta(AppStrings strings) {
    final nextPayout = _wallet?['nextPayoutWindow']?.toString();
    final weekTrips = (_wallet?['weekTrips'] as num?)?.toInt();
    final weekCommission = (_wallet?['weekCommission'] as num?)?.toDouble();

    final chips = <Widget>[
      if (nextPayout != null && nextPayout.isNotEmpty)
        _MetaChip(
          icon: Icons.event_available_rounded,
          label: strings.payoutWindowLine(nextPayout),
        ),
      if (weekTrips != null)
        _MetaChip(
          icon: Icons.local_taxi_rounded,
          label: strings.weekTripsChip(weekTrips),
        ),
      if (weekCommission != null)
        _MetaChip(
          icon: Icons.percent_rounded,
          label: strings.weekCommissionChip(weekCommission.toStringAsFixed(0)),
        ),
    ];

    if (chips.isEmpty) return const [];

    return [
      const SizedBox(height: AppTokens.spaceMd),
      Wrap(
        spacing: AppTokens.spaceXs,
        runSpacing: AppTokens.spaceXs,
        children: chips,
      ),
    ];
  }

  Widget _buildTransactionRow(
    Map<String, dynamic> tx,
    Color panel,
    Color text,
    Color muted,
    Color border,
  ) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final isCredit = tx['direction'] == 'credit';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    // A note that is present but blank or whitespace-only is as useless to read
    // as a missing one, so it takes the fallback too. Guarding null alone left
    // those rows with an empty label above the date.
    final note = tx['note']?.toString().trim();
    final label = (note == null || note.isEmpty)
        ? (isCredit ? strings.creditNoteFallback : strings.debitNoteFallback)
        : note;

    final date = _formatStamp(tx['created_at']?.toString());
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
          // Colour carries direction and the glyph carries the reason, so the
          // row still parses for a colour-blind captain.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              // A flat 0.1 wash reads noticeably dimmer against the dark
              // panel than it does on the light one, so the tint lifts after
              // dark — the same two values the rider ledger uses.
              color: amountColor.withOpacity(go.isDark ? 0.18 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconFor(tx['type']?.toString(), isCredit),
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
                  label,
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
            '${isCredit ? "+" : "−"} ${_money(amount)} ${strings.egp}',
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

  /// `amount` is a REAL column already denominated in EGP — the integer
  /// `amount_piastres` column exists but is not part of the wallet SELECT, so
  /// there is nothing to divide by 100 here. Whole values lose the redundant
  /// trailing zeros; fractional ones keep both places.
  ///
  /// This replaced `toStringAsFixed(0)`, which *rounded*: a 12.50 EGP
  /// commission rendered as `13`. Both wallets read the same
  /// GET /user/wallet/transactions rows, and the rider ledger never rounded
  /// them.
  String _money(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  /// Timestamps arrive either as the table default `datetime('now')`
  /// (`YYYY-MM-DD HH:MM:SS`, UTC, no zone marker) or as an ISO string from the
  /// API helper. The bare form has no `Z`, so parsing it directly would tag UTC
  /// wall-clock numbers as local and show an Egyptian captain a time three
  /// hours early. Both shapes are normalised to UTC before converting.
  ///
  /// This replaced `substring(0, 10)`, which showed the raw `YYYY-MM-DD` with
  /// no time at all and left the UTC offset uncorrected.
  String _formatStamp(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return '';
    final normalised = value.endsWith('Z') || value.contains('+')
        ? value
        : '${value.replaceFirst(' ', 'T')}Z';
    final parsed = DateTime.tryParse(normalised);
    if (parsed == null) return value;
    return _stamp.format(parsed.toLocal());
  }

  /// The accounting bucket makes the ledger scannable — a captain spots a
  /// payout among commission deductions by shape before reading a word of it.
  ///
  /// `direction` is the credit/debit flag; `type` is the accounting bucket
  /// (topup, trip_payment, refund, commission, …), so the two are read
  /// separately. Kept identical to the rider ledger: both screens render the
  /// same rows from the same route, and any divergence here should be
  /// deliberate and visible.
  IconData _iconFor(String? type, bool isCredit) {
    switch (type) {
      case 'topup':
        return Icons.add_card_rounded;
      case 'trip_payment':
        return Icons.local_taxi_rounded;
      case 'refund':
        return Icons.replay_rounded;
      case 'promo_credit':
        return Icons.card_giftcard_rounded;
      case 'payout':
        return Icons.account_balance_rounded;
      case 'commission':
        return Icons.percent_rounded;
      case 'adjustment':
        return Icons.tune_rounded;
      default:
        return isCredit
            ? Icons.arrow_downward_rounded
            : Icons.arrow_upward_rounded;
    }
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

/// The balance hero.
///
/// Deliberately a line-for-line match of the rider wallet's `_BalanceCard` —
/// the two apps ship the same card, and only the action inside it differs: a
/// captain withdraws where a rider tops up. Everything here exists to keep one
/// number legible and one action obvious. The gradient stays in the brand's
/// dark ramp so white never lands on a pale stop; two clipped light pools give
/// the panel some physicality so it reads as a card rather than a coloured
/// rectangle; the wordmark sits where an issuer mark would.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.onWithdraw});

  final double balance;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final card = Container(
      decoration: BoxDecoration(
        // Both stops sit in the dark half of the brand ramp, which is the
        // whole point — white text has to survive the full sweep. Dark mode
        // drops a further step down so the card does not glare at night.
        gradient: LinearGradient(
          colors: go.isDark
              ? const [AppTokens.primaryDark, AppTokens.primaryDeep]
              : const [AppTokens.primary, AppTokens.primaryDark],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        boxShadow: AppTokens.glow(
          AppTokens.primary,
          opacity: go.isDark ? 0.16 : 0.30,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        child: Stack(
          children: [
            // Positioned children do not contribute to the Stack's size, so
            // the card still measures to its content column.
            const PositionedDirectional(
              top: -52,
              end: -34,
              child: _Bloom(size: 176, opacity: 0.13),
            ),
            const PositionedDirectional(
              bottom: -64,
              end: 44,
              child: _Bloom(size: 140, opacity: 0.08),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.availableBalanceHero,
                          style: AppTokens.font(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.82),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Two-tone in white keeps the lockup's own hierarchy
                      // without competing with the balance.
                      TempoWordmark(
                        fontSize: 13,
                        textColor: Colors.white.withOpacity(0.92),
                        accentColor: Colors.white.withOpacity(0.55),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceXs),
                  // Baseline alignment stops the currency suffix from
                  // floating against the tall numerals.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        balance.toStringAsFixed(2),
                        style: AppTokens.money(fontSize: 42, color: Colors.white),
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
                  const SizedBox(height: AppTokens.spaceLg),
                  SizedBox(
                    width: double.infinity,
                    height: AppTokens.primaryActionHeight,
                    child: ElevatedButton.icon(
                      onPressed: onWithdraw,
                      icon: const Icon(
                        Icons.account_balance_wallet_rounded,
                        size: 20,
                      ),
                      // White on the green card, so the action does not read
                      // brand green sitting on brand green.
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
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusMd),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (reduceMotion) return card;

    // Settling in from 96% reads as the card arriving. The previous revision
    // scaled from the flutter_animate default of zero, which popped it out of
    // nothing instead.
    return card
        .animate()
        .fadeIn(duration: 320.ms)
        .scale(
          begin: const Offset(0.96, 0.96),
          end: const Offset(1, 1),
          duration: 420.ms,
          curve: Curves.easeOutBack,
        );
  }
}

/// Captain-only figure shown under the balance card. Themed rather than white
/// now that it sits on the page background instead of on the gradient.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceSm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: go.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: go.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTokens.font(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: go.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft light pool used behind the balance card's gradient (rider parity).
class _Bloom extends StatelessWidget {
  const _Bloom({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

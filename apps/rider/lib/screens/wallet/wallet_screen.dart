import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import 'topup_screen.dart';

/// Rider wallet — balance hero plus the transaction ledger.
///
/// Rebuilt for two reasons, one cosmetic and one functional.
///
/// **Contrast.** The old balance card ran a gradient from the brand green to
/// `#F1FBE2` — a near-white tint — while painting the label and the balance in
/// white. The bottom-trailing half of the card was therefore white-on-white and
/// the number the rider opened the screen to read was effectively invisible.
/// The gradient now stays inside the brand's dark ramp end to end, which is
/// what `AppTokens.headerGradient` was built for, so white text holds at every
/// stop. The top-up button had the same problem in reverse: an `ElevatedButton`
/// inheriting the global theme rendered brand green on a brand green card, so
/// it read as a smudge. It is now a white pill — the same treatment the captain
/// wallet uses for its payout action.
///
/// **Field names.** `GET /user/wallet` returns raw SQLite column names and the
/// API has no camel-case serializer anywhere in the stack, so the ledger rows
/// arrive as `direction` / `note` / `created_at`. This screen read `type`,
/// `description` and `createdAt`. All three missed: `type` exists but holds
/// `topup` / `trip_payment` / `refund` / … and never `credit`, so every row
/// rendered as a debit with a red outbound arrow; `description` and `createdAt`
/// were always null, so every row showed the generic fallback label above a
/// blank date. The captain wallet reads the correct keys — this screen now
/// matches it, and additionally surfaces `status` and picks a per-`type` icon.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _transactions = [];

  /// Numeric-only pattern deliberately: a pattern with month or day *names*
  /// needs `intl` locale symbol data for the active locale, which throws a
  /// `LocaleDataException` if it was never initialised. Digits and slashes
  /// need nothing beyond the built-in fallback and read the same in Arabic.
  static final DateFormat _stamp = DateFormat('dd/MM/yyyy • HH:mm');

  @override
  void initState() {
    super.initState();
    _fetchWallet();
  }

  Future<void> _fetchWallet() async {
    if (mounted) setState(() => _error = null);
    try {
      final res = await context.read<AppState>().fetchWallet();
      if (!mounted) return;
      setState(() {
        // Defensive shaping: the route returns `List<dynamic>` straight off
        // the D1 result set, so each row is narrowed before it reaches the
        // builders rather than being cast at every read site.
        _transactions = (res['transactions'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // The balance is mirrored on AppState and survives a failed refresh,
        // so only the ledger is genuinely unknown here. Errors used to be
        // swallowed into an empty list, which is indistinguishable from a
        // rider who has simply never transacted.
        _error = e.toString().replaceFirst('Exception:', '').trim();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final balance = context.watch<AppState>().walletBalance ?? 0.0;

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.walletTitle,
          style: AppTokens.font(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: go.text,
          ),
        ),
        backgroundColor: go.panel,
        foregroundColor: go.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: strings.refresh,
            onPressed: _fetchWallet,
          ),
        ],
      ),
      body: _loading
          ? _buildSkeleton()
          : RefreshIndicator(
              onRefresh: _fetchWallet,
              color: go.action,
              backgroundColor: go.panel,
              child: ListView(
                // `always` keeps pull-to-refresh reachable even when the
                // ledger is short enough that the list would not scroll.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                children: [
                  _BalanceCard(
                    balance: balance,
                    onTopUp: _openTopUp,
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
                  if (_error != null)
                    ErrorState(
                      message: _error ?? strings.walletLoadError,
                      onRetry: _fetchWallet,
                    )
                  else if (_transactions.isEmpty)
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: strings.noTransactionsYet,
                      subtitle: strings.transactionsWillAppearHere,
                      actionLabel: strings.topUpTitle,
                      onAction: _openTopUp,
                    )
                  else
                    ..._transactions.map(_buildTransactionRow),
                ],
              ),
            ),
    );
  }

  Future<void> _openTopUp() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TopupScreen()),
    );
    if (mounted) await _fetchWallet();
  }

  /// Shaped placeholder rather than a bare spinner: the skeleton occupies the
  /// same geometry the real content will, so the balance does not jump into
  /// place when the request lands. `SkeletonList` shares one sweep ticker
  /// across its rows and already honours reduce-motion.
  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        SkeletonBox(height: 188, radius: AppTokens.radiusLg),
        const SizedBox(height: AppTokens.spaceXl),
        SkeletonBox(width: 148, height: 20, radius: AppTokens.radiusSm),
        const SizedBox(height: AppTokens.spaceMd),
        SkeletonList(count: 6, itemHeight: 68),
      ],
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    // `direction` is the credit/debit flag — not `type`, which is the
    // accounting bucket (topup, trip_payment, refund, commission, …).
    final isCredit = tx['direction'] == 'credit';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final note = tx['note']?.toString().trim();
    final label = (note == null || note.isEmpty)
        ? (isCredit ? strings.creditNoteFallback : strings.debitNoteFallback)
        : note;
    final pending = tx['status'] == 'pending';
    final stamp = _formatStamp(tx['created_at']?.toString());
    final tone = isCredit ? AppTokens.success : AppTokens.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceXs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: go.border),
      ),
      child: Row(
        children: [
          // Colour carries direction and the glyph carries the reason, so the
          // row still parses for a colour-blind rider.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.withOpacity(go.isDark ? 0.18 : 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(_iconFor(tx['type']?.toString(), isCredit),
                color: tone, size: 20),
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
                    color: go.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  pending ? '$stamp  •  ${strings.pendingMarker}' : stamp,
                  style: AppTokens.font(
                    fontSize: 12,
                    color: pending ? AppTokens.accent : go.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceXs),
          Text(
            // U+2212 minus, not a hyphen — it aligns with the digit stroke
            // weight instead of sitting high and thin next to the numerals.
            '${isCredit ? '+' : '−'} ${_money(amount)} ${strings.egp}',
            style: AppTokens.money(
              fontSize: 16,
              color: tone,
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
  /// trailing zeros; fractional fares keep both places.
  String _money(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  /// Timestamps arrive either as the table default `datetime('now')`
  /// (`YYYY-MM-DD HH:MM:SS`, UTC, no zone marker) or as an ISO string from the
  /// API helper. The bare form has no `Z`, so parsing it directly would tag
  /// UTC wall-clock numbers as local and show an Egyptian rider a time three
  /// hours early. Both shapes are normalised to UTC before converting.
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

  /// The accounting bucket makes the ledger scannable — a rider spots a refund
  /// among trip charges by shape before reading a word of it.
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

/// The balance hero.
///
/// Everything here exists to keep one number legible and one action obvious.
/// The gradient stays in the brand's dark ramp so white never lands on a pale
/// stop; two clipped light pools give the panel some physicality so it reads
/// as a card rather than a coloured rectangle; the wordmark sits where an
/// issuer mark would.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.onTopUp});

  final double balance;
  final VoidCallback onTopUp;

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
                          strings.availableBalance,
                          style: AppTokens.font(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.82),
                          ),
                        ),
                      ),
                      // Two-tone in white keeps the lockup's own hierarchy
                      // without competing with the balance.
                      GoDriveWordmark(
                        fontSize: 13,
                        goColor: Colors.white.withOpacity(0.92),
                        driveColor: Colors.white.withOpacity(0.55),
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
                      onPressed: onTopUp,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      // White on the green card. The previous revision let
                      // this inherit the themed action colour, so it was
                      // brand green sitting on brand green.
                      label: Text(
                        strings.topUpTitle,
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

    // Settling in from 96% reads as the card arriving. Scaling from the
    // flutter_animate default of zero would pop it out of nothing instead.
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

/// Soft light pool used behind the balance card's gradient.
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

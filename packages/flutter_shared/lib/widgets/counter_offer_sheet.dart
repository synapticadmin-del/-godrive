import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Quick price-adjustment picker for a captain's counter-offer.
///
/// The captain is negotiating at a traffic light with one thumb, so the
/// primary path is a row of pre-computed increments — each chip shows the
/// *resulting fare*, not just the delta, because the resulting fare is the
/// number the captain is actually deciding on. The custom field is the
/// escape hatch underneath, not the default input.
///
/// Returns the chosen fare, or null if the captain backed out.
class CounterOfferSheet extends StatefulWidget {
  const CounterOfferSheet({
    super.key,
    required this.offeredPrice,
    this.increments = const [5, 10, 15, 20, 30],
    this.minFare = 1,
    this.maxFare = 10000,
  });

  /// The rider's proposed fare, in EGP.
  final double offeredPrice;

  /// Quick-add amounts offered as chips.
  final List<int> increments;

  /// Server accepts 1..10000 (createBidSchema); mirror it client-side so the
  /// captain gets an inline message instead of a failed request.
  final double minFare;
  final double maxFare;

  /// Presents the sheet and resolves to the chosen fare, or null on dismiss.
  static Future<double?> show(
    BuildContext context, {
    required double offeredPrice,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CounterOfferSheet(offeredPrice: offeredPrice),
    );
  }

  @override
  State<CounterOfferSheet> createState() => _CounterOfferSheetState();
}

class _CounterOfferSheetState extends State<CounterOfferSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: (widget.offeredPrice + 10).toStringAsFixed(0),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(double value) {
    final rounded = double.parse(value.toStringAsFixed(2));
    if (rounded < widget.minFare || rounded > widget.maxFare) {
      setState(() => _error =
          'أدخل مبلغًا بين ${widget.minFare.toStringAsFixed(0)} و ${widget.maxFare.toStringAsFixed(0)} ج.م');
      return;
    }
    HapticFeedback.selectionClick();
    Navigator.pop(context, rounded);
  }

  void _submitCustom() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      setState(() => _error = 'أدخل رقمًا صحيحًا');
      return;
    }
    _submit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: go.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              AppTokens.spaceSm,
              AppTokens.spaceLg,
              AppTokens.spaceLg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: go.border,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'إرسال سعر معدل للعميل',
                        style: AppTokens.font(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: go.text,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'إغلاق',
                      icon: Icon(Icons.close_rounded, color: go.muted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppTokens.spaceXs),

                // Anchor: what the rider actually offered.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceSm,
                    vertical: AppTokens.spaceSm,
                  ),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    border: Border.all(color: AppTokens.primary.withOpacity(0.28)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'السعر المعروض من العميل',
                          style: AppTokens.font(fontSize: 13, color: go.muted),
                        ),
                      ),
                      Text(
                        '${widget.offeredPrice.toStringAsFixed(0)} ج.م',
                        style: AppTokens.money(
                          fontSize: 18,
                          color: AppTokens.primary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  'اختر زيادة سريعة',
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXs),

                Wrap(
                  spacing: AppTokens.spaceXs,
                  runSpacing: AppTokens.spaceXs,
                  children: widget.increments.map((inc) {
                    final total = widget.offeredPrice + inc;
                    return _IncrementChip(
                      delta: inc,
                      total: total,
                      onTap: () => _submit(total),
                    );
                  }).toList(),
                ),

                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  'أو أدخل مبلغًا مخصصًا',
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceXs),

                TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _submitCustom(),
                  style: AppTokens.money(fontSize: 20, color: go.text),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: go.surface,
                    suffixText: 'ج.م',
                    suffixStyle: AppTokens.font(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: go.muted,
                    ),
                    errorText: _error,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMd,
                      vertical: AppTokens.spaceSm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      borderSide: BorderSide(color: go.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      borderSide: BorderSide(color: go.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      borderSide: const BorderSide(
                        color: AppTokens.primary,
                        width: 1.6,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppTokens.spaceMd),
                SizedBox(
                  height: AppTokens.primaryActionHeight,
                  child: ElevatedButton.icon(
                    onPressed: _submitCustom,
                    icon: const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      'إرسال العرض',
                      style: AppTokens.font(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: go.onAction,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: go.action,
                      foregroundColor: go.onAction,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IncrementChip extends StatelessWidget {
  const _IncrementChip({
    required this.delta,
    required this.total,
    required this.onTap,
  });

  final int delta;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return Material(
      color: AppTokens.primary.withOpacity(0.10),
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppTokens.tapTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceSm,
            vertical: AppTokens.spaceXs,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
            border: Border.all(color: AppTokens.primary.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '+$delta',
                style: AppTokens.font(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: go.muted,
                ),
              ),
              Text(
                total.toStringAsFixed(0),
                style: AppTokens.money(fontSize: 17, color: AppTokens.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

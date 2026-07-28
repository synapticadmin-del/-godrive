import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

/// Promo codes screen — list active promos + enter a new code.
class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});
  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> {
  final _codeController = TextEditingController();
  List<Map<String, dynamic>> _promos = [];
  bool _loading = true;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final state = context.read<AppState>();
      final res = await state.apiGet('/promos');
      _promos = (res['promos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _applyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _applying = true);
    try {
      final state = context.read<AppState>();
      final res = await state.apiPost('/promos/validate', {'code': code});
      if (mounted) {
        final discount = (res['discount'] as num?)?.toDouble() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.of(context).promoAppliedToast('$discount'),
            ),
            backgroundColor: AppTokens.success,
          ),
        );
        _codeController.clear();
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).promoInvalidToast),
            backgroundColor: AppTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.promoTitle,
          style: AppTokens.font(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // Enter code
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: InputDecoration(
                    hintText: strings.promoCodeHint,
                    hintStyle: AppTokens.font(color: go.muted, fontSize: 14),
                    filled: true,
                    fillColor: go.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.local_offer,
                        color: AppTokens.primary, size: 20),
                  ),
                  style: AppTokens.font(color: go.text, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _applying ? null : _applyCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _applying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(strings.promoApplyAction),
                ),
              ),
            ]),
          ),
          // Active promos list
          Expanded(
            child: _loading
                ? const SkeletonList(count: 3)
                : _promos.isEmpty
                    ? EmptyState(
                        icon: Icons.local_offer_outlined,
                        title: strings.promoEmptyTitle,
                        subtitle: strings.promoEmptySubtitle,
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _promos.length,
                        itemBuilder: (_, i) {
                          final p = _promos[i];
                          final type = p['type'] as String? ?? 'percent';
                          final value = (p['value'] as num?)?.toDouble() ?? 0;
                          final code = p['code'] as String? ?? '';
                          final expires =
                              (p['expires_at'] ?? '').toString().substring(0, 10);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: go.panel,
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusLg),
                              border: Border.all(color: go.border),
                            ),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTokens.primary.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(AppTokens.radiusMd),
                                ),
                                child: const Icon(Icons.local_offer,
                                    color: AppTokens.primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      code,
                                      style: AppTokens.font(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: go.text,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      type == 'percent'
                                          ? strings.promoDiscountPercent(
                                              value.toInt())
                                          : strings.promoDiscountFixed(
                                              '${value.toInt()}'),
                                      style: AppTokens.font(
                                        fontSize: 13,
                                        color: AppTokens.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (expires.isNotEmpty)
                                      Text(
                                        strings.promoExpiresLine(expires),
                                        style: AppTokens.font(
                                          fontSize: 11,
                                          color: go.muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ]),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

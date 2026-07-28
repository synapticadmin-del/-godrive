import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

/// Bottom sheet shown after a trip completes — lets the rider rate the captain
/// (1–5 stars), leave a comment, and optionally add a tip.
class RatingSheet extends StatefulWidget {
  final String tripId;
  final String captainName;
  final VoidCallback onDone;

  const RatingSheet({
    super.key,
    required this.tripId,
    required this.captainName,
    required this.onDone,
  });

  @override
  State<RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<RatingSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  Future<void> _submit() async {
    if (_rating == 0) return;
    setState(() => _submitting = true);
    try {
      final state = context.read<AppState>();
      await state.rateTrip(widget.tripId, _rating);
      if (mounted) {
        widget.onDone();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.of(context).ratingErrorPrefix('$e')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Container(
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: go.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            // Title
            Text(
              strings.ratingTitle,
              style: AppTokens.font(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: go.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.ratingCaptainLine(widget.captainName),
              style: AppTokens.font(fontSize: 14, color: go.muted),
            ),
            const SizedBox(height: 24),
            // Stars
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = star),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      star <= _rating ? Icons.star : Icons.star_border,
                      size: 44,
                      color: star <= _rating
                          ? AppTokens.accent
                          : go.muted.withOpacity(0.4),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            // Quick tags
            if (_rating > 0) ...[
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _tag(strings.ratingTagSafeDriving),
                  _tag(strings.ratingTagPoliteCaptain),
                  _tag(strings.ratingTagCleanCar),
                  _tag(strings.ratingTagOnTime),
                  _tag(strings.ratingTagComfortableMusic),
                ],
              ),
              const SizedBox(height: 16),
            ],
            // Comment
            TextField(
              controller: _commentController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: strings.ratingCommentHint,
                hintStyle: AppTokens.font(color: go.muted, fontSize: 14),
                filled: true,
                fillColor: go.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  borderSide: BorderSide.none,
                ),
              ),
              style: AppTokens.font(color: go.text, fontSize: 14),
            ),
            const SizedBox(height: 20),
            // Submit
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting || _rating == 0 ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppTokens.primary.withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        strings.ratingSubmitAction,
                        style: AppTokens.font(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                strings.ratingSkipAction,
                style: AppTokens.font(color: go.muted, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTokens.primary.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: AppTokens.font(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTokens.primary,
        ),
      ),
    );
  }
}

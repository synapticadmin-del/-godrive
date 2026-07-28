import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:provider/provider.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

import 'document_upload_screen.dart';

/// Read-through status view for a captain's onboarding documents.
///
/// Where [DocumentUploadScreen] is the checklist a captain acts on, this screen
/// answers a narrower question at a glance: where does my application stand,
/// and — if something was rejected — exactly why? It reads the same
/// `GET /captain/documents` payload, whose rows carry the per-document
/// `rejection_reason` an admin wrote (migration 0008), and pairs every rejected
/// document with a direct "إعادة الرفع" (re-upload) action back to the uploader.
class DocumentStatusScreen extends StatefulWidget {
  const DocumentStatusScreen({super.key});

  @override
  State<DocumentStatusScreen> createState() => _DocumentStatusScreenState();
}

class _DocumentStatusScreenState extends State<DocumentStatusScreen> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;

  static const _docTypes = [
    {'type': 'license', 'title': 'رخصة القيادة', 'icon': Icons.card_membership_rounded},
    {'type': 'national_id', 'title': 'البطاقة الشخصية', 'icon': Icons.badge_rounded},
    {'type': 'vehicle_reg', 'title': 'رخصة السيارة', 'icon': Icons.directions_car_rounded},
    {'type': 'criminal_record', 'title': 'فيش جنائي', 'icon': Icons.fact_check_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<CaptainState>();
    try {
      final res = await state.apiGet('/captain/documents');
      if (!mounted) return;
      setState(() {
        _docs = (res['documents'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
    // Keep the account-level approval state fresh too; a failure here is
    // non-fatal and must not blank the documents we already have.
    try {
      await state.refreshMe();
    } catch (_) {}
  }

  String _docStatus(String type) {
    final match = _docs.where((d) => d['type'] == type);
    if (match.isEmpty) return 'missing';
    return match.first['status'] as String? ?? 'missing';
  }

  /// The admin's rejection note for [type], read from the `rejection_reason`
  /// column returned per document by `GET /captain/documents`. Null when the
  /// document was not rejected or the admin left the note blank.
  String? _rejectionReason(String type) {
    final match = _docs.where((d) => d['type'] == type);
    if (match.isEmpty) return null;
    final reason = match.first['rejection_reason']?.toString().trim() ?? '';
    return reason.isEmpty ? null : reason;
  }

  List<Map<String, dynamic>> get _rejectedDocs => _docTypes
      .where((d) => _docStatus(d['type'] as String) == 'rejected')
      .toList();

  /// Send the captain to the uploader to fix a document. When this screen was
  /// pushed from the uploader, popping returns to it; otherwise open it fresh.
  void _goReupload() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.push(
        MaterialPageRoute(builder: (_) => const DocumentUploadScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final state = context.watch<CaptainState>();
    final go = GoTheme.of(context);

    final approval =
        (state.captain?['approval_status'] ?? state.captain?['status'])?.toString();

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.documentsStatusTooltip,
          style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: go.text),
        ),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: strings.refresh,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading
                ? null
                : () {
                    setState(() => _loading = true);
                    _load();
                  },
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(AppTokens.spaceMd),
              child: SkeletonList(count: 4),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTokens.primary,
              child: ListView(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                children: [
                  _buildAccountBanner(approval, go.text, go.muted, strings),
                  if (_rejectedDocs.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    _buildRejectionAlert(go.text, go.muted, strings),
                  ],
                  const SizedBox(height: AppTokens.spaceMd),
                  ..._docTypes.map((d) => _buildStatusRow(
                        d['type'] as String,
                        d['title'] as String,
                        d['icon'] as IconData,
                        go,
                        strings,
                      )),
                ],
              ),
            ),
    );
  }

  /// Where the whole application stands — the one line a captain opens this
  /// screen to see.
  Widget _buildAccountBanner(String? approval, Color text, Color muted, AppStrings strings) {
    final Color tone;
    final Color toneBg;
    final IconData icon;
    final String title;
    final String subtitle;
    switch (approval) {
      case 'approved':
        tone = AppTokens.success;
        toneBg = AppTokens.badgeApprovedBg;
        icon = Icons.verified_rounded;
        title = strings.accountApprovedTitle;
        subtitle = strings.accountApprovedSubtitle;
      case 'rejected':
        tone = AppTokens.danger;
        toneBg = AppTokens.badgeStoppedBg;
        icon = Icons.gpp_bad_rounded;
        title = strings.accountRejectedTitle;
        subtitle = strings.accountRejectedSubtitle;
      default:
        tone = AppTokens.warning;
        toneBg = AppTokens.badgePendingBg;
        icon = Icons.hourglass_top_rounded;
        title = strings.accountUnderReviewTitle;
        subtitle = strings.accountUnderReviewSubtitle;
    }

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: toneBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: tone.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 26),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTokens.font(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTokens.font(fontSize: 12.5, color: muted, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Aggregate rejection summary with the exact admin reason per document and a
  /// single, unmissable path back to re-uploading.
  Widget _buildRejectionAlert(Color text, Color muted, AppStrings strings) {
    final rejected = _rejectedDocs;
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: AppTokens.badgeStoppedBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.danger.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_rounded, color: AppTokens.danger, size: 22),
              const SizedBox(width: AppTokens.spaceXs),
              Expanded(
                child: Text(
                  rejected.length == 1
                      ? strings.docRejectedTitleSingle
                      : strings.docRejectedTitleCount(rejected.length),
                  style: AppTokens.font(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.badgeStoppedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          ...rejected.map((d) {
            final type = d['type'] as String;
            final title = d['title'] as String;
            final reason = _rejectionReason(type);
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTokens.font(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reason ?? strings.docNoReasonFallback,
                    style: AppTokens.font(
                      fontSize: 12.5,
                      color: AppTokens.badgeStoppedText,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: AppTokens.spaceXs),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _goReupload,
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: Text(
                strings.docReuploadAction,
                style: AppTokens.font(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.danger,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(AppTokens.tapTarget),
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

  Widget _buildStatusRow(
    String type,
    String title,
    IconData icon,
    GoTheme go,
    AppStrings strings,
  ) {
    final status = _docStatus(type);

    final Color badgeText;
    final Color badgeBg;
    final String statusLabel;
    final IconData statusIcon;
    final Color cardBorder;
    switch (status) {
      case 'approved':
        badgeText = AppTokens.badgeApprovedText;
        badgeBg = AppTokens.badgeApprovedBg;
        statusLabel = strings.docStatusApproved;
        statusIcon = Icons.check_circle_rounded;
        cardBorder = AppTokens.success.withOpacity(0.25);
      case 'pending':
        badgeText = AppTokens.badgePendingText;
        badgeBg = AppTokens.badgePendingBg;
        statusLabel = strings.docStatusPending;
        statusIcon = Icons.hourglass_top_rounded;
        cardBorder = go.border;
      case 'rejected':
        badgeText = AppTokens.badgeStoppedText;
        badgeBg = AppTokens.badgeStoppedBg;
        statusLabel = strings.docStatusRejected;
        statusIcon = Icons.error_rounded;
        cardBorder = AppTokens.danger.withOpacity(0.3);
      default:
        badgeText = go.muted;
        badgeBg = go.surface;
        statusLabel = strings.docStatusMissing;
        statusIcon = Icons.cloud_upload_rounded;
        cardBorder = go.border;
    }

    final reason = _rejectionReason(type);
    final needsUpload = status == 'missing' || status == 'rejected';

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: cardBorder),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: AppTokens.tapTarget,
                height: AppTokens.tapTarget,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                ),
                child: Icon(icon, color: badgeText, size: 22),
              ),
              const SizedBox(width: AppTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTokens.font(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space2xs),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 12, color: badgeText),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: AppTokens.font(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: badgeText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (needsUpload)
                Padding(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppTokens.spaceSm),
                  child: TextButton.icon(
                    onPressed: _goReupload,
                    icon: Icon(
                      Icons.upload_rounded,
                      size: 16,
                      color: status == 'rejected'
                          ? AppTokens.danger
                          : AppTokens.primary,
                    ),
                    label: Text(
                      status == 'rejected' ? strings.docReuploadAction : strings.docUploadAction,
                      style: AppTokens.font(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: status == 'rejected'
                            ? AppTokens.danger
                            : AppTokens.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // The exact admin reason, boxed under the rejected document it
          // belongs to so there is no ambiguity about which one to fix.
          if (status == 'rejected') ...[
            const SizedBox(height: AppTokens.spaceSm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTokens.spaceSm),
              decoration: BoxDecoration(
                color: AppTokens.badgeStoppedBg,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppTokens.danger),
                  const SizedBox(width: AppTokens.spaceXs),
                  Expanded(
                    child: Text(
                      reason ?? strings.docNoReasonFallback,
                      style: AppTokens.font(
                        fontSize: 12.5,
                        color: AppTokens.badgeStoppedText,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

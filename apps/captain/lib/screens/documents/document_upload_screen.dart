import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'document_status_screen.dart';

/// Document checklist — the first screen an unapproved captain lands on.
///
/// The previous design used a bare info banner and a list of cards with no
/// sense of overall progress. A captain reading it for the first time had no
/// idea how many items they still needed or what would happen when they
/// finished. This redesign gives them:
///
///  1. A warm header that names the captain and explains exactly what's
///     happening (documents under review → approval → access to the map).
///  2. A progress bar that turns green as documents are approved, giving a
///     clear sense of momentum.
///  3. Per-document cards that use the design-system badge color pairs so
///     status (pending / approved / rejected) reads at a glance.
///  4. A clear "رفع" action only where it's needed (missing / rejected).
///
/// All upload logic, API calls, and image-picker usage are preserved exactly.
class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  Set<String> _uploading = {};

  static const _docTypes = [
    {'type': 'license', 'title': 'رخصة القيادة', 'icon': Icons.card_membership_rounded},
    {'type': 'national_id', 'title': 'البطاقة الشخصية', 'icon': Icons.badge_rounded},
    {'type': 'vehicle_reg', 'title': 'رخصة السيارة', 'icon': Icons.directions_car_rounded},
    {'type': 'criminal_record', 'title': 'فيش جنائي', 'icon': Icons.fact_check_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    try {
      final state = context.read<CaptainState>();
      final res = await state.apiGet('/captain/documents');
      // Guard against leaving the screen while the request is in flight.
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
  }

  String _docStatus(String type) {
    final match = _docs.where((d) => d['type'] == type);
    if (match.isEmpty) return 'missing';
    return match.first['status'] as String? ?? 'missing';
  }

  int get _approvedCount =>
      _docTypes.where((d) => _docStatus(d['type'] as String) == 'approved').length;

  /// The admin's rejection note for [type], read from the `rejection_reason`
  /// column that `GET /captain/documents` returns per document (added in
  /// migration 0008). Returns null when the document was not rejected or the
  /// admin left the note blank.
  String? _rejectionReason(String type) {
    final match = _docs.where((d) => d['type'] == type);
    if (match.isEmpty) return null;
    final reason = match.first['rejection_reason']?.toString().trim() ?? '';
    return reason.isEmpty ? null : reason;
  }

  /// Every document an admin has rejected, in checklist order, so the captain
  /// can be pointed straight at what needs re-uploading.
  List<Map<String, dynamic>> get _rejectedDocs => _docTypes
      .where((d) => _docStatus(d['type'] as String) == 'rejected')
      .toList();

  Future<void> _upload(String docType, String title) async {
    // Offer gallery alongside camera — camera-only forces captains to re-shoot
    // documents they already have photographed on their phone.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final go = GoTheme.of(sheetCtx);
        return Container(
          decoration: BoxDecoration(
            color: go.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusXl),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sheet handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: go.border,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                ),
                ListTile(
                  leading: Container(
                    width: AppTokens.tapTarget,
                    height: AppTokens.tapTarget,
                    decoration: BoxDecoration(
                      color: AppTokens.primarySoft,
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: AppTokens.primary),
                  ),
                  title: Text(
                    'التقاط صورة',
                    style: AppTokens.font(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
                ),
                ListTile(
                  leading: Container(
                    width: AppTokens.tapTarget,
                    height: AppTokens.tapTarget,
                    decoration: BoxDecoration(
                      color: AppTokens.accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: AppTokens.accent),
                  ),
                  title: Text(
                    'اختيار من المعرض',
                    style: AppTokens.font(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
                ),
                const SizedBox(height: AppTokens.spaceMd),
              ],
            ),
          ),
        );
      },
    );
    if (source == null || !mounted) return;

    final XFile? image = await _picker.pickImage(source: source, imageQuality: 75);
    if (image == null || !mounted) return;

    setState(() => _uploading.add(docType));

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Step 1: upload the file to R2. The endpoint expects multipart/form-data
      // with the file under the field name `file` and responds
      // {ok, r2Key, url}.
      final uploadReq = http.MultipartRequest(
        'POST',
        Uri.parse('${state.baseUrl}/captain/upload'),
      );
      uploadReq.headers['Authorization'] = 'Bearer ${state.token}';
      uploadReq.files.add(await http.MultipartFile.fromPath('file', image.path));

      final uploadRes = await uploadReq.send();
      final uploadBody = await uploadRes.stream.bytesToString();

      if (uploadRes.statusCode >= 300) {
        // Surface the server's reason (FILE_TOO_LARGE, MISSING_FILE, …) instead
        // of a blanket failure message.
        String reason = 'فشل رفع الملف';
        try {
          final err = jsonDecode(uploadBody);
          if (err is Map && err['error'] != null) reason = err['error'].toString();
        } catch (_) {}
        throw Exception(reason);
      }

      // The response is plain JSON — decode it as such rather than scraping
      // with a regex, which throws on any stray '%' in the body.
      final decoded = jsonDecode(uploadBody);
      final r2Key = decoded is Map ? decoded['r2Key'] as String? : null;
      if (r2Key == null || r2Key.isEmpty) {
        throw Exception('استجابة الرفع غير صالحة');
      }

      // Step 2: register document in DB
      await state.apiPost('/captain/documents', {'type': docType, 'r2Key': r2Key});

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم رفع $title بنجاح — قيد المراجعة'),
          backgroundColor: AppTokens.success,
        ),
      );
      await _loadDocs();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString().replaceAll('Exception:', '').trim()}'),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading.remove(docType));
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          'المستندات المطلوبة',
          style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: go.text),
        ),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        actions: [
          // A read-through status view: every document, its review state, and
          // the admin's exact rejection reason in one place.
          IconButton(
            tooltip: 'حالة المستندات',
            icon: const Icon(Icons.assignment_turned_in_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DocumentStatusScreen()),
              );
            },
          ),
          // MainShell shows this screen full-screen while the captain is
          // unapproved — these actions are their only escape hatches.
          IconButton(
            tooltip: 'تحديث حالة الحساب',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              final state = context.read<CaptainState>();
              await _loadDocs();
              try {
                await state.refreshMe();
              } catch (_) {}
            },
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<CaptainState>().logout(),
          ),
        ],
      ),
      body: _loading
          ? const SkeletonList(count: 4)
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(go),
                ),
                // Rejection feedback, front and centre: the exact reason the
                // admin gave for every rejected document, right above the
                // checklist so the fix is the next thing the captain does.
                if (_rejectedDocs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildRejectionAlert(go.text, go.muted),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.spaceMd,
                    0,
                    AppTokens.spaceMd,
                    AppTokens.spaceMd,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final d = _docTypes[i];
                        return _buildDocCard(
                          d['type'] as String,
                          d['title'] as String,
                          d['icon'] as IconData,
                          go,
                        );
                      },
                      childCount: _docTypes.length,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Prominent alert summarising every rejected document and the exact reason
  /// the admin supplied, with a clear instruction to re-upload. Uses the design
  /// system's "stopped"/danger pair so it reads as an action item, not decor.
  Widget _buildRejectionAlert(Color text, Color muted) {
    final rejected = _rejectedDocs;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        0,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
      ),
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
                      ? 'مستند مرفوض — يلزم إعادة رفعه'
                      : 'بعض المستندات مرفوضة — يلزم إعادة رفعها',
                  style: AppTokens.font(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTokens.badgeStoppedText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            'راجع سبب الرفض بجانب كل مستند بالأسفل ثم اضغط "إعادة الرفع".',
            style: AppTokens.font(fontSize: 12.5, color: muted, height: 1.5),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsetsDirectional.only(top: 2),
                        child: Icon(Icons.chevron_left_rounded,
                            size: 18, color: AppTokens.danger),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: AppTokens.font(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: text,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 18, top: 2),
                    child: Text(
                      reason ??
                          'لم يذكر المشرف سبباً محدداً — يرجى رفع صورة أوضح وسليمة.',
                      style: AppTokens.font(
                        fontSize: 12.5,
                        color: AppTokens.badgeStoppedText,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeader(GoTheme go) {
    final total = _docTypes.length;
    final approved = _approvedCount;
    final progress = total == 0 ? 0.0 : approved / total;
    final allDone = approved == total;

    return Container(
      color: go.panel,
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
        AppTokens.spaceLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Onboarding illustration — a simple branded circle keeps it light
          // without requiring a bundled asset that could go stale.
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppTokens.primarySoft,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: AppTokens.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: AppTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allDone ? 'مستنداتك قيد المراجعة' : 'أكمل ملفك المهني',
                      style: AppTokens.font(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allDone
                          ? 'سيتواصل معك فريقنا خلال 24 ساعة عند إقرار الحساب.'
                          : 'ارفع مستنداتك ليتمكن فريقنا من مراجعة حسابك والموافقة عليه.',
                      style: AppTokens.font(
                        fontSize: 13,
                        color: go.muted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          // Progress bar — shows momentum; turns fully green when every
          // document has been uploaded (not necessarily approved yet, but the
          // captain can see they've done their part).
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    // Track colour follows the themed border passed into the
                    // header rather than a fixed light grey, so the unfilled
                    // portion of the bar stays visible on the dark canvas.
                    backgroundColor: go.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      allDone ? AppTokens.success : AppTokens.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                '$approved / $total',
                style: AppTokens.font(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: allDone ? AppTokens.success : AppTokens.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            allDone ? 'جميع المستندات مرفوعة' : 'تمت الموافقة على $approved من أصل $total مستندات',
            style: AppTokens.font(fontSize: 12, color: go.muted),
          ),
          // The three steps ahead — understanding what happens next is what
          // turns a form dump into an onboarding experience.
          const SizedBox(height: AppTokens.spaceLg),
          _buildStepRow(
            icon: Icons.upload_file_rounded,
            label: 'ارفع مستنداتك',
            done: approved > 0,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildStepRow(
            icon: Icons.manage_search_rounded,
            label: 'مراجعة الفريق (حتى 24 ساعة)',
            done: allDone,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildStepRow(
            icon: Icons.directions_car_rounded,
            label: 'ابدأ قبول الرحلات',
            done: false,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({required IconData icon, required String label, required bool done}) {
    // A not-yet-done step is drawn in the faint/muted greys. Those were pinned
    // to the light-theme values, so on the dark onboarding canvas the pending
    // steps washed out. Resolve the pending greys against the active theme.
    final go = GoTheme.of(context);
    final pendingIcon = go.isDark ? AppTokens.darkFaint : AppTokens.lightFaint;
    final pendingText = go.muted;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : icon,
          size: 18,
          color: done ? AppTokens.success : pendingIcon,
        ),
        const SizedBox(width: AppTokens.spaceXs),
        Text(
          label,
          style: AppTokens.font(
            fontSize: 13,
            fontWeight: done ? FontWeight.w600 : FontWeight.w400,
            color: done ? AppTokens.success : pendingText,
          ),
        ),
      ],
    );
  }

  Widget _buildDocCard(
    String type,
    String title,
    IconData icon,
    GoTheme go,
  ) {
    final status = _docStatus(type);
    final isUploading = _uploading.contains(type);

    // Badge colors come straight from the design system's badge pairs, which
    // guarantee WCAG contrast on their respective background tints.
    final Color badgeText;
    final Color badgeBg;
    final String statusLabel;
    final IconData statusIcon;
    final Color cardBorder;

    switch (status) {
      case 'approved':
        badgeText = AppTokens.badgeApprovedText;
        badgeBg = AppTokens.badgeApprovedBg;
        statusLabel = 'مقبول';
        statusIcon = Icons.check_circle_rounded;
        cardBorder = AppTokens.success.withOpacity(0.25);
      case 'pending':
        badgeText = AppTokens.badgePendingText;
        badgeBg = AppTokens.badgePendingBg;
        statusLabel = 'قيد المراجعة';
        statusIcon = Icons.hourglass_top_rounded;
        cardBorder = go.border;
      case 'rejected':
        badgeText = AppTokens.badgeStoppedText;
        badgeBg = AppTokens.badgeStoppedBg;
        statusLabel = 'مرفوض — أعد الرفع';
        statusIcon = Icons.error_rounded;
        cardBorder = AppTokens.danger.withOpacity(0.3);
      default:
        badgeText = go.muted;
        // The "not uploaded yet" badge uses a neutral surface tint; pinning it
        // to lightSurface left a pale square on the dark card, so track the
        // active theme like the approved/pending/rejected badges do.
        badgeBg = go.surface;
        statusLabel = 'لم يتم الرفع بعد';
        statusIcon = Icons.cloud_upload_rounded;
        cardBorder = go.border;
    }

    final needsUpload = status == 'missing' || status == 'rejected';

    return Container(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: cardBorder),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Document-type icon in a tinted badge-colored square
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
                  // Status badge — inline pill matching the design system tokens
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUploading)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: AppTokens.primary,
                            ),
                          )
                        else
                          Icon(statusIcon, size: 12, color: badgeText),
                        const SizedBox(width: 4),
                        Text(
                          isUploading ? 'جاري الرفع...' : statusLabel,
                          style: AppTokens.font(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: badgeText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The specific reason this document was rejected, inline on
                  // the card so the captain fixing it never has to guess.
                  if (status == 'rejected') ...[
                    const SizedBox(height: AppTokens.space2xs),
                    Text(
                      _rejectionReason(type) ??
                          'لم يذكر المشرف سبباً محدداً — يرجى رفع صورة أوضح وسليمة.',
                      style: AppTokens.font(
                        fontSize: 12,
                        color: AppTokens.badgeStoppedText,
                        height: 1.45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (needsUpload) ...[
              const SizedBox(width: AppTokens.spaceSm),
              SizedBox(
                height: AppTokens.tapTarget,
                child: ElevatedButton.icon(
                  onPressed: isUploading ? null : () => _upload(type, title),
                  icon: const Icon(Icons.camera_alt_rounded, size: 17),
                  label: Text(
                    status == 'rejected' ? 'إعادة الرفع' : 'رفع',
                    style: AppTokens.font(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: status == 'rejected' ? AppTokens.danger : AppTokens.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    minimumSize: Size.zero,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ).animate().slideX(begin: 0.06, duration: 280.ms, curve: Curves.easeOut);
  }
}

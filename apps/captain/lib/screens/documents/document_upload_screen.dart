import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_animate/flutter_animate.dart';

/// Document upload screen — picks an image, uploads to R2 via /captain/upload,
/// then registers the document via /captain/documents.
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

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    try {
      final state = context.read<CaptainState>();
      final res = await state.apiGet('/captain/documents');
      setState(() {
        _docs = (res['documents'] as List?)?.cast<Map<String, dynamic>>() ?? [];
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

  Future<void> _upload(String docType, String title) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 75);
    if (image == null) return;

    setState(() => _uploading.add(docType));

    try {
      final state = context.read<CaptainState>();

      // Step 1: upload file to R2
      final uploadReq = http.MultipartRequest('POST', Uri.parse('${state.baseUrl}/captain/upload'));
      uploadReq.headers['Authorization'] = 'Bearer ${state.token}';
      uploadReq.files.add(await http.MultipartFile.fromPath('file', image.path));
      final uploadRes = await uploadReq.send();
      if (uploadRes.statusCode >= 300) throw Exception('فشل رفع الملف');

      final uploadBody = await uploadRes.stream.bytesToString();
      final uploadData = Uri.decodeComponent(uploadBody);
      // Extract r2Key from JSON response
      final r2KeyMatch = RegExp(r'"r2Key"\s*:\s*"([^"]+)"').firstMatch(uploadData);
      final r2Key = r2KeyMatch?.group(1);
      if (r2Key == null) throw Exception('استجابة الرفع غير صالحة');

      // Step 2: register document in DB
      await state.apiPost('/captain/documents', {'type': docType, 'r2Key': r2Key});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم رفع $title بنجاح — قيد المراجعة'), backgroundColor: AppTokens.success),
        );
      }
      await _loadDocs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTokens.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(docType));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.lightBg : AppTokens.lightBg;
    final panel = isDark ? AppTokens.lightPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.lightText : AppTokens.lightText;
    final muted = isDark ? AppTokens.lightMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.lightBorder : AppTokens.lightBorder;

    final docTypes = [
      {'type': 'license', 'title': 'رخصة القيادة', 'icon': Icons.card_membership},
      {'type': 'national_id', 'title': 'البطاقة الشخصية', 'icon': Icons.badge},
      {'type': 'vehicle_reg', 'title': 'رخصة السيارة', 'icon': Icons.directions_car},
      {'type': 'criminal_record', 'title': 'فيش جنائي', 'icon': Icons.fact_check},
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text('المستندات', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700)),
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const SkeletonList(count: 4)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    border: Border.all(color: AppTokens.primary.withOpacity(0.2)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: AppTokens.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(
                      'ارفع مستنداتك بصورة واضحة. سيتم تفعيل حسابك بعد مراجعتها.',
                      style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: AppTokens.primary),
                    )),
                  ]),
                ),
                const SizedBox(height: 20),
                // Doc cards
                ...docTypes.map((d) => _buildDocCard(
                  d['type'] as String, d['title'] as String, d['icon'] as IconData,
                  panel, text, muted, border,
                )),
              ],
            ),
    );
  }

  Widget _buildDocCard(
    String type, String title, IconData icon,
    Color panel, Color text, Color muted, Color border,
  ) {
    final status = _docStatus(type);
    final isUploading = _uploading.contains(type);

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (status) {
      case 'approved':
        statusColor = AppTokens.success; statusText = 'مقبول'; statusIcon = Icons.check_circle;
      case 'pending':
        statusColor = AppTokens.accent; statusText = 'قيد المراجعة'; statusIcon = Icons.hourglass_empty;
      case 'rejected':
        statusColor = AppTokens.danger; statusText = 'مرفوض — أعد الرفع'; statusIcon = Icons.error;
      default:
        statusColor = muted; statusText = 'لم يتم الرفع'; statusIcon = Icons.cloud_upload;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: status == 'approved' ? AppTokens.success.withOpacity(0.3) : border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
          child: Icon(icon, color: statusColor, size: 24),
        ),
        title: Text(title, style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w700, color: text, fontSize: 15)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            if (isUploading)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTokens.primary))
            else
              Icon(statusIcon, color: statusColor, size: 14),
            const SizedBox(width: 4),
            Text(isUploading ? 'جاري الرفع...' : statusText,
              style: GoogleFonts.ibmPlexSansArabic(color: statusColor, fontSize: 12)),
          ]),
        ),
        trailing: (status == 'missing' || status == 'rejected')
            ? ElevatedButton.icon(
                onPressed: isUploading ? null : () => _upload(type, title),
                icon: const Icon(Icons.camera_alt, size: 18),
                label: const Text('رفع'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.primary, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              )
            : null,
      ).animate().slideX(begin: 0.1),
    );
  }
}
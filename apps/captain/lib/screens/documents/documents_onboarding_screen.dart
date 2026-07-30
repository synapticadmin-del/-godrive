import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';

/// Documents step of the captain onboarding, redesigned after the product
/// mock-ups: a grid of dark, rounded upload tiles (like the screenshots)
/// instead of a vertical card list.
///
/// The set of tiles is NOT hard-coded. It comes from GET
/// /captain/document-types, which the admin team manages from the dashboard —
/// adding a new required document (e.g. car insurance) is a dashboard action,
/// not an app release. Each tile:
///
///  * shows a big "+" on a dark rounded square when empty,
///  * swaps to the picked photo with a small "×" remove button when filled,
///  * carries an "اختياري" badge when the type is optional in the catalog,
///  * uploads straight to R2 + registers the document the moment a photo is
///    picked, so state survives app restarts.
///
/// The bottom bar mirrors the onboarding mocks: a lime "التالي" button, a
/// back chevron, and a progress indicator. It validates that every required
/// type has at least one upload before moving on.
class DocumentsOnboardingScreen extends StatefulWidget {
  /// Called when the captain taps "التالي" with all required uploads done.
  final VoidCallback? onNext;

  /// Called when the captain taps the back chevron (step 1 → earlier step).
  final VoidCallback? onBack;

  /// Step indicator, e.g. 3 of 4 — rendered as "3 من 4" in the footer.
  final int step;
  final int totalSteps;

  /// Title for the step, defaults to the localized "المستندات الشخصية".
  final String? title;

  /// Optional extra fields rendered under the grid (e.g. رقم الهوية input).
  final List<Widget> extraFields;

  const DocumentsOnboardingScreen({
    super.key,
    this.onNext,
    this.onBack,
    this.step = 3,
    this.totalSteps = 4,
    this.title,
    this.extraFields = const [],
  });

  @override
  State<DocumentsOnboardingScreen> createState() =>
      _DocumentsOnboardingScreenState();
}

class _DocType {
  final String id;
  final String titleAr;
  final String titleEn;
  final bool required;

  const _DocType({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.required,
  });

  factory _DocType.fromJson(Map<String, dynamic> j) => _DocType(
        id: j['id']?.toString() ?? '',
        titleAr: j['title_ar']?.toString() ?? '',
        titleEn: j['title_en']?.toString() ?? '',
        required: (j['required'] as num? ?? 1) == 1,
      );
}

class _DocumentsOnboardingScreenState extends State<DocumentsOnboardingScreen> {
  final ImagePicker _picker = ImagePicker();

  List<_DocType> _types = [];
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _loadFailed = false;
  final Set<String> _uploading = {};
  final Map<String, File> _localPreviews = {};

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final state = context.read<CaptainState>();
    try {
      final results = await Future.wait([
        state.apiGet('/captain/document-types'),
        state.apiGet('/captain/documents'),
      ]);
      if (!mounted) return;

      final typesRaw = (results[0]['types'] as List?) ?? const [];
      var types = typesRaw
          .whereType<Map>()
          .map((e) => _DocType.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();

      // Older backends (pre-catalog) have no document-types endpoint content —
      // fall back to the four classic types so the screen never renders empty.
      if (types.isEmpty) {
        types = const [
          _DocType(id: 'license', titleAr: 'رخصة القيادة', titleEn: 'Driving license', required: true),
          _DocType(id: 'national_id', titleAr: 'البطاقة الشخصية', titleEn: 'National ID card', required: true),
          _DocType(id: 'vehicle_reg', titleAr: 'رخصة السيارة', titleEn: 'Vehicle registration', required: true),
          _DocType(id: 'criminal_record', titleAr: 'فيش جنائي', titleEn: 'Criminal record check', required: true),
        ];
      }

      setState(() {
        _types = types;
        _docs = (results[1]['documents'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  /// Latest server-side document for a type, if any.
  Map<String, dynamic>? _docFor(String type) {
    final matches = _docs.where((d) => d['type'] == type);
    return matches.isEmpty ? null : matches.first;
  }

  int get _requiredMissingCount => _types
      .where((t) => t.required && _docFor(t.id) == null && !_uploading.contains(t.id))
      .length;

  Future<void> _pickAndUpload(_DocType type) async {
    final strings = AppStrings.of(context);
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
                    strings.sourceCamera,
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
                    strings.sourceGallery,
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

    setState(() {
      _uploading.add(type.id);
      _localPreviews[type.id] = File(image.path);
    });

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final uploadReq = http.MultipartRequest(
        'POST',
        Uri.parse('${state.baseUrl}/captain/upload'),
      );
      uploadReq.headers['Authorization'] = 'Bearer ${state.token}';
      uploadReq.files.add(await http.MultipartFile.fromPath('file', image.path));

      final uploadRes = await uploadReq.send();
      final uploadBody = await uploadRes.stream.bytesToString();

      if (uploadRes.statusCode >= 300) {
        String reason = strings.docUploadFailed;
        try {
          final err = jsonDecode(uploadBody);
          if (err is Map && err['error'] != null) reason = err['error'].toString();
        } catch (_) {}
        throw Exception(reason);
      }

      final decoded = jsonDecode(uploadBody);
      final r2Key = decoded is Map ? decoded['r2Key'] as String? : null;
      if (r2Key == null || r2Key.isEmpty) {
        throw Exception(strings.docUploadInvalidResponse);
      }

      await state.apiPost('/captain/documents', {'type': type.id, 'r2Key': r2Key});

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.docUploadedToast(_titleFor(type))),
          backgroundColor: AppTokens.success,
        ),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _localPreviews.remove(type.id));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.docErrorPrefix(e.toString().replaceAll('Exception:', '').trim()),
          ),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading.remove(type.id));
    }
  }

  /// The "×" on a filled tile: removes the local preview and, when the
  /// document is still pending review, deletes the server row so the tile
  /// truly resets. Approved/rejected rows stay — only the admin changes those.
  Future<void> _removeUpload(_DocType type) async {
    final state = context.read<CaptainState>();
    setState(() => _localPreviews.remove(type.id));
    try {
      await state.apiDelete('/captain/documents/${type.id}');
    } catch (_) {
      // Best-effort: if the row is already gone or the backend predates the
      // delete endpoint, a refresh keeps the UI honest.
    }
    await _loadAll();
  }

  void _handleNext() {
    final strings = AppStrings.of(context);
    final missing = _requiredMissingCount;
    if (missing > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.docRequiredMissing(missing)),
          backgroundColor: AppTokens.danger,
        ),
      );
      return;
    }
    widget.onNext?.call();
  }

  String _titleFor(_DocType type) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    if (isArabic) return type.titleAr;
    return type.titleEn.isNotEmpty ? type.titleEn : type.titleAr;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);
    final isDark = go.isDark;

    // The mock-ups are a near-black canvas; the shared night ramp matches it.
    final bg = isDark ? AppTokens.nightBg : go.bg;
    final tileBg = isDark ? AppTokens.nightSurface : go.surface;
    final text = go.text;
    final muted = go.muted;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: close (X) on the trailing side, المساعدة on the lead
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTokens.spaceMd,
                vertical: AppTokens.spaceXs,
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      AppStrings.of(context).helpAction,
                      style: AppTokens.font(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.info,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: text),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),

            // ── Step title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.title ?? strings.docOnboardingTitle,
                  style: AppTokens.font(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: text,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),

            // ── Upload tiles grid
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTokens.primary),
                    )
                  : _loadFailed
                      ? _buildRetry(muted)
                      : RefreshIndicator(
                          onRefresh: _loadAll,
                          color: AppTokens.primary,
                          child: GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.spaceMd,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: AppTokens.spaceSm,
                              crossAxisSpacing: AppTokens.spaceSm,
                              childAspectRatio: 0.82,
                            ),
                            itemCount: _types.length,
                            itemBuilder: (context, i) =>
                                _buildTile(_types[i], tileBg, text, muted, isDark),
                          ),
                        ),
            ),

            // ── Optional extra fields (e.g. رقم الهوية)
            if (widget.extraFields.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.extraFields,
                ),
              ),

            // ── Footer: lime next button, back chevron, step progress
            _buildFooter(strings, text, muted),
          ],
        ),
      ),
    );
  }

  Widget _buildRetry(Color muted) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: muted),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            AppStrings.of(context).docsLoadFailed,
            style: AppTokens.font(fontSize: 15, fontWeight: FontWeight.w700, color: muted),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          TextButton.icon(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(AppStrings.of(context).retryAction),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(_DocType type, Color tileBg, Color text, Color muted, bool isDark) {
    final doc = _docFor(type.id);
    final localPreview = _localPreviews[type.id];
    final isUploading = _uploading.contains(type.id);
    final hasImage = localPreview != null || (doc != null && doc['r2_key'] != null);
    final status = doc?['status']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              // Tile body
              GestureDetector(
                onTap: isUploading ? null : () => _pickAndUpload(type),
                child: Container(
                  decoration: BoxDecoration(
                    color: tileBg,
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    border: status == 'rejected'
                        ? Border.all(color: AppTokens.danger.withOpacity(0.5))
                        : status == 'approved'
                            ? Border.all(color: AppTokens.success.withOpacity(0.5))
                            : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: isUploading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTokens.lime,
                          ),
                        )
                      : localPreview != null
                          ? Image.file(localPreview, fit: BoxFit.cover)
                          : hasImage
                              ? _ServerDocImage(r2Key: doc!['r2_key'].toString())
                              : Center(
                                  child: Icon(
                                    Icons.add_rounded,
                                    size: 34,
                                    color: isDark ? AppTokens.nightMuted : muted,
                                  ),
                                ),
                ),
              ),

              // "اختياري" badge — top-start corner, like the mock-ups.
              if (!type.required && !hasImage)
                PositionedDirectional(
                  top: 6,
                  start: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                    child: Text(
                      AppStrings.of(context).docOptionalBadge,
                      style: AppTokens.font(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              // Status dot for reviewed docs
              if (status == 'approved' || status == 'pending')
                PositionedDirectional(
                  top: 6,
                  start: 6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: status == 'approved' ? AppTokens.success : AppTokens.warning,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status == 'approved' ? Icons.check_rounded : Icons.hourglass_top_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),

              // "×" remove button — top-end corner on filled, non-approved tiles.
              if (hasImage && !isUploading && status != 'approved')
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: GestureDetector(
                    onTap: () => _removeUpload(type),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _titleFor(type),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTokens.font(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: muted,
            height: 1.3,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 220.ms);
  }

  Widget _buildFooter(AppStrings strings, Color text, Color muted) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceMd,
        AppTokens.spaceMd,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Lime next button — the single dominant action, like the mocks.
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _handleNext,
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  label: Text(
                    strings.nextAction,
                    style: AppTokens.font(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.onLime,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.lime,
                    foregroundColor: AppTokens.onLime,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              // Back chevron in a dark square
              SizedBox(
                height: 52,
                width: 52,
                child: Material(
                  color: AppTokens.nightSurface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    onTap: widget.onBack ?? () => Navigator.of(context).maybePop(),
                    child: Icon(Icons.chevron_right_rounded, color: text),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  child: LinearProgressIndicator(
                    value: widget.totalSteps == 0 ? 0 : widget.step / widget.totalSteps,
                    minHeight: 5,
                    backgroundColor: AppTokens.nightSurface,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTokens.lime),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                strings.stepOfTotal(widget.step, widget.totalSteps),
                style: AppTokens.font(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders a document image that lives behind the authenticated
/// GET /captain/file/:key endpoint. Adds the bearer token manually because
/// [Image.network] can't attach headers to every redirect hop on all
/// platforms.
class _ServerDocImage extends StatefulWidget {
  final String r2Key;
  const _ServerDocImage({required this.r2Key});

  @override
  State<_ServerDocImage> createState() => _ServerDocImageState();
}

class _ServerDocImageState extends State<_ServerDocImage> {
  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    return Image.network(
      '${state.baseUrl}/captain/file/${widget.r2Key}',
      fit: BoxFit.cover,
      headers: {'Authorization': 'Bearer ${state.token}'},
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_rounded, color: AppTokens.darkFaint),
      ),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTokens.lime),
              ),
            ),
    );
  }
}

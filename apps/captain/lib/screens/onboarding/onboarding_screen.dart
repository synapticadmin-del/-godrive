import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:tempo_captain/services/captain_state.dart';
import '../documents/document_status_screen.dart';

/// Captain onboarding — the four-step wizard from the product mock-ups:
///
///   1. المعلومات الشخصية  — profile photo + four-part name + birth date
///   2. رخصة القيادة        — licence photo + expiry date
///   3. المستندات الشخصية   — national ID card + criminal record
///                            (front + optional back) + national ID number
///   4. معلومات السيارة     — vehicle photo + registration (front + optional back) + make/model/colour/plate/year
///
/// Design language follows the screenshots exactly: a near-black canvas, dark
/// rounded input fields and upload tiles, an "اختياري" badge on optional
/// tiles, a small "×" to clear a picked photo, a cyan "التالي" button with a
/// back chevron, and a "X من 4" progress bar pinned to the footer.
///
/// Every piece of data is saved the moment it is produced — photos upload to
/// R2 + register against the admin-managed document-type catalog (migration
/// 0012), and each step's fields POST to /captain/profile as a partial
/// update. A captain can close the app mid-flow and resume where they left
/// off: on launch the wizard pre-fills from GET /captain/profile and
/// GET /captain/documents.
class CaptainOnboardingScreen extends StatefulWidget {
  const CaptainOnboardingScreen({super.key});

  @override
  State<CaptainOnboardingScreen> createState() =>
      _CaptainOnboardingScreenState();
}

class _DocTypeDef {
  final String id;
  final String titleAr;
  final String titleEn;
  final bool required;
  const _DocTypeDef({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.required,
  });

  factory _DocTypeDef.fromJson(Map<String, dynamic> j) => _DocTypeDef(
        id: j['id']?.toString() ?? '',
        titleAr: j['title_ar']?.toString() ?? '',
        titleEn: j['title_en']?.toString() ?? '',
        required: (j['required'] as num? ?? 1) == 1,
      );
}

class _CaptainOnboardingScreenState extends State<CaptainOnboardingScreen> {
  static const int _totalSteps = 4;

  /// Earliest accepted vehicle model year — same floor the birth-date picker
  /// uses, so the two date-ish inputs on this screen agree.
  static const int _minVehicleYear = 1950;
  int _step = 0; // 0..3
  bool _loading = true;
  bool _saving = false;

  final ImagePicker _picker = ImagePicker();

  // Server state
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _docs = [];
  List<_DocTypeDef> _catalog = [];

  // Local previews (instant feedback while the upload round-trips)
  final Map<String, File> _localPreviews = {};
  final Set<String> _uploading = {};

  // Step 1 — personal info
  final _firstName = TextEditingController();
  final _fatherName = TextEditingController();
  final _grandfatherName = TextEditingController();
  final _familyName = TextEditingController();
  String? _birthDate; // YYYY-MM-DD

  // Step 2 — licence
  String? _licenseExpiry;

  // Step 3 — documents
  final _nationalId = TextEditingController();

  // Step 4 — vehicle
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _vehiclePlate = TextEditingController();
  final _vehicleYear = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _fatherName.dispose();
    _grandfatherName.dispose();
    _familyName.dispose();
    _nationalId.dispose();
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    _vehiclePlate.dispose();
    _vehicleYear.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Data
  // ------------------------------------------------------------------

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final state = context.read<CaptainState>();
    try {
      final results = await Future.wait([
        state.apiGet('/captain/profile').catchError((_) => <String, dynamic>{'captain': null}),
        state.apiGet('/captain/documents').catchError((_) => <String, dynamic>{'documents': const []}),
        state.apiGet('/captain/document-types').catchError((_) => <String, dynamic>{'types': const []}),
      ]);
      if (!mounted) return;

      _profile = results[0]['captain'] as Map<String, dynamic>?;
      _docs = (results[1]['documents'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      _catalog = (results[2]['types'] as List?)
              ?.whereType<Map>()
              .map((e) => _DocTypeDef.fromJson(Map<String, dynamic>.from(e)))
              .where((t) => t.id.isNotEmpty)
              .toList() ??
          [];

      _prefill();
      setState(() {
        _step = _firstIncompleteStep();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prefill() {
    final p = _profile;
    if (p == null) return;
    _firstName.text = p['first_name']?.toString() ?? '';
    _fatherName.text = p['father_name']?.toString() ?? '';
    _grandfatherName.text = p['grandfather_name']?.toString() ?? '';
    _familyName.text = p['family_name']?.toString() ?? '';
    _birthDate = p['birth_date']?.toString();
    _licenseExpiry = p['license_expiry']?.toString();
    _nationalId.text = p['national_id_number']?.toString() ?? '';
    _vehicleMake.text = p['vehicle_make']?.toString() ?? '';
    _vehicleModel.text = p['vehicle_model']?.toString() ?? '';
    _vehicleColor.text = p['vehicle_color']?.toString() ?? '';
    _vehiclePlate.text = p['vehicle_plate']?.toString() ?? '';
    _vehicleYear.text = p['vehicle_year']?.toString() ?? '';
  }

  /// The first step that still fails validation.
  ///
  /// Must be called only after the catalog, the documents and the profile have
  /// loaded and _prefill() has populated the controllers — _validForStep reads
  /// all three.
  ///
  /// Settles on the last step when everything already validates, rather than
  /// running past the end, so a returning captain gets a review-and-submit view
  /// instead of an out-of-range index.
  int _firstIncompleteStep() {
    for (var i = 0; i < _totalSteps; i++) {
      if (!_validForStep(i)) return i;
    }
    return _totalSteps - 1;
  }

  Map<String, dynamic>? _docFor(String type) {
    final matches = _docs.where((d) => d['type'] == type);
    return matches.isEmpty ? null : matches.first;
  }

  bool _hasDoc(String type) =>
      _localPreviews[type] != null ||
      (_docFor(type)?['r2_key']?.toString().isNotEmpty ?? false);

  /// Whether the active locale is Arabic.
  ///
  /// Read from Localizations, never inferred by comparing a translated string
  /// to a literal: that breaks the instant a translation is reworded, and it
  /// breaks silently.
  bool get _isArabic => Localizations.localeOf(context).languageCode == 'ar';

  String _titleFor(String typeId, String fallback) {
    final def = _catalog.where((t) => t.id == typeId).firstOrNull;
    if (def == null) return fallback;
    if (_isArabic) return def.titleAr.isNotEmpty ? def.titleAr : fallback;
    return def.titleEn.isNotEmpty ? def.titleEn : def.titleAr;
  }

  bool _isRequired(String typeId, {bool fallback = true}) {
    final def = _catalog.where((t) => t.id == typeId).firstOrNull;
    return def?.required ?? fallback;
  }

  /// True when the catalog loaded and [typeId] is not in it — i.e. an admin
  /// deactivated the type. GET /captain/document-types filters `active = 1`,
  /// so a switched-off type simply never arrives.
  ///
  /// The `isNotEmpty` guard matters: an empty catalog means the fetch failed,
  /// not that every type was deactivated. In that case this returns false so
  /// [_docMissing] falls through to _isRequired's strict `fallback: true`.
  /// Degrading to permissive on a network error is the wrong default for
  /// compliance documents.
  bool _deactivated(String typeId) =>
      _catalog.isNotEmpty && !_catalog.any((t) => t.id == typeId);

  /// True when [typeId] should block the current step.
  ///
  /// The single source of truth for both the Next gate and the validation
  /// toast. The tiles badge themselves from _isRequired, so anything that
  /// gates on a different rule can contradict what the captain is looking at.
  bool _docMissing(String typeId) =>
      !_deactivated(typeId) && _isRequired(typeId) && !_hasDoc(typeId);

  // ------------------------------------------------------------------
  // Upload
  // ------------------------------------------------------------------

  Future<void> _pickAndUpload(String type) async {
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
                  title: Text(strings.sourceCamera,
                      style: AppTokens.font(fontWeight: FontWeight.w600)),
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
                  title: Text(strings.sourceGallery,
                      style: AppTokens.font(fontWeight: FontWeight.w600)),
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
      _uploading.add(type);
      _localPreviews[type] = File(image.path);
    });

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final uploadReq = http.MultipartRequest(
        'POST',
        Uri.parse('${state.baseUrl}/captain/upload'),
      );
      uploadReq.headers['Authorization'] = 'Bearer ${state.token}';
      uploadReq.files.add(await http.MultipartFile.fromPath(
        'file',
        image.path,
        contentType: imageMediaTypeForPath(image.path),
      ));

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

      await state.apiPost('/captain/documents', {'type': type, 'r2Key': r2Key});
      await _reloadDocs();
    } catch (e) {
      if (!mounted) return;
      setState(() => _localPreviews.remove(type));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.docErrorPrefix(e.toString().replaceAll('Exception:', '').trim()),
          ),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading.remove(type));
    }
  }

  Future<void> _removeUpload(String type) async {
    final state = context.read<CaptainState>();
    setState(() => _localPreviews.remove(type));
    try {
      await state.apiDelete('/captain/documents/$type');
    } catch (_) {}
    await _reloadDocs();
  }

  Future<void> _reloadDocs() async {
    try {
      final res = await context.read<CaptainState>().apiGet('/captain/documents');
      if (!mounted) return;
      setState(() {
        _docs = (res['documents'] as List?)
                ?.whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------------
  // Step navigation
  // ------------------------------------------------------------------

  /// Latest accepted model year: next calendar year, so a brand-new model year
  /// is not rejected in December.
  int get _maxVehicleYear => DateTime.now().year + 1;

  /// The year field is optional, so blank passes. A filled one has to be a
  /// plausible model year — `maxLength: 4` alone happily accepted 0001.
  bool _vehicleYearValid() {
    final raw = _vehicleYear.text.trim();
    if (raw.isEmpty) return true;
    final year = int.tryParse(raw);
    if (year == null) return false;
    return year >= _minVehicleYear && year <= _maxVehicleYear;
  }

  bool _validForStep(int step) {
    switch (step) {
      case 0:
        return !_docMissing('profile_photo') &&
            _firstName.text.trim().isNotEmpty &&
            _fatherName.text.trim().isNotEmpty;
      case 1:
        return !_docMissing('license');
      case 2:
        return !_docMissing('national_id') &&
            !_docMissing('criminal_record') &&
            (!_isRequired('national_id', fallback: false) ||
                _nationalId.text.trim().isNotEmpty);
      case 3:
        return !_docMissing('vehicle_reg') &&
            _vehicleMake.text.trim().isNotEmpty &&
            _vehicleModel.text.trim().isNotEmpty &&
            _vehiclePlate.text.trim().isNotEmpty &&
            _vehicleYearValid();
      default:
        return true;
    }
  }

  Future<void> _next() async {
    final strings = AppStrings.of(context);
    if (!_validForStep(_step)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_validationMessage()),
          backgroundColor: AppTokens.danger,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _saveStep(_step);
      if (!mounted) return;
      if (_step < _totalSteps - 1) {
        setState(() => _step++);
      } else {
        // Final step saved — the account now sits in the review queue. Rather
        // than dropping the captain back to a blank gate, hand them the
        // read-through status screen: it says "حسابك قيد المراجعة" up top and
        // lists every document's review state, which is exactly the answer
        // they want the moment they finish uploading.
        await context.read<CaptainState>().refreshMe();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DocumentStatusScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(strings.docErrorPrefix(
              e.toString().replaceAll('Exception:', '').trim())),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _validationMessage() {
    final strings = AppStrings.of(context);
    switch (_step) {
      case 0:
        return _docMissing('profile_photo')
            ? strings.onbNeedProfilePhoto
            : strings.onbNeedNames;
      case 1:
        return strings.onbNeedLicense;
      case 2:
        if (_docMissing('national_id')) return strings.onbNeedNationalId;
        if (_docMissing('criminal_record')) return strings.onbNeedCriminalRecord;
        return strings.onbNeedNationalIdNumber;
      default:
        if (_docMissing('vehicle_reg')) return strings.onbNeedVehicleReg;
        if (!_vehicleYearValid()) {
          return strings.onbYearRange(_minVehicleYear, _maxVehicleYear);
        }
        return strings.onbNeedVehicleFields;
    }
  }

  Future<void> _saveStep(int step) async {
    final state = context.read<CaptainState>();
    switch (step) {
      case 0:
        final fullName = [
          _firstName.text.trim(),
          _fatherName.text.trim(),
          _grandfatherName.text.trim(),
          _familyName.text.trim(),
        ].where((s) => s.isNotEmpty).join(' ');
        await state.apiPost('/captain/profile', {
          'firstName': _firstName.text.trim(),
          'fatherName': _fatherName.text.trim(),
          'grandfatherName': _grandfatherName.text.trim(),
          'familyName': _familyName.text.trim(),
          if (_birthDate != null) 'birthDate': _birthDate,
          if (fullName.isNotEmpty) 'name': fullName,
        });
      case 1:
        // The licence photo is registered by _pickAndUpload on its own, so
        // with no expiry date there is genuinely nothing to persist here.
        // This used to collapse to a POST of `{}`.
        if (_licenseExpiry != null) {
          await state.apiPost('/captain/profile', {
            'licenseExpiry': _licenseExpiry,
          });
        }
      case 2:
        final nationalId = _nationalId.text.trim();
        if (nationalId.isNotEmpty) {
          await state.apiPost('/captain/profile', {
            'nationalIdNumber': nationalId,
          });
        }
      case 3:
        final year = int.tryParse(_vehicleYear.text.trim());
        await state.apiPost('/captain/profile', {
          'vehicleMake': _vehicleMake.text.trim(),
          'vehicleModel': _vehicleModel.text.trim(),
          'vehicleColor': _vehicleColor.text.trim(),
          'vehiclePlate': _vehiclePlate.text.trim(),
          'licenseNumber': _vehiclePlate.text.trim(),
          // Range already enforced by _vehicleYearValid() via _validForStep(3).
          if (year != null) 'vehicleYear': year,
        });
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);
    final isDark = go.isDark;
    final bg = isDark ? AppTokens.nightBg : go.bg;
    final fieldBg = isDark ? AppTokens.nightSurface : AppTokens.inputFill;
    final text = go.text;
    final muted = go.muted;

    final titles = [
      strings.onbStep1Title,
      strings.onbStep2Title,
      strings.docOnboardingTitle,
      strings.onbStep4Title,
    ];

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTokens.primary),
              )
            : Column(
                children: [
                  _topBar(text),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        titles[_step],
                        style: AppTokens.font(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: text,
                        ),
                      ).animate(key: ValueKey(_step)).fadeIn(duration: 200.ms),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
                      child: switch (_step) {
                        0 => _stepPersonalInfo(fieldBg, text, muted, isDark),
                        1 => _stepLicence(fieldBg, text, muted, isDark),
                        2 => _stepDocuments(fieldBg, text, muted, isDark),
                        _ => _stepVehicle(fieldBg, text, muted, isDark),
                      },
                    ),
                  ),
                  _footer(strings, text),
                ],
              ),
      ),
    );
  }

  /// The "المساعدة" sheet.
  ///
  /// Leads with the concrete blocker for the current step — the same string
  /// the Next button's toast uses — because "why can I not continue?" is the
  /// only question a stalled captain is asking. General guidance follows.
  Future<void> _showHelp() async {
    final go = GoTheme.of(context);
    final badge = GoBadgeColors.of(go, GoBadgeTone.pending);
    final strings = AppStrings.of(context);
    final optionalLabel = strings.docOptionalBadge;
    final blocker = _validForStep(_step) ? null : _validationMessage();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: go.panel,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTokens.radiusXl),
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceMd,
              AppTokens.spaceSm,
              AppTokens.spaceMd,
              AppTokens.spaceMd,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                    decoration: BoxDecoration(
                      color: go.border,
                      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                    ),
                  ),
                ),
                Text(
                  strings.onbHelpTitle,
                  style: AppTokens.font(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                if (blocker != null) ...[
                  Container(
                    padding: const EdgeInsets.all(AppTokens.spaceSm),
                    decoration: BoxDecoration(
                      color: badge.bg,
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: badge.accent),
                        const SizedBox(width: AppTokens.spaceXs),
                        Expanded(
                          child: Text(
                            strings.onbHelpBlocker(blocker),
                            style: AppTokens.font(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: badge.fg,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                ],
                Text(
                  strings.onbHelpBody(optionalLabel),
                  style: AppTokens.font(
                    fontSize: 13.5,
                    color: go.muted,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                SizedBox(
                  height: AppTokens.tapTarget,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTokens.lime,
                      foregroundColor: AppTokens.onLime,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      ),
                    ),
                    child: Text(
                      strings.onbHelpDismiss,
                      style: AppTokens.font(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTokens.onLime,
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

  Widget _topBar(Color text) {
    final strings = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceXs,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _showHelp,
            icon: Icon(Icons.help_outline_rounded, size: 18, color: text),
            label: Text(
              strings.onbHelpAction,
              style: AppTokens.font(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: text,
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
    );
  }

  // ── Step 1: المعلومات الشخصية ─────────────────────────────────────
  Widget _stepPersonalInfo(Color fieldBg, Color text, Color muted, bool isDark) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _uploadTile(
              type: 'profile_photo',
              label: _titleFor('profile_photo', strings.onbDocProfilePhoto),
              isDark: isDark,
              width: 110,
              height: 110,
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _field(_firstName, strings.onbFirstName, fieldBg, text, muted,
            required: true),
        const SizedBox(height: AppTokens.spaceSm),
        // This field was missing entirely while _validForStep(0) still
        // required it, so the step could never be completed: the captain
        // filled every visible box and the wizard still refused to advance.
        _field(_fatherName, strings.onbFatherName, fieldBg, text, muted,
            required: true),
        const SizedBox(height: AppTokens.spaceSm),
        _field(_grandfatherName, strings.onbGrandfatherName, fieldBg, text, muted),
        const SizedBox(height: AppTokens.spaceSm),
        _field(_familyName, strings.onbFamilyName, fieldBg, text, muted),
        const SizedBox(height: AppTokens.spaceSm),
        _dateField(
          value: _birthDate,
          hint: strings.onbBirthDate,
          fieldBg: fieldBg,
          text: text,
          muted: muted,
          firstDate: DateTime(1950),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
          onPicked: (d) => setState(() => _birthDate = d),
        ),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );
  }

  // ── Step 2: رخصة القيادة ──────────────────────────────────────────
  Widget _stepLicence(Color fieldBg, Color text, Color muted, bool isDark) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _uploadTile(
              type: 'license',
              label: _titleFor('license', strings.onbDocLicense),
              isDark: isDark,
              width: 130,
              height: 130,
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _dateField(
          value: _licenseExpiry,
          hint: strings.onbLicenseExpiry,
          fieldBg: fieldBg,
          text: text,
          muted: muted,
          firstDate: DateTime.now(),
          lastDate: DateTime.now().add(const Duration(days: 365 * 15)),
          onPicked: (d) => setState(() => _licenseExpiry = d),
        ),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );
  }

  // ── Step 3: المستندات الشخصية ─────────────────────────────────────
  Widget _stepDocuments(Color fieldBg, Color text, Color muted, bool isDark) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _uploadTile(
                type: 'criminal_record_back',
                label: _titleFor('criminal_record_back',
                    strings.onbDocCriminalRecordBack),
                isDark: isDark,
                optionalBadge: !_isRequired('criminal_record_back', fallback: false),
                height: 120,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: _uploadTile(
                type: 'criminal_record',
                label: _titleFor('criminal_record', strings.onbDocCriminalRecord),
                isDark: isDark,
                optionalBadge: !_isRequired('criminal_record'),
                height: 120,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            // `national_id` is seeded required in the catalog (migration 0014)
            // but had no tile in any step, so it could never be supplied.
            Expanded(
              child: _uploadTile(
                type: 'national_id',
                label: _titleFor('national_id', strings.onbDocNationalId),
                isDark: isDark,
                optionalBadge: !_isRequired('national_id'),
                height: 120,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _field(_nationalId, strings.onbNationalIdNumber, fieldBg, text, muted,
            keyboardType: TextInputType.number, maxLength: 14),
        const SizedBox(height: AppTokens.spaceXs),
        Text(
          strings.onbOptionalDocsNote,
          style: AppTokens.font(fontSize: 12, color: muted, height: 1.5),
        ),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );
  }

  // ── Step 4: معلومات السيارة ───────────────────────────────────────
  Widget _stepVehicle(Color fieldBg, Color text, Color muted, bool isDark) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _uploadTile(
                type: 'vehicle_reg_back',
                label: _titleFor('vehicle_reg_back', strings.onbDocVehicleRegBack),
                isDark: isDark,
                optionalBadge: !_isRequired('vehicle_reg_back', fallback: false),
                height: 120,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: _uploadTile(
                type: 'vehicle_reg',
                label: _titleFor('vehicle_reg', strings.onbDocVehicleReg),
                isDark: isDark,
                optionalBadge: !_isRequired('vehicle_reg'),
                height: 120,
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: _uploadTile(
                type: 'vehicle_photo',
                label: _titleFor('vehicle_photo', strings.onbDocVehiclePhoto),
                isDark: isDark,
                optionalBadge: !_isRequired('vehicle_photo', fallback: false),
                height: 120,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _field(_vehicleMake, strings.onbVehicleMake, fieldBg, text, muted,
            required: true),
        const SizedBox(height: AppTokens.spaceSm),
        _field(_vehicleModel, strings.onbVehicleModel, fieldBg, text, muted,
            required: true),
        const SizedBox(height: AppTokens.spaceSm),
        _field(_vehicleColor, strings.onbVehicleColor, fieldBg, text, muted),
        const SizedBox(height: AppTokens.spaceSm),
        _field(_vehiclePlate, strings.onbVehiclePlate, fieldBg, text, muted,
            required: true),
        const SizedBox(height: AppTokens.spaceSm),
        _field(_vehicleYear, strings.onbVehicleYear, fieldBg, text, muted,
            keyboardType: TextInputType.number, maxLength: 4),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Shared widgets
  // ------------------------------------------------------------------

  Widget _field(
    TextEditingController controller,
    String hint,
    Color fieldBg,
    Color text,
    Color muted, {
    bool required = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      onChanged: (_) => setState(() {}),
      style: AppTokens.font(fontSize: 14.5, color: text),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTokens.font(fontSize: 14, color: muted),
        filled: true,
        fillColor: fieldBg,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          borderSide: BorderSide(
            // Both arms of this were Colors.transparent, so a required
            // field that was still empty looked exactly like a satisfied
            // one. A hairline now marks what is blocking the step.
            color: required && controller.text.trim().isEmpty
                ? AppTokens.nightBorder
                : Colors.transparent,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          borderSide: const BorderSide(color: AppTokens.lime, width: 1.2),
        ),
      ),
    );
  }

  Widget _dateField({
    required String? value,
    required String hint,
    required Color fieldBg,
    required Color text,
    required Color muted,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<String> onPicked,
  }) {
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final initial = value != null
            ? DateTime.tryParse(value) ?? now
            : (lastDate.isBefore(now) ? lastDate : now);
        final picked = await showDatePicker(
          context: context,
          initialDate: initial.isBefore(firstDate)
              ? firstDate
              : (initial.isAfter(lastDate) ? lastDate : initial),
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) {
          final y = picked.year.toString().padLeft(4, '0');
          final m = picked.month.toString().padLeft(2, '0');
          final d = picked.day.toString().padLeft(2, '0');
          onPicked('$y-$m-$d');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMd,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: fieldBg,
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? hint,
                style: AppTokens.font(
                  fontSize: 14,
                  color: value == null ? muted : text,
                ),
              ),
            ),
            Icon(Icons.calendar_month_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  /// One upload tile in the mock-up style: a dark rounded square with a big
  /// "+" when empty, the picked photo with an "×" when filled, and an
  /// "اختياري" badge on optional tiles. [width]/[height] give the prominent
  /// single-tile steps (1 & 2) a larger canvas than the three-up grids.
  Widget _uploadTile({
    required String type,
    required String label,
    required bool isDark,
    bool optionalBadge = false,
    double? width,
    double height = 120,
  }) {
    final strings = AppStrings.of(context);
    final tileBg = isDark ? AppTokens.nightSurface : AppTokens.lightSurface;
    final muted = GoTheme.of(context).muted;
    final doc = _docFor(type);
    final localPreview = _localPreviews[type];
    final isUploading = _uploading.contains(type);
    final hasImage = _hasDoc(type);
    final status = doc?['status']?.toString();

    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: isUploading ? null : () => _pickAndUpload(type),
              child: Container(
                width: width,
                height: height,
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
                            ? _ServerImage(r2Key: doc!['r2_key'].toString())
                            : Center(
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 34,
                                  color: isDark ? AppTokens.nightMuted : muted,
                                ),
                              ),
              ),
            ),

            if (optionalBadge && !hasImage)
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
                    strings.docOptionalBadge,
                    style: AppTokens.font(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

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
        const SizedBox(height: 6),
        Text(
          label,
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
    );

    // A `Column(crossAxisAlignment: stretch)` handed straight to a Row is
    // given an UNBOUNDED width constraint, and stretch resolves that to an
    // infinite tile width. The Row then overflows and clips the tile away
    // completely — which is the empty space captains saw where the photo
    // picker should be on steps 1 and 2. (Steps 3 and 4 wrap their tiles in
    // Expanded, so those constraints were bounded and rendered fine.)
    // An explicit width makes the tile safe in either kind of parent.
    return width == null ? tile : SizedBox(width: width, child: tile);
  }

  Widget _footer(AppStrings strings, Color text) {
    final valid = _validForStep(_step);
    final isLast = _step == _totalSteps - 1;

    // The action is always present, always full-width, and always tappable.
    // Previously the incomplete state painted an onLime (#101010) label on a
    // nightSurface (#26262B) fill — a ~1.05:1 contrast ratio, i.e. an empty
    // grey slab with no readable text on a near-black page, which captains
    // reasonably read as "there is no Next button". Tapping it while the step
    // is incomplete raises the Arabic validation toast naming exactly what is
    // still missing, so the flow is never a dead end.
    final Color fill = valid ? AppTokens.lime : AppTokens.nightSurface;
    final Color ink = valid ? AppTokens.onLime : AppTokens.nightText;

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
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _next,
                    icon: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ink,
                            ),
                          )
                        : Icon(
                            isLast
                                ? Icons.check_rounded
                                : Icons.chevron_left_rounded,
                            size: 20,
                            color: ink,
                          ),
                    label: Text(
                      isLast ? strings.onbSubmitForReview : strings.nextAction,
                      style: AppTokens.font(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: fill,
                      foregroundColor: ink,
                      disabledBackgroundColor: AppTokens.nightSurface,
                      disabledForegroundColor: AppTokens.nightMuted,
                      elevation: 0,
                      // A hairline keeps the incomplete state legible as a
                      // button against the near-black canvas.
                      side: valid
                          ? BorderSide.none
                          : const BorderSide(color: AppTokens.nightBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTokens.spaceLg,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              SizedBox(
                height: 52,
                width: 52,
                child: Material(
                  color: AppTokens.nightSurface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    onTap: _saving ? null : _back,
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
                    value: (_step + 1) / _totalSteps,
                    minHeight: 5,
                    backgroundColor: AppTokens.nightSurface,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTokens.lime),
                  ),
                ),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Text(
                strings.onbStepCounter(_step + 1, _totalSteps),
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

/// Authenticated image loader for documents stored in R2 behind
/// GET /captain/file/:key (bearer token required).
class _ServerImage extends StatelessWidget {
  final String r2Key;
  const _ServerImage({required this.r2Key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    // The stored extension is assigned server-side from the file's own magic
    // bytes — POST /captain/upload writes `.pdf` only when `%PDF-` sits at
    // offset 0 — so this suffix is a type signal we can trust rather than
    // client-supplied metadata.
    if (r2Key.toLowerCase().endsWith('.pdf')) return const _PdfDocBadge();
    return Image.network(
      '${state.baseUrl}/captain/file/$r2Key',
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

/// Stand-in tile for a stored PDF document.
///
/// A PDF has no bitmap for [Image.network] to decode, so before this it fell
/// through to the `errorBuilder` and showed a broken-image icon — which reads as
/// a failed upload rather than a stored file. There is deliberately nothing to
/// tap: GET /captain/file requires the bearer token and serves PDFs as
/// `Content-Disposition: attachment`, so there is no URL an external viewer
/// could open without the header. The captain needs confirmation the file is
/// stored; the admin review screen renders the document itself.
class _PdfDocBadge extends StatelessWidget {
  const _PdfDocBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf_rounded, size: 30, color: AppTokens.lime),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            'PDF',
            style: AppTokens.font(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTokens.lime,
            ),
          ),
        ],
      ),
    );
  }
}

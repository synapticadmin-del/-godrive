import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'document_status_screen.dart';
import 'documents_onboarding_screen.dart';

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
/// Uploads can now carry the identity metadata the admin verifies by eye:
/// the four-part legal name and national ID number (for the ID card), plus
/// each document's expiry date. The metadata sheet appears after the photo
/// is picked, so the photo-first flow stays unchanged for the document types
/// that need no extra data.
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

  /// The checklist renders the admin-managed catalog from
  /// GET /captain/document-types when it is available, and falls back to the
  /// classic four for backends that predate the catalog (migration 0013).
  static const _fallbackDocTypes = [
    {'type': 'license', 'title': 'رخصة القيادة', 'titleEn': 'Driving license', 'icon': Icons.card_membership_rounded},
    {'type': 'national_id', 'title': 'البطاقة الشخصية', 'titleEn': 'National ID card', 'icon': Icons.badge_rounded},
    {'type': 'vehicle_reg', 'title': 'رخصة السيارة', 'titleEn': 'Vehicle registration', 'icon': Icons.directions_car_rounded},
    {'type': 'criminal_record', 'title': 'فيش جنائي', 'titleEn': 'Criminal record check', 'icon': Icons.fact_check_rounded},
  ];

  List<Map<String, dynamic>> _docTypes = _fallbackDocTypes
      .map((d) => Map<String, dynamic>.from(d))
      .toList();

  static const _iconByName = <String, IconData>{
    'card_membership': Icons.card_membership_rounded,
    'badge': Icons.badge_rounded,
    'directions_car': Icons.directions_car_rounded,
    'fact_check': Icons.fact_check_rounded,
    'account_circle': Icons.account_circle_rounded,
    'description': Icons.description_rounded,
  };

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    try {
      final state = context.read<CaptainState>();
      // Catalog + documents load together; a missing catalog endpoint (older
      // backend) is tolerated so the checklist keeps working with the fallback.
      final results = await Future.wait([
        state.apiGet('/captain/documents'),
        state.apiGet('/captain/document-types').catchError((_) => <String, dynamic>{'types': const []}),
      ]);
      // Guard against leaving the screen while the request is in flight.
      if (!mounted) return;

      final typesRaw = (results[1]['types'] as List?) ?? const [];
      if (typesRaw.isNotEmpty) {
        _docTypes = typesRaw.whereType<Map>().map((e) {
          final t = Map<String, dynamic>.from(e);
          final isArabic =
              Localizations.localeOf(context).languageCode == 'ar';
          final titleAr = t['title_ar']?.toString() ?? '';
          final titleEn = t['title_en']?.toString() ?? '';
          return {
            'type': t['id']?.toString() ?? '',
            'title': isArabic
                ? (titleAr.isNotEmpty ? titleAr : (titleEn.isNotEmpty ? titleEn : t['id']?.toString() ?? ''))
                : (titleEn.isNotEmpty ? titleEn : (titleAr.isNotEmpty ? titleAr : t['id']?.toString() ?? '')),
            'icon': _iconByName[t['icon']?.toString()] ?? Icons.description_rounded,
          };
        }).where((t) => (t['type'] as String).isNotEmpty).toList();
      }

      setState(() {
        _docs = (results[0]['documents'] as List?)
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

  /// Which identity fields (if any) a document type collects at upload time.
  /// The national ID card is where the four-part legal name and the ID number
  /// belong; expiry applies to every document except the criminal record,
  /// which carries no expiry in this flow.
  static bool _collectsHolderName(String type) => type == 'national_id';
  static bool _collectsNationalIdNumber(String type) => type == 'national_id';
  static bool _collectsExpiry(String type) =>
      type == 'license' || type == 'national_id' || type == 'vehicle_reg';

  /// Date of birth is printed on the national ID card and nowhere else in this
  /// checklist, so it is collected alongside the ID number rather than as a
  /// separate onboarding step the captain would have to find.
  static bool _collectsBirthDate(String type) => type == 'national_id';

  /// Inline validation for the date of birth.
  ///
  /// Stays `null` while the field is untouched, so the sheet does not open
  /// pre-flagged. A missing value is reported only after a submit attempt; an
  /// under-age date is reported the moment it is picked, because that is not a
  /// mistake the captain can fix by trying harder and they deserve to know
  /// before they finish the rest of the form.
  ///
  /// The picker's own `lastDate` already excludes under-18 dates, so the age
  /// branch is a backstop for the day someone widens those bounds.
  static String? _birthDateError(
    DateTime? value,
    AppStrings strings, {
    required bool submitAttempted,
  }) {
    if (value == null) {
      return submitAttempted ? strings.docBirthDateRequired : null;
    }
    if (goAgeInYears(value, DateTime.now()) < kMinCaptainAge) {
      return strings.docBirthDateTooYoung;
    }
    return null;
  }

  /// Bottom sheet that gathers the identity metadata for a document before
  /// the registration call. Returns null when the captain cancels — in that
  /// case the already-picked photo is simply discarded and nothing uploads,
  /// matching how dismissing the source sheet behaves.
  Future<Map<String, String>?> _collectIdentityFields(
    String docType,
    String title,
  ) async {
    final needsName = _collectsHolderName(docType);
    final needsIdNumber = _collectsNationalIdNumber(docType);
    final needsExpiry = _collectsExpiry(docType);
    final needsBirthDate = _collectsBirthDate(docType);
    if (!needsName && !needsIdNumber && !needsExpiry && !needsBirthDate) {
      return const {};
    }

    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    DateTime? expiry;
    DateTime? birthDate;
    // Set once the captain has tried to submit, so the birth-date field stays
    // quiet until then instead of shouting "required" at a form they have not
    // filled in yet.
    var submitAttempted = false;
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final strings = AppStrings.of(sheetCtx);
        final go = GoTheme.of(sheetCtx);

        InputDecoration fieldDecoration({
          required String label,
          required String hint,
          required IconData icon,
        }) =>
            InputDecoration(
              labelText: label,
              hintText: hint,
              // `go.action` rather than `primary`: brand green on the night
              // input fill is about 3.34:1, which only just clears the 3:1
              // floor for a non-text glyph.
              prefixIcon: Icon(icon, color: go.action, size: 20),
              filled: true,
              fillColor: go.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                borderSide: BorderSide(color: go.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                borderSide: BorderSide(color: go.border),
              ),
            );

        // Groups the fields under quiet headings. Four stacked inputs with
        // identical chrome read as one undifferentiated wall; splitting them
        // into "who this document belongs to" and "when it is valid" lets the
        // captain see at a glance which half they have finished.
        Widget sectionLabel(String text) => Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceXs),
              child: Text(
                text,
                style: AppTokens.font(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: go.muted,
                  letterSpacing: 0.2,
                ),
              ),
            );

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              // Keep the sheet above the soft keyboard.
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: go.panel,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTokens.radiusXl),
                  ),
                ),
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppTokens.spaceMd),
                    // Let the captain flick the keyboard away instead of
                    // hunting for the done key: with four fields open the
                    // keyboard covers more of the sheet than the form does.
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sheet handle
                          Center(
                            child: Container(
                              margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: go.border,
                                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                              ),
                            ),
                          ),
                          Text(
                            title,
                            style: AppTokens.font(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: go.text,
                            ),
                          ),
                          const SizedBox(height: AppTokens.spaceMd),

                          // Who the document belongs to.
                          if (needsName || needsIdNumber) ...[
                            sectionLabel(strings.docSectionIdentity),
                            if (needsName) ...[
                              TextFormField(
                                controller: nameCtrl,
                                textInputAction: TextInputAction.next,
                                style: AppTokens.font(color: go.text),
                                decoration: fieldDecoration(
                                  label: strings.docHolderFullNameLabel,
                                  hint: strings.docHolderFullNameHint,
                                  icon: Icons.person_outline_rounded,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().length < 8)
                                        ? strings.docIdentityFieldsRequired
                                        : null,
                              ),
                              const SizedBox(height: AppTokens.spaceSm),
                            ],
                            if (needsIdNumber) ...[
                              TextFormField(
                                controller: idCtrl,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                style: AppTokens.font(color: go.text),
                                decoration: fieldDecoration(
                                  label: strings.docNationalIdNumberLabel,
                                  hint: strings.docNationalIdNumberHint,
                                  icon: Icons.fingerprint_rounded,
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().length < 10)
                                        ? strings.docIdentityFieldsRequired
                                        : null,
                              ),
                              const SizedBox(height: AppTokens.spaceSm),
                            ],
                            if (needsBirthDate || needsExpiry)
                              const SizedBox(height: AppTokens.spaceXs),
                          ],

                          // When it is valid.
                          if (needsBirthDate || needsExpiry) ...[
                            sectionLabel(strings.docSectionDates),
                            // Date of birth. `GoDateField.birthDate` opens the
                            // calendar on the year grid and echoes the computed
                            // age back, so a slipped decade is caught here
                            // rather than by a reviewer three days later.
                            if (needsBirthDate) ...[
                              GoDateField(
                                label: strings.docBirthDateLabel,
                                hint: strings.docBirthDateHint,
                                helpText: strings.docBirthDateLabel,
                                purpose: GoDatePurpose.birthDate,
                                icon: Icons.cake_outlined,
                                value: birthDate,
                                onChanged: (picked) =>
                                    setSheetState(() => birthDate = picked),
                                helperText: birthDate == null
                                    ? null
                                    : strings.docBirthDateAge(
                                        goAgeInYears(
                                          birthDate!,
                                          DateTime.now(),
                                        ),
                                      ),
                                errorText: _birthDateError(
                                  birthDate,
                                  strings,
                                  submitAttempted: submitAttempted,
                                ),
                              ),
                              const SizedBox(height: AppTokens.spaceSm),
                            ],
                            if (needsExpiry) ...[
                              GoDateField(
                                label: strings.docExpiryDateLabel,
                                hint: strings.docExpiryDateHint,
                                helpText: strings.docExpiryDateLabel,
                                purpose: GoDatePurpose.documentExpiry,
                                icon: Icons.event_rounded,
                                value: expiry,
                                onChanged: (picked) =>
                                    setSheetState(() => expiry = picked),
                                errorText: submitAttempted && expiry == null
                                    ? strings.docIdentityFieldsRequired
                                    : null,
                              ),
                              const SizedBox(height: AppTokens.spaceSm),
                            ],
                          ],

                          const SizedBox(height: AppTokens.spaceXs),
                          SizedBox(
                            width: double.infinity,
                            height: AppTokens.tapTarget,
                            child: ElevatedButton(
                              onPressed: () {
                                // Surface every inline error at once. Revealing
                                // them one snackbar at a time made the captain
                                // guess which field was wrong.
                                setSheetState(() => submitAttempted = true);

                                final valid =
                                    formKey.currentState?.validate() ?? false;
                                if (!valid) return;

                                final birthError = needsBirthDate
                                    ? _birthDateError(
                                        birthDate,
                                        strings,
                                        submitAttempted: true,
                                      )
                                    : null;
                                final expiryMissing =
                                    needsExpiry && expiry == null;

                                if (birthError != null || expiryMissing) {
                                  ScaffoldMessenger.of(sheetCtx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        birthError ??
                                            strings.docIdentityFieldsRequired,
                                      ),
                                      backgroundColor: AppTokens.danger,
                                    ),
                                  );
                                  return;
                                }

                                Navigator.pop(sheetCtx, {
                                  if (needsName) 'holderFullName': nameCtrl.text.trim(),
                                  if (needsIdNumber)
                                    'nationalIdNumber': idCtrl.text.trim(),
                                  if (needsBirthDate && birthDate != null)
                                    'birthDate': goFormatDateIso(birthDate!),
                                  if (needsExpiry && expiry != null)
                                    'expiresAt': goFormatDateIso(expiry!),
                                });
                              },
                              // Colours come from the token ramp, not from
                              // `primary`/white: at night the action is lime
                              // with near-black text, and white-on-lime was
                              // close to illegible.
                              style: ElevatedButton.styleFrom(
                                backgroundColor: go.action,
                                foregroundColor: go.onAction,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                                ),
                              ),
                              child: Text(
                                strings.confirm,
                                style: AppTokens.font(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: go.onAction,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    idCtrl.dispose();
    return result;
  }

  /// Shows the captured document back to the captain before anything uploads.
  ///
  /// Glare across a laminated licence, a thumb over the ID number, a cropped
  /// corner — these are the things that actually get a document rejected, and
  /// until now the captain found out days later from a reviewer. The photo went
  /// straight from the camera into a multipart request without ever being shown
  /// back. Returning false sends them to the camera again.
  Future<bool> _confirmPhoto(XFile image, String title) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final strings = AppStrings.of(sheetCtx);
        final go = GoTheme.of(sheetCtx);

        return Container(
          decoration: BoxDecoration(
            color: go.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusXl),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: go.border,
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusPill),
                      ),
                    ),
                  ),
                  Text(
                    '${strings.docPhotoCheckTitle} — $title',
                    style: AppTokens.font(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: go.text,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceXs),
                  Text(
                    strings.docPhotoCheckHint,
                    style: AppTokens.font(
                      fontSize: 12.5,
                      color: go.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),

                  // Cap the preview so a portrait phone photo cannot push the
                  // actions off the bottom of the sheet.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetCtx).size.height * 0.42,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                      child: Container(
                        width: double.infinity,
                        color: go.surface,
                        child: Image.file(
                          File(image.path),
                          fit: BoxFit.contain,
                          // A preview that fails to decode must not strand the
                          // captain on a blank sheet with no way to judge the
                          // shot — say so and let them retake.
                          errorBuilder: (_, __, ___) => Padding(
                            padding:
                                const EdgeInsets.all(AppTokens.spaceLg),
                            child: Center(
                              child: Text(
                                strings.docUploadFailed,
                                textAlign: TextAlign.center,
                                style: AppTokens.font(
                                  fontSize: 13,
                                  color: go.muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: AppTokens.tapTarget,
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.pop(sheetCtx, false),
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 18,
                            ),
                            label: Text(
                              strings.chooseNewPhotoAction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTokens.font(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: go.text,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: go.text,
                              side: BorderSide(color: go.border),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusMd),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: SizedBox(
                          height: AppTokens.tapTarget,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(sheetCtx, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: go.action,
                              foregroundColor: go.onAction,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusMd),
                              ),
                            ),
                            child: Text(
                              strings.docPhotoUseAction,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTokens.font(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: go.onAction,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Dismissing the sheet by swiping it away is a rejection, not consent to
    // upload whatever happened to be in frame.
    return accepted ?? false;
  }

  Future<void> _upload(String docType, String title) async {
    // Offer gallery alongside camera — camera-only forces captains to re-shoot
    // documents they already have photographed on their phone.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final strings = AppStrings.of(sheetCtx);
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

    // Shoot → check → (retake as many times as needed) → details. The retake
    // loop reopens the same source the captain already chose rather than
    // sending them back through the source sheet each time.
    XFile image;
    while (true) {
      final picked =
          await _picker.pickImage(source: source, imageQuality: 75);
      if (picked == null || !mounted) return;

      final keep = await _confirmPhoto(picked, title);
      if (!mounted) return;
      if (keep) {
        image = picked;
        break;
      }
    }

    // Gather the identity metadata that travels with this document. A null
    // result means the captain backed out of the details sheet — treat that
    // like cancelling the whole upload, not like "upload without data".
    final identityFields = await _collectIdentityFields(docType, title);
    if (identityFields == null || !mounted) return;

    // Gather the identity metadata that travels with this document. A null
    // result means the captain backed out of the details sheet — treat that
    // like cancelling the whole upload, not like "upload without data".
    final identityFields = await _collectIdentityFields(docType, title);
    if (identityFields == null || !mounted) return;

    setState(() => _uploading.add(docType));

    final state = context.read<CaptainState>();
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppStrings.of(context);

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
        String reason = strings.docUploadFailed;
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
        throw Exception(strings.docUploadInvalidResponse);
      }

      // Step 2: register document in DB, with whatever identity metadata the
      // details sheet collected (empty for documents that carry none).
      await state.apiPost('/captain/documents', {
        'type': docType,
        'r2Key': r2Key,
        ...identityFields,
      });

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.docUploadedToast(title)),
          backgroundColor: AppTokens.success,
        ),
      );
      await _loadDocs();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.docErrorPrefix(e.toString().replaceAll('Exception:', '').trim())),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading.remove(docType));
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);
    final state = context.watch<CaptainState>();

    // Approval landed while the captain was mid-upload: leave the queue for
    // the live app. A cleared token (logout from another screen) also pops
    // back to the root so MainShell's LoginScreen branch takes over instead
    // of hanging on a dead session.
    if (state.isApproved || state.token == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(
          strings.documentsRequiredTitle,
          style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700, color: go.text),
        ),
        backgroundColor: go.panel,
        surfaceTintColor: Colors.transparent,
        actions: [
          // Grid view — the onboarding-style tile layout from the product
          // mock-ups, backed by the same catalog + documents endpoints.
          IconButton(
            tooltip: strings.gridViewTooltip,
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DocumentsOnboardingScreen(
                    onNext: () => Navigator.of(context).maybePop(),
                  ),
                ),
              );
            },
          ),
          // A read-through status view: every document, its review state, and
          // the admin's exact rejection reason in one place.
          IconButton(
            tooltip: strings.documentsStatusTooltip,
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
            tooltip: strings.refreshAccountTooltip,
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
            tooltip: strings.logout,
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
                  child: _buildHeader(go, strings),
                ),
                // Rejection feedback, front and centre: the exact reason the
                // admin gave for every rejected document, right above the
                // checklist so the fix is the next thing the captain does.
                if (_rejectedDocs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildRejectionAlert(go.text, go.muted, strings),
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
                          strings,
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
  Widget _buildRejectionAlert(Color text, Color muted, AppStrings strings) {
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
                      ? strings.docRejectedAlertTitleSingle
                      : strings.docRejectedAlertTitlePlural,
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
            strings.docRejectedAlertBody,
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
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHeader(GoTheme go, AppStrings strings) {
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
                      allDone ? strings.docHeaderAllUploaded : strings.docHeaderIncomplete,
                      style: AppTokens.font(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allDone
                          ? strings.docHeaderAllUploadedSubtitle
                          : strings.docHeaderIncompleteSubtitle,
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
            allDone ? strings.docProgressAllUploaded : strings.docProgressLine(approved, total),
            style: AppTokens.font(fontSize: 12, color: go.muted),
          ),
          // The three steps ahead — understanding what happens next is what
          // turns a form dump into an onboarding experience.
          const SizedBox(height: AppTokens.spaceLg),
          _buildStepRow(
            icon: Icons.upload_file_rounded,
            label: strings.docStepUpload,
            done: approved > 0,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildStepRow(
            icon: Icons.manage_search_rounded,
            label: strings.docStepReview,
            done: allDone,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          _buildStepRow(
            icon: Icons.directions_car_rounded,
            label: strings.docStepStartTrips,
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
    AppStrings strings,
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
        statusLabel = strings.docStatusRejectedReupload;
        statusIcon = Icons.error_rounded;
        cardBorder = AppTokens.danger.withOpacity(0.3);
      default:
        badgeText = go.muted;
        // The "not uploaded yet" badge uses a neutral surface tint; pinning it
        // to lightSurface left a pale square on the dark card, so track the
        // active theme like the approved/pending/rejected badges do.
        badgeBg = go.surface;
        statusLabel = strings.docStatusNotUploaded;
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
                          isUploading ? strings.docUploading : statusLabel,
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
                      _rejectionReason(type) ?? strings.docNoReasonFallback,
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
                    status == 'rejected' ? strings.docReuploadAction : strings.docUploadAction,
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

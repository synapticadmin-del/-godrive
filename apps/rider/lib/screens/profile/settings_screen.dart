import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_state.dart';

/// Language, theme, privacy and account settings.
///
/// Every surface here reads from [GoTheme] rather than the light-only
/// `AppTokens.light*` constants. Hardcoding the light palette meant this screen
/// stayed white in dark mode — and because it hosts the theme picker itself, the
/// rider was choosing "داكن" on a screen that then refused to go dark.
///
/// The privacy band (policy, export, deletion) is launch-gate item 12. Both
/// stores require in-app account deletion for any app with accounts, so the
/// delete row is a store requirement before it is a PDPL one.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Where the published policy lives.
///
/// TODO(legal): replace with the policy hosted on the product domain once one
/// exists. Until then this points at the canonical text in the repository, which
/// is publicly readable and renders in a browser. The same URL has to go in both
/// store listings — see `docs/legal/README.md`.
const String kPrivacyPolicyUrl =
    'https://github.com/synapticadmin-del/-godrive/blob/main/docs/legal/privacy-policy.ar.md';

/// Copy for the three privacy rows.
///
/// Inline rather than in [AppStrings] because
/// `packages/flutter_shared/lib/l10n/app_strings.dart` is owned by no task in
/// this execution wave, and WAVE-PLAN §8 forbids editing an unowned file. The one
/// key that already exists — `privacyPolicy` — is read from AppStrings below.
/// Reported as a seam on the E16 PR; fold these into AppStrings once that file
/// has an owner.
String _t(BuildContext context, String ar, String en) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busyExport = false;
  bool _busyDelete = false;

  // ---------------------------------------------------------------------
  // Privacy actions
  // ---------------------------------------------------------------------

  Future<void> _openPolicy() async {
    final uri = Uri.parse(kPrivacyPolicyUrl);
    // The same two-step the splash screen uses: external browser first, platform
    // default as the fallback for devices that refuse the external intent.
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  /// GET /user/export → hand the JSON to the share sheet.
  ///
  /// Sharing rather than writing to disk keeps this inside the permissions the
  /// app already holds: the rider picks the destination (mail, Drive, Files) and
  /// no storage permission is requested.
  Future<void> _exportData() async {
    if (_busyExport) return;
    setState(() => _busyExport = true);
    final state = context.read<AppState>();
    try {
      final data = await state.apiGet('/user/export');
      if (!mounted) return;
      await Share.share(
        const JsonEncoder.withIndent('  ').convert(data),
        subject: _t(context, 'بياناتي على Tempo', 'My Tempo data'),
      );
    } catch (e) {
      if (!mounted) return;
      _toast(_t(context, 'تعذّر تصدير البيانات: $e', 'Could not export your data: $e'));
    } finally {
      if (mounted) setState(() => _busyExport = false);
    }
  }

  /// DELETE /user/account, behind a confirmation that has to be typed.
  ///
  /// The dialog states what is deleted *and what is kept*, because the ledger and
  /// the consent record survive an erasure and telling the rider "everything is
  /// deleted" would be false.
  Future<void> _deleteAccount() async {
    final confirmed = await _confirmDeletion();
    if (confirmed != true || _busyDelete) return;

    setState(() => _busyDelete = true);
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    try {
      await state.apiDelete('/user/account');
      await state.logout();
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      // The server refuses deletion during a live trip (ACTIVE_TRIP) and while
      // the wallet is in credit (BALANCE_OUTSTANDING). Both arrive here carrying
      // the server's own message, which is more useful than a generic failure.
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busyDelete = false);
    }
  }

  Future<bool?> _confirmDeletion() {
    final go = GoTheme.of(context);
    final word = _t(context, 'حذف', 'DELETE');
    final controller = TextEditingController();

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final matches = controller.text.trim() == word;
            return AlertDialog(
              backgroundColor: go.panel,
              title: Text(
                _t(dialogContext, 'حذف الحساب نهائيًا', 'Delete your account'),
                style: AppTokens.font(color: go.text, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(
                        dialogContext,
                        'سيُحذف: اسمك ورقم هاتفك وبريدك وصورتك، وأماكنك المحفوظة، ووسائل الدفع، وإشعارات أجهزتك.',
                        'Deleted: your name, phone, email and photo, your saved places, '
                            'payment methods and device notifications.',
                      ),
                      style: AppTokens.font(color: go.text),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        dialogContext,
                        'سيبقى: السجلات المالية للرحلات (التزام محاسبي) وسجل موافقتك وبلاغات السلامة — '
                            'كلها مفصولة عن هويتك ومرتبطة بمعرّف مجهول.',
                        'Kept: trip financial records (an accounting obligation), your consent record '
                            'and safety reports — all detached from your identity and attached to an '
                            'anonymous id.',
                      ),
                      style: AppTokens.font(color: go.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _t(dialogContext, 'اكتب «$word» للتأكيد', 'Type "$word" to confirm'),
                      style: AppTokens.font(color: go.text, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      style: AppTokens.font(color: go.text),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: go.bg,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    _t(dialogContext, 'إلغاء', 'Cancel'),
                    style: AppTokens.font(color: go.muted),
                  ),
                ),
                TextButton(
                  // Disabled until the word matches: a destructive, irreversible
                  // action should not be reachable by a mis-tap.
                  onPressed: matches ? () => Navigator.pop(dialogContext, true) : null,
                  child: Text(
                    _t(dialogContext, 'حذف الحساب', 'Delete account'),
                    style: AppTokens.font(
                      color: matches ? AppTokens.danger : go.muted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.settingsTitle, style: AppTokens.font()),
        backgroundColor: go.panel,
        foregroundColor: go.text,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            color: go.panel,
            child: ListTile(
              title: Text(
                strings.languageLabel,
                style: AppTokens.font(color: go.text),
              ),
              trailing: DropdownButton<String>(
                value: state.locale.languageCode,
                dropdownColor: go.panel,
                style: AppTokens.font(color: go.text),
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: 'ar', child: Text(strings.arabicLanguage)),
                  DropdownMenuItem(value: 'en', child: Text(strings.englishLanguage)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    state.setLocale(Locale(val, val == 'ar' ? 'EG' : 'US'));
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: go.panel,
            child: ListTile(
              title: Text(
                strings.darkMode,
                style: AppTokens.font(color: go.text),
              ),
              trailing: DropdownButton<ThemeMode>(
                value: state.themeMode,
                dropdownColor: go.panel,
                style: AppTokens.font(color: go.text),
                underline: const SizedBox(),
                items: [
                  DropdownMenuItem(value: ThemeMode.system, child: Text(strings.themeSystem)),
                  DropdownMenuItem(value: ThemeMode.light, child: Text(strings.themeLight)),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text(strings.themeDark)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    state.setThemeMode(val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: go.panel,
            child: ListTile(
              title: Text(
                strings.aboutApp,
                style: AppTokens.font(color: go.text),
              ),
              trailing: Icon(Icons.info, color: go.muted),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Tempo',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.rocket_launch, size: 48, color: AppTokens.primary),
                );
              },
            ),
          ),

          // ---------------------------------------------------------------
          // Privacy and data — launch-gate item 12.
          // ---------------------------------------------------------------
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _t(context, 'الخصوصية والبيانات', 'Privacy & data'),
              style: AppTokens.font(color: go.muted, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: go.panel,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined, color: go.muted),
                  title: Text(
                    // The one key that already existed in AppStrings — and had no
                    // caller anywhere before this screen.
                    strings.privacyPolicy,
                    style: AppTokens.font(color: go.text),
                  ),
                  trailing: Icon(Icons.open_in_new, size: 18, color: go.muted),
                  onTap: _openPolicy,
                ),
                Divider(color: go.border, height: 1),
                ListTile(
                  leading: Icon(Icons.download_outlined, color: go.muted),
                  title: Text(
                    _t(context, 'تصدير بياناتي', 'Export my data'),
                    style: AppTokens.font(color: go.text),
                  ),
                  subtitle: Text(
                    _t(
                      context,
                      'ملف JSON بكل ما نحتفظ به عنك',
                      'A JSON file of everything we hold about you',
                    ),
                    style: AppTokens.font(color: go.muted, fontSize: 12),
                  ),
                  trailing: _busyExport
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _busyExport ? null : _exportData,
                ),
                Divider(color: go.border, height: 1),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined, color: AppTokens.danger),
                  title: Text(
                    _t(context, 'حذف الحساب', 'Delete account'),
                    style: AppTokens.font(color: AppTokens.danger, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _t(context, 'إجراء نهائي لا يمكن التراجع عنه', 'Permanent and cannot be undone'),
                    style: AppTokens.font(color: go.muted, fontSize: 12),
                  ),
                  trailing: _busyDelete
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _busyDelete ? null : _deleteAccount,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              state.logout();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTokens.danger.withOpacity(0.1),
              foregroundColor: AppTokens.danger,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(strings.logout, style: AppTokens.font(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

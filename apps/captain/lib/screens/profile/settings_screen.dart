import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../documents/document_upload_screen.dart';
import '../safety/sos_screen.dart';

/// Captain profile and settings screen.
///
/// The screen is structured in four bands:
///   1. A profile header with the captain's name and live online/approval status.
///   2. Three stat cards (rating, trip count, approval state).
///   3. Grouped settings sections, each in a white card with 48dp touch targets.
///   4. A visually distinct danger-colour logout button that asks for
///      confirmation before acting — destructive actions should never fire on
///      an accidental tap.
///
/// All copy is read from [AppStrings] (resolved from the ambient locale) so
/// this file carries no inline Arabic literals — see `app_strings.dart`.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    final captain = state.captain;
    final approval = captain?['approval_status'] ?? captain?['status'];
    final isApproved = approval == 'approved';

    // rating_avg is a REAL that can arrive as 4.6666…, so it is trimmed to one
    // decimal rather than printed raw.
    final ratingValue = (captain?['rating_avg'] as num?)?.toDouble() ?? 5.0;
    final rating = ratingValue.toStringAsFixed(1);
    final tripCount = ((captain?['rating_count'] as num?)?.toInt() ?? 0).toString();

    final vehicleMake = (captain?['vehicle_make'] as String?) ?? '';
    final vehicleModel = (captain?['vehicle_model'] as String?) ?? '';
    final vehiclePlate = (captain?['vehicle_plate'] as String?) ?? '';

    // substring(0, 1) throws when the name is an empty string.
    final captainName = (state.user?['name'] as String?)?.trim();
    final hasName = captainName != null && captainName.isNotEmpty;
    final initial = hasName ? captainName[0].toUpperCase() : 'C';

    return Scaffold(
      backgroundColor: go.bg,
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + AppTokens.spaceMd,
          bottom: 100,
        ),
        children: [
          // ── Profile header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
            child: Row(
              children: [
                // Avatar — brand-tinted initial, large enough to feel personal
                // without requiring a photo-upload flow for new captains.
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppTokens.primarySoft,
                  child: Text(
                    initial,
                    style: AppTokens.font(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTokens.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasName ? captainName : strings.captainFallbackName,
                        style: AppTokens.font(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: go.text,
                        ),
                      ),
                      const SizedBox(height: AppTokens.space2xs),
                      Row(
                        children: [
                          // Status indicator dot — green when online, muted
                          // when offline, amber when awaiting approval.
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isApproved
                                  ? (state.online ? AppTokens.success : go.muted)
                                  : AppTokens.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isApproved
                                ? (state.online ? strings.online : strings.offline)
                                : strings.pendingApproval,
                            style: AppTokens.font(fontSize: 13, color: go.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fade().slideY(begin: -0.1),

          const SizedBox(height: AppTokens.spaceLg),

          // ── Stat cards ─────────────────────────────────────────────────
          // Three equal-width panels for the captain's key performance
          // numbers. Material icons replace the previous emoji so the icons
          // can be coloured and sized consistently across brightness modes.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.star_rounded,
                    iconColor: AppTokens.warning,
                    value: rating,
                    label: strings.ratingLabel,
                    panel: go.panel,
                    text: go.text,
                    muted: go.muted,
                    border: go.border,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: _StatCard(
                    icon: Icons.directions_car_rounded,
                    iconColor: AppTokens.info,
                    value: tripCount,
                    label: strings.tripsLabel,
                    panel: go.panel,
                    text: go.text,
                    muted: go.muted,
                    border: go.border,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceXs),
                Expanded(
                  child: _StatCard(
                    icon: isApproved
                        ? Icons.verified_rounded
                        : Icons.hourglass_top_rounded,
                    iconColor: isApproved ? AppTokens.success : AppTokens.accent,
                    value: isApproved ? strings.approvedValue : strings.underReviewValue,
                    label: strings.statusLabelKey,
                    panel: go.panel,
                    text: go.text,
                    muted: go.muted,
                    border: go.border,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppTokens.spaceLg),

          // ── Vehicle information ─────────────────────────────────────────
          if (vehicleMake.isNotEmpty || vehiclePlate.isNotEmpty) ...[
            _SectionTitle(title: strings.vehicleInfoTitle, muted: go.muted),
            _SettingsCard(panel: go.panel, border: go.border, children: [
              _InfoRow(
                icon: Icons.directions_car_rounded,
                iconColor: AppTokens.primary,
                title: strings.vehicleLabel,
                value: '$vehicleMake $vehicleModel'.trim(),
                text: go.text,
                muted: go.muted,
              ),
              if (vehiclePlate.isNotEmpty) ...[
                _RowDivider(border: go.border),
                _InfoRow(
                  icon: Icons.pin_rounded,
                  iconColor: AppTokens.primary,
                  title: strings.plateLabel,
                  value: vehiclePlate,
                  text: go.text,
                  muted: go.muted,
                ),
              ],
            ]),
            const SizedBox(height: AppTokens.spaceLg),
          ],

          // ── Documents ──────────────────────────────────────────────────
          _SectionTitle(title: strings.documentsTitle, muted: go.muted),
          _SettingsCard(panel: go.panel, border: go.border, children: [
            _NavRow(
              icon: Icons.upload_file_rounded,
              iconColor: AppTokens.primary,
              title: strings.uploadDocuments,
              subtitle: strings.uploadDocumentsSubtitle,
              text: go.text,
              muted: go.muted,
              border: go.border,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DocumentUploadScreen(),
                ),
              ),
            ),
          ]),

          const SizedBox(height: AppTokens.spaceLg),

          // ── Safety ─────────────────────────────────────────────────────
          _SectionTitle(title: strings.safetyTitle, muted: go.muted),
          _SettingsCard(panel: go.panel, border: go.border, children: [
            _NavRow(
              icon: Icons.sos_rounded,
              iconColor: AppTokens.sos,
              title: strings.sosButton,
              subtitle: strings.sosSubtitle,
              text: go.text,
              muted: go.muted,
              border: go.border,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SosScreen()),
              ),
            ),
          ]),

          const SizedBox(height: AppTokens.spaceLg),

          // ── Appearance & language ───────────────────────────────────────
          _SectionTitle(title: strings.appearanceTitle, muted: go.muted),
          _SettingsCard(
            panel: go.panel,
            border: go.border,
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsetsDirectional.only(
                  start: AppTokens.spaceMd,
                  end: AppTokens.spaceSm,
                ),
                secondary: Icon(
                  Icons.dark_mode_rounded,
                  color: AppTokens.primary,
                  size: 22,
                ),
                title: Text(
                  strings.darkMode,
                  style: AppTokens.font(color: go.text, fontSize: 14),
                ),
                value: state.themeMode == ThemeMode.dark ||
                    (state.themeMode == ThemeMode.system && go.isDark),
                // go.action resolves lime in dark mode; AppTokens.primary would stay
                // green on a near-black surface where lime is the expected action colour.
                activeColor: GoTheme.of(context).action,
                onChanged: (val) =>
                    state.setThemeMode(val ? ThemeMode.dark : ThemeMode.light),
              ),
              _RowDivider(border: go.border),
              ListTile(
                contentPadding: const EdgeInsetsDirectional.only(
                  start: AppTokens.spaceMd,
                  end: AppTokens.spaceSm,
                ),
                minLeadingWidth: 22,
                leading: const Icon(
                  Icons.language_rounded,
                  color: AppTokens.accent,
                  size: 22,
                ),
                title: Text(
                  strings.languageLabel,
                  style: AppTokens.font(color: go.text, fontSize: 14),
                ),
                trailing: Text(
                  state.locale.languageCode == 'ar'
                      ? strings.arabicLanguage
                      : strings.englishLanguage,
                  style: AppTokens.font(color: go.muted, fontSize: 13),
                ),
                onTap: () => state.setLocale(
                  Locale(state.locale.languageCode == 'ar' ? 'en' : 'ar'),
                ),
              ),
            ],
          ).animate().slideY(begin: 0.1),

          const SizedBox(height: AppTokens.spaceLg),

          // ── About ──────────────────────────────────────────────────────
          _SectionTitle(title: strings.aboutTitle, muted: go.muted),
          _SettingsCard(panel: go.panel, border: go.border, children: [
            _InfoRow(
              icon: Icons.info_rounded,
              iconColor: AppTokens.info,
              title: strings.aboutApp,
              value: 'GoDrive v1.0.0',
              text: go.text,
              muted: go.muted,
            ),
            _RowDivider(border: go.border),
            _InfoRow(
              icon: Icons.privacy_tip_rounded,
              iconColor: AppTokens.primary,
              title: strings.privacyPolicy,
              value: '',
              text: go.text,
              muted: go.muted,
            ),
          ]),

          const SizedBox(height: AppTokens.spaceXl),

          // ── Logout ─────────────────────────────────────────────────────
          // The danger colour is intentional: logout is destructive and
          // irreversible mid-trip. A confirmation dialog guards against the
          // accidental tap that would disconnect a captain from an active ride.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
            child: SizedBox(
              height: AppTokens.primaryActionHeight,
              child: ElevatedButton.icon(
                onPressed: () => _confirmLogout(context, state),
                icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                label: Text(
                  strings.logout,
                  style: AppTokens.font(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                ),
              ),
            ),
          ).animate().slideY(begin: 0.2),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog before logging out.
  ///
  /// The previous version fired logout immediately on tap, which means a
  /// captain mid-trip could accidentally disconnect themselves from an active
  /// ride. An extra tap costs nothing; an accidental logout costs a trip.
  Future<void> _confirmLogout(BuildContext context, CaptainState state) async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        // Read GoTheme inside the dialog builder so the cancel label resolves
        // lime in dark mode instead of staying green (rule 3 — interactive label).
        final dialogGo = GoTheme.of(ctx);
        return AlertDialog(
          title: Text(
            strings.logout,
            style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          content: Text(
            strings.logoutConfirmMessage,
            style: AppTokens.font(fontSize: 14, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                strings.cancelAction,
                style: AppTokens.font(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: dialogGo.action,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              strings.exitAction,
              style: AppTokens.font(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTokens.danger,
              ),
            ),
          ),
        ],
      );
      },
    );

    if (confirmed == true) {
      await state.logout();
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets — private helpers that keep the build method readable.
// ─────────────────────────────────────────────────────────────────────────────

/// A single stat card: icon, numeric/text value, and a label underneath.
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    required this.panel,
    required this.text,
    required this.muted,
    required this.border,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final Color panel;
  final Color text;
  final Color muted;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppTokens.spaceMd,
        horizontal: AppTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: border),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(height: AppTokens.space2xs),
          Text(
            value,
            style: AppTokens.font(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTokens.font(fontSize: 11, color: muted),
          ),
        ],
      ),
    );
  }
}

/// Bold section heading, inset to align with the card content.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.muted});

  final String title;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // end padding matches the card margin so the label tracks the card edge.
      padding: const EdgeInsetsDirectional.only(
        start: AppTokens.spaceMd,
        end: AppTokens.spaceMd,
        bottom: AppTokens.spaceXs,
      ),
      child: Text(
        title,
        style: AppTokens.font(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: muted,
        ),
      ),
    );
  }
}

/// White card that groups a list of setting rows.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.panel,
    required this.border,
    required this.children,
  });

  final Color panel;
  final Color border;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: border),
        boxShadow: AppTokens.shadowCard,
      ),
      child: Column(children: children),
    );
  }
}

/// A thin 1dp divider between rows inside a card — reusing the theme border
/// colour keeps it from standing out more than it needs to.
class _RowDivider extends StatelessWidget {
  const _RowDivider({required this.border});

  final Color border;

  @override
  Widget build(BuildContext context) {
    return Divider(color: border, height: 1, thickness: 1);
  }
}

/// A non-interactive informational row: icon + title + optional trailing value.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.text,
    required this.muted,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final Color text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      // minLeadingWidth removes the extra indent Flutter adds by default,
      // keeping icon and text tight without custom Padding wrappers.
      minLeadingWidth: 22,
      contentPadding: const EdgeInsetsDirectional.only(
        start: AppTokens.spaceMd,
        end: AppTokens.spaceSm,
      ),
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        title,
        style: AppTokens.font(color: text, fontSize: 14),
      ),
      trailing: value.isNotEmpty
          ? Text(
              value,
              style: AppTokens.font(color: muted, fontSize: 13),
            )
          : null,
    );
  }
}

/// A tappable row that navigates somewhere — includes a chevron trailing icon.
///
/// The chevron flips automatically in RTL because it uses the directional
/// `chevron_left` icon paired with Directionality from the widget tree.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.text,
    required this.muted,
    required this.border,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color text;
  final Color muted;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // In an RTL layout Flutter automatically mirrors Icons.chevron_left to
    // point right — matching the conventional "navigate forward" affordance.
    return ListTile(
      minLeadingWidth: 22,
      contentPadding: const EdgeInsetsDirectional.only(
        start: AppTokens.spaceMd,
        end: AppTokens.spaceSm,
      ),
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        title,
        style: AppTokens.font(
          color: text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: AppTokens.font(color: muted, fontSize: 12),
            )
          : null,
      trailing: Icon(Icons.chevron_left_rounded, color: muted, size: 20),
      onTap: onTap,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../documents/document_upload_screen.dart';
import '../safety/sos_screen.dart';

/// Captain profile/settings — modern design with header card, stats, and
/// grouped settings sections. Uses theme tokens so it works in both
/// white light and pure black dark themes.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CaptainState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTokens.darkBg : AppTokens.lightBg;
    final panel = isDark ? AppTokens.darkPanel : AppTokens.lightPanel;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    final captain = state.captain;
    final approval = captain?['approval_status'] ?? captain?['status'];
    final isApproved = approval == 'approved';
    final rating = captain?['rating_avg']?.toString() ?? '5.0';
    final tripCount = captain?['rating_count']?.toString() ?? '0';
    final vehicleMake = captain?['vehicle_make'] ?? '';
    final vehicleModel = captain?['vehicle_model'] ?? '';
    final vehiclePlate = captain?['vehicle_plate'] ?? '';

    return Scaffold(
      backgroundColor: bg,
      body: ListView(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 16,
          bottom: 100,
        ),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppTokens.primary.withOpacity(0.15),
                child: Text(
                  state.user?['name']?.substring(0, 1).toUpperCase() ?? 'C',
                  style: const TextStyle(color: AppTokens.primary, fontWeight: FontWeight.w800, fontSize: 24),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(state.user?['name'] ?? 'كابتن',
                  style: GoogleFonts.ibmPlexSansArabic(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(width: 8, height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: isApproved ? (state.online ? AppTokens.success : muted) : AppTokens.accent)),
                  const SizedBox(width: 6),
                  Text(isApproved ? (state.online ? 'متصل' : 'غير متصل') : 'بانتظار الموافقة',
                    style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, color: muted)),
                ]),
              ])),
            ]),
          ).animate().fade().slideY(begin: -0.1),
          const SizedBox(height: 24),
          // Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: _statCard('⭐', rating, 'التقييم', panel, text, muted, border)),
              const SizedBox(width: 10),
              Expanded(child: _statCard('🚗', tripCount, 'رحلات', panel, text, muted, border)),
              const SizedBox(width: 10),
              Expanded(child: _statCard(isApproved ? '✅' : '⏳', isApproved ? 'معتمد' : 'مراجعة', 'الحالة', panel, text, muted, border)),
            ]),
          ),
          const SizedBox(height: 24),
          // Vehicle info
          if (vehicleMake.isNotEmpty || vehiclePlate.isNotEmpty) ...[
            _sectionTitle('معلومات المركبة', muted),
            _card(panel, border, [
              _infoRow(Icons.directions_car, 'المركبة', '$vehicleMake $vehicleModel', text, muted, border),
              if (vehiclePlate.isNotEmpty)
                _infoRow(Icons.confirmation_number, 'اللوحة', vehiclePlate, text, muted, border),
            ]),
            const SizedBox(height: 24),
          ],
          // Documents
          _sectionTitle('المستندات', muted),
          _card(panel, border, [
            _navRow(Icons.upload_file, 'رفع المستندات', 'رخصة + بطاقة + فيش', text, muted, border, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DocumentUploadScreen()));
            }),
          ]),
          const SizedBox(height: 24),
          // Safety
          _sectionTitle('الأمان', muted),
          _card(panel, border, [
            _navRow(Icons.sos, 'زر الطوارئ SOS', 'تنبيه فوري للدعم', text, muted, border, () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen()));
            }),
          ]),
          const SizedBox(height: 24),
          // Appearance
          _sectionTitle('المظهر واللغة', muted),
          _card(panel, border, [
            SwitchListTile(
              title: Text('الوضع الداكن', style: GoogleFonts.ibmPlexSansArabic(color: text)),
              secondary: const Icon(Icons.dark_mode, color: AppTokens.primary),
              value: state.themeMode == ThemeMode.dark || (state.themeMode == ThemeMode.system && isDark),
              activeColor: AppTokens.primary,
              onChanged: (val) => state.setThemeMode(val ? ThemeMode.dark : ThemeMode.light),
            ),
            Divider(color: border, height: 1),
            ListTile(
              leading: const Icon(Icons.language, color: AppTokens.accent),
              title: Text('اللغة', style: GoogleFonts.ibmPlexSansArabic(color: text)),
              trailing: Text(state.locale.languageCode == 'ar' ? 'العربية' : 'English', style: GoogleFonts.ibmPlexSansArabic(color: muted)),
              onTap: () => state.setLocale(Locale(state.locale.languageCode == 'ar' ? 'en' : 'ar')),
            ),
          ]).animate().slideY(begin: 0.1),
          const SizedBox(height: 24),
          // About
          _sectionTitle('معلومات', muted),
          _card(panel, border, [
            _infoRow(Icons.info, 'عن التطبيق', 'GoDrive v1.0.0', text, muted, border),
            Divider(color: border, height: 1),
            _infoRow(Icons.privacy_tip, 'سياسة الخصوصية', '', text, muted, border),
          ]),
          const SizedBox(height: 32),
          // Logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () async { await state.logout(); if (context.mounted) Navigator.pop(context); },
              icon: const Icon(Icons.logout, color: Colors.white),
              label: Text('تسجيل الخروج', style: GoogleFonts.ibmPlexSansArabic(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: AppTokens.danger,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd))),
            ).animate().slideY(begin: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String emoji, String value, String label, Color panel, Color text, Color muted, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.ibmPlexSansArabic(fontSize: 16, fontWeight: FontWeight.w800, color: text)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.ibmPlexSansArabic(fontSize: 11, color: muted)),
      ]),
    );
  }

  Widget _sectionTitle(String title, Color muted) {
    return Padding(padding: const EdgeInsets.only(bottom: 8, right: 16),
      child: Text(title, style: GoogleFonts.ibmPlexSansArabic(fontSize: 13, fontWeight: FontWeight.w700, color: muted)));
  }

  Widget _card(Color panel, Color border, List<Widget> children) {
    return Container(margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: Column(children: children));
  }

  Widget _infoRow(IconData icon, String title, String value, Color text, Color muted, Color border) {
    return ListTile(
      leading: Icon(icon, color: AppTokens.primary, size: 22),
      title: Text(title, style: GoogleFonts.ibmPlexSansArabic(color: text, fontSize: 14)),
      trailing: value.isNotEmpty ? Text(value, style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 13)) : null,
    );
  }

  Widget _navRow(IconData icon, String title, String subtitle, Color text, Color muted, Color border, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppTokens.primary, size: 22),
      title: Text(title, style: GoogleFonts.ibmPlexSansArabic(color: text, fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: GoogleFonts.ibmPlexSansArabic(color: muted, fontSize: 12)) : null,
      trailing: const Icon(Icons.chevron_left, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }
}
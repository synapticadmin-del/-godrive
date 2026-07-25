import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: Text('الإعدادات', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: AppTokens.lightPanel,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            color: AppTokens.lightPanel,
            child: ListTile(
              title: Text('اللغة', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
              trailing: DropdownButton<String>(
                value: state.locale.languageCode,
                dropdownColor: AppTokens.lightPanel,
                style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'ar', child: Text('العربية')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
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
            color: AppTokens.lightPanel,
            child: ListTile(
              title: Text('المظهر', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
              trailing: DropdownButton<ThemeMode>(
                value: state.themeMode,
                dropdownColor: AppTokens.lightPanel,
                style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('تلقائي')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('داكن')),
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
            color: AppTokens.lightPanel,
            child: ListTile(
              title: Text('عن التطبيق', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
              trailing: const Icon(Icons.info, color: AppTokens.lightMuted),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'GoDrive',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.rocket_launch, size: 48, color: AppTokens.primary),
                );
              },
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
            child: Text('تسجيل الخروج', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

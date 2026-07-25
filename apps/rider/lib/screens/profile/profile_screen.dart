import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';
import '../history/history_screen.dart';
import '../places/saved_places_screen.dart';
import '../wallet/wallet_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _showEditProfileModal(BuildContext context, Map<String, dynamic>? user) {
    final nameController = TextEditingController(text: user?['name'] ?? '');
    final phoneController = TextEditingController(text: user?['phone'] ?? '');
    final emailController = TextEditingController(text: user?['email'] ?? '');
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isAr ? 'تعديل البيانات الشخصية' : 'Edit Profile Information',
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الاسم الكامل' : 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isAr ? 'رقم الهاتف' : 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: isAr ? 'البريد الإلكتروني' : 'Email Address',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    await ctx.read<AppState>().updateUserProfile(
                          name: nameController.text.trim(),
                          phone: phoneController.text.trim(),
                          email: emailController.text.trim(),
                        );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isAr ? 'تم حفظ التعديلات بنجاح' : 'Profile updated successfully',
                          ),
                          backgroundColor: AppTokens.success,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTokens.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    isAr ? 'حفظ التعديلات' : 'Save Changes',
                    style: GoogleFonts.ibmPlexSansArabic(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAvatarPickerModal(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final avatars = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
      'https://images.unsplash.com/photo-1539571696357-5a69c17a67c6?w=150',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr ? 'تغيير الصورة الشخصية' : 'Change Profile Picture',
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: avatars.map((url) {
                  return GestureDetector(
                    onTap: () async {
                      await ctx.read<AppState>().updateUserProfile(avatarUrl: url);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: NetworkImage(url),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  // Fallback simulation for custom avatar link
                  final defaultAvatar = 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150';
                  await ctx.read<AppState>().updateUserProfile(avatarUrl: defaultAvatar);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(
                  isAr ? 'اختيار صورة جديدة' : 'Choose New Photo',
                  style: GoogleFonts.ibmPlexSansArabic(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.user;
    final balance = appState.walletBalance ?? 0.0;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final avatarUrl = user?['avatarUrl'] as String?;

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'الملف الشخصي' : 'Profile', style: GoogleFonts.ibmPlexSansArabic()),
        actions: [
          IconButton(
            icon: Icon(
              appState.themeMode == ThemeMode.dark ? Icons.wb_sunny : Icons.nightlight_round,
            ),
            tooltip: isAr ? 'تغيير المظهر' : 'Toggle Theme',
            onPressed: () => appState.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: isAr ? 'English' : 'العربية',
            onPressed: () => appState.toggleLanguage(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Profile Header with Avatar & Edit Button
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: AppTokens.primary,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(
                          user?['name']?.substring(0, 1).toUpperCase() ?? 'U',
                          style: const TextStyle(fontSize: 40, color: Colors.white, fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _showAvatarPickerModal(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTokens.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user?['name'] ?? (isAr ? 'مستخدم' : 'User'),
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            user?['email'] ?? '',
            style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, color: AppTokens.lightMuted),
            textAlign: TextAlign.center,
          ),
          if (user?['phone'] != null && (user!['phone'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                user['phone'],
                style: GoogleFonts.ibmPlexSansArabic(fontSize: 14, color: AppTokens.lightMuted),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => _showEditProfileModal(context, user),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                isAr ? 'تعديل البيانات' : 'Edit Details',
                style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Wallet Card Preview
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTokens.primary, Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTokens.primary.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'الرصيد المتاح' : 'Available Balance',
                      style: GoogleFonts.ibmPlexSansArabic(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${balance.toStringAsFixed(2)} ${isAr ? "ج.م" : "EGP"}',
                      style: GoogleFonts.ibmPlexSansArabic(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                  },
                  icon: const Icon(Icons.add, size: 18, color: AppTokens.primary),
                  label: Text(isAr ? 'المحفظة' : 'Wallet', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.primary, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Menu Items
          _buildMenuItem(context, Icons.history_rounded, isAr ? 'رحلاتي' : 'My Trips', const HistoryScreen()),
          _buildMenuItem(context, Icons.bookmark_border_rounded, isAr ? 'الأماكن المحفوظة' : 'Saved Places', const SavedPlacesScreen()),
          _buildMenuItem(context, Icons.account_balance_wallet_outlined, isAr ? 'المحفظة' : 'Wallet', const WalletScreen()),
          _buildMenuItem(context, Icons.settings_outlined, isAr ? 'الإعدادات' : 'Settings', const SettingsScreen()),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title, Widget screen) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTokens.primary),
        title: Text(title, style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTokens.lightMuted),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
        final go = GoTheme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            decoration: BoxDecoration(
              color: go.panel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTokens.radiusXl),
              ),
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
                      color: go.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Text(
                  isAr ? 'تعديل البيانات الشخصية' : 'Edit Profile Information',
                  style: AppTokens.font(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: go.text,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الاسم الكامل' : 'Full Name',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isAr ? 'رقم الهاتف' : 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: isAr
                        ? 'البريد الإلكتروني (غير قابل للتعديل)'
                        : 'Email Address (read only)',
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                ElevatedButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ctx.read<AppState>().updateUserProfile(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim(),
                          );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            isAr
                                ? 'تم حفظ التعديلات بنجاح'
                                : 'Profile updated successfully',
                          ),
                          backgroundColor: AppTokens.success,
                        ),
                      );
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(
                            e.toString().replaceFirst('Exception: ', ''),
                          ),
                          backgroundColor: AppTokens.danger,
                        ),
                      );
                    }
                  },
                  child: Text(
                    isAr ? 'حفظ التعديلات' : 'Save Changes',
                    style: AppTokens.font(
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
        final go = GoTheme.of(ctx);
        return Container(
          padding: const EdgeInsets.all(AppTokens.spaceLg),
          decoration: BoxDecoration(
            color: go.panel,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTokens.radiusXl),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isAr ? 'تغيير الصورة الشخصية' : 'Change Profile Picture',
                style: AppTokens.font(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: go.text,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: avatars.map((url) {
                  return GestureDetector(
                    onTap: () async {
                      await ctx
                          .read<AppState>()
                          .updateUserProfile(avatarUrl: url);
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
                  const defaultAvatar =
                      'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=150';
                  await ctx
                      .read<AppState>()
                      .updateUserProfile(avatarUrl: defaultAvatar);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(
                  isAr ? 'اختيار صورة جديدة' : 'Choose New Photo',
                  style: AppTokens.font(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AppState>().fetchProfile();
        context.read<AppState>().fetchWallet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.user;
    final balance = appState.walletBalance ?? 0.0;
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final avatarUrl = user?['avatarUrl'] as String?;
    final go = GoTheme.of(context);

    final rawName = user?['name']?.toString() ?? '';
    final email = user?['email']?.toString() ?? '';
    final phone = user?['phone']?.toString() ?? '';
    final initial = rawName.isNotEmpty
        ? rawName[0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');
    final displayName = rawName.isNotEmpty
        ? rawName
        : (email.isNotEmpty
            ? email.split('@').first
            : (isAr ? 'مستخدم' : 'User'));

    return Scaffold(
      appBar: AppBar(
        title: Text(isAr ? 'الملف الشخصي' : 'Profile'),
        actions: [
          IconButton(
            icon: Icon(
              // Visible brightness, not the enum — see AppState.
              appState.isDarkActive ? Icons.wb_sunny : Icons.nightlight_round,
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
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: (avatarUrl == null || avatarUrl.isEmpty)
                      ? Text(
                          initial,
                          style: AppTokens.font(
                            fontSize: 40,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
                        border: Border.all(color: go.panel, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            displayName,
            style: AppTokens.font(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: go.text,
            ),
            textAlign: TextAlign.center,
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: AppTokens.space2xs),
            Text(
              email,
              style: AppTokens.font(fontSize: 14, color: go.muted),
              textAlign: TextAlign.center,
            ),
          ],
          if (phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.space2xs),
              child: Text(
                phone,
                style: AppTokens.font(fontSize: 14, color: go.muted),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: AppTokens.spaceSm),
          Center(
            child: TextButton.icon(
              onPressed: () => _showEditProfileModal(context, user),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                isAr ? 'تعديل البيانات' : 'Edit Details',
                style: AppTokens.font(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),

          // Wallet Card Preview — brand gradient derived from the token ramp
          // (primary → primaryDark) instead of a one-off blue.
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTokens.primaryLight, AppTokens.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              boxShadow: AppTokens.glow(AppTokens.primary, opacity: 0.30),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'الرصيد المتاح' : 'Available Balance',
                      style: AppTokens.font(
                        color: Colors.white.withOpacity(0.82),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space2xs),
                    Text(
                      '${balance.toStringAsFixed(2)} ${isAr ? "ج.م" : "EGP"}',
                      style: AppTokens.money(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WalletScreen()),
                    );
                  },
                  icon: const Icon(Icons.add, size: 18, color: AppTokens.primary),
                  label: Text(
                    isAr ? 'المحفظة' : 'Wallet',
                    style: AppTokens.font(
                      color: AppTokens.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceMd,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceLg),

          // Menu Items
          _buildMenuItem(
            context,
            Icons.history_rounded,
            isAr ? 'رحلاتي' : 'My Trips',
            const HistoryScreen(),
          ),
          _buildMenuItem(
            context,
            Icons.bookmark_border_rounded,
            isAr ? 'الأماكن المحفوظة' : 'Saved Places',
            const SavedPlacesScreen(),
          ),
          _buildMenuItem(
            context,
            Icons.account_balance_wallet_outlined,
            isAr ? 'المحفظة' : 'Wallet',
            const WalletScreen(),
          ),
          _buildMenuItem(
            context,
            Icons.settings_outlined,
            isAr ? 'الإعدادات' : 'Settings',
            const SettingsScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context,
    IconData icon,
    String title,
    Widget screen,
  ) {
    final go = GoTheme.of(context);
    return Card(
      color: go.panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        side: BorderSide(color: go.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: go.action),
        title: Text(
          title,
          style: AppTokens.font(
            fontWeight: FontWeight.w500,
            color: go.text,
          ),
        ),
        trailing: Icon(
          // Point the chevron in the direction of travel for both RTL and LTR.
          Directionality.of(context) == TextDirection.rtl
              ? Icons.arrow_back_ios
              : Icons.arrow_forward_ios,
          size: 14,
          color: go.muted,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => screen),
        ),
      ),
    );
  }
}

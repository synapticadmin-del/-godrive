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
  /// Deterministic DiceBear avatars — same pattern as the rest of the app.
  /// The seed is stable per slot so the picker always shows the same four
  /// robots, and the saved URL round-trips through the profile untouched.
  static const _avatarSeeds = ['rider-1', 'rider-2', 'rider-3', 'rider-4'];

  static String _dicebear(String seed) =>
      'https://api.dicebear.com/7.x/bottts/svg?seed=$seed';

  void _showEditProfileModal(BuildContext context, Map<String, dynamic>? user) {
    final nameController = TextEditingController(text: user?['name'] ?? '');
    final phoneController = TextEditingController(text: user?['phone'] ?? '');
    final emailController = TextEditingController(text: user?['email'] ?? '');
    final strings = AppStrings.of(context);

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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: go.panel,
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
                      color: go.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  strings.editProfileInfoTitle,
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
                    labelText: strings.fullNameLabel,
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: strings.phoneNumberLabel,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: strings.emailReadOnlyLabel,
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 24),
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
                          content: Text(strings.profileUpdatedSuccess),
                          backgroundColor: AppTokens.success,
                        ),
                      );
                    } catch (e) {
                      if (!ctx.mounted) return;
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(
                          content: Text(e.toString().replaceFirst('Exception: ', '')),
                          backgroundColor: AppTokens.danger,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: go.action,
                    foregroundColor: go.onAction,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    strings.saveChangesAction,
                    style: AppTokens.font(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: go.onAction,
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
    final strings = AppStrings.of(context);
    final avatars = _avatarSeeds.map(_dicebear).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final go = GoTheme.of(ctx);
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: go.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.changeProfilePictureTitle,
                style: AppTokens.font(fontSize: 18, fontWeight: FontWeight.bold, color: go.text),
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
                      backgroundColor: go.surface,
                      backgroundImage: NetworkImage(url),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () async {
                  // Fallback simulation for custom avatar link
                  final defaultAvatar = _dicebear('rider-default');
                  await ctx.read<AppState>().updateUserProfile(avatarUrl: defaultAvatar);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(
                  strings.chooseNewPhotoAction,
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
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);
    final user = appState.user;
    final balance = appState.walletBalance ?? 0.0;
    final avatarUrl = user?['avatarUrl'] as String?;

    final rawName = user?['name']?.toString() ?? '';
    final email = user?['email']?.toString() ?? '';
    final phone = user?['phone']?.toString() ?? '';
    final initial = rawName.isNotEmpty
        ? rawName[0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');
    final displayName = rawName.isNotEmpty
        ? rawName
        : (email.isNotEmpty ? email.split('@').first : strings.fallbackUserName);

    return Scaffold(
      backgroundColor: go.bg,
      appBar: AppBar(
        title: Text(strings.profileTitle, style: AppTokens.font()),
        backgroundColor: go.panel,
        foregroundColor: go.text,
        actions: [
          IconButton(
            icon: Icon(
              // Visible brightness, not the enum — see AppState.
              appState.isDarkActive ? Icons.wb_sunny : Icons.nightlight_round,
            ),
            tooltip: strings.toggleThemeTooltip,
            onPressed: () => appState.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: strings.toggleLanguageTooltip,
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
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                  child: (avatarUrl == null || avatarUrl.isEmpty)
                      ? Text(
                          initial,
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
            displayName,
            style: AppTokens.font(fontSize: 22, fontWeight: FontWeight.bold, color: go.text),
            textAlign: TextAlign.center,
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              style: AppTokens.font(fontSize: 14, color: go.muted),
              textAlign: TextAlign.center,
            ),
          ],
          if (phone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                phone,
                style: AppTokens.font(fontSize: 14, color: go.muted),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => _showEditProfileModal(context, user),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                strings.editDetailsAction,
                style: AppTokens.font(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Wallet Card Preview — same brand ramp as the wallet screen,
          // softened at night (see wallet_screen for the shared reasoning).
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppTokens.primary, go.isDark ? AppTokens.primaryDark : const Color(0xFF0284C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTokens.primary.withOpacity(go.isDark ? 0.15 : 0.3),
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
                      strings.availableBalanceLabel,
                      style: AppTokens.font(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${balance.toStringAsFixed(2)} ${strings.egp}',
                      style: AppTokens.font(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                  },
                  icon: const Icon(Icons.add, size: 18, color: AppTokens.primary),
                  label: Text(strings.walletTitle, style: AppTokens.font(color: AppTokens.primary, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Menu Items
          _buildMenuItem(context, go, Icons.history_rounded, strings.myTripsLabel, const HistoryScreen()),
          _buildMenuItem(context, go, Icons.bookmark_border_rounded, strings.savedPlacesLabel, const SavedPlacesScreen()),
          _buildMenuItem(context, go, Icons.account_balance_wallet_outlined, strings.walletTitle, const WalletScreen()),
          _buildMenuItem(context, go, Icons.settings_outlined, strings.settingsTitle, const SettingsScreen()),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, GoTheme go, IconData icon, String title, Widget screen) {
    return Card(
      color: go.panel,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: go.border),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTokens.primary),
        title: Text(title, style: AppTokens.font(fontWeight: FontWeight.w500, color: go.text)),
        trailing: Icon(Icons.arrow_forward_ios, size: 14, color: go.muted),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}

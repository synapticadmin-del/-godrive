import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';
import '../places/saved_places_screen.dart';
import '../ride/payment_methods_screen.dart';
import '../ride/promo_screen.dart';
import '../wallet/wallet_screen.dart';
import 'help_screen.dart';
import 'invite_screen.dart';
import 'settings_screen.dart';

/// The rider's account tab.
///
/// Two things shape this layout. First, it is tab 3 of the home shell's
/// `IndexedStack`, so the bottom navigation belongs to the parent — this screen
/// owns everything above it and deliberately has no AppBar: the brand header
/// *is* the top of the screen.
///
/// Second, the settings list follows the grouped-rows idiom rather than a stack
/// of bordered cards. Groups are separated by a canvas-coloured gutter and rows
/// by an inset hairline, which is what lets ten destinations read as three
/// scannable clusters instead of ten competing boxes.
///
/// Colour restraint is the point here. The old screen carried a green→sky-blue
/// gradient card with a coloured drop shadow, which fought the green brand it
/// sat inside. Brand colour now appears in exactly two places — the header
/// field and the top-up pill — and every row icon is neutral ink.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busyAvatar = false;

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

  bool get _isAr => Localizations.localeOf(context).languageCode == 'ar';

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTokens.font(color: Colors.white, fontSize: 14)),
        backgroundColor: error ? AppTokens.danger : AppTokens.success,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Profile photo
  // -------------------------------------------------------------------------

  /// Picks a photo and uploads it.
  ///
  /// The image is downscaled and re-encoded before it leaves the device: a
  /// current phone camera hands back a 4–8MB frame, which would trip the
  /// endpoint's 5MB ceiling and spend the rider's data on detail that is thrown
  /// away rendering it at 66dp.
  Future<void> _pickAvatar(ImageSource source) async {
    final isAr = _isAr;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() => _busyAvatar = true);
      await context.read<AppState>().uploadAvatar(picked.path);
      _toast(isAr ? 'تم تحديث صورتك الشخصية' : 'Profile photo updated');
    } catch (e) {
      _toast(
        _describeError(e, isAr ? 'تعذّر رفع الصورة' : 'Could not upload the photo'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    final isAr = _isAr;
    try {
      setState(() => _busyAvatar = true);
      await context.read<AppState>().removeAvatar();
      _toast(isAr ? 'تم إزالة الصورة' : 'Photo removed');
    } catch (e) {
      _toast(
        _describeError(e, isAr ? 'تعذّر إزالة الصورة' : 'Could not remove the photo'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  /// Platform errors (a denied camera permission, for instance) carry wording
  /// the rider should never see, so anything unrecognised falls back to a
  /// localised message.
  String _describeError(Object error, String fallback) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty || text.startsWith('PlatformException')) return fallback;
    return text;
  }

  /// Replaces the old picker, which offered four hardcoded stock portraits and
  /// a "choose new photo" button that silently assigned a fifth. The rider can
  /// now use their own camera or gallery — the whole point of the change.
  void _showAvatarSheet() {
    final isAr = _isAr;
    final hasPhoto = context.read<AppState>().avatarImage != null;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceLg,
                AppTokens.spaceXs,
                AppTokens.spaceLg,
                AppTokens.spaceSm,
              ),
              child: Text(
                isAr ? 'الصورة الشخصية' : 'Profile photo',
                style: AppTokens.font(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            _SheetAction(
              icon: Icons.photo_camera_outlined,
              label: isAr ? 'التقاط صورة بالكاميرا' : 'Take a photo',
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar(ImageSource.camera);
              },
            ),
            _SheetAction(
              icon: Icons.photo_library_outlined,
              label: isAr ? 'اختيار من معرض الصور' : 'Choose from gallery',
              onTap: () {
                Navigator.pop(ctx);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              _SheetAction(
                icon: Icons.delete_outline,
                label: isAr ? 'إزالة الصورة الحالية' : 'Remove current photo',
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
            const SizedBox(height: AppTokens.spaceSm),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Name / phone
  // -------------------------------------------------------------------------

  void _showEditProfileSheet(Map<String, dynamic>? user) {
    final isAr = _isAr;
    final nameController = TextEditingController(text: user?['name']?.toString() ?? '');
    final phoneController = TextEditingController(text: user?['phone']?.toString() ?? '');
    final emailController = TextEditingController(text: user?['email']?.toString() ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        // Lifts the sheet clear of the keyboard.
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.spaceLg,
              0,
              AppTokens.spaceLg,
              AppTokens.spaceLg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SheetHandle(),
                const SizedBox(height: AppTokens.spaceXs),
                Text(
                  isAr ? 'البيانات الشخصية' : 'Personal details',
                  style: AppTokens.font(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                TextField(
                  controller: nameController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الاسم الكامل' : 'Full name',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: isAr ? 'رقم الهاتف' : 'Phone number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                TextField(
                  controller: emailController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: isAr
                        ? 'البريد الإلكتروني (غير قابل للتعديل)'
                        : 'Email address (read only)',
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: const Icon(Icons.lock_outline, size: 18),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await ctx.read<AppState>().updateUserProfile(
                            name: nameController.text.trim(),
                            phone: phoneController.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _toast(isAr ? 'تم حفظ التعديلات' : 'Changes saved');
                    } catch (e) {
                      _toast(
                        _describeError(e, isAr ? 'تعذّر حفظ التعديلات' : 'Could not save'),
                        error: true,
                      );
                    }
                  },
                  child: Text(isAr ? 'حفظ التعديلات' : 'Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(AppState appState) async {
    final isAr = _isAr;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'تسجيل الخروج' : 'Log out'),
        content: Text(
          isAr
              ? 'هل تريد تسجيل الخروج من حسابك؟'
              : 'Are you sure you want to log out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTokens.danger),
            child: Text(isAr ? 'تسجيل الخروج' : 'Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    appState.logout();
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final go = GoTheme.of(context);
    final isAr = _isAr;
    final user = appState.user;

    final rawName = user?['name']?.toString() ?? '';
    final email = user?['email']?.toString() ?? '';
    final phone = user?['phone']?.toString() ?? '';
    final initial = rawName.isNotEmpty
        ? rawName[0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');
    final displayName = rawName.isNotEmpty
        ? rawName
        : (email.isNotEmpty ? email.split('@').first : (isAr ? 'مستخدم' : 'Rider'));

    return Scaffold(
      backgroundColor: go.bg,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              appState: appState,
              go: go,
              isAr: isAr,
              displayName: displayName,
              // Falls back to the email so the header never shows a lone name
              // floating above empty space on an account with no phone yet.
              subtitle: phone.isNotEmpty ? phone : email,
              initial: initial,
              user: user,
            ),

            // The sheet rides up over the header's spare bottom padding, which
            // is what produces the overlapping rounded lip.
            Container(
              transform: Matrix4.translationValues(0, -AppTokens.spaceLg, 0),
              // A Material, not a coloured Container: every row below is an
              // InkWell, and ink paints onto the nearest Material ancestor. With
              // an opaque Container here the ripples would render on the
              // Scaffold *behind* this surface and never be seen.
              child: Material(
                color: go.panel,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTokens.radiusXl),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionLabel(isAr ? 'إعدادات الحساب' : 'Account settings'),
                    _SettingsRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: isAr ? 'محفظتي' : 'My wallet',
                      onTap: () => _open(const WalletScreen()),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.credit_card_outlined,
                      label: isAr ? 'وسائل الدفع' : 'Payment methods',
                      onTap: () => _open(const PaymentMethodsScreen()),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.location_on_outlined,
                      label: isAr ? 'الأماكن المفضلة' : 'Favourite places',
                      onTap: () => _open(const SavedPlacesScreen()),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.local_offer_outlined,
                      label: isAr ? 'العروض والتخفيضات' : 'Offers and discounts',
                      onTap: () => _open(const PromoScreen()),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.card_giftcard_outlined,
                      label: isAr ? 'ترشيح صديق' : 'Refer a friend',
                      onTap: () => _open(const InviteScreen()),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.headset_mic_outlined,
                      label: isAr ? 'الدعم والمساعدة' : 'Support and help',
                      onTap: () => _open(const HelpScreen()),
                    ),

                    _GroupGutter(go: go),

                    _SectionLabel(isAr ? 'إعدادات التطبيق' : 'App settings'),
                    _SettingsRow(
                      icon: Icons.language,
                      label: isAr ? 'اللغة' : 'Language',
                      value: isAr ? 'العربية' : 'English',
                      onTap: () => appState.toggleLanguage(),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      // Visible brightness, not the enum — see AppState.
                      icon: appState.isDarkActive
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      label: isAr ? 'المظهر' : 'Appearance',
                      value: appState.isDarkActive
                          ? (isAr ? 'داكن' : 'Dark')
                          : (isAr ? 'فاتح' : 'Light'),
                      onTap: () => appState.toggleTheme(),
                    ),
                    const _RowDivider(),
                    _SettingsRow(
                      icon: Icons.settings_outlined,
                      label: isAr ? 'كل الإعدادات' : 'All settings',
                      onTap: () => _open(const SettingsScreen()),
                    ),

                    _GroupGutter(go: go),

                    InkWell(
                      onTap: () => _confirmLogout(appState),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          isAr ? 'تسجيل الخروج' : 'Log out',
                          textAlign: TextAlign.center,
                          style: AppTokens.font(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTokens.danger,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The brand field: portrait, identity, and the wallet balance.
  ///
  /// The balance lives *inside* the header on a translucent white strip rather
  /// than in a card of its own. That is the fix for the old screen's loudest
  /// element — a second gradient in a different hue family, wrapped in a green
  /// glow — while keeping the balance one glance from the top of the tab.
  Widget _buildHeader({
    required AppState appState,
    required GoTheme go,
    required bool isAr,
    required String displayName,
    required String subtitle,
    required String initial,
    required Map<String, dynamic>? user,
  }) {
    final balance = appState.walletBalance ?? 0.0;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppTokens.spaceMd,
        left: AppTokens.spaceLg,
        right: AppTokens.spaceLg,
        // Deliberately deep: the settings sheet overlaps the last 24dp of it.
        bottom: AppTokens.spaceXl + AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(gradient: AppTokens.headerGradient(go.isDark)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Leading in RTL, so the portrait anchors the top-trailing corner
              // of the screen exactly as in the reference layout.
              _buildAvatar(appState, initial),
              const SizedBox(width: AppTokens.spaceMd),
              Expanded(
                child: InkWell(
                  onTap: () => _showEditProfileSheet(user),
                  borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTokens.font(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: Colors.white.withOpacity(0.75),
                            ),
                          ],
                        ),
                        if (subtitle.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              // Directional so an Arabic UI still renders a
                              // +20… number left-to-right.
                              textDirection: TextDirection.ltr,
                              textAlign: isAr ? TextAlign.right : TextAlign.left,
                              style: AppTokens.font(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: appState.isDarkActive ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                tooltip: isAr ? 'تغيير المظهر' : 'Toggle appearance',
                onTap: () => appState.toggleTheme(),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              _HeaderIconButton(
                icon: Icons.language,
                tooltip: isAr ? 'English' : 'العربية',
                onTap: () => appState.toggleLanguage(),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceLg),
          _BalanceStrip(
            isAr: isAr,
            balance: balance,
            onTopUp: () => _open(const WalletScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(AppState appState, String initial) {
    final image = appState.avatarImage;

    return GestureDetector(
      onTap: _busyAvatar ? null : _showAvatarSheet,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.85), width: 2.5),
            ),
            child: CircleAvatar(
              radius: 33,
              backgroundColor: Colors.white.withOpacity(0.18),
              backgroundImage: image,
              child: image == null
                  ? Text(
                      initial,
                      style: AppTokens.font(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
          ),
          if (_busyAvatar)
            Container(
              // Matches the bordered avatar box: 33dp radius + 2.5dp ring.
              width: 71,
              height: 71,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.45),
              ),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                ),
              ),
            )
          else
            // Directional so the badge tucks toward the centre of the layout
            // instead of hanging off the screen edge in either language.
            PositionedDirectional(
              bottom: 0,
              end: 0,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 13,
                  color: AppTokens.primaryDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header pieces
// ---------------------------------------------------------------------------

/// A translucent control on the brand field. Takes its colour from the
/// gradient behind it rather than introducing another hue.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.16),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

class _BalanceStrip extends StatelessWidget {
  const _BalanceStrip({required this.isAr, required this.balance, required this.onTopUp});

  final bool isAr;
  final double balance;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMd,
        vertical: AppTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: Colors.white.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAr ? 'الرصيد المتاح' : 'Available balance',
                  style: AppTokens.font(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${balance.toStringAsFixed(2)} ${isAr ? 'ج.م' : 'EGP'}',
                  style: AppTokens.money(fontSize: 21, color: Colors.white),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            child: InkWell(
              onTap: onTopUp,
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                child: Text(
                  isAr ? 'شحن' : 'Top up',
                  style: AppTokens.font(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    // 7:1 on white — the lighter brand green would not clear AA.
                    color: AppTokens.primaryDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grouped list pieces
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceXs,
      ),
      child: Text(
        label,
        style: AppTokens.font(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: GoTheme.of(context).muted,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String label;

  /// Current state shown before the chevron — the active language, say.
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg, vertical: 15),
        child: Row(
          children: [
            // Neutral ink, not brand green: six saturated icons stacked down the
            // page is the kind of colour noise this redesign is removing.
            Icon(icon, size: 21, color: go.text),
            const SizedBox(width: AppTokens.spaceMd),
            Expanded(
              child: Text(
                label,
                style: AppTokens.font(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: go.text,
                ),
              ),
            ),
            if (value != null) ...[
              Text(
                value!,
                style: AppTokens.font(fontSize: 13, color: go.muted),
              ),
              const SizedBox(width: AppTokens.space2xs),
            ],
            // Points the way the page will move, in either direction.
            Icon(
              isRtl ? Icons.chevron_left : Icons.chevron_right,
              size: 20,
              color: go.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hairline between rows, inset past the icon column so the icons read as one
/// vertical line rather than being cut across.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      // Directional: `indent` is the leading edge, which is the right in RTL.
      indent: AppTokens.spaceLg + 21 + AppTokens.spaceMd,
      endIndent: AppTokens.spaceLg,
      color: GoTheme.of(context).border,
    );
  }
}

/// Canvas-coloured band separating two groups of rows.
class _GroupGutter extends StatelessWidget {
  const _GroupGutter({required this.go});

  final GoTheme go;

  @override
  Widget build(BuildContext context) {
    return Container(height: AppTokens.spaceSm, color: go.bg);
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet pieces
// ---------------------------------------------------------------------------

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
        decoration: BoxDecoration(
          color: GoTheme.of(context).border,
          borderRadius: BorderRadius.circular(AppTokens.radiusXs),
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final tint = destructive ? AppTokens.danger : go.text;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 21, color: tint),
            const SizedBox(width: AppTokens.spaceMd),
            Text(
              label,
              style: AppTokens.font(fontSize: 15, fontWeight: FontWeight.w600, color: tint),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../services/captain_state.dart';

/// Captain sign-in / join.
///
/// ## Why this screen specifies every colour locally
///
/// The previous version drew a **light** canvas (white card, `lightBg`
/// scaffold, `lightText`) but let its `TextFormField`s inherit
/// `inputDecorationTheme` from the ambient `ThemeData`. Because
/// `main.dart` runs `themeMode: state.themeMode`, a captain whose phone is
/// in dark mode got `AppTheme.dark()` — whose input `fillColor` is
/// `darkSurface` (#1E293B). Result: near-black navy fields sitting on a
/// white card, with `darkMuted` hint text that all but vanished. That is the
/// field-colour bug.
///
/// The fix is not to patch one colour. A screen whose palette is decided
/// half by itself and half by the ambient theme will drift again the next
/// time the theme moves. So this screen now:
///
///  * commits to a **dark canvas** end to end — matching the category
///    standard set by inDrive, where the auth screen is a dark stage and the
///    lime action is the only bright thing on it;
///  * declares `filled`, `fillColor`, all four border states, `hintStyle`
///    and `errorStyle` **inline on every field**, so nothing is inherited
///    and the render is identical whether the phone is in light or dark
///    mode.
///
/// ## Layout
///
/// Follows the reference: a hero area up top that pages between two slides
/// (dot indicators beneath), then the auth panel. The hero currently shows
/// the app icon as a deliberate placeholder — swap the artwork in
/// `_HeroSlide` for real illustrations when they are designed; nothing else
/// needs to change.
///
/// Validation behaviour, Egyptian `+20` phone rules and the enforced terms
/// checkbox are all preserved from the previous revision.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ── Palette ─────────────────────────────────────────────────────────
  // Pinned to the night scale so the screen cannot be repainted by the
  // ambient theme. These pins are exactly GoTheme's dark preset
  // (nightBg/nightPanel/nightSurface/nightBorder/nightText/nightMuted +
  // lime/onLime), so this screen already matches the design system's dark
  // appearance token-for-token; GoTheme is left to screens that follow the
  // ambient brightness, which this one deliberately does not.
  static const _bg = AppTokens.nightBg; // #0E0E10 page
  static const _panel = AppTokens.nightPanel; // #1A1A1D auth panel
  static const _fieldFill = AppTokens.nightSurface; // #26262B inputs
  static const _border = AppTokens.nightBorder; // #34343B hairlines
  static const _text = AppTokens.nightText; // #F5F5F7 body
  static const _muted = AppTokens.nightMuted; // #9A9AA2 hints
  static const _action = AppTokens.lime; // #C1F11D CTA
  static const _onAction = AppTokens.onLime; // #101010 on CTA

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  final _heroCtrl = PageController();
  int _heroPage = 0;

  bool _isSignUp = false;
  bool _acceptTerms = false;
  bool _obscurePass = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _heroCtrl.dispose();
    super.dispose();
  }

  void _setMode(bool signUp) {
    if (_isSignUp == signUp) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSignUp = signUp;
      // Clear validation state so switching modes does not surface errors
      // for fields the captain has not seen yet.
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_isSignUp && !_acceptTerms) {
      _toast('يجب الموافقة على شروط الانضمام أولاً', AppTokens.warning);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final state = context.read<CaptainState>();
      if (_isSignUp) {
        await state.registerWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
      } else {
        await state.loginWithEmail(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text,
        );
      }
    } catch (e) {
      if (mounted) {
        _toast(
            e.toString().replaceAll('Exception:', '').trim(), AppTokens.danger);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Light icons: this screen is a dark canvas, unconditionally.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _panel,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _buildTopBar()),
              SliverToBoxAdapter(child: _buildHero()),
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildAuthPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceMd,
        AppTokens.spaceXs,
        AppTokens.spaceMd,
        0,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: _LanguageChip(
          onTap: () {
            final state = context.read<CaptainState>();
            final next = state.locale.languageCode == 'ar'
                ? const Locale('en', 'US')
                : const Locale('ar', 'EG');
            state.setLocale(next);
          },
        ),
      ),
    );
  }

  // ── Hero carousel ───────────────────────────────────────────────────

  /// Two slides the captain can swipe between, with dot indicators beneath.
  ///
  /// The artwork slot is intentionally a placeholder: it renders the app
  /// icon inside a rounded lime-tinted stage. When real illustrations land,
  /// replace the artwork in `_HeroSlide` and delete the icon fallback.
  Widget _buildHero() {
    const slides = <_HeroCopy>[
      _HeroCopy(
        title: 'اكسب على طريقتك',
        body: 'اقبل الرحلات القريبة منك، وحدّد سعرك،\nواسحب أرباحك في أي وقت.',
      ),
      _HeroCopy(
        title: 'سلامتك هي أولويتنا',
        body: 'زر الطوارئ متاح في كل رحلة،\nوكل راكب موثّق قبل الحجز.',
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 296,
          child: PageView.builder(
            controller: _heroCtrl,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _heroPage = i),
            itemBuilder: (_, i) => _HeroSlide(copy: slides[i]),
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _DotIndicator(count: slides.length, active: _heroPage),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );
  }

  // ── Auth panel ──────────────────────────────────────────────────────

  Widget _buildAuthPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeSwitch(isSignUp: _isSignUp, onChanged: _setMode),
            const SizedBox(height: AppTokens.spaceLg),

            // Join-only identity fields.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _isSignUp
                  ? Column(
                      children: [
                        _field(
                          controller: _nameCtrl,
                          hint: 'الاسم بالكامل',
                          icon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().length < 3)
                              ? 'اكتب اسمك الكامل'
                              : null,
                        ),
                        const SizedBox(height: AppTokens.spaceMd),
                        _buildPhoneField(),
                        const SizedBox(height: AppTokens.spaceMd),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),

            _field(
              controller: _emailCtrl,
              hint: 'البريد الإلكتروني',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return 'أدخل بريدك الإلكتروني';
                final ok =
                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                return ok ? null : 'صيغة البريد غير صحيحة';
              },
            ),
            const SizedBox(height: AppTokens.spaceMd),

            _field(
              controller: _passCtrl,
              hint: 'كلمة السر',
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePass,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              suffix: IconButton(
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
                icon: Icon(
                  _obscurePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _muted,
                  size: 20,
                ),
                tooltip: _obscurePass ? 'إظهار كلمة السر' : 'إخفاء كلمة السر',
              ),
              validator: (v) {
                final value = v ?? '';
                if (value.isEmpty) return 'أدخل كلمة السر';
                if (_isSignUp && value.length < 6) {
                  return 'كلمة السر 6 أحرف على الأقل';
                }
                return null;
              },
            ),

            if (_isSignUp) ...[
              const SizedBox(height: AppTokens.spaceXs),
              _buildTermsRow(),
            ],

            const SizedBox(height: AppTokens.spaceLg),

            SizedBox(
              height: AppTokens.primaryActionHeight,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _action,
                  foregroundColor: _onAction,
                  disabledBackgroundColor: _fieldFill,
                  disabledForegroundColor: _muted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                  ),
                  textStyle: AppTokens.font(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: _onAction,
                          strokeWidth: 2.2,
                        ),
                      )
                    : Text(_isSignUp ? 'تقديم طلب الانضمام' : 'تسجيل الدخول'),
              ),
            ),

            const SizedBox(height: AppTokens.spaceLg),
            _buildDivider(),
            const SizedBox(height: AppTokens.spaceMd),
            _buildSocialRow(),
            const SizedBox(height: AppTokens.spaceLg),
            _buildFooterSwitch(),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsRow() {
    return InkWell(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _acceptTerms,
                activeColor: _action,
                checkColor: _onAction,
                side: const BorderSide(color: _border, width: 1.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                onChanged: (v) => setState(() => _acceptTerms = v ?? false),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Text(
                'أوافق على شروط وأحكام الانضمام ككابتن',
                style: AppTokens.font(fontSize: 13, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: _border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
          child: Text(
            'أو المتابعة بواسطة',
            style: AppTokens.font(fontSize: 12, color: _muted),
          ),
        ),
        const Expanded(child: Divider(color: _border, thickness: 1)),
      ],
    );
  }

  Widget _buildSocialRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialTile(
          icon: Icons.g_mobiledata_rounded,
          label: 'Google',
          onTap: () => _toast('تسجيل الدخول عبر Google قريباً', AppTokens.info),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        _SocialTile(
          icon: Icons.apple_rounded,
          label: 'Apple',
          onTap: () => _toast('تسجيل الدخول عبر Apple قريباً', AppTokens.info),
        ),
      ],
    );
  }

  Widget _buildFooterSwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _isSignUp ? 'لديك حساب بالفعل؟ ' : 'ليس لديك حساب؟ ',
          style: AppTokens.font(fontSize: 14, color: _muted),
        ),
        GestureDetector(
          onTap: () => _setMode(!_isSignUp),
          child: Text(
            _isSignUp ? 'تسجيل الدخول' : 'انضم ككابتن',
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _action,
            ),
          ),
        ),
      ],
    );
  }

  // ── Fields ──────────────────────────────────────────────────────────

  /// Every visual property is declared here rather than inherited, which is
  /// what keeps the fields from repainting themselves when the ambient
  /// `themeMode` changes.
  InputDecoration _decoration({
    required String hint,
    Widget? prefix,
    Widget? suffix,
    BoxConstraints? prefixConstraints,
  }) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: AppTokens.font(fontSize: 14, color: _muted),
      filled: true,
      fillColor: _fieldFill,
      prefixIcon: prefix,
      prefixIconConstraints: prefixConstraints,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: border(_border, 1),
      focusedBorder: border(_action, 1.8),
      errorBorder: border(AppTokens.danger, 1.4),
      focusedErrorBorder: border(AppTokens.danger, 1.8),
      disabledBorder: border(_border, 1),
      errorStyle: AppTokens.font(fontSize: 12, color: AppTokens.danger),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      cursorColor: _action,
      style: AppTokens.font(fontSize: 15, color: _text),
      decoration: _decoration(
        hint: hint,
        prefix: Icon(icon, color: _muted, size: 21),
        suffix: suffix,
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      cursorColor: _action,
      // Egyptian mobile numbers are 11 digits (01X XXXX XXXX). Anything
      // non-numeric is stripped at the source rather than rejected later.
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      validator: (v) {
        final value = (v ?? '').trim();
        if (value.isEmpty) return 'أدخل رقم هاتفك';
        if (!RegExp(r'^01[0125]\d{8}$').hasMatch(value)) {
          return 'رقم مصري غير صحيح (مثال: 01012345678)';
        }
        return null;
      },
      style: AppTokens.font(fontSize: 15, color: _text),
      decoration: _decoration(
        hint: '01012345678',
        prefixConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        prefix: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: AppTokens.spaceMd,
            end: AppTokens.spaceXs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🇪🇬', style: AppTokens.font(fontSize: 17)),
              const SizedBox(width: 6),
              Text(
                '+20',
                style: AppTokens.font(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Container(width: 1, height: 22, color: _border),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────

/// Copy for one hero slide.
class _HeroCopy {
  const _HeroCopy({required this.title, required this.body});

  final String title;
  final String body;
}

/// One page of the hero carousel.
///
/// The artwork is a **placeholder**: a lime-tinted rounded stage carrying the
/// app icon. Swap the `Image.asset` below for per-slide illustration assets
/// once they exist — the surrounding layout, sizing and dot indicator need no
/// changes.
class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.copy});

  final _HeroCopy copy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Artwork placeholder — reserved space for the real illustration.
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: AppTokens.lime.withOpacity(0.10),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: AppTokens.lime.withOpacity(0.22)),
            ),
            padding: const EdgeInsets.all(24),
            child: Image.asset(
              'assets/images/godrive_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.navigation_rounded,
                size: 52,
                color: AppTokens.lime,
              ),
            ),
          ).animate().scale(duration: 420.ms, curve: Curves.easeOutBack),

          const SizedBox(height: AppTokens.spaceLg),

          Text(
            copy.title,
            textAlign: TextAlign.center,
            style: AppTokens.font(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: AppTokens.nightText,
              height: 1.25,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            copy.body,
            textAlign: TextAlign.center,
            style: AppTokens.font(
              fontSize: 14,
              color: AppTokens.nightMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Page position for the hero carousel. The active dot stretches into a pill
/// so position reads at a glance rather than requiring a colour comparison.
class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppTokens.lime : AppTokens.nightBorder,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          ),
        );
      }),
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────

/// Explicit two-state control so the captain always knows whether they are
/// signing in or creating an account.
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.isSignUp, required this.onChanged});

  final bool isSignUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.nightBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: AppTokens.nightBorder),
      ),
      child: Row(
        children: [
          _segment('دخول', !isSignUp, () => onChanged(false)),
          _segment('انضمام', isSignUp, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppTokens.lime : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          ),
          child: Text(
            label,
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? AppTokens.onLime : AppTokens.nightMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSm),
        decoration: BoxDecoration(
          color: AppTokens.nightPanel,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(color: AppTokens.nightBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 17, color: AppTokens.lime),
            const SizedBox(width: 6),
            Text(
              isAr ? 'العربية' : 'English',
              style: AppTokens.font(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTokens.nightText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialTile extends StatelessWidget {
  const _SocialTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 24, color: AppTokens.nightText),
        label: Text(
          label,
          style: AppTokens.font(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTokens.nightText,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.tapTarget),
          backgroundColor: AppTokens.nightSurface,
          side: const BorderSide(color: AppTokens.nightBorder, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
    );
  }
}

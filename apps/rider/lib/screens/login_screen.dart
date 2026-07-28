import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../services/app_state.dart';

/// Rider sign-in / join — inDrive-style dark auth screen.
///
/// Redesigned from the plain light form to match the inDrive reference: a
/// dark stage with a hero carousel up top (two illustrated slides the rider
/// swipes between), then a rounded-top auth panel below. The rider's green
/// brand colour is the action accent on the dark canvas.
///
/// The hero illustrations are friendly character artwork (generated assets),
/// replacing the previous bare logo. Each slide carries a headline and a
/// supporting line; the dot indicator beneath tracks position.
///
/// All auth logic (validation, sign-in/sign-up toggle, terms checkbox) is
/// preserved from the previous revision — only the presentation changed.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ── Palette — pinned to the night scale so the screen cannot be
  // repainted by the ambient theme. Uses the rider's green as the action
  // colour (instead of the captain's lime).
  static const _bg = AppTokens.nightBg;
  static const _panel = AppTokens.nightPanel;
  static const _fieldFill = AppTokens.nightSurface;
  static const _border = AppTokens.nightBorder;
  static const _text = AppTokens.nightText;
  static const _muted = AppTokens.nightMuted;
  static const _action = AppTokens.primary; // rider green
  static const _onAction = Colors.white;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _heroCtrl = PageController();
  int _heroPage = 0;

  bool _signUpMode = false;
  bool _acceptedTerms = false;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _heroCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final strings = AppStrings.of(context);
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_signUpMode && !_acceptedTerms) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.loginMustAcceptTerms)),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      if (_signUpMode) {
        await state.register(
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await state.login(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final strings = AppStrings.of(context);
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
            final state = context.read<AppState>();
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

  Widget _buildHero() {
    final strings = AppStrings.of(context);

    final slides = <_HeroCopy>[
      _HeroCopy(
        title: strings.loginHeroSafetyTitle,
        body: strings.loginHeroSafetyBody,
        image: 'assets/images/login_hero_safety.png',
      ),
      _HeroCopy(
        title: strings.loginHeroPriceTitle,
        body: strings.loginHeroPriceBody,
        image: 'assets/images/login_hero_price.png',
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 300,
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
    final strings = AppStrings.of(context);

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
            _ModeSwitch(isSignUp: _signUpMode, onChanged: _setMode),
            const SizedBox(height: AppTokens.spaceLg),

            // Join-only identity fields.
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: _signUpMode
                  ? Column(
                      children: [
                        _field(
                          controller: _nameCtrl,
                          hint: strings.loginFullNameHint,
                          icon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().length < 3)
                              ? strings.loginEnterValidNamePhone
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
              hint: strings.loginEmailHint,
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.isEmpty) return strings.loginEnterEmailPassword;
                final ok =
                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
                return ok ? null : strings.loginEnterEmailPassword;
              },
            ),
            const SizedBox(height: AppTokens.spaceMd),

            _field(
              controller: _passwordCtrl,
              hint: strings.loginPasswordHint,
              icon: Icons.lock_outline_rounded,
              obscure: _obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              suffix: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _muted,
                  size: 20,
                ),
              ),
              validator: (v) {
                final value = v ?? '';
                if (value.isEmpty) return strings.loginEnterEmailPassword;
                if (_signUpMode && value.length < 6) {
                  return strings.loginEnterEmailPassword;
                }
                return null;
              },
            ),

            if (_signUpMode) ...[
              const SizedBox(height: AppTokens.spaceXs),
              _buildTermsRow(),
            ],

            const SizedBox(height: AppTokens.spaceLg),

            SizedBox(
              height: AppTokens.primaryActionHeight,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
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
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: _onAction,
                          strokeWidth: 2.2,
                        ),
                      )
                    : Text(_signUpMode
                        ? strings.loginCreateAccountAction
                        : strings.loginSignInAction),
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
    final strings = AppStrings.of(context);
    return InkWell(
      onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _acceptedTerms,
                activeColor: _action,
                checkColor: _onAction,
                side: const BorderSide(color: _border, width: 1.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Text(
                strings.loginTermsLabel,
                style: AppTokens.font(fontSize: 13, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final strings = AppStrings.of(context);
    return Row(
      children: [
        const Expanded(child: Divider(color: _border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
          child: Text(
            strings.loginOrContinueWith,
            style: AppTokens.font(fontSize: 12, color: _muted),
          ),
        ),
        const Expanded(child: Divider(color: _border, thickness: 1)),
      ],
    );
  }

  Widget _buildSocialRow() {
    final strings = AppStrings.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _SocialTile(
          icon: Icons.g_mobiledata_rounded,
          label: 'Google',
          onTap: () => _toast(strings.loginSocialComingSoon, AppTokens.info),
        ),
        const SizedBox(width: AppTokens.spaceMd),
        _SocialTile(
          icon: Icons.apple_rounded,
          label: 'Apple',
          onTap: () => _toast(strings.loginSocialComingSoon, AppTokens.info),
        ),
      ],
    );
  }

  Widget _buildFooterSwitch() {
    final strings = AppStrings.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _signUpMode ? strings.loginAlreadyHaveAccount : strings.loginNoAccount,
          style: AppTokens.font(fontSize: 14, color: _muted),
        ),
        GestureDetector(
          onTap: () => _setMode(!_signUpMode),
          child: Text(
            _signUpMode ? strings.loginSignInAction : strings.loginCreateAccountAction,
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

  void _setMode(bool signUp) {
    if (_signUpMode == signUp) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _signUpMode = signUp;
      _formKey.currentState?.reset();
    });
  }

  void _toast(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
  }

  // ── Fields ──────────────────────────────────────────────────────────

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
    final strings = AppStrings.of(context);
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      cursorColor: _action,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      validator: (v) {
        final value = (v ?? '').trim();
        if (value.isEmpty) return strings.loginEnterValidNamePhone;
        if (!RegExp(r'^01[0125]\d{8}$').hasMatch(value)) {
          return strings.loginEnterValidNamePhone;
        }
        return null;
      },
      style: AppTokens.font(fontSize: 15, color: _text),
      decoration: _decoration(
        hint: strings.loginPhoneHint,
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

class _HeroCopy {
  const _HeroCopy({
    required this.title,
    required this.body,
    required this.image,
  });

  final String title;
  final String body;
  final String image;
}

/// One page of the hero carousel — friendly illustrated artwork with
/// headline and supporting copy, matching the inDrive auth pattern.
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
          // Friendly illustrated artwork.
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              copy.image,
              width: 148,
              height: 148,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  color: AppTokens.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppTokens.primary.withOpacity(0.25),
                  ),
                ),
                child: const Icon(
                  Icons.navigation_rounded,
                  size: 52,
                  color: AppTokens.primary,
                ),
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

/// Page position indicator — active dot stretches into a pill.
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
            color: isActive ? AppTokens.primary : AppTokens.nightBorder,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          ),
        );
      }),
    );
  }
}

// ── Controls ──────────────────────────────────────────────────────────

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.isSignUp, required this.onChanged});

  final bool isSignUp;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTokens.nightBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: AppTokens.nightBorder),
      ),
      child: Row(
        children: [
          _segment(strings.loginSignInAction, !isSignUp, () => onChanged(false)),
          _segment(strings.loginSignUpAction, isSignUp, () => onChanged(true)),
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
            color: active ? AppTokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          ),
          child: Text(
            label,
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? Colors.white : AppTokens.nightMuted,
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
            const Icon(Icons.language_rounded, size: 17, color: AppTokens.primary),
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

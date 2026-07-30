import 'dart:async';

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
///
/// ## Motion
///
/// The screen used to arrive fully formed: a single `.animate().scale()` on the
/// hero illustration — and with flutter_animate's default `begin` of zero, so
/// the artwork popped out of nothing — plus three implicit animations on
/// controls the rider had to touch first. Nothing moved on entry, which made
/// the splash's carefully choreographed hand-off land on a static wall.
///
/// Now the page assembles itself: the top bar and hero settle in from above,
/// the auth panel rises from the bottom edge, and the panel's rows fade up on a
/// 70ms stagger. The hero also advances on its own so a rider who never swipes
/// still sees the second slide.
///
/// Two implementation notes worth keeping in mind when editing this file:
///
/// * Every entrance runs through [_entrance], which stamps a stable `ValueKey`
///   on the `Animate` wrapper. Toggling sign-in/sign-up inserts and removes
///   siblings in the panel's `Column`, and without a fixed identity Flutter
///   would rebuild those elements at their new indices and replay the entrance
///   every single time the rider flipped the mode.
/// * flutter_animate does not consult the platform's reduce-motion setting, so
///   [_reduceMotion] is checked before any effect is attached.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // ── Palette — resolved per-build from the active theme. The previous
  // revision pinned the night scale as `static const`, so a light-mode rider
  // still got the dark stage (and the status-bar icons stayed light-on-dark
  // even when the app was in light mode). Resolving from GoTheme keeps the
  // inDrive dark look in dark mode while giving light mode its own canvas.
  bool get _isDark => GoTheme.of(context).isDark;

  Color get _bg => _isDark ? AppTokens.nightBg : AppTokens.lightBg;
  Color get _panel => _isDark ? AppTokens.nightPanel : AppTokens.lightPanel;
  Color get _fieldFill => _isDark ? AppTokens.nightSurface : AppTokens.inputFill;
  Color get _border => _isDark ? AppTokens.nightBorder : AppTokens.lightBorder;
  Color get _text => _isDark ? AppTokens.nightText : AppTokens.lightText;
  Color get _muted => _isDark ? AppTokens.nightMuted : AppTokens.lightMuted;
  Color get _action => AppTokens.primary; // rider green
  Color get _onAction => Colors.white;

  /// Riders who asked the platform to limit animation get the page as it was:
  /// no entrance effects, no auto-advance, no press rebound.
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _heroCtrl = PageController();
  int _heroPage = 0;

  /// Kept as a constant rather than read off the per-build slide list, because
  /// the auto-advance timer fires outside of `build` and must not depend on it.
  static const int _heroSlideCount = 2;

  Timer? _heroTimer;

  bool _signUpMode = false;
  bool _acceptedTerms = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _submitPressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion) {
      _heroTimer?.cancel();
      _heroTimer = null;
    } else {
      _startHeroAutoAdvance();
    }
  }

  @override
  void dispose() {
    _heroTimer?.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _heroCtrl.dispose();
    super.dispose();
  }

  /// Advances the hero on a slow loop.
  ///
  /// Restarted on every page change so a manual swipe resets the dwell instead
  /// of being yanked onward a moment later, and skipped entirely while the
  /// keyboard is up — a rider filling in the form should not have artwork
  /// sliding around above their hands.
  void _startHeroAutoAdvance() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(const Duration(milliseconds: 4600), (_) {
      if (!mounted || !_heroCtrl.hasClients) return;
      if (MediaQuery.of(context).viewInsets.bottom > 0) return;
      _heroCtrl.animateToPage(
        (_heroPage + 1) % _heroSlideCount,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
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
    // Status-bar icons follow the active canvas: light icons on the dark
    // stage, dark icons on the light canvas.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            _isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: _isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: _panel,
        systemNavigationBarIconBrightness:
            _isDark ? Brightness.light : Brightness.dark,
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

  // ── Entrance choreography ───────────────────────────────────────────

  /// Wraps [child] in a keyed fade-and-rise.
  ///
  /// `step` is a beat index, not a millisecond value — the cascade stays even
  /// if rows are inserted or reordered later.
  Widget _entrance(Widget child, {required String id, required int step}) {
    if (_reduceMotion) return child;
    final delay = (180 + step * 70).ms;
    return child
        .animate(key: ValueKey('entrance-$id'))
        .fadeIn(delay: delay, duration: 420.ms)
        .slideY(
          begin: 0.14,
          end: 0,
          delay: delay,
          duration: 480.ms,
          curve: Curves.easeOutCubic,
        );
  }

  // ── Top bar ─────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final bar = Padding(
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

    if (_reduceMotion) return bar;
    return bar
        .animate(key: const ValueKey('entrance-topbar'))
        .fadeIn(duration: 380.ms);
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

    final hero = Column(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: _heroCtrl,
            itemCount: slides.length,
            onPageChanged: (i) {
              setState(() => _heroPage = i);
              // Reset the dwell so a manual swipe gets its full reading time.
              if (!_reduceMotion) _startHeroAutoAdvance();
            },
            itemBuilder: (_, i) => _HeroSlide(
              copy: slides[i],
              reduceMotion: _reduceMotion,
            ),
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _DotIndicator(count: slides.length, active: _heroPage),
        const SizedBox(height: AppTokens.spaceLg),
      ],
    );

    if (_reduceMotion) return hero;
    // Settles downward from just above its resting place, so the stage reads
    // top-down while the panel below comes up to meet it.
    return hero
        .animate(key: const ValueKey('entrance-hero'))
        .fadeIn(delay: 80.ms, duration: 460.ms)
        .slideY(
          begin: -0.06,
          end: 0,
          delay: 80.ms,
          duration: 540.ms,
          curve: Curves.easeOutCubic,
        );
  }

  // ── Auth panel ──────────────────────────────────────────────────────

  Widget _buildAuthPanel() {
    final strings = AppStrings.of(context);

    final panel = Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg,
        AppTokens.spaceLg + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _entrance(
              _ModeSwitch(isSignUp: _signUpMode, onChanged: _setMode),
              id: 'mode',
              step: 0,
            ),
            const SizedBox(height: AppTokens.spaceLg),

            // Join-only identity fields.
            AnimatedSize(
              duration: Duration(milliseconds: _reduceMotion ? 0 : 220),
              curve: Curves.easeOut,
              child: _signUpMode
                  ? _revealed(
                      Column(
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
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            _entrance(
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
              id: 'email',
              step: 1,
            ),
            const SizedBox(height: AppTokens.spaceMd),

            _entrance(
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
              id: 'password',
              step: 2,
            ),

            if (_signUpMode) ...[
              const SizedBox(height: AppTokens.spaceXs),
              _revealed(_buildTermsRow()),
            ],

            const SizedBox(height: AppTokens.spaceLg),

            _entrance(_buildSubmitButton(), id: 'submit', step: 3),

            const SizedBox(height: AppTokens.spaceLg),
            _entrance(_buildDivider(), id: 'divider', step: 4),
            const SizedBox(height: AppTokens.spaceMd),
            _entrance(_buildSocialRow(), id: 'social', step: 5),
            const SizedBox(height: AppTokens.spaceLg),
            _entrance(_buildFooterSwitch(), id: 'footer', step: 6),
          ],
        ),
      ),
    );

    if (_reduceMotion) return panel;
    // Slide only, no fade: the panel is an opaque surface and cross-fading it
    // against the stage behind would show the hero bleeding through. Rising
    // from just below the bottom edge reads as the sheet arriving.
    return panel
        .animate(key: const ValueKey('entrance-panel'))
        .slideY(
          begin: 0.05,
          end: 0,
          duration: 560.ms,
          curve: Curves.easeOutCubic,
        );
  }

  /// Fade for content revealed by the sign-up toggle.
  ///
  /// Unlike [_entrance] this is *meant* to replay — the widget really is newly
  /// shown each time, and `AnimatedSize` on its own would grow an already
  /// fully-opaque block into view.
  Widget _revealed(Widget child) {
    if (_reduceMotion) return child;
    return child.animate().fadeIn(duration: 260.ms, curve: Curves.easeOut);
  }

  Widget _buildSubmitButton() {
    final strings = AppStrings.of(context);

    final button = ElevatedButton(
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
      // Keyed by state so the label cross-fades when the rider flips mode and
      // when the request starts, instead of snapping between the two.
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: _reduceMotion ? 0 : 220),
        child: _busy
            ? SizedBox(
                key: const ValueKey('busy'),
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: _onAction,
                  strokeWidth: 2.2,
                ),
              )
            : Text(
                _signUpMode
                    ? strings.loginCreateAccountAction
                    : strings.loginSignInAction,
                key: ValueKey(_signUpMode ? 'signup' : 'signin'),
              ),
      ),
    );

    return SizedBox(
      height: AppTokens.primaryActionHeight,
      // Listener rather than GestureDetector: raw pointer events do not enter
      // the gesture arena, so the button keeps its own tap recognition and the
      // rebound can never be left stuck down by a lost arena contest.
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: _submitPressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: button,
        ),
      ),
    );
  }

  void _setPressed(bool pressed) {
    // Nothing to acknowledge while the button is disabled mid-request.
    if (_busy || _reduceMotion) return;
    if (_submitPressed == pressed) return;
    setState(() => _submitPressed = pressed);
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
                side: BorderSide(color: _border, width: 1.6),
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
        Expanded(child: Divider(color: _border, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
          child: Text(
            strings.loginOrContinueWith,
            style: AppTokens.font(fontSize: 12, color: _muted),
          ),
        ),
        Expanded(child: Divider(color: _border, thickness: 1)),
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
///
/// The copy animates alongside the artwork now. Because `PageView.builder`
/// constructs each page as it comes into range, this replays per slide — which
/// is what you want from a carousel: the new slide's words arrive with it.
class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.copy, required this.reduceMotion});

  final _HeroCopy copy;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final artwork = ClipRRect(
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
    );

    final title = Text(
      copy.title,
      textAlign: TextAlign.center,
      style: AppTokens.font(
        fontSize: 25,
        fontWeight: FontWeight.w900,
        color: GoTheme.of(context).text,
        height: 1.25,
      ),
    );

    final body = Text(
      copy.body,
      textAlign: TextAlign.center,
      style: AppTokens.font(
        fontSize: 14,
        color: GoTheme.of(context).muted,
        height: 1.6,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceLg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (reduceMotion)
            artwork
          else
            // Explicit begin. Left at flutter_animate's default the artwork
            // scaled up from zero, which popped rather than settled.
            artwork
                .animate()
                .fadeIn(duration: 340.ms)
                .scale(
                  begin: const Offset(0.92, 0.92),
                  end: const Offset(1, 1),
                  duration: 460.ms,
                  curve: Curves.easeOutBack,
                ),
          const SizedBox(height: AppTokens.spaceLg),
          if (reduceMotion) title else _copyIn(title, 120),
          const SizedBox(height: AppTokens.spaceXs),
          if (reduceMotion) body else _copyIn(body, 210),
        ],
      ),
    );
  }

  Widget _copyIn(Widget child, int delayMs) => child
      .animate()
      .fadeIn(delay: delayMs.ms, duration: 400.ms)
      .slideY(
        begin: 0.28,
        end: 0,
        delay: delayMs.ms,
        duration: 440.ms,
        curve: Curves.easeOutCubic,
      );
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
            color: isActive ? AppTokens.primary : GoTheme.of(context).border,
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
        color: GoTheme.of(context).bg,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        border: Border.all(color: GoTheme.of(context).border),
      ),
      child: Row(
        children: [
          _segment(context, strings.loginSignInAction, !isSignUp, () => onChanged(false)),
          _segment(context, strings.loginSignUpAction, isSignUp, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, bool active, VoidCallback onTap) {
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
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? Colors.white : GoTheme.of(context).muted,
            ),
            child: Text(label),
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
          color: GoTheme.of(context).panel,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(color: GoTheme.of(context).border),
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
                color: GoTheme.of(context).text,
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
        icon: Icon(icon, size: 24, color: GoTheme.of(context).text),
        label: Text(
          label,
          style: AppTokens.font(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: GoTheme.of(context).text,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.tapTarget),
          backgroundColor: GoTheme.of(context).surface,
          side: BorderSide(color: GoTheme.of(context).border, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../services/captain_state.dart';

/// Captain sign-in / join.
///
/// Reworked around three things the previous screen got wrong:
///
///  * **It could not tell you what was wrong.** Validation was a single
///    "enter an email and password" snackbar fired after the fact. Fields
///    now validate inline, on submit, next to the offending input.
///  * **The terms checkbox was decorative.** You could register without ever
///    ticking it. It is now enforced.
///  * **Sign-in and join were the same form with two extra boxes.** The mode
///    switch is now an explicit segmented control at the top, so the captain
///    always knows which action they are about to take.
///
/// Layout follows the category standard: a brand-tinted header that carries
/// the logo, then a white card that floats over it holding the form, so the
/// eye lands on the inputs rather than on decoration.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

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
        _toast(e.toString().replaceAll('Exception:', '').trim(), AppTokens.danger);
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
    // Dark icons: this screen is a light canvas.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTokens.lightBg,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            const _HeaderWash(),
            SafeArea(
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildFormCard(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceXs,
        AppTokens.spaceLg,
        AppTokens.spaceLg,
      ),
      child: Column(
        children: [
          Align(
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
          const SizedBox(height: AppTokens.spaceMd),
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppTokens.shadowFloating,
            ),
            padding: const EdgeInsets.all(14),
            child: Image.asset(
              'assets/images/godrive_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.navigation_rounded,
                size: 44,
                color: AppTokens.primary,
              ),
            ),
          ).animate().scale(duration: 450.ms, curve: Curves.easeOutBack),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            _isSignUp ? 'انضم ككابتن' : 'أهلاً بعودتك',
            style: AppTokens.font(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: AppTokens.lightText,
            ),
          ),
          const SizedBox(height: AppTokens.space2xs),
          Text(
            _isSignUp
                ? 'أنشئ حسابك وابدأ الكسب مع أسطول GoDrive'
                : 'سجّل دخولك لاستقبال الرحلات وتتبّع أرباحك',
            textAlign: TextAlign.center,
            style: AppTokens.font(fontSize: 14, color: AppTokens.lightMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(AppTokens.spaceMd, 0, AppTokens.spaceMd, 0),
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
        border: Border.all(color: AppTokens.lightBorder),
        boxShadow: AppTokens.shadowCard,
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
                final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
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
                  color: AppTokens.lightMuted,
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
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
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
            const SizedBox(height: AppTokens.spaceMd),
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
                activeColor: AppTokens.primary,
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
                style: AppTokens.font(fontSize: 13, color: AppTokens.lightMuted),
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
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
          child: Text(
            'أو المتابعة بواسطة',
            style: AppTokens.font(fontSize: 12, color: AppTokens.lightFaint),
          ),
        ),
        const Expanded(child: Divider()),
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
          style: AppTokens.font(fontSize: 14, color: AppTokens.lightMuted),
        ),
        GestureDetector(
          onTap: () => _setMode(!_isSignUp),
          child: Text(
            _isSignUp ? 'تسجيل الدخول' : 'انضم ككابتن',
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTokens.primary,
            ),
          ),
        ),
      ],
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
      style: AppTokens.font(fontSize: 15, color: AppTokens.lightText),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTokens.lightMuted, size: 21),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
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
      style: AppTokens.font(fontSize: 15, color: AppTokens.lightText),
      decoration: InputDecoration(
        hintText: '01012345678',
        prefixIcon: Padding(
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
                  color: AppTokens.lightText,
                ),
              ),
              const SizedBox(width: AppTokens.spaceXs),
              Container(width: 1, height: 22, color: AppTokens.lightBorder),
            ],
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

/// Soft brand wash behind the header, fading into the page background.
class _HeaderWash extends StatelessWidget {
  const _HeaderWash();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 320,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTokens.headerAccent, AppTokens.lightBg],
          ),
        ),
      ),
    );
  }
}

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
        color: AppTokens.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
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
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            boxShadow: active ? AppTokens.shadowCard : null,
          ),
          child: Text(
            label,
            style: AppTokens.font(
              fontSize: 14,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? AppTokens.primary : AppTokens.lightMuted,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTokens.radiusPill),
          border: Border.all(color: AppTokens.lightBorder),
          boxShadow: AppTokens.shadowCard,
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
                color: AppTokens.lightText,
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
        icon: Icon(icon, size: 24, color: AppTokens.lightText),
        label: Text(
          label,
          style: AppTokens.font(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTokens.lightText,
          ),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.tapTarget),
          side: const BorderSide(color: AppTokens.lightBorder),
        ),
      ),
    );
  }
}

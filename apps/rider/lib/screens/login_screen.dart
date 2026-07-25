import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';

import '../services/app_state.dart';

/// Sign-in / sign-up.
///
/// Reworked to follow the reference app's authentication feel: a calm brand
/// area up top, pill-shaped actions, and generous spacing. Beyond the visual
/// pass this fixes three real defects:
///  * the language chip was decorative — it looked tappable but did nothing
///  * the Google/Apple tiles were also inert, implying sign-in methods that
///    are not wired up
///  * every colour was hardcoded to the light palette, so the whole screen
///    was unreadable in dark mode
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isSignUp = false;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _acceptTerms = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool get _isArabic =>
      Localizations.localeOf(context).languageCode == 'ar';

  void _showMessage(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTokens.danger : null,
      ),
    );
  }

  Future<void> _submit() async {
    final isAr = _isArabic;
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    if (email.isEmpty || pass.isEmpty) {
      _showMessage(isAr
          ? 'برجاء إدخال البريد الإلكتروني وكلمة السر'
          : 'Please enter your email and password');
      return;
    }

    if (_isSignUp) {
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      if (name.length < 2 || phone.length < 6) {
        _showMessage(isAr
            ? 'أدخل الاسم ورقم هاتف صحيح لإنشاء الحساب'
            : 'Enter a valid name and phone number');
        return;
      }
      if (!_acceptTerms) {
        _showMessage(isAr
            ? 'يجب الموافقة على اتفاقية الاستخدام وسياسة الخصوصية'
            : 'You must accept the terms and privacy policy');
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      final appState = context.read<AppState>();
      if (_isSignUp) {
        await appState.registerWithEmail(
          email: email,
          password: pass,
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
      } else {
        await appState.loginWithEmail(email: email, password: pass);
      }
    } catch (e) {
      if (mounted) {
        _showMessage(e.toString().replaceAll('Exception:', '').trim());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final appState = context.watch<AppState>();
    final isAr = _isArabic;

    return Scaffold(
      backgroundColor: go.bg,
      body: Stack(
        children: [
          // Soft brand wash behind the logo. Kept very low contrast so it
          // reads as atmosphere rather than a shape competing for attention.
          Positioned(
            top: -80,
            left: -70,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: go.isDark
                    ? go.action.withOpacity(0.07)
                    : AppTokens.headerAccent,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ChipButton(
                        go: go,
                        icon: appState.themeMode == ThemeMode.dark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        onTap: appState.toggleTheme,
                      ),
                      const SizedBox(width: 8),
                      _ChipButton(
                        go: go,
                        icon: Icons.language_rounded,
                        label: isAr ? 'EN' : 'ع',
                        onTap: appState.toggleLanguage,
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Column(
                      children: [
                        const SizedBox(height: 8),

                        Image.asset(
                          'assets/images/godrive_logo.png',
                          width: 92,
                          height: 92,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.navigation_rounded,
                            size: 64,
                            color: go.isDark ? go.action : AppTokens.primary,
                          ),
                        ).animate().fadeIn(duration: 400.ms).scale(
                              begin: const Offset(0.9, 0.9),
                              end: const Offset(1, 1),
                              duration: 500.ms,
                              curve: Curves.easeOutBack,
                            ),

                        const SizedBox(height: 18),

                        Text(
                          _isSignUp
                              ? (isAr ? 'أنشئ حسابك الجديد' : 'Create your account')
                              : (isAr ? 'مرحباً بك مجدداً' : 'Welcome back'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            color: go.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isSignUp
                              ? (isAr
                                  ? 'سجّل بياناتك للبدء في استخدام GoDrive'
                                  : 'Sign up to start riding with GoDrive')
                              : (isAr
                                  ? 'سجّل دخولك لمتابعة رحلاتك'
                                  : 'Sign in to continue your trips'),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 14,
                            color: go.muted,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 28),

                        if (_isSignUp) ...[
                          _Field(
                            go: go,
                            controller: _nameCtrl,
                            hint: isAr ? 'الاسم بالكامل' : 'Full name',
                            icon: Icons.person_outline_rounded,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 13),
                          _PhoneField(
                            go: go,
                            controller: _phoneCtrl,
                            hint: isAr ? 'رقم الهاتف المحمول' : 'Mobile number',
                          ),
                          const SizedBox(height: 13),
                        ],

                        _Field(
                          go: go,
                          controller: _emailCtrl,
                          hint: isAr ? 'البريد الإلكتروني' : 'Email address',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 13),

                        _Field(
                          go: go,
                          controller: _passCtrl,
                          hint: isAr ? 'كلمة السر' : 'Password',
                          icon: Icons.lock_outline_rounded,
                          obscure: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              color: go.muted,
                              size: 20,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),

                        if (_isSignUp) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Checkbox(
                                value: _acceptTerms,
                                activeColor:
                                    go.isDark ? go.action : AppTokens.primary,
                                checkColor: go.isDark ? go.onAction : Colors.white,
                                side: BorderSide(color: go.border, width: 1.5),
                                onChanged: (val) =>
                                    setState(() => _acceptTerms = val ?? false),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _acceptTerms = !_acceptTerms,
                                  ),
                                  child: Text(
                                    isAr
                                        ? 'أوافق على اتفاقية الاستخدام وسياسة الخصوصية'
                                        : 'I agree to the Terms of Use and Privacy Policy',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 12.5,
                                      color: go.muted,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 22),

                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: go.action,
                              foregroundColor: go.onAction,
                              disabledBackgroundColor: go.surface,
                              minimumSize: const Size.fromHeight(54),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTokens.radiusPill),
                              ),
                            ),
                            child: _isLoading
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: go.onAction,
                                      strokeWidth: 2.4,
                                    ),
                                  )
                                : Text(
                                    _isSignUp
                                        ? (isAr ? 'إنشاء حساب' : 'Create account')
                                        : (isAr ? 'تسجيل الدخول' : 'Sign in'),
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 26),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSignUp
                                  ? (isAr ? 'لديك حساب بالفعل؟ ' : 'Already have an account? ')
                                  : (isAr ? 'ليس لديك حساب؟ ' : "Don't have an account? "),
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 14,
                                color: go.muted,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() {
                                _isSignUp = !_isSignUp;
                                _acceptTerms = false;
                              }),
                              child: Text(
                                _isSignUp
                                    ? (isAr ? 'تسجيل الدخول' : 'Sign in')
                                    : (isAr ? 'إنشاء حساب جديد' : 'Sign up'),
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: go.isDark ? go.action : AppTokens.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.go,
    required this.icon,
    required this.onTap,
    this.label,
  });

  final GoTheme go;
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: go.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusPill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        onTap: onTap,
        child: Container(
          height: 38,
          padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            border: Border.all(color: go.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: go.text),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: GoogleFonts.ibmPlexSansArabic(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: go.text,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.go,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.onSubmitted,
    this.suffix,
  });

  final GoTheme go;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: GoogleFonts.ibmPlexSansArabic(
        color: go.text,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.ibmPlexSansArabic(color: go.muted, fontSize: 14),
        prefixIcon: Icon(icon, color: go.muted, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: go.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide(color: go.action, width: 1.5),
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.go,
    required this.controller,
    required this.hint,
  });

  final GoTheme go;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text(
            '🇪🇬 +20',
            style: GoogleFonts.ibmPlexSansArabic(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: go.text,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 22, color: go.border),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.ibmPlexSansArabic(
                color: go.text,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: GoogleFonts.ibmPlexSansArabic(
                  color: go.muted,
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 17),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

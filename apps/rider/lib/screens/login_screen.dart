import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../services/app_state.dart';

/// Sign-in / sign-up gate.
///
/// One screen with two modes: existing riders sign in with email + password,
/// new riders flip into the account-creation form (name + phone + terms).
/// The mode toggle drives the title, subtitle and primary action through
/// [AppStrings]; every label that was previously hardcoded Arabic now follows
/// the active locale.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

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
      // On success the app shell swaps this screen out itself — no route
      // pushing here.
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
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      backgroundColor: go.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.spaceLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/images/godrive_logo.png',
                        width: 96,
                        height: 96,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTokens.primary,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    Text(
                      _signUpMode
                          ? strings.loginCreateAccountTitle
                          : strings.loginWelcomeBackTitle,
                      textAlign: TextAlign.center,
                      style: AppTokens.font(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                      ),
                    ),
                    const SizedBox(height: AppTokens.space2xs),
                    Text(
                      _signUpMode
                          ? strings.loginSignUpSubtitle
                          : strings.loginSignInSubtitle,
                      textAlign: TextAlign.center,
                      style: AppTokens.font(fontSize: 14, color: go.muted),
                    ),
                    const SizedBox(height: AppTokens.spaceLg),
                    if (_signUpMode) ...[
                      TextFormField(
                        controller: _nameCtrl,
                        style: AppTokens.font(color: go.text),
                        decoration: InputDecoration(
                          hintText: strings.loginFullNameHint,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 3)
                                ? strings.loginEnterValidNamePhone
                                : null,
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        style: AppTokens.font(color: go.text),
                        decoration: InputDecoration(
                          hintText: strings.loginPhoneHint,
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().length < 10)
                                ? strings.loginEnterValidNamePhone
                                : null,
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                    ],
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      style: AppTokens.font(color: go.text),
                      decoration: InputDecoration(
                        hintText: strings.loginEmailHint,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@'))
                              ? strings.loginEnterEmailPassword
                              : null,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      style: AppTokens.font(color: go.text),
                      decoration: InputDecoration(
                        hintText: strings.loginPasswordHint,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.length < 6)
                              ? strings.loginEnterEmailPassword
                              : null,
                    ),
                    if (_signUpMode) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      Row(
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            activeColor: AppTokens.primary,
                            onChanged: (v) => setState(
                              () => _acceptedTerms = v ?? false,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              strings.loginTermsLabel,
                              style: AppTokens.font(
                                fontSize: 13,
                                color: go.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppTokens.spaceLg),
                    Semantics(
                      label: _signUpMode
                          ? strings.loginSignUpAction
                          : strings.loginSignInAction,
                      button: true,
                      child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTokens.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTokens.radiusMd,
                            ),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _signUpMode
                                    ? strings.loginCreateAccountAction
                                    : strings.loginSignInAction,
                                style: AppTokens.font(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                                () => _signUpMode = !_signUpMode,
                              ),
                      child: Text(
                        _signUpMode
                            ? strings.loginAlreadyHaveAccount
                            : strings.loginNoAccount,
                        style: AppTokens.font(
                          fontWeight: FontWeight.w600,
                          color: AppTokens.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

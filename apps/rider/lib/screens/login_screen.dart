import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../services/app_state.dart';

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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برجاء ادخال البريد الالكتروني وكلمة السر')),
      );
      return;
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
        await appState.loginWithEmail(
          email: email,
          password: pass,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppTokens.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top Left Decorative Green Curve (Matching input_file_0.png)
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppTokens.headerAccent,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Action Bar — Language Switcher
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.language, size: 18, color: AppTokens.primary),
                          const SizedBox(width: 4),
                          Text(
                            'AR',
                            style: GoogleFonts.ibmPlexSansArabic(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTokens.lightText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 12),

                        // Center Logo (GoDrive)
                        Image.asset(
                          'assets/images/godrive_logo.png',
                          width: 100,
                          height: 100,
                          fit: BoxFit.contain,
                        ).animate().scale(duration: 500.ms),

                        const SizedBox(height: 16),

                        // Title & Subtitle (Matching input_file_0.png)
                        Text(
                          _isSignUp ? 'أنشئ حسابك الجديد' : 'مرحباً بك مجدداً',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTokens.lightText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isSignUp ? 'قم بإنشاء حسابك للمتابعة والبدء' : 'سجل دخولك لمتابعة رحلاتك',
                          style: GoogleFonts.ibmPlexSansArabic(
                            fontSize: 14,
                            color: AppTokens.lightMuted,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Input Form
                        if (_isSignUp) ...[
                          _buildTextField(
                            controller: _nameCtrl,
                            hint: 'الاسم بالكامل',
                            icon: Icons.person_outline,
                          ),
                          const SizedBox(height: 16),
                          _buildPhoneField(),
                          const SizedBox(height: 16),
                        ],

                        _buildTextField(
                          controller: _emailCtrl,
                          hint: 'البريد الإلكتروني',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        _buildTextField(
                          controller: _passCtrl,
                          hint: 'كلمة السر',
                          icon: Icons.lock_outline,
                          obscure: true,
                        ),

                        if (_isSignUp) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Checkbox(
                                value: _acceptTerms,
                                activeColor: AppTokens.primary,
                                onChanged: (val) => setState(() => _acceptTerms = val ?? false),
                              ),
                              Expanded(
                                child: Text(
                                  'أوافق على اتفاقية الاستخدام وسياسة الخصوصية',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 12,
                                    color: AppTokens.lightMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Submit Button (Primary Green)
                        ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTokens.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  _isSignUp ? 'إنشاء حساب' : 'تسجيل الدخول',
                                  style: GoogleFonts.ibmPlexSansArabic(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),

                        const SizedBox(height: 28),

                        // Social Divider
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'أو المتابعة بواسطة',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontSize: 12,
                                  color: AppTokens.lightMuted,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Google & Apple Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildSocialTile(Icons.g_mobiledata, Colors.red),
                            const SizedBox(width: 16),
                            _buildSocialTile(Icons.apple, Colors.black),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Toggle Footer
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isSignUp ? 'لديك حساب بالفعل؟ ' : 'ليس لديك حساب؟ ',
                              style: GoogleFonts.ibmPlexSansArabic(
                                fontSize: 14,
                                color: AppTokens.lightMuted,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _isSignUp = !_isSignUp),
                              child: Text(
                                _isSignUp ? 'تسجيل الدخول' : 'إنشاء حساب جديد',
                                style: GoogleFonts.ibmPlexSansArabic(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppTokens.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTokens.lightText, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTokens.lightMuted),
        filled: true,
        fillColor: AppTokens.inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.inputFill,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Row(
            children: [
              Text('🇪🇬 +20', style: GoogleFonts.ibmPlexSansArabic(fontWeight: FontWeight.bold, fontSize: 14)),
              const Icon(Icons.arrow_drop_down, color: AppTokens.lightMuted),
            ],
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: AppTokens.lightBorder),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppTokens.lightText, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'رقم الهاتف المحمول',
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

  Widget _buildSocialTile(IconData icon, Color color) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppTokens.headerAccent.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

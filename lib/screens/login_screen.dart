import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import '../widgets/glass_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isLogin = true;
  String _errorMessage = '';

  // Registration-only fields
  String? _selectedDept;
  String? _selectedBatch;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Login failed: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDept == null || _selectedDept!.isEmpty) {
      setState(() => _errorMessage = 'Please select your department.');
      return;
    }
    if (_selectedBatch == null || _selectedBatch!.isEmpty) {
      setState(() => _errorMessage = 'Please select your batch.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.registerWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text.trim(),
        _nameController.text.trim(),
        _studentIdController.text.trim(),
        _selectedBatch!,
        _selectedDept!,
        _phoneController.text.trim(),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Registration failed: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_emailController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email to reset password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.sendPasswordResetEmail(_emailController.text.trim());
      setState(() {
        _errorMessage = 'Password reset email sent! Check your inbox.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppGradients.mainBackground),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: GlassCard(
                padding: const EdgeInsets.all(32),
                margin: const EdgeInsets.symmetric(horizontal: 0),
                opacity: 0.25,
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.25),
                                blurRadius: 40,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logo.png',
                            height: 72,
                          ),
                        ),
                      ).animate().fade(duration: 800.ms).scale(delay: 100.ms, curve: Curves.easeOutBack),
                      const SizedBox(height: 24),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            AppColors.secondary,
                            AppColors.primary,
                            const Color(0xFF1D4ED8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: Text(
                          'UniGrid',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ).animate().fade(delay: 200.ms, duration: 600.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
                      const SizedBox(height: 8),
                      Text(
                        _isLogin
                            ? 'Login to your student account'
                            : 'Create your academic profile',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ).animate().fade(delay: 350.ms, duration: 600.ms).slideY(begin: 0.15, end: 0, curve: Curves.easeOutQuad),
                      const SizedBox(height: 40),
                      if (_errorMessage.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.5)),
                          ),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Registration-only fields ─────────────────────────
                      if (!_isLogin) ...[
                        _buildTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          icon: Icons.person_outline,
                          validator: (value) =>
                              value!.isEmpty ? 'Enter your name' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _studentIdController,
                          label: 'Student ID',
                          icon: Icons.badge_outlined,
                          validator: (value) =>
                              value!.isEmpty ? 'Enter your Student ID' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          controller: _phoneController,
                          label: 'Contact Number',
                          icon: Icons.phone_outlined,
                          validator: (value) =>
                              value!.isEmpty ? 'Enter your contact number' : null,
                        ),
                        const SizedBox(height: 16),

                        // Department Dropdown
                        _buildDropdownField(
                          value: _selectedDept,
                          label: 'Department',
                          icon: Icons.account_balance_outlined,
                          items: kDepartments
                              .map((d) => DropdownMenuItem<String>(
                                    value: d['code'],
                                    child: Text(
                                      '${d['code']} — ${d['name']}',
                                      style: TextStyle(
                                          color: AppColors.textPrimary, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedDept = v),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Select your department'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // Batch Dropdown
                        _buildDropdownField<String>(
                          value: _selectedBatch,
                          label: 'Batch',
                          icon: Icons.groups_outlined,
                          items: kBatches
                              .map((b) => DropdownMenuItem<String>(
                                    value: b,
                                    child: Text(
                                      'Batch $b',
                                      style:
                                          TextStyle(color: AppColors.textPrimary),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedBatch = v),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Select your batch'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Common fields ─────────────────────────────────────
                      _buildTextField(
                        controller: _emailController,
                        label: 'University Email',
                        icon: Icons.email_outlined,
                        validator: (value) =>
                            value!.isEmpty ? 'Enter an email' : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _passwordController,
                        label: 'Password',
                        icon: Icons.lock_outline,
                        isPassword: true,
                        validator: (value) =>
                            value!.isEmpty ? 'Enter a password' : null,
                      ),
                      if (_isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed:
                                _isLoading ? null : _handleForgotPassword,
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                  color: AppColors.textSecondary, fontSize: 14),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : (_isLogin ? _handleLogin : _handleRegister),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor: AppColors.primary.withOpacity(0.5),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: AppColors.onPrimary, strokeWidth: 2),
                              )
                            : Text(
                                _isLogin ? 'Login' : 'Create Account',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                  _errorMessage = '';
                                  _selectedDept = null;
                                  _selectedBatch = null;
                                });
                              },
                        child: Text(
                          _isLogin
                              ? 'New here? Create an account'
                              : 'Already have an account? Sign in',
                          style: TextStyle(
                              fontSize: 16, color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                              child:
                                  Divider(color: AppColors.glassCardBorder, thickness: 1)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Or continue with',
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontSize: 13)),
                          ),
                          Expanded(
                              child:
                                  Divider(color: AppColors.glassCardBorder, thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        onTap: _isLoading
                            ? null
                            : () async {
                                setState(() {
                                  _isLoading = true;
                                  _errorMessage = '';
                                });
                                try {
                                  final authService = Provider.of<AuthService>(
                                      context,
                                      listen: false);
                                  await authService.signInWithGoogle();
                                } catch (e) {
                                  setState(() {
                                    _errorMessage = e
                                        .toString()
                                        .replaceAll('Exception: ', '');
                                  });
                                } finally {
                                  if (mounted) {
                                    setState(() {
                                      _isLoading = false;
                                    });
                                  }
                                }
                              },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.textPrimary.withOpacity(0.08)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.g_mobiledata,
                                  color: Colors.redAccent, size: 28),
                              SizedBox(width: 10),
                              Text(
                                'Continue with Google',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
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
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.textPrimary.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      validator: validator,
    );
  }

  Widget _buildDropdownField<T>({
    required T? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      dropdownColor: AppColors.backgroundTop,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.textPrimary.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import '../utils/dept_scope.dart';
import 'glass_card.dart';

class DeptSetupGuard extends StatefulWidget {
  final Widget child;

  const DeptSetupGuard({super.key, required this.child});

  @override
  State<DeptSetupGuard> createState() => _DeptSetupGuardState();
}

class _DeptSetupGuardState extends State<DeptSetupGuard> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  String? _selectedDept;
  String? _selectedBatch;
  bool _isSaving = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AppUser?>(context);

    // If no user, or user already has department & batch setup, proceed to child
    if (user == null || user.hasDeptScope) {
      return widget.child;
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.mainBackground,
        ),
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: GlassCard(
                  padding: const EdgeInsets.all(24.0),
                  borderRadius: 24,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          height: 64,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Complete Your Profile',
                          style: AppStyles.heading2,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Please select your Department and Batch to configure your UniGrid workspace.',
                          style: AppStyles.caption,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (_errorMessage.isNotEmpty) ...[
                          Text(
                            _errorMessage,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Department Dropdown
                        DropdownButtonFormField<String>(
                          value: _selectedDept,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Department',
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            prefixIcon: Icon(Icons.business,
                                color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.textPrimary.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: AppColors.glassCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: AppColors.glassCardBorder
                                      .withOpacity(0.5)),
                            ),
                          ),
                          dropdownColor: AppColors.glassCardColor,
                          items: kDepartments.map((dept) {
                            return DropdownMenuItem<String>(
                              value: dept['code'],
                              child: Text(
                                '${dept['code']} - ${dept['name']}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14, color: AppColors.textPrimary),
                              ),
                            );
                          }).toList(),
                          validator: (value) =>
                              value == null ? 'Select your department' : null,
                          onChanged: (val) {
                            setState(() {
                              _selectedDept = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        // Batch Dropdown
                        DropdownButtonFormField<String>(
                          value: _selectedBatch,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Batch',
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            prefixIcon:
                                Icon(Icons.group, color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.textPrimary.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: AppColors.glassCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: AppColors.glassCardBorder
                                      .withOpacity(0.5)),
                            ),
                          ),
                          dropdownColor: AppColors.glassCardColor,
                          items: kBatches.map((batch) {
                            return DropdownMenuItem<String>(
                              value: batch,
                              child: Text(
                                'Batch $batch',
                                style: TextStyle(color: AppColors.textPrimary),
                              ),
                            );
                          }).toList(),
                          validator: (value) =>
                              value == null ? 'Select your batch' : null,
                          onChanged: (val) {
                            setState(() {
                              _selectedBatch = val;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        // Contact Number Field
                        TextFormField(
                          controller: _phoneController,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Contact Number',
                            labelStyle: TextStyle(color: AppColors.textSecondary),
                            prefixIcon: Icon(Icons.phone_outlined,
                                color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.textPrimary.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: AppColors.glassCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: AppColors.glassCardBorder
                                      .withOpacity(0.5)),
                            ),
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? 'Enter your contact number'
                              : null,
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveProfile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isSaving
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : const Text(
                                  'Save & Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: _isSaving
                              ? null
                              : () async {
                                  try {
                                    final authService = Provider.of<AuthService>(
                                        context,
                                        listen: false);
                                    await authService.signOut();
                                  } catch (e) {
                                    setState(() {
                                      _errorMessage = 'Failed to sign out: ${e.toString()}';
                                    });
                                  }
                                },
                          child: Text(
                            'Go Back / Sign Out',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = '';
    });
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.updateUserProfile(
        department: _selectedDept,
        batch: _selectedBatch,
        phoneNumber: _phoneController.text.trim(),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to update profile: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

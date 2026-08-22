import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';
import 'glass_card.dart';

/// Wraps the main application tree to enforce:
/// 1. Emergency Maintenance Mode (blocks regular users, lets Root Admins pass)
/// 2. Force App Update Prompt (if installed version < minimum required version)
class MaintenanceGuard extends StatelessWidget {
  final Widget child;
  static const String currentAppVersion = '1.0.0';

  const MaintenanceGuard({super.key, required this.child});

  static bool _isVersionOutdated(String current, String required) {
    try {
      final curParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final reqParts = required.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      while (curParts.length < 3) {
        curParts.add(0);
      }
      while (reqParts.length < 3) {
        reqParts.add(0);
      }
      for (int i = 0; i < 3; i++) {
        if (curParts[i] < reqParts[i]) return true;
        if (curParts[i] > reqParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    final uri = Uri.parse('mailto:support.unigrid@gmail.com?subject=Urgent%20Query%20-%20UniGrid%20Maintenance');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (_) {
      Clipboard.setData(const ClipboardData(text: 'support.unigrid@gmail.com'));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email copied to clipboard: support.unigrid@gmail.com'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('system')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final bool isMaintenanceActive = data['maintenanceMode'] == true;
        final String maintenanceMsg = (data['maintenanceMessage'] ?? '').toString().trim();
        final String minVersion = (data['minAppVersion'] ?? '1.0.0').toString().trim();

        final user = Provider.of<AppUser?>(context);
        final authService = Provider.of<AuthService>(context, listen: false);
        final bool isRootAdmin = user != null &&
            (user.isAdmin || authService.isRootAdmin(user.email));

        // 1. Root Admins always bypass maintenance mode so they can manage the platform
        if (isMaintenanceActive && !isRootAdmin) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: AppGradients.mainBackground,
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: GlassCard(
                      padding: const EdgeInsets.all(26),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.amberAccent.withOpacity(0.35), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.amberAccent.withOpacity(0.2),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.engineering_rounded,
                              color: Colors.amberAccent,
                              size: 46,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'We\'ll Be Right Back!',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            maintenanceMsg.isNotEmpty
                                ? maintenanceMsg
                                : 'We sincerely apologize for the temporary inconvenience! UniGrid is currently undergoing essential scheduled maintenance and system performance upgrades.',
                            style: TextStyle(
                              color: AppColors.textPrimary.withOpacity(0.9),
                              fontSize: 13.5,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Please allow us a little time as our team completes these improvements. Everything will be back up and running smoothly very soon. We deeply appreciate your patience!',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),

                          // Urgent Support / Contact Box
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.support_agent_rounded, color: AppColors.primary, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Need Urgent Assistance?',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'If you have an urgent inquiry or concern, please contact our team directly:',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 10),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _launchEmail(context),
                                    onLongPress: () {
                                      Clipboard.setData(const ClipboardData(text: 'support.unigrid@gmail.com'));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Email copied to clipboard: support.unigrid@gmail.com'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.primary.withOpacity(0.65), width: 1.2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.primary.withOpacity(0.25),
                                            blurRadius: 10,
                                            spreadRadius: 0.5,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.email_outlined, color: AppColors.primary, size: 16),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'support.unigrid@gmail.com',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(Icons.open_in_new_rounded, color: AppColors.primary.withOpacity(0.8), size: 13),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_clock_rounded, color: AppColors.textSecondary, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Admins Retain Access',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
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

        // 2. Force App Update Check
        final bool isOutdated = _isVersionOutdated(currentAppVersion, minVersion);
        if (isOutdated && !isRootAdmin) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(gradient: AppGradients.mainBackground),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: GlassCard(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.system_update_rounded, color: Colors.blueAccent, size: 48),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Update Required',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'A new version (v$minVersion) of UniGrid is available on Google Play. Please update to continue using the app.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return child;
      },
    );
  }
}

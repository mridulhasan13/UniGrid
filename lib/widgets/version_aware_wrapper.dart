import '../utils/constants.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ota_update/ota_update.dart';

class VersionAwareWrapper extends StatefulWidget {
  final Widget child;
  const VersionAwareWrapper({super.key, required this.child});

  @override
  State<VersionAwareWrapper> createState() => _VersionAwareWrapperState();
}

class _VersionAwareWrapperState extends State<VersionAwareWrapper> {
  bool _needsUpdate = false;
  bool _optionalUpdateAvailable = false;
  bool _dismissedOptionalUpdate = false;
  String _downloadUrl = '';
  String _latestVersion = '';
  bool _isChecking = true;
  bool _isDownloading = false;
  String _downloadStatus = '';
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // Listen to Firestore for live updates
      FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('app_update')
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists || !mounted) {
          if (_isChecking) setState(() => _isChecking = false);
          return;
        }

        final data = snapshot.data()!;
        final latestBuildNumber = data['latestBuildNumber'] as int? ?? 0;
        final downloadUrl = data['downloadUrl'] as String? ?? '';
        final latestVersion = data['latestVersion'] as String? ?? '';
        final forceUpdate = data['forceUpdate'] as bool? ?? false;

        if (latestBuildNumber > currentBuildNumber && downloadUrl.isNotEmpty) {
          if (forceUpdate) {
            setState(() {
              _needsUpdate = true;
              _optionalUpdateAvailable = false;
              _downloadUrl = downloadUrl;
              _latestVersion = latestVersion;
              _isChecking = false;
            });
          } else {
            setState(() {
              _needsUpdate = false;
              _optionalUpdateAvailable = true;
              _downloadUrl = downloadUrl;
              _latestVersion = latestVersion;
              _isChecking = false;
            });
          }
        } else {
          setState(() {
            _needsUpdate = false;
            _optionalUpdateAvailable = false;
            _isChecking = false;
          });
        }
      }, onError: (e) {
        debugPrint(
            'Update check listener failed (expected if unauthenticated): $e');
        if (mounted) {
          setState(() {
            _needsUpdate = false;
            _optionalUpdateAvailable = false;
            _isChecking = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Update check failed: $e');
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _startOtaUpdate() async {
    setState(() {
      _isDownloading = true;
      _downloadStatus = 'Downloading update...';
      _downloadProgress = 0.0;
    });

    try {
      OtaUpdate()
          .execute(
        _downloadUrl,
        destinationFilename: 'unigrid_app_update.apk',
      )
          .listen(
        (OtaEvent event) {
          setState(() {
            switch (event.status) {
              case OtaStatus.DOWNLOADING:
                if (event.value != null && event.value!.isNotEmpty) {
                  final progress = double.tryParse(event.value!);
                  if (progress != null) {
                    _downloadProgress = progress / 100.0;
                    _downloadStatus = 'Downloading... ${event.value}%';
                  }
                }
                break;
              case OtaStatus.INSTALLING:
                _downloadStatus = 'Installing...';
                break;
              case OtaStatus.ALREADY_RUNNING_ERROR:
                _downloadStatus = 'Download already running.';
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _isDownloading = false;
                _downloadStatus = 'Storage permission denied.';
                break;
              case OtaStatus.CANCELED:
              case OtaStatus.INTERNAL_ERROR:
              case OtaStatus.DOWNLOAD_ERROR:
              case OtaStatus.CHECKSUM_ERROR:
                _isDownloading = false;
                _downloadStatus = 'Update failed or canceled. Tap to retry.';
                break;
            }
          });
        },
        onError: (error) {
          debugPrint('OTA error: $error');
          setState(() {
            _isDownloading = false;
            _downloadStatus = 'Failed to update. Try again.';
          });
        },
      );
    } catch (e) {
      debugPrint('Failed to make OTA update. Details: $e');
      setState(() {
        _isDownloading = false;
        _downloadStatus = 'Failed to start download.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        // Un-dismissible blur overlay if update is needed
        if (_needsUpdate)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 32),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2C),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: AppColors.textPrimary.withOpacity(0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.system_update_rounded,
                              color: Colors.blueAccent,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Update Required',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'A new version ($_latestVersion) of the UniGrid App is available. Please update to continue using the app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textPrimary.withOpacity(0.7),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (_isDownloading) ...[
                            Text(
                              _downloadStatus,
                              style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0
                                    ? _downloadProgress
                                    : null,
                                backgroundColor: AppColors.glassCardBorder,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.blueAccent),
                                minHeight: 8,
                              ),
                            ),
                          ] else ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _startOtaUpdate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: AppColors.textPrimary,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: Text(
                                  _downloadStatus.isNotEmpty
                                      ? 'Retry Download'
                                      : 'Download & Install',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            if (_downloadStatus.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _downloadStatus,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 12),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Sliding in-app notification banner for optional updates
        if (_optionalUpdateAvailable && !_dismissedOptionalUpdate)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 600),
              tween: Tween<double>(begin: -150.0, end: 0.0),
              curve: Curves.easeOutBack,
              builder: (context, yOffset, child) {
                return Transform.translate(
                  offset: Offset(0, yOffset),
                  child: child,
                );
              },
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E2C).withOpacity(0.92),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: AppColors.textPrimary.withOpacity(0.08)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.system_update_rounded,
                                  color: Colors.blueAccent,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Optional Update Available!',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'A new version ($_latestVersion) of the UniGrid App is available.',
                                      style: TextStyle(
                                        color: AppColors.textPrimary.withOpacity(0.65),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isDownloading) ...[
                            Text(
                              _downloadStatus,
                              style: const TextStyle(
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0
                                    ? _downloadProgress
                                    : null,
                                backgroundColor: AppColors.glassCardBorder,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Colors.blueAccent),
                                minHeight: 6,
                              ),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _dismissedOptionalUpdate = true;
                                    });
                                  },
                                  child: Text(
                                    'Later',
                                    style: TextStyle(
                                        color: AppColors.textSecondary, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: _startOtaUpdate,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: AppColors.textPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    _downloadStatus.isNotEmpty
                                        ? 'Retry'
                                        : 'Update',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_downloadStatus.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  _downloadStatus,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 11),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

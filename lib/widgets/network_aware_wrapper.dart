import '../utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/connectivity_service.dart';

class NetworkAwareWrapper extends StatefulWidget {
  final Widget child;
  const NetworkAwareWrapper({super.key, required this.child});

  @override
  State<NetworkAwareWrapper> createState() => _NetworkAwareWrapperState();
}

class _NetworkAwareWrapperState extends State<NetworkAwareWrapper> {
  final ConnectivityService _connectivity = ConnectivityService();
  bool _showBanner = false;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _connectivity.addListener(_onConnectivityChanged);
    _showBanner = !_connectivity.isConnected;
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    setState(() {
      if (!_connectivity.isConnected) {
        _showBanner = true;
        _wasOffline = true;
      } else if (_wasOffline) {
        // Show "Back Online!" briefly then hide
        _showBanner = true;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _showBanner = false);
        });
        _wasOffline = false;
      }
    });
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _connectivity.isConnected
                ? _buildBanner(
                    icon: Icons.wifi,
                    message: 'Back Online!',
                    color: const Color(0xFF00C853),
                  )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .then(delay: 2500.ms)
                    .fadeOut(duration: 300.ms)
                : _buildBanner(
                    icon: Icons.wifi_off_rounded,
                    message: 'No Internet Connection',
                    color: const Color(0xFFE53935),
                  )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: -1, end: 0, duration: 300.ms),
          ),
      ],
    );
  }

  Widget _buildBanner({
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        color: color,
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          bottom: 10,
          left: 16,
          right: 16,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textPrimary, size: 18),
            const SizedBox(width: 8),
            Text(
              message,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

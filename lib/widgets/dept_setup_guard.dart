import 'package:flutter/material.dart';

class DeptSetupGuard extends StatelessWidget {
  final Widget child;

  const DeptSetupGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Always proceed directly to main workspace without interrupting loading
    return child;
  }
}

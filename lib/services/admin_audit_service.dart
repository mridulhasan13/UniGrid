import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// AdminAuditService
///
/// Records all administrative and security actions taken by Admins and CRs
/// into the Firestore `admin_audit_logs` collection for security auditing,
/// traceability, and preventing unauthorized modifications.
/// ─────────────────────────────────────────────────────────────────────────────
class AdminAuditService {
  AdminAuditService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionPath = 'admin_audit_logs';

  /// Records an administrative action to the audit log.
  static Future<void> logAction({
    required String action,
    required String category, // 'Security', 'Roles', 'User', 'System', 'Broadcast'
    String? targetId,
    String? targetName,
    Map<String, dynamic>? details,
    AppUser? actingAdmin,
  }) async {
    try {
      final currentAuthUser = FirebaseAuth.instance.currentUser;
      final adminUid = actingAdmin?.id ?? currentAuthUser?.uid ?? 'system';
      final adminName = actingAdmin?.name.isNotEmpty == true
          ? actingAdmin!.name
          : (currentAuthUser?.displayName?.isNotEmpty == true
              ? currentAuthUser!.displayName!
              : (currentAuthUser?.email?.split('@').first ?? 'Admin'));
      final adminEmail = actingAdmin?.email ?? currentAuthUser?.email ?? '';

      final logData = {
        'action': action,
        'category': category,
        'adminUid': adminUid,
        'adminName': adminName,
        'adminEmail': adminEmail,
        'targetId': targetId ?? '',
        'targetName': targetName ?? '',
        'details': details ?? {},
        'timestamp': FieldValue.serverTimestamp(),
        'clientTimestamp': DateTime.now().toIso8601String(),
      };

      await _firestore.collection(_collectionPath).add(logData);
      debugPrint('[AdminAudit] ✓ Logged: "$action" by $adminName ($category)');
    } catch (e) {
      debugPrint('[AdminAudit] Non-fatal error recording audit log: $e');
    }
  }

  /// Returns a real-time stream of the most recent audit logs.
  static Stream<QuerySnapshot<Map<String, dynamic>>> getAuditLogsStream({int limit = 40}) {
    return _firestore
        .collection(_collectionPath)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }
}

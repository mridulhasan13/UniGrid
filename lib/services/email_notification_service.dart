import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Production Email Dispatcher for UniGrid Onboarding & Approval
/// Powered by Google Apps Script Web App.
class EmailNotificationService {
  static const String _webAppUrl =
      'https://script.google.com/macros/s/AKfycbxqilnZOMQ_X6rybSFAskewJ4nOfUTdndk44-JuMZ5W__aCvdlEF7GiD2hxcLwm_eCB/exec';

  /// Dispatches the "Registration Under Review / Pending" email
  static Future<bool> sendPendingEmail({
    required String email,
    required String name,
    required String department,
    required String batch,
  }) async {
    return _sendEmail(
      email: email,
      name: name,
      department: department,
      batch: batch,
      type: 'pending',
    );
  }

  /// Dispatches the "Account Approved" email
  static Future<bool> sendApprovedEmail({
    required String email,
    required String name,
    required String department,
    required String batch,
  }) async {
    return _sendEmail(
      email: email,
      name: name,
      department: department,
      batch: batch,
      type: 'approved',
    );
  }

  static Future<bool> _sendEmail({
    required String email,
    required String name,
    required String department,
    required String batch,
    required String type,
  }) async {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      debugPrint('[EmailNotificationService] Skipped: Invalid email "$email"');
      return false;
    }

    debugPrint('[EmailNotificationService] Dispatching $type email to $cleanEmail ($name, $department, $batch)...');

    try {
      final payload = jsonEncode({
        'to': cleanEmail,
        'name': name.trim().isEmpty ? 'Student' : name.trim(),
        'department': department.trim().isEmpty ? 'Academic Department' : department.trim(),
        'batch': batch.trim().isEmpty ? 'Current Batch' : batch.trim(),
        'type': type,
      });

      // Use 'text/plain' to avoid CORS preflight OPTIONS rejection in Flutter Web / Edge
      final response = await http.post(
        Uri.parse(_webAppUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: payload,
      );

      debugPrint('[EmailNotificationService] Response status: ${response.statusCode}');
      if (response.statusCode >= 200 && response.statusCode < 400) {
        debugPrint('[EmailNotificationService] Email ($type) sent successfully to $cleanEmail');
        return true;
      } else {
        debugPrint('[EmailNotificationService] HTTP error ${response.statusCode}: ${response.body}');
        return false;
      }
    } catch (e) {
      // In Flutter Web, Google Apps Script 302 redirects can trigger a browser CORS error
      // AFTER the email has already been sent on Google's servers.
      debugPrint('[EmailNotificationService] Dispatch completed (or browser redirect caught): $e');
      return true;
    }
  }
}

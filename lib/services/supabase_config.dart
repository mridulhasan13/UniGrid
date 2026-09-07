import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project credentials with dynamic Firestore configuration,
/// 900 MB auto-handoff threshold, and multi-project keep-alive heartbeat.
class SupabaseConfig {
  static const String defaultUrl = 'https://vgwcrwnynoelrfvdocwk.supabase.co';
  static const String defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZnd2Nyd255bm9lbHJmdmRvY3drIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODEyOTg3MzcsImV4cCI6MjA5Njg3NDczN30.DqFw4YbQFnYcR-667HyQKyRq4Xin0AklWL3LJXE-nmk';
  static const String defaultBucket = 'unigrid-files';
  static const double defaultMaxQuotaMB = 900.0;

  static String url = defaultUrl;
  static String anonKey = defaultAnonKey;
  static String bucket = defaultBucket;
  static double maxQuotaMB = defaultMaxQuotaMB;

  static const List<Map<String, String>> defaultPreviousProjects = [
    {
      'url': 'https://yamjfprclflcgmlmjqwu.supabase.co',
      'anonKey':
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlhbWpmcHJjbGZsY2dtbG1qcXd1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczOTczNTAsImV4cCI6MjEwMjk3MzM1MH0.2lH-jSc3x1RCMGCh_r9Gd0938wIGHmrpyV8rMRkWR2U',
      'bucket': 'unigrid-files',
    },
  ];

  /// List of archived / previous Supabase projects that have reached ~900 MB or are standby databases.
  /// Kept active with 4-day keep-alive heartbeats so projects remain 100% awake and accessible.
  static List<Map<String, String>> previousProjects =
      List<Map<String, String>>.from(defaultPreviousProjects);

  static DateTime? lastHeartbeatTime;

  /// Fetches remote storage configuration from Firestore `app_config/storage`
  static Future<void> syncFromCloud() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('storage')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final remoteUrl = (data['url'] ?? '').toString().trim();
        final remoteKey = (data['anonKey'] ?? '').toString().trim();
        final remoteBucket = (data['bucket'] ?? '').toString().trim();
        final remoteQuota = (data['maxQuotaMB'] is num)
            ? (data['maxQuotaMB'] as num).toDouble()
            : defaultMaxQuotaMB;

        maxQuotaMB = remoteQuota;

        // Parse previous archived / standby projects
        List<Map<String, String>> parsed = [];
        if (data['previousProjects'] is List) {
          parsed = (data['previousProjects'] as List)
              .map((item) {
                if (item is Map) {
                  return {
                    'url': (item['url'] ?? '').toString().trim(),
                    'anonKey': (item['anonKey'] ?? '').toString().trim(),
                    'bucket': (item['bucket'] ?? defaultBucket).toString().trim(),
                  };
                }
                return <String, String>{};
              })
              .where((m) => m['url']?.isNotEmpty == true && m['anonKey']?.isNotEmpty == true)
              .toList();
        }

        // Merge defaultPreviousProjects with cloud list
        final Set<String> existingUrls = parsed.map((e) => e['url']!).toSet();
        for (final def in defaultPreviousProjects) {
          if (!existingUrls.contains(def['url'])) {
            parsed.add(def);
          }
        }
        previousProjects = parsed;

        if (remoteUrl.isNotEmpty && remoteKey.isNotEmpty) {
          final bool isDifferent = remoteUrl != url || remoteKey != anonKey;
          url = remoteUrl;
          anonKey = remoteKey;
          if (remoteBucket.isNotEmpty) bucket = remoteBucket;

          if (isDifferent) {
            debugPrint('[SupabaseConfig] Storage endpoint switched to: $url ($bucket)');
            await Supabase.initialize(
              url: url,
              anonKey: anonKey,
            );
          }
        }
      } else {
        // Seed default multi-project configuration in Firestore
        await FirebaseFirestore.instance
            .collection('app_config')
            .doc('storage')
            .set({
          'url': defaultUrl,
          'anonKey': defaultAnonKey,
          'bucket': defaultBucket,
          'maxQuotaMB': defaultMaxQuotaMB,
          'previousProjects': defaultPreviousProjects,
          'provider': 'Supabase Multi-Storage Tier',
          'description': 'Dynamic Cloud Storage. When active project hits 900MB, add it to previousProjects and put new credentials in url/anonKey.',
          'lastHeartbeatPing': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('[SupabaseConfig] Seeded default multi-storage config in Firestore');
      }

      // Check and execute keep-alive heartbeat if due
      await triggerHeartbeatIfNeeded();
    } catch (e) {
      debugPrint('[SupabaseConfig] Cloud sync fallback to default: $e');
    }
  }

  /// Automatically hands off uploads to the next standby Supabase project
  /// when the active project reaches capacity (~900MB), gets paused, or returns quota exceeded.
  static Future<bool> switchToNextStandbyProject() async {
    try {
      if (previousProjects.isEmpty) return false;

      // Find the first standby project that is not the current active project
      final nextCandidateIndex = previousProjects.indexWhere(
        (p) => (p['url'] ?? '') != url && (p['anonKey'] ?? '').isNotEmpty,
      );
      if (nextCandidateIndex == -1) return false;

      final nextProject = previousProjects[nextCandidateIndex];
      final nextUrl = nextProject['url']!;
      final nextAnonKey = nextProject['anonKey']!;
      final nextBucket = nextProject['bucket'] ?? defaultBucket;

      // Move current project into archived previous list
      final currentArchived = {
        'url': url,
        'anonKey': anonKey,
        'bucket': bucket,
      };

      final updatedPrevious = List<Map<String, String>>.from(previousProjects);
      updatedPrevious.removeAt(nextCandidateIndex);
      if (!updatedPrevious.any((p) => p['url'] == currentArchived['url'])) {
        updatedPrevious.add(currentArchived);
      }

      // Update in-memory config
      url = nextUrl;
      anonKey = nextAnonKey;
      bucket = nextBucket;
      previousProjects = updatedPrevious;

      debugPrint('[SupabaseConfig] ⚡ Auto-handoff activated! Switched to: $url');
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
      );

      // Persist handoff to Firestore so all app users automatically use the new project
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('storage')
          .set({
        'url': url,
        'anonKey': anonKey,
        'bucket': bucket,
        'previousProjects': previousProjects,
        'lastHandoffTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      debugPrint('[SupabaseConfig] Auto-handoff failed: $e');
      return false;
    }
  }

  /// Sends a tiny keep-alive ping (< 150 KB, ~0.2 KB) to the active project
  /// AND every archived previous Supabase project if >= 4 days have elapsed.
  /// Ensures none of the projects ever pause or sleep.
  static Future<void> triggerHeartbeatIfNeeded({bool force = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastMs = prefs.getInt('supabase_last_heartbeat_ms') ?? 0;
      final now = DateTime.now();
      final lastDate = DateTime.fromMillisecondsSinceEpoch(lastMs);

      // Trigger if 4+ days elapsed (well within the 7-day inactivity pause window) or forced
      if (force || now.difference(lastDate).inDays >= 4 || lastMs == 0) {
        debugPrint('[SupabaseHeartbeat] Executing 5-day keep-alive ping across all Supabase projects...');

        final List<Map<String, String>> targets = [
          {'url': url, 'anonKey': anonKey},
          ...previousProjects,
        ];

        for (final target in targets) {
          final targetUrl = target['url'] ?? '';
          final targetKey = target['anonKey'] ?? '';
          if (targetUrl.isEmpty || targetKey.isEmpty) continue;

          try {
            // Lightweight REST endpoint ping (< 200 bytes)
            final pingUri = Uri.parse('$targetUrl/rest/v1/');
            final response = await http.get(
              pingUri,
              headers: {
                'apikey': targetKey,
                'Authorization': 'Bearer $targetKey',
              },
            ).timeout(const Duration(seconds: 5));

            debugPrint('[SupabaseHeartbeat] Pinged $targetUrl -> Status: ${response.statusCode}');
          } catch (pingErr) {
            debugPrint('[SupabaseHeartbeat] Ping notice for $targetUrl: $pingErr');
          }
        }

        lastHeartbeatTime = now;
        await prefs.setInt('supabase_last_heartbeat_ms', now.millisecondsSinceEpoch);

        // Update Firestore last ping record in background
        FirebaseFirestore.instance
            .collection('app_config')
            .doc('storage')
            .set({
          'lastHeartbeatPing': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).catchError((_) {});
      }
    } catch (e) {
      debugPrint('[SupabaseHeartbeat] Heartbeat check failed non-fatally: $e');
    }
  }
}

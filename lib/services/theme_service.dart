import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/constants.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService instance = ThemeService._internal();
  ThemeService._internal();

  String _currentTheme = 'Sky Sapphire';
  String get currentTheme => _currentTheme;

  StreamSubscription? _themeSubscription;
  int _retryCount = 0;

  String? _activeDept;
  String? _activeBatch;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('app_theme') ?? 'Sky Sapphire';
    setTheme(savedTheme, saveToPrefs: false);
  }

  void stopListener() {
    _themeSubscription?.cancel();
    _themeSubscription = null;
    _retryCount = 0;
    _activeDept = null;
    _activeBatch = null;
  }

  void initGlobalThemeListener({String? department, String? batch}) {
    _themeSubscription?.cancel();
    _themeSubscription = null;

    _activeDept = department;
    _activeBatch = batch;

    final DocumentReference docRef;
    if (department != null && department.isNotEmpty && batch != null && batch.isNotEmpty) {
      docRef = FirebaseFirestore.instance
          .collection('depts')
          .doc(department)
          .collection('batches')
          .doc(batch)
          .collection('config')
          .doc('app_theme');
    } else {
      docRef = FirebaseFirestore.instance
          .collection('admin_settings')
          .doc('app_theme');
    }

    _themeSubscription = docRef.snapshots().listen(
      (doc) {
        _retryCount = 0; // Reset retry count on success
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null && data['currentTheme'] != null) {
            final themeName = data['currentTheme'] as String;
            if (themeName != _currentTheme) {
              setTheme(themeName, saveToPrefs: true, syncToFirestore: false);
            }
          }
        }
      },
      onError: (e) {
        final errStr = e.toString();
        // If permission-denied or unauthenticated (e.g. user logged out), immediately stop without spamming retries
        if (errStr.contains('permission-denied') ||
            errStr.contains('unauthenticated') ||
            errStr.contains('PERMISSION_DENIED')) {
          debugPrint('[ThemeService] Scoped theme listener stopped due to auth/permission change.');
          stopListener();
          return;
        }

        if (_retryCount < 3) {
          _retryCount++;
          final delayMs = 1000 * _retryCount;
          debugPrint('[ThemeService] Retrying scoped theme listener in ${delayMs}ms (attempt $_retryCount/3)');
          Future.delayed(Duration(milliseconds: delayMs), () {
            if (_activeDept == department && _activeBatch == batch) {
              initGlobalThemeListener(department: department, batch: batch);
            }
          });
        }
      },
    );
  }

  void setTheme(String themeName,
      {bool saveToPrefs = true, bool syncToFirestore = false}) {
    _currentTheme = themeName;

    switch (themeName) {
      case 'Mist Emerald':
        AppColors.primary = const Color(0xFF10B981);
        AppColors.secondary = const Color(0xFF69F0AE);
        AppColors.backgroundTop = const Color(0xFF020604);
        AppColors.backgroundBottom = const Color(0xFF020604);
        AppColors.glassCardColor = const Color(0xFF1E293B);
        AppColors.glassCardBorder = const Color(0xFF334155);
        break;
      case 'Sky Sapphire':
        AppColors.primary = const Color(0xFF3B82F6);
        AppColors.secondary = const Color(0xFF93C5FD);
        AppColors.backgroundTop = const Color(0xFF030710);
        AppColors.backgroundBottom = const Color(0xFF030710);
        AppColors.glassCardColor = const Color(0xFF0D1B2A);
        AppColors.glassCardBorder = const Color(0xFF1B263B);
        break;
      case 'Pastel Bloom':
        AppColors.primary = const Color(0xFFEC4899);
        AppColors.secondary = const Color(0xFFFBCFE8);
        AppColors.backgroundTop = const Color(0xFF070205);
        AppColors.backgroundBottom = const Color(0xFF070205);
        AppColors.glassCardColor = const Color(0xFF2D1020);
        AppColors.glassCardBorder = const Color(0xFF4E1A38);
        break;
      case 'Sayan Cyan':
        AppColors.primary = const Color(0xFF06B6D4);
        AppColors.secondary = const Color(0xFF67E8F9);
        AppColors.backgroundTop = const Color(0xFF020608);
        AppColors.backgroundBottom = const Color(0xFF020608);
        AppColors.glassCardColor = const Color(0xFF0A2330);
        AppColors.glassCardBorder = const Color(0xFF134252);
        break;
      case 'Ruby Rose':
        AppColors.primary = const Color(0xFFEF4444);
        AppColors.secondary = const Color(0xFFFCA5A5);
        AppColors.backgroundTop = const Color(0xFF060202);
        AppColors.backgroundBottom = const Color(0xFF060202);
        AppColors.glassCardColor = const Color(0xFF2D0D0D);
        AppColors.glassCardBorder = const Color(0xFF4E1616);
        break;
      case 'Amethyst Orchid':
        AppColors.primary = const Color(0xFF8B5CF6);
        AppColors.secondary = const Color(0xFFC7D2FE);
        AppColors.backgroundTop = const Color(0xFF04020B);
        AppColors.backgroundBottom = const Color(0xFF04020B);
        AppColors.glassCardColor = const Color(0xFF210D3D);
        AppColors.glassCardBorder = const Color(0xFF3E1F6B);
        break;
      case 'Sunset Coral':
        AppColors.primary = const Color(0xFFF97316);
        AppColors.secondary = const Color(0xFFFED7AA);
        AppColors.backgroundTop = const Color(0xFF060302);
        AppColors.backgroundBottom = const Color(0xFF060302);
        AppColors.glassCardColor = const Color(0xFF2D160E);
        AppColors.glassCardBorder = const Color(0xFF4E2618);
        break;
      case 'Black & White':
        AppColors.primary = const Color(0xFFFFFFFF);
        AppColors.secondary = const Color(0xFF9CA3AF);
        AppColors.backgroundTop = const Color(0xFF000000);
        AppColors.backgroundBottom = const Color(0xFF000000);
        AppColors.glassCardColor = const Color(0xFF18181B);
        AppColors.glassCardBorder = const Color(0xFF27272A);
        break;
      default:
        AppColors.primary = const Color(0xFF3B82F6);
        AppColors.secondary = const Color(0xFF93C5FD);
        AppColors.backgroundTop = const Color(0xFF030710);
        AppColors.backgroundBottom = const Color(0xFF030710);
        AppColors.glassCardColor = const Color(0xFF0D1B2A);
        AppColors.glassCardBorder = const Color(0xFF1B263B);
    }

    notifyListeners();

    if (saveToPrefs) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('app_theme', themeName);
      });
    }

    if (syncToFirestore) {
      final DocumentReference docRef;
      if (_activeDept != null && _activeDept!.isNotEmpty && _activeBatch != null && _activeBatch!.isNotEmpty) {
        docRef = FirebaseFirestore.instance
            .collection('depts')
            .doc(_activeDept!)
            .collection('batches')
            .doc(_activeBatch!)
            .collection('config')
            .doc('app_theme');
      } else {
        docRef = FirebaseFirestore.instance
            .collection('admin_settings')
            .doc('app_theme');
      }

      docRef.set({
        'currentTheme': themeName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((e) {
        debugPrint('[ThemeService] Failed to sync theme to Firestore: $e');
      });
    }
  }

  @override
  void dispose() {
    _themeSubscription?.cancel();
    super.dispose();
  }
}

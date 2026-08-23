import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, compute;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../notifications/fcm_service.dart';
import 'theme_service.dart';
import 'supabase_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _userController = StreamController<AppUser?>.broadcast();
  StreamSubscription? _userSubscription;
  StreamSubscription? _rootAdminsSubscription;
  List<Map<String, dynamic>> _rootAdmins = [];

  // Track the last dept/batch used to init the theme listener so we only
  // restart it when the user's scope actually changes (Bug #3 guard).
  String? _lastThemeDept;
  String? _lastThemeBatch;

  final _sessionInitCompleter = Completer<void>();

  AuthService() {
    // Explicitly lock Firebase Auth to LOCAL persistence on web so sessions
    // survive tab closes and browser restarts (indexedDB-backed, not just session-storage).
    if (kIsWeb) {
      _auth.setPersistence(Persistence.LOCAL).catchError((e) {
        debugPrint('[AuthService] setPersistence error: $e');
      });
    }
    _initRootAdminListener();
    _initSession();
    _auth.authStateChanges().listen((User? firebaseUser) {
      if (firebaseUser != null) {
        // Refresh 3-day session clock whenever logged-in user state is active
        final isGoogleUser = firebaseUser.providerData
            .any((p) => p.providerId == 'google.com');
        _saveSession(firebaseUser.email ?? '', isGoogleUser);

        // On web: initialize FCM first (requests browser permission) then save
        // the token. On native: init already ran in main.dart, just save.
        if (kIsWeb) {
          FCMService.initialize().then((_) {
            FCMService.saveTokenForUser(firebaseUser.uid);
          }).catchError((e) {
            debugPrint('[AuthService] FCM web init error: $e');
          });
        } else {
          FCMService.saveTokenForUser(firebaseUser.uid);
        }
        // NOTE: ThemeService listener is initialized in _startFirestoreListener
        // once the user's dept/batch is known — calling it here without those params
        // would subscribe to the wrong doc and trigger a full MaterialApp rebuild.
        // _initRootAdminListener() is already called once in the constructor; calling
        // it again here on every authStateChanges event would tear down and restart
        // the root_admins stream unnecessarily (Bug #2 + Bug #3 guard).
      }
      _startFirestoreListener(
        firebaseUser?.uid,
        firebaseUser?.email,
        displayName: firebaseUser?.displayName,
        photoUrl: firebaseUser?.photoURL,
      );
    });
  }

  Future<void> waitForSessionInit() async {
    if (_sessionInitCompleter.isCompleted) return;
    await _sessionInitCompleter.future.timeout(
      const Duration(milliseconds: 1000),
      onTimeout: () {},
    );
  }

  void _initRootAdminListener() {
    _rootAdminsSubscription?.cancel();
    _rootAdminsSubscription = _firestore.collection('root_admins').snapshots().listen(
      (snapshot) {
        final newAdmins = snapshot.docs.map((doc) => doc.data()).toList();

        // Compare the set of admin emails — only restart the user listener if
        // the root_admins collection actually changed. Restarting unconditionally
        // would cancel+recreate the user Firestore stream on every snapshot event,
        // emitting a new AppUser and causing AuthWrapper to rebuild (Bug #2 guard).
        final prevEmails = _rootAdmins
            .map((a) =>
                (a['email'] ?? a['Email'])?.toString().trim().toLowerCase() ?? '')
            .toSet();
        final newEmails = newAdmins
            .map((a) =>
                (a['email'] ?? a['Email'])?.toString().trim().toLowerCase() ?? '')
            .toSet();

        _rootAdmins = newAdmins;

        if (!prevEmails.containsAll(newEmails) ||
            !newEmails.containsAll(prevEmails)) {
          // Root admin roster actually changed — re-evaluate the current user.
          final current = _auth.currentUser;
          if (current != null) {
            _startFirestoreListener(
              current.uid,
              current.email,
              displayName: current.displayName,
              photoUrl: current.photoURL,
            );
          }
        }
      },
      onError: (e) {
        debugPrint(
            '[AuthService] root_admins listener error (expected before login): $e');
      },
    );
  }

  bool isRootAdmin(String? email) {
    if (email == null) return false;
    final cleanEmail = email.trim().toLowerCase();

    // FAIL-SAFE: Hardcoded fallback for primary root admins
    if (cleanEmail == 'mridul.owner@unigrid.app' ||
        cleanEmail == 'mridulhasan13@gmail.com') {
      return true;
    }

    // Database check for other potential root admins (supporting both 'email' and 'Email' keys)
    return _rootAdmins.any((a) {
      final dbEmail = (a['email'] ?? a['Email'])?.toString().trim().toLowerCase();
      return dbEmail == cleanEmail;
    });
  }

  /// The current Firebase Auth user (raw) — non-null means a session exists
  /// even if the Firestore AppUser hasn't loaded yet.
  User? get currentFirebaseUser => _auth.currentUser;

  void _startFirestoreListener(String? uid, String? email,
      {String? displayName, String? photoUrl}) {
    _userSubscription?.cancel();

    if (uid == null) {
      _lastThemeDept = null;
      _lastThemeBatch = null;
      ThemeService.instance.stopListener();
      _userController.add(null);
      return;
    }

    // Always use the real Firebase UID for the document — no more unified ID
    _userSubscription =
        _firestore.collection('users').doc(uid).snapshots().listen(
      (doc) {
        final bool isRoot = isRootAdmin(email);

        if (doc.exists) {
          var data =
              Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);

          // Sync email, name, and photoUrl from Firebase Auth into Firestore if they are missing/empty in Firestore
          final storedEmail = (data['email'] as String?)?.trim() ?? '';
          final authEmail = (email ?? '').trim();
          final storedName = (data['name'] as String?)?.trim() ?? '';
          final authName = (displayName ?? '').trim();
          final storedPhoto = (data['photoUrl'] as String?)?.trim() ?? '';
          final authPhoto = (photoUrl ?? '').trim();

          bool needsUpdate = false;
          final Map<String, dynamic> updateFields = {};

          if (authEmail.isNotEmpty && storedEmail.isEmpty) {
            updateFields['email'] = authEmail;
            data['email'] = authEmail;
            needsUpdate = true;
          }
          if (authName.isNotEmpty &&
              (storedName.isEmpty ||
                  storedName == 'Unknown User' ||
                  storedName == 'Unknown')) {
            updateFields['name'] = authName;
            data['name'] = authName;
            needsUpdate = true;
          }
          if (authPhoto.isNotEmpty && storedPhoto.isEmpty) {
            updateFields['photoUrl'] = authPhoto;
            data['photoUrl'] = authPhoto;
            needsUpdate = true;
          }

          if (needsUpdate) {
            _firestore.collection('users').doc(uid).set(
              updateFields,
              SetOptions(merge: true),
            );
          }

          // Auto-promote root admins — always ensure isCR, isAdmin, and isApproved are true, and set default department 'IPE' & batch '51'
          final currentDept = (data['department'] as String?)?.trim() ?? '';
          final currentBatch = (data['batch'] as String?)?.trim() ?? '';

          if (isRoot) {
            final Map<String, dynamic> rootUpdates = {};
            if (data['isCR'] != true) rootUpdates['isCR'] = true;
            if (data['isAdmin'] != true) rootUpdates['isAdmin'] = true;
            if (data['isApproved'] != true) rootUpdates['isApproved'] = true;
            if (currentDept.isEmpty) rootUpdates['department'] = 'IPE';
            if (currentBatch.isEmpty) rootUpdates['batch'] = '51';

            if (rootUpdates.isNotEmpty) {
              rootUpdates['email'] = email;
              _firestore.collection('users').doc(uid).set(
                rootUpdates,
                SetOptions(merge: true),
              );
              data['isCR'] = true;
              data['isAdmin'] = true;
              data['isApproved'] = true;
              if (currentDept.isEmpty) data['department'] = 'IPE';
              if (currentBatch.isEmpty) data['batch'] = '51';
            }
          }

          final appUser = AppUser.fromMap(data, doc.id);
          _userController.add(appUser);
          SharedPreferences.getInstance().then((prefs) {
            prefs.setString('auth_session_department', appUser.department);
            prefs.setString('auth_session_batch', appUser.batch);
          }).catchError((_) {});
          if (appUser.hasDeptScope) {
            // Only restart the Firestore theme listener when the user's dept/batch
            // actually changes. Restarting on every snapshot would cancel+recreate
            // the theme subscription and fire notifyListeners(), triggering a full
            // MaterialApp rebuild via Consumer<ThemeService> (Bug #3 guard).
            if (appUser.department != _lastThemeDept ||
                appUser.batch != _lastThemeBatch) {
              _lastThemeDept = appUser.department;
              _lastThemeBatch = appUser.batch;
              ThemeService.instance.initGlobalThemeListener(
                department: appUser.department,
                batch: appUser.batch,
              );
            }
          }
        } else {
          // Create a new user document
          final newUser = AppUser(
            id: uid,
            email: email ?? '',
            isCR: isRoot,
            isAdmin: isRoot,
            isApproved: isRoot,
            department: isRoot ? 'IPE' : '',
            batch: isRoot ? '51' : '',
            name: displayName ?? '',
            photoUrl: photoUrl ?? '',
            createdAt: DateTime.now(),
          );
          _firestore.collection('users').doc(uid).set(newUser.toMap());
          _userController.add(newUser);
        }
      },
      onError: (e) {
        debugPrint('[AuthService] User listener error: $e');
      },
    );
  }

  Stream<AppUser?> get user => _userController.stream;

  /// Always returns the live Firebase Auth email — never stale Firestore data.
  String? get currentAuthEmail => _auth.currentUser?.email;

  Future<AppUser?> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email.trim().toLowerCase(), password: password.trim());
      User? firebaseUser = result.user;
      if (firebaseUser != null) {
        await _saveSession(email.trim().toLowerCase(), false, password: password.trim());
        // Record login event directly in Firestore
        _firestore.collection('users').doc(firebaseUser.uid).set({
          'lastLogin': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
          'loginCount': FieldValue.increment(1),
        }, SetOptions(merge: true));

        _startFirestoreListener(
          firebaseUser.uid,
          firebaseUser.email,
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoURL,
        );
        final doc =
            await _firestore.collection('users').doc(firebaseUser.uid).get();
        if (doc.exists) {
          return AppUser.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }
      }
    } catch (e) {
      debugPrint('[AuthService] signIn error: $e');
      throw Exception('Login failed: $e');
    }
    return null;
  }

  Future<AppUser?> registerWithEmailAndPassword(
    String email,
    String password,
    String name,
    String studentId,
    String batch,
    String department,
    String phoneNumber,
  ) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: cleanEmail, password: password);
      User? user = result.user;

      if (user != null) {
        await _saveSession(cleanEmail, false, password: password);
        final bool isRoot = isRootAdmin(cleanEmail);
        final newUser = AppUser(
          id: user.uid,
          email: user.email!,
          isCR: isRoot,
          isAdmin: isRoot, // Full admin status for root admins
          isApproved:
              isRoot, // Root admin is auto-approved; others need CR approval
          name: name,
          studentId: studentId,
          batch: batch,
          department: department,
          phoneNumber: phoneNumber,
          createdAt: DateTime.now(),
        );
        await _firestore.collection('users').doc(user.uid).set(newUser.toMap());
        
        // Notify CRs & Admins of the new registration request
        if (!isRoot && department.isNotEmpty && batch.isNotEmpty) {
          FCMService.notifyNewRegistration(
            studentName: name.isNotEmpty ? name : 'New Student',
            studentId: studentId,
            department: department,
            batch: batch,
            senderUserId: user.uid,
          ).catchError((e) {
            debugPrint('[AuthService] New registration push notice error: $e');
          });
        }
        
        return newUser;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      final currentUid = _auth.currentUser?.uid;

      // 1. Immediately tear down listeners to avoid permission-denied errors & UI stutter
      _lastThemeDept = null;
      _lastThemeBatch = null;
      ThemeService.instance.stopListener();
      _userSubscription?.cancel();
      _userSubscription = null;

      // 2. Remove FCM token asynchronously in background (never blocks UI)
      if (currentUid != null) {
        FCMService.removeCurrentTokenOnLogout(currentUid).catchError((e) {
          debugPrint('[AuthService] FCM token removal notice: $e');
        });
      }

      // 3. Clear local session & sign out from Firebase
      await _clearSession();
      await _auth.signOut();
      _userController.add(null);
    } catch (e) {
      debugPrint('[AuthService] signOut error: $e');
      _userController.add(null);
    }
  }

  /// Permanently deletes the current user's account, Firestore data, and Firebase Auth record.
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final uid = user.uid;

      // 1. Remove FCM tokens
      try {
        await FCMService.removeCurrentTokenOnLogout(uid);
      } catch (e) {
        debugPrint('[AuthService] FCM token removal on delete notice: $e');
      }

      // 2. Delete Firestore User Document
      try {
        await _firestore.collection('users').doc(uid).delete();
      } catch (e) {
        debugPrint('[AuthService] Firestore user doc deletion notice: $e');
      }

      // 3. Tear down listeners & clear local session
      _lastThemeDept = null;
      _lastThemeBatch = null;
      ThemeService.instance.stopListener();
      _userSubscription?.cancel();
      _userSubscription = null;
      await _clearSession();

      // 4. Delete Firebase Auth user record
      await user.delete();
      _userController.add(null);
    } catch (e) {
      debugPrint('[AuthService] deleteAccount error: $e');
      rethrow;
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updatePassword(
      String currentPassword, String newPassword) async {
    try {
      final user = _auth.currentUser;
      if (user != null && user.email != null) {
        AuthCredential credential = EmailAuthProvider.credential(
          email: user.email!,
          password: currentPassword,
        );
        await user.reauthenticateWithCredential(credential);
        await user.updatePassword(newPassword);
      } else {
        throw Exception('User is not logged in.');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateUserProfile({
    String? name,
    String? studentId,
    String? batch,
    String? department,
    String? phoneNumber,
    String? schoolName,
    String? collegeName,
    String? photoUrl,
  }) async {
    try {
      final firebaseUser = _auth.currentUser;
      final String? userId = firebaseUser?.uid; // Always use real UID

      if (userId == null) return;

      final updatedData = <String, dynamic>{};
      if (name != null) updatedData['name'] = name;
      if (studentId != null) updatedData['studentId'] = studentId;
      if (batch != null) updatedData['batch'] = batch;
      if (department != null) updatedData['department'] = department;
      if (phoneNumber != null) updatedData['phoneNumber'] = phoneNumber;
      if (schoolName != null) updatedData['schoolName'] = schoolName;
      if (collegeName != null) updatedData['collegeName'] = collegeName;
      if (photoUrl != null) updatedData['photoUrl'] = photoUrl;

      await _firestore
          .collection('users')
          .doc(userId)
          .set(updatedData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('updateUserProfile error: $e');
      rethrow;
    }
  }

  Future<void> updateOnlineStatus(bool isOnline) async {
    try {
      final firebaseUser = _auth.currentUser;
      final String? userId = firebaseUser?.uid;

      if (userId == null) return;

      await _firestore.collection('users').doc(userId).set({
        'isOnline': isOnline,
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Status update failed: $e');
    }
  }

  Future<String> uploadChatImage(Uint8List fileBytes, String extension) async {
    try {
      final compressedBytes = await compute(_compressImageForChat, fileBytes);
      final fileName = '${const Uuid().v4()}.$extension';
      final url = await SupabaseStorageService.uploadFile(
        bytes: compressedBytes,
        fileName: fileName,
        folder: 'chat_images',
      );
      return url;
    } catch (e) {
      debugPrint('[AuthService] uploadChatImage error: $e');
      rethrow;
    }
  }

  Future<String> uploadProfilePhoto(
      Uint8List fileBytes, String extension) async {
    try {
      final compressedBytes = await compute(_compressImageForChat, fileBytes);
      final fileName = '${const Uuid().v4()}.$extension';
      final url = await SupabaseStorageService.uploadFile(
        bytes: compressedBytes,
        fileName: fileName,
        folder: 'profile_photos',
      );
      await updateUserProfile(photoUrl: url);
      return url;
    } catch (e) {
      debugPrint('[AuthService] uploadProfilePhoto error: $e');
      rethrow;
    }
  }

  Future<AppUser?> signInWithGoogle() async {
    try {
      UserCredential result;
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        result = await _auth.signInWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          return null; // User cancelled
        }
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        result = await _auth.signInWithCredential(credential);
      }
      User? firebaseUser = result.user;
      if (firebaseUser != null) {
        await _saveSession(firebaseUser.email ?? '', true);
        _startFirestoreListener(
          firebaseUser.uid,
          firebaseUser.email,
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoURL,
        );
        final doc =
            await _firestore.collection('users').doc(firebaseUser.uid).get();
        if (doc.exists) {
          return AppUser.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        }
      }
    } catch (e) {
      debugPrint('signInWithGoogle error: $e');
      throw Exception('Google sign-in failed: $e');
    }
    return null;
  }

  Future<void> _saveSession(String email, bool isGoogle, {String? password}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('auth_session_timestamp', DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('auth_session_email', email);
      await prefs.setBool('auth_session_is_google', isGoogle);
      // Store password for silent email/password re-auth within the 3-day window
      if (password != null && password.isNotEmpty) {
        await prefs.setString('auth_session_password', password);
      }
      debugPrint('[AuthService] Session saved for $email (Google: $isGoogle).');
    } catch (e) {
      debugPrint('[AuthService] Error saving session: $e');
    }
  }

  Future<bool> hasActiveStoredSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('auth_session_timestamp');
      if (timestamp != null) {
        final loginTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        return DateTime.now().difference(loginTime).inHours < 72;
      }
    } catch (e) {
      debugPrint('[AuthService] Error checking stored session: $e');
    }
    return false;
  }

  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_session_timestamp');
      await prefs.remove('auth_session_email');
      await prefs.remove('auth_session_password');
      await prefs.remove('auth_session_is_google');
      debugPrint('[AuthService] Session cleared.');
    } catch (e) {
      debugPrint('[AuthService] Error clearing session: $e');
    }
  }

  Future<void> _initSession() async {
    try {
      // Wait up to 1200ms for Firebase to finish restoring its session from disk/storage before we act.
      if (_auth.currentUser == null) {
        try {
          await _auth
              .authStateChanges()
              .first
              .timeout(const Duration(milliseconds: 1200));
        } catch (_) {
          // Timed out or no user restored — continue with session logic below.
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('auth_session_timestamp');
      if (timestamp != null) {
        final loginTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final difference = DateTime.now().difference(loginTime);
        if (difference.inHours >= 72) {
          debugPrint('[AuthService] Session expired (>= 3 days of inactivity). Logging out.');
          await signOut();
          return;
        }

        // Active session within 3 days — refresh timestamp on active startup
        await prefs.setInt('auth_session_timestamp', DateTime.now().millisecondsSinceEpoch);
        debugPrint('[AuthService] Session refreshed for active user.');

        // If Firebase Auth still has no user after our wait, attempt silent re-auth.
        if (_auth.currentUser == null) {
          final isGoogle = prefs.getBool('auth_session_is_google') ?? false;
          if (isGoogle && !kIsWeb) {
            debugPrint('[AuthService] Attempting silent Google login (mobile)...');
            await _signInGoogleSilently();
          } else if (!isGoogle) {
            final email = prefs.getString('auth_session_email') ?? '';
            final password = prefs.getString('auth_session_password') ?? '';
            if (email.isNotEmpty && password.isNotEmpty) {
              debugPrint('[AuthService] Attempting silent email/password re-auth for $email...');
              await _signInEmailSilently(email, password);
            }
          }
        }
      } else {
        // No session stored yet. If already logged in (e.g. Firebase restored it
        // on web), initialize the session now so the 3-day clock starts.
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          final isGoogleUser = currentUser.providerData
              .any((p) => p.providerId == 'google.com');
          await _saveSession(currentUser.email ?? '', isGoogleUser);
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Error initializing session: $e');
    } finally {
      if (!_sessionInitCompleter.isCompleted) {
        _sessionInitCompleter.complete();
      }
    }
  }

  Future<void> _signInEmailSilently(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      debugPrint('[AuthService] Silent email/password re-auth succeeded.');
    } catch (e) {
      debugPrint('[AuthService] Silent email/password re-auth failed: $e');
      // Do not call signOut() here — the stored session and timestamp are still
      // valid. Firebase may be temporarily unavailable (no network). The user
      // will be prompted to log in manually only after the 3-day window expires.
    }
  }

  Future<void> _signInGoogleSilently() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signInSilently();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await _auth.signInWithCredential(credential);
      }
    } catch (e) {
      debugPrint('[AuthService] Silent Google login failed: $e');
    }
  }
}

/// Fast format-specific decoder using magic numbers to bypass auto-detector overhead
img.Image? _decodeImageFromBytes(Uint8List bytes) {
  if (bytes.length < 4) return img.decodeImage(bytes);
  
  // Check JPEG magic number: FF D8
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return img.decodeJpg(bytes);
  }
  
  // Check PNG magic number: 89 50 4E 47
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return img.decodePng(bytes);
  }
  
  // Check GIF magic number: 47 49 46 38 ('GIF8')
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
    return img.decodeGif(bytes);
  }
  
  return img.decodeImage(bytes);
}

/// Optimize chat images — preserve 100% original for files under 3MB.
/// Only resize if over 3MB (very large camera photos).
Uint8List _compressImageForChat(Uint8List bytes) {
  try {
    // Preserve 100% original pixel perfection for images up to 3MB
    // This covers all handwritten notes, equations, diagrams, and screenshots.
    if (bytes.lengthInBytes <= 3 * 1024 * 1024) {
      return bytes;
    }

    final image = _decodeImageFromBytes(bytes);
    if (image == null) return bytes;

    // For very large high-res camera photos (>3MB):
    // Resize to 2048px max dimension using bicubic interpolation, then
    // encode as high-quality JPEG (95%) for crystal-clear text and diagrams.
    img.Image resized = image;
    if (image.width > 2048 || image.height > 2048) {
      if (image.width > image.height) {
        resized = img.copyResize(image, width: 2048, interpolation: img.Interpolation.cubic);
      } else {
        resized = img.copyResize(image, height: 2048, interpolation: img.Interpolation.cubic);
      }
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 95));
  } catch (e) {
    debugPrint('[ChatCompress] Error during HD image optimization: $e');
    return bytes;
  }
}

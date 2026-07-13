import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, compute;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image/image.dart' as img;
import '../models/models.dart';
import 'fcm_service.dart';
import 'onesignal_service.dart';
import 'theme_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final _userController = StreamController<AppUser?>.broadcast();
  StreamSubscription? _userSubscription;
  StreamSubscription? _rootAdminsSubscription;
  List<Map<String, dynamic>> _rootAdmins = [];

  AuthService() {
    _initRootAdminListener();
    _initSession();
    _auth.authStateChanges().listen((User? firebaseUser) {
      if (firebaseUser != null) {
        FCMService.saveTokenForUser(firebaseUser.uid);
        OneSignalService.setExternalUserId(firebaseUser.uid);
        ThemeService.instance.initGlobalThemeListener();
        _initRootAdminListener();
      } else {
        OneSignalService.removeExternalUserId();
        ThemeService.instance.initGlobalThemeListener();
      }
      _startFirestoreListener(
        firebaseUser?.uid,
        firebaseUser?.email,
        displayName: firebaseUser?.displayName,
        photoUrl: firebaseUser?.photoURL,
      );
    });
  }

  void _initRootAdminListener() {
    _rootAdminsSubscription?.cancel();
    _rootAdminsSubscription = _firestore.collection('root_admins').snapshots().listen(
      (snapshot) {
        _rootAdmins = snapshot.docs.map((doc) => doc.data()).toList();
        final current = _auth.currentUser;
        if (current != null) {
          _startFirestoreListener(
            current.uid,
            current.email,
            displayName: current.displayName,
            photoUrl: current.photoURL,
          );
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

    // FAIL-SAFE: Hardcoded fallback for the primary root admin
    if (cleanEmail == 'mridul.owner@unigrid.app') return true;

    // Database check for other potential root admins (supporting both 'email' and 'Email' keys)
    return _rootAdmins.any((a) {
      final dbEmail = (a['email'] ?? a['Email'])?.toString().trim().toLowerCase();
      return dbEmail == cleanEmail;
    });
  }

  void _startFirestoreListener(String? uid, String? email,
      {String? displayName, String? photoUrl}) {
    _userSubscription?.cancel();

    if (uid == null) {
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

          // Auto-promote root admins — always ensure isCR, isAdmin, and isApproved are true
          if (isRoot && (data['isCR'] != true || data['isAdmin'] != true || data['isApproved'] != true)) {
            _firestore.collection('users').doc(uid).set(
              {'isCR': true, 'isAdmin': true, 'isApproved': true, 'email': email},
              SetOptions(merge: true),
            );
            data['isCR'] = true;
            data['isAdmin'] = true;
            data['isApproved'] = true;
          }

          final appUser = AppUser.fromMap(data, doc.id);
          _userController.add(appUser);
          if (appUser.hasDeptScope) {
            OneSignalService.setTags(appUser.department, appUser.batch);
            ThemeService.instance.initGlobalThemeListener(
              department: appUser.department,
              batch: appUser.batch,
            );
          }
        } else {
          // Create a new user document
          final newUser = AppUser(
            id: uid,
            email: email ?? '',
            isCR: isRoot,
            isAdmin: isRoot,
            isApproved: isRoot,
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
        await _saveSession(email.trim().toLowerCase(), password.trim(), false);
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
        await _saveSession(cleanEmail, password, false);
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
        
        // Notify the CR of the newly registered student's department and batch
        FCMService.notifyCRNewRegistration(
          studentName: name,
          studentId: studentId,
          department: department,
          batch: batch,
        ).catchError((e) {
          debugPrint('❌ Failed to notify CR of new registration: $e');
        });

        return newUser;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      _userSubscription?.cancel();
      await _clearSession();
      await _auth.signOut();
      _userController.add(null);
    } catch (e) {
      debugPrint(e.toString());
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
      final base64Image = base64Encode(compressedBytes);
      return 'data:image/jpeg;base64,$base64Image';
    } catch (e) {
      rethrow;
    }
  }

  Future<String> uploadProfilePhoto(
      Uint8List fileBytes, String extension) async {
    try {
      final compressedBytes = await compute(_compressImageForChat, fileBytes);
      final base64Image = base64Encode(compressedBytes);
      final dataUrl = 'data:image/jpeg;base64,$base64Image';

      await updateUserProfile(photoUrl: dataUrl);
      return dataUrl;
    } catch (e) {
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
        await _saveSession(firebaseUser.email ?? '', '', true);
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

  Future<void> _saveSession(String email, String password, bool isGoogle) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('auth_session_timestamp', DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('auth_session_email', email);
      await prefs.setString('auth_session_password', password);
      await prefs.setBool('auth_session_is_google', isGoogle);
      debugPrint('[AuthService] Session saved for $email (Google: $isGoogle).');
    } catch (e) {
      debugPrint('[AuthService] Error saving session: $e');
    }
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
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt('auth_session_timestamp');
      if (timestamp != null) {
        final loginTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final difference = DateTime.now().difference(loginTime);
        if (difference.inDays >= 3) {
          debugPrint('[AuthService] Session expired (>= 3 days). Logging out.');
          await signOut();
          return;
        }

        // If Firebase Auth does not have a user, try auto-login
        if (_auth.currentUser == null) {
          final isGoogle = prefs.getBool('auth_session_is_google') ?? false;
          if (isGoogle) {
            debugPrint('[AuthService] Attempting silent Google login...');
            await _signInGoogleSilently();
          } else {
            final email = prefs.getString('auth_session_email');
            final password = prefs.getString('auth_session_password');
            if (email != null && password != null && email.isNotEmpty && password.isNotEmpty) {
              debugPrint('[AuthService] Attempting auto-login for $email...');
              await _auth.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
            }
          }
        }
      } else {
        // No session stored yet. If already logged in, initialize the session now.
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          await _saveSession(currentUser.email ?? '', '', false);
        }
      }
    } catch (e) {
      debugPrint('[AuthService] Error initializing session: $e');
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

/// Compress image inside a background isolate to prevent UI freezes and support instant chat photo encoding
Uint8List _compressImageForChat(Uint8List bytes) {
  try {
    final image = _decodeImageFromBytes(bytes);
    if (image == null) return bytes;

    // Aggressive compression to stay under Firestore's 1MB document limit
    // Target 256px max dimension, quality 70 = ~30-50KB per image
    img.Image resized;
    if (image.width > image.height) {
      resized = img.copyResize(image, width: 256, interpolation: img.Interpolation.nearest);
    } else {
      resized = img.copyResize(image, height: 256, interpolation: img.Interpolation.nearest);
    }

    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  } catch (e) {
    debugPrint('[ChatCompress] Error during background compression: $e');
    return bytes;
  }
}

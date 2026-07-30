import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/supabase_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'models/models.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/pending_approval_screen.dart';
import 'utils/constants.dart';
import 'notifications/fcm_service.dart';
import 'notifications/notification_coordinator.dart';

import 'package:google_fonts/google_fonts.dart';
import 'widgets/network_aware_wrapper.dart';
import 'package:flutter/foundation.dart';

import 'widgets/dept_setup_guard.dart';
import 'widgets/version_aware_wrapper.dart';
import 'widgets/unigrid_loader.dart';

import 'notifications/in_app_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Supabase (used for file/media storage)
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // Register background FCM handler BEFORE anything else
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize notifications asynchronously in the background so they do not block first paint
  FCMService.initialize().catchError((e) {
    debugPrint('Failed to initialize FCM: $e');
  });

  // Initialize 4-path notification system (web→web, web→app, app→web, app→app)
  await NotificationCoordinator.init();

  // Load theme settings dynamically before app start
  await ThemeService.instance.init();

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: !kIsWeb,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeService>(
            create: (_) => ThemeService.instance),
        Provider<AuthService>(create: (_) => AuthService()),
        StreamProvider<AppUser?>(
          create: (context) => context.read<AuthService>().user,
          initialData: null,
        ),
      ],
      child: Consumer<ThemeService>(builder: (context, themeService, _) {
        return MaterialApp(
          navigatorKey: globalNavigatorKey,
          title: 'UniGrid',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            primaryColor: AppColors.primary,
            scaffoldBackgroundColor: AppColors.backgroundTop, // Fallback
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              secondary: AppColors.secondary,
              surface: AppColors.glassCardColor,
              background: AppColors.backgroundBottom,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              iconTheme: IconThemeData(color: AppColors.textPrimary),
              titleTextStyle: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.textSecondary,
              type: BottomNavigationBarType.fixed,
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF1E293B),
              contentTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              actionTextColor: AppColors.secondary,
            ),
            textTheme:
                GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
              bodyColor: AppColors.textPrimary,
              displayColor: AppColors.textPrimary,
            ),
          ),
          home: const NetworkAwareWrapper(
            child: VersionAwareWrapper(
              child: AuthWrapper(),
            ),
          ),
        );
      }),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isRestoringSession = true;

  @override
  void initState() {
    super.initState();
    _initSessionCheck();
  }

  Future<void> _initSessionCheck() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.waitForSessionInit();
    if (mounted) {
      setState(() {
        _isRestoringSession = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AppUser?>(context);
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (_isRestoringSession || firebaseUser != null) {
        // Restoring saved session or waiting for Firestore profile to sync
        return const Scaffold(
          body: Center(
            child: UniGridLoader(
              title: 'Loading workspace...',
              subtitle: 'Restoring your session...',
              showBackground: false,
            ),
          ),
        );
      }
      // Session restoration finished and truly not logged in
      return const LoginScreen();
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = authService.isRootAdmin(user.email);

    Widget nextScreen;
    if (!user.isApproved && !isRootAdmin) {
      // Logged in but awaiting admin approval (non-admin users only)
      nextScreen = const PendingApprovalScreen();
    } else {
      // Logged in and approved (or root admin) — show the app
      nextScreen = const MainScreen();
    }

    // Force all logged-in users to have a Department/Batch set up BEFORE proceeding.
    return DeptSetupGuard(child: nextScreen);
  }
}

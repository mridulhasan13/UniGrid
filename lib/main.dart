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
import 'notifications/notification_router.dart';

import 'package:google_fonts/google_fonts.dart';
import 'widgets/network_aware_wrapper.dart';
import 'package:flutter/foundation.dart';

import 'widgets/dept_setup_guard.dart';
import 'widgets/maintenance_guard.dart';
import 'widgets/unigrid_loader.dart';
import 'utils/web_bridge.dart';

import 'notifications/in_app_notification.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and Supabase concurrently for ultra-fast startup
  await Future.wait([
    Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ),
    Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    ),
  ]);

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: !kIsWeb,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Balanced image cache: fast rendering without exceeding web browser memory ceilings
  PaintingBinding.instance.imageCache.maximumSize = kIsWeb ? 200 : 1000;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      kIsWeb ? (30 * 1024 * 1024) : (120 * 1024 * 1024); // 30MB on Web, 120MB on Native

  // Asynchronous non-blocking background initialization
  FCMService.initialize().catchError((e) {
    debugPrint('FCM init notice: $e');
  });
  NotificationCoordinator.init().catchError((e) {
    debugPrint('NotificationCoordinator init notice: $e');
  });
  SupabaseConfig.syncFromCloud().catchError((e) {
    debugPrint('Supabase cloud config notice: $e');
  });
  ThemeService.instance.init();

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
            appBarTheme: AppBarTheme(
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
              backgroundColor: AppColors.glassCardColor,
              contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              actionTextColor: AppColors.secondary,
            ),
            textTheme:
                GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
              bodyColor: AppColors.textPrimary,
              displayColor: AppColors.textPrimary,
            ),
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.windows: ZoomPageTransitionsBuilder(),
                TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
                TargetPlatform.linux: ZoomPageTransitionsBuilder(),
              },
            ),
          ),
          scrollBehavior: const MaterialScrollBehavior().copyWith(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          ),
          home: const NetworkAwareWrapper(
            child: AuthWrapper(),
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
    // Pre-cache core brand & profile assets in parallel and notify web container
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyAppLoaded();
      try {
        precacheImage(const AssetImage('assets/images/logo.png'), context);
        precacheImage(const AssetImage('assets/images/mridul_profile.png'), context);
      } catch (_) {}
    });
    await authService.waitForSessionInit();
    if (mounted) {
      setState(() {
        _isRestoringSession = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyAppLoaded();
        NotificationRouter.processPendingNotification();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestoringSession) {
      return const Scaffold(
        body: Center(
          child: UniGridLoader(
            title: 'Loading UniGrid...',
            subtitle: 'Restoring your session...',
            showBackground: false,
          ),
        ),
      );
    }

    final user = Provider.of<AppUser?>(context);
    final firebaseUser = FirebaseAuth.instance.currentUser;

    // 1. Truly logged out (no Firebase Auth session and no AppUser profile)
    if (firebaseUser == null && user == null) {
      return const LoginScreen();
    }

    // 2. Firebase Auth session exists, but Firestore AppUser profile is still syncing
    if (user == null) {
      return const Scaffold(
        body: Center(
          child: UniGridLoader(
            title: 'Loading workspace...',
            subtitle: 'Syncing your profile...',
            showBackground: false,
          ),
        ),
      );
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

    // Enforce scheduled maintenance mode & force dept setup
    return MaintenanceGuard(
      child: DeptSetupGuard(child: nextScreen),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'materials_screen.dart';
import 'chat_screen.dart';
import 'cr_panel_screen.dart';
import 'profile_screen.dart';
import 'master_panel_screen.dart';
import '../services/auth_service.dart';

import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../widgets/glass_card.dart';
import '../notifications/notification_router.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  static final ValueNotifier<int> tabNotifier = ValueNotifier<int>(0);

  /// Programmatically switch tabs from anywhere (e.g. notification clicks)
  static void switchTab(int index) {
    tabNotifier.value = index;
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = MainScreen.tabNotifier.value;
    MainScreen.tabNotifier.addListener(_onTabChanged);

    // Process any pending notification tap once MainScreen is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationRouter.processPendingNotification();
    });
  }

  @override
  void dispose() {
    MainScreen.tabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted && _currentIndex != MainScreen.tabNotifier.value) {
      setState(() {
        _currentIndex = MainScreen.tabNotifier.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);

    if (user != null) {
      RoutineReminderService.syncRoutineReminders(user);
    }

    final List<Widget> screens = [
      const HomeScreen(),
      const ScheduleScreen(),
      const MaterialsScreen(),
      const ChatScreen(),
      if (user != null && (user.isCR || isRootAdmin))
        const CRPanelScreen(),
      if (isRootAdmin)
        const MasterPanelScreen(),
      const ProfileScreen(),
    ];

    final List<BottomNavigationBarItem> navItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today), label: 'Schedule'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.folder), label: 'Materials'),
      const BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
      if (user != null && (user.isCR || isRootAdmin))
        const BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings), label: 'CR Panel'),
      if (isRootAdmin)
        const BottomNavigationBarItem(
            icon: Icon(Icons.security), label: 'Master'),
      const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
    ];

    // Safety: reset index if out of bounds (happens when CR Panel is added/removed)
    if (_currentIndex >= screens.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 0);
      });
    }
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.mainBackground,
        ),
        child: Stack(
          children: [
            // Main Content
            IndexedStack(
              index: safeIndex,
              children: screens,
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom > 0
              ? MediaQuery.of(context).padding.bottom + 8
              : 16,
        ),
        decoration: BoxDecoration(
          color: AppColors.glassCardColor.withOpacity(0.92), // Deeper backdrop to hide scrolling content
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.glassCardBorder,
            width: 1.5,
          ),
          boxShadow: [
            // Strong drop shadow to place the bar "above of all elements"
            BoxShadow(
              color: Colors.black.withOpacity(0.55),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            // Theme-colored ambient glow
            BoxShadow(
              color: AppColors.primary.withOpacity(0.12),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.textPrimary.withOpacity(0.06),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final isSelected = index == safeIndex;

                  IconData iconData = Icons.help;
                  if (item.icon is Icon) {
                    iconData = (item.icon as Icon).icon ?? Icons.help;
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _currentIndex = index;
                      });
                      MainScreen.tabNotifier.value = index;
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
                      child: Icon(
                        iconData,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 26,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

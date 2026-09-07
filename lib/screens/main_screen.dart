import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../notifications/notification_router.dart';
import '../notifications/routine_reminder_service.dart';

import '../notifications/web_to_app/wa_receiver.dart';

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
  String? _lastSyncedUserId;
  final Map<int, Widget> _cachedScreens = {};
  bool? _lastIsCR;
  bool? _lastIsRootAdmin;

  void _clearHistoryForTab(int tabIndex) {
    if (tabIndex == 0) {
      WAReceiver.clearHistory('unigrid_alerts').catchError((_) {});
    } else if (tabIndex == 1) {
      WAReceiver.clearHistory('unigrid_routine').catchError((_) {});
    } else if (tabIndex == 2) {
      WAReceiver.clearHistory('unigrid_materials').catchError((_) {});
    } else if (tabIndex == 3) {
      WAReceiver.clearHistory('batch_chat').catchError((_) {});
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = MainScreen.tabNotifier.value;
    if (_currentIndex == 3) {
      NotificationRouter.activeChatId = 'group_chat';
    }
    _clearHistoryForTab(_currentIndex);
    MainScreen.tabNotifier.addListener(_onTabChanged);

    // Process any pending notification tap once MainScreen is mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationRouter.processPendingNotification();
    });
  }

  @override
  void dispose() {
    if (NotificationRouter.activeChatId == 'group_chat') {
      NotificationRouter.activeChatId = null;
    }
    MainScreen.tabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted && _currentIndex != MainScreen.tabNotifier.value) {
      setState(() {
        _currentIndex = MainScreen.tabNotifier.value;
      });
      _clearHistoryForTab(_currentIndex);
      if (_currentIndex == 3) {
        NotificationRouter.activeChatId = 'group_chat';
      } else if (NotificationRouter.activeChatId == 'group_chat') {
        NotificationRouter.activeChatId = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);

    if (user != null && _lastSyncedUserId != user.id) {
      _lastSyncedUserId = user.id;
      RoutineReminderService.syncRoutineReminders(user);
    }

    final isCR = user != null && user.isCR;
    if (_lastIsCR != isCR || _lastIsRootAdmin != isRootAdmin) {
      _lastIsCR = isCR;
      _lastIsRootAdmin = isRootAdmin;
      _cachedScreens.clear();
    }

    final safeIndex = _currentIndex.clamp(0, 6);

    final List<Widget Function()> screenBuilders = [
      () => const RepaintBoundary(child: HomeScreen()),
      () => const RepaintBoundary(child: ScheduleScreen()),
      () => const RepaintBoundary(child: MaterialsScreen()),
      () => const RepaintBoundary(child: ChatScreen()),
      if (user != null && (user.isCR || isRootAdmin))
        () => const RepaintBoundary(child: CRPanelScreen()),
      if (isRootAdmin)
        () => const RepaintBoundary(child: MasterPanelScreen()),
      () => const RepaintBoundary(child: ProfileScreen()),
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
    if (_currentIndex >= screenBuilders.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = 0);
      });
    }

    // Cache the active screen so its state and listeners stay alive
    if (!_cachedScreens.containsKey(safeIndex) && safeIndex < screenBuilders.length) {
      _cachedScreens[safeIndex] = screenBuilders[safeIndex]();
    }

    final List<Widget> lazyScreens = List.generate(screenBuilders.length, (i) {
      if (_cachedScreens.containsKey(i)) {
        return _cachedScreens[i]!;
      }
      return const SizedBox.shrink();
    });

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppGradients.mainBackground,
        ),
        child: Stack(
          children: [
            // Main Content with Lazy Initialization
            IndexedStack(
              index: safeIndex.clamp(0, lazyScreens.length - 1),
              children: lazyScreens,
            ),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
          ? const SizedBox.shrink()
          : Container(
              margin: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom > 0
                    ? MediaQuery.of(context).padding.bottom + 8
                    : 16,
              ),
              decoration: BoxDecoration(
                color: AppColors.glassCardColor.withOpacity(0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.glassCardBorder,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.isLight
                        ? Colors.black.withOpacity(0.08)
                        : Colors.black.withOpacity(0.55),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.12),
                    blurRadius: 16,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4.0, vertical: 4.0),
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
    );
  }
}

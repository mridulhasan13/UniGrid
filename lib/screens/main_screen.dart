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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    Provider.of<ThemeService>(context); // Listen to global theme updates
    final user = Provider.of<AppUser?>(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final isRootAdmin = user != null && authService.isRootAdmin(user.email);

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
      bottomNavigationBar: GlassCard(
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom > 0
              ? MediaQuery.of(context).padding.bottom + 8
              : 16,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        borderRadius: 24,
        opacity: 0.3,
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
    );
  }
}

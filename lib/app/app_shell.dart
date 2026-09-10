import 'package:flutter/material.dart';

import '../screens/home/home_screen.dart';
import '../screens/media/media_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/transfers/transfers_screen.dart';
import '../theme/theme.dart';
import '../models/device.dart';
import 'app_controller.dart';

/// Root scaffold: shared [AppController] + bottom navigation.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          _HomeTabShell(controller: widget.controller),
          TransfersScreen(controller: widget.controller),
          MediaScreen(controller: widget.controller),
          SettingsScreen(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Transfers',
              ),
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library),
                label: 'Media',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTabShell extends StatelessWidget {
  const _HomeTabShell({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    // Listen to the controller (receiving/error state) AND the device list.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ValueListenableBuilder<List<TransferDevice>>(
          valueListenable: controller.devices,
          builder: (context, devices, _) {
            return HomeScreen(
              controller: controller,
              devices: devices,
            );
          },
        );
      },
    );
  }
}
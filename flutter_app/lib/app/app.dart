import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/features/home/home_screen.dart';
import 'package:btmu/features/import_center/import_center_screen.dart';
import 'package:btmu/features/library/library_screen.dart';
import 'package:btmu/features/player/mini_player.dart';
import 'package:btmu/features/playlists/playlists_screen.dart';
import 'package:btmu/features/x1/x1_screen.dart';
import 'package:btmu/features/x2/x2_screen.dart';

class BttMusicApp extends StatelessWidget {
  const BttMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Btt Music',
      debugShowCheckedModeBanner: false,
      theme: BttTheme.buildDarkTheme(),
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _screens = <Widget>[
    HomeScreen(),
    LibraryScreen(),
    ImportCenterScreen(),
    X2Screen(),
    X1Screen(),
    PlaylistsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIdx = ref.watch(currentTabIndexProvider).clamp(0, _screens.length - 1);

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: tabIdx,
            children: _screens,
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MiniPlayer(),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: BttColors.bgElevated,
        indicatorColor: BttColors.cyanAccent.withValues(alpha: 0.18),
        selectedIndex: tabIdx,
        onDestinationSelected: (idx) {
          // One light tick per real tab change only — tapping the tab
          // you are already on stays silent.
          if (idx != tabIdx) HapticFeedback.selectionClick();
          ref.read(currentTabIndexProvider.notifier).state = idx;
        },
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: BttColors.cyanAccent),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded, color: BttColors.cyanAccent),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded, color: BttColors.greenAccent),
            label: 'Import',
          ),
          NavigationDestination(
            icon: Icon(Icons.travel_explore_outlined),
            selectedIcon: Icon(Icons.travel_explore_rounded, color: BttColors.goldAccent),
            label: 'X2',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_none_rounded),
            selectedIcon: Icon(Icons.mic_rounded, color: BttColors.cyanAccent),
            label: 'X1',
          ),
          NavigationDestination(
            icon: Icon(Icons.queue_music_outlined),
            selectedIcon: Icon(Icons.queue_music_rounded, color: BttColors.goldAccent),
            label: 'Playlists',
          ),
        ],
      ),
    );
  }
}

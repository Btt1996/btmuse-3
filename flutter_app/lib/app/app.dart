import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/features/home/home_screen.dart';
import 'package:btmu/features/import_center/import_center_screen.dart';
import 'package:btmu/features/library/library_screen.dart';
import 'package:btmu/features/player/mini_player.dart';

class BttMusicApp extends ConsumerWidget {
  const BttMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // v3.0.5, items 9 + 12: the theme (palette + layout) and the custom
    // font are live state — changing either in Settings rebuilds the app
    // immediately, no restart. applyVariant keeps the BttColors statics
    // (used directly by screens) in sync with the provider.
    final variant = ref.watch(themeVariantProvider);
    final customFontFamily = ref.watch(customFontFamilyProvider);
    BttColors.applyVariant(variant);
    return MaterialApp(
      title: 'Btmus',
      debugShowCheckedModeBanner: false,
      theme: BttTheme.buildDarkTheme(
        variant: variant,
        customFontFamily: customFontFamily,
      ),
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  // v3.0.5, item 15: three tabs only. X1/X2 are pushed routes (from
  // Home / Import Center) and Playlists lives inside Library.
  static const _screens = <Widget>[
    HomeScreen(),
    LibraryScreen(),
    ImportCenterScreen(),
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
          // MiniPlayer floats above the pill, never under it — bottom
          // 84 clears the pill (12 bottom + 62 tall) with room to spare.
          // It stays inside AppShell (below the Navigator) so the Hero
          // artwork morph to FullScreenPlayer keeps working.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 84,
            child: MiniPlayer(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: _FloatingNavBar(
              selectedIndex: tabIdx,
              onSelected: (idx) {
                // One light tick per real tab change only — tapping the
                // tab you are already on stays silent.
                if (idx != tabIdx) HapticFeedback.selectionClick();
                ref.read(currentTabIndexProvider.notifier).state = idx;
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// v3.0.5, item 15: the bottom bar is a floating pill, not a fixed
/// NavigationBar glued to the bottom edge. Three destinations only:
/// Home, Import, Library (pill order; indices follow [BttTab]).
class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: BttColors.bgElevated,
        borderRadius: BorderRadius.circular(31),
        border: Border.all(color: BttColors.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _navItem(
            context,
            tabIndex: BttTab.home,
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'Home',
            accent: BttColors.accentPink,
          ),
          _navItem(
            context,
            tabIndex: BttTab.importCenter,
            icon: Icons.add_circle_outline_rounded,
            selectedIcon: Icons.add_circle_rounded,
            label: 'Import',
            accent: BttColors.accentMagenta,
          ),
          _navItem(
            context,
            tabIndex: BttTab.library,
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music_rounded,
            label: 'Library',
            accent: BttColors.accentPink,
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required int tabIndex,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required Color accent,
  }) {
    final selected = selectedIndex == tabIndex;
    final color = selected ? accent : BttColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(tabIndex),
        borderRadius: BorderRadius.circular(31),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

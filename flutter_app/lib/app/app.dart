import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:btmu/app/providers/app_providers.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/core/deep_link.dart';
import 'package:btmu/data/models/track.dart';
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
      home: const DeepLinkBootstrap(child: AppShell()),
    );
  }
}

/// Handles every link that reaches the app from outside (v3.0.5, batch 2,
/// item 13): Siri deep links.
///
/// Deep links arrive through the native bridge as [BttDeepLinkAction]s
/// (see [parseBttDeepLink]); this widget consumes them one at a time and
/// performs the side effect — navigation or playback. Unknown links are
/// ignored. A Siri request for a playlist that does not exist does
/// nothing: playback is never faked.
class DeepLinkBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  const DeepLinkBootstrap({super.key, required this.child});

  @override
  ConsumerState<DeepLinkBootstrap> createState() => _DeepLinkBootstrapState();
}

class _DeepLinkBootstrapState extends ConsumerState<DeepLinkBootstrap> {
  @override
  void initState() {
    super.initState();
    // Instantiate the bridge (registers the onLink handler) and handle
    // a cold-launch link.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialLink();
    });
  }

  Future<void> _handleInitialLink() async {
    final raw = await ref.read(nativeBridgeProvider).getInitialLink();
    if (raw != null && raw.isNotEmpty && mounted) {
      ref.read(pendingDeepLinkActionProvider.notifier).state =
          parseBttDeepLink(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BttDeepLinkAction?>(pendingDeepLinkActionProvider,
        (_, action) {
      if (action != null) {
        ref.read(pendingDeepLinkActionProvider.notifier).state = null;
        _handleAction(action);
      }
    });
    return widget.child;
  }

  Future<void> _handleAction(BttDeepLinkAction action) async {
    switch (action) {
      case SiriPlayDeepLink(:final shuffle):
        await _playSiri(shuffle: shuffle, playlistName: null);
      case SiriPlaylistDeepLink(:final playlistName):
        await _playSiri(shuffle: false, playlistName: playlistName);
      case UnknownDeepLink():
        break;
    }
  }

  Future<void> _playSiri({
    required bool shuffle,
    required String? playlistName,
  }) async {
    final handler = ref.read(audioHandlerProvider);
    if (playlistName != null) {
      final playlists =
          await ref.read(playlistRepositoryProvider).getAllPlaylists();
      final match = playlists
          .where((pl) =>
              pl.name.trim().toLowerCase() ==
              playlistName.trim().toLowerCase())
          .toList();
      if (match.isEmpty) return;
      final ids = match.first.trackIds;
      if (ids.isEmpty) return;
      final all = await ref.read(libraryRepositoryProvider).getAllTracks();
      final byId = {for (final t in all) t.id: t};
      final tracks =
          [for (final id in ids) byId[id]].whereType<Track>().toList();
      if (tracks.isEmpty) return;
      if (shuffle) {
        await handler.setShuffleMode(AudioServiceShuffleMode.all);
      }
      await handler.setTrackQueueAndPlay(tracks,
          sourceLabel: 'Siri: $playlistName');
      return;
    }
    if (shuffle) {
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
    }
    if (handler.currentTrack != null) {
      await handler.play();
    } else if (handler.currentTracks.isNotEmpty) {
      await handler.playTrackAtIndex(0);
    }
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

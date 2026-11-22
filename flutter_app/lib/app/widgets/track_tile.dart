import 'package:flutter/material.dart';
import 'package:btmu/app/theme/btt_theme.dart';
import 'package:btmu/app/widgets/btt_artwork.dart';
import 'package:btmu/data/models/track.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onMorePressed;

  const TrackTile({
    super.key,
    required this.track,
    required this.isCurrent,
    required this.onTap,
    this.onFavoriteToggle,
    this.onMorePressed,
  });

  @override
  Widget build(BuildContext context) {
    final durStr = _formatDuration(track.durationSeconds);

    return Material(
      color: isCurrent ? BttColors.bgCardHighlight : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              BttArtwork(
                artworkPath: track.artworkPath,
                artworkUrl: track.artworkUrl,
                size: 52,
                radius: 12,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isCurrent
                                ? BttColors.cyanAccent
                                : BttColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${track.artist}  ·  ${track.format}$durStr',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (onFavoriteToggle != null)
                IconButton(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(
                    track.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: track.isFavorite ? BttColors.goldAccent : BttColors.textMuted,
                    size: 21,
                  ),
                  onPressed: onFavoriteToggle,
                ),
              if (onMorePressed != null)
                IconButton(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: BttColors.textSecondary,
                  ),
                  onPressed: onMorePressed,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '  ·  $m:$s';
  }
}

import 'dart:math' as math;
import '../../data/models/smart_remix_config.dart';
import '../../data/models/track.dart';

class RemixPlanEntry {
  final Track track;
  final double effectiveBpm;
  final double effectiveEnergy;
  final double transitionScore;
  final bool usesHeuristicFallback;

  const RemixPlanEntry({
    required this.track,
    required this.effectiveBpm,
    required this.effectiveEnergy,
    required this.transitionScore,
    required this.usesHeuristicFallback,
  });
}

/// Smart Remix sequencing: orders a track list into a playback plan.
///
/// Energy-arc mapping, verified Phase 6 against the sorts in
/// [buildMixOrder] (warm-up → build → peak → cooldown is the Λ arc):
///
/// * [SmartRemixMode.chillMix] — warm-up → build → peak. Ascending
///   energy; ends at the peak, no cooldown.
/// * [SmartRemixMode.energyMix] — peak → cooldown. Descending energy;
///   starts at the peak, no warm-up.
/// * [SmartRemixMode.partyMix] — peak first. Descending combined
///   energy/BPM score; a peak block, not an arc.
/// * [SmartRemixMode.smoothMix] — no global arc. Nearest-neighbour
///   chaining minimises step-to-step BPM/energy jumps from the first
///   track, so the overall shape follows wherever the library order
///   starts; it is continuity, not a designed arc.
/// * [SmartRemixMode.randomSmartMix] — no arc. Deterministic shuffle
///   (seeded when [seed] is given).
/// * [SmartRemixMode.arcMix] — the full Λ arc (added Phase 6).
///   Ascending energy up to and including the peak track, then
///   descending: warm-up → build → peak → cooldown.
///
/// The save-as-playlist action on `SmartRemixScreen` persists exactly
/// the order the selected mode produced, so what is saved is what the
/// mapping above describes.
class SmartRemixEngine {
  static (double bpm, double energy, bool heuristic) resolveFeatures(Track track) {
    if (track.bpm != null && track.energyScore != null && !track.isAnalysisEstimated) {
      return (track.bpm!, track.energyScore!.clamp(0.0, 1.0), false);
    }

    // Honest deterministic heuristic estimate derived from genre/duration/format when PCM analysis is unavailable.
    final text = '${track.title} ${track.album} ${track.genre ?? ''}'.toLowerCase();
    var bpm = 112.0;
    var energy = 0.55;

    if (text.contains('chill') || text.contains('ambient') || text.contains('lofi')) {
      bpm = 84.0;
      energy = 0.28;
    } else if (text.contains('remix') || text.contains('club') || text.contains('dance') || text.contains('edm')) {
      bpm = 126.0;
      energy = 0.88;
    } else if (text.contains('hip') || text.contains('rap') || text.contains('trap')) {
      bpm = 96.0;
      energy = 0.72;
    } else if (text.contains('rock') || text.contains('metal')) {
      bpm = 132.0;
      energy = 0.84;
    } else if (track.durationSeconds > 300) {
      bpm = 104.0;
      energy = 0.45;
    }

    return (bpm, energy, true);
  }

  static List<RemixPlanEntry> buildMixOrder({
    required List<Track> tracks,
    required SmartRemixMode mode,
    int? seed,
  }) {
    if (tracks.isEmpty) return [];

    final enriched = tracks.map((t) {
      final (bpm, energy, heuristic) = resolveFeatures(t);
      return (track: t, bpm: bpm, energy: energy, heuristic: heuristic);
    }).toList();

    switch (mode) {
      case SmartRemixMode.chillMix:
        enriched.sort((a, b) => a.energy.compareTo(b.energy));
      case SmartRemixMode.energyMix:
        enriched.sort((a, b) => b.energy.compareTo(a.energy));
      case SmartRemixMode.partyMix:
        enriched.sort((a, b) {
          final aScore = a.energy * 0.65 + (a.bpm / 160.0) * 0.35;
          final bScore = b.energy * 0.65 + (b.bpm / 160.0) * 0.35;
          return bScore.compareTo(aScore);
        });
      case SmartRemixMode.randomSmartMix:
        final rng = math.Random(seed);
        enriched.shuffle(rng);
      case SmartRemixMode.arcMix:
        // Full Λ arc: warm-up → build → peak → cooldown.
        // Sort ascending by energy, lift the peak out, then run the
        // lower half up to the peak and the upper half back down.
        // (2 tracks degrade to peak-then-down; 1 track is just itself.)
        enriched.sort((a, b) => a.energy.compareTo(b.energy));
        final peak = enriched.removeLast();
        final ascendingCount = enriched.length ~/ 2;
        final arc = [
          ...enriched.sublist(0, ascendingCount),
          peak,
          ...enriched.sublist(ascendingCount).reversed,
        ];
        enriched
          ..clear()
          ..addAll(arc);
      case SmartRemixMode.smoothMix:
        // Nearest-neighbor BPM & energy chaining for smoothest transitions
        final remaining = List.of(enriched);
        final ordered = [remaining.removeAt(0)];
        while (remaining.isNotEmpty) {
          final prev = ordered.last;
          remaining.sort((a, b) {
            final distA = (a.bpm - prev.bpm).abs() / 40.0 + (a.energy - prev.energy).abs();
            final distB = (b.bpm - prev.bpm).abs() / 40.0 + (b.energy - prev.energy).abs();
            return distA.compareTo(distB);
          });
          ordered.add(remaining.removeAt(0));
        }
        enriched
          ..clear()
          ..addAll(ordered);
    }

    final result = <RemixPlanEntry>[];
    for (var i = 0; i < enriched.length; i++) {
      final item = enriched[i];
      double score = 1.0;
      if (i > 0) {
        final prev = enriched[i - 1];
        final bpmDiff = (item.bpm - prev.bpm).abs();
        final energyDiff = (item.energy - prev.energy).abs();
        score = (1.0 - (bpmDiff / 60.0) * 0.5 - energyDiff * 0.5).clamp(0.1, 1.0);
      }
      result.add(
        RemixPlanEntry(
          track: item.track,
          effectiveBpm: item.bpm,
          effectiveEnergy: item.energy,
          transitionScore: score,
          usesHeuristicFallback: item.heuristic,
        ),
      );
    }
    return result;
  }
}

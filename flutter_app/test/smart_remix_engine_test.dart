import 'package:flutter_test/flutter_test.dart';
import 'package:btmu/data/models/smart_remix_config.dart';
import 'package:btmu/data/models/track.dart';
import 'package:btmu/features/smart_remix/smart_remix_engine.dart';

Track _makeTrack(String id, String title, {double? bpm, double? energy, bool est = false}) {
  return Track(
    id: id,
    title: title,
    artist: 'Artist',
    album: 'Album',
    durationSeconds: 180,
    localFilePath: '/tmp/$id.mp3',
    format: 'MP3',
    fileSizeBytes: 1024,
    sha256: id,
    sourceProvider: 'local',
    addedAtMs: 0,
    bpm: bpm,
    energyScore: energy,
    isAnalysisEstimated: est,
  );
}

void main() {
  test('Chill Mix sorts ascending by energy and Energy Mix sorts descending', () {
    final t1 = _makeTrack('1', 'High', bpm: 130, energy: 0.92);
    final t2 = _makeTrack('2', 'Low', bpm: 80, energy: 0.20);
    final t3 = _makeTrack('3', 'Mid', bpm: 108, energy: 0.55);

    final chill = SmartRemixEngine.buildMixOrder(
      tracks: [t1, t2, t3],
      mode: SmartRemixMode.chillMix,
    );
    expect(chill.map((e) => e.track.id).toList(), ['2', '3', '1']);

    final energy = SmartRemixEngine.buildMixOrder(
      tracks: [t1, t2, t3],
      mode: SmartRemixMode.energyMix,
    );
    expect(energy.map((e) => e.track.id).toList(), ['1', '3', '2']);
  });

  test('Heuristic fallback flag is reported transparently for unanalyzed tracks', () {
    final unanalyzed = _makeTrack('u1', 'Chill Rain Ambient', est: true);
    final plan = SmartRemixEngine.buildMixOrder(
      tracks: [unanalyzed],
      mode: SmartRemixMode.smoothMix,
    );
    expect(plan.first.usesHeuristicFallback, isTrue);
  });
}

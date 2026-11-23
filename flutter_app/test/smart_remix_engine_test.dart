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

  test('Arc halves: Chill Mix ends at the peak, Energy Mix starts at the peak', () {
    // Phase 6 verified mapping: chillMix is warm-up -> build -> peak
    // (ascending energy, no cooldown); energyMix is peak -> cooldown
    // (descending energy, no warm-up). The full warm-up -> build ->
    // peak -> cooldown arc is Arc Mix (added Phase 6, coordinator);
    // see the 'Arc Mix produces the full arc' test below.
    final t1 = _makeTrack('1', 'High', bpm: 130, energy: 0.92);
    final t2 = _makeTrack('2', 'Low', bpm: 80, energy: 0.20);
    final t3 = _makeTrack('3', 'Mid', bpm: 108, energy: 0.55);

    final chill = SmartRemixEngine.buildMixOrder(
      tracks: [t1, t2, t3],
      mode: SmartRemixMode.chillMix,
    );
    expect(chill.last.track.id, '1');
    expect(chill.first.track.id, '2');

    final energy = SmartRemixEngine.buildMixOrder(
      tracks: [t1, t2, t3],
      mode: SmartRemixMode.energyMix,
    );
    expect(energy.first.track.id, '1');
    expect(energy.last.track.id, '2');
  });

  test('Party Mix orders by combined energy/BPM score descending', () {
    // Score = energy * 0.65 + (bpm / 160) * 0.35.
    // A: 0.9*0.65 + 80/160*0.35 = 0.760; B: 0.5*0.65 + 1.0*0.35 = 0.675;
    // C: 0.7*0.65 + 120/160*0.35 = 0.7175. Order: A, C, B — a peak
    // block, not an arc: BPM can outrank a higher-energy track.
    final a = _makeTrack('a', 'A', bpm: 80, energy: 0.9);
    final b = _makeTrack('b', 'B', bpm: 160, energy: 0.5);
    final c = _makeTrack('c', 'C', bpm: 120, energy: 0.7);

    final party = SmartRemixEngine.buildMixOrder(
      tracks: [b, c, a],
      mode: SmartRemixMode.partyMix,
    );
    expect(party.map((e) => e.track.id).toList(), ['a', 'c', 'b']);
  });

  test('Smooth Mix chains nearest neighbours from the first track', () {
    // Input order anchors the chain: starting at High, Mid is nearer
    // than Low (BPM 40/40 + energy 0.4 = 1.4 vs BPM 60/40 + energy
    // 0.7 = 2.2), so the chain is High -> Mid -> Low. No global arc:
    // the shape follows the starting track.
    final high = _makeTrack('h', 'High', bpm: 140, energy: 0.9);
    final low = _makeTrack('l', 'Low', bpm: 80, energy: 0.2);
    final mid = _makeTrack('m', 'Mid', bpm: 100, energy: 0.5);

    final smooth = SmartRemixEngine.buildMixOrder(
      tracks: [high, low, mid],
      mode: SmartRemixMode.smoothMix,
    );
    expect(smooth.map((e) => e.track.id).toList(), ['h', 'm', 'l']);
  });

  test('Random Smart Mix is deterministic with a seed', () {
    final tracks = [
      _makeTrack('1', 'One', bpm: 100, energy: 0.5),
      _makeTrack('2', 'Two', bpm: 110, energy: 0.6),
      _makeTrack('3', 'Three', bpm: 120, energy: 0.7),
      _makeTrack('4', 'Four', bpm: 130, energy: 0.8),
      _makeTrack('5', 'Five', bpm: 140, energy: 0.9),
    ];
    final first = SmartRemixEngine.buildMixOrder(
      tracks: tracks,
      mode: SmartRemixMode.randomSmartMix,
      seed: 7,
    );
    final second = SmartRemixEngine.buildMixOrder(
      tracks: tracks,
      mode: SmartRemixMode.randomSmartMix,
      seed: 7,
    );
    expect(
      first.map((e) => e.track.id).toList(),
      second.map((e) => e.track.id).toList(),
    );
    expect(first.map((e) => e.track.id).toSet(), {'1', '2', '3', '4', '5'});
  });

  test('Arc Mix produces the full warm-up → peak → cooldown arc', () {
    // Phase 6 (coordinator): ascending energies up to and including the
    // peak track, then descending. The peak sits mid-list, never at an
    // end (for 3+ tracks). Sorted energies here: 0.20, 0.55, 0.60, 0.75,
    // 0.92 — peak 0.92, lower half ascends to it, upper half descends.
    final t1 = _makeTrack('1', 'High', bpm: 130, energy: 0.92);
    final t2 = _makeTrack('2', 'Low', bpm: 80, energy: 0.20);
    final t3 = _makeTrack('3', 'Mid', bpm: 108, energy: 0.55);
    final t4 = _makeTrack('4', 'MidHigh', bpm: 120, energy: 0.75);
    final t5 = _makeTrack('5', 'MidLow', bpm: 100, energy: 0.60);

    final arc = SmartRemixEngine.buildMixOrder(
      tracks: [t1, t2, t3, t4, t5],
      mode: SmartRemixMode.arcMix,
    );
    expect(arc.map((e) => e.track.id).toList(), ['2', '3', '1', '4', '5']);
    final energies = arc.map((e) => e.effectiveEnergy).toList();
    expect(energies[1] > energies[0], isTrue);
    expect(energies[2], 0.92);
    expect(energies[3] < energies[2], isTrue);
    expect(energies[4] < energies[3], isTrue);
  });
}

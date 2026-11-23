import React, { useState } from 'react';
import {
  Play,
  Heart,
  RefreshCw,
  Sparkles,
  Sliders,
  Activity,
  Download,
  Search,
  Wifi,
  WifiOff,
  Music,
  CheckCircle2,
  Wrench,
} from 'lucide-react';
import { useMusic } from '../../context/MusicContext';
import { formatDuration, formatFileSize } from '../../utils/id3Parser';
import { useOnlineStatus } from '../../hooks/useOnlineStatus';
import { OnboardingView } from './OnboardingView';
import { Track } from '../../types/music';
import { SmartMixDrawer } from '../player/SmartMixDrawer';
import { PlaylistImportModal } from '../import/PlaylistImportModal';
import { executeSmartSynchro, SynchroProgress } from '../../services/smartSynchroService';
import { triggerHaptic } from '../../services/nativeAudioBridge';

interface HomeScreenProps {
  onGoToTab: (tab: 'home' | 'search' | 'library' | 'playlists' | 'sync' | 'settings' | 'import') => void;
  onOpenPlaylist: (playlistId: string) => void;
  onTriggerFileInput: () => void;
}

export const HomeScreen: React.FC<HomeScreenProps> = ({
  onGoToTab,
  onOpenPlaylist,
  onTriggerFileInput,
}) => {
  const {
    tracks,
    playTrack,
    toggleFavorite,
    storageStats,
    playerState,
    trackAnalyses,
    refreshLibrary,
    showToast,
  } = useMusic();
  const isOnline = useOnlineStatus();
  const [isSmartMixDrawerOpen, setIsSmartMixDrawerOpen] = useState(false);
  const [isImportModalOpen, setIsImportModalOpen] = useState(false);
  const [isSynchroRunning, setIsSynchroRunning] = useState(false);
  const [synchroStatus, setSynchroStatus] = useState<string | null>(null);

  const getGreeting = () => {
    const hour = new Date().getHours();
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  };

  if (tracks.length === 0) {
    return (
      <OnboardingView
        onGoToSync={() => onGoToTab('sync')}
        onTriggerFileInput={onTriggerFileInput}
      />
    );
  }

  const recentlyPlayed = [...tracks]
    .filter((t) => (t.playCount && t.playCount > 0) || t.lastPlayedAt)
    .sort((a, b) => (b.lastPlayedAt || 0) - (a.lastPlayedAt || 0))
    .slice(0, 8);

  const favoriteTracks = tracks.filter((t) => t.isFavorite).slice(0, 8);
  const recentlyAdded = [...tracks].sort((a, b) => b.downloadDate - a.downloadDate).slice(0, 8);
  const smartMixConfig = playerState.smartMixConfig;

  const handleRunSmartSynchro = async () => {
    triggerHaptic();
    if (isSynchroRunning) return;
    setIsSynchroRunning(true);
    setSynchroStatus('Scanning library...');

    try {
      const res = await executeSmartSynchro(
        {
          enrichMetadata: true,
          fetchMissingArtwork: true,
          healPlaylists: true,
          currentlyPlayingTrackId: playerState.currentTrack?.id,
        },
        (progress: SynchroProgress) => {
          if (progress.stage === 'scanning') {
            setSynchroStatus('Scanning tags & artwork...');
          } else if (progress.stage === 'fetching_artwork' || progress.stage === 'enriching_metadata') {
            setSynchroStatus(`Matching: ${progress.currentTrackTitle || ''} (${progress.current}/${progress.total})`);
          } else if (progress.stage === 'healing_playlists') {
            setSynchroStatus('Healing playlists...');
          }
        }
      );

      await refreshLibrary();
      showToast(`Smart Synchro complete: ${res.repairedTracks} tracks repaired!`);
      setSynchroStatus(`Synchronized & healed ${res.repairedTracks} tracks`);
      setTimeout(() => setSynchroStatus(null), 4000);
    } catch {
      showToast('Smart Synchro scan encountered an issue.');
      setSynchroStatus(null);
    } finally {
      setIsSynchroRunning(false);
    }
  };

  return (
    <div className="flex-1 overflow-y-auto px-4 pt-notch pb-28 space-y-7 max-w-lg mx-auto w-full select-none">
      {/* Header: Brand, Greeting & Status */}
      <div className="flex items-start justify-between gap-2 pt-2">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-14 h-14 rounded-3xl overflow-hidden shadow-lg border border-[#6202E1]/30 bg-[#0D1524] shrink-0">
            <img
              src="/app-logo.png"
              alt="btmu Logo"
              className="w-full h-full object-cover"
            />
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <span className="text-[11px] font-black tracking-widest uppercase text-[#F70E42] font-mono">
                Btmus by Taboubi Ahmed
              </span>
              <span className="px-1.5 py-0.5 rounded-full bg-[#6202E1]/15 text-[9px] font-bold text-[#F70E42]">
                v2.00
              </span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-black text-[#F0F4FA] tracking-tight mt-0.5 truncate font-display">
              {getGreeting()}
            </h1>
          </div>
        </div>

        {/* Online / Offline status badge */}
        <div
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold border ${
            isOnline
              ? 'bg-[#0D1524]/80 border-[#6202E1]/30 text-[#F0F4FA]'
              : 'bg-[#0D1524]/50 border-white/10 text-[#7E8F9E]'
          }`}
        >
          {isOnline ? (
            <>
              <span className="w-2 h-2 rounded-full bg-[#F70E42] animate-pulse" />
              <Wifi className="w-3.5 h-3.5 text-[#F70E42]" />
              <span className="font-mono text-[11px]">Online</span>
            </>
          ) : (
            <>
              <span className="w-2 h-2 rounded-full bg-[#7E8F9E]" />
              <WifiOff className="w-3.5 h-3.5" />
              <span className="font-mono text-[11px]">Offline</span>
            </>
          )}
        </div>
      </div>

      {/* Discovery / Search Callout */}
      <div
        onClick={() => {
          triggerHaptic();
          onGoToTab('search');
        }}
        className="p-3.5 rounded-2xl bg-[#0D1524]/80 backdrop-blur-xl border border-[#6202E1]/20 shadow-md flex items-center justify-between cursor-pointer hover:border-[#6202E1] transition active:scale-[0.99]"
      >
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white flex items-center justify-center font-bold shadow-md">
            <Search className="w-4 h-4" />
          </div>
          <div>
            <div className="text-xs font-black text-[#F0F4FA] tracking-tight">
              Unified Music Search & Discovery
            </div>
            <p className="text-[11px] text-[#7E8F9E]">
              YouTube, Spotify, Telegram & CC with instant download
            </p>
          </div>
        </div>
        <span className="text-xs font-bold text-[#F70E42]">&rarr;</span>
      </div>

      {/* SMART SYNCHRO ENGINE CARD */}
      <div className="p-4 rounded-3xl bg-[#0D1524]/85 backdrop-blur-2xl border border-[#F70E42]/30 shadow-md">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-9 h-9 rounded-xl bg-[#F70E42]/20 border border-[#F70E42]/40 text-[#F70E42] flex items-center justify-center font-bold shrink-0">
              <Wrench className="w-4 h-4" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-xs font-black text-[#F0F4FA] tracking-wide">
                  SMART SYNCHRO REPAIR
                </span>
                <span className="px-1.5 py-0.5 rounded-full bg-[#F70E42]/15 text-[9px] font-mono font-bold text-[#F70E42]">
                  v2.00
                </span>
              </div>
              <p className="text-[11px] text-[#7E8F9E] truncate mt-0.5">
                {synchroStatus || 'Enrich missing artwork, official tags & heal orphaned playlists'}
              </p>
            </div>
          </div>

          <button
            onClick={handleRunSmartSynchro}
            disabled={isSynchroRunning}
            className="px-3.5 py-2 rounded-xl bg-gradient-to-r from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white text-xs font-bold flex items-center gap-1.5 transition active:scale-95 shadow-sm disabled:opacity-60"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isSynchroRunning ? 'animate-spin' : ''}`} />
            <span>{isSynchroRunning ? 'Repairing' : 'Auto-Sync'}</span>
          </button>
        </div>
      </div>

      {/* Btt Smart Mix Quick Action & Status Banner */}
      <div
        onClick={() => {
          triggerHaptic();
          setIsSmartMixDrawerOpen(true);
        }}
        className="p-4 rounded-3xl bg-[#0D1524]/85 backdrop-blur-2xl border border-white/10 shadow-md cursor-pointer hover:border-[#6202E1] transition-all group active:scale-[0.99]"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white flex items-center justify-center font-bold shadow-md">
              <Sparkles className="w-4 h-4" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-black text-[#F0F4FA] tracking-wide">
                  SMART MIX
                </span>
                <span
                  className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                    smartMixConfig.enabled
                      ? 'bg-[#6202E1]/20 text-[#F70E42] border border-[#6202E1]/30'
                      : 'bg-white/10 text-[#7E8F9E]'
                  }`}
                >
                  {smartMixConfig.enabled
                    ? `${smartMixConfig.preset.toUpperCase()} (${smartMixConfig.duration}s)`
                    : 'OFF'}
                </span>
              </div>
              <p className="text-[11px] text-[#7E8F9E] mt-0.5">
                {smartMixConfig.enabled
                  ? 'Continuous harmonic mixing & silence trimming active'
                  : 'Tap to configure seamless transitions and crossfades'}
              </p>
            </div>
          </div>

          <div className="p-2 rounded-xl bg-white/5 text-[#F0F4FA] group-hover:bg-[#F70E42] group-hover:text-white transition">
            <Sliders className="w-4 h-4" />
          </div>
        </div>

        <div className="mt-3 pt-2.5 border-t border-white/10 flex items-center justify-between text-[10px] text-[#7E8F9E]">
          <div className="flex items-center gap-3">
            <span className="flex items-center gap-1 font-semibold text-[#F0F4FA]">
              <Activity className="w-3 h-3 text-[#F70E42]" />
              {Object.keys(trackAnalyses).length}/{tracks.length} Analyzed
            </span>
            {smartMixConfig.useHarmonicMixing && (
              <span className="text-[#F70E42] font-bold">Harmonic Match</span>
            )}
            {smartMixConfig.trimSilence && <span>Trim Silence</span>}
          </div>
          <span className="font-semibold text-[#F70E42] group-hover:underline">
            Configure &rarr;
          </span>
        </div>
      </div>

      {/* Library Metric Card */}
      <div className="p-4 rounded-3xl bg-[#0D1524]/85 backdrop-blur-2xl border border-white/10 shadow-md flex items-center justify-between gap-3">
        <div className="space-y-1 min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs font-bold text-[#F0F4FA]">Music Library</span>
            <span className="px-2 py-0.5 rounded-full bg-[#6202E1]/15 text-[#F70E42] text-[10px] font-bold font-mono">
              {tracks.length} Songs Stored
            </span>
          </div>
          <p className="text-[11px] text-[#7E8F9E] truncate font-mono">
            {formatFileSize(storageStats.trackBytes)} cached offline on this iPhone
          </p>
        </div>

        <div className="flex items-center gap-1.5 shrink-0">
          <button
            onClick={() => {
              triggerHaptic();
              setIsImportModalOpen(true);
            }}
            className="px-3.5 py-2 rounded-xl bg-gradient-to-r from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white text-xs font-bold flex items-center gap-1.5 transition active:scale-95 shadow-sm"
          >
            <Download className="w-3.5 h-3.5" />
            Import
          </button>
          <button
            onClick={() => {
              triggerHaptic();
              onGoToTab('sync');
            }}
            className="px-3 py-2 rounded-xl bg-white/10 text-[#F0F4FA] text-xs font-semibold flex items-center gap-1 transition active:scale-95 hover:bg-white/15"
          >
            <RefreshCw className="w-3 h-3" />
            Sync
          </button>
        </div>
      </div>

      {/* SECTION: RECENTLY PLAYED (Horizontal Carousel) */}
      {recentlyPlayed.length > 0 && (
        <section className="space-y-4">
          <div className="flex items-end justify-between">
            <div>
              <span className="text-[10px] font-mono uppercase tracking-widest text-[#F70E42] font-bold">
                Jump Back In
              </span>
              <h3 className="text-xl font-extrabold text-[#F0F4FA] tracking-tight">
                Recently Played
              </h3>
            </div>
            <span className="text-xs text-[#7E8F9E] font-mono">
              {recentlyPlayed.length} songs
            </span>
          </div>

          <div className="flex gap-4 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-none snap-x snap-mandatory">
            {recentlyPlayed.map((track) => (
              <SongHorizontalCard
                key={track.id}
                track={track}
                analysis={trackAnalyses[track.id]}
                isCurrent={playerState.currentTrack?.id === track.id}
                isPlaying={playerState.isPlaying && playerState.currentTrack?.id === track.id}
                onPlay={() => {
                  triggerHaptic();
                  playTrack(track, recentlyPlayed);
                }}
                onToggleFavorite={() => {
                  triggerHaptic();
                  toggleFavorite(track.id);
                }}
              />
            ))}
          </div>
        </section>
      )}

      {/* SECTION: FAVORITES (Horizontal Carousel) */}
      {favoriteTracks.length > 0 && (
        <section className="space-y-4">
          <div className="flex items-end justify-between">
            <div>
              <span className="text-[10px] font-mono uppercase tracking-widest text-[#F70E42] font-bold">
                Loved Tracks
              </span>
              <h3 className="text-xl font-extrabold text-[#F0F4FA] tracking-tight flex items-center gap-1.5">
                <Heart className="w-4 h-4 fill-current text-rose-500" /> Favorites
              </h3>
            </div>
            <button
              onClick={() => {
                triggerHaptic();
                onGoToTab('library');
              }}
              className="text-xs text-[#F70E42] hover:underline font-semibold"
            >
              See all ({tracks.filter((t) => t.isFavorite).length})
            </button>
          </div>

          <div className="flex gap-4 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-none snap-x snap-mandatory">
            {favoriteTracks.map((track) => (
              <SongHorizontalCard
                key={track.id}
                track={track}
                analysis={trackAnalyses[track.id]}
                isCurrent={playerState.currentTrack?.id === track.id}
                isPlaying={playerState.isPlaying && playerState.currentTrack?.id === track.id}
                onPlay={() => {
                  triggerHaptic();
                  playTrack(track, favoriteTracks);
                }}
                onToggleFavorite={() => {
                  triggerHaptic();
                  toggleFavorite(track.id);
                }}
              />
            ))}
          </div>
        </section>
      )}

      {/* SECTION: RECENTLY DOWNLOADED (Horizontal Carousel) */}
      <section className="space-y-4">
        <div className="flex items-end justify-between">
          <div>
            <span className="text-[10px] font-mono uppercase tracking-widest text-[#F70E42] font-bold">
              Offline Vault
            </span>
            <h3 className="text-xl font-extrabold text-[#F0F4FA] tracking-tight">
              Recently Downloaded
            </h3>
          </div>
          <button
            onClick={() => {
              triggerHaptic();
              onGoToTab('library');
            }}
            className="text-xs text-[#F70E42] hover:underline font-semibold"
          >
            All songs ({tracks.length}) &rarr;
          </button>
        </div>

        <div className="flex gap-4 overflow-x-auto pb-2 -mx-4 px-4 scrollbar-none snap-x snap-mandatory">
          {recentlyAdded.map((track) => (
            <SongHorizontalCard
              key={track.id}
              track={track}
              analysis={trackAnalyses[track.id]}
              isCurrent={playerState.currentTrack?.id === track.id}
              isPlaying={playerState.isPlaying && playerState.currentTrack?.id === track.id}
              onPlay={() => {
                triggerHaptic();
                playTrack(track, recentlyAdded);
              }}
              onToggleFavorite={() => {
                triggerHaptic();
                toggleFavorite(track.id);
              }}
            />
          ))}
        </div>
      </section>

      {/* Drawers & Modals */}
      <SmartMixDrawer
        isOpen={isSmartMixDrawerOpen}
        onClose={() => setIsSmartMixDrawerOpen(false)}
      />

      <PlaylistImportModal
        isOpen={isImportModalOpen}
        onClose={() => setIsImportModalOpen(false)}
        onPlaylistCreated={(id) => onOpenPlaylist(id)}
      />
    </div>
  );
};

// Apple-Inspired Horizontal Song Card
export const SongHorizontalCard: React.FC<{
  track: Track;
  analysis?: any;
  isCurrent?: boolean;
  isPlaying?: boolean;
  onPlay: () => void;
  onToggleFavorite: () => void;
}> = ({ track, analysis, isCurrent, isPlaying, onPlay, onToggleFavorite }) => {
  return (
    <div
      onClick={onPlay}
      className={`w-40 sm:w-44 shrink-0 p-3 rounded-3xl bg-[#0D1524]/85 backdrop-blur-xl border transition-all cursor-pointer group snap-start active:scale-[0.97] select-none ${
        isCurrent
          ? 'border-[#6202E1] shadow-[0_0_18px_rgba(247,14,66,0.35)]'
          : 'border-white/10 hover:border-[#6202E1]/40'
      }`}
    >
      <div className="relative w-full aspect-square rounded-2xl overflow-hidden bg-[#05070B] shadow-xl border border-white/10 mb-2">
        {track.artworkUrl ? (
          <img
            src={track.artworkUrl}
            alt={track.title}
            className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-300"
            loading="lazy"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-[#7E8F9E]">
            <Music className="w-8 h-8" />
          </div>
        )}

        <button
          onClick={(e) => {
            e.stopPropagation();
            onToggleFavorite();
          }}
          className={`absolute top-1.5 right-1.5 p-1.5 rounded-full backdrop-blur-md transition ${
            track.isFavorite
              ? 'bg-rose-500/25 text-rose-500'
              : 'bg-black/40 text-white/70 hover:text-white opacity-0 group-hover:opacity-100'
          }`}
          aria-label="Toggle favorite"
        >
          <Heart className={`w-3 h-3 ${track.isFavorite ? 'fill-current' : ''}`} />
        </button>

        <div
          className={`absolute inset-0 bg-black/40 flex items-center justify-center transition-opacity ${
            isPlaying || isCurrent ? 'opacity-100' : 'opacity-0 group-hover:opacity-100'
          }`}
        >
          <div className="w-9 h-9 rounded-full bg-gradient-to-tr from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white flex items-center justify-center shadow-md scale-95 group-hover:scale-105 transition-transform">
            {isPlaying ? (
              <span className="flex items-center gap-0.5">
                <span className="w-1 h-3 bg-white rounded-full animate-bounce" />
                <span className="w-1 h-4 bg-white rounded-full animate-bounce [animation-delay:0.15s]" />
                <span className="w-1 h-2 bg-white rounded-full animate-bounce [animation-delay:0.3s]" />
              </span>
            ) : (
              <Play className="w-4 h-4 fill-current ml-0.5" />
            )}
          </div>
        </div>
      </div>

      <h4 className="text-xs font-bold text-[#F0F4FA] truncate leading-tight">
        {track.title}
      </h4>
      <p className="text-[11px] text-[#7E8F9E] truncate mt-0.5 font-medium">
        {track.artist || 'Unknown'}
      </p>

      <div className="flex items-center justify-between text-[10px] font-mono text-[#7E8F9E] mt-1 pt-1 border-t border-white/5">
        <span>{formatDuration(track.duration)}</span>
        {analysis ? (
          <span className="text-[#F70E42] font-bold">
            {analysis.bpm} BPM
          </span>
        ) : track.fileSize ? (
          <span>{formatFileSize(track.fileSize)}</span>
        ) : null}
      </div>
    </div>
  );
};

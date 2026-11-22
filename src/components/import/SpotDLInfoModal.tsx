import React from 'react';
import { X, ShieldAlert, Send, FolderPlus, Library } from 'lucide-react';

/**
 * QUARANTINED — spotDL bridge UI (Phase 0 item 5).
 *
 * The previous version of this modal let the user enter a self-hosted spotDL
 * bridge URL, probe it, and save it so the X2 pipeline could download
 * commercial tracks via a Spotify-to-YouTube downloader. That flow is
 * unavailable while its legality is audited: downloading audio from YouTube
 * violates YouTube's Terms of Service, and ripping commercial recordings
 * violates Spotify's Terms of Service.
 *
 * This modal now renders only an honest "unavailable" state: no URL input, no
 * connection test, no hosting instructions, and no download action.
 *
 * Props `bridgeUrl` / `onSaveBridgeUrl` are retained solely so the existing
 * callers (SettingsScreen, PlaylistImportModal) keep compiling unchanged.
 * `onSaveBridgeUrl` is never invoked while the bridge is quarantined.
 */

interface SpotDLInfoModalProps {
  isOpen: boolean;
  onClose: () => void;
  bridgeUrl: string;
  onSaveBridgeUrl: (url: string) => void;
}

export const SpotDLInfoModal: React.FC<SpotDLInfoModalProps> = ({
  isOpen,
  onClose,
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-3 sm:p-4 bg-black/80 backdrop-blur-2xl animate-in fade-in duration-200">
      <div className="w-full max-w-lg rounded-3xl bg-white/95 dark:bg-[#080d10]/95 border border-zinc-200 dark:border-white/10 shadow-[0_20px_60px_0_rgba(0,0,0,0.6)] flex flex-col max-h-[90vh] overflow-hidden">
        {/* Header */}
        <div className="p-4 border-b border-zinc-200 dark:border-white/10 flex items-center justify-between shrink-0 bg-white/50 dark:bg-black/30 backdrop-blur-md">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-2xl bg-amber-500/20 text-amber-500 flex items-center justify-center">
              <ShieldAlert className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-1.5">
                <span className="text-[10px] font-black tracking-widest text-amber-500 uppercase font-mono">
                  Unavailable
                </span>
                <span className="text-[10px] text-zinc-400">• Under legal review</span>
              </div>
              <h3 className="text-base font-extrabold text-black dark:text-white leading-none mt-0.5">
                spotDL Bridge — Unavailable
              </h3>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 text-zinc-400 hover:text-black dark:hover:text-white transition active:scale-90"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Body */}
        <div className="flex-1 overflow-y-auto p-5 space-y-4 text-xs">
          <div className="p-3.5 rounded-2xl bg-amber-500/10 border border-amber-500/20 text-amber-900 dark:text-amber-200 space-y-1.5">
            <div className="flex items-center gap-1.5 font-bold text-amber-700 dark:text-amber-300">
              <ShieldAlert className="w-4 h-4 shrink-0" />
              <span>Why this is unavailable</span>
            </div>
            <p className="leading-relaxed text-[11px]">
              spotDL resolves a Spotify track and downloads the matching audio from YouTube.
              Downloading audio from YouTube violates YouTube&apos;s Terms of Service, and
              ripping commercial recordings violates Spotify&apos;s Terms of Service. The
              spotDL bridge is therefore disabled while its legality is audited. Do not
              re-enable it without that audit.
            </p>
          </div>

          <div className="space-y-2.5">
            <div className="font-bold text-black dark:text-white">What still works</div>

            <div className="p-3 rounded-2xl bg-zinc-50 dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800 space-y-1">
              <div className="font-bold text-black dark:text-white flex items-center gap-1.5">
                <Send className="w-3.5 h-3.5 text-[#02ABB0]" />
                <span>Telegram Audio Hub</span>
              </div>
              <p className="text-[11px] text-zinc-500 pl-5.5">
                Sync audio files you already own from your Telegram bot or channel — the
                recommended path for commercial tracks.
              </p>
            </div>

            <div className="p-3 rounded-2xl bg-zinc-50 dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800 space-y-1">
              <div className="font-bold text-black dark:text-white flex items-center gap-1.5">
                <FolderPlus className="w-3.5 h-3.5 text-[#02ABB0]" />
                <span>Local file import</span>
              </div>
              <p className="text-[11px] text-zinc-500 pl-5.5">
                Import MP3, M4A, FLAC, WAV, or OGG files from iPhone Files or iCloud Drive.
              </p>
            </div>

            <div className="p-3 rounded-2xl bg-zinc-50 dark:bg-zinc-900/80 border border-zinc-200 dark:border-zinc-800 space-y-1">
              <div className="font-bold text-black dark:text-white flex items-center gap-1.5">
                <Library className="w-3.5 h-3.5 text-[#02ABB0]" />
                <span>Open catalogs (X2)</span>
              </div>
              <p className="text-[11px] text-zinc-500 pl-5.5">
                Jamendo, Internet Archive, and Free Music Archive provide Creative Commons
                and public-domain recordings with authorized downloads.
              </p>
            </div>
          </div>
        </div>

        {/* Footer */}
        <div className="p-4 border-t border-zinc-200 dark:border-zinc-800 text-[10px] text-zinc-500 flex items-center justify-between shrink-0 bg-zinc-50 dark:bg-black/20">
          <span>Quarantined pending legal audit — Phase 0 item 5</span>
          <button
            onClick={onClose}
            className="px-4 py-2 rounded-xl bg-[#02ABB0] text-black font-extrabold text-xs active:scale-95 transition"
          >
            Done
          </button>
        </div>
      </div>
    </div>
  );
};

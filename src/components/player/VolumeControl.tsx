import React, { useRef, useState, useCallback } from 'react';
import { Volume2, Volume1, VolumeX } from 'lucide-react';
import { useMusic } from '../../context/MusicContext';

interface VolumeControlProps {
  className?: string;
  showPresets?: boolean;
}

export const VolumeControl: React.FC<VolumeControlProps> = ({
  className = '',
  showPresets = true,
}) => {
  const { playerState, setVolume } = useMusic();

  const { volume, isMuted } = playerState;

  const [isDragging, setIsDragging] = useState(false);
  const [dragPercent, setDragPercent] = useState<number | null>(null);
  const trackRef = useRef<HTMLDivElement | null>(null);

  // Volume-only (0-100%). Phase 3 (W-1): the 300% Web Audio booster was
  // removed - it lives in the native app only. No percentage above 100%.
  const currentPercent = isMuted ? 0 : volume * 100;

  const displayPercent = isDragging && dragPercent !== null ? dragPercent : currentPercent;
  const maxPercent = 100;
  const progressRatio = Math.max(0, Math.min(1, displayPercent / maxPercent));

  // Determine current volume icon
  const renderVolumeIcon = () => {
    if (isMuted || displayPercent === 0) {
      return <VolumeX className="w-4 h-4 text-zinc-400 dark:text-zinc-500" />;
    }
    if (displayPercent < 40) {
      return <Volume1 className="w-4 h-4 text-zinc-500 dark:text-zinc-400" />;
    }
    return <Volume2 className="w-4 h-4 text-black dark:text-white" />;
  };

  // Convert clientX to percentage
  const calculatePercentFromX = useCallback(
    (clientX: number) => {
      if (!trackRef.current) return 0;
      const rect = trackRef.current.getBoundingClientRect();
      const clickX = clientX - rect.left;
      const fraction = Math.max(0, Math.min(1, clickX / rect.width));
      return Math.round(fraction * maxPercent);
    },
    [maxPercent]
  );

  // Apply volume based on percentage (0-100% only).
  const applyPercent = useCallback(
    (pct: number) => {
      if (pct <= 0) {
        setVolume(0);
        return;
      }
      setVolume(Math.min(pct, 100) / 100);
    },
    [setVolume]
  );

  // Pointer handlers for precise, smooth dragging
  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    e.preventDefault();
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
    setIsDragging(true);
    const newPct = calculatePercentFromX(e.clientX);
    setDragPercent(newPct);
    applyPercent(newPct);

    const handlePointerMove = (moveEv: PointerEvent) => {
      const movedPct = calculatePercentFromX(moveEv.clientX);
      setDragPercent(movedPct);
      applyPercent(movedPct);
    };

    const handlePointerUp = (upEv: PointerEvent) => {
      const finalPct = calculatePercentFromX(upEv.clientX);
      setIsDragging(false);
      setDragPercent(null);
      applyPercent(finalPct);
      window.removeEventListener('pointermove', handlePointerMove);
      window.removeEventListener('pointerup', handlePointerUp);
      window.removeEventListener('pointercancel', handlePointerUp);
    };

    window.addEventListener('pointermove', handlePointerMove);
    window.addEventListener('pointerup', handlePointerUp);
    window.addEventListener('pointercancel', handlePointerUp);
  };

  return (
    <div className={`space-y-2 select-none ${className}`}>
      <div className="flex items-center justify-between gap-3">
        {/* Mute / Unmute Button */}
        <button
          type="button"
          onClick={() => {
            if (isMuted || volume === 0) {
              setVolume(0.8);
            } else {
              setVolume(0);
            }
          }}
          className="p-2 -ml-1 text-zinc-500 hover:text-black dark:text-zinc-400 dark:hover:text-white rounded-full hover:bg-zinc-100 dark:hover:bg-zinc-800 transition active:scale-95"
          aria-label={isMuted ? 'Unmute' : 'Mute'}
        >
          {renderVolumeIcon()}
        </button>

        {/* Custom Touch-Friendly Volume Slider Track & Cursor */}
        <div
          ref={trackRef}
          onPointerDown={handlePointerDown}
          className="relative flex-1 h-9 flex items-center cursor-pointer group touch-none"
          title="Drag to adjust volume cursor"
        >
          {/* Background Track */}
          <div className="w-full h-2 bg-zinc-200 dark:bg-zinc-800 rounded-full overflow-hidden relative border border-zinc-300 dark:border-zinc-700/60">
            {/* Filled Volume Monochrome Bar */}
            <div
              className="h-full bg-black dark:bg-white transition-all duration-75"
              style={{ width: `${progressRatio * 100}%` }}
            />
          </div>

          {/* Draggable Thumb Cursor */}
          <div
            className={`absolute top-1/2 -translate-y-1/2 -ml-2.5 rounded-full shadow-md transition-transform ${
              isDragging
                ? 'scale-125 w-5 h-5 bg-black dark:bg-white ring-4 ring-black/20 dark:ring-white/20'
                : 'w-4 h-4 bg-black dark:bg-white group-hover:scale-110'
            }`}
            style={{ left: `${progressRatio * 100}%` }}
          />

          {/* Floating Tooltip Indicator while Dragging */}
          {isDragging && (
            <div
              className="absolute -top-7 -translate-x-1/2 px-2 py-0.5 rounded-md text-[10px] font-mono font-bold bg-black text-white dark:bg-white dark:text-black shadow-lg pointer-events-none whitespace-nowrap z-30"
              style={{ left: `${progressRatio * 100}%` }}
            >
              {displayPercent}%
            </div>
          )}
        </div>

        {/* Volume Percentage */}
        <div className="shrink-0 text-right min-w-[50px]">
          <span className="text-xs font-mono font-bold text-black dark:text-white">
            {Math.round(displayPercent)}%
          </span>
        </div>

      </div>

      {/* Volume Presets Row */}
      {showPresets && (
        <div className="flex items-center justify-between gap-1.5 pt-0.5">
          <span className="text-[10px] uppercase font-bold tracking-wider text-zinc-500 dark:text-zinc-400">
            Presets:
          </span>

          <div className="flex items-center gap-1">
            <button
              type="button"
              onClick={() => setVolume(0.25)}
              className={`px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-bold transition ${
                Math.abs(volume - 0.25) < 0.05
                  ? 'bg-black text-white dark:bg-white dark:text-black'
                  : 'bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:text-black dark:hover:text-white'
              }`}
            >
              25%
            </button>
            <button
              type="button"
              onClick={() => setVolume(0.5)}
              className={`px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-bold transition ${
                Math.abs(volume - 0.5) < 0.05
                  ? 'bg-black text-white dark:bg-white dark:text-black'
                  : 'bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:text-black dark:hover:text-white'
              }`}
            >
              50%
            </button>
            <button
              type="button"
              onClick={() => setVolume(0.75)}
              className={`px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-bold transition ${
                Math.abs(volume - 0.75) < 0.05
                  ? 'bg-black text-white dark:bg-white dark:text-black'
                  : 'bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:text-black dark:hover:text-white'
              }`}
            >
              75%
            </button>
            <button
              type="button"
              onClick={() => setVolume(1.0)}
              className={`px-2.5 py-0.5 rounded-lg text-[10px] font-mono font-bold transition ${
                volume >= 0.98
                  ? 'bg-black text-white dark:bg-white dark:text-black'
                  : 'bg-zinc-100 dark:bg-zinc-800 text-zinc-600 dark:text-zinc-400 hover:text-black dark:hover:text-white'
              }`}
            >
              100%
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

import React, { useState, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Volume2, Sliders, X, Check } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { useMusic } from '../../context/MusicContext';
import { triggerHaptic } from '../../services/nativeAudioBridge';

interface CircularVolumeDialProps {
  className?: string;
}

export const CircularVolumeDial: React.FC<CircularVolumeDialProps> = ({ className = '' }) => {
  const { playerState, setVolume } = useMusic();
  const { volume, isMuted } = playerState;

  const [isExpanded, setIsExpanded] = useState(false);
  const [isDraggingSlider, setIsDraggingSlider] = useState(false);
  const cardRef = useRef<HTMLDivElement | null>(null);

  const handleBackdropClick = (e: React.MouseEvent | React.TouchEvent) => {
    if (isDraggingSlider) return;
    if (cardRef.current && !cardRef.current.contains(e.target as Node)) {
      setIsExpanded(false);
    }
  };

  const radius = 28;
  const circumference = Math.PI * radius;

  // Upper arc (Volume): 0 to 1
  const effectiveVol = isMuted ? 0 : volume;
  const volDashoffset = circumference * (1 - effectiveVol);

  // W-1 (Phase 3): the 300% booster arc/presets were removed. The dial is
  // volume only (0-100% element volume). 300% is native-only
  // (Flutter/SwiftUI with limiter); the Capacitor path has no safe 300%
  // because the Web Audio routing breaks iOS background playback.

  return (
    <div className={`relative flex items-center justify-center ${className}`}>
      {/* COLLAPSED STATE: Liquid Glass Circular Audio Dial */}
      <motion.button
        type="button"
        onClick={() => {
          triggerHaptic();
          setIsExpanded(true);
        }}
        whileHover={{ scale: 1.06 }}
        whileTap={{ scale: 0.92 }}
        transition={{ type: 'spring', stiffness: 420, damping: 28 }}
        className="relative w-18 h-18 rounded-full p-1 bg-[#0D1626]/90 backdrop-blur-3xl border border-[#6202E1]/30 shadow-[0_8px_32px_rgba(0,0,0,0.7)] flex items-center justify-center cursor-pointer select-none group"
        title="Tap to adjust Volume"
        aria-label="Audio dial - tap to expand"
      >
        {/* Specular glass highlight */}
        <div className="absolute inset-1 rounded-full bg-gradient-to-tr from-[#6202E1]/20 via-transparent to-white/20 pointer-events-none" />

        {/* Semicircle SVG Arcs */}
        <svg className="w-16 h-16 -rotate-90 pointer-events-none" viewBox="0 0 72 72">
          {/* Upper Track (Volume Background) */}
          <path
            d="M 36,8 A 28,28 0 0,1 36,64"
            fill="none"
            stroke="currentColor"
            className="text-white/10"
            strokeWidth="4"
            strokeLinecap="round"
          />
          {/* Upper Active (Volume Value - Pink) */}
          <path
            d="M 36,8 A 28,28 0 0,1 36,64"
            fill="none"
            stroke="#F70E42"
            strokeWidth="4"
            strokeDasharray={circumference}
            strokeDashoffset={volDashoffset}
            strokeLinecap="round"
            className="transition-all duration-200 drop-shadow-[0_0_6px_rgba(247,14,66,0.5)]"
          />

        </svg>

        {/* Center Glass Core */}
        <div className="absolute inset-3.5 rounded-full bg-[#05070B]/95 border border-[#6202E1]/20 shadow-inner flex flex-col items-center justify-center text-center">
          <div className="flex flex-col items-center leading-none">
            <span className="text-[10.5px] font-mono font-black text-[#F0F4FA]">
              {Math.round(effectiveVol * 100)}%
            </span>
            <span className="text-[7.5px] font-mono font-bold text-[#7E8F9E] mt-0.5">
              VOL
            </span>
          </div>
        </div>
      </motion.button>

      {/* EXPANDED INTERACTIVE MODAL */}
      {typeof document !== 'undefined' &&
        createPortal(
          <AnimatePresence>
            {isExpanded && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                onClick={handleBackdropClick}
                className="fixed inset-0 z-[9999] flex flex-col justify-end sm:justify-center items-center bg-black/75 backdrop-blur-md p-3 sm:p-6 pb-[max(env(safe-area-inset-bottom,0px),1rem)] select-none"
              >
                <motion.div
                  ref={cardRef}
                  initial={{ opacity: 0, y: 50, scale: 0.94 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: 40, scale: 0.94 }}
                  transition={{ type: 'spring', stiffness: 400, damping: 30 }}
                  onClick={(e) => e.stopPropagation()}
                  className="w-full max-w-sm rounded-[2.2rem] bg-[#0A1322]/95 backdrop-blur-3xl border border-[#6202E1]/30 shadow-[0_24px_70px_rgba(0,0,0,0.85)] p-4 sm:p-5 space-y-4 max-h-[85vh] overflow-y-auto"
                >
                  {/* Header */}
                  <div className="flex items-center justify-between pb-2 border-b border-white/10">
                    <div className="flex items-center gap-2.5">
                      <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white flex items-center justify-center font-bold shadow-md">
                        <Sliders className="w-4 h-4" />
                      </div>
                      <div>
                        <div className="text-xs font-black tracking-wide uppercase text-[#F0F4FA] font-mono">
                          Audio Dial
                        </div>
                        <p className="text-[10px] text-[#7E8F9E] font-medium">
                          Volume up to 100% — the 300% booster lives in the native app only
                        </p>
                      </div>
                    </div>

                    <button
                      type="button"
                      onClick={() => {
                        triggerHaptic();
                        setIsExpanded(false);
                      }}
                      className="p-1.5 rounded-full bg-white/10 hover:bg-white/15 text-[#F0F4FA] transition active:scale-90"
                      aria-label="Close menu"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>

                  {/* MASTER VOLUME */}
                  <div className="p-3.5 rounded-2xl bg-[#0D1524]/80 border border-white/10 space-y-2">
                    <div className="flex justify-between items-center text-xs font-bold text-[#F0F4FA]">
                      <span className="flex items-center gap-1.5">
                        <Volume2 className="w-4 h-4 text-[#F70E42]" />
                        <span>Master Volume</span>
                      </span>
                      <span className="font-mono text-xs font-black text-[#F70E42]">
                        {Math.round(volume * 100)}%
                      </span>
                    </div>

                    <div className="relative py-1 flex items-center">
                      <input
                        type="range"
                        min={0}
                        max={100}
                        value={Math.round(volume * 100)}
                        onMouseDown={() => setIsDraggingSlider(true)}
                        onTouchStart={() => setIsDraggingSlider(true)}
                        onMouseUp={() => setIsDraggingSlider(false)}
                        onTouchEnd={() => setIsDraggingSlider(false)}
                        onChange={(e) => setVolume(Number(e.target.value) / 100)}
                        className="w-full h-3 rounded-full appearance-none cursor-pointer bg-white/15 accent-[#F70E42]"
                      />
                    </div>
                  </div>

                  {/* W-1 (Phase 3): the 300% booster stage was removed. 300% is
                      native-only (Flutter/SwiftUI with limiter); the Capacitor
                      path has no safe 300% because the Web Audio routing
                      breaks iOS background playback (commit 7627d41). Volume
                      here is the plain audio element, max 100%. */}
                  <div className="p-3.5 rounded-2xl bg-[#0D1524]/80 border border-white/10">
                    <p className="text-[11px] text-[#7E8F9E] leading-relaxed">
                      The 300% volume booster lives in the native app only. In this
                      web player, volume tops out at 100% to keep iOS background
                      playback and lock-screen control working.
                    </p>
                  </div>

                  {/* Done Button */}
                  <button
                    type="button"
                    onClick={() => {
                      triggerHaptic();
                      setIsExpanded(false);
                    }}
                    className="w-full py-2.5 rounded-2xl bg-gradient-to-r from-[#6202E1] via-[#C4009B] to-[#F70E42] text-white font-bold text-xs shadow-md transition active:scale-95 flex items-center justify-center gap-1.5"
                  >
                    <Check className="w-4 h-4" />
                    <span>Done</span>
                  </button>
                </motion.div>
              </motion.div>
            )}
          </AnimatePresence>,
          document.body
        )}
    </div>
  );
};

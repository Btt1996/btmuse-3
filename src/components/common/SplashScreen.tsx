import React, { useState, useEffect } from 'react';

interface SplashScreenProps {
  onComplete: () => void;
}

export const SplashScreen: React.FC<SplashScreenProps> = ({ onComplete }) => {
  const [isAnimatingIn, setIsAnimatingIn] = useState(false);
  const [isExiting, setIsExiting] = useState(false);

  useEffect(() => {
    // Trigger entrance animation immediately on mount
    const enterTimer = requestAnimationFrame(() => {
      setIsAnimatingIn(true);
    });

    // Start graceful fade-out at 850ms (never more than 1.4s total)
    const exitTimer = setTimeout(() => {
      setIsExiting(true);
    }, 850);

    // Completely dismiss and unmount at 1150ms
    const completeTimer = setTimeout(() => {
      onComplete();
    }, 1150);

    return () => {
      cancelAnimationFrame(enterTimer);
      clearTimeout(exitTimer);
      clearTimeout(completeTimer);
    };
  }, [onComplete]);

  return (
    <div
      className={`fixed inset-0 z-50 flex flex-col items-center justify-center bg-[#05070B] select-none transition-opacity duration-350 ease-[cubic-bezier(0.16,1,0.3,1)] ${
        isExiting ? 'opacity-0 pointer-events-none' : 'opacity-100'
      }`}
      aria-label="btmu Splash"
    >
      {/* Soft atmospheric ambient glow */}
      <div className="absolute w-72 h-72 rounded-full bg-radial from-[#6202E1]/20 via-[#C4009B]/10 to-transparent blur-3xl pointer-events-none" />

      {/* Main Logo Emblem */}
      <div
        className={`relative z-10 flex flex-col items-center gap-4 transition-all duration-500 ease-[cubic-bezier(0.16,1,0.3,1)] ${
          isAnimatingIn
            ? 'scale-100 opacity-100 translate-y-0'
            : 'scale-[0.88] opacity-0 translate-y-2'
        } ${isExiting ? 'scale-[1.04]' : ''}`}
      >
        <div className="w-28 h-28 rounded-3xl overflow-hidden shadow-[0_20px_50px_rgba(0,0,0,0.8)] border border-[#6202E1]/30 bg-[#05070B] p-0.5">
          <img
            src="/app-logo.png"
            alt="Btmus by Taboubi Ahmed"
            className="w-full h-full object-cover rounded-[1.35rem]"
          />
        </div>

        {/* Wordmark in Sora display font */}
        <div className="flex flex-col items-center">
          <h1 className="font-display text-2xl font-extrabold tracking-tight bg-gradient-to-r from-[#6202E1] via-[#C4009B] to-[#F70E42] bg-clip-text text-transparent">
            Btmus
          </h1>
          <span className="text-xs font-medium tracking-widest text-[#7E8F9E] uppercase font-sans mt-0.5">
            by Taboubi Ahmed
          </span>
        </div>
      </div>

      {/* Bottom discreet version indicator */}
      <div className="absolute bottom-8 text-[11px] font-mono tracking-wider text-[#7E8F9E]/60 uppercase">
        v3.0.5
      </div>
    </div>
  );
};

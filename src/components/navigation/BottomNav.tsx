import React from 'react';
import { Home, Library, ListMusic, Download } from 'lucide-react';
import { motion } from 'motion/react';
import { triggerHaptic } from '../../services/nativeAudioBridge';

export type TabType = 'home' | 'library' | 'playlists' | 'import';

interface BottomNavProps {
  currentTab: TabType;
  onSelectTab: (tab: TabType) => void;
}

export const BottomNav: React.FC<BottomNavProps> = ({ currentTab, onSelectTab }) => {
  const tabs: { id: TabType; label: string; icon: React.FC<{ className?: string }> }[] = [
    { id: 'home', label: 'Home', icon: Home },
    { id: 'library', label: 'Library', icon: Library },
    { id: 'playlists', label: 'Playlists', icon: ListMusic },
    { id: 'import', label: 'Import', icon: Download },
  ];

  const handleTabPress = (tabId: TabType) => {
    triggerHaptic();
    onSelectTab(tabId);
  };

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-40 px-3.5 pb-[max(env(safe-area-inset-bottom,0px),0.75rem)] pt-1 select-none pointer-events-none">
      <div className="max-w-md mx-auto pointer-events-auto">
        {/* iOS Liquid Glass Floating Pill Navigation Bar */}
        <div className="relative rounded-[2.2rem] bg-[#0A1322]/85 backdrop-blur-3xl border border-[#6202E1]/20 shadow-[0_16px_48px_rgba(0,0,0,0.75)] p-1.5 transition-all duration-300">
          {/* Specular Liquid Edge Highlight */}
          <div className="absolute inset-x-6 top-0 h-[1px] bg-gradient-to-r from-transparent via-[#C4009B]/60 to-transparent rounded-full pointer-events-none" />

          <div className="flex items-center justify-around h-13 relative">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              const isActive = currentTab === tab.id;

              return (
                <button
                  key={tab.id}
                  onClick={() => handleTabPress(tab.id)}
                  className="relative flex-1 flex flex-col items-center justify-center py-1 transition-transform duration-200 active:scale-90 focus:outline-none"
                  aria-label={tab.label}
                >
                  {/* Fluid Liquid Glass Capsule Indicator */}
                  {isActive && (
                    <motion.div
                      layoutId="liquidGlassTabIndicator"
                      transition={{
                        type: 'spring',
                        stiffness: 450,
                        damping: 34,
                        mass: 0.8,
                      }}
                      className="absolute inset-0 mx-1 rounded-2xl bg-gradient-to-b from-[#F70E42]/25 to-[#6202E1]/15 border border-[#F70E42]/40 shadow-[0_0_18px_rgba(247,14,66,0.3)] pointer-events-none"
                    />
                  )}

                  <div className="relative z-10 flex flex-col items-center">
                    <Icon
                      className={`w-5 h-5 transition-all duration-200 ${
                        isActive
                          ? 'text-[#F70E42] scale-110 stroke-[2.4] drop-shadow-[0_0_8px_rgba(247,14,66,0.5)]'
                          : 'text-[#7E8F9E] stroke-[1.8] hover:text-[#F0F4FA]'
                      }`}
                    />
                    <span
                      className={`text-[9.5px] tracking-tight mt-0.5 font-sans transition-colors duration-200 ${
                        isActive
                          ? 'text-[#F70E42] font-bold'
                          : 'text-[#7E8F9E] font-medium'
                      }`}
                    >
                      {tab.label}
                    </span>
                  </div>
                </button>
              );
            })}
          </div>

          {/* Discreet Footer Signature: Btmus by Taboubi Ahmed */}
          <div className="pt-0.5 pb-0.5 text-center">
            <span className="text-[9px] tracking-widest uppercase font-mono text-[#7E8F9E]/80 font-semibold select-none">
              Btmus <span className="lowercase font-normal tracking-normal text-[#7E8F9E]/50">by Taboubi Ahmed</span>
            </span>
          </div>
        </div>
      </div>
    </nav>
  );
};

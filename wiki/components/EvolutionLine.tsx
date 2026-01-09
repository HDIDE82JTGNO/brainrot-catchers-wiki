"use client";

import React from 'react';
import Link from 'next/link';
import { Creature } from '@/types';
import { ColorTheme } from '@/lib/colorUtils';
import { getSpritePath } from '@/lib/spriteUtils';

interface EvolutionLineProps {
  evolutionChain: Creature[];
  currentCreatureName: string;
  theme: ColorTheme;
  isShiny: boolean;
}

export function EvolutionLine({ evolutionChain, currentCreatureName, theme, isShiny }: EvolutionLineProps) {
  if (evolutionChain.length <= 1) {
    return null;
  }

  return (
    <div className="bg-white p-6 rounded-3xl border-2 shadow-xl transition-all duration-300" style={{ borderColor: theme.light }}>
      <h3 className="text-xl font-bold mb-6 flex items-center gap-3 transition-colors duration-300" style={{ color: theme.dark }}>
        <span className="w-1.5 h-8 rounded-full transition-all duration-300" style={{ background: theme.gradient }}></span>
        Evolution Line
      </h3>
      
      <div className="flex flex-wrap items-center justify-center gap-4 md:gap-6">
        {evolutionChain.map((creature, index) => {
          const isCurrent = creature.Name === currentCreatureName;
          const spritePath = getSpritePath(creature.Name, isShiny);
          
          return (
            <React.Fragment key={creature.Id || creature.Name}>
              {/* Evolution Stage */}
              <Link
                href={`/creatures/${encodeURIComponent(creature.Name)}`}
                className={`group relative flex flex-col items-center transition-all duration-300 ${
                  isCurrent ? 'scale-110' : 'hover:scale-105'
                }`}
              >
                <div
                  className="w-20 h-20 md:w-24 md:h-24 bg-white rounded-full flex items-center justify-center shadow-lg border-2 relative overflow-hidden transition-all duration-300"
                  style={{
                    borderColor: isCurrent ? theme.primary : theme.light,
                    boxShadow: isCurrent 
                      ? `0 0 0 4px ${theme.primary}40, 0 0 0 8px white, 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)`
                      : '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)'
                  }}
                >
                  <img
                    src={spritePath}
                    alt={`${creature.Name} Sprite`}
                    className="w-full h-full object-contain p-2 drop-shadow-md"
                    style={{ imageRendering: 'pixelated' }}
                    onError={(e) => {
                      (e.target as HTMLImageElement).style.display = 'none';
                      const fallback = (e.target as HTMLImageElement).nextElementSibling as HTMLElement;
                      if (fallback) fallback.classList.remove('hidden');
                    }}
                  />
                  <div className="hidden text-2xl text-slate-300">?</div>
                </div>
                
                {/* Creature Name */}
                <span
                  className={`mt-2 text-xs md:text-sm font-semibold text-center transition-colors duration-300 ${
                    isCurrent ? 'font-bold' : ''
                  }`}
                  style={{ color: isCurrent ? theme.primary : theme.dark }}
                >
                  {creature.Name}
                </span>
                
                {/* Evolution Level Badge - Show the level at which the previous creature evolves into this one */}
                {index > 0 && evolutionChain[index - 1].EvolutionLevel && (
                  <span
                    className="mt-1 text-xs px-2 py-0.5 rounded-full bg-white border transition-all duration-300"
                    style={{
                      color: theme.primary,
                      borderColor: theme.primary
                    }}
                  >
                    Lv. {evolutionChain[index - 1].EvolutionLevel}
                  </span>
                )}
              </Link>
              
              {/* Arrow */}
              {index < evolutionChain.length - 1 && (
                <div className="flex items-center">
                  <svg
                    className="w-6 h-6 md:w-8 md:h-8 transition-colors duration-300"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    style={{ color: theme.primary }}
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M9 5l7 7-7 7"
                    />
                  </svg>
                </div>
              )}
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}


"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import statusData from '../../data/status.json';
import movesData from '../../data/moves.json';
import { Move } from '@/types';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';

const statusEffects = statusData as unknown as any[];
const moves = movesData as unknown as Move[];

const AnimatedDiv = animated.div as any;

// Find moves that cause each status
const statusMoveMap = new Map<string, Move[]>();
statusEffects.forEach(status => {
  const movesWithStatus = moves.filter(m => m.StatusEffect === status.Code);
  if (movesWithStatus.length > 0) {
    statusMoveMap.set(status.Code, movesWithStatus);
  }
});

export default function StatusEffectsPage() {
  const [search, setSearch] = useState('');

  const filteredStatus = useMemo(() => {
    if (!search) return statusEffects;
    const searchLower = search.toLowerCase();
    return statusEffects.filter(status =>
      status.Name.toLowerCase().includes(searchLower) ||
      status.Code.toLowerCase().includes(searchLower) ||
      status.Description.toLowerCase().includes(searchLower)
    );
  }, [search]);

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(filteredStatus.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: { opacity: 1, transform: 'translateY(0px) scale(1)' },
    config: getSpringConfig('snappy'),
  });

  const getColorStyle = (color: any) => {
    if (!color) return {};
    if (typeof color === 'object' && color.r !== undefined) {
      return {
        backgroundColor: `rgb(${Math.round(color.r * 255)}, ${Math.round(color.g * 255)}, ${Math.round(color.b * 255)})`,
      };
    }
    return {};
  };

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Status Effects
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Complete guide to all status conditions and their effects in battle.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Search */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <svg className="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
              </svg>
            </div>
            <input
              type="text"
              placeholder="Search status effects..."
              className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        {/* Status Effects List */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">
            Status Effects ({filteredStatus.length})
          </h2>
          
          {filteredStatus.length === 0 ? (
            <EmptyState 
              message={`No status effects found matching "${search}"`}
              icon="💊"
            />
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {trail.map((style, idx) => {
                const status = filteredStatus[idx];
                if (!status) return null;
                
                const movesWithStatus = statusMoveMap.get(status.Code) || [];
                
                return (
                  <AnimatedDiv key={status.Id} style={style}>
                    <div className="border-2 border-slate-200 rounded-xl p-5 hover:border-blue-300 transition-all">
                      <div className="flex items-start gap-4 mb-3">
                        <div
                          className="w-16 h-16 rounded-lg flex items-center justify-center text-white font-bold text-xl shadow-md"
                          style={getColorStyle(status.Color)}
                        >
                          {status.Code}
                        </div>
                        <div className="flex-1">
                          <h3 className="text-2xl font-bold text-slate-900 mb-1">{status.Name}</h3>
                          <p className="text-slate-600 text-sm">{status.Description}</p>
                        </div>
                      </div>
                      
                      {movesWithStatus.length > 0 && (
                        <div className="mt-3 pt-3 border-t border-slate-200">
                          <div className="text-xs font-semibold text-slate-500 uppercase mb-2">
                            Moves ({movesWithStatus.length})
                          </div>
                          <div className="flex flex-wrap gap-1">
                            {movesWithStatus.slice(0, 5).map(move => (
                              <span
                                key={move.Id}
                                className="px-2 py-1 bg-slate-100 text-slate-700 rounded text-xs"
                              >
                                {move.Name}
                              </span>
                            ))}
                            {movesWithStatus.length > 5 && (
                              <span className="px-2 py-1 text-slate-500 text-xs">
                                +{movesWithStatus.length - 5} more
                              </span>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                  </AnimatedDiv>
                );
              })}
            </div>
          )}
        </div>
      </AnimatedDiv>
    </div>
  );
}


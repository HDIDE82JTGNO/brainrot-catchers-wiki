"use client";

import React, { useState, useMemo } from 'react';
import { TeamAnalyzer } from '@/components/TeamAnalyzer';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import { Creature, Move } from '@/types';
import { getSpringConfig } from '@/lib/springConfigs';
import { useSpring, animated } from '@react-spring/web';
import Image from 'next/image';
import Link from 'next/link';
import { getSpritePath } from '@/lib/spriteUtils';
import { TypeBadge } from '@/components/TypeBadge';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];

const AnimatedDiv = animated.div as any;
const MAX_TEAM_SIZE = 6;

export default function TeamBuilderPage() {
  const [team, setTeam] = useState<Creature[]>([]);
  const [shinyCreatures, setShinyCreatures] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');

  // Filter creatures for selection
  const filteredCreatures = useMemo(() => {
    if (!searchQuery.trim()) return creatures.slice(0, 50);
    
    const queryLower = searchQuery.toLowerCase();
    return creatures.filter(c =>
      c.Name.toLowerCase().includes(queryLower) ||
      c.Description?.toLowerCase().includes(queryLower) ||
      c.Types?.some(t => t.toLowerCase().includes(queryLower))
    ).slice(0, 50);
  }, [searchQuery]);

  const addToTeam = (creature: Creature) => {
    if (team.length >= MAX_TEAM_SIZE) return;
    if (team.some(c => c.Id === creature.Id)) return;
    setTeam([...team, creature]);
  };

  const removeFromTeam = (index: number) => {
    setTeam(team.filter((_, i) => i !== index));
  };

  const clearTeam = () => {
    setTeam([]);
  };

  const toggleShiny = (creatureName: string) => {
    setShinyCreatures(prev => {
      const next = new Set(prev);
      if (next.has(creatureName)) {
        next.delete(creatureName);
      } else {
        next.add(creatureName);
      }
      return next;
    });
  };

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Team Builder
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Build and analyze teams of up to {MAX_TEAM_SIZE} creatures. Check coverage, weaknesses, and synergies.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Team Slots */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4">
            <h2 className="text-xl font-bold text-slate-900">
              Team ({team.length}/{MAX_TEAM_SIZE})
            </h2>
            {team.length > 0 && (
              <button
                onClick={clearTeam}
                className="px-4 py-2 bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition-colors font-medium text-sm"
              >
                Clear Team
              </button>
            )}
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-4">
            {Array.from({ length: MAX_TEAM_SIZE }).map((_, idx) => {
              const creature = team[idx];
              return (
                <div
                  key={idx}
                  className={`aspect-square border-2 rounded-xl flex flex-col items-center justify-center p-2 ${
                    creature
                      ? 'border-blue-400 bg-blue-50'
                      : 'border-slate-200 bg-slate-50 border-dashed'
                  }`}
                >
                  {creature ? (
                    <>
                      <button
                        onClick={() => removeFromTeam(idx)}
                        className="absolute top-1 right-1 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center text-xs font-bold hover:bg-red-600 transition-colors"
                      >
                        ×
                      </button>
                      <Link href={`/creatures/${encodeURIComponent(creature.Name)}`}>
                        <div className="w-full h-full flex flex-col items-center justify-center cursor-pointer hover:opacity-80 transition-opacity">
                          <div className="w-16 h-16 mb-1 bg-white rounded-full flex items-center justify-center border-2 border-slate-200">
                            <Image
                              src={getSpritePath(creature.Name, shinyCreatures.has(creature.Name))}
                              alt={creature.Name}
                              width={64}
                              height={64}
                              className="w-full h-full object-contain p-1"
                              style={{ imageRendering: 'pixelated' }}
                            />
                          </div>
                          <div className="text-xs font-bold text-slate-900 text-center mb-1">{creature.Name}</div>
                          <div className="flex gap-0.5">
                            {creature.Types?.map(t => (
                              <TypeBadge key={t} type={t} className="scale-75" />
                            ))}
                          </div>
                        </div>
                      </Link>
                    </>
                  ) : (
                    <div className="text-slate-400 text-xs text-center">Empty Slot</div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Team Analysis */}
        {team.length > 0 && (
          <TeamAnalyzer
            team={team}
            moves={moves}
            shinyCreatures={shinyCreatures}
          />
        )}

        {/* Creature Selection */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">Add Creatures to Team</h2>
          
          {/* Search */}
          <div className="relative mb-4">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <svg className="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <input
              type="text"
              placeholder="Search creatures..."
              className="w-full pl-10 pr-4 py-2 border-2 border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          {/* Creature Grid */}
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3 max-h-96 overflow-y-auto">
            {filteredCreatures.map(creature => {
              const isInTeam = team.some(c => c.Id === creature.Id);
              
              return (
                <button
                  key={creature.Id}
                  onClick={() => addToTeam(creature)}
                  disabled={isInTeam || team.length >= MAX_TEAM_SIZE}
                  className={`p-3 border-2 rounded-lg transition-all text-left flex flex-col items-center ${
                    isInTeam
                      ? 'border-blue-500 bg-blue-50 opacity-50 cursor-not-allowed'
                      : team.length >= MAX_TEAM_SIZE
                      ? 'border-slate-200 opacity-50 cursor-not-allowed'
                      : 'border-slate-200 hover:border-blue-400 hover:shadow-md'
                  }`}
                >
                  <div className="w-12 h-12 mb-2 bg-white rounded-full flex items-center justify-center border-2 border-slate-200 flex-shrink-0">
                    <Image
                      src={getSpritePath(creature.Name, shinyCreatures.has(creature.Name))}
                      alt={creature.Name}
                      width={48}
                      height={48}
                      className="w-full h-full object-contain p-1"
                      style={{ imageRendering: 'pixelated' }}
                    />
                  </div>
                  <div className="text-xs font-medium text-slate-600 mb-1">
                    #{String(creature.DexNumber).padStart(3, '0')}
                  </div>
                  <div className="font-bold text-slate-900 text-sm mb-1 text-center">{creature.Name}</div>
                  <div className="flex gap-1 flex-wrap justify-center">
                    {creature.Types?.map(t => (
                      <span
                        key={t}
                        className="text-[8px] px-1 py-0.5 bg-slate-200 text-slate-700 rounded"
                      >
                        {t}
                      </span>
                    ))}
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {team.length === 0 && (
          <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-12 text-center">
            <p className="text-slate-500 mb-4">No creatures in team</p>
            <p className="text-sm text-slate-400">Search and add creatures above to build your team</p>
          </div>
        )}
      </AnimatedDiv>
    </div>
  );
}


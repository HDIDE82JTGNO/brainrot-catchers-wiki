"use client";

import React, { useState, useMemo, useEffect } from 'react';
import { TeamAnalyzer } from '@/components/TeamAnalyzer';
import { TeamMemberEditor } from '@/components/TeamMemberEditor';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import itemsData from '../../data/items.json';
import { Creature, Move, Item } from '@/types';
import { TeamMember, createDefaultTeamMember } from '@/lib/teamTypes';
import { getSpringConfig } from '@/lib/springConfigs';
import { useSpring, animated } from '@react-spring/web';
import Image from 'next/image';
import Link from 'next/link';
import { getSpritePath } from '@/lib/spriteUtils';
import { TypeBadge } from '@/components/TypeBadge';
import { ItemImage } from '@/components/ItemImage';
import { parseTeamFromUrl, shareTeam } from '@/lib/shareUtils';
import { ShareButton } from '@/components/ShareButton';
import { CopyTeamButton } from '@/components/CopyDataButton';
import { IconEdit } from '@tabler/icons-react';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];
const items = itemsData as unknown as Item[];

const AnimatedDiv = animated.div as any;
const MAX_TEAM_SIZE = 6;
const TEAM_STORAGE_KEY = 'brainrot-team-builder-team';

// Helper to save team to localStorage
function saveTeamToStorage(team: TeamMember[]) {
  if (typeof window === 'undefined') return;
  try {
    localStorage.setItem(TEAM_STORAGE_KEY, JSON.stringify(team));
  } catch (error) {
    console.error('Failed to save team to localStorage:', error);
  }
}

// Helper to load team from localStorage
function loadTeamFromStorage(creatures: Creature[]): TeamMember[] | null {
  if (typeof window === 'undefined') return null;
  try {
    const stored = localStorage.getItem(TEAM_STORAGE_KEY);
    if (!stored) return null;
    const data = JSON.parse(stored);
    if (!Array.isArray(data)) return null;
    
    // Reconstruct team members from stored data
    return data
      .map((item: any): TeamMember | null => {
        const creature = creatures.find(c => c.Id === item.Id);
        if (!creature) return null;
        return {
          ...creature,
          ivs: item.ivs || { HP: 0, Attack: 0, Defense: 0, SpecialAttack: 0, SpecialDefense: 0, Speed: 0 },
          evs: item.evs || { HP: 0, Attack: 0, Defense: 0, SpecialAttack: 0, SpecialDefense: 0, Speed: 0 },
          moves: item.moves || [],
          level: item.level || 50,
          heldItem: item.heldItem,
        };
      })
      .filter((m): m is TeamMember => m !== null);
  } catch (error) {
    console.error('Failed to load team from localStorage:', error);
    return null;
  }
}

export default function TeamBuilderPage() {
  const [team, setTeam] = useState<TeamMember[]>([]);
  const [shinyCreatures, setShinyCreatures] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [teamLoadedFromUrl, setTeamLoadedFromUrl] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);

  // Load team from URL or localStorage on mount
  useEffect(() => {
    if (isInitialized) return;
    
    // First check URL
    const urlTeam = parseTeamFromUrl(creatures);
    if (urlTeam && urlTeam.length > 0) {
      setTeam(urlTeam);
      setTeamLoadedFromUrl(true);
      setTimeout(() => setTeamLoadedFromUrl(false), 3000);
      saveTeamToStorage(urlTeam);
    } else {
      // Fallback to localStorage
      const storedTeam = loadTeamFromStorage(creatures);
      if (storedTeam && storedTeam.length > 0) {
        setTeam(storedTeam);
      }
    }
    setIsInitialized(true);
  }, [isInitialized]);

  // Save team to localStorage whenever it changes
  useEffect(() => {
    if (isInitialized) {
      saveTeamToStorage(team);
    }
  }, [team, isInitialized]);

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
    const newTeam = [...team, createDefaultTeamMember(creature)];
    setTeam(newTeam);
  };

  const removeFromTeam = (index: number) => {
    const newTeam = team.filter((_, i) => i !== index);
    setTeam(newTeam);
  };

  const clearTeam = () => {
    setTeam([]);
    if (typeof window !== 'undefined') {
      localStorage.removeItem(TEAM_STORAGE_KEY);
    }
  };

  const updateTeamMember = (index: number, member: TeamMember) => {
    const newTeam = [...team];
    newTeam[index] = member;
    setTeam(newTeam);
    setEditingIndex(null);
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
        {/* Team Loaded Notification */}
        {teamLoadedFromUrl && (
          <div className="bg-green-100 border-2 border-green-300 rounded-lg p-4 text-green-700 text-center">
            Team loaded from URL!
          </div>
        )}

        {/* Team Slots */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4">
            <h2 className="text-xl font-bold text-slate-900">
              Team ({team.length}/{MAX_TEAM_SIZE})
            </h2>
            <div className="flex gap-2">
              {team.length > 0 && (
                <>
                  <CopyTeamButton team={team} />
                  <ShareButton
                    url={shareTeam(team)}
                    title="Share Team - Brainrot Catchers Wiki"
                    text={`Check out my team of ${team.length} creatures!`}
                  />
                  <button
                    onClick={clearTeam}
                    className="px-4 py-2 bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition-colors font-medium text-sm"
                  >
                    Clear Team
                  </button>
                </>
              )}
            </div>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
            {Array.from({ length: MAX_TEAM_SIZE }).map((_, idx) => {
              const member = team[idx];
              const totalIVs = member ? Object.values(member.ivs).reduce((a, b) => a + b, 0) : 0;
              const totalEVs = member ? Object.values(member.evs).reduce((a, b) => a + b, 0) : 0;
              
              return (
                <div
                  key={idx}
                  className={`relative border-2 rounded-xl p-3 ${
                    member
                      ? 'border-blue-400 bg-blue-50'
                      : 'border-slate-200 bg-slate-50 border-dashed min-h-[200px]'
                  }`}
                >
                  {member ? (
                    <>
                      <button
                        onClick={() => removeFromTeam(idx)}
                        className="absolute top-1 right-1 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center text-xs font-bold hover:bg-red-600 transition-colors z-10"
                      >
                        ×
                      </button>
                      <button
                        onClick={() => setEditingIndex(idx)}
                        className="absolute top-1 left-1 w-6 h-6 bg-blue-500 text-white rounded-full flex items-center justify-center hover:bg-blue-600 transition-colors z-10"
                        title="Edit"
                      >
                        <IconEdit className="w-3 h-3" />
                      </button>
                      <Link href={`/creatures/${encodeURIComponent(member.Name)}`}>
                        <div className="w-full flex flex-col items-center cursor-pointer hover:opacity-80 transition-opacity pt-6">
                          <div className="relative w-16 h-16 mb-2 bg-white rounded-full flex items-center justify-center border-2 border-slate-200">
                            <Image
                              src={getSpritePath(member.Name, shinyCreatures.has(member.Name))}
                              alt={member.Name}
                              width={64}
                              height={64}
                              className="w-full h-full object-contain p-1"
                              style={{ imageRendering: 'pixelated' }}
                            />
                            {member.heldItem && (() => {
                              const item = items.find(i => i.Name === member.heldItem);
                              return item ? (
                                <div className="absolute -bottom-1 -right-1 w-5 h-5 bg-white rounded-full border-2 border-slate-300 flex items-center justify-center shadow-sm">
                                  <ItemImage item={item} moves={moves} size={20} />
                                </div>
                              ) : null;
                            })()}
                          </div>
                          <div className="text-xs font-bold text-slate-900 text-center mb-1">{member.Name}</div>
                          <div className="flex gap-0.5 mb-2">
                            {member.Types?.map(t => (
                              <TypeBadge key={t} type={t} className="scale-75" />
                            ))}
                          </div>
                          
                          {/* Level */}
                          <div className="text-[10px] text-slate-600 mb-1">
                            Lv. {member.level}
                          </div>
                          
                          {/* IVs Summary */}
                          {totalIVs > 0 && (
                            <div className="text-[9px] text-slate-600 mb-1">
                              IVs: {totalIVs}/186
                            </div>
                          )}
                          
                          {/* EVs Summary */}
                          {totalEVs > 0 && (
                            <div className="text-[9px] text-slate-600 mb-1">
                              EVs: {totalEVs}/510
                            </div>
                          )}
                          
                          {/* Moves */}
                          {member.moves.length > 0 && (
                            <div className="mt-1 w-full">
                              <div className="text-[9px] font-semibold text-slate-700 mb-1">Moves:</div>
                              <div className="space-y-0.5">
                                {member.moves.slice(0, 2).map((move, i) => (
                                  <div key={i} className="text-[8px] text-slate-600 truncate px-1">
                                    {move}
                                  </div>
                                ))}
                                {member.moves.length > 2 && (
                                  <div className="text-[8px] text-slate-500 italic px-1">
                                    +{member.moves.length - 2} more
                                  </div>
                                )}
                              </div>
                            </div>
                          )}
                        </div>
                      </Link>
                    </>
                  ) : (
                    <div className="flex items-center justify-center h-full min-h-[200px]">
                      <div className="text-slate-400 text-xs text-center">Empty Slot</div>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Team Member Editor Modal */}
        {editingIndex !== null && team[editingIndex] && (
          <TeamMemberEditor
            member={team[editingIndex]}
            moves={moves}
            items={items}
            onSave={(member) => updateTeamMember(editingIndex, member)}
            onCancel={() => setEditingIndex(null)}
          />
        )}

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
              className="w-full pl-10 pr-4 py-2 border-2 border-slate-300 rounded-lg bg-white text-slate-900 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
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


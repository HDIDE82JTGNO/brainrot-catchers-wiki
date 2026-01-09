"use client";

import React, { useState, useMemo, useEffect } from 'react';
import { TeamAnalyzer } from '@/components/TeamAnalyzer';
import { TeamMemberEditor } from '@/components/TeamMemberEditor';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import { Creature, Move } from '@/types';
import { TeamMember, createDefaultTeamMember } from '@/lib/teamTypes';
import { getSpringConfig } from '@/lib/springConfigs';
import { useSpring, animated } from '@react-spring/web';
import Image from 'next/image';
import Link from 'next/link';
import { getSpritePath } from '@/lib/spriteUtils';
import { TypeBadge } from '@/components/TypeBadge';
import { parseTeamFromUrl, shareTeam } from '@/lib/shareUtils';
import { ShareButton } from '@/components/ShareButton';
import { CopyTeamButton } from '@/components/CopyDataButton';
import { IconEdit } from '@tabler/icons-react';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];

const AnimatedDiv = animated.div as any;
const MAX_TEAM_SIZE = 6;

export default function TeamBuilderPage() {
  const [team, setTeam] = useState<TeamMember[]>([]);
  const [shinyCreatures, setShinyCreatures] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [teamLoadedFromUrl, setTeamLoadedFromUrl] = useState(false);

  // Load team from URL on mount
  useEffect(() => {
    const urlTeam = parseTeamFromUrl(creatures);
    if (urlTeam && urlTeam.length > 0) {
      setTeam(urlTeam);
      setTeamLoadedFromUrl(true);
      setTimeout(() => setTeamLoadedFromUrl(false), 3000);
    }
  }, []);

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
    setTeam([...team, createDefaultTeamMember(creature)]);
  };

  const removeFromTeam = (index: number) => {
    setTeam(team.filter((_, i) => i !== index));
  };

  const clearTeam = () => {
    setTeam([]);
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
          <div className="bg-green-100 dark:bg-green-900/30 border-2 border-green-300 dark:border-green-700 rounded-lg p-4 text-green-700 dark:text-green-300 text-center">
            Team loaded from URL!
          </div>
        )}

        {/* Team Slots */}
        <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4">
            <h2 className="text-xl font-bold text-slate-900 dark:text-slate-100">
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
                    className="px-4 py-2 bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 rounded-lg hover:bg-red-200 dark:hover:bg-red-900/50 transition-colors font-medium text-sm"
                  >
                    Clear Team
                  </button>
                </>
              )}
            </div>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-4">
            {Array.from({ length: MAX_TEAM_SIZE }).map((_, idx) => {
              const member = team[idx];
              return (
                <div
                  key={idx}
                  className={`relative aspect-square border-2 rounded-xl flex flex-col items-center justify-center p-2 ${
                    member
                      ? 'border-blue-400 dark:border-blue-500 bg-blue-50 dark:bg-blue-900/30'
                      : 'border-slate-200 dark:border-slate-700 bg-slate-50 dark:bg-slate-700/50 border-dashed'
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
                        <div className="w-full h-full flex flex-col items-center justify-center cursor-pointer hover:opacity-80 transition-opacity">
                          <div className="w-16 h-16 mb-1 bg-white dark:bg-slate-800 rounded-full flex items-center justify-center border-2 border-slate-200 dark:border-slate-600">
                            <Image
                              src={getSpritePath(member.Name, shinyCreatures.has(member.Name))}
                              alt={member.Name}
                              width={64}
                              height={64}
                              className="w-full h-full object-contain p-1"
                              style={{ imageRendering: 'pixelated' }}
                            />
                          </div>
                          <div className="text-xs font-bold text-slate-900 dark:text-slate-100 text-center mb-1">{member.Name}</div>
                          <div className="flex gap-0.5">
                            {member.Types?.map(t => (
                              <TypeBadge key={t} type={t} className="scale-75" />
                            ))}
                          </div>
                          {member.moves.length > 0 && (
                            <div className="text-[10px] text-slate-600 dark:text-slate-400 mt-1">
                              {member.moves.length} move{member.moves.length !== 1 ? 's' : ''}
                            </div>
                          )}
                        </div>
                      </Link>
                    </>
                  ) : (
                    <div className="text-slate-400 dark:text-slate-500 text-xs text-center">Empty Slot</div>
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
        <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Add Creatures to Team</h2>
          
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
              className="w-full pl-10 pr-4 py-2 border-2 border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
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
                      ? 'border-blue-500 dark:border-blue-400 bg-blue-50 dark:bg-blue-900/30 opacity-50 cursor-not-allowed'
                      : team.length >= MAX_TEAM_SIZE
                      ? 'border-slate-200 dark:border-slate-700 opacity-50 cursor-not-allowed'
                      : 'border-slate-200 dark:border-slate-700 hover:border-blue-400 dark:hover:border-blue-500 hover:shadow-md dark:bg-slate-700/50'
                  }`}
                >
                  <div className="w-12 h-12 mb-2 bg-white dark:bg-slate-800 rounded-full flex items-center justify-center border-2 border-slate-200 dark:border-slate-600 flex-shrink-0">
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
                  <div className="font-bold text-slate-900 dark:text-slate-100 text-sm mb-1 text-center">{creature.Name}</div>
                  <div className="flex gap-1 flex-wrap justify-center">
                    {creature.Types?.map(t => (
                      <span
                        key={t}
                        className="text-[8px] px-1 py-0.5 bg-slate-200 dark:bg-slate-600 text-slate-700 dark:text-slate-300 rounded"
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
          <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-12 text-center">
            <p className="text-slate-500 dark:text-slate-400 mb-4">No creatures in team</p>
            <p className="text-sm text-slate-400 dark:text-slate-500">Search and add creatures above to build your team</p>
          </div>
        )}
      </AnimatedDiv>
    </div>
  );
}


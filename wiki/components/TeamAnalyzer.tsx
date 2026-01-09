"use client";

import React, { useMemo } from 'react';
import { Move } from '@/types';
import { TeamMember } from '@/lib/teamTypes';
import { TypeBadge } from './TypeBadge';
import { analyzeTeamCoverage } from '@/lib/coverageAnalysis';
import { getWeaknesses, getResistances, getImmunities } from '@/lib/typeEffectiveness';
import { getSpritePath } from '@/lib/spriteUtils';
import { calculateStats } from '@/lib/statCalculator';
import Image from 'next/image';
import Link from 'next/link';

interface TeamAnalyzerProps {
  team: TeamMember[];
  moves: Move[];
  shinyCreatures?: Set<string>;
  className?: string;
}

export function TeamAnalyzer({ team, moves, shinyCreatures = new Set(), className = '' }: TeamAnalyzerProps) {
  // Get movesets for each creature (use custom moves if set, otherwise full learnset)
  const creatureMovesets = useMemo(() => {
    return team.map(member => {
      if (member.moves.length > 0) {
        // Use custom moveset
        return moves.filter(m => member.moves.includes(m.Name));
      } else {
        // Fallback to full learnset
        const moveNames: string[] = [];
        if (member.Learnset) {
          Object.values(member.Learnset).forEach(moveList => {
            if (Array.isArray(moveList)) {
              moveNames.push(...moveList);
            }
          });
        }
        return moves.filter(m => moveNames.includes(m.Name));
      }
    });
  }, [team, moves]);

  // Analyze team coverage
  const coverageAnalysis = useMemo(() => {
    if (creatureMovesets.length === 0) return null;
    return analyzeTeamCoverage(creatureMovesets);
  }, [creatureMovesets]);

  // Analyze team weaknesses/resistances
  const teamWeaknesses = useMemo(() => {
    const allWeaknesses = new Map<string, number>();
    
    for (const creature of team) {
      const weaknesses = getWeaknesses(creature.Types || []);
      for (const weakness of weaknesses) {
        allWeaknesses.set(weakness, (allWeaknesses.get(weakness) || 0) + 1);
      }
    }
    
    return Array.from(allWeaknesses.entries())
      .map(([type, count]) => ({ type, count }))
      .sort((a, b) => b.count - a.count);
  }, [team]);

  const teamResistances = useMemo(() => {
    const allResistances = new Map<string, number>();
    
    for (const creature of team) {
      const resistances = getResistances(creature.Types || []);
      for (const resistance of resistances) {
        allResistances.set(resistance, (allResistances.get(resistance) || 0) + 1);
      }
    }
    
    return Array.from(allResistances.entries())
      .map(([type, count]) => ({ type, count }))
      .sort((a, b) => b.count - a.count);
  }, [team]);

  const teamImmunities = useMemo(() => {
    const allImmunities = new Set<string>();
    
    for (const creature of team) {
      const immunities = getImmunities(creature.Types || []);
      immunities.forEach(imm => allImmunities.add(imm));
    }
    
    return Array.from(allImmunities);
  }, [team]);

  // Calculate stat totals (using calculated stats if IVs/EVs/level are set)
  const statTotals = useMemo(() => {
    return team.reduce((acc, member) => {
      // Calculate actual stats if IVs/EVs are set
      const stats = calculateStats(member.BaseStats, member.level, member.ivs, member.evs);
      return {
        hp: acc.hp + stats.HP,
        attack: acc.attack + stats.Attack,
        defense: acc.defense + stats.Defense,
        specialAttack: acc.specialAttack + stats.SpecialAttack,
        specialDefense: acc.specialDefense + stats.SpecialDefense,
        speed: acc.speed + stats.Speed,
      };
    }, { hp: 0, attack: 0, defense: 0, specialAttack: 0, specialDefense: 0, speed: 0 });
  }, [team]);

  if (team.length === 0) {
    return (
      <div className={`bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-12 text-center ${className}`}>
        <p className="text-slate-500 dark:text-slate-400">Add creatures to your team to see analysis</p>
      </div>
    );
  }

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Team Overview */}
      <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
        <h3 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Team Overview</h3>
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-4">
          {team.map((member, idx) => (
            <Link
              key={member.Id}
              href={`/creatures/${encodeURIComponent(member.Name)}`}
              className="text-center hover:opacity-80 transition-opacity"
            >
              <div className="w-20 h-20 mx-auto mb-2 bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-700 dark:to-slate-800 rounded-full flex items-center justify-center border-2 border-slate-200 dark:border-slate-600">
                <Image
                  src={getSpritePath(member.Name, shinyCreatures.has(member.Name))}
                  alt={member.Name}
                  width={80}
                  height={80}
                  className="w-full h-full object-contain p-1"
                  style={{ imageRendering: 'pixelated' }}
                />
              </div>
              <div className="text-xs font-bold text-slate-900 dark:text-slate-100">{member.Name}</div>
              <div className="flex justify-center gap-0.5 mt-1">
                {member.Types?.map(t => (
                  <TypeBadge key={t} type={t} className="scale-75" />
                ))}
              </div>
            </Link>
          ))}
        </div>
      </div>

      {/* Coverage Analysis */}
      {coverageAnalysis && (
        <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
          <h3 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Team Move Coverage</h3>
          <div className="p-4 bg-gradient-to-r from-blue-50 to-blue-100 dark:from-blue-900/30 dark:to-blue-800/30 rounded-lg border-2 border-blue-200 dark:border-blue-700 mb-4">
            <div className="flex items-center justify-between">
              <span className="font-semibold text-slate-900 dark:text-slate-100">Coverage:</span>
              <span className="text-2xl font-black text-blue-600 dark:text-blue-400">
                {coverageAnalysis.coveragePercentage.toFixed(1)}%
              </span>
            </div>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="p-4 rounded-xl border-2 border-green-200 bg-green-50">
              <div className="text-sm font-bold text-green-800 uppercase mb-2">
                Super Effective ({coverageAnalysis.superEffective.length})
              </div>
              <div className="flex flex-wrap gap-1.5">
                {coverageAnalysis.superEffective.map(result => (
                  <TypeBadge key={result.type} type={result.type} className="scale-75" />
                ))}
              </div>
            </div>
            {coverageAnalysis.gaps.length > 0 && (
              <div className="p-4 rounded-xl border-2 border-red-200 bg-red-50">
                <div className="text-sm font-bold text-red-800 uppercase mb-2">
                  Coverage Gaps ({coverageAnalysis.gaps.length})
                </div>
                <div className="flex flex-wrap gap-1.5">
                  {coverageAnalysis.gaps.map(type => (
                    <TypeBadge key={type} type={type} className="scale-75" />
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Team Weaknesses */}
      {teamWeaknesses.length > 0 && (
        <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
          <h3 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Team Weaknesses</h3>
          <div className="flex flex-wrap gap-2">
            {teamWeaknesses.map(({ type, count }) => (
              <div
                key={type}
                className="flex items-center gap-1 px-3 py-1.5 bg-red-100 border-2 border-red-300 rounded-lg"
              >
                <TypeBadge type={type} className="scale-75" />
                <span className="text-xs font-bold text-red-700">
                  {count} weak
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Team Resistances */}
      {teamResistances.length > 0 && (
        <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
          <h3 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Team Resistances</h3>
          <div className="flex flex-wrap gap-2">
            {teamResistances.map(({ type, count }) => (
              <div
                key={type}
                className="flex items-center gap-1 px-3 py-1.5 bg-orange-100 border-2 border-orange-300 rounded-lg"
              >
                <TypeBadge type={type} className="scale-75" />
                <span className="text-xs font-bold text-orange-700">
                  {count} resist
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Team Immunities */}
      {teamImmunities.length > 0 && (
        <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
          <h3 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Team Immunities</h3>
          <div className="flex flex-wrap gap-2">
            {teamImmunities.map(type => (
              <TypeBadge key={type} type={type} />
            ))}
          </div>
        </div>
      )}

      {/* Stat Totals */}
      <div className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-xl p-6">
        <h3 className="text-xl font-bold text-slate-900 dark:text-slate-100 mb-4">Team Stat Totals</h3>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          <div className="p-3 bg-slate-50 dark:bg-slate-700 rounded-lg">
            <div className="text-xs text-slate-600 dark:text-slate-400 mb-1">HP</div>
            <div className="text-2xl font-black text-slate-900 dark:text-slate-100">{statTotals.hp}</div>
          </div>
          <div className="p-3 bg-slate-50 dark:bg-slate-700 rounded-lg">
            <div className="text-xs text-slate-600 dark:text-slate-400 mb-1">Attack</div>
            <div className="text-2xl font-black text-slate-900 dark:text-slate-100">{statTotals.attack}</div>
          </div>
          <div className="p-3 bg-slate-50 dark:bg-slate-700 rounded-lg">
            <div className="text-xs text-slate-600 dark:text-slate-400 mb-1">Defense</div>
            <div className="text-2xl font-black text-slate-900 dark:text-slate-100">{statTotals.defense}</div>
          </div>
          <div className="p-3 bg-slate-50 dark:bg-slate-700 rounded-lg">
            <div className="text-xs text-slate-600 dark:text-slate-400 mb-1">Special Attack</div>
            <div className="text-2xl font-black text-slate-900 dark:text-slate-100">{statTotals.specialAttack}</div>
          </div>
          <div className="p-3 bg-slate-50 dark:bg-slate-700 rounded-lg">
            <div className="text-xs text-slate-600 dark:text-slate-400 mb-1">Special Defense</div>
            <div className="text-2xl font-black text-slate-900 dark:text-slate-100">{statTotals.specialDefense}</div>
          </div>
          <div className="p-3 bg-slate-50 dark:bg-slate-700 rounded-lg">
            <div className="text-xs text-slate-600 dark:text-slate-400 mb-1">Speed</div>
            <div className="text-2xl font-black text-slate-900 dark:text-slate-100">{statTotals.speed}</div>
          </div>
        </div>
        <div className="mt-4 pt-4 border-t border-slate-200 dark:border-slate-700">
          <div className="text-sm text-slate-600 dark:text-slate-400">Total BST:</div>
          <div className="text-3xl font-black text-blue-600 dark:text-blue-400">
            {statTotals.hp + statTotals.attack + statTotals.defense + statTotals.specialAttack + statTotals.specialDefense + statTotals.speed}
          </div>
        </div>
      </div>
    </div>
  );
}


"use client";

import React from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { Creature, Move } from '@/types';
import { TypeBadge } from './TypeBadge';
import { StatRadar } from './StatRadar';
import { getSpritePath } from '@/lib/spriteUtils';
import { getWeaknesses, getResistances, getImmunities } from '@/lib/typeEffectiveness';

interface ComparisonViewProps {
  creatures: Creature[];
  moves: Move[];
  shinyCreatures?: Set<string>;
  onRemove?: (index: number) => void;
  className?: string;
}

export function ComparisonView({ 
  creatures, 
  moves, 
  shinyCreatures = new Set(),
  onRemove,
  className = '' 
}: ComparisonViewProps) {
  if (creatures.length === 0) {
    return (
      <div className={`bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-12 text-center ${className}`}>
        <p className="text-slate-500">Select creatures to compare</p>
      </div>
    );
  }

  // Get all unique stat names
  const statNames = ['HP', 'Attack', 'Defense', 'SpecialAttack', 'SpecialDefense', 'Speed'] as const;

  // Calculate stat totals
  const statTotals = creatures.map(c => {
    const stats = c.BaseStats;
    return stats.HP + stats.Attack + stats.Defense + stats.SpecialAttack + stats.SpecialDefense + stats.Speed;
  });

  // Get move pools
  const movePools = creatures.map(c => {
    const moves: string[] = [];
    if (c.Learnset) {
      Object.values(c.Learnset).forEach(moveList => {
        if (Array.isArray(moveList)) {
          moves.push(...moveList);
        }
      });
    }
    return Array.from(new Set(moves));
  });

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Header Row */}
      <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 overflow-x-auto">
        <div className="flex gap-4 min-w-max">
          <div className="w-48 flex-shrink-0"></div>
          {creatures.map((creature, idx) => (
            <div key={creature.Id} className="w-64 flex-shrink-0 relative">
              {onRemove && (
                <button
                  onClick={() => onRemove(idx)}
                  className="absolute -top-2 -right-2 w-6 h-6 bg-red-500 text-white rounded-full flex items-center justify-center text-xs font-bold hover:bg-red-600 transition-colors z-10"
                  title="Remove from comparison"
                >
                  ×
                </button>
              )}
              <Link href={`/creatures/${encodeURIComponent(creature.Name)}`}>
                <div className="text-center cursor-pointer hover:opacity-80 transition-opacity">
                  <div className="w-32 h-32 mx-auto mb-2 bg-gradient-to-br from-slate-50 to-slate-100 rounded-full flex items-center justify-center border-2 border-slate-200">
                    <Image
                      src={getSpritePath(creature.Name, shinyCreatures.has(creature.Name))}
                      alt={creature.Name}
                      width={128}
                      height={128}
                      className="w-full h-full object-contain p-2"
                      style={{ imageRendering: 'pixelated' }}
                    />
                  </div>
                  <h3 className="font-bold text-lg text-slate-900 mb-1">{creature.Name}</h3>
                  <div className="text-xs text-slate-500 mb-2">#{String(creature.DexNumber).padStart(3, '0')}</div>
                  <div className="flex justify-center gap-1 mb-2">
                    {creature.Types?.map(t => (
                      <TypeBadge key={t} type={t} className="scale-75" />
                    ))}
                  </div>
                </div>
              </Link>
            </div>
          ))}
        </div>
      </div>

      {/* Stats Comparison */}
      <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 overflow-x-auto">
        <h3 className="text-xl font-bold text-slate-900 mb-4">Base Stats</h3>
        <div className="min-w-max">
          <table className="w-full">
            <thead>
              <tr>
                <th className="text-left py-2 px-4 font-semibold text-slate-700">Stat</th>
                {creatures.map((c, idx) => (
                  <th key={c.Id} className="text-center py-2 px-4 font-semibold text-slate-700 min-w-[8rem]">
                    {c.Name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {statNames.map(statName => {
                const values = creatures.map(c => c.BaseStats[statName]);
                const maxValue = Math.max(...values);
                const minValue = Math.min(...values);
                
                return (
                  <tr key={statName}>
                    <td className="py-2 px-4 font-medium text-slate-700">{statName}</td>
                    {values.map((value, idx) => {
                      const isMax = value === maxValue && maxValue !== minValue;
                      const isMin = value === minValue && maxValue !== minValue;
                      
                      return (
                        <td
                          key={idx}
                          className={`py-2 px-4 text-center ${
                            isMax ? 'bg-green-50 font-bold text-green-700' : ''
                          } ${
                            isMin ? 'bg-red-50 font-bold text-red-700' : ''
                          }`}
                        >
                          {value}
                          {isMax && <span className="ml-1 text-xs">↑</span>}
                          {isMin && maxValue !== minValue && <span className="ml-1 text-xs">↓</span>}
                        </td>
                      );
                    })}
                  </tr>
                );
              })}
              <tr className="bg-slate-50 font-bold">
                <td className="py-2 px-4 text-slate-700">Total</td>
                {statTotals.map((total, idx) => {
                  const maxTotal = Math.max(...statTotals);
                  const minTotal = Math.min(...statTotals);
                  const isMax = total === maxTotal && maxTotal !== minTotal;
                  const isMin = total === minTotal && maxTotal !== minTotal;
                  
                  return (
                    <td
                      key={idx}
                      className={`py-2 px-4 text-center ${
                        isMax ? 'bg-green-100 text-green-800' : ''
                      } ${
                        isMin ? 'bg-red-100 text-red-800' : ''
                      }`}
                    >
                      {total}
                      {isMax && <span className="ml-1 text-xs">↑</span>}
                      {isMin && maxTotal !== minTotal && <span className="ml-1 text-xs">↓</span>}
                    </td>
                  );
                })}
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {/* Stat Radar Charts */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {creatures.map((creature, idx) => (
          <div key={creature.Id} className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
            <h4 className="text-lg font-bold text-slate-900 mb-4 text-center">{creature.Name}</h4>
            <StatRadar stats={creature.BaseStats} />
          </div>
        ))}
      </div>

      {/* Type Effectiveness */}
      <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
        <h3 className="text-xl font-bold text-slate-900 mb-4">Type Effectiveness</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {creatures.map((creature, idx) => {
            const weaknesses = getWeaknesses(creature.Types || []);
            const resistances = getResistances(creature.Types || []);
            const immunities = getImmunities(creature.Types || []);
            
            return (
              <div key={creature.Id} className="p-4 border-2 border-slate-200 rounded-xl">
                <h4 className="font-bold text-slate-900 mb-3">{creature.Name}</h4>
                {weaknesses.length > 0 && (
                  <div className="mb-3">
                    <div className="text-xs font-bold text-red-700 uppercase mb-1">Weaknesses</div>
                    <div className="flex flex-wrap gap-1">
                      {weaknesses.map(type => (
                        <TypeBadge key={type} type={type} className="scale-75" />
                      ))}
                    </div>
                  </div>
                )}
                {resistances.length > 0 && (
                  <div className="mb-3">
                    <div className="text-xs font-bold text-orange-700 uppercase mb-1">Resistances</div>
                    <div className="flex flex-wrap gap-1">
                      {resistances.map(type => (
                        <TypeBadge key={type} type={type} className="scale-75" />
                      ))}
                    </div>
                  </div>
                )}
                {immunities.length > 0 && (
                  <div>
                    <div className="text-xs font-bold text-gray-700 uppercase mb-1">Immunities</div>
                    <div className="flex flex-wrap gap-1">
                      {immunities.map(type => (
                        <TypeBadge key={type} type={type} className="scale-75" />
                      ))}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      {/* Move Pool Comparison */}
      <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
        <h3 className="text-xl font-bold text-slate-900 mb-4">Move Pool Sizes</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {creatures.map((creature, idx) => (
            <div key={creature.Id} className="p-4 border-2 border-slate-200 rounded-xl">
              <h4 className="font-bold text-slate-900 mb-2">{creature.Name}</h4>
              <div className="text-2xl font-black text-blue-600">{movePools[idx].length}</div>
              <div className="text-sm text-slate-500">Total moves</div>
            </div>
          ))}
        </div>
      </div>

      {/* Other Info */}
      <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 overflow-x-auto">
        <h3 className="text-xl font-bold text-slate-900 mb-4">Other Information</h3>
        <div className="min-w-max">
          <table className="w-full">
            <thead>
              <tr>
                <th className="text-left py-2 px-4 font-semibold text-slate-700">Property</th>
                {creatures.map(c => (
                  <th key={c.Id} className="text-center py-2 px-4 font-semibold text-slate-700 min-w-[8rem]">
                    {c.Name}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              <tr>
                <td className="py-2 px-4 font-medium text-slate-700">Catch Rate</td>
                {creatures.map(c => (
                  <td key={c.Id} className="py-2 px-4 text-center">
                    {c.CatchRateScalar || '-'}
                  </td>
                ))}
              </tr>
              <tr>
                <td className="py-2 px-4 font-medium text-slate-700">Weight</td>
                {creatures.map(c => (
                  <td key={c.Id} className="py-2 px-4 text-center">
                    {c.BaseWeightKg ? `${c.BaseWeightKg} kg` : '-'}
                  </td>
                ))}
              </tr>
              <tr>
                <td className="py-2 px-4 font-medium text-slate-700">Female Ratio</td>
                {creatures.map(c => (
                  <td key={c.Id} className="py-2 px-4 text-center">
                    {c.FemaleChance ? `${c.FemaleChance}%` : '-'}
                  </td>
                ))}
              </tr>
              <tr>
                <td className="py-2 px-4 font-medium text-slate-700">Evolution Level</td>
                {creatures.map(c => (
                  <td key={c.Id} className="py-2 px-4 text-center">
                    {c.EvolutionLevel ? `Lv. ${c.EvolutionLevel}` : '-'}
                  </td>
                ))}
              </tr>
              <tr>
                <td className="py-2 px-4 font-medium text-slate-700">Evolves Into</td>
                {creatures.map(c => (
                  <td key={c.Id} className="py-2 px-4 text-center">
                    {c.EvolvesInto ? (
                      <Link href={`/creatures/${encodeURIComponent(c.EvolvesInto)}`} className="text-blue-600 hover:underline">
                        {c.EvolvesInto}
                      </Link>
                    ) : '-'}
                  </td>
                ))}
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}


"use client";

import React, { useState, useMemo } from 'react';
import { Creature } from '@/types';
import { TypeBadge } from './TypeBadge';
import { getDefensiveEffectiveness, getWeaknesses, getResistances, getImmunities, getEffectivenessColor } from '@/lib/typeEffectiveness';
import { getAllTypes } from '@/lib/typeEffectiveness';

interface WeaknessCalculatorProps {
  creatures: Creature[];
  className?: string;
}

export function WeaknessCalculator({ creatures, className = '' }: WeaknessCalculatorProps) {
  const [selectedCreature, setSelectedCreature] = useState<Creature | null>(null);
  const [selectedTypes, setSelectedTypes] = useState<string[]>([]);
  const [mode, setMode] = useState<'creature' | 'types'>('creature');

  const allTypes = getAllTypes();

  const defensiveData = useMemo(() => {
    const types = mode === 'creature' && selectedCreature
      ? selectedCreature.Types || []
      : selectedTypes;

    if (types.length === 0) return null;

    const effectiveness = getDefensiveEffectiveness(types);
    const weaknesses = getWeaknesses(types);
    const resistances = getResistances(types);
    const immunities = getImmunities(types);

    return {
      types,
      effectiveness,
      weaknesses,
      resistances,
      immunities,
    };
  }, [mode, selectedCreature, selectedTypes]);

  const toggleType = (type: string) => {
    setSelectedTypes(prev => {
      if (prev.includes(type)) {
        return prev.filter(t => t !== type);
      }
      if (prev.length < 2) {
        return [...prev, type];
      }
      return prev;
    });
  };

  return (
    <div className={`bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 ${className}`}>
      <h2 className="text-2xl font-bold text-slate-900 mb-6">Weakness & Resistance Calculator</h2>

      <div className="space-y-6">
        {/* Mode Selection */}
        <div className="flex gap-2">
          <button
            onClick={() => {
              setMode('creature');
              setSelectedTypes([]);
            }}
            className={`px-4 py-2 rounded-lg font-medium transition-all ${
              mode === 'creature'
                ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
            }`}
          >
            By Creature
          </button>
          <button
            onClick={() => {
              setMode('types');
              setSelectedCreature(null);
            }}
            className={`px-4 py-2 rounded-lg font-medium transition-all ${
              mode === 'types'
                ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
            }`}
          >
            By Types
          </button>
        </div>

        {/* Creature Selection */}
        {mode === 'creature' && (
          <div>
            <label className="block text-sm font-semibold text-slate-700 mb-2">Select Creature</label>
            <select
              value={selectedCreature?.Name || ''}
              onChange={(e) => {
                const creature = creatures.find(c => c.Name === e.target.value);
                setSelectedCreature(creature || null);
              }}
              className="w-full p-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
            >
              <option value="">Select creature...</option>
              {creatures.map(c => (
                <option key={c.Id} value={c.Name}>{c.Name}</option>
              ))}
            </select>
            {selectedCreature && (
              <div className="mt-2 flex items-center gap-2">
                <span className="text-xs text-slate-600">Types:</span>
                {selectedCreature.Types?.map(t => (
                  <TypeBadge key={t} type={t} className="scale-75" />
                ))}
              </div>
            )}
          </div>
        )}

        {/* Type Selection */}
        {mode === 'types' && (
          <div>
            <label className="block text-sm font-semibold text-slate-700 mb-2">Select Types (up to 2)</label>
            <div className="flex flex-wrap gap-2">
              {allTypes.map(type => (
                <button
                  key={type}
                  onClick={() => toggleType(type)}
                  className={`transition-all ${
                    selectedTypes.includes(type)
                      ? 'ring-2 ring-blue-500 ring-offset-2 scale-105'
                      : 'opacity-70 hover:opacity-100 hover:scale-105'
                  }`}
                >
                  <TypeBadge type={type} />
                </button>
              ))}
            </div>
            {selectedTypes.length > 0 && (
              <div className="mt-2 flex items-center gap-2">
                <span className="text-sm text-slate-600">Selected:</span>
                {selectedTypes.map(type => (
                  <TypeBadge key={type} type={type} />
                ))}
                <button
                  onClick={() => setSelectedTypes([])}
                  className="text-xs text-red-600 hover:text-red-700 underline ml-2"
                >
                  Clear
                </button>
              </div>
            )}
          </div>
        )}

        {/* Results */}
        {defensiveData && (
          <div className="space-y-4">
            {/* Summary Cards */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              {defensiveData.weaknesses.length > 0 && (
                <div className="p-4 rounded-xl border-2 border-red-200 bg-red-50">
                  <div className="text-sm font-bold text-red-800 uppercase mb-2">
                    Weaknesses ({defensiveData.weaknesses.length})
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {defensiveData.weaknesses.map(type => {
                      const mult = defensiveData.effectiveness[type];
                      return (
                        <div key={type} className="flex items-center gap-1">
                          <TypeBadge type={type} className="scale-75" />
                          <span className="text-xs font-bold text-red-700">
                            {mult === 4 ? '4×' : '2×'}
                          </span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {defensiveData.resistances.length > 0 && (
                <div className="p-4 rounded-xl border-2 border-orange-200 bg-orange-50">
                  <div className="text-sm font-bold text-orange-800 uppercase mb-2">
                    Resistances ({defensiveData.resistances.length})
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {defensiveData.resistances.map(type => {
                      const mult = defensiveData.effectiveness[type];
                      return (
                        <div key={type} className="flex items-center gap-1">
                          <TypeBadge type={type} className="scale-75" />
                          <span className="text-xs font-bold text-orange-700">
                            {mult === 0.25 ? '¼×' : '½×'}
                          </span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}

              {defensiveData.immunities.length > 0 && (
                <div className="p-4 rounded-xl border-2 border-gray-200 bg-gray-50">
                  <div className="text-sm font-bold text-gray-800 uppercase mb-2">
                    Immunities ({defensiveData.immunities.length})
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {defensiveData.immunities.map(type => (
                      <TypeBadge key={type} type={type} className="scale-75" />
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Full Effectiveness Table */}
            <div className="overflow-x-auto">
              <table className="min-w-full">
                <thead>
                  <tr className="bg-slate-100">
                    <th className="px-4 py-2 text-left text-sm font-semibold text-slate-700">Attack Type</th>
                    <th className="px-4 py-2 text-center text-sm font-semibold text-slate-700">Effectiveness</th>
                    <th className="px-4 py-2 text-center text-sm font-semibold text-slate-700">Multiplier</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {allTypes.map(attackType => {
                    const mult = defensiveData.effectiveness[attackType];
                    return (
                      <tr key={attackType} className="hover:bg-slate-50">
                        <td className="px-4 py-2">
                          <TypeBadge type={attackType} className="scale-90" />
                        </td>
                        <td className="px-4 py-2 text-center">
                          <span className={`px-2 py-1 rounded text-xs font-bold ${getEffectivenessColor(mult)}`}>
                            {mult === 0 ? 'Immune' :
                             mult >= 4 ? '4× Super Effective' :
                             mult >= 2 ? 'Super Effective' :
                             mult >= 1 ? 'Normal' :
                             mult >= 0.5 ? 'Not Very Effective' :
                             mult >= 0.25 ? '2× Not Very Effective' :
                             'Immune'}
                          </span>
                        </td>
                        <td className="px-4 py-2 text-center font-bold text-slate-900">
                          {mult === 0 ? '0×' :
                           mult === 0.25 ? '¼×' :
                           mult === 0.5 ? '½×' :
                           mult === 1 ? '1×' :
                           mult === 2 ? '2×' :
                           mult === 4 ? '4×' :
                           `${mult}×`}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {!defensiveData && (
          <div className="p-8 text-center text-slate-500">
            {mode === 'creature' 
              ? 'Select a creature to see its weaknesses and resistances'
              : 'Select types to see their defensive effectiveness'}
          </div>
        )}
      </div>
    </div>
  );
}


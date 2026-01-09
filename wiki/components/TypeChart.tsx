"use client";

import React, { useState, useMemo } from 'react';
import { getAllTypes, getTypeEffectiveness, getEffectivenessColor, getEffectivenessLabel } from '@/lib/typeEffectiveness';
import { TypeBadge } from './TypeBadge';

interface TypeChartProps {
  selectedTypes?: string[];
  onTypeClick?: (type: string) => void;
  highlightDefender?: string[];
  className?: string;
}

export function TypeChart({ 
  selectedTypes = [], 
  onTypeClick,
  highlightDefender,
  className = ''
}: TypeChartProps) {
  const [hoveredAttackType, setHoveredAttackType] = useState<string | null>(null);
  const [hoveredDefenderType, setHoveredDefenderType] = useState<string | null>(null);
  const allTypes = getAllTypes();

  // Calculate effectiveness matrix
  const effectivenessMatrix = useMemo(() => {
    const matrix: Record<string, Record<string, number>> = {};
    for (const attackType of allTypes) {
      matrix[attackType] = {};
      for (const defenderType of allTypes) {
        matrix[attackType][defenderType] = getTypeEffectiveness(attackType, [defenderType]);
      }
    }
    return matrix;
  }, []);

  // Calculate dual-type effectiveness if highlightDefender is provided
  const dualTypeEffectiveness = useMemo(() => {
    if (!highlightDefender || highlightDefender.length === 0) return null;
    const effectiveness: Record<string, number> = {};
    for (const attackType of allTypes) {
      effectiveness[attackType] = getTypeEffectiveness(attackType, highlightDefender);
    }
    return effectiveness;
  }, [highlightDefender]);

  const getCellColor = (attackType: string, defenderType: string): string => {
    // If highlighting a specific defender type combination
    if (highlightDefender && highlightDefender.length > 0) {
      if (highlightDefender.includes(defenderType)) {
        const mult = dualTypeEffectiveness?.[attackType] ?? 1;
        return getEffectivenessColor(mult);
      }
    }
    
    // If hovering over attack type, show its effectiveness
    if (hoveredAttackType === attackType) {
      const mult = effectivenessMatrix[attackType][defenderType];
      return getEffectivenessColor(mult);
    }
    
    // If hovering over defender type, show what's effective against it
    if (hoveredDefenderType === defenderType) {
      const mult = effectivenessMatrix[attackType][defenderType];
      if (mult >= 2) return getEffectivenessColor(mult);
    }
    
    // Default: show neutral
    return 'bg-slate-100 hover:bg-slate-200';
  };

  const getCellText = (attackType: string, defenderType: string): string => {
    const mult = effectivenessMatrix[attackType][defenderType];
    if (mult === 0) return '0';
    if (mult === 0.5) return '½';
    if (mult === 2) return '2';
    if (mult === 4) return '4';
    return '';
  };

  return (
    <div className={`bg-white rounded-2xl border-2 border-slate-200 shadow-xl overflow-hidden ${className}`}>
      <div className="p-6 border-b-2 border-slate-200 bg-gradient-to-r from-slate-50 to-slate-100">
        <h2 className="text-2xl font-bold text-slate-900 mb-2">Type Effectiveness Chart</h2>
        <p className="text-sm text-slate-600">
          {highlightDefender && highlightDefender.length > 0
            ? `Showing effectiveness against ${highlightDefender.join('/')}`
            : 'Hover over types to see effectiveness'}
        </p>
      </div>

      <div className="overflow-x-auto p-6">
        <div className="inline-block min-w-full">
          <table className="min-w-full">
            <thead>
              <tr>
                <th className="px-2 py-2 text-xs font-bold text-slate-700 uppercase sticky left-0 bg-white z-10 border-r-2 border-slate-200">
                  Attack →
                  <br />
                  Defender ↓
                </th>
                {allTypes.map(type => (
                  <th
                    key={type}
                    className={`px-2 py-2 text-xs font-bold text-slate-700 uppercase cursor-pointer transition-colors ${
                      hoveredAttackType === type ? 'bg-blue-100' : ''
                    }`}
                    onMouseEnter={() => setHoveredAttackType(type)}
                    onMouseLeave={() => setHoveredAttackType(null)}
                    onClick={() => onTypeClick?.(type)}
                  >
                    <TypeBadge type={type} className="scale-75" />
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {allTypes.map(defenderType => (
                <tr key={defenderType}>
                  <td
                    className={`px-2 py-2 text-xs font-bold text-slate-700 sticky left-0 bg-white z-10 border-r-2 border-slate-200 cursor-pointer transition-colors ${
                      hoveredDefenderType === defenderType ? 'bg-blue-100' : ''
                    }`}
                    onMouseEnter={() => setHoveredDefenderType(defenderType)}
                    onMouseLeave={() => setHoveredDefenderType(null)}
                    onClick={() => onTypeClick?.(defenderType)}
                  >
                    <TypeBadge type={defenderType} className="scale-75" />
                  </td>
                  {allTypes.map(attackType => {
                    const mult = effectivenessMatrix[attackType][defenderType];
                    return (
                      <td
                        key={`${attackType}-${defenderType}`}
                        className={`px-2 py-2 text-center text-sm font-bold transition-all cursor-pointer border border-slate-100 ${getCellColor(attackType, defenderType)}`}
                        title={`${attackType} → ${defenderType}: ${getEffectivenessLabel(mult)}`}
                        onMouseEnter={() => {
                          setHoveredAttackType(attackType);
                          setHoveredDefenderType(defenderType);
                        }}
                        onMouseLeave={() => {
                          setHoveredAttackType(null);
                          setHoveredDefenderType(null);
                        }}
                      >
                        {getCellText(attackType, defenderType)}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Legend */}
      <div className="p-4 border-t-2 border-slate-200 bg-slate-50">
        <div className="flex flex-wrap gap-4 items-center justify-center text-xs">
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-green-500 rounded border border-slate-300"></div>
            <span>Super Effective (2×)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-slate-200 rounded border border-slate-300"></div>
            <span>Normal (1×)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-orange-300 rounded border border-slate-300"></div>
            <span>Not Very Effective (½×)</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 bg-gray-200 rounded border border-slate-300"></div>
            <span>Immune (0×)</span>
          </div>
        </div>
      </div>
    </div>
  );
}


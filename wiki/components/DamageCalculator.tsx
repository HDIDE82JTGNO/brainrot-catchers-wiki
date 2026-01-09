"use client";

import React, { useState, useMemo } from 'react';
import { Creature, Move } from '@/types';
import { calculateDamage, calculateDamageScenarios } from '@/lib/damageCalc';
import { TypeBadge } from './TypeBadge';
import { getEffectivenessColor } from '@/lib/typeEffectiveness';

interface DamageCalculatorProps {
  creatures: Creature[];
  moves: Move[];
  className?: string;
}

export function DamageCalculator({ creatures, moves, className = '' }: DamageCalculatorProps) {
  const [selectedAttacker, setSelectedAttacker] = useState<Creature | null>(null);
  const [selectedDefender, setSelectedDefender] = useState<Creature | null>(null);
  const [selectedMove, setSelectedMove] = useState<Move | null>(null);
  const [attackerLevel, setAttackerLevel] = useState(50);
  const [defenderLevel, setDefenderLevel] = useState(50);
  const [attackerAttackStage, setAttackerAttackStage] = useState(0);
  const [defenderDefenseStage, setDefenderDefenseStage] = useState(0);

  // Filter moves available to attacker
  const availableMoves = useMemo(() => {
    if (!selectedAttacker) return [];
    
    const learnsetMoves: string[] = [];
    if (selectedAttacker.Learnset) {
      Object.values(selectedAttacker.Learnset).forEach(moveList => {
        if (Array.isArray(moveList)) {
          learnsetMoves.push(...moveList);
        }
      });
    }
    
    return moves.filter(m => learnsetMoves.includes(m.Name));
  }, [selectedAttacker, moves]);

  // Calculate damage
  const damageResult = useMemo(() => {
    if (!selectedAttacker || !selectedDefender || !selectedMove) {
      return null;
    }

    return calculateDamage({
      attacker: selectedAttacker,
      defender: selectedDefender,
      move: selectedMove,
      attackerLevel,
      defenderLevel,
      attackerAttackStage,
      defenderDefenseStage,
    });
  }, [selectedAttacker, selectedDefender, selectedMove, attackerLevel, defenderLevel, attackerAttackStage, defenderDefenseStage]);

  const critDamageResult = useMemo(() => {
    if (!selectedAttacker || !selectedDefender || !selectedMove) {
      return null;
    }

    return calculateDamage({
      attacker: selectedAttacker,
      defender: selectedDefender,
      move: selectedMove,
      attackerLevel,
      defenderLevel,
      attackerAttackStage,
      defenderDefenseStage,
      isCritical: true,
    });
  }, [selectedAttacker, selectedDefender, selectedMove, attackerLevel, defenderLevel, attackerAttackStage, defenderDefenseStage]);

  return (
    <div className={`bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 ${className}`}>
      <h2 className="text-2xl font-bold text-slate-900 mb-6">Damage Calculator</h2>

      <div className="space-y-6">
        {/* Attacker Selection */}
        <div>
          <label className="block text-sm font-semibold text-slate-700 mb-2">Attacker</label>
          <select
            value={selectedAttacker?.Name || ''}
            onChange={(e) => {
              const creature = creatures.find(c => c.Name === e.target.value);
              setSelectedAttacker(creature || null);
              setSelectedMove(null);
            }}
            className="w-full p-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          >
            <option value="">Select attacker...</option>
            {creatures.map(c => (
              <option key={c.Id} value={c.Name}>{c.Name}</option>
            ))}
          </select>
          {selectedAttacker && (
            <div className="mt-2 flex items-center gap-2">
              <span className="text-xs text-slate-600">Types:</span>
              {selectedAttacker.Types?.map(t => (
                <TypeBadge key={t} type={t} className="scale-75" />
              ))}
            </div>
          )}
        </div>

        {/* Defender Selection */}
        <div>
          <label className="block text-sm font-semibold text-slate-700 mb-2">Defender</label>
          <select
            value={selectedDefender?.Name || ''}
            onChange={(e) => {
              const creature = creatures.find(c => c.Name === e.target.value);
              setSelectedDefender(creature || null);
            }}
            className="w-full p-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
          >
            <option value="">Select defender...</option>
            {creatures.map(c => (
              <option key={c.Id} value={c.Name}>{c.Name}</option>
            ))}
          </select>
          {selectedDefender && (
            <div className="mt-2 flex items-center gap-2">
              <span className="text-xs text-slate-600">Types:</span>
              {selectedDefender.Types?.map(t => (
                <TypeBadge key={t} type={t} className="scale-75" />
              ))}
            </div>
          )}
        </div>

        {/* Move Selection */}
        {selectedAttacker && (
          <div>
            <label className="block text-sm font-semibold text-slate-700 mb-2">Move</label>
            <select
              value={selectedMove?.Name || ''}
              onChange={(e) => {
                const move = moves.find(m => m.Name === e.target.value);
                setSelectedMove(move || null);
              }}
              className="w-full p-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
            >
              <option value="">Select move...</option>
              {availableMoves.map(m => (
                <option key={m.Id} value={m.Name}>
                  {m.Name} ({m.Type}, {m.BasePower || 0} BP)
                </option>
              ))}
            </select>
            {selectedMove && (
              <div className="mt-2 flex items-center gap-2 text-xs text-slate-600">
                <TypeBadge type={selectedMove.Type} className="scale-75" />
                <span>Power: {selectedMove.BasePower || '-'}</span>
                <span>Accuracy: {selectedMove.Accuracy || '-'}%</span>
                <span>Category: {selectedMove.Category}</span>
              </div>
            )}
          </div>
        )}

        {/* Level and Stat Stage Controls */}
        {(selectedAttacker && selectedDefender) && (
          <div className="grid grid-cols-2 gap-4 p-4 bg-slate-50 rounded-lg">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Attacker Level: {attackerLevel}
              </label>
              <input
                type="range"
                min="1"
                max="100"
                value={attackerLevel}
                onChange={(e) => setAttackerLevel(Number(e.target.value))}
                className="w-full"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Defender Level: {defenderLevel}
              </label>
              <input
                type="range"
                min="1"
                max="100"
                value={defenderLevel}
                onChange={(e) => setDefenderLevel(Number(e.target.value))}
                className="w-full"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Attack Stage: {attackerAttackStage > 0 ? '+' : ''}{attackerAttackStage}
              </label>
              <input
                type="range"
                min="-6"
                max="6"
                value={attackerAttackStage}
                onChange={(e) => setAttackerAttackStage(Number(e.target.value))}
                className="w-full"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">
                Defense Stage: {defenderDefenseStage > 0 ? '+' : ''}{defenderDefenseStage}
              </label>
              <input
                type="range"
                min="-6"
                max="6"
                value={defenderDefenseStage}
                onChange={(e) => setDefenderDefenseStage(Number(e.target.value))}
                className="w-full"
              />
            </div>
          </div>
        )}

        {/* Damage Results */}
        {damageResult && selectedMove && (
          <div className="space-y-4">
            <div className="p-4 bg-gradient-to-r from-blue-50 to-blue-100 rounded-lg border-2 border-blue-200">
              <div className="flex items-center justify-between mb-2">
                <h3 className="text-lg font-bold text-slate-900">Damage Range</h3>
                <span className={`px-3 py-1 rounded-full text-sm font-bold ${getEffectivenessColor(damageResult.effectiveness)}`}>
                  {damageResult.effectivenessLabel}
                </span>
              </div>
              
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <div className="text-xs text-slate-600 mb-1">Normal Hit</div>
                  <div className="text-2xl font-black text-slate-900">
                    {damageResult.min} - {damageResult.max}
                  </div>
                  <div className="text-xs text-slate-500">Avg: {damageResult.average}</div>
                </div>
                {critDamageResult && (
                  <div>
                    <div className="text-xs text-slate-600 mb-1">Critical Hit</div>
                    <div className="text-2xl font-black text-green-600">
                      {critDamageResult.min} - {critDamageResult.max}
                    </div>
                    <div className="text-xs text-slate-500">Avg: {critDamageResult.average}</div>
                  </div>
                )}
              </div>

              <div className="mt-4 pt-4 border-t border-blue-200 grid grid-cols-3 gap-4 text-xs">
                <div>
                  <span className="text-slate-600">STAB:</span>
                  <span className="font-bold ml-1">{damageResult.stab === 1.5 ? 'Yes (1.5×)' : 'No'}</span>
                </div>
                <div>
                  <span className="text-slate-600">Effectiveness:</span>
                  <span className="font-bold ml-1">{damageResult.effectiveness}×</span>
                </div>
                <div>
                  <span className="text-slate-600">KO Chance:</span>
                  <span className={`font-bold ml-1 ${damageResult.koChance >= 100 ? 'text-red-600' : damageResult.koChance >= 50 ? 'text-orange-600' : 'text-slate-700'}`}>
                    {damageResult.koChance}%
                  </span>
                </div>
              </div>
            </div>

            {/* Defender HP Bar */}
            {selectedDefender && (
              <div className="p-4 bg-slate-50 rounded-lg">
                <div className="text-xs font-semibold text-slate-700 mb-2">
                  Defender HP: {selectedDefender.BaseStats.HP}
                </div>
                <div className="w-full bg-slate-200 rounded-full h-4 overflow-hidden">
                  <div
                    className="bg-red-500 h-full transition-all duration-300"
                    style={{
                      width: `${Math.min(100, (damageResult.max / selectedDefender.BaseStats.HP) * 100)}%`,
                    }}
                  />
                </div>
                <div className="text-xs text-slate-500 mt-1">
                  Max damage: {damageResult.max} / {selectedDefender.BaseStats.HP} HP
                  {damageResult.max >= selectedDefender.BaseStats.HP && (
                    <span className="text-red-600 font-bold ml-2">✓ Guaranteed KO</span>
                  )}
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}


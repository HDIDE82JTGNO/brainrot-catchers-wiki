"use client";

import React, { useState, useMemo } from 'react';
import { TeamMember, StatBlock } from '@/lib/teamTypes';
import { Move } from '@/types';
import { validateIVs, validateEVs, getTotalEVs } from '@/lib/statCalculator';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';
import { IconX } from '@tabler/icons-react';

const AnimatedDiv = animated.div as any;

interface TeamMemberEditorProps {
  member: TeamMember;
  moves: Move[];
  onSave: (member: TeamMember) => void;
  onCancel: () => void;
}

export function TeamMemberEditor({ member, moves, onSave, onCancel }: TeamMemberEditorProps) {
  const [ivs, setIvs] = useState<StatBlock>(member.ivs);
  const [evs, setEvs] = useState<StatBlock>(member.evs);
  const [selectedMoves, setSelectedMoves] = useState<string[]>(member.moves);
  const [level, setLevel] = useState(member.level);
  const [moveSearch, setMoveSearch] = useState('');

  // Get available moves for this creature
  const availableMoves = useMemo(() => {
    const moveNames: string[] = [];
    if (member.Learnset) {
      Object.values(member.Learnset).forEach(moveList => {
        if (Array.isArray(moveList)) {
          moveNames.push(...moveList);
        }
      });
    }
    return moves.filter(m => moveNames.includes(m.Name));
  }, [member, moves]);

  // Filter moves by search
  const filteredMoves = useMemo(() => {
    if (!moveSearch.trim()) return availableMoves;
    const query = moveSearch.toLowerCase();
    return availableMoves.filter(m => 
      m.Name.toLowerCase().includes(query) ||
      m.Type.toLowerCase().includes(query)
    );
  }, [availableMoves, moveSearch]);

  const totalEVs = getTotalEVs(evs);
  const evsValid = validateEVs(evs);
  const ivsValid = validateIVs(ivs);

  const updateIV = (stat: keyof StatBlock, value: number) => {
    const numValue = Math.max(0, Math.min(31, Math.floor(value) || 0));
    setIvs({ ...ivs, [stat]: numValue });
  };

  const updateEV = (stat: keyof StatBlock, value: number) => {
    const numValue = Math.max(0, Math.min(252, Math.floor(value) || 0));
    const newEvs = { ...evs, [stat]: numValue };
    const newTotal = getTotalEVs(newEvs);
    if (newTotal <= 510) {
      setEvs(newEvs);
    }
  };

  const toggleMove = (moveName: string) => {
    if (selectedMoves.includes(moveName)) {
      setSelectedMoves(selectedMoves.filter(m => m !== moveName));
    } else if (selectedMoves.length < 4) {
      setSelectedMoves([...selectedMoves, moveName]);
    }
  };

  const handleSave = () => {
    const updatedMember: TeamMember = {
      ...member,
      ivs,
      evs,
      moves: selectedMoves,
      level,
    };
    onSave(updatedMember);
  };

  const fadeIn = useSpring({
    from: { opacity: 0, scale: 0.95 },
    to: { opacity: 1, scale: 1 },
    config: getSpringConfig('gentle'),
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <AnimatedDiv
        style={fadeIn}
        className="bg-white dark:bg-slate-800 rounded-2xl border-2 border-slate-200 dark:border-slate-700 shadow-2xl max-w-4xl w-full max-h-[90vh] overflow-y-auto"
      >
        <div className="sticky top-0 bg-white dark:bg-slate-800 border-b-2 border-slate-200 dark:border-slate-700 p-4 flex items-center justify-between z-10">
          <h2 className="text-2xl font-bold text-slate-900 dark:text-slate-100">
            Edit {member.Name}
          </h2>
          <button
            onClick={onCancel}
            className="p-2 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors"
          >
            <IconX className="w-5 h-5 text-slate-600 dark:text-slate-300" />
          </button>
        </div>

        <div className="p-6 space-y-6">
          {/* Level */}
          <div>
            <label className="block text-sm font-semibold text-slate-900 dark:text-slate-100 mb-2">
              Level
            </label>
            <input
              type="number"
              min="1"
              max="100"
              value={level}
              onChange={(e) => setLevel(Math.max(1, Math.min(100, parseInt(e.target.value) || 1)))}
              className="w-full px-4 py-2 border-2 border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
            />
          </div>

          {/* IVs */}
          <div>
            <label className="block text-sm font-semibold text-slate-900 dark:text-slate-100 mb-2">
              Individual Values (IVs) - 0-31
            </label>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              {(Object.keys(ivs) as Array<keyof StatBlock>).map(stat => (
                <div key={stat}>
                  <label className="block text-xs text-slate-600 dark:text-slate-400 mb-1">
                    {stat}
                  </label>
                  <input
                    type="number"
                    min="0"
                    max="31"
                    value={ivs[stat]}
                    onChange={(e) => updateIV(stat, parseInt(e.target.value) || 0)}
                    className="w-full px-3 py-2 border-2 border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
              ))}
            </div>
            {!ivsValid && (
              <p className="text-xs text-red-600 dark:text-red-400 mt-2">
                IVs must be between 0 and 31
              </p>
            )}
          </div>

          {/* EVs */}
          <div>
            <label className="block text-sm font-semibold text-slate-900 dark:text-slate-100 mb-2">
              Effort Values (EVs) - 0-252 per stat, 510 total
              <span className={`ml-2 ${totalEVs > 510 ? 'text-red-600 dark:text-red-400' : 'text-slate-600 dark:text-slate-400'}`}>
                ({totalEVs}/510)
              </span>
            </label>
            <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
              {(Object.keys(evs) as Array<keyof StatBlock>).map(stat => (
                <div key={stat}>
                  <label className="block text-xs text-slate-600 dark:text-slate-400 mb-1">
                    {stat}
                  </label>
                  <input
                    type="number"
                    min="0"
                    max="252"
                    value={evs[stat]}
                    onChange={(e) => updateEV(stat, parseInt(e.target.value) || 0)}
                    className="w-full px-3 py-2 border-2 border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
              ))}
            </div>
            {!evsValid && (
              <p className="text-xs text-red-600 dark:text-red-400 mt-2">
                EVs must be between 0-252 per stat and total must not exceed 510
              </p>
            )}
          </div>

          {/* Moves */}
          <div>
            <label className="block text-sm font-semibold text-slate-900 dark:text-slate-100 mb-2">
              Moves ({selectedMoves.length}/4)
            </label>
            <input
              type="text"
              placeholder="Search moves..."
              value={moveSearch}
              onChange={(e) => setMoveSearch(e.target.value)}
              className="w-full px-4 py-2 border-2 border-slate-300 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 mb-3 focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
            />
            <div className="max-h-48 overflow-y-auto border-2 border-slate-200 dark:border-slate-700 rounded-lg p-2">
              {filteredMoves.length === 0 ? (
                <p className="text-sm text-slate-500 dark:text-slate-400 text-center py-4">
                  No moves found
                </p>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                  {filteredMoves.map(move => {
                    const isSelected = selectedMoves.includes(move.Name);
                    return (
                      <button
                        key={move.Id}
                        onClick={() => toggleMove(move.Name)}
                        disabled={!isSelected && selectedMoves.length >= 4}
                        className={`p-3 rounded-lg border-2 text-left transition-all ${
                          isSelected
                            ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300'
                            : selectedMoves.length >= 4
                            ? 'border-slate-200 dark:border-slate-700 opacity-50 cursor-not-allowed'
                            : 'border-slate-200 dark:border-slate-700 hover:border-blue-400 dark:hover:border-blue-500 hover:bg-slate-50 dark:hover:bg-slate-700'
                        }`}
                      >
                        <div className="font-semibold text-sm text-slate-900 dark:text-slate-100">
                          {move.Name}
                        </div>
                        <div className="text-xs text-slate-600 dark:text-slate-400 mt-1">
                          {move.Type} • Power: {move.BasePower || '-'} • Acc: {move.Accuracy || '-'}%
                        </div>
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>

          {/* Actions */}
          <div className="flex gap-4 pt-4 border-t-2 border-slate-200 dark:border-slate-700">
            <button
              onClick={onCancel}
              className="flex-1 px-4 py-2 border-2 border-slate-300 dark:border-slate-600 rounded-lg hover:bg-slate-50 dark:hover:bg-slate-700 transition-colors font-medium text-slate-700 dark:text-slate-300"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={!ivsValid || !evsValid}
              className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </div>
      </AnimatedDiv>
    </div>
  );
}


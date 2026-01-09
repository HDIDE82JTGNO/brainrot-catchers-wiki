"use client";

import React, { useState, useMemo } from 'react';
import { Creature, Move } from '@/types';
import { TypeBadge } from './TypeBadge';
import { analyzeMoveCoverage, getRecommendedMoves, CoverageAnalysis } from '@/lib/coverageAnalysis';
import { getEffectivenessColor } from '@/lib/typeEffectiveness';

interface MoveCoverageAnalyzerProps {
  creatures: Creature[];
  moves: Move[];
  className?: string;
}

export function MoveCoverageAnalyzer({ creatures, moves, className = '' }: MoveCoverageAnalyzerProps) {
  const [selectedCreature, setSelectedCreature] = useState<Creature | null>(null);
  const [selectedMoves, setSelectedMoves] = useState<Move[]>([]);
  const [mode, setMode] = useState<'creature' | 'manual'>('creature');

  // Get moves for selected creature
  const creatureMoves = useMemo(() => {
    if (!selectedCreature || !selectedCreature.Learnset) return [];

    const moveNames: string[] = [];
    Object.values(selectedCreature.Learnset).forEach(moveList => {
      if (Array.isArray(moveList)) {
        moveNames.push(...moveList);
      }
    });

    return moves.filter(m => moveNames.includes(m.Name));
  }, [selectedCreature, moves]);

  // Analyze coverage
  const coverageAnalysis = useMemo(() => {
    const movesToAnalyze = mode === 'creature' ? creatureMoves : selectedMoves;
    if (movesToAnalyze.length === 0) return null;
    return analyzeMoveCoverage(movesToAnalyze);
  }, [mode, creatureMoves, selectedMoves]);

  // Get recommendations
  const recommendations = useMemo(() => {
    if (!coverageAnalysis || !selectedCreature) return [];
    const movesToAnalyze = mode === 'creature' ? creatureMoves : selectedMoves;
    return getRecommendedMoves(movesToAnalyze, moves);
  }, [coverageAnalysis, mode, creatureMoves, selectedMoves, moves, selectedCreature]);

  const addMove = (move: Move) => {
    if (selectedMoves.some(m => m.Id === move.Id)) return;
    setSelectedMoves([...selectedMoves, move]);
  };

  const removeMove = (moveId: string) => {
    setSelectedMoves(selectedMoves.filter(m => m.Id !== moveId));
  };

  return (
    <div className={`bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6 ${className}`}>
      <h2 className="text-2xl font-bold text-slate-900 mb-6">Move Coverage Analyzer</h2>

      <div className="space-y-6">
        {/* Mode Selection */}
        <div className="flex gap-2">
          <button
            onClick={() => {
              setMode('creature');
              setSelectedMoves([]);
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
              setMode('manual');
              setSelectedCreature(null);
            }}
            className={`px-4 py-2 rounded-lg font-medium transition-all ${
              mode === 'manual'
                ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
            }`}
          >
            Manual Selection
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
            {selectedCreature && creatureMoves.length > 0 && (
              <div className="mt-2">
                <div className="text-xs text-slate-600 mb-1">Available moves ({creatureMoves.length}):</div>
                <div className="flex flex-wrap gap-1">
                  {creatureMoves.slice(0, 20).map(m => (
                    <span
                      key={m.Id}
                      className="text-xs px-2 py-1 bg-slate-100 text-slate-700 rounded"
                    >
                      {m.Name}
                    </span>
                  ))}
                  {creatureMoves.length > 20 && (
                    <span className="text-xs px-2 py-1 text-slate-500">
                      +{creatureMoves.length - 20} more
                    </span>
                  )}
                </div>
              </div>
            )}
          </div>
        )}

        {/* Manual Move Selection */}
        {mode === 'manual' && (
          <div>
            <label className="block text-sm font-semibold text-slate-700 mb-2">Select Moves</label>
            <div className="flex flex-wrap gap-2 mb-2">
              {selectedMoves.map(move => (
                <div
                  key={move.Id}
                  className="flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-700 rounded border border-blue-300"
                >
                  <TypeBadge type={move.Type} className="scale-75" />
                  <span className="text-sm font-medium">{move.Name}</span>
                  <button
                    onClick={() => removeMove(move.Id)}
                    className="text-red-600 hover:text-red-700 font-bold ml-1"
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
            <input
              type="text"
              placeholder="Search moves..."
              className="w-full p-2 border border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  const query = (e.target as HTMLInputElement).value.toLowerCase();
                  const foundMove = moves.find(m => 
                    m.Name.toLowerCase() === query ||
                    m.Name.toLowerCase().includes(query)
                  );
                  if (foundMove && !selectedMoves.some(m => m.Id === foundMove.Id)) {
                    addMove(foundMove);
                    (e.target as HTMLInputElement).value = '';
                  }
                }
              }}
            />
            <div className="text-xs text-slate-500 mt-1">
              Type a move name and press Enter to add it
            </div>
          </div>
        )}

        {/* Coverage Analysis Results */}
        {coverageAnalysis && (
          <div className="space-y-4">
            {/* Coverage Summary */}
            <div className="p-4 bg-gradient-to-r from-blue-50 to-blue-100 rounded-lg border-2 border-blue-200">
              <div className="flex items-center justify-between mb-2">
                <h3 className="text-lg font-bold text-slate-900">Coverage Summary</h3>
                <div className="text-2xl font-black text-blue-600">
                  {coverageAnalysis.coveragePercentage.toFixed(1)}%
                </div>
              </div>
              <div className="grid grid-cols-4 gap-2 text-xs">
                <div>
                  <div className="font-bold text-green-700">Super Effective</div>
                  <div>{coverageAnalysis.superEffective.length} types</div>
                </div>
                <div>
                  <div className="font-bold text-slate-700">Normal</div>
                  <div>{coverageAnalysis.normal.length} types</div>
                </div>
                <div>
                  <div className="font-bold text-orange-700">Not Very Effective</div>
                  <div>{coverageAnalysis.notVeryEffective.length} types</div>
                </div>
                <div>
                  <div className="font-bold text-gray-700">Immune</div>
                  <div>{coverageAnalysis.immune.length} types</div>
                </div>
              </div>
            </div>

            {/* Coverage Breakdown */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Super Effective */}
              {coverageAnalysis.superEffective.length > 0 && (
                <div className="p-4 rounded-xl border-2 border-green-200 bg-green-50">
                  <h4 className="text-sm font-bold text-green-800 uppercase mb-2">
                    Super Effective ({coverageAnalysis.superEffective.length})
                  </h4>
                  <div className="flex flex-wrap gap-1.5">
                    {coverageAnalysis.superEffective.map(result => (
                      <div key={result.type} className="flex items-center gap-1">
                        <TypeBadge type={result.type} className="scale-75" />
                        <span className="text-xs font-bold text-green-700">
                          {result.effectiveness === 4 ? '4×' : '2×'}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Coverage Gaps */}
              {coverageAnalysis.gaps.length > 0 && (
                <div className="p-4 rounded-xl border-2 border-red-200 bg-red-50">
                  <h4 className="text-sm font-bold text-red-800 uppercase mb-2">
                    Coverage Gaps ({coverageAnalysis.gaps.length})
                  </h4>
                  <div className="flex flex-wrap gap-1.5">
                    {coverageAnalysis.gaps.map(type => (
                      <TypeBadge key={type} type={type} className="scale-75" />
                    ))}
                  </div>
                </div>
              )}
            </div>

            {/* Recommendations */}
            {recommendations.length > 0 && (
              <div className="p-4 rounded-xl border-2 border-blue-200 bg-blue-50">
                <h4 className="text-sm font-bold text-blue-800 uppercase mb-2">
                  Recommended Moves
                </h4>
                <div className="space-y-2">
                  {recommendations.slice(0, 5).map(move => (
                    <div
                      key={move.Id}
                      className="flex items-center gap-2 p-2 bg-white rounded border border-blue-200"
                    >
                      <TypeBadge type={move.Type} className="scale-75" />
                      <span className="font-medium text-slate-900">{move.Name}</span>
                      <span className="text-xs text-slate-500">
                        {move.BasePower || '-'} BP
                      </span>
                      {!selectedMoves.some(m => m.Id === move.Id) && (
                        <button
                          onClick={() => addMove(move)}
                          className="ml-auto text-xs text-blue-600 hover:text-blue-700 underline"
                        >
                          Add
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Full Coverage Table */}
            <div className="overflow-x-auto">
              <table className="min-w-full">
                <thead>
                  <tr className="bg-slate-100">
                    <th className="px-4 py-2 text-left text-sm font-semibold text-slate-700">Type</th>
                    <th className="px-4 py-2 text-center text-sm font-semibold text-slate-700">Effectiveness</th>
                    <th className="px-4 py-2 text-left text-sm font-semibold text-slate-700">Best Move</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {[...coverageAnalysis.superEffective, ...coverageAnalysis.normal, ...coverageAnalysis.notVeryEffective, ...coverageAnalysis.immune]
                    .map(result => (
                      <tr key={result.type} className="hover:bg-slate-50">
                        <td className="px-4 py-2">
                          <TypeBadge type={result.type} className="scale-90" />
                        </td>
                        <td className="px-4 py-2 text-center">
                          <span className={`px-2 py-1 rounded text-xs font-bold ${getEffectivenessColor(result.effectiveness)}`}>
                            {result.effectiveness === 0 ? 'Immune' :
                             result.effectiveness >= 4 ? '4×' :
                             result.effectiveness >= 2 ? '2×' :
                             result.effectiveness === 1 ? '1×' :
                             result.effectiveness === 0.5 ? '½×' :
                             result.effectiveness === 0.25 ? '¼×' :
                             `${result.effectiveness}×`}
                          </span>
                        </td>
                        <td className="px-4 py-2">
                          {result.bestMove ? (
                            <div className="flex items-center gap-2">
                              <TypeBadge type={result.bestMove.Type} className="scale-75" />
                              <span className="text-sm">{result.bestMove.Name}</span>
                            </div>
                          ) : (
                            <span className="text-slate-400 text-sm">None</span>
                          )}
                        </td>
                      </tr>
                    ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {!coverageAnalysis && (
          <div className="p-8 text-center text-slate-500">
            {mode === 'creature'
              ? 'Select a creature to analyze its move coverage'
              : 'Select moves to analyze coverage'}
          </div>
        )}
      </div>
    </div>
  );
}


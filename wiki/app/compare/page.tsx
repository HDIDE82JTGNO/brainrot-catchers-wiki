"use client";

import React, { useState, useMemo, useEffect } from 'react';
import { ComparisonView } from '@/components/ComparisonView';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import { Creature, Move } from '@/types';
import { getSpringConfig } from '@/lib/springConfigs';
import { useSpring, animated } from '@react-spring/web';
import Link from 'next/link';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];

const AnimatedDiv = animated.div as any;
const MAX_COMPARISONS = 6;

export default function ComparePage() {
  const [selectedCreatures, setSelectedCreatures] = useState<Creature[]>([]);
  const [shinyCreatures, setShinyCreatures] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');

  // Filter creatures for selection
  const filteredCreatures = useMemo(() => {
    if (!searchQuery.trim()) return creatures.slice(0, 50); // Show first 50 by default
    
    const queryLower = searchQuery.toLowerCase();
    return creatures.filter(c =>
      c.Name.toLowerCase().includes(queryLower) ||
      c.Description?.toLowerCase().includes(queryLower) ||
      c.Types?.some(t => t.toLowerCase().includes(queryLower))
    ).slice(0, 50);
  }, [searchQuery]);

  const addCreature = (creature: Creature) => {
    if (selectedCreatures.length >= MAX_COMPARISONS) return;
    if (selectedCreatures.some(c => c.Id === creature.Id)) return;
    setSelectedCreatures([...selectedCreatures, creature]);
  };

  const removeCreature = (index: number) => {
    setSelectedCreatures(selectedCreatures.filter((_, i) => i !== index));
  };

  const clearAll = () => {
    setSelectedCreatures([]);
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
          Creature Comparison
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Compare up to {MAX_COMPARISONS} creatures side-by-side. Stats, types, moves, and more.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Selection Panel */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-4">
            <h2 className="text-xl font-bold text-slate-900">
              Selected Creatures ({selectedCreatures.length}/{MAX_COMPARISONS})
            </h2>
            {selectedCreatures.length > 0 && (
              <button
                onClick={clearAll}
                className="px-4 py-2 bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition-colors font-medium text-sm"
              >
                Clear All
              </button>
            )}
          </div>

          {/* Selected Creatures */}
          {selectedCreatures.length > 0 && (
            <div className="flex flex-wrap gap-2 mb-4 p-4 bg-slate-50 rounded-lg">
              {selectedCreatures.map((creature, idx) => (
                <div
                  key={creature.Id}
                  className="flex items-center gap-2 px-3 py-2 bg-white border-2 border-slate-200 rounded-lg"
                >
                  <span className="font-medium text-slate-900">{creature.Name}</span>
                  <button
                    onClick={() => removeCreature(idx)}
                    className="text-red-600 hover:text-red-700 font-bold"
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          )}

          {/* Search */}
          <div className="relative mb-4">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <svg className="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
              </svg>
            </div>
            <input
              type="text"
              placeholder="Search creatures to add..."
              className="w-full pl-10 pr-4 py-2 border-2 border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          {/* Creature Grid */}
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3 max-h-96 overflow-y-auto">
            {filteredCreatures.map(creature => {
              const isSelected = selectedCreatures.some(c => c.Id === creature.Id);
              const isShiny = shinyCreatures.has(creature.Name);
              
              return (
                <button
                  key={creature.Id}
                  onClick={() => addCreature(creature)}
                  disabled={isSelected || selectedCreatures.length >= MAX_COMPARISONS}
                  className={`p-3 border-2 rounded-lg transition-all text-left ${
                    isSelected
                      ? 'border-blue-500 bg-blue-50 opacity-50 cursor-not-allowed'
                      : selectedCreatures.length >= MAX_COMPARISONS
                      ? 'border-slate-200 opacity-50 cursor-not-allowed'
                      : 'border-slate-200 hover:border-blue-400 hover:shadow-md'
                  }`}
                >
                  <div className="text-xs font-medium text-slate-600 mb-1">
                    #{String(creature.DexNumber).padStart(3, '0')}
                  </div>
                  <div className="font-bold text-slate-900 text-sm mb-1">{creature.Name}</div>
                  <div className="flex gap-1 flex-wrap">
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

        {/* Comparison View */}
        {selectedCreatures.length > 0 && (
          <ComparisonView
            creatures={selectedCreatures}
            moves={moves}
            shinyCreatures={shinyCreatures}
            onRemove={removeCreature}
          />
        )}

        {selectedCreatures.length === 0 && (
          <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-12 text-center">
            <p className="text-slate-500 mb-4">No creatures selected for comparison</p>
            <p className="text-sm text-slate-400">Search and select creatures above to compare them</p>
          </div>
        )}
      </AnimatedDiv>
    </div>
  );
}


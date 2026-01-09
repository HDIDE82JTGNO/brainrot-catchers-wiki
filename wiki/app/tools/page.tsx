"use client";

import React, { useState, useMemo } from 'react';
import { TypeChart } from '@/components/TypeChart';
import { TypeBadge } from '@/components/TypeBadge';
import { DamageCalculator } from '@/components/DamageCalculator';
import { WeaknessCalculator } from '@/components/WeaknessCalculator';
import { MoveCoverageAnalyzer } from '@/components/MoveCoverageAnalyzer';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import { Creature, Move } from '@/types';
import { getSpringConfig } from '@/lib/springConfigs';
import { useSpring, animated } from '@react-spring/web';
import { getAllTypes, getDefensiveEffectiveness, getWeaknesses, getResistances, getImmunities } from '@/lib/typeEffectiveness';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];

const AnimatedDiv = animated.div as any;

type ToolTab = 'type-chart' | 'damage' | 'weakness' | 'coverage' | 'random';

export default function ToolsPage() {
  const [activeTab, setActiveTab] = useState<ToolTab>('type-chart');
  const [randomCreature, setRandomCreature] = useState<Creature | null>(null);
  const [randomMove, setRandomMove] = useState<Move | null>(null);
  const [selectedDefenderTypes, setSelectedDefenderTypes] = useState<string[]>([]);
  const allTypes = getAllTypes();

  const defensiveEffectiveness = useMemo(() => {
    if (selectedDefenderTypes.length === 0) return null;
    return getDefensiveEffectiveness(selectedDefenderTypes);
  }, [selectedDefenderTypes]);

  const weaknesses = useMemo(() => {
    if (selectedDefenderTypes.length === 0) return [];
    return getWeaknesses(selectedDefenderTypes);
  }, [selectedDefenderTypes]);

  const resistances = useMemo(() => {
    if (selectedDefenderTypes.length === 0) return [];
    return getResistances(selectedDefenderTypes);
  }, [selectedDefenderTypes]);

  const immunities = useMemo(() => {
    if (selectedDefenderTypes.length === 0) return [];
    return getImmunities(selectedDefenderTypes);
  }, [selectedDefenderTypes]);

  const toggleDefenderType = (type: string) => {
    setSelectedDefenderTypes(prev => {
      if (prev.includes(type)) {
        return prev.filter(t => t !== type);
      }
      if (prev.length < 2) {
        return [...prev, type];
      }
      return prev;
    });
  };

  const clearSelection = () => {
    setSelectedDefenderTypes([]);
  };

  const generateRandomCreature = () => {
    const random = creatures[Math.floor(Math.random() * creatures.length)];
    setRandomCreature(random);
  };

  const generateRandomMove = () => {
    const random = moves[Math.floor(Math.random() * moves.length)];
    setRandomMove(random);
  };

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const tabs = [
    { id: 'type-chart' as ToolTab, label: 'Type Chart', icon: '📊' },
    { id: 'damage' as ToolTab, label: 'Damage Calculator', icon: '⚔️' },
    { id: 'weakness' as ToolTab, label: 'Weakness Calculator', icon: '🛡️' },
    { id: 'coverage' as ToolTab, label: 'Move Coverage', icon: '🎯' },
    { id: 'random' as ToolTab, label: 'Random Generator', icon: '🎲' },
  ];

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Tools
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Interactive calculators and analyzers for type effectiveness, damage, weaknesses, and more.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Tab Navigation */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-4">
          <div className="flex flex-wrap gap-2">
            {tabs.map(tab => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2 rounded-lg font-medium transition-all flex items-center gap-2 ${
                  activeTab === tab.id
                    ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                    : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
                }`}
              >
                <span>{tab.icon}</span>
                <span>{tab.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Tab Content */}
        <div>
          {activeTab === 'type-chart' && (
            <div className="space-y-6">
              {/* Defender Type Selector */}
              <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
                <h2 className="text-xl font-bold text-slate-900 mb-4">Select Defender Types (up to 2)</h2>
                <div className="flex flex-wrap gap-2 mb-4">
                  {allTypes.map(type => (
                    <button
                      key={type}
                      onClick={() => toggleDefenderType(type)}
                      className={`transition-all ${
                        selectedDefenderTypes.includes(type)
                          ? 'ring-2 ring-blue-500 ring-offset-2 scale-105'
                          : 'opacity-70 hover:opacity-100 hover:scale-105'
                      }`}
                    >
                      <TypeBadge type={type} />
                    </button>
                  ))}
                </div>
                {selectedDefenderTypes.length > 0 && (
                  <div className="flex items-center gap-4">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-slate-700">Selected:</span>
                      {selectedDefenderTypes.map(type => (
                        <TypeBadge key={type} type={type} />
                      ))}
                    </div>
                    <button
                      onClick={clearSelection}
                      className="text-sm text-red-600 hover:text-red-700 font-medium underline"
                    >
                      Clear
                    </button>
                  </div>
                )}
              </div>

              {/* Defensive Analysis */}
              {selectedDefenderTypes.length > 0 && (
                <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
                  <h2 className="text-xl font-bold text-slate-900 mb-4">
                    Defensive Analysis: {selectedDefenderTypes.join(' / ')}
                  </h2>
                  <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                    {weaknesses.length > 0 && (
                      <div className="p-4 rounded-xl border-2 border-red-200 bg-red-50">
                        <h3 className="text-sm font-bold text-red-800 uppercase mb-2">
                          Weaknesses ({weaknesses.length})
                        </h3>
                        <div className="flex flex-wrap gap-1.5">
                          {weaknesses.map(type => {
                            const mult = defensiveEffectiveness?.[type] ?? 1;
                            return (
                              <div key={type} className="flex items-center gap-1">
                                <TypeBadge type={type} className="scale-90" />
                                <span className="text-xs font-bold text-red-700">
                                  {mult === 4 ? '4×' : '2×'}
                                </span>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    )}

                    {resistances.length > 0 && (
                      <div className="p-4 rounded-xl border-2 border-orange-200 bg-orange-50">
                        <h3 className="text-sm font-bold text-orange-800 uppercase mb-2">
                          Resistances ({resistances.length})
                        </h3>
                        <div className="flex flex-wrap gap-1.5">
                          {resistances.map(type => {
                            const mult = defensiveEffectiveness?.[type] ?? 1;
                            return (
                              <div key={type} className="flex items-center gap-1">
                                <TypeBadge type={type} className="scale-90" />
                                <span className="text-xs font-bold text-orange-700">
                                  {mult === 0.25 ? '¼×' : '½×'}
                                </span>
                              </div>
                            );
                          })}
                        </div>
                      </div>
                    )}

                    {immunities.length > 0 && (
                      <div className="p-4 rounded-xl border-2 border-gray-200 bg-gray-50">
                        <h3 className="text-sm font-bold text-gray-800 uppercase mb-2">
                          Immunities ({immunities.length})
                        </h3>
                        <div className="flex flex-wrap gap-1.5">
                          {immunities.map(type => (
                            <TypeBadge key={type} type={type} className="scale-90" />
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Type Chart */}
              <TypeChart 
                highlightDefender={selectedDefenderTypes.length > 0 ? selectedDefenderTypes : undefined}
                onTypeClick={toggleDefenderType}
              />
            </div>
          )}

          {activeTab === 'damage' && (
            <DamageCalculator creatures={creatures} moves={moves} />
          )}

          {activeTab === 'weakness' && (
            <WeaknessCalculator creatures={creatures} />
          )}

          {activeTab === 'coverage' && (
            <MoveCoverageAnalyzer creatures={creatures} moves={moves} />
          )}

          {activeTab === 'random' && (
            <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
              <h2 className="text-2xl font-bold text-slate-900 mb-6">Random Generator</h2>
              <div className="space-y-6">
                <div className="flex flex-wrap gap-4 justify-center">
                  <button
                    onClick={generateRandomCreature}
                    className="px-6 py-3 bg-blue-100 text-blue-700 rounded-lg hover:bg-blue-200 transition-colors font-bold text-lg border-2 border-blue-300"
                  >
                    🎲 Random Creature
                  </button>
                  <button
                    onClick={generateRandomMove}
                    className="px-6 py-3 bg-red-100 text-red-700 rounded-lg hover:bg-red-200 transition-colors font-bold text-lg border-2 border-red-300"
                  >
                    🎲 Random Move
                  </button>
                </div>

                {randomCreature && (
                  <div className="p-6 bg-blue-50 rounded-lg border-2 border-blue-200">
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="text-2xl font-bold text-slate-900">{randomCreature.Name}</h3>
                      <a
                        href={`/creatures/${encodeURIComponent(randomCreature.Name)}`}
                        className="text-blue-600 hover:text-blue-700 underline text-sm"
                      >
                        View Details →
                      </a>
                    </div>
                    <p className="text-slate-600 mb-3">{randomCreature.Description}</p>
                    <div className="flex gap-2">
                      {randomCreature.Types?.map(t => (
                        <TypeBadge key={t} type={t} />
                      ))}
                    </div>
                  </div>
                )}

                {randomMove && (
                  <div className="p-6 bg-red-50 rounded-lg border-2 border-red-200">
                    <div className="flex items-center justify-between mb-3">
                      <h3 className="text-2xl font-bold text-slate-900">{randomMove.Name}</h3>
                      <a
                        href="/moves"
                        className="text-red-600 hover:text-red-700 underline text-sm"
                      >
                        View All Moves →
                      </a>
                    </div>
                    <p className="text-slate-600 mb-3">{randomMove.Description}</p>
                    <div className="flex items-center gap-3">
                      <TypeBadge type={randomMove.Type} />
                      <span className="text-sm text-slate-600">
                        {randomMove.BasePower || '-'} BP | {randomMove.Accuracy || '-'}% Acc | {randomMove.Category}
                      </span>
                    </div>
                  </div>
                )}

                {!randomCreature && !randomMove && (
                  <div className="p-8 text-center text-slate-500">
                    <p>Click a button above to generate something random!</p>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      </AnimatedDiv>
    </div>
  );
}


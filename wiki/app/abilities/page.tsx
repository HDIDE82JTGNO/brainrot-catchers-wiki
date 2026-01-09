"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import abilitiesData from '../../data/abilities.json';
import creaturesData from '../../data/creatures.json';
import { Ability, Creature } from '@/types';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';
import Link from 'next/link';

const abilities = abilitiesData as unknown as Ability[];
const creatures = creaturesData as unknown as Creature[];

const AnimatedDiv = animated.div as any;

// Build creature map for each ability
const abilityCreatureMap = new Map<string, Creature[]>();
creatures.forEach(creature => {
  if (creature.Abilities && Array.isArray(creature.Abilities)) {
    creature.Abilities.forEach(abilityEntry => {
      if (!abilityCreatureMap.has(abilityEntry.Name)) {
        abilityCreatureMap.set(abilityEntry.Name, []);
      }
      abilityCreatureMap.get(abilityEntry.Name)!.push(creature);
    });
  }
});

// Get unique trigger types
const TRIGGER_TYPES = Array.from(new Set(abilities.map(a => a.TriggerType))).sort();

type SortOption = 'name-asc' | 'name-desc' | 'trigger-type';

export default function AbilitiesPage() {
  const [search, setSearch] = useState('');
  const [selectedTriggerTypes, setSelectedTriggerTypes] = useState<string[]>([]);
  const [sortBy, setSortBy] = useState<SortOption>('name-asc');

  const filteredAbilities = useMemo(() => {
    let result = abilities.filter(ability => {
      const matchesSearch = !search || 
        ability.Name.toLowerCase().includes(search.toLowerCase()) ||
        ability.Description.toLowerCase().includes(search.toLowerCase());
      
      const matchesTriggerType = selectedTriggerTypes.length === 0 ||
        selectedTriggerTypes.includes(ability.TriggerType);
      
      return matchesSearch && matchesTriggerType;
    });

    // Apply sorting
    result.sort((a, b) => {
      switch (sortBy) {
        case 'name-asc':
          return a.Name.localeCompare(b.Name);
        case 'name-desc':
          return b.Name.localeCompare(a.Name);
        case 'trigger-type':
          return a.TriggerType.localeCompare(b.TriggerType) || a.Name.localeCompare(b.Name);
        default:
          return 0;
      }
    });

    return result;
  }, [search, selectedTriggerTypes, sortBy]);

  const toggleTriggerType = (type: string) => {
    setSelectedTriggerTypes(prev =>
      prev.includes(type)
        ? prev.filter(t => t !== type)
        : [...prev, type]
    );
  };

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(filteredAbilities.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: { opacity: 1, transform: 'translateY(0px) scale(1)' },
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Abilities
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Complete database of all creature abilities with descriptions and effects.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Search and Filters */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="flex flex-col lg:flex-row gap-4 mb-4">
            {/* Search */}
            <div className="relative flex-1">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <svg className="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
                </svg>
              </div>
              <input
                type="text"
                placeholder="Search abilities..."
                className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>

            {/* Sort */}
            <div className="relative">
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as SortOption)}
                className="w-full lg:w-48 appearance-none pl-4 pr-10 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none bg-white text-slate-700 cursor-pointer"
              >
                <option value="name-asc">Name (A-Z)</option>
                <option value="name-desc">Name (Z-A)</option>
                <option value="trigger-type">Trigger Type</option>
              </select>
              <div className="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none text-slate-500">
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </div>
            </div>
          </div>

          {/* Trigger Type Filters */}
          <div>
            <label className="block text-sm font-semibold text-slate-700 mb-2">Trigger Types</label>
            <div className="flex flex-wrap gap-2">
              {TRIGGER_TYPES.map(type => (
                <button
                  key={type}
                  onClick={() => toggleTriggerType(type)}
                  className={`px-3 py-1.5 rounded-lg text-sm font-medium border-2 transition-all ${
                    selectedTriggerTypes.includes(type)
                      ? 'bg-blue-100 text-blue-700 border-blue-300'
                      : 'bg-white text-slate-600 border-slate-300 hover:border-blue-300'
                  }`}
                >
                  {type}
                </button>
              ))}
            </div>
            {selectedTriggerTypes.length > 0 && (
              <button
                onClick={() => setSelectedTriggerTypes([])}
                className="mt-2 text-sm text-red-600 hover:text-red-700 font-medium underline"
              >
                Clear Filters
              </button>
            )}
          </div>
        </div>

        {/* Abilities List */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">
            Abilities ({filteredAbilities.length} of {abilities.length})
          </h2>
          
          {filteredAbilities.length === 0 ? (
            <EmptyState 
              message={`No abilities found matching "${search}"${selectedTriggerTypes.length > 0 ? ' with selected trigger types' : ''}`}
              icon="✨"
            />
          ) : (
            <div className="space-y-4">
              {trail.map((style, idx) => {
                const ability = filteredAbilities[idx];
                if (!ability) return null;
                
                const creaturesWithAbility = abilityCreatureMap.get(ability.Name) || [];
                
                return (
                  <AnimatedDiv key={ability.Id} style={style}>
                    <div className="border-2 border-slate-200 rounded-xl p-5 hover:border-blue-300 transition-all">
                      <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
                        <div className="flex-1">
                          <div className="flex items-center gap-3 mb-2">
                            <h3 className="text-2xl font-bold text-slate-900">{ability.Name}</h3>
                            <span className="px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-bold">
                              {ability.TriggerType}
                            </span>
                          </div>
                          <p className="text-slate-600 mb-3">{ability.Description}</p>
                          
                          {/* Ability Details */}
                          <div className="flex flex-wrap gap-4 text-sm text-slate-600">
                            {ability.Multiplier && (
                              <span>
                                <strong>Multiplier:</strong> {ability.Multiplier}x
                              </span>
                            )}
                            {ability.TypeBoost && (
                              <span>
                                <strong>Type Boost:</strong> {ability.TypeBoost}
                              </span>
                            )}
                            {ability.HPThreshold && (
                              <span>
                                <strong>HP Threshold:</strong> {ability.HPThreshold}%
                              </span>
                            )}
                            {ability.WeatherCondition && (
                              <span>
                                <strong>Weather:</strong> {ability.WeatherCondition}
                              </span>
                            )}
                          </div>
                        </div>
                        
                        {/* Creatures with this ability */}
                        <div className="md:w-64">
                          <div className="text-sm font-semibold text-slate-700 mb-2">
                            Creatures ({creaturesWithAbility.length})
                          </div>
                          <div className="flex flex-wrap gap-2">
                            {creaturesWithAbility.slice(0, 5).map(creature => (
                              <Link
                                key={creature.Id}
                                href={`/creatures/${encodeURIComponent(creature.Name)}`}
                                className="px-2 py-1 bg-slate-100 text-slate-700 rounded text-xs hover:bg-blue-100 hover:text-blue-700 transition-colors"
                              >
                                {creature.Name}
                              </Link>
                            ))}
                            {creaturesWithAbility.length > 5 && (
                              <span className="px-2 py-1 text-slate-500 text-xs">
                                +{creaturesWithAbility.length - 5} more
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                    </div>
                  </AnimatedDiv>
                );
              })}
            </div>
          )}
        </div>
      </AnimatedDiv>
    </div>
  );
}


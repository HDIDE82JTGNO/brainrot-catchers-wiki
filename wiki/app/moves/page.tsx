"use client";

import React, { useState, useMemo } from 'react';
import { useTransition, useSpring, animated } from '@react-spring/web';
import movesData from '../../data/moves.json';
import typesData from '../../data/types.json';
import creaturesData from '../../data/creatures.json';
import { Move, Creature } from '@/types';
import { MoveTable } from '@/components/MoveTable';
import { TypeBadge } from '@/components/TypeBadge';
import { MoveFilters, INITIAL_FILTERS, applyFilters, getActiveFilterCount } from '@/lib/moveFilters';
import { getSpringConfig } from '@/lib/springConfigs';

const moves = movesData as unknown as Move[];
const creatures = creaturesData as unknown as Creature[];
const ALL_TYPES = Object.keys(typesData).sort();
const CATEGORIES = ['Physical', 'Special', 'Status'];

// Type assertion for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;

type SortOption = 'name-asc' | 'name-desc' | 'power-desc' | 'power-asc' | 'accuracy-desc' | 'accuracy-asc' | 'priority-desc' | 'priority-asc' | 'type-asc' | 'category-asc';

export default function MovesPage() {
  const [filters, setFilters] = useState<MoveFilters>(INITIAL_FILTERS);
  const [sortBy, setSortBy] = useState<SortOption>('name-asc');
  const [viewMode, setViewMode] = useState<'table' | 'compact'>('table');
  const [showFilters, setShowFilters] = useState(false);

  // Build move learnset map (which creatures learn each move) - memoized to avoid recomputation
  const moveLearnsetMap = useMemo(() => {
    const map = new Map<string, Creature[]>();
    creatures.forEach(creature => {
      if (!creature.Learnset) return;
      Object.values(creature.Learnset).forEach(moveList => {
        if (Array.isArray(moveList)) {
          moveList.forEach(moveName => {
            if (!map.has(moveName)) {
              map.set(moveName, []);
            }
            map.get(moveName)!.push(creature);
          });
        }
      });
    });
    return map;
  }, []); // Empty deps - only compute once

  const activeFilterCount = useMemo(() => getActiveFilterCount(filters), [filters]);

  const filteredMoves = useMemo(() => {
    let result = applyFilters(moves, filters);

    // Apply sorting
    result.sort((a, b) => {
      switch (sortBy) {
        case 'name-asc':
          return a.Name.localeCompare(b.Name);
        case 'name-desc':
          return b.Name.localeCompare(a.Name);
        case 'power-desc':
          return (b.BasePower || 0) - (a.BasePower || 0);
        case 'power-asc':
          return (a.BasePower || 0) - (b.BasePower || 0);
        case 'accuracy-desc':
          return (b.Accuracy || 0) - (a.Accuracy || 0);
        case 'accuracy-asc':
          return (a.Accuracy || 0) - (b.Accuracy || 0);
        case 'priority-desc':
          return (b.Priority || 0) - (a.Priority || 0);
        case 'priority-asc':
          return (a.Priority || 0) - (b.Priority || 0);
        case 'type-asc':
          return a.Type.localeCompare(b.Type);
        case 'category-asc':
          const categoryOrder = { Physical: 0, Special: 1, Status: 2 };
          return (categoryOrder[a.Category as keyof typeof categoryOrder] || 99) - 
                 (categoryOrder[b.Category as keyof typeof categoryOrder] || 99);
        default:
          return 0;
      }
    });

    return result;
  }, [filters, sortBy]);

  // Filter panel animation
  const filterPanelSpring = useSpring({
    height: showFilters ? 'auto' : 0,
    opacity: showFilters ? 1 : 0,
    config: getSpringConfig('gentle'),
  });

  const toggleType = (type: string) => {
    setFilters(prev => ({
      ...prev,
      types: prev.types.includes(type)
        ? prev.types.filter(t => t !== type)
        : [...prev.types, type]
    }));
  };

  const toggleCategory = (category: string) => {
    setFilters(prev => ({
      ...prev,
      categories: prev.categories.includes(category)
        ? prev.categories.filter(c => c !== category)
        : [...prev.categories, category]
    }));
  };

  const clearFilters = () => {
    setFilters(INITIAL_FILTERS);
  };

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Move Database
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>Complete database of all known moves with detailed stats and effects.</p>
      </div>

      {/* Search and Controls */}
      <div className="bg-white rounded-2xl shadow-xl border-2 border-slate-200 p-6">
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
              placeholder="Search moves by name or description..."
              className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              value={filters.search}
              onChange={(e) => setFilters(prev => ({ ...prev, search: e.target.value }))}
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
              <option value="power-desc">Power (High-Low)</option>
              <option value="power-asc">Power (Low-High)</option>
              <option value="accuracy-desc">Accuracy (High-Low)</option>
              <option value="accuracy-asc">Accuracy (Low-High)</option>
              <option value="priority-desc">Priority (High-Low)</option>
              <option value="priority-asc">Priority (Low-High)</option>
              <option value="type-asc">Type</option>
              <option value="category-asc">Category</option>
            </select>
            <div className="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none text-slate-500">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </div>
          </div>

          {/* View Toggle */}
          <div className="flex gap-2">
            <button
              onClick={() => setViewMode('table')}
              className={`px-4 py-2 rounded-lg font-medium text-sm transition-all border-2 ${
                viewMode === 'table'
                  ? 'bg-blue-50 text-blue-700 border-blue-300'
                  : 'bg-white text-slate-600 border-slate-300 hover:border-blue-300'
              }`}
            >
              Full
            </button>
            <button
              onClick={() => setViewMode('compact')}
              className={`px-4 py-2 rounded-lg font-medium text-sm transition-all border-2 ${
                viewMode === 'compact'
                  ? 'bg-blue-50 text-blue-700 border-blue-300'
                  : 'bg-white text-slate-600 border-slate-300 hover:border-blue-300'
              }`}
            >
              Compact
            </button>
          </div>

          {/* Filter Toggle */}
          <button
            onClick={() => setShowFilters(!showFilters)}
            className={`px-4 py-2 rounded-lg font-medium text-sm transition-all flex items-center gap-2 border-2 ${
              activeFilterCount > 0
                ? 'bg-blue-50 text-blue-700 border-blue-300 hover:bg-blue-100'
                : 'bg-white text-slate-600 border-slate-300 hover:border-blue-300 hover:text-blue-600'
            }`}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
            </svg>
            Filters
            {activeFilterCount > 0 && (
              <span className="bg-blue-600 text-white text-xs font-bold px-1.5 py-0.5 rounded-full min-w-[1.25rem] text-center">
                {activeFilterCount}
              </span>
            )}
          </button>
        </div>

        {/* Filters Panel */}
        <AnimatedDiv
          className="border-t border-slate-200 overflow-hidden"
          style={{
            height: filterPanelSpring.height,
            opacity: filterPanelSpring.opacity,
          }}
        >
          {showFilters && (
          <div className="pt-4 mt-4 space-y-4">
            {/* Type Filter */}
            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">Types</label>
              <div className="flex flex-wrap gap-2">
                {ALL_TYPES.map(type => (
                  <button
                    key={type}
                    onClick={() => toggleType(type)}
                    className={`transition-all ${
                      filters.types.includes(type)
                        ? 'ring-2 ring-blue-500 ring-offset-2 scale-105'
                        : 'opacity-70 hover:opacity-100 hover:scale-105'
                    }`}
                  >
                    <TypeBadge type={type} />
                  </button>
                ))}
              </div>
            </div>

            {/* Category Filter */}
            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">Categories</label>
              <div className="flex gap-2">
                {CATEGORIES.map(cat => (
                  <button
                    key={cat}
                    onClick={() => toggleCategory(cat)}
                    className={`px-4 py-2 rounded-lg font-medium text-sm border-2 transition-all ${
                      filters.categories.includes(cat)
                        ? 'bg-blue-100 text-blue-700 border-blue-300'
                        : 'bg-white text-slate-600 border-slate-300 hover:border-blue-300'
                    }`}
                  >
                    {cat}
                  </button>
                ))}
              </div>
            </div>

            {/* Power Range */}
            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">
                Power: {filters.power.min} - {filters.power.max}
              </label>
              <div className="flex gap-4 items-center">
                <input
                  type="range"
                  min="0"
                  max="200"
                  value={filters.power.min}
                  onChange={(e) => setFilters(prev => ({
                    ...prev,
                    power: { ...prev.power, min: parseInt(e.target.value) }
                  }))}
                  className="flex-1"
                />
                <input
                  type="range"
                  min="0"
                  max="200"
                  value={filters.power.max}
                  onChange={(e) => setFilters(prev => ({
                    ...prev,
                    power: { ...prev.power, max: parseInt(e.target.value) }
                  }))}
                  className="flex-1"
                />
              </div>
            </div>

            {/* Accuracy Range */}
            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">
                Accuracy: {filters.accuracy.min} - {filters.accuracy.max}
              </label>
              <div className="flex gap-4 items-center">
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={filters.accuracy.min}
                  onChange={(e) => setFilters(prev => ({
                    ...prev,
                    accuracy: { ...prev.accuracy, min: parseInt(e.target.value) }
                  }))}
                  className="flex-1"
                />
                <input
                  type="range"
                  min="0"
                  max="100"
                  value={filters.accuracy.max}
                  onChange={(e) => setFilters(prev => ({
                    ...prev,
                    accuracy: { ...prev.accuracy, max: parseInt(e.target.value) }
                  }))}
                  className="flex-1"
                />
              </div>
            </div>

            {/* Effect Filters */}
            <div>
              <label className="block text-sm font-semibold text-slate-700 mb-2">Effects</label>
              <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                {[
                  { key: 'hasStatus', label: 'Status Effect' },
                  { key: 'hasMultiHit', label: 'Multi-Hit' },
                  { key: 'hasRecoil', label: 'Recoil' },
                  { key: 'hasPriority', label: 'Priority' },
                  { key: 'hasHealing', label: 'Healing' },
                  { key: 'hasStatChanges', label: 'Stat Changes' },
                  { key: 'hasFlinch', label: 'Flinch' },
                  { key: 'hasConfusion', label: 'Confusion' },
                ].map(({ key, label }) => (
                  <label key={key} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={filters.effects[key as keyof typeof filters.effects]}
                      onChange={(e) => setFilters(prev => ({
                        ...prev,
                        effects: { ...prev.effects, [key]: e.target.checked }
                      }))}
                      className="w-4 h-4 text-blue-600 border-slate-300 rounded focus:ring-blue-500"
                    />
                    <span className="text-sm text-slate-700">{label}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Clear Filters */}
            {activeFilterCount > 0 && (
              <div className="pt-2 border-t border-slate-200">
                <button
                  onClick={clearFilters}
                  className="text-sm text-red-600 hover:text-red-700 font-medium underline"
                >
                  Clear All Filters ({activeFilterCount})
                </button>
              </div>
            )}
          </div>
          )}
        </AnimatedDiv>

        {/* Active Filters Display */}
        {activeFilterCount > 0 && (
          <div className="mt-4 pt-4 border-t border-slate-200 flex flex-wrap gap-2">
            {filters.types.map(type => (
              <span
                key={type}
                className="inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-bold border border-blue-200"
              >
                Type: {type}
                <button
                  onClick={() => toggleType(type)}
                  className="hover:text-blue-900"
                >
                  ×
                </button>
              </span>
            ))}
            {filters.categories.map(cat => (
              <span
                key={cat}
                className="inline-flex items-center gap-1 px-2 py-1 bg-green-100 text-green-700 rounded text-xs font-bold border border-green-200"
              >
                Category: {cat}
                <button
                  onClick={() => toggleCategory(cat)}
                  className="hover:text-green-900"
                >
                  ×
                </button>
              </span>
            ))}
            {(filters.power.min > 0 || filters.power.max < 200) && (
              <span className="inline-flex items-center gap-1 px-2 py-1 bg-purple-100 text-purple-700 rounded text-xs font-bold border border-purple-200">
                Power: {filters.power.min}-{filters.power.max}
              </span>
            )}
            {(filters.accuracy.min > 0 || filters.accuracy.max < 100) && (
              <span className="inline-flex items-center gap-1 px-2 py-1 bg-purple-100 text-purple-700 rounded text-xs font-bold border border-purple-200">
                Accuracy: {filters.accuracy.min}-{filters.accuracy.max}
              </span>
            )}
            {Object.entries(filters.effects).map(([key, value]) =>
              value ? (
                <span
                  key={key}
                  className="inline-flex items-center gap-1 px-2 py-1 bg-orange-100 text-orange-700 rounded text-xs font-bold border border-orange-200"
                >
                  {key.replace('has', '').replace(/([A-Z])/g, ' $1').trim()}
                </span>
              ) : null
            )}
          </div>
        )}
      </div>

      {/* Moves Table */}
      <div className="bg-white rounded-2xl shadow-xl border-2 border-slate-200 overflow-hidden">
        <div className="bg-gradient-to-r from-red-50 to-pink-50 px-6 py-4 border-b-2 border-slate-100">
          <h2 className="text-lg font-bold text-slate-800">
            Moves ({filteredMoves.length} of {moves.length})
          </h2>
        </div>
        <MoveTable 
          moves={filteredMoves} 
          showPriority={viewMode === 'table'} 
          compact={viewMode === 'compact'}
          moveLearnsetMap={moveLearnsetMap}
        />
      </div>
    </div>
  );
}

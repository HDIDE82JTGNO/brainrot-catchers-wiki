"use client";

import React, { useState, useEffect } from 'react';
import { useTransition, animated, useSpring } from '@react-spring/web';
import { CreatureFilters, INITIAL_FILTERS, StatRange } from '../lib/creatureFilters';
import { TypeBadge } from './TypeBadge';
import { getSpringConfig } from '@/lib/springConfigs';

// Type assertion for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;

// Types and Colors
const ALL_TYPES = ['Normal', 'Fire', 'Water', 'Electric', 'Grass', 'Ice', 'Fighting', 'Poison', 'Ground', 'Flying', 'Psychic', 'Bug', 'Rock', 'Ghost', 'Dragon', 'Dark', 'Steel', 'Fairy'];

interface CreatureFilterModalProps {
  isOpen: boolean;
  onClose: () => void;
  filters: CreatureFilters;
  onApply: (filters: CreatureFilters) => void;
  availableMoves: string[]; // Pass this from parent to populate move dropdown
  availableAbilities?: string[]; // Pass this from parent to populate ability dropdown
}

export function CreatureFilterModal({ isOpen, onClose, filters, onApply, availableMoves, availableAbilities = [] }: CreatureFilterModalProps) {
  // Local state for the modal form
  const [localFilters, setLocalFilters] = useState<CreatureFilters>(filters);
  const [moveSearch, setMoveSearch] = useState('');
  const [abilitySearch, setAbilitySearch] = useState('');

  // Sync local state when modal opens
  useEffect(() => {
    if (isOpen) {
      setLocalFilters(filters);
    }
  }, [isOpen, filters]);

  // Modal animations
  const backdropSpring = useSpring({
    opacity: isOpen ? 1 : 0,
    backdropFilter: isOpen ? 'blur(8px)' : 'blur(0px)',
    config: getSpringConfig('gentle'),
  });

  const modalSpring = useSpring({
    opacity: isOpen ? 1 : 0,
    transform: isOpen ? 'scale(1) translateY(0px)' : 'scale(0.95) translateY(20px)',
    config: getSpringConfig('snappy'),
  });

  if (!isOpen) return null;

  const handleStatChange = (stat: keyof CreatureFilters, type: 'min' | 'max', value: number) => {
    setLocalFilters(prev => ({
      ...prev,
      [stat]: {
        ...prev[stat as keyof CreatureFilters] as StatRange,
        [type]: value
      }
    }));
  };

  const toggleType = (type: string) => {
    setLocalFilters(prev => {
      const types = prev.types.includes(type)
        ? prev.types.filter(t => t !== type)
        : [...prev.types, type];
      return { ...prev, types };
    });
  };

  const toggleMove = (move: string) => {
    setLocalFilters(prev => {
        const moves = prev.moves.includes(move)
            ? prev.moves.filter(m => m !== move)
            : [...prev.moves, move];
        return { ...prev, moves };
    });
  };

  const toggleAbility = (ability: string) => {
    setLocalFilters(prev => {
        const abilities = prev.abilities.includes(ability)
            ? prev.abilities.filter(a => a !== ability)
            : [...prev.abilities, ability];
        return { ...prev, abilities };
    });
  };

  const resetFilters = () => {
    setLocalFilters(INITIAL_FILTERS);
  };

  const filteredMoves = availableMoves.filter(m => 
    m.toLowerCase().includes(moveSearch.toLowerCase())
  ).slice(0, 50); // Limit to 50 for performance

  const filteredAbilities = availableAbilities.filter(a => 
    a.toLowerCase().includes(abilitySearch.toLowerCase())
  ).slice(0, 50); // Limit to 50 for performance

  return (
    <AnimatedDiv 
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-2 sm:p-4 overflow-y-auto"
      style={{
        opacity: backdropSpring.opacity,
        backdropFilter: backdropSpring.backdropFilter,
      }}
      onClick={onClose}
    >
      <AnimatedDiv 
        className="bg-white rounded-2xl sm:rounded-3xl shadow-2xl w-full max-w-4xl max-h-[95vh] sm:max-h-[90vh] flex flex-col overflow-hidden border-2 border-slate-200 my-auto"
        style={{
          opacity: modalSpring.opacity,
          transform: modalSpring.transform,
        }}
        onClick={(e: React.MouseEvent) => e.stopPropagation()}
      >
        
        {/* Header */}
        <div className="p-6 border-b-2 border-slate-100 flex justify-between items-center bg-gradient-to-r from-indigo-50 to-purple-50">
          <div>
             <h2 className="text-3xl font-bold bg-gradient-to-r from-indigo-600 to-purple-600 bg-clip-text text-transparent">Filter Creatures</h2>
             <p className="text-sm text-slate-600 mt-1">Refine your search with detailed criteria</p>
          </div>
          <button onClick={onClose} className="p-2 hover:bg-white/80 rounded-xl text-slate-500 hover:text-slate-700 transition-all hover:scale-110">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>

        {/* Scrollable Content */}
        <div className="flex-1 overflow-y-auto p-6 space-y-8">
          
          {/* Types Section */}
          <section>
            <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                <span className="w-1 h-4 bg-blue-500 rounded-full"></span>
                Types (Match All)
            </h3>
            <div className="flex flex-wrap gap-2">
              {ALL_TYPES.map(type => (
                <button
                  key={type}
                  onClick={() => toggleType(type)}
                  className={`transition-all duration-200 ${localFilters.types.includes(type) ? 'ring-2 ring-blue-500 ring-offset-2 scale-105' : 'opacity-60 hover:opacity-100 grayscale hover:grayscale-0'}`}
                >
                  <TypeBadge type={type} />
                </button>
              ))}
            </div>
          </section>

           {/* Stats Section */}
           <section>
             <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                <span className="w-1 h-4 bg-purple-500 rounded-full"></span>
                Base Stats Range
             </h3>
             <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {[
                    { label: 'HP', key: 'hp' },
                    { label: 'Attack', key: 'attack' },
                    { label: 'Defense', key: 'defense' },
                    { label: 'Sp. Atk', key: 'specialAttack' },
                    { label: 'Sp. Def', key: 'specialDefense' },
                    { label: 'Speed', key: 'speed' },
                ].map((stat) => (
                    <div key={stat.key} className="bg-slate-50 p-3 rounded-lg border border-slate-100">
                        <label className="block text-xs font-bold text-slate-500 uppercase mb-2">{stat.label}</label>
                        <div className="flex items-center gap-2">
                            <input 
                                type="number" 
                                min="0" max="255"
                                value={(localFilters[stat.key as keyof CreatureFilters] as StatRange).min}
                                onChange={(e) => handleStatChange(stat.key as keyof CreatureFilters, 'min', Number(e.target.value))}
                                className="w-full px-2 py-1 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                            />
                            <span className="text-slate-400">-</span>
                            <input 
                                type="number" 
                                min="0" max="255"
                                value={(localFilters[stat.key as keyof CreatureFilters] as StatRange).max}
                                onChange={(e) => handleStatChange(stat.key as keyof CreatureFilters, 'max', Number(e.target.value))}
                                className="w-full px-2 py-1 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                            />
                        </div>
                    </div>
                ))}
             </div>
           </section>

           {/* Moves Section */}
           <section>
             <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                <span className="w-1 h-4 bg-green-500 rounded-full"></span>
                Moves (Match Any)
             </h3>
             <div className="bg-slate-50 border border-slate-200 rounded-lg p-4">
                <input 
                    type="text"
                    placeholder="Search for a move..."
                    className="w-full px-4 py-2 mb-4 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 outline-none"
                    value={moveSearch}
                    onChange={(e) => setMoveSearch(e.target.value)}
                />
                
                {localFilters.moves.length > 0 && (
                     <div className="flex flex-wrap gap-2 mb-4 p-2 bg-white rounded border border-slate-100">
                        {localFilters.moves.map(move => (
                            <span key={move} className="inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-bold">
                                {move}
                                <button onClick={() => toggleMove(move)} className="hover:text-blue-900">×</button>
                            </span>
                        ))}
                     </div>
                )}

                <div className="max-h-40 overflow-y-auto grid grid-cols-2 sm:grid-cols-3 gap-2">
                    {filteredMoves.map(move => (
                        <label key={move} className="flex items-center gap-2 text-sm text-slate-700 hover:bg-white p-1 rounded cursor-pointer transition-colors">
                            <input 
                                type="checkbox"
                                checked={localFilters.moves.includes(move)}
                                onChange={() => toggleMove(move)}
                                className="rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                            />
                            {move}
                        </label>
                    ))}
                    {filteredMoves.length === 0 && (
                        <div className="col-span-full text-center text-slate-400 text-sm py-2">No moves found</div>
                    )}
                </div>
             </div>
           </section>

           {/* Abilities Section */}
           {availableAbilities.length > 0 && (
             <section>
               <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                  <span className="w-1 h-4 bg-yellow-500 rounded-full"></span>
                  Abilities (Match Any)
               </h3>
               <div className="bg-slate-50 border border-slate-200 rounded-lg p-4">
                  <input 
                      type="text"
                      placeholder="Search for an ability..."
                      className="w-full px-4 py-2 mb-4 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-blue-500 outline-none"
                      value={abilitySearch}
                      onChange={(e) => setAbilitySearch(e.target.value)}
                  />
                  
                  {localFilters.abilities.length > 0 && (
                       <div className="flex flex-wrap gap-2 mb-4 p-2 bg-white rounded border border-slate-100">
                          {localFilters.abilities.map(ability => (
                              <span key={ability} className="inline-flex items-center gap-1 px-2 py-1 bg-yellow-100 text-yellow-700 rounded text-xs font-bold">
                                  {ability}
                                  <button onClick={() => toggleAbility(ability)} className="hover:text-yellow-900">×</button>
                              </span>
                          ))}
                       </div>
                  )}

                  <div className="max-h-40 overflow-y-auto grid grid-cols-2 sm:grid-cols-3 gap-2">
                      {filteredAbilities.map(ability => (
                          <label key={ability} className="flex items-center gap-2 text-sm text-slate-700 hover:bg-white p-1 rounded cursor-pointer transition-colors">
                              <input 
                                  type="checkbox"
                                  checked={localFilters.abilities.includes(ability)}
                                  onChange={() => toggleAbility(ability)}
                                  className="rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                              />
                              {ability}
                          </label>
                      ))}
                      {filteredAbilities.length === 0 && (
                          <div className="col-span-full text-center text-slate-400 text-sm py-2">No abilities found</div>
                      )}
                  </div>
               </div>
             </section>
           )}

           {/* Other Filters */}
           <section className="grid grid-cols-1 md:grid-cols-2 gap-8">
               {/* Evolution */}
               <div>
                 <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                    <span className="w-1 h-4 bg-orange-500 rounded-full"></span>
                    Evolution Status
                 </h3>
                 <div className="flex bg-slate-50 p-1 rounded-lg border border-slate-200">
                    {['all', 'can_evolve', 'final'].map(opt => (
                        <button
                            key={opt}
                            onClick={() => setLocalFilters(prev => ({ ...prev, evolutionStatus: opt as any }))}
                            className={`flex-1 py-2 text-sm font-medium rounded-md transition-all ${
                                localFilters.evolutionStatus === opt 
                                    ? 'bg-white text-blue-600 shadow-sm border border-slate-100' 
                                    : 'text-slate-500 hover:text-slate-700'
                            }`}
                        >
                            {opt === 'all' ? 'All' : opt === 'can_evolve' ? 'Evolving' : 'Final Form'}
                        </button>
                    ))}
                 </div>
               </div>
                
               {/* Dex Number */}
               <div>
                  <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                    <span className="w-1 h-4 bg-gray-500 rounded-full"></span>
                    Dex Number Range
                 </h3>
                  <div className="flex items-center gap-3 bg-slate-50 p-3 rounded-lg border border-slate-100">
                        <input 
                            type="number" 
                            value={localFilters.dexNumber.min}
                            onChange={(e) => handleStatChange('dexNumber', 'min', Number(e.target.value))}
                            className="w-full px-3 py-2 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                            placeholder="Min"
                        />
                        <span className="text-slate-400 font-bold">to</span>
                        <input 
                            type="number" 
                            value={localFilters.dexNumber.max}
                            onChange={(e) => handleStatChange('dexNumber', 'max', Number(e.target.value))}
                            className="w-full px-3 py-2 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                            placeholder="Max"
                        />
                  </div>
               </div>
           </section>

            {/* Catch Rate & Weight */}
            <section className="grid grid-cols-1 md:grid-cols-2 gap-8">
                <div>
                    <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                        <span className="w-1 h-4 bg-red-500 rounded-full"></span>
                        Catch Rate
                    </h3>
                    <div className="flex items-center gap-3 bg-slate-50 p-3 rounded-lg border border-slate-100">
                        <input 
                            type="number" 
                            value={localFilters.catchRate.min}
                            onChange={(e) => handleStatChange('catchRate', 'min', Number(e.target.value))}
                            className="w-full px-3 py-2 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                        />
                         <span className="text-slate-400">-</span>
                        <input 
                            type="number" 
                            value={localFilters.catchRate.max}
                            onChange={(e) => handleStatChange('catchRate', 'max', Number(e.target.value))}
                            className="w-full px-3 py-2 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                        />
                    </div>
                </div>
                 <div>
                    <h3 className="text-sm font-bold text-slate-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                        <span className="w-1 h-4 bg-teal-500 rounded-full"></span>
                        Weight (kg)
                    </h3>
                    <div className="flex items-center gap-3 bg-slate-50 p-3 rounded-lg border border-slate-100">
                        <input 
                            type="number" 
                            value={localFilters.weight.min}
                            onChange={(e) => handleStatChange('weight', 'min', Number(e.target.value))}
                            className="w-full px-3 py-2 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                        />
                         <span className="text-slate-400">-</span>
                        <input 
                            type="number" 
                            value={localFilters.weight.max}
                            onChange={(e) => handleStatChange('weight', 'max', Number(e.target.value))}
                            className="w-full px-3 py-2 text-sm border border-slate-200 rounded text-center focus:ring-1 focus:ring-blue-500 outline-none"
                        />
                    </div>
                </div>
            </section>
        </div>

        {/* Footer */}
        <div className="p-6 border-t-2 border-slate-100 bg-gradient-to-r from-slate-50 to-slate-100 flex flex-col sm:flex-row justify-between items-center gap-4">
          <button 
            onClick={resetFilters}
            className="text-slate-600 font-medium text-sm hover:text-red-600 transition-colors px-4 py-2 hover:bg-white rounded-lg border border-slate-200 hover:border-red-200"
          >
            Clear All Filters
          </button>
          <div className="flex gap-3 w-full sm:w-auto">
             <button 
                onClick={onClose}
                className="flex-1 sm:flex-none px-6 py-2.5 rounded-xl font-medium text-slate-600 hover:bg-white border-2 border-slate-200 hover:border-slate-300 transition-all"
             >
                Cancel
             </button>
             <button 
                onClick={() => onApply(localFilters)}
                className="flex-1 sm:flex-none px-6 py-2.5 bg-gradient-to-r from-indigo-600 to-purple-600 text-white rounded-xl font-bold shadow-lg hover:shadow-xl hover:from-indigo-700 hover:to-purple-700 transition-all active:scale-95"
             >
                Apply Filters
             </button>
          </div>
        </div>
      </AnimatedDiv>
    </AnimatedDiv>
  );
}


"use client";

import React, { useState, useMemo, useEffect, useCallback, memo } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { usePathname } from 'next/navigation';
import { useTrail, useSpring, animated } from '@react-spring/web';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import abilitiesData from '../../data/abilities.json';
import { TypeBadge } from '@/components/TypeBadge';
import { Creature, Ability } from '@/types';
import { getSpritePath } from '@/lib/spriteUtils';
import { CreatureFilterModal } from '@/components/CreatureFilterModal';
import { CreatureFilters, INITIAL_FILTERS, applyFilters } from '@/lib/creatureFilters';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as any[];
const abilities = abilitiesData as unknown as Ability[];

// Type assertions for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;
const AnimatedSvg = animated.svg as any;

// Shiny toggle button with flip animation
const ShinyToggleButton = memo(function ShinyToggleButton({ isShiny, onClick }: { isShiny: boolean; onClick: (e: React.MouseEvent) => void }) {
  const flipSpring = useSpring({
    transform: isShiny ? 'rotateY(180deg)' : 'rotateY(0deg)',
    config: getSpringConfig('snappy'),
  });

  return (
    <AnimatedDiv
      className="absolute top-3 right-3 z-20"
      style={{
        transform: flipSpring.transform,
        transformStyle: 'preserve-3d',
      }}
    >
      <button
        onClick={onClick}
        className={`p-2 rounded-xl transition-all shadow-md ${
          isShiny
            ? 'bg-gradient-to-br from-yellow-100 to-yellow-200 text-yellow-700 border-2 border-yellow-300 hover:from-yellow-200 hover:to-yellow-300'
            : 'bg-white/95 backdrop-blur-sm text-slate-400 border-2 border-slate-200 hover:bg-white hover:text-yellow-500 hover:border-yellow-300'
        }`}
        title={isShiny ? 'Toggle to Normal' : 'Toggle to Shiny'}
      >
        <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
          <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
        </svg>
      </button>
    </AnimatedDiv>
  );
});

// Get all unique moves for the dropdown
const availableMoves = Array.from(new Set(
    creatures.flatMap(c => {
        if (!c.Learnset) return [];
        const moves: string[] = [];
        Object.values(c.Learnset).forEach(m => {
             if (Array.isArray(m)) moves.push(...m);
        });
        return moves;
    })
)).sort();

// Get all unique abilities for the dropdown
const availableAbilities = Array.from(new Set(
    abilities.map(a => a.Name)
)).sort();

const ITEMS_PER_PAGE = 20;

export default function CreaturesPage() {
  const [search, setSearch] = useState('');
  const [isSearchFocused, setIsSearchFocused] = useState(false);
  const [shinyCreatures, setShinyCreatures] = useState<Set<string>>(new Set());
  const [filters, setFilters] = useState<CreatureFilters>(INITIAL_FILTERS);
  const [isFilterModalOpen, setIsFilterModalOpen] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);

  // Calculate active filter count
  const activeFilterCount = useMemo(() => {
    let count = 0;
    if (filters.types.length > 0) count++;
    if (filters.moves.length > 0) count++;
    if (filters.abilities.length > 0) count++;
    if (filters.hp.min > 0 || filters.hp.max < 255) count++;
    if (filters.attack.min > 0 || filters.attack.max < 255) count++;
    if (filters.defense.min > 0 || filters.defense.max < 255) count++;
    if (filters.specialAttack.min > 0 || filters.specialAttack.max < 255) count++;
    if (filters.specialDefense.min > 0 || filters.specialDefense.max < 255) count++;
    if (filters.speed.min > 0 || filters.speed.max < 255) count++;
    if (filters.catchRate.min > 0 || filters.catchRate.max < 255) count++;
    if (filters.weight.min > 0 || filters.weight.max < 1000) count++;
    if (filters.evolutionStatus !== 'all') count++;
    if (filters.dexNumber.min > 1 || filters.dexNumber.max < 999) count++;
    return count;
  }, [filters]);

  const filtered = useMemo(() => {
    let result = creatures.filter(c => 
        c.Name?.toLowerCase().includes(search.toLowerCase())
    );
    
    // Apply advanced filters
    result = applyFilters(result, filters);
    
    return result;
  }, [search, filters]);

  // Pagination
  const totalPages = Math.ceil(filtered.length / ITEMS_PER_PAGE);
  const paginatedCreatures = useMemo(() => {
    const startIndex = (currentPage - 1) * ITEMS_PER_PAGE;
    return filtered.slice(startIndex, startIndex + ITEMS_PER_PAGE);
  }, [filtered, currentPage]);

  // Reset to page 1 when filters change
  useEffect(() => {
    setCurrentPage(1);
  }, [search, filters]);

  const toggleShiny = useCallback((creatureName: string, e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setShinyCreatures(prev => {
      const next = new Set(prev);
      if (next.has(creatureName)) {
        next.delete(creatureName);
      } else {
        next.add(creatureName);
      }
      return next;
    });
  }, []);

  const toggleAllShiny = useCallback(() => {
    // Check if all filtered creatures are already shiny
    const allShiny = filtered.every(c => shinyCreatures.has(c.Name));
    
    setShinyCreatures(prev => {
      const next = new Set(prev);
      if (allShiny) {
        // Remove all filtered creatures from shiny set
        filtered.forEach(c => next.delete(c.Name));
      } else {
        // Add all filtered creatures to shiny set
        filtered.forEach(c => next.add(c.Name));
      }
      return next;
    });
  }, [filtered, shinyCreatures]);

  const handleApplyFilters = useCallback((newFilters: CreatureFilters) => {
    setFilters(newFilters);
    setIsFilterModalOpen(false);
  }, []);

  const pathname = usePathname();
  const [isMounted, setIsMounted] = useState(false);
  const prevPathnameRef = React.useRef(pathname);
  
  // Set mounted to true when filtered creatures are available
  useEffect(() => {
    if (paginatedCreatures.length > 0) {
      setIsMounted(true);
    }
  }, [paginatedCreatures.length]);
  
  useEffect(() => {
    // Only animate if pathname actually changed
    if (prevPathnameRef.current !== pathname) {
      setIsMounted(false);
      const timer = setTimeout(() => {
        setIsMounted(true);
      }, 50);
      prevPathnameRef.current = pathname;
      return () => clearTimeout(timer);
    }
  }, [pathname]);

  // Trail animation for creature cards (only for visible page)
  const trail = useTrail(paginatedCreatures.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: isMounted ? { opacity: 1, transform: 'translateY(0px) scale(1)' } : { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    config: getSpringConfig('snappy'),
  });

  // Search input focus animation
  const searchSpring = useSpring({
    borderColor: isSearchFocused ? 'rgb(59, 130, 246)' : 'rgb(203, 213, 225)',
    boxShadow: isSearchFocused 
      ? '0 0 0 3px rgba(59, 130, 246, 0.1)' 
      : '0 0 0 0px rgba(59, 130, 246, 0)',
    config: getSpringConfig('snappy'),
  });

  return (
    <div>
      <CreatureFilterModal 
        isOpen={isFilterModalOpen} 
        onClose={() => setIsFilterModalOpen(false)}
        filters={filters}
        onApply={handleApplyFilters}
        availableMoves={availableMoves}
        availableAbilities={availableAbilities}
      />

      <div className="flex flex-col md:flex-row justify-between items-center mb-8 gap-4">
        <h1 className="text-3xl font-bold text-white w-full md:w-auto text-center" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>Creature Dex</h1>
        <div className="flex flex-col sm:flex-row gap-3 w-full md:w-auto">
          
          {/* Filter Button */}
          <button
            onClick={() => setIsFilterModalOpen(true)}
            className={`px-3 sm:px-4 py-2 rounded-lg font-medium text-xs sm:text-sm transition-all flex items-center justify-center gap-2 border-2 ${
                activeFilterCount > 0 
                    ? 'bg-blue-50 text-blue-700 border-blue-200 hover:bg-blue-100' 
                    : 'bg-white text-slate-600 border-slate-200 hover:border-blue-300 hover:text-blue-600'
            }`}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" /></svg>
            <span className="hidden sm:inline">Filters</span>
            <span className="sm:hidden">Filter</span>
            {activeFilterCount > 0 && (
                <span className="bg-blue-600 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full min-w-[1.25rem] text-center">
                    {activeFilterCount}
                </span>
            )}
          </button>

          <button
            onClick={toggleAllShiny}
            className={`px-3 sm:px-4 py-2 rounded-lg font-medium text-xs sm:text-sm transition-all flex items-center justify-center gap-2 ${
              filtered.length > 0 && filtered.every(c => shinyCreatures.has(c.Name))
                ? 'bg-yellow-100 text-yellow-700 border-2 border-yellow-300 hover:bg-yellow-200'
                : 'bg-slate-100 text-slate-700 border-2 border-slate-300 hover:bg-slate-200'
            }`}
            disabled={filtered.length === 0}
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
            </svg>
            <span className="hidden sm:inline">
              {filtered.length > 0 && filtered.every(c => shinyCreatures.has(c.Name))
                ? 'Show Normal'
                : 'Show All Shiny'}
            </span>
            <span className="sm:hidden">Shiny</span>
          </button>
          
          <AnimatedDiv className="relative w-full sm:w-80 md:w-96" style={searchSpring}>
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <AnimatedSvg 
                className="h-5 w-5 text-gray-400" 
                viewBox="0 0 20 20" 
                fill="currentColor"
                style={{
                  transform: isSearchFocused ? 'scale(1.1)' : 'scale(1)',
                }}
              >
                <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
              </AnimatedSvg>
            </div>
            <input 
              type="text" 
              placeholder="Search creatures..." 
              className="w-full pl-10 pr-4 py-2 border rounded-lg shadow-sm outline-none transition-all bg-white"
              style={{
                borderColor: searchSpring.borderColor,
                boxShadow: searchSpring.boxShadow,
              } as unknown as React.CSSProperties}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              onFocus={() => setIsSearchFocused(true)}
              onBlur={() => setIsSearchFocused(false)}
            />
          </AnimatedDiv>
        </div>
      </div>
      
      {/* Active Filters Display (Optional but helpful) */}
      {activeFilterCount > 0 && (
          <div className="mb-6 flex flex-wrap gap-2">
               {filters.types.map(t => (
                   <span key={t} className="inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-bold border border-blue-200">
                       Type: {t}
                   </span>
               ))}
               {filters.moves.map(m => (
                   <span key={m} className="inline-flex items-center gap-1 px-2 py-1 bg-green-100 text-green-700 rounded text-xs font-bold border border-green-200">
                       Move: {m}
                   </span>
               ))}
               {filters.abilities.map(a => (
                   <span key={a} className="inline-flex items-center gap-1 px-2 py-1 bg-yellow-100 text-yellow-700 rounded text-xs font-bold border border-yellow-200">
                       Ability: {a}
                   </span>
               ))}
               {/* Add more filter tags if desired */}
               <button 
                  onClick={() => setFilters(INITIAL_FILTERS)}
                  className="text-xs text-slate-500 hover:text-red-500 font-medium underline"
               >
                   Clear All ({activeFilterCount})
               </button>
          </div>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3 sm:gap-4 md:gap-6">
        {trail.map((style, idx) => {
          const c = paginatedCreatures[idx];
          if (!c) return null;
          const isShiny = shinyCreatures.has(c.Name);
          
          return (
          <AnimatedDiv 
            key={c.Id || c.DexNumber || `creature-${idx}`}
            style={style}
          >
          <Link href={`/creatures/${encodeURIComponent(c.Name)}`} className="group block bg-white rounded-2xl border-2 border-slate-200 shadow-lg hover:shadow-2xl hover:border-blue-400 transition-all duration-300 overflow-hidden card-hover">
            <div className="aspect-square bg-gradient-to-br from-slate-50 to-slate-100 flex items-center justify-center relative overflow-hidden">
               {/* Subtle pattern overlay */}
               <div className="absolute inset-0 opacity-5 bg-[url('data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDAiIGhlaWdodD0iNDAiIHZpZXdCb3g9IjAgMCA0MCA0MCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48ZyBmaWxsPSIjMDAwIj48Y2lyY2xlIGN4PSIyMCIgY3k9IjIwIiByPSIyIi8+PC9nPjwvc3ZnPg==')]"></div>
               
               <Image
                 src={getSpritePath(c.Name, shinyCreatures.has(c.Name))}
                 alt={c.Name}
                 width={256}
                 height={256}
                 className="w-3/4 h-3/4 object-contain transition-transform duration-500 group-hover:scale-125 relative z-10 drop-shadow-lg"
                 style={{ imageRendering: 'pixelated' }}
                 loading="lazy"
                 onError={(e) => {
                   (e.target as HTMLImageElement).style.display = 'none';
                   (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden');
                 }}
               />
               <span className="hidden text-5xl opacity-50 grayscale group-hover:grayscale-0 transition-all duration-300 relative z-10">👾</span>
               
               <div className="absolute top-3 left-3 text-xs font-bold text-slate-600 bg-white/95 backdrop-blur-sm px-2 py-1 rounded-lg shadow-md border border-slate-200 z-20">
                 #{String(c.DexNumber || 0).padStart(3, '0')}
               </div>
               
               <ShinyToggleButton
                 isShiny={isShiny}
                 onClick={(e) => toggleShiny(c.Name, e)}
               />
            </div>
            <div className="p-5 bg-gradient-to-b from-white to-slate-50">
              <div className="font-bold text-lg text-slate-900 mb-3 truncate group-hover:text-blue-600 transition-colors">{c.Name}</div>
              <div className="flex gap-1.5 flex-wrap">
                {c.Types && c.Types.filter(t => t && t !== null).map((t, tidx) => <TypeBadge key={`${c.Id || idx}-type-${tidx}`} type={t} className="scale-95" />)}
              </div>
            </div>
          </Link>
          </AnimatedDiv>
        );
        })}
      </div>
      
      {filtered.length === 0 && (
        <EmptyState 
          message={`No creatures found matching "${search}"${activeFilterCount > 0 ? ' with current filters' : ''}`}
          icon="👾"
        />
      )}

      {/* Pagination Controls */}
      {filtered.length > ITEMS_PER_PAGE && (
        <div className="flex items-center justify-center gap-4 mt-8">
          <button
            onClick={() => setCurrentPage(prev => Math.max(1, prev - 1))}
            disabled={currentPage === 1}
            className="px-4 py-2 rounded-lg font-medium text-sm transition-all border-2 disabled:opacity-50 disabled:cursor-not-allowed bg-white text-slate-600 border-slate-300 hover:border-blue-300 hover:text-blue-600"
          >
            Previous
          </button>
          <span className="text-sm text-slate-600">
            Page {currentPage} of {totalPages} ({filtered.length} total)
          </span>
          <button
            onClick={() => setCurrentPage(prev => Math.min(totalPages, prev + 1))}
            disabled={currentPage === totalPages}
            className="px-4 py-2 rounded-lg font-medium text-sm transition-all border-2 disabled:opacity-50 disabled:cursor-not-allowed bg-white text-slate-600 border-slate-300 hover:border-blue-300 hover:text-blue-600"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}

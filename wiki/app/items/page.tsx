"use client";

import React, { useState, useMemo, useEffect } from 'react';
import { usePathname } from 'next/navigation';
import { useTrail, animated } from '@react-spring/web';
import itemsData from '../../data/items.json';
import movesData from '../../data/moves.json';
import { Item } from '@/types';
import { ItemImage } from '@/components/ItemImage';
import { TypeBadge } from '@/components/TypeBadge';
import { EmptyState } from '@/components/EmptyState';
import { getSpringConfig } from '@/lib/springConfigs';

const items = itemsData as unknown as Item[];
const moves = movesData as unknown as any[];

// Type assertion for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;

// Group items by category
const itemsByCategory = items.reduce((acc, item) => {
  const cat = item.Category || 'Misc';
  if (!acc[cat]) acc[cat] = [];
  acc[cat].push(item);
  return acc;
}, {} as Record<string, Item[]>);

type SortOption = 'none' | 'battle' | 'overworld' | 'type';

// All available types for filtering
const ALL_TYPES = ['Normal', 'Fire', 'Water', 'Electric', 'Grass', 'Ice', 'Fighting', 'Poison', 'Ground', 'Flying', 'Psychic', 'Bug', 'Rock', 'Ghost', 'Dragon', 'Dark', 'Steel', 'Fairy'];

export default function ItemsPage() {
  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState<SortOption>('none');
  const [selectedMLType, setSelectedMLType] = useState<string | null>(null);

  // Helper to get move type for an item
  const getItemType = (item: Item) => {
    if (item.Name.startsWith('ML - ')) {
      const moveName = item.Name.replace('ML - ', '');
      const move = moves.find(m => m.Name === moveName);
      if (move) {
        if (Array.isArray(move.Type)) return move.Type[0];
        return move.Type;
      }
    }
    return '';
  };

  // Get all unique types in MoveLearners category
  const mlTypes = useMemo(() => {
    const mlItems = itemsByCategory['MoveLearners'] || [];
    const types = new Set<string>();
    mlItems.forEach(item => {
      const type = getItemType(item);
      if (type) types.add(type);
    });
    return Array.from(types).sort();
  }, []);

  const filteredAndSortedCategories = useMemo(() => {
    return Object.entries(itemsByCategory).reduce((acc, [category, categoryItems]) => {
      // 1. Filter by search
      let filteredItems = categoryItems.filter(item => 
        item.Name.toLowerCase().includes(search.toLowerCase()) || 
        item.Description?.toLowerCase().includes(search.toLowerCase())
      );

      // 2. Filter ML items by type if a type is selected
      if (category === 'MoveLearners' && selectedMLType) {
        filteredItems = filteredItems.filter(item => getItemType(item) === selectedMLType);
      }

      // 3. Sort
      if (filteredItems.length > 0) {
        filteredItems.sort((a, b) => {
          if (sortBy === 'battle') {
            // Battle items first
            if (a.UsableInBattle && !b.UsableInBattle) return -1;
            if (!a.UsableInBattle && b.UsableInBattle) return 1;
            // If both or neither, sort alphabetically
            return a.Name.localeCompare(b.Name);
          } else if (sortBy === 'overworld') {
            // Overworld items first
            if (a.UsableInOverworld && !b.UsableInOverworld) return -1;
            if (!a.UsableInOverworld && b.UsableInOverworld) return 1;
            // If both or neither, sort alphabetically
            return a.Name.localeCompare(b.Name);
          } else if (sortBy === 'type') {
            // Sort by type (works for all items, but most useful for ML)
            const typeA = getItemType(a) || '';
            const typeB = getItemType(b) || '';
            if (typeA !== typeB) {
              return typeA.localeCompare(typeB);
            }
            // Same type, sort by name
            return a.Name.localeCompare(b.Name);
          }
          // Default: Alphabetical by name
          return a.Name.localeCompare(b.Name);
        });

        acc.push([category, filteredItems]);
      }
      return acc;
    }, [] as [string, Item[]][]);
  }, [search, sortBy, selectedMLType]);

  return (
    <div className="max-w-6xl mx-auto">
      <div className="flex flex-col md:flex-row justify-between items-center mb-8 gap-4">
        <h1 className="text-3xl font-bold text-white w-full md:w-auto text-center" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>Items</h1>
        
        <div className="flex flex-col sm:flex-row gap-4 w-full md:w-auto">
             {/* Sort Dropdown */}
            <div className="relative">
                <select
                    value={sortBy}
                    onChange={(e) => setSortBy(e.target.value as SortOption)}
                    className="w-full sm:w-48 appearance-none pl-4 pr-10 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none bg-white text-slate-700 cursor-pointer"
                >
                    <option value="none">Sort by Name</option>
                    <option value="battle">Battle Usage</option>
                    <option value="overworld">Overworld Usage</option>
                    <option value="type">By Type</option>
                </select>
                <div className="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none text-slate-500">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" /></svg>
                </div>
            </div>

            {/* Search Input */}
            <div className="relative w-full md:w-80">
                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <svg className="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
                    </svg>
                </div>
                <input 
                    type="text" 
                    placeholder="Search items..." 
                    className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                />
            </div>
        </div>
      </div>
      
      <div className="space-y-12">
        {filteredAndSortedCategories.length > 0 ? (
          filteredAndSortedCategories.map(([category, categoryItems]) => (
            <div key={category}>
              <h2 className="text-xl font-bold text-slate-700 mb-4 border-b border-slate-200 pb-2 flex items-center gap-2">
                <span className="bg-slate-100 px-2 py-1 rounded text-sm text-slate-500 uppercase tracking-wide">{category}</span>
                <span className="text-xs text-slate-400 font-normal">({categoryItems.length})</span>
              </h2>
              
              {/* Type Filter for MoveLearners */}
              {category === 'MoveLearners' && (
                <div className="mb-4">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="text-sm font-medium text-slate-600">Filter by Type:</span>
                    <button
                      onClick={() => setSelectedMLType(null)}
                      className={`px-3 py-1 text-xs font-medium rounded-lg border transition-colors ${
                        selectedMLType === null
                          ? 'bg-blue-100 text-blue-700 border-blue-300'
                          : 'bg-slate-100 text-slate-600 border-slate-300 hover:bg-slate-200'
                      }`}
                    >
                      All
                    </button>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {mlTypes.map(type => (
                      <button
                        key={type}
                        onClick={() => setSelectedMLType(selectedMLType === type ? null : type)}
                        className={`transition-all ${
                          selectedMLType === type
                            ? 'ring-2 ring-blue-500 ring-offset-2 scale-105'
                            : 'opacity-70 hover:opacity-100 hover:scale-105'
                        }`}
                      >
                        <TypeBadge type={type} />
                      </button>
                    ))}
                  </div>
                </div>
              )}

              <ItemCardList items={categoryItems} moves={moves} getItemType={getItemType} />
            </div>
          ))
        ) : (
          <EmptyState 
            message={`No items found matching "${search}"`}
            icon="🎒"
          />
        )}
      </div>
    </div>
  );
}

function ItemCardList({ items, moves, getItemType }: { items: Item[]; moves: any[]; getItemType: (item: Item) => string }) {
  const pathname = usePathname();
  const [isMounted, setIsMounted] = useState(false);
  const prevPathnameRef = React.useRef(pathname);
  
  // Set mounted to true when items are available
  useEffect(() => {
    if (items.length > 0) {
      setIsMounted(true);
    }
  }, [items.length]);
  
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

  const itemKeys = useMemo(() => items.map((item, idx) => `${item.Name}-${idx}`), [items]);
  
  // Use a faster spring config for items page
  const fastConfig = { tension: 1000, friction: 40 };
  
  const trail = useTrail(items.length, {
    keys: itemKeys,
    from: { opacity: 0, transform: 'translateY(20px)' },
    to: isMounted ? { opacity: 1, transform: 'translateY(0px)' } : { opacity: 0, transform: 'translateY(20px)' },
    config: fastConfig,
    trail: 3, // Very small stagger delay - items animate almost simultaneously
  });

  if (items.length === 0) return null;

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {trail.map((style, idx) => {
        const item = items[idx];
        if (!item) return null;
        return (
          <AnimatedDiv 
            key={itemKeys[idx]}
            style={style}
            className="bg-white p-4 rounded-xl border border-slate-200 shadow-sm hover:shadow-md transition-all flex gap-4 items-start group"
          >
            <div className="w-16 h-16 bg-slate-50 rounded-lg border border-slate-100 flex-shrink-0 flex items-center justify-center overflow-hidden">
              <ItemImage item={item} moves={moves} size={48} />
            </div>
            <div className="flex-1 min-w-0">
              <h3 className="font-bold text-slate-900 truncate pr-2 group-hover:text-blue-600 transition-colors" title={item.Name}>{item.Name}</h3>
              <p className="text-sm text-slate-500 mt-1 line-clamp-2 leading-relaxed h-10">{item.Description}</p>
              
              <div className="mt-2 flex gap-2 flex-wrap">
                {(item.UsableInBattle || item.UsableInOverworld) && (
                  <>
                    {item.UsableInBattle && <span className="text-[10px] bg-red-50 text-red-600 px-1.5 py-0.5 rounded font-medium border border-red-100">Battle</span>}
                    {item.UsableInOverworld && <span className="text-[10px] bg-green-50 text-green-600 px-1.5 py-0.5 rounded font-medium border border-green-100">Overworld</span>}
                  </>
                )}
                {item.Name.startsWith('ML - ') && (
                  <TypeBadge type={getItemType(item)} className="scale-90 origin-left" />
                )}
              </div>
            </div>
          </AnimatedDiv>
        );
      })}
    </div>
  );
}

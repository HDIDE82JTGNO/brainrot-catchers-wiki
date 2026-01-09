"use client";

import React, { useState, useEffect, useRef, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { Creature, Move, Item, Location } from '@/types';
import { TypeBadge } from './TypeBadge';
import { getSpritePath } from '@/lib/spriteUtils';

interface GlobalSearchProps {
  creatures: Creature[];
  moves: Move[];
  items: Item[];
  locations: Location[];
  className?: string;
}

interface SearchResult {
  type: 'creature' | 'move' | 'item' | 'location';
  id: string;
  name: string;
  description?: string;
  url: string;
  icon?: string;
  metadata?: React.ReactNode;
}

export function GlobalSearch({ creatures, moves, items, locations, className = '' }: GlobalSearchProps) {
  const [query, setQuery] = useState('');
  const [isOpen, setIsOpen] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const searchRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const router = useRouter();

  // Search results
  const results = useMemo(() => {
    if (!query.trim()) return [];

    const queryLower = query.toLowerCase().trim();
    const searchResults: SearchResult[] = [];

    // Search creatures
    creatures
      .filter(c => 
        c.Name.toLowerCase().includes(queryLower) ||
        c.Description?.toLowerCase().includes(queryLower) ||
        c.Types?.some(t => t.toLowerCase().includes(queryLower))
      )
      .slice(0, 5)
      .forEach(c => {
        searchResults.push({
          type: 'creature',
          id: c.Id,
          name: c.Name,
          description: c.Description,
          url: `/creatures/${encodeURIComponent(c.Name)}`,
          icon: '👾',
          metadata: (
            <div className="flex items-center gap-1">
              {c.Types?.map(t => (
                <TypeBadge key={t} type={t} className="scale-75" />
              ))}
            </div>
          ),
        });
      });

    // Search moves
    moves
      .filter(m =>
        m.Name.toLowerCase().includes(queryLower) ||
        m.Description?.toLowerCase().includes(queryLower) ||
        m.Type.toLowerCase().includes(queryLower)
      )
      .slice(0, 5)
      .forEach(m => {
        searchResults.push({
          type: 'move',
          id: m.Id,
          name: m.Name,
          description: m.Description,
          url: `/moves`,
          icon: '💥',
          metadata: (
            <div className="flex items-center gap-2 text-xs">
              <TypeBadge type={m.Type} className="scale-75" />
              <span>{m.BasePower || '-'} BP</span>
            </div>
          ),
        });
      });

    // Search items
    items
      .filter(i =>
        i.Name.toLowerCase().includes(queryLower) ||
        i.Description?.toLowerCase().includes(queryLower) ||
        i.Category.toLowerCase().includes(queryLower)
      )
      .slice(0, 5)
      .forEach(i => {
        searchResults.push({
          type: 'item',
          id: i.Id,
          name: i.Name,
          description: i.Description,
          url: `/items`,
          icon: '🎒',
          metadata: (
            <span className="text-xs text-slate-500">{i.Category}</span>
          ),
        });
      });

    // Search locations
    locations
      .filter(l =>
        l.Name.toLowerCase().includes(queryLower) ||
        l.Description?.toLowerCase().includes(queryLower) ||
        l.Parent?.toLowerCase().includes(queryLower)
      )
      .slice(0, 5)
      .forEach(l => {
        searchResults.push({
          type: 'location',
          id: l.Id,
          name: l.Name,
          description: l.Description,
          url: `/locations`,
          icon: '🗺️',
          metadata: l.Parent ? (
            <span className="text-xs text-slate-500">in {l.Parent}</span>
          ) : undefined,
        });
      });

    return searchResults.slice(0, 10); // Limit to 10 total results
  }, [query, creatures, moves, items, locations]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ctrl+K or Cmd+K to open search
      if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
        e.preventDefault();
        setIsOpen(true);
        setTimeout(() => inputRef.current?.focus(), 0);
      }

      // Escape to close
      if (e.key === 'Escape') {
        setIsOpen(false);
        setQuery('');
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

  // Handle keyboard navigation
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedIndex(prev => Math.min(prev + 1, results.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedIndex(prev => Math.max(prev - 1, 0));
      } else if (e.key === 'Enter' && results[selectedIndex]) {
        e.preventDefault();
        router.push(results[selectedIndex].url);
        setIsOpen(false);
        setQuery('');
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, selectedIndex, results, router]);

  // Close on outside click
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (searchRef.current && !searchRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      return () => document.removeEventListener('mousedown', handleClickOutside);
    }
  }, [isOpen]);

  // Reset selected index when results change
  useEffect(() => {
    setSelectedIndex(0);
  }, [results]);

  const handleResultClick = (url: string) => {
    router.push(url);
    setIsOpen(false);
    setQuery('');
  };

  return (
    <div ref={searchRef} className={`relative ${className}`}>
      {/* Search Button/Input */}
      <button
        onClick={() => setIsOpen(true)}
        className="w-full md:w-80 px-4 py-2 bg-white border-2 border-slate-300 rounded-lg shadow-sm hover:border-blue-400 transition-all flex items-center gap-2 text-left"
      >
        <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
        <span className="flex-1 text-slate-500">Search...</span>
        <kbd className="hidden md:inline-flex items-center px-2 py-1 text-xs font-semibold text-slate-500 bg-slate-100 border border-slate-300 rounded">
          Ctrl+K
        </kbd>
      </button>

      {/* Search Modal */}
      {isOpen && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-start justify-center pt-20 md:pt-32">
          <div className="w-full max-w-2xl mx-4 bg-white rounded-2xl shadow-2xl border-2 border-slate-200 overflow-hidden">
            {/* Search Input */}
            <div className="p-4 border-b-2 border-slate-200">
              <div className="relative">
                <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                  <svg className="h-5 w-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                  </svg>
                </div>
                <input
                  ref={inputRef}
                  type="text"
                  placeholder="Search creatures, moves, items, locations..."
                  className="w-full pl-10 pr-4 py-3 border-2 border-slate-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none text-lg"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  autoFocus
                />
              </div>
            </div>

            {/* Results */}
            <div className="max-h-96 overflow-y-auto">
              {results.length === 0 && query.trim() ? (
                <div className="p-8 text-center text-slate-500">
                  No results found for &quot;{query}&quot;
                </div>
              ) : results.length === 0 ? (
                <div className="p-8 text-center text-slate-500">
                  Start typing to search...
                </div>
              ) : (
                <div className="divide-y divide-slate-200">
                  {results.map((result, index) => (
                    <button
                      key={`${result.type}-${result.id}`}
                      onClick={() => handleResultClick(result.url)}
                      className={`w-full p-4 hover:bg-blue-50 transition-colors text-left ${
                        index === selectedIndex ? 'bg-blue-50' : ''
                      }`}
                      onMouseEnter={() => setSelectedIndex(index)}
                    >
                      <div className="flex items-start gap-3">
                        <div className="text-2xl flex-shrink-0">{result.icon}</div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            <span className="font-semibold text-slate-900">{result.name}</span>
                            <span className="text-xs px-2 py-0.5 bg-slate-100 text-slate-600 rounded uppercase">
                              {result.type}
                            </span>
                            {result.metadata}
                          </div>
                          {result.description && (
                            <p className="text-sm text-slate-600 line-clamp-1">{result.description}</p>
                          )}
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Footer */}
            <div className="p-3 border-t-2 border-slate-200 bg-slate-50 flex items-center justify-between text-xs text-slate-500">
              <div className="flex items-center gap-4">
                <div className="flex items-center gap-1">
                  <kbd className="px-1.5 py-0.5 bg-white border border-slate-300 rounded">↑</kbd>
                  <kbd className="px-1.5 py-0.5 bg-white border border-slate-300 rounded">↓</kbd>
                  <span>Navigate</span>
                </div>
                <div className="flex items-center gap-1">
                  <kbd className="px-1.5 py-0.5 bg-white border border-slate-300 rounded">Enter</kbd>
                  <span>Select</span>
                </div>
                <div className="flex items-center gap-1">
                  <kbd className="px-1.5 py-0.5 bg-white border border-slate-300 rounded">Esc</kbd>
                  <span>Close</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}


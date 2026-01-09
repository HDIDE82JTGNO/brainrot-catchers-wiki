"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import locationsData from '../../data/locations.json';
import { Location } from '@/types';
import { EncounterList } from '@/components/EncounterList';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';

const locations = locationsData as unknown as Location[];

// Type assertions for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;
const AnimatedSvg = animated.svg as any;

type SortOption = 'default' | 'name-asc' | 'name-desc' | 'has-encounters';

export default function LocationsPage() {
  const [search, setSearch] = useState('');
  const [filterParent, setFilterParent] = useState<string | null>(null);
  const [filterHasEncounters, setFilterHasEncounters] = useState<boolean | null>(null);
  const [sortBy, setSortBy] = useState<SortOption>('default');
  const [expandedGroups, setExpandedGroups] = useState<Set<string>>(new Set());

  // Get unique parent names for filtering
  const parentNames = useMemo(() => {
    const parents = new Set<string>();
    locations.forEach(loc => {
      if (loc.Parent) {
        parents.add(loc.Parent);
      }
    });
    return Array.from(parents).sort();
  }, []);

  // Group locations by parent
  const groupedLocations = useMemo(() => {
    const groups: { [key: string]: Location[] } = {};
    const mainLocations: Location[] = [];

    locations.forEach(loc => {
      if (loc.Parent) {
        if (!groups[loc.Parent]) {
          groups[loc.Parent] = [];
        }
        groups[loc.Parent].push(loc);
      } else {
        mainLocations.push(loc);
      }
    });

    return { main: mainLocations, groups };
  }, []);

  // Filter and sort locations
  const filteredLocations = useMemo(() => {
    let result = [...locations];

    // Apply search filter
    if (search) {
      const searchLower = search.toLowerCase();
      result = result.filter(loc =>
        loc.Name.toLowerCase().includes(searchLower) ||
        loc.Description?.toLowerCase().includes(searchLower) ||
        loc.Parent?.toLowerCase().includes(searchLower)
      );
    }

    // Apply parent filter
    if (filterParent) {
      result = result.filter(loc => loc.Parent === filterParent);
    }

    // Apply encounters filter
    if (filterHasEncounters !== null) {
      result = result.filter(loc =>
        filterHasEncounters
          ? loc.Encounters && loc.Encounters.length > 0
          : !loc.Encounters || loc.Encounters.length === 0
      );
    }

    // Apply sorting
    if (sortBy === 'name-asc') {
      result.sort((a, b) => a.Name.localeCompare(b.Name));
    } else if (sortBy === 'name-desc') {
      result.sort((a, b) => b.Name.localeCompare(a.Name));
    } else if (sortBy === 'has-encounters') {
      result.sort((a, b) => {
        const aHas = a.Encounters && a.Encounters.length > 0;
        const bHas = b.Encounters && b.Encounters.length > 0;
        if (aHas && !bHas) return -1;
        if (!aHas && bHas) return 1;
        return 0;
      });
    }
    // 'default' keeps the original order from JSON

    return result;
  }, [search, filterParent, filterHasEncounters, sortBy]);

  // Group filtered results
  const filteredGroups = useMemo(() => {
    const groups: { [key: string]: Location[] } = {};
    const main: Location[] = [];

    filteredLocations.forEach(loc => {
      if (loc.Parent) {
        if (!groups[loc.Parent]) {
          groups[loc.Parent] = [];
        }
        groups[loc.Parent].push(loc);
      } else {
        main.push(loc);
      }
    });

    return { main, groups };
  }, [filteredLocations]);

  const toggleGroup = (parentName: string) => {
    setExpandedGroups(prev => {
      const next = new Set(prev);
      if (next.has(parentName)) {
        next.delete(parentName);
      } else {
        next.add(parentName);
      }
      return next;
    });
  };

  const activeFilterCount = (search ? 1 : 0) + (filterParent ? 1 : 0) + (filterHasEncounters !== null ? 1 : 0);

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Locations
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>Explore the world map and discover where creatures hide.</p>
      </div>

      {/* Search and Filters */}
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
              placeholder="Search locations by name or description..."
              className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500 outline-none transition-all"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>

          {/* Sort */}
          <div className="relative">
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as SortOption)}
              className="w-full lg:w-48 appearance-none pl-4 pr-10 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500 outline-none bg-white text-slate-700 cursor-pointer"
            >
              <option value="default">Default Order</option>
              <option value="name-asc">Name (A-Z)</option>
              <option value="name-desc">Name (Z-A)</option>
              <option value="has-encounters">Has Encounters First</option>
            </select>
            <div className="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none text-slate-500">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            </div>
          </div>
        </div>

        {/* Filters */}
        <div className="flex flex-wrap gap-4 items-center">
          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold text-slate-700">Parent:</label>
            <select
              value={filterParent || ''}
              onChange={(e) => setFilterParent(e.target.value || null)}
              className="px-3 py-1.5 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500 outline-none bg-white"
            >
              <option value="">All Locations</option>
              {parentNames.map(parent => (
                <option key={parent} value={parent}>{parent}</option>
              ))}
            </select>
          </div>

          <div className="flex items-center gap-2">
            <label className="text-sm font-semibold text-slate-700">Encounters:</label>
            <select
              value={filterHasEncounters === null ? '' : filterHasEncounters ? 'yes' : 'no'}
              onChange={(e) => {
                const val = e.target.value;
                setFilterHasEncounters(val === '' ? null : val === 'yes');
              }}
              className="px-3 py-1.5 border border-slate-300 rounded-lg text-sm focus:ring-2 focus:ring-emerald-500 focus:border-emerald-500 outline-none bg-white"
            >
              <option value="">All</option>
              <option value="yes">Has Encounters</option>
              <option value="no">No Encounters</option>
            </select>
          </div>

          {activeFilterCount > 0 && (
            <button
              onClick={() => {
                setSearch('');
                setFilterParent(null);
                setFilterHasEncounters(null);
                setSortBy('default');
              }}
              className="text-sm text-red-600 hover:text-red-700 font-medium underline ml-auto"
            >
              Clear Filters ({activeFilterCount})
            </button>
          )}
        </div>
      </div>

      {/* Locations List */}
      {filteredLocations.length === 0 ? (
        <div className="bg-white rounded-2xl border-2 border-slate-200 p-12">
          <EmptyState 
            message="No locations found matching your filters."
            icon="🗺️"
          />
        </div>
      ) : (
        <div className="space-y-6">
          {/* Main Locations (no parent) */}
          {filteredGroups.main.map(loc => {
            const subLocations = filteredGroups.groups[loc.Name] || [];
            return (
              <LocationCard 
                key={loc.Id} 
                location={loc} 
                subLocations={subLocations.length > 0 ? subLocations : undefined}
                expandedGroups={expandedGroups}
                toggleGroup={toggleGroup}
              />
            );
          })}

          {/* Grouped Locations (with parent) - only show if parent doesn't exist as main location */}
          {Object.entries(filteredGroups.groups).map(([parentName, subLocations]) => {
            // Skip if this parent exists as a main location (already handled above)
            const parentExistsAsMain = filteredGroups.main.some(loc => loc.Name === parentName);
            if (parentExistsAsMain) return null;

            const isExpanded = expandedGroups.has(parentName);
            const groupSpring = useSpring({
              height: isExpanded ? 'auto' : 0,
              opacity: isExpanded ? 1 : 0,
              config: getSpringConfig('gentle'),
            });
            
            const iconSpring = useSpring({
              transform: isExpanded ? 'rotate(180deg)' : 'rotate(0deg)',
              config: getSpringConfig('snappy'),
            });

            return (
              <div key={parentName} className="bg-white rounded-2xl border-2 border-slate-200 shadow-lg overflow-hidden">
                <button
                  onClick={() => toggleGroup(parentName)}
                  className="w-full bg-white px-6 py-4 border-b-2 border-slate-100 hover:bg-white transition-colors flex items-center justify-between"
                >
                  <h2 className="text-xl font-bold text-slate-900">{parentName}</h2>
                  <div className="flex items-center gap-2">
                    <span className="text-sm text-slate-900">{subLocations.length} location{subLocations.length !== 1 ? 's' : ''}</span>
                    <AnimatedSvg
                      className="w-5 h-5 text-slate-900"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      style={{ transform: iconSpring.transform }}
                    >
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                    </AnimatedSvg>
                  </div>
                </button>
                <AnimatedDiv
                  style={{
                    height: groupSpring.height,
                    opacity: groupSpring.opacity,
                  }}
                  className="overflow-hidden"
                >
                  {isExpanded && (
                    <div className="p-6 space-y-4">
                      {subLocations.map(loc => (
                        <LocationCard key={loc.Id} location={loc} isSubLocation />
                      ))}
                    </div>
                  )}
                </AnimatedDiv>
              </div>
            );
          })}
        </div>
      )}

      {/* Summary */}
      <div className="text-center text-sm text-white">
        Showing {filteredLocations.length} of {locations.length} locations
      </div>
    </div>
  );
}

function LocationCard({ 
  location, 
  isSubLocation = false,
  subLocations,
  expandedGroups,
  toggleGroup
}: { 
  location: Location; 
  isSubLocation?: boolean;
  subLocations?: Location[];
  expandedGroups?: Set<string>;
  toggleGroup?: (name: string) => void;
}) {
  const hasEncounters = location.Encounters && location.Encounters.length > 0;
  const hasSubLocations = subLocations && subLocations.length > 0;
  const isExpanded = hasSubLocations && expandedGroups && expandedGroups.has(location.Name);

  const subLocationsSpring = useSpring({
    height: isExpanded ? 'auto' : 0,
    opacity: isExpanded ? 1 : 0,
    config: getSpringConfig('gentle'),
  });

  const iconSpring = useSpring({
    transform: isExpanded ? 'rotate(180deg)' : 'rotate(0deg)',
    config: getSpringConfig('snappy'),
  });

  return (
    <div className={`bg-white ${isSubLocation ? 'border border-slate-200 rounded-xl' : 'rounded-2xl border-2 border-slate-200'} shadow-lg hover:shadow-xl transition-all overflow-hidden card-hover`}>
      <div className={`bg-white px-6 py-5 ${hasSubLocations ? 'border-b-2 border-slate-100' : ''} flex flex-col sm:flex-row justify-between items-start sm:items-baseline gap-2`}>
        <div className="flex-1">
          <h2 className={`${isSubLocation ? 'text-xl' : 'text-2xl'} font-bold text-slate-900`}>
            {location.Name}
            {location.Parent && !isSubLocation && (
              <span className="ml-2 text-base font-normal text-slate-700">in {location.Parent}</span>
            )}
          </h2>
          {location.Description && (
            <p className="text-sm text-slate-800 mt-2">{location.Description}</p>
          )}
        </div>
        <div className="flex items-center gap-2">
          {hasSubLocations && toggleGroup && (
            <button
              onClick={() => toggleGroup(location.Name)}
              className="flex items-center gap-2 px-3 py-1.5 rounded-lg hover:bg-slate-50 transition-colors"
            >
              <span className="text-sm text-slate-600">{subLocations.length} location{subLocations.length !== 1 ? 's' : ''}</span>
              <AnimatedSvg
                className="w-4 h-4 text-slate-600"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                style={{ transform: iconSpring.transform }}
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </AnimatedSvg>
            </button>
          )}
          <span className="text-xs font-mono text-slate-900 bg-transparent px-2 py-1 rounded border border-slate-300">{location.Id}</span>
        </div>
      </div>

      {hasSubLocations && subLocations && (
        <AnimatedDiv
          style={{
            height: subLocationsSpring.height,
            opacity: subLocationsSpring.opacity,
          }}
          className="overflow-hidden border-b-2 border-slate-100"
        >
          {isExpanded && (
            <div className="p-6 space-y-4 bg-slate-50">
              {subLocations.map(loc => (
                <LocationCard key={loc.Id} location={loc} isSubLocation />
              ))}
            </div>
          )}
        </AnimatedDiv>
      )}

      {hasEncounters && (
        <div className="p-6">
          <div>
            <h3 className="text-sm font-bold text-slate-700 uppercase tracking-wider mb-4 flex items-center gap-2">
              <span className="w-1 h-5 bg-emerald-500 rounded-full"></span>
              Wild Encounters ({location.Encounters.length})
            </h3>
            <EncounterList encounters={location.Encounters} />
          </div>
        </div>
      )}
    </div>
  );
}

"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import naturesData from '../../data/natures.json';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';

const natures = naturesData as unknown as any[];

const AnimatedDiv = animated.div as any;

export default function NaturesPage() {
  const [search, setSearch] = useState('');

  const filteredNatures = useMemo(() => {
    if (!search) return natures;
    const searchLower = search.toLowerCase();
    return natures.filter(nature =>
      nature.Name.toLowerCase().includes(searchLower) ||
      nature.Increases.toLowerCase().includes(searchLower) ||
      nature.Decreases.toLowerCase().includes(searchLower)
    );
  }, [search]);

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(filteredNatures.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: { opacity: 1, transform: 'translateY(0px) scale(1)' },
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Natures
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Natures modify creature stats: +10% to one stat, -10% to another.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Search */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <svg className="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
              </svg>
            </div>
            <input
              type="text"
              placeholder="Search natures..."
              className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        {/* Natures Grid */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">
            Natures ({filteredNatures.length})
          </h2>
          
          {filteredNatures.length === 0 ? (
            <EmptyState 
              message={`No natures found matching "${search}"`}
              icon="🎭"
            />
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {trail.map((style, idx) => {
                const nature = filteredNatures[idx];
                if (!nature) return null;
                
                return (
                  <AnimatedDiv key={nature.Name} style={style}>
                    <div className={`border-2 rounded-xl p-4 transition-all ${
                      nature.IsNeutral 
                        ? 'border-slate-300 bg-slate-50' 
                        : 'border-slate-200 hover:border-blue-300 bg-white'
                    }`}>
                      <h3 className="text-lg font-bold text-slate-900 mb-3">{nature.Name}</h3>
                      {nature.IsNeutral ? (
                        <div className="text-sm text-slate-600">No stat changes</div>
                      ) : (
                        <div className="space-y-2">
                          <div className="flex items-center gap-2">
                            <span className="text-green-600 font-bold">+</span>
                            <span className="text-sm text-slate-700">{nature.Increases}</span>
                            <span className="text-xs text-green-600 font-bold">+10%</span>
                          </div>
                          <div className="flex items-center gap-2">
                            <span className="text-red-600 font-bold">-</span>
                            <span className="text-sm text-slate-700">{nature.Decreases}</span>
                            <span className="text-xs text-red-600 font-bold">-10%</span>
                          </div>
                        </div>
                      )}
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


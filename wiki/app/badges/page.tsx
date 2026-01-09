"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import badgesData from '../../data/badges.json';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';

const badges = badgesData as any[];

const AnimatedDiv = animated.div as any;

export default function BadgesPage() {
  const [search, setSearch] = useState('');

  const filteredBadges = useMemo(() => {
    if (!search) return badges;
    
    const searchLower = search.toLowerCase();
    return badges.filter(badge =>
      badge.Name.toLowerCase().includes(searchLower) ||
      badge.Number.toString().includes(searchLower)
    );
  }, [search]);

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(filteredBadges.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: { opacity: 1, transform: 'translateY(0px) scale(1)' },
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Badges
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Collection of badges earned through achievements and progression.
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
              placeholder="Search badges..."
              className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        {/* Badges List */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">
            Badges ({filteredBadges.length})
          </h2>
          
          {filteredBadges.length === 0 ? (
            <EmptyState 
              message={`No badges found${search ? ` matching "${search}"` : ''}`}
              icon="🏆"
            />
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              {trail.map((style, idx) => {
                const badge = filteredBadges[idx];
                if (!badge) return null;
                
                return (
                  <AnimatedDiv key={badge.Id} style={style}>
                    <div className="border-2 border-slate-200 rounded-xl p-5 hover:border-blue-300 transition-all text-center">
                      <div className="text-4xl mb-2">🏆</div>
                      <h3 className="text-lg font-bold text-slate-900 mb-1">{badge.Name}</h3>
                      <p className="text-sm text-slate-500">Badge #{badge.Number}</p>
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


"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import challengesData from '../../data/challenges.json';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';

const challenges = challengesData as any;

const AnimatedDiv = animated.div as any;

export default function ChallengesPage() {
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState<'all' | 'daily' | 'weekly'>('all');

  const filteredChallenges = useMemo(() => {
    let all: any[] = [];
    if (category === 'all' || category === 'daily') {
      all = [...all, ...(challenges.daily || []).map((c: any) => ({ ...c, Category: 'Daily' }))];
    }
    if (category === 'all' || category === 'weekly') {
      all = [...all, ...(challenges.weekly || []).map((c: any) => ({ ...c, Category: 'Weekly' }))];
    }
    
    if (search) {
      const searchLower = search.toLowerCase();
      all = all.filter(c =>
        c.Name.toLowerCase().includes(searchLower) ||
        c.Description.toLowerCase().includes(searchLower) ||
        c.Type.toLowerCase().includes(searchLower)
      );
    }
    
    return all;
  }, [search, category]);

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(filteredChallenges.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: { opacity: 1, transform: 'translateY(0px) scale(1)' },
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Challenges
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Daily and weekly challenges with rewards for completing objectives.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Filters */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <div className="flex flex-col lg:flex-row gap-4">
            <div className="flex gap-2">
              {(['all', 'daily', 'weekly'] as const).map(cat => (
                <button
                  key={cat}
                  onClick={() => setCategory(cat)}
                  className={`px-4 py-2 rounded-lg font-medium text-sm transition-all border-2 ${
                    category === cat
                      ? 'bg-blue-100 text-blue-700 border-blue-300'
                      : 'bg-white text-slate-600 border-slate-300 hover:border-blue-300'
                  }`}
                >
                  {cat === 'all' ? 'All' : cat === 'daily' ? 'Daily' : 'Weekly'}
                </button>
              ))}
            </div>
            <div className="relative flex-1">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <svg className="h-5 w-5 text-gray-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clipRule="evenodd" />
                </svg>
              </div>
              <input
                type="text"
                placeholder="Search challenges..."
                className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
          </div>
        </div>

        {/* Challenges List */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">
            Challenges ({filteredChallenges.length})
          </h2>
          
          {filteredChallenges.length === 0 ? (
            <EmptyState 
              message={`No challenges found${search ? ` matching "${search}"` : ''}`}
              icon="🎯"
            />
          ) : (
            <div className="space-y-4">
              {trail.map((style, idx) => {
                const challenge = filteredChallenges[idx];
                if (!challenge) return null;
                
                const rewardText = challenge.Reward?.Type === 'Item' 
                  ? `${challenge.Reward.Amount}x ${challenge.Reward.ItemName}`
                  : `${challenge.Reward?.Amount || 0} Studs`;
                
                return (
                  <AnimatedDiv key={challenge.Id} style={style}>
                    <div className="border-2 border-slate-200 rounded-xl p-5 hover:border-blue-300 transition-all">
                      <div className="flex items-start justify-between gap-4">
                        <div className="flex-1">
                          <div className="flex items-center gap-3 mb-2">
                            <h3 className="text-xl font-bold text-slate-900">{challenge.Name}</h3>
                            <span className={`px-2 py-1 rounded text-xs font-bold ${
                              challenge.Category === 'Daily' 
                                ? 'bg-blue-100 text-blue-700' 
                                : 'bg-purple-100 text-purple-700'
                            }`}>
                              {challenge.Category}
                            </span>
                          </div>
                          <p className="text-slate-600 mb-2">{challenge.Description}</p>
                          <div className="flex items-center gap-4 text-sm text-slate-500">
                            <span>Goal: {challenge.Goal}</span>
                            <span>Type: {challenge.Type}</span>
                          </div>
                        </div>
                        <div className="text-right">
                          <div className="text-xs font-semibold text-slate-500 uppercase mb-1">Reward</div>
                          <div className="px-3 py-2 bg-green-100 text-green-700 rounded-lg font-bold">
                            {rewardText}
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


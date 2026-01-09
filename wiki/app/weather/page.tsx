"use client";

import React, { useState, useMemo } from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import weatherData from '../../data/weather.json';
import { getSpringConfig } from '@/lib/springConfigs';
import { EmptyState } from '@/components/EmptyState';
import { TypeBadge } from '@/components/TypeBadge';

const weatherTypes = weatherData as unknown as any[];

const AnimatedDiv = animated.div as any;

export default function WeatherPage() {
  const [search, setSearch] = useState('');

  const filteredWeather = useMemo(() => {
    if (!search) return weatherTypes;
    const searchLower = search.toLowerCase();
    return weatherTypes.filter(weather =>
      weather.Name.toLowerCase().includes(searchLower) ||
      weather.Description.toLowerCase().includes(searchLower)
    );
  }, [search]);

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(filteredWeather.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: { opacity: 1, transform: 'translateY(0px) scale(1)' },
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Weather
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Weather conditions that affect spawn rates and battle mechanics.
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
              placeholder="Search weather..."
              className="w-full pl-10 pr-4 py-2 border border-slate-300 rounded-lg shadow-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-all"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        {/* Weather List */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-4">
            Weather Types ({filteredWeather.length})
          </h2>
          
          {filteredWeather.length === 0 ? (
            <EmptyState 
              message={`No weather types found matching "${search}"`}
              icon="☀️"
            />
          ) : (
            <div className="space-y-4">
              {trail.map((style, idx) => {
                const weather = filteredWeather[idx];
                if (!weather) return null;
                
                const spawnMods = weather.SpawnModifiers || {};
                const abilityMods = weather.AbilityModifiers || {};
                
                return (
                  <AnimatedDiv key={weather.Id} style={style}>
                    <div className="border-2 border-slate-200 rounded-xl p-5 hover:border-blue-300 transition-all">
                      <div className="flex items-start gap-4 mb-3">
                        <div className="text-4xl">🌤️</div>
                        <div className="flex-1">
                          <div className="flex items-center gap-3 mb-2">
                            <h3 className="text-2xl font-bold text-slate-900">{weather.Name}</h3>
                            <span className="px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-bold">
                              Weight: {weather.Weight}
                            </span>
                          </div>
                          <p className="text-slate-600">{weather.Description}</p>
                        </div>
                      </div>
                      
                      {Object.keys(spawnMods).length > 0 && (
                        <div className="mt-4 pt-4 border-t border-slate-200">
                          <div className="text-xs font-semibold text-slate-500 uppercase mb-2">
                            Spawn Modifiers
                          </div>
                          <div className="flex flex-wrap gap-2">
                            {Object.entries(spawnMods).map(([type, multiplier]: [string, any]) => (
                              <div key={type} className="flex items-center gap-1">
                                <TypeBadge type={type} className="scale-90" />
                                <span className={`text-xs font-bold ${multiplier > 1 ? 'text-green-600' : 'text-red-600'}`}>
                                  {multiplier > 1 ? '+' : ''}{((multiplier - 1) * 100).toFixed(0)}%
                                </span>
                              </div>
                            ))}
                          </div>
                        </div>
                      )}
                      
                      {Object.keys(abilityMods).length > 0 && (
                        <div className="mt-4 pt-4 border-t border-slate-200">
                          <div className="text-xs font-semibold text-slate-500 uppercase mb-2">
                            Battle Modifiers
                          </div>
                          <div className="flex flex-wrap gap-2">
                            {Object.entries(abilityMods).map(([type, multiplier]: [string, any]) => (
                              <div key={type} className="flex items-center gap-1">
                                <TypeBadge type={type} className="scale-90" />
                                <span className={`text-xs font-bold ${multiplier > 1 ? 'text-green-600' : 'text-red-600'}`}>
                                  {multiplier > 1 ? '+' : ''}{((multiplier - 1) * 100).toFixed(0)}%
                                </span>
                              </div>
                            ))}
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


"use client";

import React from 'react';
import { useSpring, animated, useTrail } from '@react-spring/web';
import badgesData from '../../data/badges.json';
import { getSpringConfig } from '@/lib/springConfigs';

const badges = badgesData as unknown as any[];

const AnimatedDiv = animated.div as any;

export default function BadgesPage() {
  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const trail = useTrail(badges.length, {
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
          Gym badges earned by defeating gym leaders. Collect all 8 to become a champion!
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-6">
          <h2 className="text-xl font-bold text-slate-900 mb-6">
            Gym Badges ({badges.length})
          </h2>
          
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-6">
            {trail.map((style, idx) => {
              const badge = badges[idx];
              if (!badge) return null;
              
              return (
                <AnimatedDiv key={badge.Id} style={style}>
                  <div className="text-center">
                    <div className="w-24 h-24 mx-auto mb-3 bg-slate-100 rounded-full flex items-center justify-center border-4 border-slate-300">
                      {badge.Image && badge.Image !== 'rbxassetid://0' ? (
                        <img 
                          src={badge.Image.replace('rbxassetid://', 'https://assetdelivery.roblox.com/v1/asset/?id=')} 
                          alt={badge.Name}
                          className="w-full h-full object-contain rounded-full"
                          onError={(e) => {
                            (e.target as HTMLImageElement).style.display = 'none';
                            (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden');
                          }}
                        />
                      ) : null}
                      <div className={`hidden text-3xl ${badge.Image && badge.Image !== 'rbxassetid://0' ? '' : ''}`}>
                        🏆
                      </div>
                    </div>
                    <h3 className="font-bold text-slate-900">{badge.Name}</h3>
                    <p className="text-sm text-slate-500">Badge #{badge.Number}</p>
                  </div>
                </AnimatedDiv>
              );
            })}
          </div>
        </div>
      </AnimatedDiv>
    </div>
  );
}


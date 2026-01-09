"use client";

import React, { useState, useEffect, useRef } from 'react';
import Image from 'next/image';
import { TypeBadge } from '@/components/TypeBadge';
import { StatRadar } from '@/components/StatRadar';
import { CaptureCalculator } from '@/components/CaptureCalculator';
import { EvolutionLine } from '@/components/EvolutionLine';
import Link from 'next/link';
import { getSpritePath } from '@/lib/spriteUtils';
import { extractAverageColor, ColorTheme, getDefaultTheme } from '@/lib/colorUtils';
import { buildEvolutionChain } from '@/lib/evolutionUtils';
import { Creature, Location, Ability } from '@/types';
import { FavoriteButton } from '@/components/FavoriteButton';
import { ShareButton } from '@/components/ShareButton';
import { shareCreature } from '@/lib/shareUtils';
import abilitiesData from '../../../data/abilities.json';

interface PageProps {
  creature: Creature;
  moves: any[];
  locations: Location[];
  allCreatures: Creature[];
}

const abilities = abilitiesData as unknown as Ability[];

// Client component for interactivity
function CreatureDetailClient({ creature, moves, locations, allCreatures }: PageProps) {
  const [isShiny, setIsShiny] = useState(false);
  const [theme, setTheme] = useState<ColorTheme>(getDefaultTheme());
  const [isLoadingTheme, setIsLoadingTheme] = useState(true);
  const imgRef = useRef<HTMLImageElement>(null);

  // Find locations
  const foundIn = locations.filter(loc => 
    loc.Encounters.some(enc => enc.Creature === creature.Name)
  );

  // Parse Learnset
  const learnsetEntries = creature.Learnset 
    ? Object.entries(creature.Learnset).map(([lvl, mvs]: [string, any]) => ({
        level: parseInt(lvl),
        moves: mvs
      })).sort((a, b) => a.level - b.level)
    : [];

  // Build evolution chain
  const evolutionChain = buildEvolutionChain(creature.Name, allCreatures);

  const spritePath = getSpritePath(creature.Name, isShiny);

  // Extract color theme from sprite
  useEffect(() => {
    setIsLoadingTheme(true);
    extractAverageColor(spritePath)
      .then((extractedTheme) => {
        setTheme(extractedTheme);
        setIsLoadingTheme(false);
      })
      .catch(() => {
        setTheme(getDefaultTheme());
        setIsLoadingTheme(false);
      });
  }, [spritePath]);

  return (
    <div className="max-w-6xl mx-auto animate-fade-in" style={{ '--theme-primary': theme.primary, '--theme-light': theme.light, '--theme-dark': theme.dark, '--theme-gradient': theme.gradient } as React.CSSProperties}>
        <div className="mb-6 flex items-center justify-between">
          <Link 
            href="/creatures" 
            className="inline-flex items-center gap-2 font-medium transition-colors px-4 py-2 hover:bg-white rounded-lg border border-transparent hover:border-slate-200"
            style={{ color: theme.dark }}
            onMouseEnter={(e) => e.currentTarget.style.color = theme.primary}
            onMouseLeave={(e) => e.currentTarget.style.color = theme.dark}
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 19l-7-7m0 0l7-7m-7 7h18" /></svg>
            Back to Dex
          </Link>
          <div className="flex items-center gap-2">
            <FavoriteButton
              type="creature"
              id={creature.Id}
              name={creature.Name}
            />
            <ShareButton
              url={shareCreature(creature.Name, isShiny)}
              title={`${creature.Name} - Brainrot Catchers Wiki`}
            />
          </div>
        </div>
        
        <div className="flex flex-col lg:flex-row gap-8">
            {/* Left Column: Info Card */}
            <div className="w-full lg:w-1/3 space-y-6">
                <div className="bg-white rounded-3xl border-2 shadow-xl overflow-hidden transition-all duration-300" style={{ borderColor: theme.light }}>
                    <div 
                      className="p-8 flex flex-col items-center justify-center border-b-2 relative transition-all duration-300"
                      style={{ background: theme.gradient, borderColor: theme.light }}
                    >
                        <div className="w-56 h-56 bg-white rounded-full flex items-center justify-center shadow-xl border-2 relative overflow-hidden transition-all duration-300" style={{ borderColor: theme.primary }}>
                            <Image
                              src={spritePath}
                              alt={`${creature.Name} Sprite`}
                              width={224}
                              height={224}
                              className="w-full h-full object-contain p-3 drop-shadow-lg"
                              style={{ imageRendering: 'pixelated' }}
                              priority
                              onError={(e) => {
                                (e.target as HTMLImageElement).style.display = 'none';
                                (e.target as HTMLImageElement).nextElementSibling?.classList.remove('hidden');
                              }}
                            />
                            <div className="hidden text-5xl text-slate-300">?</div>
                        </div>
                        
                        <button 
                          onClick={() => setIsShiny(!isShiny)}
                          className={`mt-6 px-5 py-2 rounded-xl text-sm font-bold uppercase tracking-wider transition-all border-2 shadow-md ${
                            isShiny 
                              ? 'bg-gradient-to-r from-yellow-100 to-yellow-200 text-yellow-700 border-yellow-300 hover:from-yellow-200 hover:to-yellow-300' 
                              : 'bg-white border-slate-300 hover:bg-slate-50'
                          }`}
                          style={!isShiny ? { color: theme.dark, borderColor: theme.primary } : {}}
                        >
                          {isShiny ? '✨ Shiny' : 'Normal'}
                        </button>
                    </div>
                    
                    <div className="p-6 text-center">
                        <div className="font-bold text-sm tracking-wider mb-2 transition-colors duration-300" style={{ color: theme.primary }}>#{String(creature.DexNumber).padStart(3, '0')}</div>
                        <h1 
                          className="text-4xl font-extrabold bg-clip-text text-transparent mb-4 transition-all duration-300"
                          style={{ backgroundImage: `linear-gradient(to right, ${theme.dark}, ${theme.primary})` }}
                        >
                          {creature.Name}
                        </h1>
                        <div className="flex justify-center gap-2 mb-6">
                             {creature.Types && creature.Types.map(t => <TypeBadge key={t} type={t} />)}
                        </div>
                        <p 
                          className="italic leading-relaxed text-sm p-5 rounded-xl border-2 transition-all duration-300"
                          style={{ 
                            color: theme.dark, 
                            background: theme.light,
                            borderColor: theme.light
                          }}
                        >
                          {creature.Description}
                        </p>
                    </div>

                    <div className="px-6 pb-6">
                        <div className="grid grid-cols-2 gap-4 text-sm">
                            <div 
                              className="p-4 rounded-xl border-2 shadow-sm transition-all duration-300"
                              style={{ 
                                background: `linear-gradient(to bottom right, ${theme.light}, white)`,
                                borderColor: theme.light
                              }}
                            >
                              <span className="block text-xs font-bold uppercase mb-1 transition-colors duration-300" style={{ color: theme.primary }}>Weight</span>
                              <span className="font-bold text-lg transition-colors duration-300" style={{ color: theme.dark }}>{creature.BaseWeightKg} kg</span>
                            </div>
                            <div 
                              className="p-4 rounded-xl border-2 shadow-sm transition-all duration-300"
                              style={{ 
                                background: `linear-gradient(to bottom right, ${theme.light}, white)`,
                                borderColor: theme.light
                              }}
                            >
                              <span className="block text-xs font-bold uppercase mb-1 transition-colors duration-300" style={{ color: theme.primary }}>Female Ratio</span>
                              <span className="font-bold text-lg transition-colors duration-300" style={{ color: theme.dark }}>{creature.FemaleChance}%</span>
                            </div>
                            {creature.EvolvesInto && (
                                <div 
                                  className="p-4 rounded-xl border-2 col-span-2 shadow-sm transition-all duration-300"
                                  style={{ 
                                    background: `linear-gradient(to bottom right, ${theme.light}, ${theme.primary}15)`,
                                    borderColor: theme.primary
                                  }}
                                >
                                  <span className="block text-xs font-bold uppercase mb-1 transition-colors duration-300" style={{ color: theme.primary }}>Evolves Into</span>
                                  <Link 
                                    href={`/creatures/${creature.EvolvesInto}`} 
                                    className="font-bold hover:underline block text-lg transition-colors duration-300"
                                    style={{ color: theme.primary }}
                                    onMouseEnter={(e) => e.currentTarget.style.color = theme.dark}
                                    onMouseLeave={(e) => e.currentTarget.style.color = theme.primary}
                                  >
                                      {creature.EvolvesInto}
                                  </Link>
                                  <span className="text-xs transition-colors duration-300" style={{ color: theme.primary }}>at level {creature.EvolutionLevel}</span>
                                </div>
                            )}
                        </div>
                    </div>
                </div>

                {evolutionChain.length > 1 && (
                  <EvolutionLine
                    evolutionChain={evolutionChain}
                    currentCreatureName={creature.Name}
                    theme={theme}
                    isShiny={isShiny}
                  />
                )}

                <CaptureCalculator catchRate={creature.CatchRateScalar || 45} />
            </div>

            {/* Right Column: Stats & Data */}
            <div className="w-full lg:w-2/3 space-y-6">
                <div className="bg-white p-6 rounded-3xl border-2 shadow-xl transition-all duration-300" style={{ borderColor: theme.light }}>
                    <h3 className="text-xl font-bold mb-6 flex items-center gap-3 transition-colors duration-300" style={{ color: theme.dark }}>
                      <span className="w-1.5 h-8 rounded-full transition-all duration-300" style={{ background: theme.gradient }}></span>
                      Base Stats
                    </h3>
                    <StatRadar stats={creature.BaseStats} />
                </div>

                {creature.Abilities && creature.Abilities.length > 0 && (
                  <div className="bg-white p-6 rounded-3xl border-2 shadow-xl transition-all duration-300" style={{ borderColor: theme.light }}>
                    <h3 className="text-xl font-bold mb-6 flex items-center gap-3 transition-colors duration-300" style={{ color: theme.dark }}>
                      <span className="w-1.5 h-8 rounded-full transition-all duration-300" style={{ background: theme.gradient }}></span>
                      Abilities
                    </h3>
                    <div className="space-y-4">
                      {creature.Abilities.map((abilityEntry, idx) => {
                        const ability = abilities.find(a => a.Name === abilityEntry.Name);
                        return (
                          <div
                            key={idx}
                            className="p-4 rounded-xl border-2 transition-all duration-300"
                            style={{
                              background: `linear-gradient(to bottom right, ${theme.light}, ${theme.primary}15)`,
                              borderColor: theme.light
                            }}
                          >
                            <div className="flex items-start justify-between mb-2">
                              <div>
                                <Link
                                  href={`/abilities`}
                                  className="font-bold text-lg hover:underline transition-colors duration-300"
                                  style={{ color: theme.primary }}
                                  onMouseEnter={(e) => e.currentTarget.style.color = theme.dark}
                                  onMouseLeave={(e) => e.currentTarget.style.color = theme.primary}
                                >
                                  {abilityEntry.Name}
                                </Link>
                                {ability && (
                                  <span className="ml-2 px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-bold">
                                    {ability.TriggerType}
                                  </span>
                                )}
                              </div>
                              <span
                                className="text-sm font-bold px-2 py-1 rounded transition-colors duration-300"
                                style={{
                                  color: theme.primary,
                                  background: theme.light
                                }}
                              >
                                {abilityEntry.Chance}%
                              </span>
                            </div>
                            {ability && (
                              <p className="text-sm text-slate-600 mt-2">{ability.Description}</p>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  </div>
                )}

                <div className="bg-white p-6 rounded-3xl border-2 shadow-xl transition-all duration-300" style={{ borderColor: theme.light }}>
                    <h3 className="text-xl font-bold mb-6 flex items-center gap-3 transition-colors duration-300" style={{ color: theme.dark }}>
                      <span className="w-1.5 h-8 rounded-full transition-all duration-300" style={{ background: theme.gradient }}></span>
                      Locations
                    </h3>
                    {foundIn.length > 0 ? (
                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                          {foundIn.map(loc => {
                              const encounter = loc.Encounters.find(e => e.Creature === creature.Name);
                              return (
                                <Link 
                                  href="/locations" 
                                  key={loc.Id} 
                                  className="flex justify-between items-center p-4 rounded-xl transition-all border-2 shadow-sm hover:shadow-md card-hover"
                                  style={{ 
                                    background: `linear-gradient(to bottom right, ${theme.light}, ${theme.primary}15)`,
                                    borderColor: theme.light
                                  }}
                                  onMouseEnter={(e) => {
                                    e.currentTarget.style.background = `linear-gradient(to bottom right, ${theme.primary}20, ${theme.primary}30)`;
                                    e.currentTarget.style.borderColor = theme.primary;
                                  }}
                                  onMouseLeave={(e) => {
                                    e.currentTarget.style.background = `linear-gradient(to bottom right, ${theme.light}, ${theme.primary}15)`;
                                    e.currentTarget.style.borderColor = theme.light;
                                  }}
                                >
                                    <span className="font-semibold transition-colors duration-300" style={{ color: theme.dark }}>{loc.Name}</span>
                                    <span 
                                      className="text-sm font-bold bg-white px-3 py-1.5 rounded-lg border-2 shadow-sm transition-all duration-300"
                                      style={{ 
                                        color: theme.primary,
                                        borderColor: theme.primary
                                      }}
                                    >
                                        {encounter?.Chance}%
                                    </span>
                                </Link>
                              )
                          })}
                      </div>
                    ) : (
                      <p 
                        className="italic p-4 rounded-xl border transition-all duration-300"
                        style={{ 
                          color: theme.dark,
                          background: theme.light,
                          borderColor: theme.light
                        }}
                      >
                        This creature has not been spotted in the wild.
                      </p>
                    )}
                </div>

                <div className="bg-white p-6 rounded-3xl border-2 shadow-xl transition-all duration-300" style={{ borderColor: theme.light }}>
                    <h3 className="text-xl font-bold mb-6 flex items-center gap-3 transition-colors duration-300" style={{ color: theme.dark }}>
                      <span className="w-1.5 h-8 rounded-full transition-all duration-300" style={{ background: theme.gradient }}></span>
                      Learnset
                    </h3>
                    {learnsetEntries.length > 0 ? (
                        <div className="overflow-x-auto rounded-xl border-2 transition-all duration-300" style={{ borderColor: theme.light }}>
                          <table className="min-w-full text-sm">
                              <thead>
                                  <tr 
                                    className="uppercase tracking-wider text-xs border-b-2 transition-all duration-300"
                                    style={{ 
                                      background: `linear-gradient(to right, ${theme.light}, ${theme.primary}20)`,
                                      color: theme.dark,
                                      borderColor: theme.primary
                                    }}
                                  >
                                      <th className="py-4 px-5 text-left font-bold w-20">Level</th>
                                      <th className="py-4 px-5 text-left font-bold">Move</th>
                                      <th className="py-4 px-5 text-left font-bold">Type</th>
                                      <th className="py-4 px-5 text-left font-bold">Power</th>
                                      <th className="py-4 px-5 text-left font-bold">Acc</th>
                                  </tr>
                              </thead>
                              <tbody className="divide-y transition-colors duration-300" style={{ '--tw-divide-opacity': '0.3', borderColor: `${theme.light}` } as React.CSSProperties}>
                                  {learnsetEntries.map((entry: any) => (
                                      entry.moves.map((moveName: string) => {
                                          const move = moves.find((m: any) => m.Name === moveName);
                                          return (
                                              <tr 
                                                key={`${entry.level}-${moveName}`} 
                                                className="transition-colors"
                                                style={{ '--hover-bg': `${theme.light}80` } as React.CSSProperties}
                                                onMouseEnter={(e) => e.currentTarget.style.backgroundColor = `${theme.light}80`}
                                                onMouseLeave={(e) => e.currentTarget.style.backgroundColor = 'transparent'}
                                              >
                                                  <td className="py-4 px-5 font-bold transition-colors duration-300" style={{ color: theme.dark }}>{entry.level}</td>
                                                  <td className="py-4 px-5 font-semibold transition-colors duration-300" style={{ color: theme.dark }}>{moveName}</td>
                                                  <td className="py-4 px-5">
                                                      {move && <TypeBadge type={move.Type} className="scale-90 origin-left" />}
                                                  </td>
                                                  <td className="py-4 px-5 font-medium transition-colors duration-300" style={{ color: theme.dark }}>{move?.BasePower || '-'}</td>
                                                  <td className="py-4 px-5 font-medium transition-colors duration-300" style={{ color: theme.dark }}>{move?.Accuracy || '-'}</td>
                                              </tr>
                                          );
                                      })
                                  ))}
                              </tbody>
                          </table>
                        </div>
                    ) : (
                        <p 
                          className="italic p-4 rounded-xl border transition-all duration-300"
                          style={{ 
                            color: theme.dark,
                            background: theme.light,
                            borderColor: theme.light
                          }}
                        >
                          No moves learned by level up.
                        </p>
                    )}
                </div>
            </div>
        </div>
    </div>
  );
}

// Server component to fetch data
import creaturesData from '../../../data/creatures.json';
import movesData from '../../../data/moves.json';
import locationsData from '../../../data/locations.json';

export default async function CreatureDetail({ params }: { params: Promise<{ name: string }> }) {
  const { name } = await params;
  const decodedName = decodeURIComponent(name);
  
  const creature = (creaturesData as any[]).find(c => c.Name === decodedName);
  
  if (!creature) {
    return <div className="p-8">Creature not found: {decodedName}</div>;
  }

  return (
    <CreatureDetailClient 
      creature={creature} 
      moves={movesData as any[]} 
      locations={locationsData as any[]}
      allCreatures={creaturesData as any[]}
    />
  );
}

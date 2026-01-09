"use client";

import React, { useState, useEffect } from 'react';
import { getFavorites, getFavoritesByType, Favorite, FavoriteType } from '@/lib/favorites';
import { TypeBadge } from '@/components/TypeBadge';
import { getSpritePath } from '@/lib/spriteUtils';
import Image from 'next/image';
import Link from 'next/link';
import creaturesData from '../../data/creatures.json';
import movesData from '../../data/moves.json';
import itemsData from '../../data/items.json';
import locationsData from '../../data/locations.json';
import { Creature, Move, Item, Location } from '@/types';
import { getSpringConfig } from '@/lib/springConfigs';
import { useSpring, animated } from '@react-spring/web';
import { FavoriteButton } from '@/components/FavoriteButton';

const creatures = creaturesData as unknown as Creature[];
const moves = movesData as unknown as Move[];
const items = itemsData as unknown as Item[];
const locations = locationsData as unknown as Location[];

const AnimatedDiv = animated.div as any;

export default function FavoritesPage() {
  const [favorites, setFavorites] = useState<Favorite[]>([]);
  const [selectedType, setSelectedType] = useState<FavoriteType | 'all'>('all');

  useEffect(() => {
    const loadFavorites = () => {
      setFavorites(getFavorites());
    };
    
    loadFavorites();
    // Listen for storage changes (from other tabs)
    window.addEventListener('storage', loadFavorites);
    // Poll for changes (from same tab)
    const interval = setInterval(loadFavorites, 500);
    
    return () => {
      window.removeEventListener('storage', loadFavorites);
      clearInterval(interval);
    };
  }, []);

  const displayedFavorites = selectedType === 'all'
    ? favorites
    : getFavoritesByType(selectedType);

  const fadeIn = useSpring({
    to: { opacity: 1, transform: 'translateY(0px)' },
    config: getSpringConfig('gentle'),
  });

  const getFavoriteData = (favorite: Favorite) => {
    switch (favorite.type) {
      case 'creature':
        return creatures.find(c => c.Id === favorite.id);
      case 'move':
        return moves.find(m => m.Id === favorite.id);
      case 'item':
        return items.find(i => i.Id === favorite.id);
      case 'location':
        return locations.find(l => l.Id === favorite.id);
      default:
        return null;
    }
  };

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Favorites
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          Your saved creatures, moves, items, and locations.
        </p>
      </div>

      <AnimatedDiv style={fadeIn} className="space-y-6">
        {/* Filter Tabs */}
        <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-4">
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => setSelectedType('all')}
              className={`px-4 py-2 rounded-lg font-medium transition-all ${
                selectedType === 'all'
                  ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                  : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
              }`}
            >
              All ({favorites.length})
            </button>
            <button
              onClick={() => setSelectedType('creature')}
              className={`px-4 py-2 rounded-lg font-medium transition-all ${
                selectedType === 'creature'
                  ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                  : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
              }`}
            >
              Creatures ({getFavoritesByType('creature').length})
            </button>
            <button
              onClick={() => setSelectedType('move')}
              className={`px-4 py-2 rounded-lg font-medium transition-all ${
                selectedType === 'move'
                  ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                  : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
              }`}
            >
              Moves ({getFavoritesByType('move').length})
            </button>
            <button
              onClick={() => setSelectedType('item')}
              className={`px-4 py-2 rounded-lg font-medium transition-all ${
                selectedType === 'item'
                  ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                  : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
              }`}
            >
              Items ({getFavoritesByType('item').length})
            </button>
            <button
              onClick={() => setSelectedType('location')}
              className={`px-4 py-2 rounded-lg font-medium transition-all ${
                selectedType === 'location'
                  ? 'bg-blue-100 text-blue-700 border-2 border-blue-300'
                  : 'bg-slate-100 text-slate-600 border-2 border-slate-300 hover:border-blue-300'
              }`}
            >
              Locations ({getFavoritesByType('location').length})
            </button>
          </div>
        </div>

        {/* Favorites List */}
        {displayedFavorites.length === 0 ? (
          <div className="bg-white rounded-2xl border-2 border-slate-200 shadow-xl p-12 text-center">
            <p className="text-slate-500 mb-2">No favorites yet</p>
            <p className="text-sm text-slate-400">Start adding favorites by clicking the star icon on any page</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {displayedFavorites.map(favorite => {
              const data = getFavoriteData(favorite);
              if (!data) return null;

              let url = '';
              let icon = '';
              let content: React.ReactNode = null;

              switch (favorite.type) {
                case 'creature':
                  url = `/creatures/${encodeURIComponent(favorite.name)}`;
                  icon = '👾';
                  const creature = data as Creature;
                  content = (
                    <Link href={url} className="block">
                      <div className="aspect-square bg-gradient-to-br from-slate-50 to-slate-100 rounded-lg flex items-center justify-center mb-2 border-2 border-slate-200">
                        <Image
                          src={getSpritePath(creature.Name, false)}
                          alt={creature.Name}
                          width={128}
                          height={128}
                          className="w-3/4 h-3/4 object-contain"
                          style={{ imageRendering: 'pixelated' }}
                        />
                      </div>
                      <div className="font-bold text-slate-900 mb-1">{creature.Name}</div>
                      <div className="flex gap-1">
                        {creature.Types?.map(t => (
                          <TypeBadge key={t} type={t} className="scale-75" />
                        ))}
                      </div>
                    </Link>
                  );
                  break;
                case 'move':
                  url = '/moves';
                  icon = '💥';
                  const move = data as Move;
                  content = (
                    <Link href={url} className="block">
                      <div className="text-4xl mb-2">{icon}</div>
                      <div className="font-bold text-slate-900 mb-1">{move.Name}</div>
                      <div className="flex items-center gap-2">
                        <TypeBadge type={move.Type} className="scale-75" />
                        <span className="text-xs text-slate-500">{move.BasePower || '-'} BP</span>
                      </div>
                    </Link>
                  );
                  break;
                case 'item':
                  url = '/items';
                  icon = '🎒';
                  const item = data as Item;
                  content = (
                    <Link href={url} className="block">
                      <div className="text-4xl mb-2">{icon}</div>
                      <div className="font-bold text-slate-900 mb-1">{item.Name}</div>
                      <div className="text-xs text-slate-500">{item.Category}</div>
                    </Link>
                  );
                  break;
                case 'location':
                  url = '/locations';
                  icon = '🗺️';
                  const location = data as Location;
                  content = (
                    <Link href={url} className="block">
                      <div className="text-4xl mb-2">{icon}</div>
                      <div className="font-bold text-slate-900 mb-1">{location.Name}</div>
                      {location.Parent && (
                        <div className="text-xs text-slate-500">in {location.Parent}</div>
                      )}
                    </Link>
                  );
                  break;
              }

              return (
                <div
                  key={`${favorite.type}-${favorite.id}`}
                  className="bg-white rounded-xl border-2 border-slate-200 shadow-lg p-4 hover:shadow-xl transition-all relative"
                >
                  <div className="absolute top-2 right-2">
                    <FavoriteButton
                      type={favorite.type}
                      id={favorite.id}
                      name={favorite.name}
                    />
                  </div>
                  {content}
                </div>
              );
            })}
          </div>
        )}
      </AnimatedDiv>
    </div>
  );
}


"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTrail, animated } from "@react-spring/web";
import { getSpringConfig } from "@/lib/springConfigs";

// Dynamically import data files
const loadData = async () => {
  const [creaturesData, itemsData, movesData, locationsData, abilitiesData, weatherData] = await Promise.all([
    import("../data/creatures.json"),
    import("../data/items.json"),
    import("../data/moves.json"),
    import("../data/locations.json"),
    import("../data/abilities.json").catch(() => ({ default: [] })),
    import("../data/weather.json").catch(() => ({ default: [] }))
  ]);
  return {
    creatures: creaturesData.default,
    items: itemsData.default,
    moves: movesData.default,
    locations: locationsData.default,
    abilities: abilitiesData.default,
    weather: weatherData.default
  };
};

// Type assertion for react-spring animated components with React 19
const AnimatedDiv = animated.div as any;

export default function Home() {
  const pathname = usePathname();
  const [isMounted, setIsMounted] = useState(false);
  const [data, setData] = useState<{
    creatures: any[];
    items: any[];
    moves: any[];
    locations: any[];
    abilities?: any[];
    weather?: any[];
  } | null>(null);
  const prevPathnameRef = React.useRef(pathname);
  
  useEffect(() => {
    loadData().then(setData);
  }, []);

  // Set mounted to true once data is loaded
  useEffect(() => {
    if (data) {
      setIsMounted(true);
    }
  }, [data]);

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

  const cards = data ? [
    { 
      title: "Creatures", 
      count: data.creatures.length, 
      href: "/creatures", 
      description: "Browse the complete Dex. Stats, evolutions, move pools, and capture rates.", 
      icon: "👾",
      gradient: "from-cyan-600 to-blue-600",
      hoverBorder: "hover:border-cyan-400",
      hoverText: "group-hover:text-cyan-600"
    },
    { 
      title: "Abilities", 
      count: data.abilities?.length || 0, 
      href: "/abilities", 
      description: "Complete database of creature abilities with descriptions and battle effects.", 
      icon: "✨",
      gradient: "from-purple-600 to-indigo-600",
      hoverBorder: "hover:border-purple-400",
      hoverText: "group-hover:text-purple-600"
    },
    { 
      title: "Moves", 
      count: data.moves.length, 
      href: "/moves", 
      description: "Master the battle system with detailed move data, power, accuracy, and effects.", 
      icon: "💥",
      gradient: "from-red-600 to-pink-600",
      hoverBorder: "hover:border-red-400",
      hoverText: "group-hover:text-red-600"
    },
    { 
      title: "Items", 
      count: data.items.length, 
      href: "/items", 
      description: "Find capture cubes, healing items, held equipment, and move learners.", 
      icon: "🎒",
      gradient: "from-amber-600 to-orange-600",
      hoverBorder: "hover:border-amber-400",
      hoverText: "group-hover:text-amber-600"
    },
    { 
      title: "Locations", 
      count: data.locations.length, 
      href: "/locations", 
      description: "Explore the world map, spawn tables, encounter rates, and sub-areas.", 
      icon: "🗺️",
      gradient: "from-emerald-600 to-green-600",
      hoverBorder: "hover:border-emerald-400",
      hoverText: "group-hover:text-emerald-600"
    },
    { 
      title: "Weather", 
      count: data.weather?.length || 0, 
      href: "/weather", 
      description: "Weather conditions that affect spawn rates and battle mechanics.", 
      icon: "☀️",
      gradient: "from-yellow-600 to-orange-600",
      hoverBorder: "hover:border-yellow-400",
      hoverText: "group-hover:text-yellow-600"
    },
  ] : [];

  const trail = useTrail(cards.length, {
    from: { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    to: isMounted ? { opacity: 1, transform: 'translateY(0px) scale(1)' } : { opacity: 0, transform: 'translateY(20px) scale(0.95)' },
    config: getSpringConfig('snappy'),
  });

  return (
    <div className="space-y-6">
      {/* Header Section */}
      <div className="text-center">
        <h1 className="text-4xl md:text-5xl font-extrabold text-white mb-3" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)', WebkitTextFillColor: 'white', color: 'white', background: 'none', WebkitBackgroundClip: 'unset', backgroundClip: 'unset' }}>
          Brainrot Catchers Wiki
        </h1>
        <p className="text-lg text-white max-w-2xl mx-auto" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>
          The ultimate database for creatures, items, moves, and locations. Everything you need to master the game.
        </p>
      </div>

      {/* Stats Overview Card */}
      {data && (
        <div className="bg-white rounded-2xl shadow-xl border-2 border-slate-200 p-6">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="text-center">
              <div className="text-3xl mb-2">👾</div>
              <div className="text-2xl font-bold text-slate-900">{data.creatures.length}</div>
              <div className="text-sm text-slate-600">Creatures</div>
            </div>
            <div className="text-center">
              <div className="text-3xl mb-2">🎒</div>
              <div className="text-2xl font-bold text-slate-900">{data.items.length}</div>
              <div className="text-sm text-slate-600">Items</div>
            </div>
            <div className="text-center">
              <div className="text-3xl mb-2">💥</div>
              <div className="text-2xl font-bold text-slate-900">{data.moves.length}</div>
              <div className="text-sm text-slate-600">Moves</div>
            </div>
            <div className="text-center">
              <div className="text-3xl mb-2">🗺️</div>
              <div className="text-2xl font-bold text-slate-900">{data.locations.length}</div>
              <div className="text-sm text-slate-600">Locations</div>
            </div>
          </div>
        </div>
      )}

      {/* Category Cards */}
      <div>
        <h2 className="text-2xl font-bold text-white mb-4 text-center" style={{ textShadow: '0 1px 2px rgba(0, 0, 0, 0.3)' }}>Explore the Database</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {trail.map((style, index) => {
            const card = cards[index];
            if (!card) return null;
            
            return (
              <AnimatedDiv key={card.title} style={style}>
                <Link 
                  href={card.href} 
                  className={`group block bg-white rounded-2xl border-2 border-slate-200 shadow-lg hover:shadow-xl ${card.hoverBorder} transition-all duration-300 overflow-hidden card-hover p-6`}
                >
                  <div className="flex items-start justify-between mb-4">
                    <div className="text-5xl">{card.icon}</div>
                    <div className={`text-xs font-bold text-white bg-gradient-to-r ${card.gradient} px-3 py-1.5 rounded-full shadow-sm`}>
                      {card.count} Entries
                    </div>
                  </div>
                  <h3 className={`text-2xl font-bold text-slate-900 mb-2 ${card.hoverText} transition-colors`}>
                    {card.title}
                  </h3>
                  <p className="text-slate-600 text-sm leading-relaxed">
                    {card.description}
                  </p>
                </Link>
              </AnimatedDiv>
            );
          })}
        </div>
      </div>
    </div>
  );
}

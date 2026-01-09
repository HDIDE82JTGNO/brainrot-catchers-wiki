"use client";

import React, { useState, memo } from 'react';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';

// Type assertion for react-spring animated components with React 19
const AnimatedSpan = animated.span as any;

const TYPE_COLORS: { [key: string]: string } = {
  Normal: 'bg-gray-400',
  Fire: 'bg-red-500',
  Water: 'bg-blue-500',
  Electric: 'bg-yellow-400',
  Grass: 'bg-green-500',
  Ice: 'bg-cyan-300',
  Fighting: 'bg-red-700',
  Poison: 'bg-purple-500',
  Ground: 'bg-yellow-600',
  Flying: 'bg-indigo-300',
  Psychic: 'bg-pink-500',
  Bug: 'bg-lime-500',
  Rock: 'bg-yellow-800',
  Ghost: 'bg-purple-800',
  Dragon: 'bg-indigo-600',
  Steel: 'bg-gray-500',
  Dark: 'bg-gray-800',
  Fairy: 'bg-pink-300',
};

interface TypeBadgeProps {
  type: string;
  className?: string;
  isActive?: boolean;
}

export const TypeBadge = memo(function TypeBadge({ type, className = '', isActive = false }: TypeBadgeProps) {
  const [isHovered, setIsHovered] = useState(false);
  const colorClass = TYPE_COLORS[type] || 'bg-gray-500';
  
  const spring = useSpring({
    transform: isHovered ? 'scale(1.1)' : isActive ? 'scale(1.05)' : 'scale(1)',
    boxShadow: isHovered 
      ? '0 4px 8px rgba(0, 0, 0, 0.2)' 
      : isActive 
        ? '0 2px 4px rgba(0, 0, 0, 0.15)' 
        : '0 0 0 rgba(0, 0, 0, 0)',
    config: getSpringConfig('snappy'),
  });

  const pulseSpring = useSpring({
    opacity: isActive ? [0.8, 1, 0.8] : 1,
    config: { duration: 1500 },
    loop: isActive,
  });
  
  return (
    <AnimatedSpan 
      className={`px-2 py-1 rounded text-white text-xs font-bold uppercase cursor-default ${colorClass} ${className}`}
      style={{
        transform: spring.transform,
        boxShadow: spring.boxShadow,
        opacity: pulseSpring.opacity,
      } as unknown as React.CSSProperties}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      {type}
    </AnimatedSpan>
  );
});


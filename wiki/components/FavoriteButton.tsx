"use client";

import React, { useState, useEffect } from 'react';
import { isFavorited, toggleFavorite, FavoriteType } from '@/lib/favorites';
import { useSpring, animated } from '@react-spring/web';
import { getSpringConfig } from '@/lib/springConfigs';

const AnimatedSvg = animated.svg as any;

interface FavoriteButtonProps {
  type: FavoriteType;
  id: string;
  name: string;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
}

export function FavoriteButton({ type, id, name, className = '', size = 'md' }: FavoriteButtonProps) {
  const [favorited, setFavorited] = useState(false);

  useEffect(() => {
    setFavorited(isFavorited(type, id));
  }, [type, id]);

  const handleClick = (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    const newState = toggleFavorite(type, id, name);
    setFavorited(newState);
  };

  const scaleSpring = useSpring({
    transform: favorited ? 'scale(1.2)' : 'scale(1)',
    config: getSpringConfig('snappy'),
  });

  const sizeClasses = {
    sm: 'w-4 h-4',
    md: 'w-5 h-5',
    lg: 'w-6 h-6',
  };

  return (
    <button
      onClick={handleClick}
      className={`transition-colors ${className}`}
      title={favorited ? 'Remove from favorites' : 'Add to favorites'}
    >
      <AnimatedSvg
        className={sizeClasses[size]}
        style={scaleSpring}
        fill={favorited ? 'currentColor' : 'none'}
        stroke="currentColor"
        viewBox="0 0 24 24"
        color={favorited ? '#fbbf24' : '#64748b'}
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth={2}
          d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"
        />
      </AnimatedSvg>
    </button>
  );
}


/**
 * Animation utilities and helpers
 * Provides common animation patterns and utilities
 */

import { SpringConfig } from '@react-spring/web';
import { getSpringConfig } from './springConfigs';

/**
 * Common animation values for consistent timing
 */
export const animationTimings = {
  fast: 150,
  normal: 300,
  slow: 500,
};

/**
 * Stagger delay calculation for trail animations
 */
export const getStaggerDelay = (index: number, baseDelay: number = 50): number => {
  return index * baseDelay;
};

/**
 * Common transform values for animations
 */
export const transforms = {
  fadeIn: {
    from: { opacity: 0 },
    to: { opacity: 1 },
  },
  slideUp: {
    from: { opacity: 0, transform: 'translateY(20px)' },
    to: { opacity: 1, transform: 'translateY(0px)' },
  },
  slideDown: {
    from: { opacity: 0, transform: 'translateY(-20px)' },
    to: { opacity: 1, transform: 'translateY(0px)' },
  },
  slideLeft: {
    from: { opacity: 0, transform: 'translateX(20px)' },
    to: { opacity: 1, transform: 'translateX(0px)' },
  },
  slideRight: {
    from: { opacity: 0, transform: 'translateX(-20px)' },
    to: { opacity: 1, transform: 'translateX(0px)' },
  },
  scaleIn: {
    from: { opacity: 0, transform: 'scale(0.9)' },
    to: { opacity: 1, transform: 'scale(1)' },
  },
  scaleOut: {
    from: { opacity: 1, transform: 'scale(1)' },
    to: { opacity: 0, transform: 'scale(0.9)' },
  },
};

/**
 * Get spring config for a specific animation type
 */
export const getAnimationConfig = (
  type: 'gentle' | 'snappy' | 'slow' | 'bouncy' | 'default' = 'default'
): SpringConfig => {
  return getSpringConfig(type);
};

/**
 * Calculate opacity based on scroll position
 */
export const getScrollOpacity = (
  scrollY: number,
  startFade: number = 0,
  endFade: number = 100
): number => {
  if (scrollY < startFade) return 1;
  if (scrollY > endFade) return 0;
  return 1 - (scrollY - startFade) / (endFade - startFade);
};

/**
 * Parallax offset calculation
 */
export const getParallaxOffset = (
  scrollY: number,
  speed: number = 0.5
): number => {
  return scrollY * speed;
};


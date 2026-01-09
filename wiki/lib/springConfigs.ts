import { SpringConfig } from '@react-spring/web';

/**
 * Predefined spring configurations for different animation types
 * Inspired by React Spring examples and best practices
 */

export const springConfigs = {
  // Gentle, smooth animations for UI elements (very fast)
  gentle: {
    tension: 400,
    friction: 25,
  } as SpringConfig,

  // Snappy, responsive animations for interactive elements (very fast)
  snappy: {
    tension: 800,
    friction: 35,
  } as SpringConfig,

  // Slow, smooth animations for page transitions (very fast)
  slow: {
    tension: 200,
    friction: 35,
  } as SpringConfig,

  // Bouncy animations for playful interactions (very fast)
  bouncy: {
    tension: 800,
    friction: 20,
  } as SpringConfig,

  // Default spring config (very fast)
  default: {
    tension: 500,
    friction: 40,
  } as SpringConfig,
};

/**
 * Check if user prefers reduced motion
 */
export const prefersReducedMotion = (): boolean => {
  if (typeof window === 'undefined') return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
};

/**
 * Get spring config with reduced motion support
 */
export const getSpringConfig = (config: keyof typeof springConfigs = 'default'): SpringConfig => {
  if (prefersReducedMotion()) {
    return {
      tension: 200,
      friction: 30,
    };
  }
  return springConfigs[config];
};


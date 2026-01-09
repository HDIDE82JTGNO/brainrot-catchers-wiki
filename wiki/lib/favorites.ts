/**
 * Favorites management utilities
 * Uses LocalStorage to persist favorites
 */

export type FavoriteType = 'creature' | 'move' | 'item' | 'location';

export interface Favorite {
  type: FavoriteType;
  id: string;
  name: string;
  addedAt: number;
}

const STORAGE_KEY = 'brainrot-wiki-favorites';

/**
 * Get all favorites
 */
export function getFavorites(): Favorite[] {
  if (typeof window === 'undefined') return [];
  
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (!stored) return [];
    return JSON.parse(stored);
  } catch {
    return [];
  }
}

/**
 * Add a favorite
 */
export function addFavorite(type: FavoriteType, id: string, name: string): void {
  if (typeof window === 'undefined') return;
  
  const favorites = getFavorites();
  
  // Check if already favorited
  if (favorites.some(f => f.type === type && f.id === id)) {
    return;
  }
  
  favorites.push({
    type,
    id,
    name,
    addedAt: Date.now(),
  });
  
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(favorites));
  } catch (error) {
    console.error('Failed to save favorites:', error);
  }
}

/**
 * Remove a favorite
 */
export function removeFavorite(type: FavoriteType, id: string): void {
  if (typeof window === 'undefined') return;
  
  const favorites = getFavorites().filter(
    f => !(f.type === type && f.id === id)
  );
  
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(favorites));
  } catch (error) {
    console.error('Failed to save favorites:', error);
  }
}

/**
 * Check if item is favorited
 */
export function isFavorited(type: FavoriteType, id: string): boolean {
  const favorites = getFavorites();
  return favorites.some(f => f.type === type && f.id === id);
}

/**
 * Toggle favorite status
 */
export function toggleFavorite(type: FavoriteType, id: string, name: string): boolean {
  const isFav = isFavorited(type, id);
  
  if (isFav) {
    removeFavorite(type, id);
    return false;
  } else {
    addFavorite(type, id, name);
    return true;
  }
}

/**
 * Get favorites by type
 */
export function getFavoritesByType(type: FavoriteType): Favorite[] {
  return getFavorites().filter(f => f.type === type);
}

/**
 * Clear all favorites
 */
export function clearFavorites(): void {
  if (typeof window === 'undefined') return;
  
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch (error) {
    console.error('Failed to clear favorites:', error);
  }
}


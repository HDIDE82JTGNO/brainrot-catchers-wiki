/**
 * Collection tracker utilities
 * Tracks which creatures have been caught
 */

const STORAGE_KEY = 'brainrot-wiki-collection';

/**
 * Get collection (set of caught creature IDs)
 */
export function getCollection(): Set<string> {
  if (typeof window === 'undefined') return new Set();
  
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (!stored) return new Set();
    const ids = JSON.parse(stored) as string[];
    return new Set(ids);
  } catch {
    return new Set();
  }
}

/**
 * Add creature to collection
 */
export function addToCollection(creatureId: string): void {
  if (typeof window === 'undefined') return;
  
  const collection = getCollection();
  collection.add(creatureId);
  
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(Array.from(collection)));
  } catch (error) {
    console.error('Failed to save collection:', error);
  }
}

/**
 * Remove creature from collection
 */
export function removeFromCollection(creatureId: string): void {
  if (typeof window === 'undefined') return;
  
  const collection = getCollection();
  collection.delete(creatureId);
  
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(Array.from(collection)));
  } catch (error) {
    console.error('Failed to save collection:', error);
  }
}

/**
 * Check if creature is in collection
 */
export function isInCollection(creatureId: string): boolean {
  const collection = getCollection();
  return collection.has(creatureId);
}

/**
 * Toggle collection status
 */
export function toggleCollection(creatureId: string): boolean {
  const isCollected = isInCollection(creatureId);
  
  if (isCollected) {
    removeFromCollection(creatureId);
    return false;
  } else {
    addToCollection(creatureId);
    return true;
  }
}

/**
 * Get collection completion percentage
 */
export function getCollectionPercentage(totalCreatures: number): number {
  if (totalCreatures === 0) return 0;
  const collection = getCollection();
  return (collection.size / totalCreatures) * 100;
}

/**
 * Clear collection
 */
export function clearCollection(): void {
  if (typeof window === 'undefined') return;
  
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch (error) {
    console.error('Failed to clear collection:', error);
  }
}

/**
 * Export collection as JSON
 */
export function exportCollection(): string {
  const collection = getCollection();
  return JSON.stringify(Array.from(collection), null, 2);
}

/**
 * Import collection from JSON
 */
export function importCollection(json: string): boolean {
  if (typeof window === 'undefined') return false;
  
  try {
    const ids = JSON.parse(json) as string[];
    if (!Array.isArray(ids)) return false;
    
    localStorage.setItem(STORAGE_KEY, JSON.stringify(ids));
    return true;
  } catch {
    return false;
  }
}


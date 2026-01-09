/**
 * Share link generation utilities
 */

/**
 * Generate shareable URL with query parameters
 */
export function generateShareUrl(basePath: string, params: Record<string, string | number | boolean>): string {
  if (typeof window === 'undefined') {
    return basePath;
  }

  const url = new URL(basePath, window.location.origin);
  
  Object.entries(params).forEach(([key, value]) => {
    if (value !== null && value !== undefined) {
      url.searchParams.set(key, String(value));
    }
  });

  return url.toString();
}

/**
 * Copy text to clipboard
 */
export async function copyToClipboard(text: string): Promise<boolean> {
  if (typeof window === 'undefined' || !navigator.clipboard) {
    return false;
  }

  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch (error) {
    console.error('Failed to copy to clipboard:', error);
    return false;
  }
}

/**
 * Share URL with Web Share API or clipboard fallback
 */
export async function shareUrl(url: string, title: string, text?: string): Promise<boolean> {
  if (typeof window === 'undefined') return false;

  // Try Web Share API first
  if (navigator.share) {
    try {
      await navigator.share({
        title,
        text: text || title,
        url,
      });
      return true;
    } catch (error) {
      // User cancelled or error occurred
      if ((error as Error).name !== 'AbortError') {
        console.error('Share failed:', error);
      }
    }
  }

  // Fallback to clipboard
  return copyToClipboard(url);
}

/**
 * Generate share link for creature with filters
 */
export function shareCreature(name: string, shiny?: boolean): string {
  return generateShareUrl(`/creatures/${encodeURIComponent(name)}`, {
    ...(shiny !== undefined && { shiny: shiny.toString() }),
  });
}

/**
 * Generate share link for comparison
 */
export function shareComparison(creatureNames: string[]): string {
  return generateShareUrl('/compare', {
    creatures: creatureNames.join(','),
  });
}

/**
 * Generate share link for team
 */
export function shareTeam(creatureIds: string[]): string {
  return generateShareUrl('/team-builder', {
    team: creatureIds.join(','),
  });
}

/**
 * Parse share URL parameters
 */
export function parseShareParams(): Record<string, string> {
  if (typeof window === 'undefined') return {};

  const params = new URLSearchParams(window.location.search);
  const result: Record<string, string> = {};

  params.forEach((value, key) => {
    result[key] = value;
  });

  return result;
}


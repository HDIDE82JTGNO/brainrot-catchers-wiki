/**
 * Share link generation utilities
 */

import { Creature, Move } from '@/types';
import { TeamMember, createDefaultTeamMember } from './teamTypes';

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
 * Generate share link for team (legacy - creature IDs only)
 */
export function shareTeamLegacy(creatureIds: string[]): string {
  return generateShareUrl('/team-builder', {
    team: creatureIds.join(','),
  });
}

/**
 * Generate share link for team with full data (IVs, EVs, moves, level)
 */
export function shareTeam(team: TeamMember[]): string {
  if (typeof window === 'undefined') {
    return '/team-builder';
  }

  // Encode team data as base64 JSON
  const teamData = team.map(member => ({
    id: member.Id,
    ivs: member.ivs,
    evs: member.evs,
    moves: member.moves,
    level: member.level,
  }));

  try {
    const encoded = btoa(JSON.stringify(teamData));
    return generateShareUrl('/team-builder', {
      team: encoded,
    });
  } catch (error) {
    console.error('Failed to encode team:', error);
    // Fallback to simple creature IDs
    return generateShareUrl('/team-builder', {
      team: team.map(m => m.Id).join(','),
    });
  }
}

/**
 * Parse team from URL
 */
export function parseTeamFromUrl(allCreatures: Creature[]): TeamMember[] | null {
  if (typeof window === 'undefined') return null;

  try {
    const params = new URLSearchParams(window.location.search);
    const teamParam = params.get('team');
    if (!teamParam) return null;

    // Try to decode as base64 JSON first (new format)
    try {
      const decoded = JSON.parse(atob(teamParam));
      if (Array.isArray(decoded)) {
        return decoded.map((data: any) => {
          const creature = allCreatures.find(c => c.Id === data.id);
          if (!creature) return null;
          
          const member = createDefaultTeamMember(creature);
          return {
            ...member,
            ivs: data.ivs || member.ivs,
            evs: data.evs || member.evs,
            moves: data.moves || member.moves,
            level: data.level || member.level,
          };
        }).filter((m): m is TeamMember => m !== null);
      }
    } catch {
      // Fallback to legacy format (comma-separated creature IDs)
      const creatureIds = teamParam.split(',');
      return creatureIds
        .map(id => {
          const creature = allCreatures.find(c => c.Id === id);
          return creature ? createDefaultTeamMember(creature) : null;
        })
        .filter((m): m is TeamMember => m !== null);
    }
  } catch (error) {
    console.error('Failed to parse team from URL:', error);
    return null;
  }

  return null;
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

/**
 * Copy creature data to clipboard
 */
export async function copyCreatureData(creature: Creature, format: 'json' | 'text'): Promise<boolean> {
  let text: string;

  if (format === 'json') {
    text = JSON.stringify(creature, null, 2);
  } else {
    text = [
      `Name: ${creature.Name}`,
      `Dex Number: #${String(creature.DexNumber).padStart(3, '0')}`,
      `Types: ${creature.Types?.join(', ') || 'N/A'}`,
      `Description: ${creature.Description || 'N/A'}`,
      '',
      'Base Stats:',
      `  HP: ${creature.BaseStats.HP}`,
      `  Attack: ${creature.BaseStats.Attack}`,
      `  Defense: ${creature.BaseStats.Defense}`,
      `  Special Attack: ${creature.BaseStats.SpecialAttack}`,
      `  Special Defense: ${creature.BaseStats.SpecialDefense}`,
      `  Speed: ${creature.BaseStats.Speed}`,
      `  Total BST: ${creature.BaseStats.HP + creature.BaseStats.Attack + creature.BaseStats.Defense + creature.BaseStats.SpecialAttack + creature.BaseStats.SpecialDefense + creature.BaseStats.Speed}`,
    ].join('\n');
  }

  return copyToClipboard(text);
}

/**
 * Copy move data to clipboard
 */
export async function copyMoveData(move: Move, format: 'json' | 'text'): Promise<boolean> {
  let text: string;

  if (format === 'json') {
    text = JSON.stringify(move, null, 2);
  } else {
    text = [
      `Name: ${move.Name}`,
      `Type: ${move.Type}`,
      `Category: ${move.Category}`,
      `Base Power: ${move.BasePower || 'N/A'}`,
      `Accuracy: ${move.Accuracy || 'N/A'}%`,
      `Priority: ${move.Priority || 0}`,
      `Description: ${move.Description || 'N/A'}`,
      move.StatusEffect ? `Status Effect: ${move.StatusEffect} (${move.StatusChance || 0}% chance)` : '',
      move.HealsPercent ? `Heals: ${move.HealsPercent}%` : '',
      move.RecoilPercent ? `Recoil: ${move.RecoilPercent}%` : '',
    ].filter(Boolean).join('\n');
  }

  return copyToClipboard(text);
}

/**
 * Copy team data to clipboard
 */
export async function copyTeamData(team: TeamMember[], format: 'json' | 'text'): Promise<boolean> {
  let text: string;

  if (format === 'json') {
    text = JSON.stringify(team, null, 2);
  } else {
    text = [
      `Team (${team.length} members):`,
      '',
      ...team.map((member, idx) => [
        `${idx + 1}. ${member.Name} (Level ${member.level})`,
        `   Types: ${member.Types?.join(', ') || 'N/A'}`,
        `   IVs: HP:${member.ivs.HP} Atk:${member.ivs.Attack} Def:${member.ivs.Defense} SpA:${member.ivs.SpecialAttack} SpD:${member.ivs.SpecialDefense} Spe:${member.ivs.Speed}`,
        `   EVs: HP:${member.evs.HP} Atk:${member.evs.Attack} Def:${member.evs.Defense} SpA:${member.evs.SpecialAttack} SpD:${member.evs.SpecialDefense} Spe:${member.evs.Speed}`,
        `   Moves: ${member.moves.length > 0 ? member.moves.join(', ') : 'None'}`,
      ].join('\n')),
    ].join('\n');
  }

  return copyToClipboard(text);
}


// Maps creature names to sprite filenames
export function getSpritePath(creatureName: string, isShiny: boolean = false): string {
  // Remove special characters and spaces
  const cleanName = creatureName.replace(/[^a-zA-Z0-9]/g, '');
  const suffix = isShiny ? '-S' : '-NS';
  return `/sprites/${cleanName}${suffix}.webp`;
}

// Check if sprite exists (optional, mostly for robust implementation)
export const spriteExists = (creatureName: string): boolean => {
  // In a client-side context, we can't check file existence easily without a manifest.
  // We'll rely on the standardized naming convention.
  return true;
};


import fs from 'fs';
import path from 'path';
import luaparse from 'luaparse';

const WIKI_GAME_DATA_DIR = path.resolve(__dirname, '../game-data');
const WIKI_DATA_DIR = path.resolve(__dirname, '../data');

// Input paths - now pointing to vendored files
const PATHS = {
  creatures: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/Creatures.lua'),
  items: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/Items.lua'),
  moves: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/Moves.lua'),
  locations: path.join(WIKI_GAME_DATA_DIR, 'ServerScriptService/Server/GameData/ChunkList.lua'),
  typeChart: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/TypeChart.lua'),
  abilities: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/Abilities.lua'),
  speciesAbilities: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/SpeciesAbilities.lua'),
  status: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/Status.lua'),
  weather: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/WeatherConfig.lua'),
  natures: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/Natures.lua'),
  challenges: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/ChallengesConfig.lua'),
  badges: path.join(WIKI_GAME_DATA_DIR, 'ReplicatedStorage/Shared/BadgeConfig.lua'),
};

// Ensure output dir exists
if (!fs.existsSync(WIKI_DATA_DIR)) {
  fs.mkdirSync(WIKI_DATA_DIR, { recursive: true });
}

function parseLuaFile(filePath: string) {
  if (!fs.existsSync(filePath)) {
      throw new Error(`File not found: ${filePath}`);
  }
  let content = fs.readFileSync(filePath, 'utf-8');
  
  // 1. Remove type aliases
  content = content.replace(/^type\s+\w+\s*=\s*.+/gm, '');
  
  // 2. Simplify function signatures
  content = content.replace(/local\s+function\s+(\w+)\s*\([^)]*\)(?:\s*:\s*[\w\?]+)?/g, 'local function $1()');
  
  // 3. Remove variable type annotations
  content = content.replace(/local\s+(\w+)\s*:\s*[\w\.]+\s*=/g, 'local $1 =');
  content = content.replace(/local\s+(\w+)\s*:\s*\{[^}]*\}\s*=/g, 'local $1 =');

  // 4. Remove --!strict
  content = content.replace(/--!strict/g, '');

  // 5. General cleanup of inline type assertions if any left (:: Type)
  content = content.replace(/::\s*[\w\.]+/g, '');

  return content;
}

function findTableInAST(ast: any): any {
    const returnStmt = ast.body.find((node: any) => node.type === 'ReturnStatement');
    if (!returnStmt || returnStmt.arguments.length === 0) return null;

    const arg = returnStmt.arguments[0];
    if (arg.type === 'TableConstructorExpression') {
        return arg;
    } else if (arg.type === 'Identifier') {
        const name = arg.name;
        for (let i = ast.body.length - 1; i >= 0; i--) {
            const stmt = ast.body[i];
            if (stmt.type === 'LocalStatement') {
                for (let j = 0; j < stmt.variables.length; j++) {
                    if (stmt.variables[j].name === name) {
                        return stmt.init[j];
                    }
                }
            } else if (stmt.type === 'AssignmentStatement') {
                for (let j = 0; j < stmt.variables.length; j++) {
                     if (stmt.variables[j].name === name) {
                         return stmt.init[j];
                     }
                }
            }
        }
    }
    return null;
}

function toSlug(str: string): string {
    return (str || "unknown").toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
}

function extractCreatures(content: string) {
  const creatures: any[] = [];
  try {
      const ast = luaparse.parse(content);
      const tableConstructor = findTableInAST(ast);
      if (!tableConstructor || tableConstructor.type !== 'TableConstructorExpression') {
          console.error("Could not find Creatures table in AST");
          return [];
      }
      
      tableConstructor.fields.forEach((field, fieldIdx) => {
          if (field.type === 'TableKeyString' || field.type === 'TableKey') {
              const key = field.type === 'TableKeyString' 
                  ? field.key.name 
                  : astNodeToValue(field.key);
              
              if (!key) {
                  console.warn(`Skipping field ${fieldIdx}: no key found, field type: ${field.type}, key node:`, field.key);
                  return;
              }
              
              if (field.value.type === 'CallExpression') {
                  const args = field.value.arguments;
                  const values = args.map(arg => astNodeToValue(arg));
                  
                  // Ensure Name is valid - use key as fallback since key should be the creature name
                  const name = (values[1] && values[1] !== null) ? values[1] : key;
                  const id = key;

                  // Convert learnset array to object format { "1": ["Move1"], "5": ["Move2"] }
                  let learnset = null;
                  if (values[7]) {
                      if (Array.isArray(values[7])) {
                          learnset = {};
                          values[7].forEach((moves, level) => {
                              if (moves && Array.isArray(moves)) {
                                  const filteredMoves = moves.filter(m => m !== null);
                                  if (filteredMoves.length > 0) {
                                      learnset[level + 1] = filteredMoves; // Lua arrays are 1-indexed
                                  }
                              }
                          });
                          if (Object.keys(learnset).length === 0) learnset = null;
                      } else if (typeof values[7] === 'object') {
                          learnset = values[7];
                      }
                  }

                  creatures.push({
                    Id: id,
                    Slug: toSlug(name),
                    DexNumber: values[0] || 0,
                    Name: name,
                    Sprite: values[2] || null,
                    ShinySprite: values[3] || null,
                    Description: values[4] || "",
                    Types: Array.isArray(values[5]) ? values[5].filter(t => t !== null && t !== undefined) : (values[5] ? [values[5]] : []),
                    BaseStats: values[6] || {},
                    Learnset: learnset,
                    EvolutionLevel: values[8] || null,
                    EvolvesInto: values[9] || null,
                    BaseWeightKg: values[10] || null,
                    ShinyColors: values[11] || null,
                    Class: values[12] || null,
                    CatchRateScalar: values[13] || null,
                    FemaleChance: values[14] || null
                });
              } else {
                  console.warn(`Field ${key} value is not a CallExpression, got: ${field.value.type}`);
              }
          }
      });
      
  } catch (e) {
      console.error("Failed to parse Creatures.lua via AST:", e);
      if (e instanceof Error) {
          console.error(e.stack);
      }
  }
  return creatures;
}

function extractItems(content: string) {
  const items: any[] = [];
  try {
      const ast = luaparse.parse(content);
      const tableConstructor = findTableInAST(ast);
       if (!tableConstructor || tableConstructor.type !== 'TableConstructorExpression') return [];

      tableConstructor.fields.forEach(field => {
           const key = field.type === 'TableKeyString' ? field.key.name : astNodeToValue(field.key);
           if (field.value.type === 'CallExpression') {
               const args = field.value.arguments;
               const values = args.map(arg => astNodeToValue(arg));
                
               const name = key || "Unknown";

               items.push({
                    Id: key,
                    Slug: toSlug(name),
                    Name: name,
                    Stats: values[0],
                    Description: values[1],
                    Category: values[2],
                    UsableInBattle: values[3],
                    UsableInOverworld: values[4],
                    Image: values[5]
                });
           }
      });
  } catch (e) {
      console.error("Failed to parse Items.lua via AST:", e);
  }
  return items;
}

function extractMoves(content: string) {
    const moves: any[] = [];
    try {
        const ast = luaparse.parse(content);
        const tableConstructor = findTableInAST(ast);
        if (!tableConstructor || tableConstructor.type !== 'TableConstructorExpression') return [];

        tableConstructor.fields.forEach(field => {
            const key = field.type === 'TableKeyString' ? field.key.name : astNodeToValue(field.key);
            
            if (field.value.type === 'CallExpression') {
                const callExpr = field.value;
                const creator = callExpr.base.name; 
                const args = callExpr.arguments;
                const values = args.map(arg => astNodeToValue(arg));

                let move: any = { Name: key || "Unknown" };
                move.Slug = toSlug(move.Name);
                move.Id = key; // Ensure ID is set
                
                if (creator === 'createMove') {
                    move = {
                        ...move,
                        BasePower: values[0],
                        Accuracy: values[1],
                        Priority: values[2],
                        Type: values[3],
                        Category: values[4],
                        Description: values[5],
                        HealsPercent: values[6],
                        StatusEffect: values[7],
                        StatusChance: values[8],
                        CausesFlinch: values[9],
                        CausesConfusion: values[10],
                        StatChanges: values[11],
                        MultiHit: values[12]
                    };
                } else if (creator === 'createMultiHitMove') {
                    move = {
                        ...move,
                        BasePower: values[0],
                        Accuracy: values[1],
                        Priority: values[2],
                        Type: values[3],
                        Category: values[4],
                        Description: values[5],
                        MinHits: values[6],
                        MaxHits: values[7],
                        Fixed: values[8],
                        StatusEffect: values[9],
                        StatusChance: values[10],
                        CausesFlinch: values[11]
                    };
                } else if (creator === 'createRecoilMove') {
                    move = {
                        ...move,
                        BasePower: values[0],
                        Accuracy: values[1],
                        Priority: values[2],
                        Type: values[3],
                        Category: values[4],
                        Description: values[5],
                        RecoilPercent: values[6],
                        StatusEffect: values[7],
                        StatusChance: values[8],
                        CausesFlinch: values[9]
                    };
                } else if (creator === 'createStatMove') {
                    move = {
                        ...move,
                        BasePower: 0,
                        Accuracy: values[0],
                        Priority: values[1],
                        Type: values[2],
                        Category: "Status",
                        Description: values[3],
                        StatChanges: values[4]
                    };
                }
                moves.push(move);
            }
        });

    } catch (e) {
        console.error("Failed to parse Moves.lua via AST:", e);
    }
    return moves;
}

function extractLocations(content: string) {
    const match = content.match(/local ChunkList = \{([\s\S]*?)\}\s*return/);
    if (!match) return [];
    
    const tableContent = match[1];
    
    try {
        const ast = luaparse.parse(`t = {${tableContent}}`);
        const tableNode = ast.body[0].init[0];
        
        const chunks = {};
        
        tableNode.fields.forEach(field => {
            if (field.type === 'TableKeyString' || field.type === 'TableKey') {
                const key = field.type === 'TableKeyString' ? field.key.name : astNodeToValue(field.key);
                // Recursively parse the chunk data
                const value = astNodeToValue(field.value);
                chunks[key] = value;
            }
        });
        
        const locations: any[] = [];
        const seenIds = new Set<string>();
        
        // Define chunk order for proper sequencing
        const chunkOrder = [
            'Title', 'Trade', 'Battle',
            'Chunk1', 'Chunk2', 'Chunk3', 'Chunk4', 'Chunk5', 'Chunk6', 'Chunk7', 'Chunk8',
            'CatchCare', 'House1', "Professor's Lab", 'PlayersHouse', 'Gym1'
        ];
        
        // Helper to process a chunk/subchunk
        const processChunk = (key: string, data: any, parentName?: string, parentKey?: string) => {
            if (!data) return;
            
            const properName = data.ProperName || '';
            const locName = properName || key;
            
            // Skip locations with empty ProperName (like Chunk1House1, Chunk3House4)
            if (!properName && /^Chunk\d+House\d+$/.test(key)) {
                return;
            }
            
            // Skip duplicates
            if (seenIds.has(key)) {
                return;
            }
            
            const normalizeEncounter = (enc: any) => {
                if (!enc) return null;
                // [name, min, max, chance] or {Creature: name, ...}
                if (Array.isArray(enc)) {
                    return {
                        Creature: enc[0],
                        MinLevel: enc[1],
                        MaxLevel: enc[2],
                        Chance: enc[3]
                    };
                }
                return enc; // Already object or unknown format
            };
            
            const encounters = (data.Encounters || [])
                .map(normalizeEncounter)
                .filter((e: any) => e && e.Creature); // Filter valid encounters

            const location: any = {
                Id: key,
                Slug: toSlug(locName),
                Name: locName,
                Encounters: encounters,
                Description: data.Description || undefined,
            };
            
            if (parentName) {
                location.Parent = parentName;
            }
            
            locations.push(location);
            seenIds.add(key);

            // Process SubChunks if any
            if (data.SubChunks) {
                for (const [subKey, subData] of Object.entries(data.SubChunks)) {
                    processChunk(subKey, subData, locName, key);
                }
            }
        };

        // Process chunks in order
        const processedKeys = new Set<string>();
        
        // First, process chunks in defined order
        for (const key of chunkOrder) {
            if (chunks[key] && typeof chunks[key] === 'object') {
                processChunk(key, chunks[key]);
                processedKeys.add(key);
            }
        }
        
        // Then process any remaining chunks not in the order list
        for (const [key, data] of Object.entries(chunks)) {
            if (!processedKeys.has(key) && typeof data === 'object') {
                processChunk(key, data);
            }
        }
        
        // Sort locations: main chunks first (by chunk order), then sub-chunks grouped under parents
        const getChunkNumber = (id: string): number => {
            const match = id.match(/^Chunk(\d+)$/);
            if (match) return parseInt(match[1]);
            if (id === 'Title') return -3;
            if (id === 'Trade') return -2;
            if (id === 'Battle') return -1;
            return 999; // Other locations go after chunks
        };
        
        locations.sort((a, b) => {
            const aChunkNum = getChunkNumber(a.Id);
            const bChunkNum = getChunkNumber(b.Id);
            
            // Main chunks first, sorted by number
            if (aChunkNum !== 999 && bChunkNum !== 999) {
                return aChunkNum - bChunkNum;
            }
            
            // If one is a main chunk and other isn't, main chunk comes first
            if (aChunkNum !== 999 && bChunkNum === 999) return -1;
            if (aChunkNum === 999 && bChunkNum !== 999) return 1;
            
            // Both are sub-chunks or other locations
            // Group sub-chunks with their parent
            if (a.Parent && b.Parent) {
                const aParentNum = getChunkNumber(a.Parent);
                const bParentNum = getChunkNumber(b.Parent);
                if (aParentNum !== bParentNum) {
                    return aParentNum - bParentNum;
                }
                // Same parent, sort by name
                return a.Name.localeCompare(b.Name);
            }
            
            // One has parent, one doesn't - parented ones come after their parent
            if (a.Parent && !b.Parent) {
                const aParentNum = getChunkNumber(a.Parent);
                const bNum = getChunkNumber(b.Id);
                if (aParentNum < bNum) return -1;
                if (aParentNum > bNum) return 1;
                return 1; // Sub-chunk comes after parent
            }
            if (!a.Parent && b.Parent) {
                const aNum = getChunkNumber(a.Id);
                const bParentNum = getChunkNumber(b.Parent);
                if (aNum < bParentNum) return -1;
                if (aNum > bParentNum) return 1;
                return -1; // Parent comes before sub-chunk
            }
            
            // Neither has parent, sort by name
            return a.Name.localeCompare(b.Name);
        });
        
        return locations;
    } catch (e) {
        console.error("Failed to parse locations:", e);
        return [];
    }
}

function extractTypes(content: string) {
    const match = content.match(/local CHART: .*? = \{([\s\S]*?)\}\s*function/);
    if (!match) return {};
    
    const tableContent = match[1];
     try {
        const ast = luaparse.parse(`t = {${tableContent}}`);
        const tableNode = ast.body[0].init[0];
        const chart = astNodeToValue(tableNode);
        return chart;
     } catch(e) {
         console.error("Failed to parse types:", e);
         return {};
     }
}

function extractAbilities(content: string) {
    const abilities: any[] = [];
    try {
        // Use regex to extract the Definitions table content
        // Match: Abilities.Definitions = { ... } followed by -- Helper or function
        const match = content.match(/Abilities\.Definitions\s*=\s*\{([\s\S]*?)\}\s*(?:--\s*Helper|function)/);
        if (!match) {
            // Try alternative: just Definitions = { ... }
            const altMatch = content.match(/Definitions\s*=\s*\{([\s\S]*?)\}\s*(?:--\s*Helper|function)/);
            if (!altMatch) {
                console.error("Could not find Abilities.Definitions table");
                return [];
            }
            const tableContent = altMatch[1];
            try {
                const ast = luaparse.parse(`t = {${tableContent}}`);
                const tableNode = ast.body[0].init[0];
                const definitions = astNodeToValue(tableNode);
                if (definitions && typeof definitions === 'object') {
                    for (const [key, value] of Object.entries(definitions)) {
                        if (value && typeof value === 'object') {
                            abilities.push({
                                Id: key,
                                Name: value.Name || key,
                                Description: value.Description || "",
                                TriggerType: value.TriggerType || "",
                                ...value
                            });
                        }
                    }
                }
            } catch (e2) {
                console.error("Failed to parse extracted table:", e2);
            }
            return abilities;
        }
        
        const tableContent = match[1];
        try {
            const ast = luaparse.parse(`t = {${tableContent}}`);
            const tableNode = ast.body[0].init[0];
            const definitions = astNodeToValue(tableNode);
            if (definitions && typeof definitions === 'object') {
                for (const [key, value] of Object.entries(definitions)) {
                    if (value && typeof value === 'object') {
                        abilities.push({
                            Id: key,
                            Name: value.Name || key,
                            Description: value.Description || "",
                            TriggerType: value.TriggerType || "",
                            ...value
                        });
                    }
                }
            }
        } catch (e) {
            console.error("Failed to parse abilities table:", e);
        }
    } catch (e) {
        console.error("Failed to extract abilities:", e);
    }
    return abilities;
}

function extractStatusEffects(content: string) {
    const statusEffects: any[] = [];
    try {
        // Extract STATUS_DEFINITIONS table - look for local STATUS_DEFINITIONS pattern
        // Pattern: local STATUS_DEFINITIONS: {...} = { ... }
        const match = content.match(/local\s+STATUS_DEFINITIONS[^=]*=\s*\{([\s\S]*?)\}\s*(?:--|function|\[\[|$)/m);
        if (!match) {
            // Try without local keyword
            const altMatch = content.match(/STATUS_DEFINITIONS[^=]*=\s*\{([\s\S]*?)\}\s*(?:--|function|\[\[|$)/m);
            if (!altMatch) {
                console.error("Could not find STATUS_DEFINITIONS table");
                return [];
            }
            const tableContent = altMatch[1];
            return parseStatusTable(tableContent);
        }
        
        const tableContent = match[1];
        return parseStatusTable(tableContent);
    } catch (e) {
        console.error("Failed to extract status effects:", e);
    }
    return statusEffects;
}

function extractWeather(content: string) {
    const weatherTypes: any[] = [];
    try {
        // Extract WeatherConfig.Types table
        const match = content.match(/WeatherConfig\.Types\s*=\s*\{([\s\S]*?)\}\s*(?:--|function|local)/);
        if (!match) {
            console.error("Could not find WeatherConfig.Types table");
            return [];
        }
        
        const tableContent = match[1];
        try {
            const ast = luaparse.parse(`t = {${tableContent}}`);
            const tableNode = ast.body[0].init[0];
            const definitions = astNodeToValue(tableNode);
            if (definitions && typeof definitions === 'object') {
                // Convert array to array of objects
                if (Array.isArray(definitions)) {
                    definitions.forEach((weather, idx) => {
                        if (weather && typeof weather === 'object') {
                            weatherTypes.push({
                                Id: weather.Id || idx + 1,
                                Name: weather.Name || '',
                                Description: weather.Description || '',
                                Icon: weather.Icon || '',
                                Weight: weather.Weight || 0,
                                SpawnModifiers: weather.SpawnModifiers || {},
                                AbilityModifiers: weather.AbilityModifiers || {},
                                ...weather
                            });
                        }
                    });
                } else {
                    // Object format
                    for (const [key, value] of Object.entries(definitions)) {
                        if (value && typeof value === 'object') {
                            weatherTypes.push({
                                Id: value.Id || parseInt(key) || 0,
                                Name: value.Name || '',
                                Description: value.Description || '',
                                Icon: value.Icon || '',
                                Weight: value.Weight || 0,
                                SpawnModifiers: value.SpawnModifiers || {},
                                AbilityModifiers: value.AbilityModifiers || {},
                                ...value
                            });
                        }
                    }
                }
            }
        } catch (e) {
            console.error("Failed to parse weather table:", e);
        }
    } catch (e) {
        console.error("Failed to extract weather:", e);
    }
    return weatherTypes;
}

function extractNatures(content: string) {
    const natures: any[] = [];
    try {
        // Extract NATURE_DEFS table
        const match = content.match(/local\s+NATURE_DEFS[^=]*=\s*\{([\s\S]*?)\}\s*(?:local|function|return)/);
        if (!match) {
            console.error("Could not find NATURE_DEFS table");
            return [];
        }
        
        const tableContent = match[1];
        try {
            const ast = luaparse.parse(`t = {${tableContent}}`);
            const tableNode = ast.body[0].init[0];
            const definitions = astNodeToValue(tableNode);
            if (definitions && typeof definitions === 'object') {
                for (const [name, value] of Object.entries(definitions)) {
                    if (value && typeof value === 'object') {
                        const incStat = mapNatureKeyToStat(value.inc);
                        const decStat = mapNatureKeyToStat(value.dec);
                        natures.push({
                            Name: name,
                            Increases: incStat || 'None',
                            Decreases: decStat || 'None',
                            IncreaseKey: value.inc,
                            DecreaseKey: value.dec,
                            IsNeutral: value.inc === 'None' && value.dec === 'None'
                        });
                    }
                }
            }
        } catch (e) {
            console.error("Failed to parse natures table:", e);
        }
    } catch (e) {
        console.error("Failed to extract natures:", e);
    }
    return natures;
}

function extractChallenges(content: string) {
    const challenges: any = { daily: [], weekly: [] };
    try {
        // Extract DailyChallenges array
        const dailyMatch = content.match(/ChallengesConfig\.DailyChallenges\s*=\s*\{([\s\S]*?)\}\s*(?:--|ChallengesConfig\.WeeklyChallenges)/);
        if (dailyMatch) {
            const tableContent = dailyMatch[1];
            try {
                const ast = luaparse.parse(`t = {${tableContent}}`);
                const tableNode = ast.body[0].init[0];
                const definitions = astNodeToValue(tableNode);
                if (Array.isArray(definitions)) {
                    challenges.daily = definitions.filter(d => d && typeof d === 'object');
                }
            } catch (e) {
                console.error("Failed to parse daily challenges:", e);
            }
        }
        
        // Extract WeeklyChallenges array
        const weeklyMatch = content.match(/ChallengesConfig\.WeeklyChallenges\s*=\s*\{([\s\S]*?)\}\s*(?:--|return|function)/);
        if (weeklyMatch) {
            const tableContent = weeklyMatch[1];
            try {
                const ast = luaparse.parse(`t = {${tableContent}}`);
                const tableNode = ast.body[0].init[0];
                const definitions = astNodeToValue(tableNode);
                if (Array.isArray(definitions)) {
                    challenges.weekly = definitions.filter(d => d && typeof d === 'object');
                }
            } catch (e) {
                console.error("Failed to parse weekly challenges:", e);
            }
        }
    } catch (e) {
        console.error("Failed to extract challenges:", e);
    }
    return challenges;
}

function extractBadges(content: string) {
    const badges: any[] = [];
    try {
        // Extract BadgeImages table
        const match = content.match(/BadgeConfig\.BadgeImages\s*=\s*\{([\s\S]*?)\}\s*(?:--|BadgeConfig\.Locked|return)/);
        if (!match) {
            console.error("Could not find BadgeImages table");
            return [];
        }
        
        const tableContent = match[1];
        try {
            const ast = luaparse.parse(`t = {${tableContent}}`);
            const tableNode = ast.body[0].init[0];
            const definitions = astNodeToValue(tableNode);
            if (definitions && typeof definitions === 'object') {
                if (Array.isArray(definitions)) {
                    definitions.forEach((image, idx) => {
                        badges.push({
                            Id: idx + 1,
                            Number: idx + 1,
                            Image: image || '',
                            Name: `Badge ${idx + 1}`
                        });
                    });
                } else {
                    for (const [key, value] of Object.entries(definitions)) {
                        const num = parseInt(key);
                        badges.push({
                            Id: num,
                            Number: num,
                            Image: value || '',
                            Name: `Badge ${num}`
                        });
                    }
                }
            }
        } catch (e) {
            console.error("Failed to parse badges table:", e);
        }
    } catch (e) {
        console.error("Failed to extract badges:", e);
    }
    return badges.sort((a, b) => a.Number - b.Number);
}

function mapNatureKeyToStat(key: string): string | null {
    const mapping: { [key: string]: string } = {
        'Atk': 'Attack',
        'Def': 'Defense',
        'Spe': 'Speed',
        'SpA': 'SpecialAttack',
        'SpD': 'SpecialDefense',
        'None': 'None'
    };
    return mapping[key] || null;
}

function parseStatusTable(tableContent: string): any[] {
    const statusEffects: any[] = [];
    try {
        // Parse the table content
        const ast = luaparse.parse(`t = {${tableContent}}`);
        const tableNode = ast.body[0].init[0];
        const definitions = astNodeToValue(tableNode);
        if (definitions && typeof definitions === 'object') {
            // Status effect names and descriptions
            const statusNames: { [key: string]: string } = {
                'BRN': 'Burn',
                'PAR': 'Paralysis',
                'PSN': 'Poison',
                'TOX': 'Badly Poisoned',
                'SLP': 'Sleep',
                'FRZ': 'Freeze'
            };
            
            const statusDescriptions: { [key: string]: string } = {
                'BRN': 'Reduces Attack and deals damage each turn.',
                'PAR': 'Reduces Speed and may prevent movement.',
                'PSN': 'Deals damage each turn.',
                'TOX': 'Deals increasing damage each turn.',
                'SLP': 'Prevents action for 1-3 turns.',
                'FRZ': 'Prevents action until thawed.'
            };
            
            for (const [key, value] of Object.entries(definitions)) {
                if (value && typeof value === 'object') {
                    statusEffects.push({
                        Id: key,
                        Name: statusNames[key] || key,
                        Code: key,
                        Description: statusDescriptions[key] || '',
                        Color: value.Color,
                        StrokeColor: value.StrokeColor,
                        IsVolatile: value.IsVolatile || false,
                        ...value
                    });
                }
            }
        }
    } catch (e) {
        console.error("Failed to parse status effects table:", e);
    }
    return statusEffects;
}

function extractSpeciesAbilities(content: string) {
    const speciesAbilities: any = {};
    try {
        // Use regex to extract the table content (after the type annotation)
        const match = content.match(/local SpeciesAbilities.*?=\s*\{([\s\S]*?)\}\s*return/);
        if (!match) {
            // Try without return statement
            const altMatch = content.match(/SpeciesAbilities.*?=\s*\{([\s\S]*?)\}\s*(?:return|$)/);
            if (!altMatch) {
                console.error("Could not find SpeciesAbilities table");
                return {};
            }
            const tableContent = altMatch[1];
            try {
                const ast = luaparse.parse(`t = {${tableContent}}`);
                const tableNode = ast.body[0].init[0];
                const data = astNodeToValue(tableNode);
                if (data && typeof data === 'object') {
                    return data;
                }
            } catch (e2) {
                console.error("Failed to parse SpeciesAbilities table:", e2);
            }
            return {};
        }
        
        const tableContent = match[1];
        try {
            const ast = luaparse.parse(`t = {${tableContent}}`);
            const tableNode = ast.body[0].init[0];
            const data = astNodeToValue(tableNode);
            if (data && typeof data === 'object') {
                return data;
            }
        } catch (e) {
            console.error("Failed to parse SpeciesAbilities table:", e);
        }
    } catch (e) {
        console.error("Failed to extract SpeciesAbilities:", e);
    }
    return speciesAbilities;
}

function astNodeToValue(node: any): any {
    if (!node) return null;
    
    switch (node.type) {
        case 'StringLiteral':
            // luaparse provides both raw (with quotes) and value (without)
            // Sometimes value is null but raw exists
            if (node.value !== undefined && node.value !== null) {
                return node.value;
            }
            // Fallback: strip quotes from raw if needed
            if (node.raw) {
                const raw = node.raw;
                // Remove surrounding quotes
                if ((raw.startsWith('"') && raw.endsWith('"')) || (raw.startsWith("'") && raw.endsWith("'"))) {
                    return raw.slice(1, -1);
                }
                return raw;
            }
            return null;
        case 'NumericLiteral':
            return node.value;
        case 'BooleanLiteral':
            return node.value;
        case 'NilLiteral':
            return null;
        case 'TableConstructorExpression':
            const obj: any = {};
            const arr: any[] = [];
            let isArray = true;
            let hasNumericKeys = false;
            
            node.fields.forEach((field: any) => {
                if (field.type === 'TableValue') {
                    arr.push(astNodeToValue(field.value));
                } else if (field.type === 'TableKeyString') {
                    isArray = false;
                    obj[field.key.name] = astNodeToValue(field.value);
                } else if (field.type === 'TableKey') {
                    isArray = false;
                    const key = astNodeToValue(field.key);
                    // Check if key is numeric (for array-like tables)
                    if (typeof key === 'number') {
                        hasNumericKeys = true;
                        arr[key - 1] = astNodeToValue(field.value); // Lua arrays are 1-indexed
                    } else {
                        obj[key] = astNodeToValue(field.value);
                    }
                }
            });
            
            // If we have numeric keys, return array (fill gaps with null)
            if (hasNumericKeys && arr.length > 0) {
                return arr;
            }
            return isArray && arr.length > 0 ? arr : (Object.keys(obj).length > 0 ? obj : (isArray ? [] : {}));
        case 'UnaryExpression':
             if (node.operator === '-') {
                 return -astNodeToValue(node.argument);
             }
             return astNodeToValue(node.argument);
        case 'BinaryExpression':
            return null;
        case 'MemberExpression':
            // Handle Types.Fighting -> "Fighting"
            if (node.indexer === '.' && node.identifier) {
                 return node.identifier.name;
            }
            return null;
        case 'CallExpression':
            if (node.base && node.base.type === 'MemberExpression' && node.base.identifier && node.base.identifier.name === 'new' && node.base.base && node.base.base.name === 'Color3') {
                 const args = node.arguments.map(astNodeToValue).filter(a => a !== null);
                 if (args.length >= 3) {
                     return { r: args[0], g: args[1], b: args[2] };
                 }
            }
            return null;
        default:
            // Log unknown types for debugging
            if (node.type && !['Identifier', 'Comment'].includes(node.type)) {
                console.warn(`Unknown AST node type: ${node.type}`);
            }
            return null;
    }
}

function main() {
    console.log("Starting extraction...");
    
    // Extract abilities first (needed for creature enhancement)
    let speciesAbilitiesData: any = {};
    try {
        const speciesAbilitiesRaw = parseLuaFile(PATHS.speciesAbilities);
        speciesAbilitiesData = extractSpeciesAbilities(speciesAbilitiesRaw);
        console.log(`Extracted species abilities for ${Object.keys(speciesAbilitiesData).length} species.`);
    } catch(e) { 
        console.error("Error extracting species abilities:", e); 
    }
    
    try {
        const abilitiesRaw = parseLuaFile(PATHS.abilities);
        const abilities = extractAbilities(abilitiesRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'abilities.json'), JSON.stringify(abilities, null, 2));
        console.log(`Extracted ${abilities.length} abilities.`);
    } catch(e) { console.error("Error extracting abilities:", e); }
    
    try {
        const creaturesRaw = parseLuaFile(PATHS.creatures);
        const creatures = extractCreatures(creaturesRaw);
        
        // Enhance creatures with abilities from SpeciesAbilities
        creatures.forEach(creature => {
            // Try both Name and Id for lookup
            const speciesAbilities = speciesAbilitiesData[creature.Name] || speciesAbilitiesData[creature.Id];
            if (speciesAbilities && Array.isArray(speciesAbilities)) {
                creature.Abilities = speciesAbilities.map((entry: any) => ({
                    Name: entry.Name || entry.name,
                    Chance: entry.Chance || entry.chance || 0
                }));
            }
        });
        
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'creatures.json'), JSON.stringify(creatures, null, 2));
        console.log(`Extracted ${creatures.length} creatures.`);
    } catch(e) { console.error("Error extracting creatures:", e); }

    try {
        const itemsRaw = parseLuaFile(PATHS.items);
        const items = extractItems(itemsRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'items.json'), JSON.stringify(items, null, 2));
        console.log(`Extracted ${items.length} items.`);
    } catch(e) { console.error("Error extracting items:", e); }

    try {
        const movesRaw = parseLuaFile(PATHS.moves);
        const moves = extractMoves(movesRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'moves.json'), JSON.stringify(moves, null, 2));
        console.log(`Extracted ${moves.length} moves.`);
    } catch(e) { console.error("Error extracting moves:", e); }
    
    try {
        const locRaw = parseLuaFile(PATHS.locations);
        const locations = extractLocations(locRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'locations.json'), JSON.stringify(locations, null, 2));
        console.log(`Extracted ${locations.length} locations.`);
    } catch(e) { console.error("Error extracting locations:", e); }
    
    try {
        const typesRaw = parseLuaFile(PATHS.typeChart);
        const types = extractTypes(typesRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'types.json'), JSON.stringify(types, null, 2));
        console.log(`Extracted types chart.`);
    } catch(e) { console.error("Error extracting types:", e); }
    
    try {
        const statusRaw = parseLuaFile(PATHS.status);
        const statusEffects = extractStatusEffects(statusRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'status.json'), JSON.stringify(statusEffects, null, 2));
        console.log(`Extracted ${statusEffects.length} status effects.`);
    } catch(e) { console.error("Error extracting status effects:", e); }
    
    try {
        const weatherRaw = parseLuaFile(PATHS.weather);
        const weatherTypes = extractWeather(weatherRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'weather.json'), JSON.stringify(weatherTypes, null, 2));
        console.log(`Extracted ${weatherTypes.length} weather types.`);
    } catch(e) { console.error("Error extracting weather:", e); }
    
    try {
        const naturesRaw = parseLuaFile(PATHS.natures);
        const natures = extractNatures(naturesRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'natures.json'), JSON.stringify(natures, null, 2));
        console.log(`Extracted ${natures.length} natures.`);
    } catch(e) { console.error("Error extracting natures:", e); }
    
    try {
        const challengesRaw = parseLuaFile(PATHS.challenges);
        const challenges = extractChallenges(challengesRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'challenges.json'), JSON.stringify(challenges, null, 2));
        console.log(`Extracted ${challenges.daily.length} daily and ${challenges.weekly.length} weekly challenges.`);
    } catch(e) { console.error("Error extracting challenges:", e); }
    
    try {
        const badgesRaw = parseLuaFile(PATHS.badges);
        const badges = extractBadges(badgesRaw);
        fs.writeFileSync(path.join(WIKI_DATA_DIR, 'badges.json'), JSON.stringify(badges, null, 2));
        console.log(`Extracted ${badges.length} badges.`);
    } catch(e) { console.error("Error extracting badges:", e); }
}

main();

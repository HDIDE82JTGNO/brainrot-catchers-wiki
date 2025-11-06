-- Natures.lua
-- Defines Pokemon-style natures and applies modifiers to available stats (Attack, Defense, Speed)
-- This code adapts Sp. Atk/Sp. Def natures to the game's stat set by remapping to Attack/Defense/Speed.

local Natures = {}

-- Internal representation uses canonical keys: "Atk", "Def", "Spe", "SpA", "SpD", or "None"
local NATURE_DEFS: { [string]: { inc: string, dec: string } } = {
    Hardy   = { inc = "None", dec = "None" },
    Lonely  = { inc = "Atk",  dec = "Def"  },
    Brave   = { inc = "Atk",  dec = "Spe"  },
    Adamant = { inc = "Atk",  dec = "SpA"  },
    Naughty = { inc = "Atk",  dec = "SpD"  },

    Bold    = { inc = "Def",  dec = "Atk"  },
    Docile  = { inc = "None", dec = "None" },
    Relaxed = { inc = "Def",  dec = "Spe"  },
    Impish  = { inc = "Def",  dec = "SpA"  },
    Lax     = { inc = "Def",  dec = "SpD"  },

    Timid   = { inc = "Spe",  dec = "Atk"  },
    Hasty   = { inc = "Spe",  dec = "Def"  },
    Serious = { inc = "None", dec = "None" },
    Jolly   = { inc = "Spe",  dec = "SpA"  },
    Naive   = { inc = "Spe",  dec = "SpD"  },

    Modest  = { inc = "SpA",  dec = "Atk"  },
    Mild    = { inc = "SpA",  dec = "Def"  },
    Quiet   = { inc = "SpA",  dec = "Spe"  },
    Bashful = { inc = "None", dec = "None" },
    Rash    = { inc = "SpA",  dec = "SpD"  },

    Calm    = { inc = "SpD",  dec = "Atk"  },
    Gentle  = { inc = "SpD",  dec = "Def"  },
    Sassy   = { inc = "SpD",  dec = "Spe"  },
    Careful = { inc = "SpD",  dec = "SpA"  },
    Quirky  = { inc = "None", dec = "None" },
}

local function mapNatureKeyToStat(natureKey: string): string?
    -- Map SpA -> Attack (increase), SpD -> Defense (increase)
    -- For decreases on SpA/SpD, remap to Speed to preserve a trade-off when increase also hits the same bucket
    if natureKey == "Atk" then return "Attack" end
    if natureKey == "Def" then return "Defense" end
    if natureKey == "Spe" then return "Speed" end
    if natureKey == "SpA" then return "Attack" end
    if natureKey == "SpD" then return "Defense" end
    return nil
end

local function pickAlternateStat(avoidStat: string): string
    -- Deterministic rotation to avoid inc/dec colliding on same stat
    if avoidStat == "Attack" then return "Defense" end
    if avoidStat == "Defense" then return "Speed" end
    return "Attack" -- from Speed -> Attack
end

function Natures.GetNature(natureName: string): { inc: string, dec: string }?
    return NATURE_DEFS[natureName]
end

function Natures.GetRandomNature(): string
    local keys = {}
    for name, _ in pairs(NATURE_DEFS) do
        keys[#keys + 1] = name
    end
    if #keys == 0 then return "Hardy" end
    local idx = math.random(1, #keys)
    return keys[idx]
end

-- Apply nature modifiers to a StatBlock (Attack, Defense, Speed). HP is never modified.
function Natures.ApplyNatureModifiers(stats: { [string]: number }, natureName: string): { [string]: number }
    if type(stats) ~= "table" then return stats end
    local def = NATURE_DEFS[natureName]
    if not def or (def.inc == "None" and def.dec == "None") then
        return stats
    end

    local incStat = mapNatureKeyToStat(def.inc)
    local decStat = mapNatureKeyToStat(def.dec)

    -- Prevent increase and decrease from targeting the same final stat
    if incStat and decStat and incStat == decStat then
        decStat = pickAlternateStat(incStat)
    end

    local modified = {
        HP = stats.HP,
        Attack = stats.Attack,
        Defense = stats.Defense,
        Speed = stats.Speed,
    }

    if incStat and modified[incStat] then
        modified[incStat] = math.floor(modified[incStat] * 1.1 + 0.5)
    end
    if decStat and modified[decStat] then
        modified[decStat] = math.max(1, math.floor(modified[decStat] * 0.9 + 0.5))
    end

    return modified
end

return Natures



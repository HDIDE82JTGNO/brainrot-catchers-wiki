--!strict
-- Abilities.lua
-- Shared ability utilities and simple trigger effects

local Abilities = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovesModule = require(ReplicatedStorage.Shared.Moves)

-- Species ability tables (probabilities)
local SpeciesAbilities = require(ReplicatedStorage.Shared:WaitForChild("SpeciesAbilities"))

local function normalize(name: string?): string
    return string.lower(tostring(name or ""))
end

function Abilities.GetName(creature: any): string?
    return type(creature) == "table" and creature.Ability or nil
end

function Abilities.Has(creature: any, abilityName: string): boolean
    local a = Abilities.GetName(creature)
    return a ~= nil and normalize(a) == normalize(abilityName)
end

-- Select an ability for a species using probabilities table
function Abilities.SelectAbility(speciesName: string, inWild: boolean): string?
    local pool = SpeciesAbilities[speciesName]
    if not pool or type(pool) ~= "table" then return nil end
    -- Sum weights
    local total = 0
    for _, entry in ipairs(pool) do total += (entry.Chance or 0) end
    if total <= 0 then return (pool[1] and pool[1].Name) or nil end
    local roll = math.random() * total
    local acc = 0
    for _, entry in ipairs(pool) do
        acc += (entry.Chance or 0)
        if roll <= acc then
            return entry.Name
        end
    end
    return (pool[#pool] and pool[#pool].Name) or nil
end

-- Priority bonus for abilities like Gale Wings (aka Wind Wings) or Trickster (status moves)
function Abilities.PriorityBonus(attacker: any, moveName: string?): number
    if not attacker or not moveName then return 0 end
    local ability = normalize(Abilities.GetName(attacker))
    local move = MovesModule[moveName]
    if not move then return 0 end
    local moveTypeName = type(move.Type) == "string" and move.Type or nil
    -- Gale Wings / Wind Wings: Flying-type moves get +1 priority
    if (ability == "gale wings" or ability == "wind wings") and moveTypeName == "Flying" then
        return 1
    end
    -- Trickster: status moves (BasePower == 0) get +1 priority
    if ability == "trickster" then
        if (move.BasePower or 0) <= 0 and (not move.HealsPercent) then
            return 1
        end
    end
    return 0
end

-- Convert move type for Pixelate/Refrigerate and similar
function Abilities.ModifyMoveType(attacker: any, moveTypeName: string?): string?
    local ability = normalize(Abilities.GetName(attacker))
    if not moveTypeName then return moveTypeName end
    if ability == "pixelate" and moveTypeName == "Normal" then
        return "Fairy"
    end
    if ability == "refrigerate" and moveTypeName == "Normal" then
        return "Ice"
    end
    -- Twirlina/Ballerina: some variants convert all moves to Fairy; spec uses Pixelate/Fairy Sense separately
    return moveTypeName
end

-- Ability-based immunity overrides (e.g., Magic Eyes lets Normal/Fighting hit Ghost)
function Abilities.OverrideImmunity(attacker: any, defender: any, moveTypeName: string, typeEffectiveness: number): number
    local abil = normalize(Abilities.GetName(attacker))
    if typeEffectiveness == 0 then
        if abil == "magic eyes" and (moveTypeName == "Normal" or moveTypeName == "Fighting") then
            return 1 -- ignore Ghost immunity for these types
        end
    end
    return typeEffectiveness
end

-- Multiplicative damage modifiers from abilities (attacker and defender)
function Abilities.DamageMultiplier(attacker: any, defender: any, moveTypeName: string, moveName: string?): number
    local mul = 1.0
    local a = normalize(Abilities.GetName(attacker))
    local d = normalize(Abilities.GetName(defender))
    
    -- Get attacker HP percentage
    local attackerHPPercent = 100
    if attacker.MaxStats and attacker.MaxStats.HP and attacker.MaxStats.HP > 0 then
        attackerHPPercent = ((attacker.Stats and attacker.Stats.HP) or 0) / attacker.MaxStats.HP * 100
    elseif attacker.CurrentHP then
        attackerHPPercent = attacker.CurrentHP
    end

    -- Attacker boosts
    if a == "scrapper" and moveTypeName == "Normal" then mul *= 1.2 end
    if (a == "fairy sense" or a == "fairy aura") and moveTypeName == "Fairy" then mul *= 1.2 end
    if a == "steel jaw" and moveTypeName == "Bite" then 
        -- Note: Requires move flags or name checking. Assuming bite moves contain "Bite" or "Crunch" for now.
        if moveName and (string.find(moveName, "Bite") or string.find(moveName, "Crunch")) then
             mul *= 1.5 
        end
    end
    if a == "sharp fins" and moveTypeName == "Water" then
        -- Assuming physical water moves; for now apply to all water moves if we don't have categories
        mul *= 1.5
    end
    if (a == "blaze" or a == "fireup") and moveTypeName == "Fire" and attackerHPPercent <= 33 then
        mul *= 1.5
    end
    if a == "permeate" and moveTypeName == "Grass" and attackerHPPercent <= 25 then
        mul *= 1.5
    end

    -- Defender reductions
    if d == "thickness" and (moveTypeName == "Fire" or moveTypeName == "Ice") then mul *= 0.5 end
    if d == "metallic glide" then
        -- Assuming physical moves; applies reduction
        mul *= 0.8
    end
    
    return mul
end

-- Check for status immunity
function Abilities.IsImmuneToStatus(creature: any, status: string, weather: string?): boolean
    local ability = normalize(Abilities.GetName(creature))
    
    if status == "Paralysis" and ability == "lithe" then return true end
    if status == "Sleep" and ability == "arcane veil" then return true end
    if ability == "grass veil" and weather == "Sunlight" then return true end
    
    return false
end

-- Check for recoil negation
function Abilities.NegatesRecoil(creature: any): boolean
    local ability = normalize(Abilities.GetName(creature))
    return ability == "hard head"
end

-- Check for entry ability
function Abilities.OnEntry(creature: any): string?
    local ability = normalize(Abilities.GetName(creature))
    if ability == "intimidate" or ability == "menace" then return "Intimidate" end
    if ability == "solar wrath" then return "Sunlight" end
    return nil
end

-- Crit chance modifier (stage bonus)
function Abilities.GetCritStageBonus(creature: any, opponentUsedMove: boolean?): number
    local ability = normalize(Abilities.GetName(creature))
    if ability == "great fortune" then return 1 end
    if ability == "spy lens" and opponentUsedMove then return 1 end
    return 0
end

-- Check for guaranteed escape
function Abilities.GuaranteesEscape(creature: any): boolean
    local ability = normalize(Abilities.GetName(creature))
    return ability == "run away"
end

-- Check if ability prevents escape
function Abilities.TrapsOpponent(creature: any): boolean
    local ability = normalize(Abilities.GetName(creature))
    return ability == "elastic trap" or ability == "shadow tag" or ability == "arena trap"
end

return Abilities



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
function Abilities.DamageMultiplier(attacker: any, defender: any, moveTypeName: string): number
    local mul = 1.0
    local a = normalize(Abilities.GetName(attacker))
    local d = normalize(Abilities.GetName(defender))
    -- Attacker boosts
    if a == "scrapper" and moveTypeName == "Normal" then mul *= 1.2 end
    if (a == "fairy sense" or a == "fairy aura") and moveTypeName == "Fairy" then mul *= 1.2 end
    if a == "steel jaw" and moveTypeName == "Bite" then -- placeholder; depends on move flags
        -- If you later tag biting moves in MovesModule, apply here
    end
    -- Defender reductions
    if d == "thickness" and (moveTypeName == "Fire" or moveTypeName == "Ice") then mul *= 0.5 end
    if d == "metallic glide" then
        -- If physical category is tracked, apply small reduction (e.g., 0.9)
    end
    return mul
end

return Abilities



--!strict
-- Abilities.lua
-- Shared ability utilities and trigger effects
-- Contains definitions for all abilities and their battle effects

local Abilities = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MovesModule = require(ReplicatedStorage.Shared.Moves)

-- Species ability tables (probabilities)
local SpeciesAbilities = require(ReplicatedStorage.Shared:WaitForChild("SpeciesAbilities"))

-- Ability definitions with their effects
-- Each ability has: Name, Description, TriggerType, and effect-specific fields
Abilities.Definitions = {
	-- Fire-type boosters
	["Fireup"] = {
		Name = "Fireup",
		Description = "Powers up Fire-type moves when HP is low.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Fire",
		HPThreshold = 33,
		Multiplier = 1.5,
	},
	["Blaze"] = {
		Name = "Blaze",
		Description = "Powers up Fire-type moves when HP is low.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Fire",
		HPThreshold = 33,
		Multiplier = 1.5,
	},
	
	-- Entry abilities
	["Menace"] = {
		Name = "Menace",
		Description = "Lowers the foe's Attack when entering battle.",
		TriggerType = "OnEntry",
		Effect = "Intimidate",
		StatChange = { Stat = "Attack", Stages = -1, Target = "Foe" },
	},
	["Intimidate"] = {
		Name = "Intimidate",
		Description = "Lowers the foe's Attack when entering battle.",
		TriggerType = "OnEntry",
		Effect = "Intimidate",
		StatChange = { Stat = "Attack", Stages = -1, Target = "Foe" },
	},
	["Solar Wrath"] = {
		Name = "Solar Wrath",
		Description = "Summons harsh sunlight when entering battle.",
		TriggerType = "OnEntry",
		Effect = "Sunlight",
	},
	
	-- Priority modifiers
	["Trickster"] = {
		Name = "Trickster",
		Description = "Gives priority to status moves.",
		TriggerType = "PriorityBonus",
		Condition = "StatusMove",
		Bonus = 1,
	},
	["Wind Wings"] = {
		Name = "Wind Wings",
		Description = "Gives priority to Flying-type moves.",
		TriggerType = "PriorityBonus",
		TypeBoost = "Flying",
		Bonus = 1,
	},
	["Gale Wings"] = {
		Name = "Gale Wings",
		Description = "Gives priority to Flying-type moves.",
		TriggerType = "PriorityBonus",
		TypeBoost = "Flying",
		Bonus = 1,
	},
	
	-- Type conversion abilities
	["Pixelate"] = {
		Name = "Pixelate",
		Description = "Normal-type moves become Fairy-type and get a power boost.",
		TriggerType = "TypeConversion",
		FromType = "Normal",
		ToType = "Fairy",
		DamageBoost = 1.2,
	},
	["Refrigerate"] = {
		Name = "Refrigerate",
		Description = "Normal-type moves become Ice-type and get a power boost.",
		TriggerType = "TypeConversion",
		FromType = "Normal",
		ToType = "Ice",
		DamageBoost = 1.2,
	},
	
	-- Immunity override abilities
	["Magic Eyes"] = {
		Name = "Magic Eyes",
		Description = "Normal and Fighting-type moves can hit Ghost-types.",
		TriggerType = "ImmunityOverride",
		Types = {"Normal", "Fighting"},
		IgnoresImmunity = "Ghost",
	},
	
	-- Status immunity abilities
	["Lithe"] = {
		Name = "Lithe",
		Description = "Prevents paralysis.",
		TriggerType = "StatusImmunity",
		Immunity = "PAR",
	},
	["Arcane Veil"] = {
		Name = "Arcane Veil",
		Description = "Prevents sleep.",
		TriggerType = "StatusImmunity",
		Immunity = "SLP",
	},
	["Grass Veil"] = {
		Name = "Grass Veil",
		Description = "Prevents status conditions in sunlight.",
		TriggerType = "StatusImmunity",
		Immunity = "All",
		WeatherCondition = "Sunlight",
	},
	["Absolute Focus"] = {
		Name = "Absolute Focus",
		Description = "Prevents flinching.",
		TriggerType = "FlinchImmunity",
	},
	
	-- Speed modifiers
	["Swift Current"] = {
		Name = "Swift Current",
		Description = "Boosts Speed in rain or when hit by a Water-type move.",
		TriggerType = "SpeedModifier",
		WeatherCondition = "Rain",
		OnHitType = "Water",
		StatChange = { Stat = "Speed", Stages = 1 },
	},
	["Sand Speed"] = {
		Name = "Sand Speed",
		Description = "Doubles Speed in a sandstorm.",
		TriggerType = "SpeedModifier",
		WeatherCondition = "Sandstorm",
		SpeedMultiplier = 2,
	},
	["Steadfast"] = {
		Name = "Steadfast",
		Description = "Boosts Speed when flinched.",
		TriggerType = "OnFlinch",
		StatChange = { Stat = "Speed", Stages = 1 },
	},
	["Steadspeed"] = {
		Name = "Steadspeed",
		Description = "Gradually boosts Speed over time.",
		TriggerType = "EndOfTurn",
		StatChange = { Stat = "Speed", Stages = 1 },
		Chance = 30, -- 30% chance each turn
	},
	
	-- Damage boosters
	["Scrapper"] = {
		Name = "Scrapper",
		Description = "Powers up Normal-type moves.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Normal",
		Multiplier = 1.2,
	},
	["Fairy Sense"] = {
		Name = "Fairy Sense",
		Description = "Powers up Fairy-type moves.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Fairy",
		Multiplier = 1.2,
	},
	["Sharp Fins"] = {
		Name = "Sharp Fins",
		Description = "Powers up Water-type moves.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Water",
		Multiplier = 1.5,
	},
	["Steel Jaw"] = {
		Name = "Steel Jaw",
		Description = "Powers up biting moves.",
		TriggerType = "DamageMultiplier",
		MoveFlag = "Bite",
		Multiplier = 1.5,
	},
	["Big Beaks"] = {
		Name = "Big Beaks",
		Description = "Powers up pecking moves.",
		TriggerType = "DamageMultiplier",
		MoveFlag = "Peck",
		Multiplier = 1.3,
	},
	["Permeate"] = {
		Name = "Permeate",
		Description = "Powers up Grass-type moves when HP is low.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Grass",
		HPThreshold = 25,
		Multiplier = 1.5,
	},
	
	-- Damage reduction
	["Thickness"] = {
		Name = "Thickness",
		Description = "Reduces damage from Fire and Ice-type moves.",
		TriggerType = "DamageReduction",
		Types = {"Fire", "Ice"},
		Multiplier = 0.5,
	},
	["Metallic Glide"] = {
		Name = "Metallic Glide",
		Description = "Reduces physical damage taken.",
		TriggerType = "DamageReduction",
		Category = "Physical",
		Multiplier = 0.8,
	},
	
	-- Contact damage
	["Needle Guard"] = {
		Name = "Needle Guard",
		Description = "Damages attackers that make contact.",
		TriggerType = "OnContact",
		DamagePercent = 12.5, -- 1/8 of attacker's max HP
	},
	["Corrosive Skin"] = {
		Name = "Corrosive Skin",
		Description = "May poison attackers that make contact.",
		TriggerType = "OnContact",
		StatusEffect = "PSN",
		Chance = 30,
	},
	
	-- Type absorption
	["Sap Siphon"] = {
		Name = "Sap Siphon",
		Description = "Absorbs Grass-type moves to restore HP.",
		TriggerType = "TypeAbsorption",
		AbsorbType = "Grass",
		HealPercent = 25,
	},
	["Water Press"] = {
		Name = "Water Press",
		Description = "Absorbs Water-type moves to boost Attack.",
		TriggerType = "TypeAbsorption",
		AbsorbType = "Water",
		StatChange = { Stat = "Attack", Stages = 1 },
	},
	
	-- Recoil prevention
	["Hard Head"] = {
		Name = "Hard Head",
		Description = "Prevents recoil damage.",
		TriggerType = "RecoilImmunity",
	},
	
	-- Escape abilities
	["Run Away"] = {
		Name = "Run Away",
		Description = "Guarantees escape from wild battles.",
		TriggerType = "GuaranteedEscape",
	},
	
	-- Trapping abilities
	["Elastic Trap"] = {
		Name = "Elastic Trap",
		Description = "Prevents the foe from escaping.",
		TriggerType = "TrapOpponent",
	},
	["Bubble Trap"] = {
		Name = "Bubble Trap",
		Description = "Prevents the foe from escaping.",
		TriggerType = "TrapOpponent",
	},
	["Sticky Goo"] = {
		Name = "Sticky Goo",
		Description = "Prevents the foe from escaping and may slow them.",
		TriggerType = "TrapOpponent",
		SpeedDrop = true,
	},
	
	-- Critical hit modifiers
	["Great Fortune"] = {
		Name = "Great Fortune",
		Description = "Boosts critical hit ratio.",
		TriggerType = "CritBonus",
		Stages = 1,
	},
	["Spy Lens"] = {
		Name = "Spy Lens",
		Description = "Boosts critical hit ratio after the foe attacks.",
		TriggerType = "CritBonus",
		Condition = "AfterFoeMove",
		Stages = 1,
	},
	
	-- Accuracy abilities
	["Recon Flight"] = {
		Name = "Recon Flight",
		Description = "Moves never miss.",
		TriggerType = "AccuracyBypass",
	},
	["Stealth Feathers"] = {
		Name = "Stealth Feathers",
		Description = "Boosts evasion.",
		TriggerType = "EvasionBoost",
		Stages = 1,
	},
	
	-- Weather healing
	["Sun Bounty"] = {
		Name = "Sun Bounty",
		Description = "Doubles Speed in sunlight.",
		TriggerType = "SpeedModifier",
		WeatherCondition = "Sunlight",
		SpeedMultiplier = 2,
	},
	["Desert Reservoir"] = {
		Name = "Desert Reservoir",
		Description = "Recovers HP in sunlight.",
		TriggerType = "WeatherHeal",
		WeatherCondition = "Sunlight",
		HealPercent = 6.25, -- 1/16 per turn
	},
	
	-- Misc abilities
	["Synchronize"] = {
		Name = "Synchronize",
		Description = "Passes status conditions to the attacker.",
		TriggerType = "OnStatus",
		Effect = "PassToAttacker",
	},
	["Magic Mirror"] = {
		Name = "Magic Mirror",
		Description = "Reflects status moves back at the attacker.",
		TriggerType = "OnStatusMove",
		Effect = "Reflect",
	},
	["Matrix Breaker"] = {
		Name = "Matrix Breaker",
		Description = "Ignores the foe's ability.",
		TriggerType = "AbilityBypass",
	},
	["Amphibious"] = {
		Name = "Amphibious",
		Description = "Immune to Water-type moves.",
		TriggerType = "TypeImmunity",
		ImmuneType = "Water",
	},
	["Seed Shield"] = {
		Name = "Seed Shield",
		Description = "Reduces damage from Grass-type moves.",
		TriggerType = "DamageReduction",
		Types = {"Grass"},
		Multiplier = 0.5,
	},
	["Sludge Shield"] = {
		Name = "Sludge Shield",
		Description = "Reduces damage from Poison-type moves and prevents poisoning.",
		TriggerType = "DamageReduction",
		Types = {"Poison"},
		Multiplier = 0.5,
		StatusImmunity = "PSN",
	},
	["Jetstream"] = {
		Name = "Jetstream",
		Description = "Boosts Speed when using Flying-type moves.",
		TriggerType = "OnMoveUse",
		TypeCondition = "Flying",
		StatChange = { Stat = "Speed", Stages = 1 },
	},
	["Overdrive"] = {
		Name = "Overdrive",
		Description = "Greatly boosts Attack when HP is low, but takes recoil.",
		TriggerType = "DamageMultiplier",
		HPThreshold = 25,
		Multiplier = 2.0,
		TakesRecoil = true,
	},
	["Triple Kick"] = {
		Name = "Triple Kick",
		Description = "Multi-hit moves are more likely to hit maximum times.",
		TriggerType = "MultiHitBonus",
	},
	["Drumming Beat"] = {
		Name = "Drumming Beat",
		Description = "Sound-based moves are powered up.",
		TriggerType = "DamageMultiplier",
		MoveFlag = "Sound",
		Multiplier = 1.3,
	},
	["Stubborn Waddle"] = {
		Name = "Stubborn Waddle",
		Description = "Cannot be forced to switch out.",
		TriggerType = "SwitchImmunity",
	},
	["Mudslide"] = {
		Name = "Mudslide",
		Description = "Ground-type moves get a power boost.",
		TriggerType = "DamageMultiplier",
		TypeBoost = "Ground",
		Multiplier = 1.3,
	},
	["Waddle Stomp"] = {
		Name = "Waddle Stomp",
		Description = "Contact moves may cause the foe to flinch.",
		TriggerType = "OnContactAttack",
		Effect = "Flinch",
		Chance = 10,
	},
	["Sand Cover"] = {
		Name = "Sand Cover",
		Description = "Boosts evasion in a sandstorm.",
		TriggerType = "EvasionBoost",
		WeatherCondition = "Sandstorm",
		Stages = 1,
	},
	["Dispirit"] = {
		Name = "Dispirit",
		Description = "Lowers the foe's Attack when entering battle.",
		TriggerType = "OnEntry",
		Effect = "Intimidate",
		StatChange = { Stat = "Attack", Stages = -1, Target = "Foe" },
	},
	["Ball Room"] = {
		Name = "Ball Room",
		Description = "Powers up ally Fairy-type moves.",
		TriggerType = "AllyBoost",
		TypeBoost = "Fairy",
		Multiplier = 1.3,
	},
}

-- Helper function to normalize ability names for comparison
local function normalize(name: string?): string
	return string.lower(tostring(name or ""))
end

-- Get the ability name from a creature
function Abilities.GetName(creature: any): string?
	return type(creature) == "table" and creature.Ability or nil
end

-- Get the ability definition
function Abilities.GetDefinition(abilityName: string?): any
	if not abilityName then return nil end
	-- Try exact match first
	if Abilities.Definitions[abilityName] then
		return Abilities.Definitions[abilityName]
	end
	-- Try normalized match
	for name, def in pairs(Abilities.Definitions) do
		if normalize(name) == normalize(abilityName) then
			return def
		end
	end
	return nil
end

-- Check if creature has a specific ability
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
	return moveTypeName
end

-- Ability-based immunity overrides (e.g., Magic Eyes lets Normal/Fighting hit Ghost)
function Abilities.OverrideImmunity(attacker: any, defender: any, moveTypeName: string, typeEffectiveness: number): number
	local abil = normalize(Abilities.GetName(attacker))
	if typeEffectiveness == 0 then
		if abil == "magic eyes" and (moveTypeName == "Normal" or moveTypeName == "Fighting") then
			return 1 -- ignore Ghost immunity for these types
		end
		-- Matrix Breaker ignores defender abilities
		if abil == "matrix breaker" then
			return 1
		end
	end
	return typeEffectiveness
end

-- Check if defender has type immunity ability
function Abilities.CheckTypeImmunity(defender: any, moveTypeName: string): (boolean, string?)
	local abil = normalize(Abilities.GetName(defender))
	
	-- Amphibious - immune to Water
	if abil == "amphibious" and moveTypeName == "Water" then
		return true, "Amphibious"
	end
	
	-- Sap Siphon - immune to Grass (heals instead)
	if abil == "sap siphon" and moveTypeName == "Grass" then
		return true, "Sap Siphon"
	end
	
	-- Water Press - immune to Water (boosts Attack instead)
	if abil == "water press" and moveTypeName == "Water" then
		return true, "Water Press"
	end
	
	return false, nil
end

-- Check for ability activation when hit by a specific type
function Abilities.OnHitByType(defender: any, moveTypeName: string): { Ability: string, Effect: string, StatChange: { Stat: string, Stages: number }? }?
	local abil = normalize(Abilities.GetName(defender))
	local abilityName = Abilities.GetName(defender)
	
	-- Swift Current - Speed boost when hit by Water
	if abil == "swift current" and moveTypeName == "Water" then
		return {
			Ability = abilityName or "Swift Current",
			Effect = "speed_boost",
			StatChange = { Stat = "Speed", Stages = 1 },
		}
	end
	
	-- Sap Siphon - Heal when hit by Grass
	if abil == "sap siphon" and moveTypeName == "Grass" then
		return {
			Ability = abilityName or "Sap Siphon",
			Effect = "absorption",
			HealPercent = 25,
		}
	end
	
	-- Water Press - Attack boost when hit by Water
	if abil == "water press" and moveTypeName == "Water" then
		return {
			Ability = abilityName or "Water Press",
			Effect = "attack_boost",
			StatChange = { Stat = "Attack", Stages = 1 },
		}
	end
	
	return nil
end

-- Multiplicative damage modifiers from abilities (attacker and defender)
function Abilities.DamageMultiplier(attacker: any, defender: any, moveTypeName: string, moveName: string?): number
	local mul = 1.0
	local a = normalize(Abilities.GetName(attacker))
	local d = normalize(Abilities.GetName(defender))
	
	-- Get attacker HP percentage
	local attackerHPPercent = 100
	if attacker and attacker.MaxStats and attacker.MaxStats.HP and attacker.MaxStats.HP > 0 then
		attackerHPPercent = ((attacker.Stats and attacker.Stats.HP) or 0) / attacker.MaxStats.HP * 100
	elseif attacker and attacker.CurrentHP then
		attackerHPPercent = attacker.CurrentHP
	end

	-- Attacker boosts
	if a == "scrapper" and moveTypeName == "Normal" then mul *= 1.2 end
	if (a == "fairy sense" or a == "fairy aura") and moveTypeName == "Fairy" then mul *= 1.2 end
	if a == "steel jaw" then 
		if moveName and (string.find(moveName, "Bite") or string.find(moveName, "Crunch") or string.find(moveName, "Fang")) then
			mul *= 1.5 
		end
	end
	if a == "big beaks" then
		if moveName and (string.find(moveName, "Peck") or string.find(moveName, "Beak") or string.find(moveName, "Drill")) then
			mul *= 1.3
		end
	end
	if a == "sharp fins" and moveTypeName == "Water" then
		mul *= 1.5
	end
	if (a == "blaze" or a == "fireup") and moveTypeName == "Fire" and attackerHPPercent <= 33 then
		mul *= 1.5
	end
	if a == "permeate" and moveTypeName == "Grass" and attackerHPPercent <= 25 then
		mul *= 1.5
	end
	if a == "mudslide" and moveTypeName == "Ground" then
		mul *= 1.3
	end
	if a == "drumming beat" then
		-- Check for sound-based moves
		if moveName then
			local moveDef = MovesModule[moveName]
			if moveDef and moveDef.Flags and moveDef.Flags.Sound then
				mul *= 1.3
			end
		end
	end
	if a == "overdrive" and attackerHPPercent <= 25 then
		mul *= 2.0
	end

	-- Pixelate/Refrigerate damage boost for converted moves
	if a == "pixelate" and moveTypeName == "Fairy" then
		-- Check if original move was Normal (already converted)
		mul *= 1.2
	end
	if a == "refrigerate" and moveTypeName == "Ice" then
		mul *= 1.2
	end

	-- Defender reductions
	if d == "thickness" and (moveTypeName == "Fire" or moveTypeName == "Ice") then mul *= 0.5 end
	if d == "metallic glide" then
		mul *= 0.8
	end
	if d == "seed shield" and moveTypeName == "Grass" then
		mul *= 0.5
	end
	if d == "sludge shield" and moveTypeName == "Poison" then
		mul *= 0.5
	end
	
	return mul
end

-- Check for status immunity
function Abilities.IsImmuneToStatus(creature: any, status: string, weather: string?): (boolean, string?)
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if (status == "Paralysis" or status == "PAR") and ability == "lithe" then 
		return true, abilityName 
	end
	if (status == "Sleep" or status == "SLP") and ability == "arcane veil" then 
		return true, abilityName 
	end
	if ability == "grass veil" and weather == "Sunlight" then 
		return true, abilityName 
	end
	if (status == "Poison" or status == "PSN" or status == "TOX") and ability == "sludge shield" then
		return true, abilityName
	end
	
	return false, nil
end

-- Check for flinch immunity
function Abilities.IsImmuneToFlinch(creature: any): (boolean, string?)
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if ability == "absolute focus" or ability == "inner focus" then
		return true, abilityName
	end
	return false, nil
end

-- Check for recoil negation
function Abilities.NegatesRecoil(creature: any): boolean
	local ability = normalize(Abilities.GetName(creature))
	return ability == "hard head"
end

-- Check for entry ability and return the effect type
function Abilities.OnEntry(creature: any): { Effect: string, Ability: string, StatChange: { Stat: string, Stages: number, Target: string }? }?
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if ability == "intimidate" or ability == "menace" or ability == "dispirit" then 
		return {
			Effect = "Intimidate",
			Ability = abilityName or "Menace",
			StatChange = { Stat = "Attack", Stages = -1, Target = "Foe" },
		}
	end
	if ability == "solar wrath" then 
		return {
			Effect = "Sunlight",
			Ability = abilityName or "Solar Wrath",
		}
	end
	return nil
end

-- Get speed modifier from ability
function Abilities.GetSpeedModifier(creature: any, weather: string?): (number, string?)
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if ability == "sand speed" and weather == "Sandstorm" then
		return 2, abilityName
	end
	if ability == "swift current" and weather == "Rain" then
		return 2, abilityName
	end
	if ability == "sun bounty" and weather == "Sunlight" then
		return 2, abilityName
	end
	
	return 1, nil
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
		or ability == "bubble trap" or ability == "sticky goo"
end

-- Check if ability prevents being forced to switch
function Abilities.PreventsForceSwitch(creature: any): boolean
	local ability = normalize(Abilities.GetName(creature))
	return ability == "stubborn waddle" or ability == "suction cups"
end

-- Check for contact damage ability (like Iron Barbs/Rough Skin)
function Abilities.GetContactDamage(defender: any): { Ability: string, DamagePercent: number }?
	local ability = normalize(Abilities.GetName(defender))
	local abilityName = Abilities.GetName(defender)
	
	if ability == "needle guard" then
		return { Ability = abilityName or "Needle Guard", DamagePercent = 12.5 }
	end
	return nil
end

-- Check for contact status ability (like Poison Point/Static)
function Abilities.GetContactStatus(defender: any): { Ability: string, Status: string, Chance: number }?
	local ability = normalize(Abilities.GetName(defender))
	local abilityName = Abilities.GetName(defender)
	
	if ability == "corrosive skin" then
		return { Ability = abilityName or "Corrosive Skin", Status = "PSN", Chance = 30 }
	end
	return nil
end

-- Check for flinch on attack ability
function Abilities.GetFlinchOnAttack(attacker: any): { Ability: string, Chance: number }?
	local ability = normalize(Abilities.GetName(attacker))
	local abilityName = Abilities.GetName(attacker)
	
	if ability == "waddle stomp" then
		return { Ability = abilityName or "Waddle Stomp", Chance = 10 }
	end
	return nil
end

-- Check for end of turn effects
function Abilities.GetEndOfTurnEffect(creature: any, weather: string?): { Ability: string, Effect: string, HealPercent: number?, StatChange: { Stat: string, Stages: number }?, Chance: number? }?
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	-- Desert Reservoir - Heal in sunlight
	if ability == "desert reservoir" and weather == "Sunlight" then
		return {
			Ability = abilityName or "Desert Reservoir",
			Effect = "heal",
			HealPercent = 6.25,
		}
	end
	
	-- Steadspeed - Chance to boost Speed each turn
	if ability == "steadspeed" then
		if math.random(1, 100) <= 30 then
			return {
				Ability = abilityName or "Steadspeed",
				Effect = "speed_boost",
				StatChange = { Stat = "Speed", Stages = 1 },
			}
		end
	end
	
	return nil
end

-- Check for on-flinch effects (like Steadfast)
function Abilities.OnFlinch(creature: any): { Ability: string, StatChange: { Stat: string, Stages: number } }?
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if ability == "steadfast" then
		return {
			Ability = abilityName or "Steadfast",
			StatChange = { Stat = "Speed", Stages = 1 },
		}
	end
	return nil
end

-- Check for synchronize effect (passes status to attacker)
function Abilities.HasSynchronize(creature: any): boolean
	local ability = normalize(Abilities.GetName(creature))
	return ability == "synchronize"
end

-- Check for magic mirror effect (reflects status moves)
function Abilities.HasMagicMirror(creature: any): boolean
	local ability = normalize(Abilities.GetName(creature))
	return ability == "magic mirror"
end

-- Check for evasion boost from ability
function Abilities.GetEvasionBoost(creature: any, weather: string?): (number, string?)
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if ability == "stealth feathers" then
		return 1, abilityName
	end
	if ability == "sand cover" and weather == "Sandstorm" then
		return 1, abilityName
	end
	return 0, nil
end

-- Check for on-move-use effects (like Jetstream)
function Abilities.OnMoveUse(creature: any, moveName: string?, moveTypeName: string?): { Ability: string, StatChange: { Stat: string, Stages: number } }?
	local ability = normalize(Abilities.GetName(creature))
	local abilityName = Abilities.GetName(creature)
	
	if ability == "jetstream" and moveTypeName == "Flying" then
		return {
			Ability = abilityName or "Jetstream",
			StatChange = { Stat = "Speed", Stages = 1 },
		}
	end
	return nil
end

-- Check for accuracy bypass (like No Guard)
function Abilities.BypassesAccuracy(attacker: any): boolean
	local ability = normalize(Abilities.GetName(attacker))
	return ability == "recon flight" or ability == "no guard"
end

-- Check for multi-hit bonus
function Abilities.HasMultiHitBonus(creature: any): boolean
	local ability = normalize(Abilities.GetName(creature))
	return ability == "triple kick" or ability == "skill link"
end

return Abilities
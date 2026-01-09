local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local Natures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Natures"))

local StatCalc = {}

-- Simple stat growth. Tune later to match your game's balance
-- Closer to mainline Pokémon formulas at low levels:
-- HP:      floor(((2*Base + IV) * Level) / 100) + Level + 10
-- Others:  floor(((2*Base + IV) * Level) / 100) + 5
local function calcHP(baseHP: number, level: number, ivHP: number?): number
    level = level or 1
    baseHP = baseHP or 1
    local iv = ivHP or 0
    local val = math.floor((((2 * baseHP + iv) * level) / 100)) + level + 10
    return math.max(1, val)
end

local function calcLinear(base: number, level: number, iv: number?): number
    level = level or 1
    base = base or 1
    iv = iv or 0
    local val = math.floor((((2 * base + iv) * level) / 100)) + 5
    return math.max(1, val)
end

function StatCalc.GetBaseStats(name: string)
	local data = Creatures[name]
	return data and data.BaseStats or nil
end

function StatCalc.GetMaxHP(name: string, level: number): number
	local base = StatCalc.GetBaseStats(name)
	local baseHP = base and base.HP or 1
	return calcHP(baseHP, level)
end

function StatCalc.ComputeStats(name: string, level: number, ivs: {HP: number?, Attack: number?, Defense: number?, SpecialAttack: number?, SpecialDefense: number?, Speed: number?}?, natureName: string?)
	local base = StatCalc.GetBaseStats(name) or {}
	local maxStats = {
		HP = calcHP(base.HP or 1, level, ivs and ivs.HP or 0),
		Attack = calcLinear(base.Attack or 1, level, ivs and ivs.Attack or 0),
		Defense = calcLinear(base.Defense or 1, level, ivs and ivs.Defense or 0),
		SpecialAttack = calcLinear(base.SpecialAttack or 1, level, ivs and ivs.SpecialAttack or 0),
		SpecialDefense = calcLinear(base.SpecialDefense or 1, level, ivs and ivs.SpecialDefense or 0),
		Speed = calcLinear(base.Speed or 1, level, ivs and ivs.Speed or 0),
	}

	-- Apply nature modifiers to non-HP stats if provided
	if natureName then
		local modified = Natures.ApplyNatureModifiers({
			HP = maxStats.HP,
			Attack = maxStats.Attack,
			Defense = maxStats.Defense,
			SpecialAttack = maxStats.SpecialAttack,
			SpecialDefense = maxStats.SpecialDefense,
			Speed = maxStats.Speed,
		}, natureName)
		maxStats.Attack = modified.Attack
		maxStats.Defense = modified.Defense
		maxStats.SpecialAttack = modified.SpecialAttack
		maxStats.SpecialDefense = modified.SpecialDefense
		maxStats.Speed = modified.Speed
	end

	-- For battle usage, current stats default to max (except HP handled by CurrentHP)
	local stats = {
		HP = maxStats.HP,
		Attack = maxStats.Attack,
		Defense = maxStats.Defense,
		SpecialAttack = maxStats.SpecialAttack,
		SpecialDefense = maxStats.SpecialDefense,
		Speed = maxStats.Speed,
	}
	return stats, maxStats
end

return StatCalc



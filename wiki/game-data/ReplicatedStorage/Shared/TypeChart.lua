--!strict
--[[
	TypeChart.lua (Gen 9)
	Offensive type effectiveness chart: attackType -> defenderType -> multiplier

	This is intentionally separate from `Types.lua` (which is used for UI/metadata in this project)
	to avoid mixing defensive relationships with offensive effectiveness.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

local TypeChart = {}

-- Map type definition tables (from `Types.lua`) back to their string names.
local _typeNameByDef: {[any]: string} = {}
do
	for name, def in pairs(Types) do
		_typeNameByDef[def] = name
	end
end

local CHART: {[string]: {[string]: number}} = {
	Normal = { Rock = 0.5, Ghost = 0, Steel = 0.5 },
	Fire = { Fire = 0.5, Water = 0.5, Grass = 2, Ice = 2, Bug = 2, Rock = 0.5, Dragon = 0.5, Steel = 2 },
	Water = { Fire = 2, Water = 0.5, Grass = 0.5, Ground = 2, Rock = 2, Dragon = 0.5 },
	Electric = { Water = 2, Electric = 0.5, Grass = 0.5, Ground = 0, Flying = 2, Dragon = 0.5 },
	Grass = { Fire = 0.5, Water = 2, Grass = 0.5, Poison = 0.5, Ground = 2, Flying = 0.5, Bug = 0.5, Rock = 2, Dragon = 0.5, Steel = 0.5 },
	Ice = { Fire = 0.5, Water = 0.5, Grass = 2, Ice = 0.5, Ground = 2, Flying = 2, Dragon = 2, Steel = 0.5 },
	Fighting = { Normal = 2, Ice = 2, Poison = 0.5, Flying = 0.5, Psychic = 0.5, Bug = 0.5, Rock = 2, Ghost = 0, Dark = 2, Steel = 2, Fairy = 0.5 },
	Poison = { Grass = 2, Poison = 0.5, Ground = 0.5, Rock = 0.5, Ghost = 0.5, Steel = 0, Fairy = 2 },
	Ground = { Fire = 2, Electric = 2, Grass = 0.5, Poison = 2, Flying = 0, Bug = 0.5, Rock = 2, Steel = 2 },
	Flying = { Electric = 0.5, Grass = 2, Fighting = 2, Bug = 2, Rock = 0.5, Steel = 0.5 },
	Psychic = { Fighting = 2, Poison = 2, Psychic = 0.5, Dark = 0, Steel = 0.5 },
	Bug = { Fire = 0.5, Grass = 2, Fighting = 0.5, Poison = 0.5, Flying = 0.5, Psychic = 2, Ghost = 0.5, Dark = 2, Steel = 0.5, Fairy = 0.5 },
	Rock = { Fire = 2, Ice = 2, Fighting = 0.5, Ground = 0.5, Flying = 2, Bug = 2, Steel = 0.5 },
	Ghost = { Normal = 0, Psychic = 2, Ghost = 2, Dark = 0.5 },
	Dragon = { Dragon = 2, Steel = 0.5, Fairy = 0 },
	Dark = { Fighting = 0.5, Psychic = 2, Ghost = 2, Dark = 0.5, Fairy = 0.5 },
	Steel = { Fire = 0.5, Water = 0.5, Electric = 0.5, Ice = 2, Rock = 2, Steel = 0.5, Fairy = 2 },
	Fairy = { Fire = 0.5, Fighting = 2, Poison = 0.5, Dragon = 2, Dark = 2, Steel = 0.5 },
}

function TypeChart.ResolveTypeName(typeValue: any): string?
	if type(typeValue) == "string" then
		return typeValue
	end
	if type(typeValue) == "table" then
		return _typeNameByDef[typeValue]
	end
	return nil
end

function TypeChart.GetMultiplier(attackType: any, defenderTypes: any): number
	local atkName = TypeChart.ResolveTypeName(attackType)
	if not atkName then
		return 1
	end

	local defList: {string} = {}
	if type(defenderTypes) == "string" then
		defList = { defenderTypes }
	elseif type(defenderTypes) == "table" then
		for _, t in ipairs(defenderTypes) do
			if type(t) == "string" then
				table.insert(defList, t)
			end
		end
	end

	if #defList == 0 then
		return 1
	end

	local atkRow = CHART[atkName]
	if not atkRow then
		return 1
	end

	local mult = 1.0
	for _, defName in ipairs(defList) do
		mult *= (atkRow[defName] or 1.0)
	end
	return mult
end

return TypeChart



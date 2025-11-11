local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local ClientData = require(ServerScriptService:WaitForChild("Server"):WaitForChild("ClientData"))
local GameData = require(ServerScriptService:WaitForChild("Server"):WaitForChild("GameData"))

local HeldItemEffects = {}

local function _hasType(creature, typeName)
	if not creature then return false end
	local types = {}
	local defT = creature.Type
	if type(defT) == "string" then
		table.insert(types, defT)
	elseif type(defT) == "table" then
		for _, t in ipairs(defT) do
			if type(t) == "string" then
				table.insert(types, t)
			end
		end
	end
	for _, t in ipairs(types) do
		if t == typeName then return true end
	end
	return false
end

function HeldItemEffects.DamageMultiplier(attacker, defender, moveTypeName)
	local mul = 1.0
	local held = attacker and attacker.HeldItem or nil
	if held then
		local name = string.lower(held)
		if name == string.lower("Fairy Dust") and moveTypeName == "Fairy" then mul *= 1.1 end
		if name == string.lower("Static Chip") and moveTypeName == "Electric" then mul *= 1.1 end
		if name == string.lower("Metal Fist") and moveTypeName == "Steel" and _hasType(attacker, "Fighting") then mul *= 1.2 end
		if name == string.lower("Rage Core") then
			local cur = attacker and attacker.Stats and attacker.Stats.HP or 0
			local max = attacker and attacker.MaxStats and attacker.MaxStats.HP or 1
			if max > 0 and cur / max <= 0.25 then mul *= 1.5 end
		end
	end
	return mul
end

function HeldItemEffects.ApplyStatMods(creature)
	if not creature or not creature.Stats or not creature.HeldItem then return end
	local items = GameData and GameData.Items or nil
	local def = items and items[creature.HeldItem] or nil
	if not def or not def.Stats then return end
	local s = def.Stats
	local function bump(val, pct)
		if type(pct) ~= "number" or pct == 0 then return val end
		local mul = 1 + (pct / 100)
		return math.max(1, math.floor((val or 1) * mul + 0.5))
	end
	creature.Stats.Attack = bump(creature.Stats.Attack, s.Attack or 0)
	creature.Stats.Defense = bump(creature.Stats.Defense, s.Defense or 0)
	creature.Stats.Speed = bump(creature.Stats.Speed, s.Speed or 0)
end

function HeldItemEffects.ProcessEndOfTurn(battle, Player, friendlyActions, enemyActions)
	if not battle then return end
	local crumbsApplied = false
	local function applyCrumbs(holder, isPlayerSide)
		if crumbsApplied then return end
		local heldName = holder and holder.HeldItem and tostring(holder.HeldItem) or ""
		heldName = heldName:lower():gsub("^%s+"," "):gsub("%s+$"," ")
		if holder and heldName == "crumbs" then
			if holder.Stats and holder.MaxStats and holder.Stats.HP > 0 then
				local maxHP = holder.MaxStats.HP or 1
				local heal = math.max(1, math.floor(maxHP / 16))
				local beforeHP = holder.Stats.HP or 0
				holder.Stats.HP = math.min(maxHP, beforeHP + heal)
				local cname = (holder.Nickname or holder.Name or (isPlayerSide and "Your creature" or "Foe"))
				local step = {
					Type = "Heal",
					Amount = heal,
					IsPlayer = isPlayerSide,
					Message = tostring(cname) .. " regained some HP thanks to Crumbs!",
					DelaySeconds = 0.6, -- allow UI time to display message before HP tween
					EndOfTurn = true, -- signal client to avoid pre-damage visual adjustments
					NewHP = holder.Stats.HP, -- explicit target HP after the heal
					MaxHP = maxHP,
				}
				DBG:print("[HeldItem][Crumbs] applying:", cname, "before:", beforeHP, "+", heal, "->", holder.Stats.HP)
				if isPlayerSide then
					table.insert(friendlyActions, step)
				else
					table.insert(enemyActions, step)
				end
				crumbsApplied = true
				if isPlayerSide then
					local pd = ClientData:Get(Player)
					if pd and pd.Party and battle.PlayerCreatureIndex then
						local slot = pd.Party[battle.PlayerCreatureIndex]
						if slot then
							slot.Stats = slot.Stats or {}
							slot.Stats.HP = holder.Stats.HP
							local m = holder.MaxStats and holder.MaxStats.HP or slot.MaxStats and slot.MaxStats.HP
							if m and m > 0 then
								slot.CurrentHP = math.clamp(math.floor((holder.Stats.HP / m) * 100 + 0.5), 0, 100)
							end
							if ClientData.UpdateClientData then ClientData:UpdateClientData(Player, pd) end
						end
					end
				end
			end
		end
	end
	applyCrumbs(battle.PlayerCreature, true)
	applyCrumbs(battle.FoeCreature, false)
end

return HeldItemEffects



--!strict
local PvPTurnResolver = {}
PvPTurnResolver.__index = PvPTurnResolver

type ActionEntry = {Actor: string, Data: any, UserId: number}

local function clone(obj)
	if type(obj) ~= "table" then return obj end
	local res = {}
	for k, v in pairs(obj) do
		res[k] = clone(v)
	end
	return res
end

local function buildTurnResult(battle, oppBattle, friendlyActions, enemyActions, turnId)
	local hpData = {
		Player = battle.PlayerCreature.Stats.HP,
		PlayerMax = battle.PlayerCreature.MaxStats.HP,
		Enemy = battle.FoeCreature.Stats.HP,
		EnemyMax = battle.FoeCreature.MaxStats.HP,
	}
	return {
		Player = {
			Friendly = friendlyActions,
			Enemy = enemyActions,
			HP = hpData,
			PlayerCreature = battle.PlayerCreature,
			FoeCreature = battle.FoeCreature,
			TurnId = turnId,
		},
		Opponent = {
			Friendly = enemyActions,
			Enemy = friendlyActions,
			HP = {
				Player = oppBattle.PlayerCreature.Stats.HP,
				PlayerMax = oppBattle.PlayerCreature.MaxStats.HP,
				Enemy = oppBattle.FoeCreature.Stats.HP,
				EnemyMax = oppBattle.FoeCreature.MaxStats.HP,
			},
			PlayerCreature = oppBattle.PlayerCreature,
			FoeCreature = oppBattle.FoeCreature,
			TurnId = turnId,
		}
	}
end

function PvPTurnResolver.Resolve(battle, oppBattle, actions: {ActionEntry})
	-- Order: attacker speed/priority not implemented; use received order
	local friendlyActions = {}
	local enemyActions = {}
	for _, entry in ipairs(actions) do
		if entry.Actor == "Player" then
			table.insert(friendlyActions, entry.Data)
		else
			table.insert(enemyActions, entry.Data)
		end
	end
	local nextTurnId = (battle.TurnId or 0) + 1
	local turnResult = buildTurnResult(battle, oppBattle, friendlyActions, enemyActions, nextTurnId)
	return turnResult, nextTurnId
end

return PvPTurnResolver


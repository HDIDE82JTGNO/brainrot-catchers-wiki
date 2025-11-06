--!strict
--[[
	BattleValidator.lua
	Server-side validation for all battle-related actions
	Prevents exploits and ensures data integrity
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BattleTypes = require(ReplicatedStorage.Shared.BattleTypes)

type ActionRequest = BattleTypes.ActionRequest
type BattleState = BattleTypes.BattleState
type Creature = BattleTypes.Creature

local BattleValidator = {}

-- Rate limiting per player
local ActionTimestamps: {[Player]: {[string]: number}} = {}
local RATE_LIMIT_WINDOW = 0.5 -- seconds between actions

--[[
	Validates a player's action request
	@param player The player making the request
	@param battle The current battle state
	@param action The action request
	@return success: boolean, errorMessage: string?
]]
function BattleValidator.ValidateAction(
	player: Player,
	battle: BattleState?,
	action: ActionRequest?
): (boolean, string?)
	-- Type validation
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "Invalid player"
	end
	
	if not battle then
		return false, "No active battle"
	end
	
	if not action or type(action) ~= "table" then
		return false, "Invalid action format"
	end
	
	-- Rate limiting
	local now = tick()
	ActionTimestamps[player] = ActionTimestamps[player] or {}
	local lastAction = ActionTimestamps[player][action.kind] or 0
	
	if now - lastAction < RATE_LIMIT_WINDOW then
		return false, "Action too fast - rate limited"
	end
	
	ActionTimestamps[player][action.kind] = now
	
	-- Validate action kind
	if action.kind ~= "Move" and action.kind ~= "Switch" and action.kind ~= "Run" and action.kind ~= "Forfeit" then
		return false, "Invalid action kind: " .. tostring(action.kind)
	end
	
	-- Validate move action
	if action.kind == "Move" then
		if not action.slot or type(action.slot) ~= "number" then
			return false, "Invalid move slot"
		end
		
		if action.slot < 1 or action.slot > 4 then
			return false, "Move slot out of range: " .. tostring(action.slot)
		end
		
		-- Validate move exists
		local playerCreature = battle.PlayerCreature
		if not playerCreature or not playerCreature.CurrentMoves then
			return false, "No moves available"
		end
		
		local move = playerCreature.CurrentMoves[action.slot]
		if not move then
			return false, "Move slot is empty"
		end
	end
	
	-- Validate switch action
	if action.kind == "Switch" then
		if not action.partyIndex or type(action.partyIndex) ~= "number" then
			return false, "Invalid party index"
		end
		
		if action.partyIndex < 1 or action.partyIndex > 6 then
			return false, "Party index out of range: " .. tostring(action.partyIndex)
		end
		
		-- Cannot switch to same creature
		if action.partyIndex == battle.PlayerCreatureIndex then
			return false, "Cannot switch to same creature"
		end
	end
	
	return true, nil
end

--[[
	Validates creature data integrity
	@param creature The creature to validate
	@return success: boolean, errorMessage: string?
]]
function BattleValidator.ValidateCreature(creature: Creature?): (boolean, string?)
	if not creature or type(creature) ~= "table" then
		return false, "Invalid creature data"
	end
	
	if not creature.Name or type(creature.Name) ~= "string" then
		return false, "Invalid creature name"
	end
	
	if not creature.Level or type(creature.Level) ~= "number" or creature.Level < 1 or creature.Level > 100 then
		return false, "Invalid creature level"
	end
	
	if not creature.Stats or type(creature.Stats) ~= "table" then
		return false, "Invalid creature stats"
	end
	
	-- Validate HP
	if not creature.Stats.HP or type(creature.Stats.HP) ~= "number" or creature.Stats.HP < 0 then
		return false, "Invalid creature HP"
	end
	
	return true, nil
end

--[[
	Validates party data
	@param party The party to validate
	@return success: boolean, errorMessage: string?
]]
function BattleValidator.ValidateParty(party: {Creature}?): (boolean, string?)
	if not party or type(party) ~= "table" then
		return false, "Invalid party data"
	end
	
	if #party == 0 then
		return false, "Party is empty"
	end
	
	if #party > 6 then
		return false, "Party has too many creatures"
	end
	
	-- Validate each creature
	for i, creature in ipairs(party) do
		local success, err = BattleValidator.ValidateCreature(creature)
		if not success then
			return false, "Party slot " .. i .. ": " .. (err or "Unknown error")
		end
	end
	
	return true, nil
end

--[[
	Clean up rate limiting data for disconnected players
]]
function BattleValidator.CleanupPlayer(player: Player)
	ActionTimestamps[player] = nil
end

return BattleValidator

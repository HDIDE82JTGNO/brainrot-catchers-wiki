--!strict
--[[
	PostBattleHandler.lua
	Handles post-battle events like XP gain, level-ups, and evolution
	Manages UI updates and evolution detection
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PostBattleHandler = {}
PostBattleHandler.__index = PostBattleHandler

export type PostBattleHandlerType = typeof(PostBattleHandler.new())

--[[
	Creates a new post-battle handler instance
	@param messageQueue The message queue reference
	@param uiController The UI controller reference
	@return PostBattleHandler
]]
function PostBattleHandler.new(messageQueue: any, uiController: any): any
	local self = setmetatable({}, PostBattleHandler)
	
	self._messageQueue = messageQueue
	self._uiController = uiController
	self._preBattleSnapshot = nil
	self._evolutionQueue = {}
	
	return self
end

--[[
	Takes a snapshot of the party before battle
	@param partyData The current party data
]]
function PostBattleHandler:TakePreBattleSnapshot(partyData: {any})
	print("[PostBattleHandler] Taking pre-battle snapshot")
	
	self._preBattleSnapshot = {}
	
	for i, creature in ipairs(partyData) do
		self._preBattleSnapshot[i] = {
			Name = creature.Name,
			Level = creature.Level,
			XPProgress = creature.XPProgress or 0,
		}
	end
end

--[[
	Checks for evolutions by comparing pre and post battle data
	@param postBattlePartyData The party data after battle
	@return table Array of evolution data
]]
function PostBattleHandler:CheckForEvolutions(postBattlePartyData: {any}): {any}
	print("[PostBattleHandler] Checking for evolutions")
	
	if not self._preBattleSnapshot then
		warn("[PostBattleHandler] No pre-battle snapshot found")
		return {}
	end
	
	local evolutions = {}
	
	for i, postCreature in ipairs(postBattlePartyData) do
		local preCreature = self._preBattleSnapshot[i]
		
		if preCreature and postCreature.Name ~= preCreature.Name then
			-- Evolution detected
			table.insert(evolutions, {
				SlotIndex = i,
				OldName = preCreature.Name,
				NewName = postCreature.Name,
				OldLevel = preCreature.Level,
				NewLevel = postCreature.Level,
			})
			
			print("[PostBattleHandler] Evolution detected:", preCreature.Name, "→", postCreature.Name)
		end
	end
	
	return evolutions
end

--[[
	Handles XP gain display
	@param creatureName The creature's name
	@param xpAmount The amount of XP gained
	@param leveledUp Whether the creature leveled up
	@param newLevel The new level (if leveled up)
]]
function PostBattleHandler:HandleXPGain(
	creatureName: string,
	xpAmount: number,
	leveledUp: boolean,
	newLevel: number?
)
	print("[PostBattleHandler] Handling XP gain for:", creatureName)
	
	-- Show XP gain message
	local message = string.format("%s gained %d XP!", creatureName, xpAmount)
	self._messageQueue:Enqueue(message)
	
	-- If leveled up, show level up message
	if leveledUp and newLevel then
		local levelUpMessage = string.format("%s grew to Lv. %d!", creatureName, newLevel)
		self._messageQueue:Enqueue(levelUpMessage)
	end
end

--[[
	Queues an evolution for display
	@param evolutionData The evolution data
]]
function PostBattleHandler:QueueEvolution(evolutionData: any)
	print("[PostBattleHandler] Queuing evolution:", evolutionData.OldName, "→", evolutionData.NewName)
	table.insert(self._evolutionQueue, evolutionData)
end

--[[
	Processes queued evolutions
	@param onComplete Callback when all evolutions are processed
]]
function PostBattleHandler:ProcessEvolutions(onComplete: (() -> ())?)
	print("[PostBattleHandler] Processing", #self._evolutionQueue, "evolution(s)")
	
	if #self._evolutionQueue == 0 then
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- Process each evolution
	local function processNext(index: number)
		if index > #self._evolutionQueue then
			-- All evolutions processed
			self._evolutionQueue = {}
			if onComplete then
				onComplete()
			end
			return
		end
		
		local evolution = self._evolutionQueue[index]
		self:_displayEvolution(evolution, function()
			processNext(index + 1)
		end)
	end
	
	processNext(1)
end

--[[
	Internal: Displays a single evolution
	@param evolutionData The evolution data
	@param onComplete Callback when evolution display completes
]]
function PostBattleHandler:_displayEvolution(evolutionData: any, onComplete: (() -> ())?)
	print("[PostBattleHandler] Displaying evolution:", evolutionData.OldName, "→", evolutionData.NewName)
	
	-- Get EvolutionUI module
	local EvolutionUI = require(script.Parent.Parent.Utilities.EvolutionUI)
	
	if EvolutionUI and EvolutionUI.PlayEvolution then
		EvolutionUI:PlayEvolution(
			evolutionData.OldName,
			evolutionData.NewName,
			onComplete
		)
	else
		warn("[PostBattleHandler] EvolutionUI not found")
		if onComplete then
			onComplete()
		end
	end
end

--[[
	Clears the pre-battle snapshot
]]
function PostBattleHandler:ClearSnapshot()
	self._preBattleSnapshot = nil
	self._evolutionQueue = {}
end

--[[
	Gets the pre-battle snapshot
	@return {any}? The pre-battle party data
]]
function PostBattleHandler:GetPreBattleSnapshot(): {any}?
	return self._preBattleSnapshot
end

--[[
	Updates XP progress UI during battle
	@param creature The creature data
	@param shouldTween Whether to tween the progress bar
]]
function PostBattleHandler:UpdateXPProgressUI(creature: any, shouldTween: boolean)
	if self._uiController and self._uiController.UpdateLevelUI then
		self._uiController:UpdateLevelUI(creature, shouldTween)
	end
end

return PostBattleHandler

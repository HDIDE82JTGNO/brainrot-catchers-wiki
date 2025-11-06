--!strict
--[[
	SwitchHandler.lua
	Handles creature switching animations and logic
	Manages both voluntary and forced switches with proper sequencing
]]

local SwitchHandler = {}
SwitchHandler.__index = SwitchHandler

export type SwitchHandlerType = typeof(SwitchHandler.new())
export type SwitchCompleteCallback = () -> ()

--[[
	Creates a new switch handler instance
	@param battleState The battle state reference
	@param sceneManager The scene manager reference
	@param animationController The animation controller reference
	@param messageQueue The message queue reference
	@return SwitchHandler
]]
function SwitchHandler.new(
	battleState: any,
	sceneManager: any,
	animationController: any,
	messageQueue: any
): any
	local self = setmetatable({}, SwitchHandler)
	
	self._battleState = battleState
	self._sceneManager = sceneManager
	self._animationController = animationController
	self._messageQueue = messageQueue
	
	return self
end

--[[
	Handles voluntary creature switch
	@param newCreature The new creature data
	@param newIndex The new creature's party index
	@param onComplete Callback when switch completes
]]
function SwitchHandler:HandleVoluntarySwitch(
	newCreature: any,
	newIndex: number,
	onComplete: SwitchCompleteCallback?
)
	print("[SwitchHandler] Handling voluntary switch to:", newCreature.Name)
	
	local oldCreature = self._battleState.PlayerCreature
	local oldCreatureName = oldCreature.Nickname or oldCreature.Name
	local newCreatureName = newCreature.Nickname or newCreature.Name
	
	-- Show "come back" message
	self._messageQueue:Enqueue(oldCreatureName .. ", come back!")
	
	-- Wait for message
	self._messageQueue:WaitForDrain()
	
	-- Despawn old creature with hologram
	self:_despawnCreatureWithHologram(true, function()
		-- Update battle state
		self._battleState:UpdatePlayerCreature(newCreature, newIndex)
		
		-- Show "Go" message
		self._messageQueue:Enqueue("Go " .. newCreatureName .. "!")
		
		-- Spawn new creature with hologram
		self:_spawnCreatureWithHologram(newCreature, true, function()
			-- Wait for message
			self._messageQueue:WaitForDrain()
			
			if onComplete then
				onComplete()
			end
		end)
	end)
end

--[[
	Handles forced creature switch (after fainting)
	@param newCreature The new creature data
	@param newIndex The new creature's party index
	@param onComplete Callback when switch completes
]]
function SwitchHandler:HandleForcedSwitch(
	newCreature: any,
	newIndex: number,
	onComplete: SwitchCompleteCallback?
)
	print("[SwitchHandler] Handling forced switch to:", newCreature.Name)
	
	local newCreatureName = newCreature.Nickname or newCreature.Name
	
	-- Update battle state
	self._battleState:UpdatePlayerCreature(newCreature, newIndex)
	
	-- Show "Go" message
	self._messageQueue:Enqueue("Go " .. newCreatureName .. "!")
	
	-- Spawn new creature with hologram
	self:_spawnCreatureWithHologram(newCreature, true, function()
		-- Wait for message
		self._messageQueue:WaitForDrain()
		
		if onComplete then
			onComplete()
		end
	end)
end

--[[
	Handles enemy creature switch
	@param newCreature The new creature data
	@param onComplete Callback when switch completes
]]
function SwitchHandler:HandleEnemySwitch(
	newCreature: any,
	onComplete: SwitchCompleteCallback?
)
	print("[SwitchHandler] Handling enemy switch to:", newCreature.Name)
	
	local newCreatureName = newCreature.Name
	
	-- Show switch message
	self._messageQueue:Enqueue("Enemy sent out " .. newCreatureName .. "!")
	
	-- Despawn old creature
	self:_despawnCreatureWithHologram(false, function()
		-- Update battle state
		self._battleState:UpdateFoeCreature(newCreature)
		
		-- Spawn new creature
		self:_spawnCreatureWithHologram(newCreature, false, function()
			-- Wait for message
			self._messageQueue:WaitForDrain()
			
			if onComplete then
				onComplete()
			end
		end)
	end)
end

--[[
	Internal: Despawns creature with hologram effect
	@param isPlayer Whether this is the player's creature
	@param onComplete Callback when despawn completes
]]
function SwitchHandler:_despawnCreatureWithHologram(
	isPlayer: boolean,
	onComplete: (() -> ())?
)
	local model = isPlayer 
		and self._sceneManager:GetPlayerCreature() 
		or self._sceneManager:GetFoeCreature()
	
	if not model then
		if onComplete then
			onComplete()
		end
		return
	end
	
	-- TODO: Implement hologram fade-out effect
	-- For now, just despawn instantly
	self._sceneManager:DespawnCreature(isPlayer, true, onComplete)
end

--[[
	Internal: Spawns creature with hologram effect
	@param creature The creature data
	@param isPlayer Whether this is the player's creature
	@param onComplete Callback when spawn completes
]]
function SwitchHandler:_spawnCreatureWithHologram(
	creature: any,
	isPlayer: boolean,
	onComplete: (() -> ())?
)
	local playerSpawn, foeSpawn = self._sceneManager:GetSpawnPoints()
	local spawnPoint = isPlayer and playerSpawn or foeSpawn
	
	if not spawnPoint then
		warn("[SwitchHandler] Spawn point not found")
		if onComplete then
			onComplete()
		end
		return
	end
	
	self._sceneManager:SpawnCreature(
		creature,
		spawnPoint,
		isPlayer,
		true, -- Use hologram
		function()
			-- Start idle animation
			local model = isPlayer 
				and self._sceneManager:GetPlayerCreature() 
				or self._sceneManager:GetFoeCreature()
			
			if model then
				self._animationController:PlayIdleAnimation(model)
			end
			
			if onComplete then
				onComplete()
			end
		end
	)
end

return SwitchHandler

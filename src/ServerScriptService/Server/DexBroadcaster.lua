--!nocheck
local DexBroadcaster = {}

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local ClientData = require(script.Parent.ClientData)
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

-- Events
local Events = ReplicatedStorage:WaitForChild("Events")

-- State
local _playerDexNumbers = {} -- [Player] -> number
local _connections = {}
local _updateInterval = 5 -- Update every 5 seconds
local _updateThread = nil

--[[
	Internal: Broadcasts a player's Dex number to all clients
]]
local function BroadcastPlayerDex(player: Player, dexNumber: number)
	-- Send to all clients
	Events.Communicate:FireAllClients("PlayerDexUpdate", {
		Player = player,
		DexNumber = dexNumber
	})
end

--[[
	Internal: Broadcasts all players' Dex numbers to a specific client
]]
local function BroadcastAllDexToClient(client: Player)
	
	for player, dexNumber in pairs(_playerDexNumbers) do
		if player ~= client then -- Don't send their own data
			Events.Communicate:FireClient(client, "PlayerDexUpdate", {
				Player = player,
				DexNumber = dexNumber
			})
		end
	end
end

--[[
	Internal: Calculates Dex number by counting unique creatures
]]
local function CalculateDexNumber(playerData: any): number
	if not playerData then return 0 end
	
	local uniqueCreatures = {}
	local count = 0
	
	-- Count creatures in party
	if playerData.Party then
		for _, creature in ipairs(playerData.Party) do
			if creature and creature.Name then
				if not uniqueCreatures[creature.Name] then
					uniqueCreatures[creature.Name] = true
					count = count + 1
				end
			end
		end
	end
	
	-- Count creatures in boxes
	if playerData.Boxes then
		for boxIndex, box in ipairs(playerData.Boxes) do
			if box then
				for _, creature in ipairs(box) do
					if creature and creature.Name then
						if not uniqueCreatures[creature.Name] then
							uniqueCreatures[creature.Name] = true
							count = count + 1
						end
					end
				end
			end
		end
	end
	
	-- Count creatures in main creatures array (if it exists)
	if playerData.Creatures then
		for _, creature in ipairs(playerData.Creatures) do
			if creature and creature.Name then
				if not uniqueCreatures[creature.Name] then
					uniqueCreatures[creature.Name] = true
					count = count + 1
				end
			end
		end
	end
	return count
end

--[[
	Internal: Updates a player's Dex number and broadcasts it
]]
local function UpdatePlayerDex(player: Player)
	local playerData = ClientData:Get(player)
	if playerData then
		-- Calculate Dex number dynamically
		local dexNumber = CalculateDexNumber(playerData)
		_playerDexNumbers[player] = dexNumber
		
		-- Store Dex number in player data (but don't call UpdateClientData to avoid recursion)
		playerData.DexNumber = dexNumber
		
		BroadcastPlayerDex(player, dexNumber)
	end
end

--[[
	Internal: Handles player joining
]]
local function OnPlayerAdded(player: Player)

	-- Wait for player data to be available
	task.spawn(function()
		-- Wait for player data to be initialized
		local attempts = 0
		while attempts < 10 do
			local playerData = ClientData:Get(player)
			if playerData then
				UpdatePlayerDex(player)
				break
			end
			task.wait(0.5)
			attempts = attempts + 1
		end
		
	
	end)
end

--[[
	Internal: Handles player leaving
]]
local function OnPlayerRemoving(player: Player)
	-- Remove from tracking
	_playerDexNumbers[player] = nil
	
	-- Broadcast removal to all clients
	Events.Communicate:FireAllClients("PlayerDexUpdate", {
		Player = player,
		DexNumber = nil -- nil indicates player left
	})
end

--[[
	Internal: Handles client data updates
]]
local function OnClientDataUpdated(player: Player, newData: any)

	-- Update Dex number if it changed
	if newData and newData.DexNumber then
		local oldDex = _playerDexNumbers[player] or 0
		local newDex = newData.DexNumber
		
		if oldDex ~= newDex then
			UpdatePlayerDex(player)
		end
	end
end

--[[
	Internal: Periodic update to check all players' Dex numbers
]]
local function PeriodicUpdate()
	while true do
		task.wait(_updateInterval)
		
		-- Check all currently connected players
		for _, player in ipairs(Players:GetPlayers()) do
			local playerData = ClientData:Get(player)
			if playerData then
				-- Calculate current Dex number from unique creatures
				local currentDex = CalculateDexNumber(playerData)
				local storedDex = _playerDexNumbers[player] or 0
				
				-- Always update and broadcast the Dex number
				_playerDexNumbers[player] = currentDex
				
				-- Store Dex number in player data (but don't call UpdateClientData to avoid recursion)
				playerData.DexNumber = currentDex
				
				BroadcastPlayerDex(player, currentDex)
	
			end
		end
	end
end

--[[
	Public: Initializes the Dex broadcasting system
]]
function DexBroadcaster:Init()
	
	-- Set up connections
	table.insert(_connections, Players.PlayerAdded:Connect(OnPlayerAdded))
	table.insert(_connections, Players.PlayerRemoving:Connect(OnPlayerRemoving))
	
	-- Listen for client data updates via the ClientData module
	-- We'll hook into the ClientData:UpdateClientData function
	local originalUpdateClientData = ClientData.UpdateClientData
	ClientData.UpdateClientData = function(self, player: Player, data: any)
		-- Call original function
		originalUpdateClientData(self, player, data)
		
	-- Check if creature data changed and recalculate Dex
	if data and (data.Party or data.Boxes or data.Creatures) then
		
		local newDex = CalculateDexNumber(data)
		local oldDex = _playerDexNumbers[player] or 0
		
		-- Always update and broadcast the Dex number (even if unchanged)
		_playerDexNumbers[player] = newDex
		
		-- Store Dex number in player data (but don't call UpdateClientData to avoid recursion)
		data.DexNumber = newDex
		
		BroadcastPlayerDex(player, newDex)
	
	end
	end
	
	-- Handle new players joining - send them all existing Dex numbers
	table.insert(_connections, Players.PlayerAdded:Connect(function(newPlayer: Player)
		-- Wait a moment for the new player to be ready
		task.wait(1)
		BroadcastAllDexToClient(newPlayer)
	end))
	
	-- Start periodic update thread
	_updateThread = task.spawn(PeriodicUpdate)

end

--[[
	Public: Gets a player's current Dex number
]]
function DexBroadcaster:GetPlayerDex(player: Player): number?
	return _playerDexNumbers[player]
end

--[[
	Public: Gets all tracked Dex numbers
]]
function DexBroadcaster:GetAllDexNumbers(): {[Player]: number}
	return _playerDexNumbers
end

--[[
	Public: Manually updates a player's Dex number
]]
function DexBroadcaster:UpdatePlayerDex(player: Player, dexNumber: number)
	_playerDexNumbers[player] = dexNumber
	BroadcastPlayerDex(player, dexNumber)
end

--[[
	Public: Sets the update interval for periodic checks
]]
function DexBroadcaster:SetUpdateInterval(interval: number)
	_updateInterval = math.max(1, interval) -- Minimum 1 second
end

--[[
	Public: Gets the current update interval
]]
function DexBroadcaster:GetUpdateInterval(): number
	return _updateInterval
end

--[[
	Public: Cleans up the Dex broadcasting system
]]
function DexBroadcaster:Cleanup()
	
	-- Stop periodic update thread
	if _updateThread then
		task.cancel(_updateThread)
		_updateThread = nil
	end
	
	-- Disconnect all connections
	for _, connection in ipairs(_connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	_connections = {}
	
	-- Clear tracking data
	_playerDexNumbers = {}

end

return DexBroadcaster

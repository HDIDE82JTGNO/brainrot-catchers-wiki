--!strict
-- PlayerClickDetectors: Adds click detectors to players when context is "Trade"
-- Clicking on a player opens the ViewPlayer menu

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local RSAssets = ReplicatedStorage:WaitForChild("Assets")

local GameContext = require(script.Parent.GameContext)
local ViewPlayerManager = require(script.Parent.Parent.UI.ViewPlayerManager)

-- Track click detectors for cleanup (array of detectors per player)
local _clickDetectors: {[Player]: {ClickDetector}} = {}
local _connections: {RBXScriptConnection} = {}
local _playerConnections: {[Player]: {RBXScriptConnection}} = {} -- Track connections per player
local _descendantConnections: {[Player]: RBXScriptConnection} = {} -- Track DescendantAdded connections per player

-- Function to open ViewPlayer menu for a player
local function openViewPlayerForPlayer(player: Player)
	-- Use ViewPlayerManager without level mode storage (uses local variable)
	ViewPlayerManager.OpenForPlayer(player, nil)
end

-- Add click detector to a player's character
local function addClickDetectorToPlayer(player: Player)
	if player == LocalPlayer then return end
	if _clickDetectors[player] then return end -- Already has detectors
	
	local character = player.Character
	if not character then return end
	
	-- Wait for HumanoidRootPart to ensure character is loaded
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoidRootPart then return end
	
	-- Get ClickDetector template
	local clickDetectorTemplate = RSAssets:FindFirstChild("ClickDetector")
	if not clickDetectorTemplate then
		warn("[PlayerClickDetectors] ClickDetector template not found in Assets")
		return
	end
	
	-- Initialize detectors array for this player
	_clickDetectors[player] = {}
	
	-- Function to add click detector to a part
	local function addDetectorToPart(part: BasePart)
		if not part or part.Name == "HumanoidRootPart" then return end
		
		-- Clone and attach click detector
		local clickDetector = clickDetectorTemplate:Clone()
		clickDetector.Parent = part
		table.insert(_clickDetectors[player], clickDetector)
		
		-- Connect click event
		clickDetector.MouseClick:Connect(function()
			openViewPlayerForPlayer(player)
		end)
	end
	
	-- Add detectors to all existing body parts (except HRP)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			addDetectorToPart(descendant)
		end
	end
	
	-- Listen for new body parts being added (like accessories)
	local descendantConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			addDetectorToPart(descendant)
		end
	end)
	
	-- Store descendant connection separately for cleanup
	_descendantConnections[player] = descendantConnection
end

-- Remove click detectors from a player
local function removeClickDetectorFromPlayer(player: Player)
	local detectors = _clickDetectors[player]
	if detectors then
		for _, detector in ipairs(detectors) do
			if detector and detector.Parent then
				detector:Destroy()
			end
		end
		_clickDetectors[player] = nil
	end
	-- Clean up descendant connection
	if _descendantConnections[player] then
		if _descendantConnections[player].Connected then
			_descendantConnections[player]:Disconnect()
		end
		_descendantConnections[player] = nil
	end
end

-- Handle player added
local function onPlayerAdded(player: Player)
	-- Only set up connections once per player
	if _playerConnections[player] then return end
	
	_playerConnections[player] = {}
	
	-- Add click detector if in Trade context and character exists
	if GameContext:Is("Trade") and player.Character then
		addClickDetectorToPlayer(player)
	end
	
	-- Handle character respawn
	local connection = player.CharacterAdded:Connect(function(character)
		-- Remove old click detectors if they exist
		removeClickDetectorFromPlayer(player)
		-- Clean up old descendant connection if it exists
		if _descendantConnections[player] then
			if _descendantConnections[player].Connected then
				_descendantConnections[player]:Disconnect()
			end
			_descendantConnections[player] = nil
		end
		-- Add new detectors if still in Trade context
		if GameContext:Is("Trade") then
			addClickDetectorToPlayer(player)
		end
	end)
	table.insert(_connections, connection)
	table.insert(_playerConnections[player], connection)
	
	-- Handle character removal
	local removalConnection = player.CharacterRemoving:Connect(function(character)
		removeClickDetectorFromPlayer(player)
	end)
	table.insert(_connections, removalConnection)
	table.insert(_playerConnections[player], removalConnection)
end

-- Handle player removing
local function onPlayerRemoving(player: Player)
	removeClickDetectorFromPlayer(player)
	-- Clean up player connections
	if _playerConnections[player] then
		for _, conn in ipairs(_playerConnections[player]) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
		_playerConnections[player] = nil
	end
end

-- Initialize: Check context and set up click detectors
local function init()
	-- Listen for new players (always set up, but only add detectors if Trade)
	table.insert(_connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(_connections, Players.PlayerRemoving:Connect(onPlayerRemoving))
	
	-- Check if we're in Trade context
	if GameContext:Is("Trade") then
		-- Add click detectors to existing players
		for _, player in ipairs(Players:GetPlayers()) do
			onPlayerAdded(player)
		end
	end
	
	-- Listen for context changes
	table.insert(_connections, game:GetService("Workspace"):GetAttributeChangedSignal("Context"):Connect(function()
		local isTrade = GameContext:Is("Trade")
		
		if isTrade then
			-- Add click detectors to all players
			for _, player in ipairs(Players:GetPlayers()) do
				if player.Character then
					addClickDetectorToPlayer(player)
				end
				-- Set up connections if not already set up
				-- (onPlayerAdded handles this, but we need to check if connections exist)
				-- Actually, connections are per-player, so we need to track them differently
				-- For now, just ensure click detectors are added
			end
		else
			-- Remove all click detectors
			for player, _ in pairs(_clickDetectors) do
				removeClickDetectorFromPlayer(player)
			end
		end
	end))
end

-- Cleanup function
local function cleanup()
	for _, connection in ipairs(_connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	_connections = {}
	
	for player, _ in pairs(_clickDetectors) do
		removeClickDetectorFromPlayer(player)
	end
	
	for player, conns in pairs(_playerConnections) do
		for _, conn in ipairs(conns) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
	end
	_playerConnections = {}
	
	-- Clean up descendant connections
	for player, conn in pairs(_descendantConnections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	_descendantConnections = {}
end

-- Initialize when script loads
init()

return {
	Init = init,
	Cleanup = cleanup,
}


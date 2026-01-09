--!strict
local ClientData = require(script.ClientData)
local ServerFunctions = require(script.ServerFunctions)
local DexBroadcaster = require(script.DexBroadcaster)
local ChallengesSystem = require(script.ChallengesSystem)
local PurchaseHandler = require(script.PurchaseHandler)
local MysteryTradeService = require(script.MysteryTradeService)
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ChunkList = require(script.GameData.ChunkList)
local Config = require(script.GameData.Config)
local DBG = require(game:GetService("ReplicatedStorage").Shared.DBG)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Events = ReplicatedStorage:WaitForChild("Events")

-- Optional: run lightweight battle sanity checks in dev/debug environments
if Config.BATTLE_SANITY_CHECKS == true then
	local ok, err = pcall(function()
		require(script.Battle.Gen9SanityChecks).Run()
	end)
	if not ok then
		warn(err)
	end
end

-- Initialize Dex broadcasting system
DexBroadcaster:Init()

-- Initialize Purchase Handler (must be initialized at server startup)
PurchaseHandler:Init()

-- Initialize Mystery Trade Service
MysteryTradeService:Init({
	ClientData = ClientData,
	Events = Events,
	DBG = DBG,
})

-- Note: Weather system is initialized via WeatherApiModule.apply() in ServerFunctions
-- This follows the same pattern as DayNightCycle

-- Initialize Challenges period checking for players
do
	local function waitForProfile(player: Player, timeout: number?): any?
		local deadline = os.clock() + (timeout or 10)
		local profile = ClientData:Get(player)
		while not profile and os.clock() < deadline and player.Parent == Players do
			task.wait(0.1)
			profile = ClientData:Get(player)
		end
		return profile
	end
	
	-- Helper function to get badge count
	local function getBadgeCount(player: Player): number
		local profile = ClientData:Get(player)
		return tonumber(profile and profile.Badges) or 0
	end
	
	-- Helper function to check if player has unlocked battling (badges >= 1)
	local function hasUnlockedBattling(player: Player): boolean
		local badges = getBadgeCount(player)
		return badges >= 1
	end
	
	-- Helper function to check if player has unlocked trading (badges >= 1)
	local function hasUnlockedTrading(player: Player): boolean
		local badges = getBadgeCount(player)
		return badges >= 1
	end
	
	-- Helper function to check if player meets requirements for a given context
	local function checkContextRequirements(player: Player, context: string): boolean
		if context == "Battle" then
			return hasUnlockedBattling(player)
		elseif context == "Trade" then
			return hasUnlockedTrading(player)
		end
		-- Story context or unknown contexts don't have requirements
		return true
	end
	
	local function onPlayerJoin(player: Player)
		task.spawn(function()
			-- Wait for player data to be loaded
			local profile = waitForProfile(player, 15)
			if not profile then return end
			
			-- Check context and requirements for Battle/Trade contexts
			local context = player:GetAttribute("ClientContext")
			if context == "Battle" or context == "Trade" then
				local requirementsMet = checkContextRequirements(player, context)
				if not requirementsMet then
					DBG:print("[Context] Player", player.Name, "joined with", context, "context but hasn't unlocked it. Teleporting to main game.")
					local success, err = pcall(function()
						TeleportService:TeleportAsync(Config.REQUIREMENT_FAILURE_PLACE_ID, {player})
					end)
					if not success then
						DBG:warn("[Context] Failed to teleport player", player.Name, ":", err)
					end
					return
				end
			end
			
			-- Check if challenges need to be refreshed for new period
			ChallengesSystem.CheckAndRefreshPeriods(player)
		end)
	end
	
	Players.PlayerAdded:Connect(onPlayerJoin)
	
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerJoin(player)
	end
end

-- Validate critical chunks exist in ServerStorage at startup
do
	local ServerStorage = game:GetService("ServerStorage")
	local ChunksFolder = ServerStorage:FindFirstChild("Chunks")
	local InteriorsFolder = ServerStorage:FindFirstChild("Interiors")
	
	if not ChunksFolder then
		warn("[CRITICAL] ServerStorage.Chunks folder does not exist! Chunks cannot be loaded!")
	else
		-- Verify Chunk1 exists (critical for game to function)
		local Chunk1 = ChunksFolder:FindFirstChild("Chunk1")
		if not Chunk1 then
			warn("[CRITICAL] Chunk1 not found in ServerStorage.Chunks!")
			warn("[CRITICAL] Available chunks in ServerStorage.Chunks:")
			for _, child in ipairs(ChunksFolder:GetChildren()) do
				warn("  -", child.Name)
			end
		else
			DBG:print("[Startup] Chunk1 validated in ServerStorage.Chunks")
		end
	end
	
	if not InteriorsFolder then
		warn("[WARNING] ServerStorage.Interiors folder does not exist! Interior chunks cannot be loaded!")
	else
		DBG:print("[Startup] ServerStorage.Interiors validated")
	end
end

-- Disable player-vs-player collisions
do
    local Players = game:GetService("Players")
    local PhysicsService = game:GetService("PhysicsService")
    local GROUP = "plrs"
    pcall(function()
        PhysicsService:RegisterCollisionGroup(GROUP)
    end)
    PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)

    local function setCharacterGroup(character: Model)
        for _, descendant in ipairs(character:GetDescendants()) do
            if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
                descendant.CollisionGroup = GROUP
            end
        end
        -- Also connect to catch new parts added to the character
        character.DescendantAdded:Connect(function(descendant)
            if (descendant:IsA("BasePart") or descendant:IsA("MeshPart")) and descendant.Parent == character then
                descendant.CollisionGroup = GROUP
            end
        end)
    end

    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            setCharacterGroup(character)
        end)
        -- Apply to existing character
        if player.Character then
            setCharacterGroup(player.Character)
        end
    end)
    -- Apply to players already in game on server start
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            setCharacterGroup(p.Character)
        end
        p.CharacterAdded:Connect(setCharacterGroup)
    end
end

-- Save precise position on character removal if AutoSave is ON and not in a Trainer battle
do
    local function onCharacterRemoving(player: Player, character: Model)
        local profile = ClientData:Get(player)
        if not profile then return end
        if not profile.Settings or profile.Settings.AutoSave ~= true then return end
		-- Resolve HRP early for spatial guards
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") then return end
		-- Never save on the title screen: if near title spawn, skip
		local spawnBox = workspace:FindFirstChild("SpawnBox")
		local spawnLocation = spawnBox and spawnBox:FindFirstChild("SpawnLocation")
		if spawnLocation and spawnLocation:IsA("BasePart") then
			local dist = (hrp.Position - spawnLocation.Position).Magnitude
			if dist <= 100 then
				return
			end
		end
        -- Do not save from title screen or before any gameplay chunk has been loaded
        -- Require the authoritative current chunk set by the server
        local currentChunkName = profile.Chunk
        if currentChunkName == nil then
            return
        end
        -- Validate against known gameplay chunks; prevents title/intro saving
        local isValidGameplayChunk = (type(currentChunkName) == "string") and (ChunkList[currentChunkName] ~= nil)
        if not isValidGameplayChunk then
            return
        end
        -- Do not update LeaveData if in an active battle or when a pending battle snapshot exists
        local ActiveBattles = ServerFunctions:GetActiveBattles()
        local isInBattle = (ActiveBattles and ActiveBattles[player] ~= nil) or (profile.InBattle == true)
        if isInBattle then
            return
        end
        -- Pending battle snapshot indicates we should not overwrite rejoin placement
        if profile.PendingBattle ~= nil then
            return
        end
		-- Extract HRP CFrame and save along with current chunk
        -- Store position and Euler rotation for restore
        local cf = hrp.CFrame
        local rx, ry, rz = cf:ToOrientation()
        profile.LeaveData = {
            Position = { X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z },
            Rotation = { X = rx, Y = ry, Z = rz },
            Chunk = currentChunkName
        }
        -- Also persist chunk
        profile.LastChunk = currentChunkName
        -- Push update to client cache
        ClientData:UpdateClientData(player, profile)
    end

    Players.PlayerAdded:Connect(function(player)
        player.CharacterRemoving:Connect(function(character)
            onCharacterRemoving(player, character)
        end)
    end)
    -- Hook for players already in-game
    for _, p in ipairs(Players:GetPlayers()) do
        p.CharacterRemoving:Connect(function(character)
            onCharacterRemoving(p, character)
        end)
    end
end

-- Handle Battle/Trade context changes from client
-- These contexts don't have physical chunks, so we set the Chunk directly
do
    local VIRTUAL_CONTEXTS = {
        Battle = true,
        Trade = true,
    }

    local function waitForProfile(player: Player, timeout: number?): any?
        local deadline = os.clock() + (timeout or 10)
        local profile = ClientData:Get(player)
        while not profile and os.clock() < deadline and player.Parent == Players do
            task.wait(0.1)
            profile = ClientData:Get(player)
        end
        return profile
    end

    local function handleContextChange(player: Player, context: string?, waitForData: boolean?)
        if not context then
            return
        end

        DBG:print("[Context] handleContextChange called for", player.Name, "context:", context, "waitForData:", waitForData)

        local profile
        if waitForData then
            profile = waitForProfile(player, 10)
        else
            profile = ClientData:Get(player)
        end
        
        if not profile then
            DBG:warn("[Context] No profile for", player.Name, "when handling context:", context)
            return
        end

        local currentChunk = profile.Chunk
        DBG:print("[Context] Current profile.Chunk for", player.Name, "is:", tostring(currentChunk))

        -- Entering a virtual context (Battle/Trade)
        if VIRTUAL_CONTEXTS[context] then
            -- Only update if not already in this context
            if currentChunk == context then
                DBG:print("[Context] Already in context", context, "for", player.Name, "- skipping")
                return
            end

            -- Save current chunk as LastChunk for restoration later (if it's a valid Story chunk)
            if currentChunk and currentChunk ~= "nil" and currentChunk ~= "Title" and currentChunk ~= "Battle" and currentChunk ~= "Trade" then
                profile.LastChunk = currentChunk
            end

            -- Set Chunk to the virtual context
            profile.Chunk = context
            DBG:print("[Context] Set profile.Chunk to", context, "for", player.Name, "(LastChunk:", profile.LastChunk, ")")
            
            -- Verify it was set
            DBG:print("[Context] Verification - profile.Chunk is now:", profile.Chunk)

            -- Update client data
            ClientData:UpdateClientData(player, profile)
            
            -- Double-check after update
            local verifyProfile = ClientData:Get(player)
            DBG:print("[Context] After UpdateClientData, ClientData:Get returns Chunk:", verifyProfile and verifyProfile.Chunk)

        -- Leaving a virtual context (returning to Story)
        elseif context == "Story" and VIRTUAL_CONTEXTS[currentChunk] then
            -- Restore Chunk from LastChunk
            local restoredChunk = profile.LastChunk or "Chunk1"
            profile.Chunk = restoredChunk
            DBG:print("[Context] Restored Chunk to", restoredChunk, "for", player.Name, "(from", currentChunk, "context)")

            -- Update client data
            ClientData:UpdateClientData(player, profile)
        end
    end

    local function setupContextListener(player: Player)
        -- Check initial context (spawn a task to wait for profile if needed)
        local initialContext = player:GetAttribute("ClientContext")
        if initialContext and VIRTUAL_CONTEXTS[initialContext] then
            task.spawn(function()
                handleContextChange(player, initialContext, true) -- Wait for profile
            end)
        end

        -- Listen for context changes
        player:GetAttributeChangedSignal("ClientContext"):Connect(function()
            local newContext = player:GetAttribute("ClientContext")
            handleContextChange(player, newContext, false)
        end)
    end

    Players.PlayerAdded:Connect(setupContextListener)

    -- Hook for players already in-game
    for _, p in ipairs(Players:GetPlayers()) do
        setupContextListener(p)
    end
end
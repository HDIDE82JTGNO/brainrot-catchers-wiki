--!strict
local ClientData = require(script.ClientData)
local ServerFunctions = require(script.ServerFunctions)
local DexBroadcaster = require(script.DexBroadcaster)
local Players = game:GetService("Players")
local ChunkList = require(script.GameData.ChunkList)

-- Initialize Dex broadcasting system
DexBroadcaster:Init()

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
            if descendant:IsA("BasePart") then
                descendant.CollisionGroup = GROUP
            end
        end
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
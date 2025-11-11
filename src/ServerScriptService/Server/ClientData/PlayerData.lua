local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game.ServerScriptService

local PlayerDataTemplate = require(ReplicatedStorage.Shared.PlayerData)

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)
local DATA_STORE_KEY = RunService:IsStudio() and "435g6hyu7tefr" or "Test-2"


local PlayerStore = ProfileStore.New(DATA_STORE_KEY,PlayerDataTemplate.DEFAULT_PLAYER_DATA)
local Profiles: {[Player]: typeof(PlayerStore:StartSessionAsync())} = {}



local Local = {}
local Shared = {}

function Local.OnStart()
	for _,p in ipairs(PlayersService:GetChildren()) do
		task.spawn(Local.LoadProfile,p)
	end
	PlayersService.PlayerAdded:Connect(Local.LoadProfile)
end

function Shared.ResetData(player: Player)
	local profile = Profiles[player]
	if not profile then return end

	-- Deep copy defaults to avoid shared references across players
	local defaults = PlayerDataTemplate.DEFAULT_PLAYER_DATA
	local fresh = table.clone(defaults)
	fresh.Settings = table.clone(defaults.Settings)
	fresh.Events = table.clone(defaults.Events)
	-- Reset containers explicitly
	fresh.Party = {}
	fresh.Boxes = {}
	fresh.Items = {}
	fresh.Creatures = {}
	fresh.Gamepasses = {}
	fresh.PickedUpItems = {}
	fresh.DefeatedTrainers = {}
	-- Remove optional runtime/session fields explicitly
	fresh.SelectedStarter = nil
	fresh.Starters = nil
	fresh.PendingCapture = nil
	-- Clear positional/session fields
    fresh.LastChunk = nil
    fresh.LastCF = nil
    fresh.LeaveData = nil
	fresh.Sequence = nil
	fresh.Chunk = nil
	fresh.DexNumber = 0

	-- Initialize Boxes to 8 empty new-schema boxes
	for i = 1, 8 do
		fresh.Boxes[i] = { Name = "Box " .. tostring(i), Creatures = {} }
	end

	profile.Data = fresh
	return profile.Data
end

function Local.LoadProfile(player:Player) 
	local Profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= PlayersService
		end,	
	})
	
	if Profile == nil then
		return player:Kick("Your data failed to load! Please rejoin.")
	end
	
	Profile:AddUserId(player.UserId)
	Profile:Reconcile()

	-- Initialize Boxes if missing: 8 boxes, 30 slots each (arrays)
	if not Profile.Data.Boxes or type(Profile.Data.Boxes) ~= "table" then
		Profile.Data.Boxes = {}
	end
	if #Profile.Data.Boxes < 8 then
		for i = #Profile.Data.Boxes + 1, 8 do
			Profile.Data.Boxes[i] = {}
		end
	end
	
	Profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Profile session has ended, please rejoin.")
	end)
	
	if player.Parent == PlayersService then
		Profiles[player] = Profile
		
		-- Proactively push initial data to client once the profile is ready
		do
			local ok, mod = pcall(function()
				return require(ServerScriptService.Server.ClientData)
			end)
			if ok and mod and mod.UpdateClientData then
				mod:UpdateClientData(player, Profile.Data)
			else
				-- Fallback to direct event to avoid tight coupling if module is unavailable
				pcall(function()
					local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
					Events.Communicate:FireClient(player, "ClientData", Profile.Data)
				end)
			end
		end

		-- Roll back any mid-battle state from a previous session using PendingBattle snapshot
		local data = Profile.Data
		if data and data.PendingBattle and type(data.PendingBattle) == "table" then
			local snap = data.PendingBattle
			-- Restore party
			if type(snap.Party) == "table" then
				data.Party = {}
				for i, c in ipairs(snap.Party) do
					data.Party[i] = c and table.clone(c) or nil
				end
			end
			-- Restore basic fields
			if snap.Studs ~= nil then data.Studs = snap.Studs end
			if type(snap.DefeatedTrainers) == "table" then data.DefeatedTrainers = table.clone(snap.DefeatedTrainers) end
			if type(snap.Chunk) == "string" then data.Chunk = snap.Chunk end
			if type(snap.LastChunk) == "string" then data.LastChunk = snap.LastChunk end
			if type(snap.LeaveData) == "table" then
				-- Only overwrite when snapshot includes LeaveData; otherwise preserve existing saved LeaveData
				data.LeaveData = table.clone(snap.LeaveData)
			end
			-- Clear snapshot after restore
			data.PendingBattle = nil
		end

		-- Only connect RemoveProfile if AutoSave is enabled in their settings
		if Profile.Data.Settings.AutoSave == true then
			player.AncestryChanged:Connect(function(_, parent)
				if not parent then
					warn("AUTO SAVE IS ENABLED FOR THIS PLAYER")
					Local.RemoveProfile(player)
				end
			end)
		else
			warn("AUTO SAVE IS DISABLED")
		end
	else
		Profile:EndSession()
	end
end

function Local.RemoveProfile(player: Player)
	local profile = Profiles[player]
	if not profile then 
		print(`[DATA] Tried to remove profile for {player.Name}, but no profile was found.`)
		return 
	end

    -- Do not persist progress if in battle, in cutscene, or on the title screen
    local inBattle = (profile.Data and profile.Data.InBattle == true)
    local inCutscene = (profile.Data and profile.Data.InCutscene == true)
    local atTitle = (profile.Data and ((profile.Data.Chunk == nil) or (profile.Data.Chunk == "nil") or (profile.Data.Chunk == "Title")))
    if profile.Data.Settings.AutoSave == true and not inBattle and not inCutscene and not atTitle then
        print(`[DATA] AutoSave is ON for {player.Name}, saving + ending session...`)
        profile:EndSession()
    else
        -- ProfileStore does not support a non-saving release; end session gracefully
        print(`[DATA] AutoSave is OFF, Title screen, or InBattle for {player.Name}, ending session without manual save`)
        profile:EndSession()
    end

	Profiles[player] = nil
	print(`[DATA] Profile removed for {player.Name}`)
end

function Shared.ManualSave(player: Player)
	local profile = Profiles[player]
	if not profile then 
		print(`[DATA] ManualSave failed: {player.Name} has no profile loaded.`)
		return false 
	end

    -- Never allow manual saves during battle, cutscenes, or on title screen
    local atTitle = (profile.Data and ((profile.Data.Chunk == nil) or (profile.Data.Chunk == "nil") or (profile.Data.Chunk == "Title")))
    if (profile.Data and (profile.Data.InBattle == true or profile.Data.InCutscene == true)) or atTitle then
        warn(`[DATA] ManualSave blocked: {player.Name} is currently InBattle/InCutscene or on Title screen`)
		return false
	end

	print(`[DATA] {player.Name} manually saved. Committing data...`)

	-- Capture latest position and chunk before saving
	local data = profile.Data
	if data then
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		-- Prefer current Chunk; fall back to LastChunk to ensure LeaveData is usable on Continue
		local currentChunk = (type(data.Chunk) == "string" and data.Chunk) or (type(data.LastChunk) == "string" and data.LastChunk) or nil
		if hrp and hrp:IsA("BasePart") and currentChunk ~= nil then
			local cf = hrp.CFrame
			local rx, ry, rz = cf:ToOrientation()
			data.LeaveData = {
				Position = { X = hrp.Position.X, Y = hrp.Position.Y, Z = hrp.Position.Z },
				Rotation = { X = rx, Y = ry, Z = rz },
				Chunk = currentChunk,
			}
			-- Keep LastChunk consistent for server chunk authorization and client fallbacks
			data.LastChunk = currentChunk
		end
	end

	-- Force a save
	local success, err = pcall(function()
		-- Mark this save as explicitly user-initiated to bypass autosave gating
		if data then
			data._AllowOneSave = true
		end
		profile:Save()
	end)

	if success then
		print(`[DATA] Manual save successful for {player.Name}`)
		return true
	else
		warn(`[DATA] Manual save FAILED for {player.Name}: {err}`)
		return false
	end
end


function Shared.GetData(player: Player, timeoutSeconds: number?): PlayerDataTemplate.PlayerData?
	local profile = Profiles[player]
	if not profile then return end
	return profile.Data
end


function Shared.UpdateGems(player:Player,amount:number)
	local data = Shared.GetData(player)
	if not data then return end
	
	local gems = data.Gems
	print(`Player had {gems}`)
	data.Gems += amount
	print(`Player now has {data.Gems}`)
end

Local.OnStart()

return Shared
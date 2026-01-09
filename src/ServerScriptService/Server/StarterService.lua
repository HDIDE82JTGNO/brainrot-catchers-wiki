local StarterService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local ClientData = require(script.Parent.ClientData)
local CreatureFactory = require(script.Parent:WaitForChild("CreatureFactory"))
local AbilitiesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Abilities"))

-- Session-scoped flags (cleared on player leave) for starter generation/refresh control
local SessionStarterGenerated: {[Player]: boolean} = {}

Players.PlayerRemoving:Connect(function(p: Player)
	SessionStarterGenerated[p] = nil
end)

function StarterService.RequestStarters(Player: Player)
	local PlayerData = ClientData:Get(Player)
	if not PlayerData then
		return nil
	end

	-- Per-session behavior:
	-- - First Request in a session:
	--   * If no starters exist yet -> generate new set and mark generated
	--   * If starters already exist (from previous session) and no selection -> REFRESH ONCE (generate new), then mark generated
	-- - Subsequent Requests in the same session (generated==true):
	--   * If no selection -> return existing without regenerating
	--   * If selection made -> return nil (no re-present)
	local generatedThisSession = SessionStarterGenerated[Player] == true
	if PlayerData.Starters then
		if PlayerData.SelectedStarter then
			DBG:print("[RequestStarters] Starter already selected for", Player.Name)
			return nil
		end
		if not generatedThisSession then
			DBG:print("[RequestStarters] Refreshing starters once for this session for", Player.Name)
			-- Fall through to (re)generation path below by clearing starters
			PlayerData.Starters = nil
		else
			-- Return existing set without regenerating
			local ForClient = {}
			for i, creature in ipairs(PlayerData.Starters) do
				ForClient[i] = { Name = creature.Name, Shiny = creature.Shiny }
			end
			--DBG:print("[RequestStarters] Returning existing starters (session already generated) for", Player.Name)
			return ForClient
		end
	end

	-- Define the three starter creatures
	local starterInfo = {
		{Creature = "Frigo Camelo", Level = 5},
		{Creature = "Kitung", Level = 5},
		{Creature = "Twirlina", Level = 5},
	}

	-- Initialize starters array in player data
	PlayerData.Starters = {}

	-- Data to send to client
	local ForClient = {}

	-- Generate each starter creature
	for i, info in ipairs(starterInfo) do
		-- Tag Original Trainer (OT) and catcher name with player's chosen nickname if available
		info.OT = Player.UserId
		local caughtByName = (PlayerData and PlayerData.Nickname) or Player.Name
		info.CaughtBy = caughtByName
		-- Starter creatures are tradelocked by design
		info.TradeLocked = true
		local creature = CreatureFactory.CreateFromInfo(info)
		PlayerData.Starters[i] = creature

		ForClient[i] = {
			Name = creature.Name,
			Shiny = creature.Shiny,
		}
	end

	-- Update the client's data
	ClientData:UpdateClientData(Player, PlayerData)
	-- Mark generated for this session (prevents further refresh within the same join)
	SessionStarterGenerated[Player] = true

	DBG:print("Generated starters for player:", Player.Name)
	return ForClient
end

function StarterService.PickStarter(Player: Player, StarterName: string)
	local PlayerData = ClientData:Get(Player)

	-- Check if player has starters
	if not PlayerData or not PlayerData.Starters then
		Player:Kick("No starters available!")
		return false
	end

	-- Check if player already picked a starter
	if PlayerData.SelectedStarter then
		Player:Kick("Already selected a starter!")
		return false
	end

	-- Find the selected starter
	local selectedStarter = nil
	for _, starter in ipairs(PlayerData.Starters) do
		if starter.Name == StarterName then
			selectedStarter = starter
			break
		end
	end

	if not selectedStarter then
		Player:Kick("Invalid starter selection!")
		return false
	end

	-- Add the selected starter to player's party
	PlayerData.Party = PlayerData.Party or {}

	-- Ensure the starter has an assigned ability (backfill for pre-fix starters)
	if not selectedStarter.Ability or selectedStarter.Ability == "" then
		selectedStarter.Ability = AbilitiesModule.SelectAbility(selectedStarter.Name, false)
	end

	PlayerData.Party[1] = selectedStarter
	PlayerData.SelectedStarter = StarterName
	
	-- Mark starter creature as seen (caught implies seen)
	PlayerData.SeenCreatures = PlayerData.SeenCreatures or {}
	if not PlayerData.SeenCreatures[selectedStarter.Name] then
		PlayerData.SeenCreatures[selectedStarter.Name] = true
		DBG:print("[Seen] Marked", selectedStarter.Name, "as seen (starter selected)")
	end
	
	-- Mark FIRST_CREATURE acquired
	pcall(function()
		PlayerData.Events = PlayerData.Events or {}
		if PlayerData.Events.FIRST_CREATURE ~= true then
			PlayerData.Events.FIRST_CREATURE = true
		end
	end)

	-- Update the client's data
	ClientData:UpdateClientData(Player, PlayerData)

	DBG:print("Player", Player.Name, "selected starter:", StarterName)
	DBG:print("Starter added to party:", selectedStarter.Name, "Level:", selectedStarter.Level, "Shiny:", selectedStarter.Shiny)
	DBG:print("Player party now contains:", #PlayerData.Party, "creatures")
	return true
end

return StarterService


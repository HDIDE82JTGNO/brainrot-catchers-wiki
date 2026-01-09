--[[
	ChallengesSystem.lua
	Server-side module for managing daily and weekly challenges.
	
	Features:
	- Daily challenges (3) that refresh at 00:00 UTC
	- Weekly challenges (6) that refresh at 00:00 UTC Monday
	- Automatic period detection and progress reset
	- All players receive the same challenges (deterministic)
	- Progress tracking for all challenge types
	- Reward distribution on completion
	- Client notification system
]]

--// Types
export type ChallengeProgress = {
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
}

export type DailyChallengesData = {
	DaySeed: number,
	Progress: { [string]: ChallengeProgress },
}

export type WeeklyChallengesData = {
	WeekSeed: number,
	Progress: { [string]: ChallengeProgress },
}

--// Module
local ChallengesSystem = {}

--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

--// Dependencies
local ChallengesConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ChallengesConfig"))
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

-- Dependencies (set during initialization)
local ClientData = nil
local Events = nil

--============================================================================--
-- INITIALIZATION
--============================================================================--

--- Initialize the ChallengesSystem with dependencies
--- @param deps table Dependencies containing ClientData and Events
function ChallengesSystem.Initialize(deps: { ClientData: any, Events: any? })
	ClientData = deps.ClientData
	Events = deps.Events or ReplicatedStorage:WaitForChild("Events")
end

--============================================================================--
-- PERIOD MANAGEMENT
--============================================================================--

--- Initialize or reset a player's challenge progress for a new period
--- @param playerData table Player's data table
--- @param challengeType "Daily" | "Weekly" Challenge category
local function initializeChallengesForPeriod(
	playerData: any,
	challengeType: "Daily" | "Weekly"
)
	local challenges: { ChallengesConfig.ChallengeDefinition }
	local currentSeed: number
	local dataKey: string
	local seedKey: string
	
	if challengeType == "Daily" then
		challenges = ChallengesConfig.GetCurrentDailyChallenges()
		currentSeed = ChallengesConfig.GetDaySeed()
		dataKey = "DailyChallenges"
		seedKey = "DaySeed"
	else
		challenges = ChallengesConfig.GetCurrentWeeklyChallenges()
		currentSeed = ChallengesConfig.GetWeekSeed()
		dataKey = "WeeklyChallenges"
		seedKey = "WeekSeed"
	end
	
	-- Ensure the data structure exists
	if not playerData[dataKey] then
		playerData[dataKey] = {
			[seedKey] = 0,
			Progress = {},
		}
	end
	
	-- Check if we need to reset (new period)
	if playerData[dataKey][seedKey] ~= currentSeed then
		-- New period - reset all progress
		playerData[dataKey][seedKey] = currentSeed
		playerData[dataKey].Progress = {}
		
		DBG:print(string.format(
			"[ChallengesSystem] Reset %s challenges for new period (seed: %d)",
			challengeType,
			currentSeed
		))
	end
	
	-- Initialize progress for any missing challenges
	for _, challenge in ipairs(challenges) do
		if not playerData[dataKey].Progress[challenge.Id] then
			playerData[dataKey].Progress[challenge.Id] = {
				Progress = 0,
				Completed = false,
				Claimed = false,
			}
		end
	end
end

--- Ensure player has properly initialized challenge data for current periods
--- @param playerData table Player's data table
local function ensureChallengesData(playerData: any)
	initializeChallengesForPeriod(playerData, "Daily")
	initializeChallengesForPeriod(playerData, "Weekly")
end

--============================================================================--
-- PROGRESS TRACKING
--============================================================================--

--- Get player's progress for a specific challenge
--- @param player Player The player
--- @param challengeId string Challenge ID
--- @return Progress data or nil
function ChallengesSystem.GetChallengeProgress(player: Player, challengeId: string)
	if not ClientData then return nil end
	
	local playerData = ClientData:Get(player)
	if not playerData then return nil end
	
	ensureChallengesData(playerData)
	
	-- Check daily challenges
	if playerData.DailyChallenges.Progress[challengeId] then
		return playerData.DailyChallenges.Progress[challengeId]
	end
	
	-- Check weekly challenges
	if playerData.WeeklyChallenges.Progress[challengeId] then
		return playerData.WeeklyChallenges.Progress[challengeId]
	end
	
	return nil
end

--- Update progress for a specific challenge type
--- Returns list of newly completed challenge IDs
--- @param player Player The player
--- @param challengeType string Type of challenge (e.g., "CaptureCreatures")
--- @param amount number? Amount to increment (default 1)
--- @param specificData any? Additional data for special challenge types
--- @return Array of newly completed challenge IDs
function ChallengesSystem.UpdateProgress(
	player: Player,
	challengeType: string,
	amount: number?,
	specificData: any?
)
	if not ClientData then return {} end
	
	local playerData = ClientData:Get(player)
	if not playerData then return {} end
	
	ensureChallengesData(playerData)
	
	amount = amount or 1
	local newlyCompleted: { string } = {}
	
	-- Get active challenges of this type (only current daily/weekly)
	local activeChallenges = ChallengesConfig.GetActiveChallengesByType(challengeType)
	
	for _, challenge in ipairs(activeChallenges) do
		-- Determine which data store to use
		local progressStore: { [string]: ChallengeProgress }?
		if ChallengesConfig.IsDailyChallenge(challenge.Id) then
			progressStore = playerData.DailyChallenges.Progress
		else
			progressStore = playerData.WeeklyChallenges.Progress
		end
		
		if not progressStore then continue end
		
		local progress = progressStore[challenge.Id]
		if not progress or progress.Completed then continue end
		
		-- Calculate new progress based on challenge type
		local newProgress = progress.Progress
		
		if challengeType == "CaptureCreatures"
			or challengeType == "DefeatTrainers"
			or challengeType == "WinWildBattles"
			or challengeType == "EvolveCreature"
			or challengeType == "WalkSteps"
			or challengeType == "UseMoves"
			or challengeType == "HealCreatures"
		then
			-- Incremental challenges
			newProgress = progress.Progress + amount
			
		elseif challengeType == "CaptureUniqueTypes" then
			-- Count unique types captured
			if specificData and typeof(specificData) == "table" then
				local uniqueTypes: { [string]: boolean } = {}
				
				for _, creature in ipairs(playerData.Party or {}) do
					if creature and creature.Type then
						uniqueTypes[creature.Type] = true
					end
				end
				
				for _, box in ipairs(playerData.Boxes or {}) do
					if typeof(box) == "table" and box.Creatures then
						for _, creature in ipairs(box.Creatures) do
							if creature and creature.Type then
								uniqueTypes[creature.Type] = true
							end
						end
					end
				end
				
				local count = 0
				for _ in pairs(uniqueTypes) do
					count = count + 1
				end
				newProgress = count
			end
			
		elseif challengeType == "ReachLevel" then
			-- Only complete if a creature crossed the level threshold
			if specificData and typeof(specificData) == "table" then
				local prevLevel = specificData.PreviousLevel or 0
				local newLevel = specificData.NewLevel or 0
				
				if prevLevel < challenge.Goal and newLevel >= challenge.Goal then
					newProgress = challenge.Goal
				else
					newProgress = progress.Progress
				end
			else
				newProgress = progress.Progress
			end
			
		elseif challengeType == "DiscoverCreatures" then
			-- Count seen creatures
			local count = 0
			for _ in pairs(playerData.SeenCreatures or {}) do
				count = count + 1
			end
			newProgress = count
		end
		
		-- Clamp to goal
		newProgress = math.min(newProgress, challenge.Goal)
		progress.Progress = newProgress
		
		-- Check if completed
		if newProgress >= challenge.Goal and not progress.Completed then
			progress.Completed = true
			table.insert(newlyCompleted, challenge.Id)
			
			DBG:print(string.format(
				"[ChallengesSystem] Player %s completed challenge: %s",
				player.Name,
				challenge.Id
			))
		end
	end
	
	-- Update client data
	if ClientData.UpdateClientData then
		ClientData:UpdateClientData(player, playerData)
	end
	
	-- Auto-claim rewards and notify client of completions
	for _, challengeId in ipairs(newlyCompleted) do
		-- Auto-claim the reward immediately upon completion
		local claimSuccess, rewardText = ChallengesSystem.ClaimReward(player, challengeId)
		if claimSuccess then
			DBG:print(string.format(
				"[ChallengesSystem] Auto-claimed reward for %s: %s",
				challengeId,
				rewardText
			))
		end
		ChallengesSystem.NotifyCompletion(player, challengeId)
	end
	
	return newlyCompleted
end

--============================================================================--
-- REWARD CLAIMING
--============================================================================--

--- Claim reward for a completed challenge
--- @param player Player The player
--- @param challengeId string Challenge ID to claim
--- @return boolean Success status
--- @return string Result message or reward text
function ChallengesSystem.ClaimReward(player: Player, challengeId: string): (boolean, string)
	if not ClientData then return false, "System not initialized" end
	
	local playerData = ClientData:Get(player)
	if not playerData then return false, "No player data" end
	
	ensureChallengesData(playerData)
	
	-- Find the progress in daily or weekly
	local progress: ChallengeProgress?
	local isDaily = ChallengesConfig.IsDailyChallenge(challengeId)
	
	if isDaily then
		progress = playerData.DailyChallenges.Progress[challengeId]
	else
		progress = playerData.WeeklyChallenges.Progress[challengeId]
	end
	
	if not progress then return false, "Challenge not found" end
	if not progress.Completed then return false, "Challenge not completed" end
	if progress.Claimed then return false, "Reward already claimed" end
	
	local challenge = ChallengesConfig.GetChallengeById(challengeId)
	if not challenge then return false, "Challenge config not found" end
	
	-- Grant reward
	local reward = challenge.Reward
	local rewardText = ""
	
	if reward.Type == "Item" then
		if not playerData.Items then
			playerData.Items = {}
		end
		local currentAmount = playerData.Items[reward.ItemName] or 0
		playerData.Items[reward.ItemName] = currentAmount + reward.Amount
		rewardText = string.format("%s x%d", reward.ItemName, reward.Amount)
		
	elseif reward.Type == "Studs" then
		local previousStuds = playerData.Studs or 0
		playerData.Studs = previousStuds + reward.Amount
		rewardText = string.format("%d Studs", reward.Amount)
		DBG:print(string.format(
			"[ChallengesSystem] Studs reward: %d + %d = %d",
			previousStuds,
			reward.Amount,
			playerData.Studs
		))
	end
	
	-- Mark as claimed
	progress.Claimed = true
	
	DBG:print(string.format(
		"[ChallengesSystem] Before UpdateClientData - playerData.Studs = %s",
		tostring(playerData.Studs)
	))
	
	-- Update client data
	if ClientData.UpdateClientData then
		ClientData:UpdateClientData(player, playerData)
	end
	
	DBG:print(string.format(
		"[ChallengesSystem] Player %s claimed reward for: %s -> %s",
		player.Name,
		challengeId,
		rewardText
	))
	
	return true, rewardText
end

--============================================================================--
-- CLIENT COMMUNICATION
--============================================================================--

--- Notify client that a challenge was completed
--- @param player Player The player to notify
--- @param challengeId string Completed challenge ID
function ChallengesSystem.NotifyCompletion(player: Player, challengeId: string)
	if not Events then return end
	
	local challenge = ChallengesConfig.GetChallengeById(challengeId)
	if not challenge then return end
	
	local communicateEvent = Events:FindFirstChild("Communicate")
	if communicateEvent then
		communicateEvent:FireClient(player, "ChallengeCompleted", {
			ChallengeId = challengeId,
			Name = challenge.Name,
			Description = challenge.Description,
			RewardText = ChallengesConfig.GetRewardText(challenge),
			ProfessorMessage = challenge.ProfessorMessage,
			Category = ChallengesConfig.IsDailyChallenge(challengeId) and "Daily" or "Weekly",
		})
	end
end

--- Notify client that challenges have refreshed
--- @param player Player The player to notify
--- @param category "Daily" | "Weekly" | "Both" Which challenges refreshed
function ChallengesSystem.NotifyChallengesRefreshed(player: Player, category: "Daily" | "Weekly" | "Both")
	if not Events then return end
	
	local communicateEvent = Events:FindFirstChild("Communicate")
	if communicateEvent then
		communicateEvent:FireClient(player, "ChallengesRefreshed", {
			Category = category,
		})
	end
end

--============================================================================--
-- DATA RETRIEVAL
--============================================================================--

--- Get all challenges with their current progress for a player
--- @param player Player The player
--- @return Challenge data with progress
function ChallengesSystem.GetAllChallengesForPlayer(player: Player)
	if not ClientData then
		return {
			Daily = {},
			Weekly = {},
			DailyRefreshTime = 0,
			WeeklyRefreshTime = 0,
		}
	end
	
	local playerData = ClientData:Get(player)
	if not playerData then
		return {
			Daily = {},
			Weekly = {},
			DailyRefreshTime = 0,
			WeeklyRefreshTime = 0,
		}
	end
	
	ensureChallengesData(playerData)
	
	local result: ChallengesConfig.ChallengesData = {
		Daily = {},
		Weekly = {},
		DailyRefreshTime = ChallengesConfig.GetSecondsUntilDailyRefresh(),
		WeeklyRefreshTime = ChallengesConfig.GetSecondsUntilWeeklyRefresh(),
	}
	
	-- Build daily challenges list
	for _, challenge in ipairs(ChallengesConfig.GetCurrentDailyChallenges()) do
		local progress = playerData.DailyChallenges.Progress[challenge.Id]
			or { Progress = 0, Completed = false, Claimed = false }
		
		table.insert(result.Daily, {
			Id = challenge.Id,
			Name = challenge.Name,
			Description = challenge.Description,
			Goal = challenge.Goal,
			Progress = progress.Progress,
			Completed = progress.Completed,
			Claimed = progress.Claimed,
			RewardText = ChallengesConfig.GetRewardText(challenge),
			Category = "Daily",
		})
	end
	
	-- Build weekly challenges list
	for _, challenge in ipairs(ChallengesConfig.GetCurrentWeeklyChallenges()) do
		local progress = playerData.WeeklyChallenges.Progress[challenge.Id]
			or { Progress = 0, Completed = false, Claimed = false }
		
		table.insert(result.Weekly, {
			Id = challenge.Id,
			Name = challenge.Name,
			Description = challenge.Description,
			Goal = challenge.Goal,
			Progress = progress.Progress,
			Completed = progress.Completed,
			Claimed = progress.Claimed,
			RewardText = ChallengesConfig.GetRewardText(challenge),
			Category = "Weekly",
		})
	end
	
	return result
end

--============================================================================--
-- PROGRESS RECALCULATION
--============================================================================--

--- Recalculate all progress-based challenges (for DiscoverCreatures, CaptureUniqueTypes)
--- NOTE: ReachLevel is NOT recalculated - it only updates when a creature actually levels up
--- @param player Player The player
function ChallengesSystem.RecalculateProgress(player: Player)
	if not ClientData then return end
	
	local playerData = ClientData:Get(player)
	if not playerData then return end
	
	ensureChallengesData(playerData)
	
	-- Recalculate discovery challenges
	ChallengesSystem.UpdateProgress(player, "DiscoverCreatures", 0)
	
	-- Recalculate unique types
	ChallengesSystem.UpdateProgress(player, "CaptureUniqueTypes", 0, {})
end

--============================================================================--
-- PERIOD CHECK (for live refresh detection)
--============================================================================--

--- Check if player's challenges need refresh and notify if so
--- Called periodically or on player join
--- @param player Player The player to check
function ChallengesSystem.CheckAndRefreshPeriods(player: Player)
	if not ClientData then return end
	
	local playerData = ClientData:Get(player)
	if not playerData then return end
	
	local currentDaySeed = ChallengesConfig.GetDaySeed()
	local currentWeekSeed = ChallengesConfig.GetWeekSeed()
	
	local dailyRefreshed = false
	local weeklyRefreshed = false
	
	-- Check daily
	if not playerData.DailyChallenges or playerData.DailyChallenges.DaySeed ~= currentDaySeed then
		dailyRefreshed = true
	end
	
	-- Check weekly
	if not playerData.WeeklyChallenges or playerData.WeeklyChallenges.WeekSeed ~= currentWeekSeed then
		weeklyRefreshed = true
	end
	
	-- Initialize/reset as needed
	ensureChallengesData(playerData)
	
	-- Update client data
	if ClientData.UpdateClientData and (dailyRefreshed or weeklyRefreshed) then
		ClientData:UpdateClientData(player, playerData)
	end
	
	-- Notify client
	if dailyRefreshed and weeklyRefreshed then
		ChallengesSystem.NotifyChallengesRefreshed(player, "Both")
	elseif dailyRefreshed then
		ChallengesSystem.NotifyChallengesRefreshed(player, "Daily")
	elseif weeklyRefreshed then
		ChallengesSystem.NotifyChallengesRefreshed(player, "Weekly")
	end
end

return ChallengesSystem

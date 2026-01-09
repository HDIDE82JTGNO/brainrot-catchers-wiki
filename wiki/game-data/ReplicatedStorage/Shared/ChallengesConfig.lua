--[[
	ChallengesConfig.lua
	Defines daily and weekly challenge pools with deterministic rotation.
	
	System Overview:
	- Daily Challenges: 3 challenges that refresh at 00:00 UTC each day
	- Weekly Challenges: 6 challenges that refresh at 00:00 UTC each Monday
	- All players receive the same challenges (deterministic based on date seed)
	- Large expandable pool ensures variety without running out of content
	
	Challenge Types:
	- CaptureCreatures: Capture X creatures
	- CaptureUniqueTypes: Capture X creatures of different types
	- DefeatTrainers: Defeat X trainers
	- WinWildBattles: Win X wild battles
	- EvolveCreature: Evolve X creatures
	- ReachLevel: Get a creature to level X
	- WalkSteps: Walk X steps
	- DiscoverCreatures: See X different creatures in battle
	- UseMoves: Use moves in battle X times
	- HealCreatures: Heal creatures X times using potions
]]

--// Types
export type RewardData = {
	Type: "Item" | "Studs",
	ItemName: string?,
	Amount: number,
}

export type ChallengeDefinition = {
	Id: string,
	Name: string,
	Description: string,
	Type: string,
	Goal: number,
	Reward: RewardData,
	ProfessorMessage: string,
}

export type ChallengeEntry = {
	Id: string,
	Name: string,
	Description: string,
	Goal: number,
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
	RewardText: string,
	Category: "Daily" | "Weekly",
}

export type ChallengesData = {
	Daily: { ChallengeEntry },
	Weekly: { ChallengeEntry },
	DailyRefreshTime: number, -- Seconds until next daily refresh
	WeeklyRefreshTime: number, -- Seconds until next weekly refresh
}

--// Module
local ChallengesConfig = {}

--// Constants
ChallengesConfig.DAILY_CHALLENGE_COUNT = 3
ChallengesConfig.WEEKLY_CHALLENGE_COUNT = 6

--============================================================================--
-- DAILY CHALLENGE POOL
-- These are smaller, achievable-in-a-day tasks with modest rewards
--============================================================================--
ChallengesConfig.DailyChallenges = {
	-- Capture Challenges (Daily)
	{
		Id = "daily_capture_3",
		Name = "Quick Catch",
		Description = "Capture 3 creatures.",
		Type = "CaptureCreatures",
		Goal = 3,
		Reward = { Type = "Item", ItemName = "Potion", Amount = 2 },
		ProfessorMessage = "Nice catches! Keep it up!",
	},
	{
		Id = "daily_capture_5",
		Name = "Creature Hunt",
		Description = "Capture 5 creatures.",
		Type = "CaptureCreatures",
		Goal = 5,
		Reward = { Type = "Item", ItemName = "Potion", Amount = 3 },
		ProfessorMessage = "Your catching skills are impressive!",
	},
	{
		Id = "daily_capture_8",
		Name = "Catching Spree",
		Description = "Capture 8 creatures.",
		Type = "CaptureCreatures",
		Goal = 8,
		Reward = { Type = "Item", ItemName = "Super Potion", Amount = 2 },
		ProfessorMessage = "What a productive catching session!",
	},
	
	-- Battle Challenges (Daily)
	{
		Id = "daily_wild_battles_3",
		Name = "Wild Skirmish",
		Description = "Win 3 wild battles.",
		Type = "WinWildBattles",
		Goal = 3,
		Reward = { Type = "Studs", Amount = 150 },
		ProfessorMessage = "Great battle performance!",
	},
	{
		Id = "daily_wild_battles_5",
		Name = "Wild Warrior",
		Description = "Win 5 wild battles.",
		Type = "WinWildBattles",
		Goal = 5,
		Reward = { Type = "Studs", Amount = 250 },
		ProfessorMessage = "You're dominating the wild!",
	},
	{
		Id = "daily_wild_battles_8",
		Name = "Nature's Champion",
		Description = "Win 8 wild battles.",
		Type = "WinWildBattles",
		Goal = 8,
		Reward = { Type = "Item", ItemName = "Super Potion", Amount = 2 },
		ProfessorMessage = "The wild creatures fear you now!",
	},
	{
		Id = "daily_trainer_1",
		Name = "Trainer Duel",
		Description = "Defeat 1 trainer in battle.",
		Type = "DefeatTrainers",
		Goal = 1,
		Reward = { Type = "Studs", Amount = 200 },
		ProfessorMessage = "A worthy victory!",
	},
	{
		Id = "daily_trainer_2",
		Name = "Double Trouble",
		Description = "Defeat 2 trainers in battle.",
		Type = "DefeatTrainers",
		Goal = 2,
		Reward = { Type = "Studs", Amount = 400 },
		ProfessorMessage = "Two trainers down, excellent!",
	},
	
	-- Discovery Challenges (Daily)
	{
		Id = "daily_discover_3",
		Name = "Scout's Eye",
		Description = "Discover 3 different creatures.",
		Type = "DiscoverCreatures",
		Goal = 3,
		Reward = { Type = "Item", ItemName = "Capture Cube", Amount = 3 },
		ProfessorMessage = "New discoveries for the research!",
	},
	{
		Id = "daily_discover_5",
		Name = "Field Notes",
		Description = "Discover 5 different creatures.",
		Type = "DiscoverCreatures",
		Goal = 5,
		Reward = { Type = "Item", ItemName = "Capture Cube", Amount = 5 },
		ProfessorMessage = "Your dex is expanding nicely!",
	},
	
	-- Walking Challenges (Daily)
	{
		Id = "daily_walk_500",
		Name = "Morning Stroll",
		Description = "Walk 500 steps.",
		Type = "WalkSteps",
		Goal = 500,
		Reward = { Type = "Studs", Amount = 100 },
		ProfessorMessage = "A nice walk in the fresh air!",
	},
	{
		Id = "daily_walk_1000",
		Name = "Daily Walker",
		Description = "Walk 1,000 steps.",
		Type = "WalkSteps",
		Goal = 1000,
		Reward = { Type = "Studs", Amount = 200 },
		ProfessorMessage = "Good exercise today!",
	},
	{
		Id = "daily_walk_2000",
		Name = "Trail Blazer",
		Description = "Walk 2,000 steps.",
		Type = "WalkSteps",
		Goal = 2000,
		Reward = { Type = "Item", ItemName = "Potion", Amount = 3 },
		ProfessorMessage = "You've really been exploring!",
	},
	
	-- Evolution Challenges (Daily - rare, always 1)
	{
		Id = "daily_evolve_1",
		Name = "Evolution Day",
		Description = "Evolve 1 creature.",
		Type = "EvolveCreature",
		Goal = 1,
		Reward = { Type = "Item", ItemName = "Rare Candy", Amount = 1 },
		ProfessorMessage = "Witnessing evolution is magical!",
	},
	
	-- Healing Challenges (Daily)
	{
		Id = "daily_heal_3",
		Name = "First Aid",
		Description = "Use potions to heal creatures 3 times.",
		Type = "HealCreatures",
		Goal = 3,
		Reward = { Type = "Item", ItemName = "Potion", Amount = 2 },
		ProfessorMessage = "Taking care of your team!",
	},
	{
		Id = "daily_heal_5",
		Name = "Field Medic",
		Description = "Use potions to heal creatures 5 times.",
		Type = "HealCreatures",
		Goal = 5,
		Reward = { Type = "Item", ItemName = "Super Potion", Amount = 1 },
		ProfessorMessage = "Your creatures are well cared for!",
	},
	
	-- Move Usage Challenges (Daily)
	{
		Id = "daily_moves_10",
		Name = "Combat Practice",
		Description = "Use moves in battle 10 times.",
		Type = "UseMoves",
		Goal = 10,
		Reward = { Type = "Studs", Amount = 100 },
		ProfessorMessage = "Good training session!",
	},
	{
		Id = "daily_moves_20",
		Name = "Battle Tactics",
		Description = "Use moves in battle 20 times.",
		Type = "UseMoves",
		Goal = 20,
		Reward = { Type = "Studs", Amount = 200 },
		ProfessorMessage = "Your battle strategy is improving!",
	},
	{
		Id = "daily_moves_30",
		Name = "Move Master",
		Description = "Use moves in battle 30 times.",
		Type = "UseMoves",
		Goal = 30,
		Reward = { Type = "Item", ItemName = "Super Potion", Amount = 1 },
		ProfessorMessage = "Excellent combat mastery!",
	},
	
	-- Unique Type Capture (Daily)
	{
		Id = "daily_unique_types_2",
		Name = "Type Diversity",
		Description = "Capture creatures of 2 different types.",
		Type = "CaptureUniqueTypes",
		Goal = 2,
		Reward = { Type = "Item", ItemName = "Capture Cube", Amount = 3 },
		ProfessorMessage = "Diversity in your catches!",
	},
}

--============================================================================--
-- WEEKLY CHALLENGE POOL
-- These are larger goals with better rewards, designed for a week of play
--============================================================================--
ChallengesConfig.WeeklyChallenges = {
	-- Capture Challenges (Weekly)
	{
		Id = "weekly_capture_20",
		Name = "Capture Collector",
		Description = "Capture 20 creatures.",
		Type = "CaptureCreatures",
		Goal = 20,
		Reward = { Type = "Item", ItemName = "Great Cube", Amount = 5 },
		ProfessorMessage = "Amazing dedication to catching!",
	},
	{
		Id = "weekly_capture_35",
		Name = "Master Catcher",
		Description = "Capture 35 creatures.",
		Type = "CaptureCreatures",
		Goal = 35,
		Reward = { Type = "Item", ItemName = "Great Cube", Amount = 8 },
		ProfessorMessage = "You're becoming a legendary catcher!",
	},
	{
		Id = "weekly_capture_50",
		Name = "Capture Champion",
		Description = "Capture 50 creatures.",
		Type = "CaptureCreatures",
		Goal = 50,
		Reward = { Type = "Item", ItemName = "Ultra Cube", Amount = 3 },
		ProfessorMessage = "Unbelievable catching prowess!",
	},
	
	-- Battle Challenges (Weekly)
	{
		Id = "weekly_wild_battles_15",
		Name = "Wild Dominator",
		Description = "Win 15 wild battles.",
		Type = "WinWildBattles",
		Goal = 15,
		Reward = { Type = "Studs", Amount = 500 },
		ProfessorMessage = "The wilderness bows to you!",
	},
	{
		Id = "weekly_wild_battles_30",
		Name = "Nature's Bane",
		Description = "Win 30 wild battles.",
		Type = "WinWildBattles",
		Goal = 30,
		Reward = { Type = "Studs", Amount = 1000 },
		ProfessorMessage = "Incredible wild battle record!",
	},
	{
		Id = "weekly_wild_battles_50",
		Name = "Apex Predator",
		Description = "Win 50 wild battles.",
		Type = "WinWildBattles",
		Goal = 50,
		Reward = { Type = "Item", ItemName = "Hyper Potion", Amount = 5 },
		ProfessorMessage = "You rule the wilderness!",
	},
	{
		Id = "weekly_trainer_5",
		Name = "Rival Crusher",
		Description = "Defeat 5 trainers in battle.",
		Type = "DefeatTrainers",
		Goal = 5,
		Reward = { Type = "Studs", Amount = 750 },
		ProfessorMessage = "Trainers respect your strength!",
	},
	{
		Id = "weekly_trainer_10",
		Name = "Tournament Champion",
		Description = "Defeat 10 trainers in battle.",
		Type = "DefeatTrainers",
		Goal = 10,
		Reward = { Type = "Studs", Amount = 1500 },
		ProfessorMessage = "You're a force to be reckoned with!",
	},
	{
		Id = "weekly_trainer_15",
		Name = "Legendary Duelist",
		Description = "Defeat 15 trainers in battle.",
		Type = "DefeatTrainers",
		Goal = 15,
		Reward = { Type = "Item", ItemName = "Max Potion", Amount = 3 },
		ProfessorMessage = "No trainer can stand against you!",
	},
	
	-- Discovery Challenges (Weekly)
	{
		Id = "weekly_discover_10",
		Name = "Research Assistant",
		Description = "Discover 10 different creatures.",
		Type = "DiscoverCreatures",
		Goal = 10,
		Reward = { Type = "Item", ItemName = "Great Cube", Amount = 5 },
		ProfessorMessage = "Excellent field research!",
	},
	{
		Id = "weekly_discover_20",
		Name = "Dex Scholar",
		Description = "Discover 20 different creatures.",
		Type = "DiscoverCreatures",
		Goal = 20,
		Reward = { Type = "Item", ItemName = "Great Cube", Amount = 8 },
		ProfessorMessage = "Your dex knowledge is impressive!",
	},
	{
		Id = "weekly_discover_30",
		Name = "Creature Encyclopedist",
		Description = "Discover 30 different creatures.",
		Type = "DiscoverCreatures",
		Goal = 30,
		Reward = { Type = "Item", ItemName = "Ultra Cube", Amount = 2 },
		ProfessorMessage = "A true creature scholar!",
	},
	
	-- Walking Challenges (Weekly)
	{
		Id = "weekly_walk_5000",
		Name = "Weekly Hiker",
		Description = "Walk 5,000 steps.",
		Type = "WalkSteps",
		Goal = 5000,
		Reward = { Type = "Studs", Amount = 500 },
		ProfessorMessage = "Great exploration this week!",
	},
	{
		Id = "weekly_walk_10000",
		Name = "Marathon Walker",
		Description = "Walk 10,000 steps.",
		Type = "WalkSteps",
		Goal = 10000,
		Reward = { Type = "Studs", Amount = 1000 },
		ProfessorMessage = "What dedication to exploring!",
	},
	{
		Id = "weekly_walk_20000",
		Name = "Grand Explorer",
		Description = "Walk 20,000 steps.",
		Type = "WalkSteps",
		Goal = 20000,
		Reward = { Type = "Item", ItemName = "Hyper Potion", Amount = 3 },
		ProfessorMessage = "You've covered amazing ground!",
	},
	
	-- Evolution Challenges (Weekly)
	{
		Id = "weekly_evolve_3",
		Name = "Evolution Enthusiast",
		Description = "Evolve 3 creatures.",
		Type = "EvolveCreature",
		Goal = 3,
		Reward = { Type = "Item", ItemName = "Rare Candy", Amount = 2 },
		ProfessorMessage = "Multiple evolutions, wonderful!",
	},
	{
		Id = "weekly_evolve_5",
		Name = "Evolution Expert",
		Description = "Evolve 5 creatures.",
		Type = "EvolveCreature",
		Goal = 5,
		Reward = { Type = "Item", ItemName = "Rare Candy", Amount = 3 },
		ProfessorMessage = "You truly understand evolution!",
	},
	
	-- Level Challenges (Weekly)
	{
		Id = "weekly_level_15",
		Name = "Power Training",
		Description = "Get a creature to level 15.",
		Type = "ReachLevel",
		Goal = 15,
		Reward = { Type = "Item", ItemName = "Super Potion", Amount = 5 },
		ProfessorMessage = "Your creature is growing strong!",
	},
	{
		Id = "weekly_level_25",
		Name = "Strength Builder",
		Description = "Get a creature to level 25.",
		Type = "ReachLevel",
		Goal = 25,
		Reward = { Type = "Item", ItemName = "Hyper Potion", Amount = 3 },
		ProfessorMessage = "Impressive training dedication!",
	},
	{
		Id = "weekly_level_35",
		Name = "Elite Training",
		Description = "Get a creature to level 35.",
		Type = "ReachLevel",
		Goal = 35,
		Reward = { Type = "Item", ItemName = "Max Potion", Amount = 2 },
		ProfessorMessage = "You're approaching elite status!",
	},
	
	-- Healing Challenges (Weekly)
	{
		Id = "weekly_heal_15",
		Name = "Team Doctor",
		Description = "Use potions to heal creatures 15 times.",
		Type = "HealCreatures",
		Goal = 15,
		Reward = { Type = "Item", ItemName = "Super Potion", Amount = 5 },
		ProfessorMessage = "Your team is well maintained!",
	},
	{
		Id = "weekly_heal_30",
		Name = "Master Healer",
		Description = "Use potions to heal creatures 30 times.",
		Type = "HealCreatures",
		Goal = 30,
		Reward = { Type = "Item", ItemName = "Hyper Potion", Amount = 3 },
		ProfessorMessage = "The best care for your creatures!",
	},
	
	-- Move Usage Challenges (Weekly)
	{
		Id = "weekly_moves_50",
		Name = "Battle Veteran",
		Description = "Use moves in battle 50 times.",
		Type = "UseMoves",
		Goal = 50,
		Reward = { Type = "Studs", Amount = 400 },
		ProfessorMessage = "Experienced in combat!",
	},
	{
		Id = "weekly_moves_100",
		Name = "Combat Specialist",
		Description = "Use moves in battle 100 times.",
		Type = "UseMoves",
		Goal = 100,
		Reward = { Type = "Studs", Amount = 800 },
		ProfessorMessage = "A true battle specialist!",
	},
	{
		Id = "weekly_moves_200",
		Name = "Legendary Combatant",
		Description = "Use moves in battle 200 times.",
		Type = "UseMoves",
		Goal = 200,
		Reward = { Type = "Item", ItemName = "Hyper Potion", Amount = 4 },
		ProfessorMessage = "Unmatched battle experience!",
	},
	
	-- Unique Type Capture (Weekly)
	{
		Id = "weekly_unique_types_4",
		Name = "Type Hunter",
		Description = "Capture creatures of 4 different types.",
		Type = "CaptureUniqueTypes",
		Goal = 4,
		Reward = { Type = "Item", ItemName = "Great Cube", Amount = 5 },
		ProfessorMessage = "Great type diversity!",
	},
	{
		Id = "weekly_unique_types_6",
		Name = "Type Collector",
		Description = "Capture creatures of 6 different types.",
		Type = "CaptureUniqueTypes",
		Goal = 6,
		Reward = { Type = "Item", ItemName = "Great Cube", Amount = 8 },
		ProfessorMessage = "Impressive type collection!",
	},
	{
		Id = "weekly_unique_types_8",
		Name = "Type Master",
		Description = "Capture creatures of 8 different types.",
		Type = "CaptureUniqueTypes",
		Goal = 8,
		Reward = { Type = "Item", ItemName = "Ultra Cube", Amount = 2 },
		ProfessorMessage = "You're a type master!",
	},
}

--============================================================================--
-- TIME CALCULATION FUNCTIONS
--============================================================================--

--- Get the current UTC timestamp
--- @return number Unix timestamp in seconds
function ChallengesConfig.GetCurrentUTCTime(): number
	return os.time(os.date("!*t") :: any)
end

--- Get the start of the current UTC day (00:00 UTC)
--- @return number Unix timestamp of current day start
function ChallengesConfig.GetDayStart(): number
	local utcTime = os.date("!*t")
	return os.time({
		year = utcTime.year,
		month = utcTime.month,
		day = utcTime.day,
		hour = 0,
		min = 0,
		sec = 0,
	})
end

--- Get the start of the current UTC week (Monday 00:00 UTC)
--- @return number Unix timestamp of current week start
function ChallengesConfig.GetWeekStart(): number
	local utcTime = os.date("!*t")
	-- Lua's wday: 1 = Sunday, 2 = Monday, ..., 7 = Saturday
	-- Convert to Monday-based: Monday = 0, Tuesday = 1, ..., Sunday = 6
	local daysSinceMonday = (utcTime.wday + 5) % 7
	
	return os.time({
		year = utcTime.year,
		month = utcTime.month,
		day = utcTime.day - daysSinceMonday,
		hour = 0,
		min = 0,
		sec = 0,
	})
end

--- Get seconds until next daily refresh (00:00 UTC tomorrow)
--- @return number Seconds until daily refresh
function ChallengesConfig.GetSecondsUntilDailyRefresh(): number
	local dayStart = ChallengesConfig.GetDayStart()
	local nextDayStart = dayStart + 86400 -- 24 hours in seconds
	return math.max(0, nextDayStart - ChallengesConfig.GetCurrentUTCTime())
end

--- Get seconds until next weekly refresh (Monday 00:00 UTC)
--- @return number Seconds until weekly refresh
function ChallengesConfig.GetSecondsUntilWeeklyRefresh(): number
	local weekStart = ChallengesConfig.GetWeekStart()
	local nextWeekStart = weekStart + 604800 -- 7 days in seconds
	return math.max(0, nextWeekStart - ChallengesConfig.GetCurrentUTCTime())
end

--- Get the unique seed for today (used for deterministic challenge selection)
--- @return number Day seed
function ChallengesConfig.GetDaySeed(): number
	local dayStart = ChallengesConfig.GetDayStart()
	-- Days since Unix epoch
	return math.floor(dayStart / 86400)
end

--- Get the unique seed for this week (used for deterministic challenge selection)
--- @return number Week seed
function ChallengesConfig.GetWeekSeed(): number
	local weekStart = ChallengesConfig.GetWeekStart()
	-- Weeks since Unix epoch
	return math.floor(weekStart / 604800)
end

--============================================================================--
-- DETERMINISTIC CHALLENGE SELECTION
-- Uses seeded pseudo-random selection to ensure all players get same challenges
--============================================================================--

--- Simple deterministic shuffle using seed
--- @param tbl table Array to shuffle
--- @param seed number Seed for randomization
--- @return table Shuffled copy of array
local function seededShuffle(tbl: { any }, seed: number): { any }
	local copy = table.clone(tbl)
	local rng = Random.new(seed)
	
	-- Fisher-Yates shuffle with seeded RNG
	for i = #copy, 2, -1 do
		local j = rng:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	
	return copy
end

--- Get the current daily challenges (same for all players)
--- @return Array of 3 daily challenges
function ChallengesConfig.GetCurrentDailyChallenges()
	local seed = ChallengesConfig.GetDaySeed()
	local shuffled = seededShuffle(ChallengesConfig.DailyChallenges, seed)
	
	local result = {}
	for i = 1, math.min(ChallengesConfig.DAILY_CHALLENGE_COUNT, #shuffled) do
		table.insert(result, shuffled[i])
	end
	
	return result
end

--- Get the current weekly challenges (same for all players)
--- @return Array of 6 weekly challenges
function ChallengesConfig.GetCurrentWeeklyChallenges()
	local seed = ChallengesConfig.GetWeekSeed()
	local shuffled = seededShuffle(ChallengesConfig.WeeklyChallenges, seed)
	
	local result = {}
	for i = 1, math.min(ChallengesConfig.WEEKLY_CHALLENGE_COUNT, #shuffled) do
		table.insert(result, shuffled[i])
	end
	
	return result
end

--============================================================================--
-- HELPER FUNCTIONS
--============================================================================--

--- Get challenge by ID from daily or weekly pools
--- @param id string Challenge ID
--- @return Challenge definition or nil
function ChallengesConfig.GetChallengeById(id: string)
	-- Check daily challenges
	for _, challenge in ipairs(ChallengesConfig.DailyChallenges) do
		if challenge.Id == id then
			return challenge
		end
	end
	
	-- Check weekly challenges
	for _, challenge in ipairs(ChallengesConfig.WeeklyChallenges) do
		if challenge.Id == id then
			return challenge
		end
	end
	
	return nil
end

--- Get all challenges matching a specific type from current active challenges
--- @param challengeType string Type to filter by
--- @return Matching challenges
function ChallengesConfig.GetActiveChallengesByType(challengeType: string)
	local results = {}
	
	-- Check current daily challenges
	for _, challenge in ipairs(ChallengesConfig.GetCurrentDailyChallenges()) do
		if challenge.Type == challengeType then
			table.insert(results, challenge)
		end
	end
	
	-- Check current weekly challenges
	for _, challenge in ipairs(ChallengesConfig.GetCurrentWeeklyChallenges()) do
		if challenge.Type == challengeType then
			table.insert(results, challenge)
		end
	end
	
	return results
end

--- Get all challenges of a type from the full pool (for progress tracking)
--- @param challengeType string Type to filter by
--- @return Matching challenges
function ChallengesConfig.GetChallengesByType(challengeType: string)
	local results = {}
	
	for _, challenge in ipairs(ChallengesConfig.DailyChallenges) do
		if challenge.Type == challengeType then
			table.insert(results, challenge)
		end
	end
	
	for _, challenge in ipairs(ChallengesConfig.WeeklyChallenges) do
		if challenge.Type == challengeType then
			table.insert(results, challenge)
		end
	end
	
	return results
end

--- Get formatted reward text for a challenge
--- @param challenge ChallengeDefinition Challenge to format
--- @return string Formatted reward text
function ChallengesConfig.GetRewardText(challenge: ChallengeDefinition): string
	if not challenge or not challenge.Reward then
		return "Unknown Reward"
	end
	
	local reward = challenge.Reward
	if reward.Type == "Item" then
		return string.format("Reward: %s x%d", reward.ItemName or "Item", reward.Amount or 1)
	elseif reward.Type == "Studs" then
		return string.format("Reward: %d Studs", reward.Amount or 0)
	end
	
	return "Unknown Reward"
end

--- Format seconds into human-readable time string
--- @param seconds number Seconds to format
--- @return string Formatted time (e.g., "5 Hours", "24 Minutes", "3 Days")
function ChallengesConfig.FormatTimeRemaining(seconds: number): string
	if seconds <= 0 then
		return "Refreshing..."
	end
	
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	
	if days >= 1 then
		if days == 1 then
			return "1 Day"
		else
			return string.format("%d Days", days)
		end
	elseif hours >= 1 then
		if hours == 1 then
			return "1 Hour"
		else
			return string.format("%d Hours", hours)
		end
	else
		if minutes <= 1 then
			return "1 Minute"
		else
			return string.format("%d Minutes", minutes)
		end
	end
end

--- Check if a challenge is in the daily pool
--- @param challengeId string Challenge ID to check
--- @return boolean True if daily challenge
function ChallengesConfig.IsDailyChallenge(challengeId: string): boolean
	for _, challenge in ipairs(ChallengesConfig.DailyChallenges) do
		if challenge.Id == challengeId then
			return true
		end
	end
	return false
end

--- Check if a challenge is in the weekly pool
--- @param challengeId string Challenge ID to check
--- @return boolean True if weekly challenge
function ChallengesConfig.IsWeeklyChallenge(challengeId: string): boolean
	for _, challenge in ipairs(ChallengesConfig.WeeklyChallenges) do
		if challenge.Id == challengeId then
			return true
		end
	end
	return false
end

return ChallengesConfig


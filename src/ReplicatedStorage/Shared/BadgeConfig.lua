--!strict
-- BadgeConfig: Shared configuration for badge images and data
-- Used by client modules to display badges

local BadgeConfig = {}

-- Badge image asset IDs
-- Index corresponds to badge number (1-8)
BadgeConfig.BadgeImages = {
	[1] = "rbxassetid://88980118006188",
	[2] = "rbxassetid://91666496900016",
	-- Badges 3-8 currently use rbxassetid://0 (placeholder)
	[3] = "rbxassetid://0",
	[4] = "rbxassetid://0",
	[5] = "rbxassetid://0",
	[6] = "rbxassetid://0",
	[7] = "rbxassetid://0",
	[8] = "rbxassetid://0",
}

-- Locked badge image (shown for next badge to earn)
BadgeConfig.LockedBadgeImage = "rbxassetid://99525585483457"

-- Maximum number of badges
BadgeConfig.MaxBadges = 8

return BadgeConfig


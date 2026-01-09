--!strict
--[[
	BoxBackgrounds.lua
	Shared module for box background image IDs and default background logic
	Used by Vault.lua and Trade.lua
]]

local BoxBackgrounds = {}

-- Predefined Box Background IDs (expandable)
local BOX_BACKGROUNDS: {number} = {
	140677672905926, -- CatchInc (default for Party)
	81042384701409,  -- BC's logo
	89197109127471,  -- Yellow studs
	122211658648741, -- Blue studs
	104351619158315, -- Red studs
	82088477616564,  -- Shiny (1)
}

-- Get default background ID for a box index (cycles through backgrounds)
function BoxBackgrounds.GetDefaultBackgroundForBox(index: number): string
	if #BOX_BACKGROUNDS == 0 then return "" end
	local i = math.max(1, ((index - 1) % #BOX_BACKGROUNDS) + 1)
	return tostring(BOX_BACKGROUNDS[i])
end

-- Get the default Party box background ID
function BoxBackgrounds.GetPartyBackground(): string
	return "140677672905926"
end

-- Get all available background IDs
function BoxBackgrounds.GetBackgrounds(): {number}
	return BOX_BACKGROUNDS
end

return BoxBackgrounds


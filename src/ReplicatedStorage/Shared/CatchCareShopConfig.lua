local Config = {}

export type ShopItem = {
	ItemName: string,
	Price: number,
	IconOverride: string?,
}

export type TierDefinition = {
	Tier: number,
	Items: {ShopItem},
}

export type LocationDefinition = {
	DisplayName: string,
	Tier: number,
}

local ITEMS_PER_PAGE = 5

local TIER_ITEMS: {[number]: TierDefinition} = {
	[1] = {
		Tier = 1,
		Items = {
			{ ItemName = "Apple", Price = 120 },
			{ ItemName = "Potion", Price = 200 },
			{ ItemName = "Capture Cube", Price = 175 },
			{ ItemName = "Static Chip", Price = 450 },
			{ ItemName = "Spike Band", Price = 650 },
			{ ItemName = "Sleep Mask", Price = 480 },
		},
	},
	[2] = {
		Tier = 2,
		Items = {
			{ ItemName = "Epic Potion", Price = 600 },
			{ ItemName = "Revive", Price = 1200 },
			{ ItemName = "Rot Cube", Price = 1400 },
			{ ItemName = "Stone Armor", Price = 900 },
			{ ItemName = "Focus Bandage", Price = 1500 },
			{ ItemName = "Crumbs", Price = 950 },
		},
	},
	[3] = {
		Tier = 3,
		Items = {
			{ ItemName = "Maximum Potion", Price = 1500 },
			{ ItemName = "Toxic Candy", Price = 1100 },
			{ ItemName = "Bright Core", Price = 1600 },
			{ ItemName = "Metal Fist", Price = 1650 },
			{ ItemName = "Fairy Dust", Price = 1650 },
			{ ItemName = "Echo Bell", Price = 1725 },
		},
	},
	[4] = {
		Tier = 4,
		Items = {
			{ ItemName = "Maximum Revive", Price = 2600 },
			{ ItemName = "Golden Apple", Price = 3200 },
			{ ItemName = "Rage Core", Price = 2200 },
			{ ItemName = "Inferno Seed", Price = 2800 },
			{ ItemName = "Tore Stone", Price = 3000 },
		},
	},
	[5] = {
		Tier = 5,
		Items = {
			{ ItemName = "Glitch Cube", Price = 3600 },
			{ ItemName = "Golden Apple", Price = 3200 },
			{ ItemName = "Maximum Revive", Price = 2600 },
			{ ItemName = "Bright Core", Price = 1600 },
			{ ItemName = "Echo Bell", Price = 1725 },
			{ ItemName = "Rot Cube", Price = 1400 },
		},
	},
}

local LOCATION_TIERS: {[string]: LocationDefinition} = {
	["Chunk3"] = { DisplayName = "Cresamore Town", Tier = 1 },
	["Chunk5"] = { DisplayName = "Asterden", Tier = 2 },
}

Config.ItemsPerPage = ITEMS_PER_PAGE
Config.Tiers = TIER_ITEMS
Config.Locations = LOCATION_TIERS
Config.DefaultTier = 1
Config.DefaultLocationName = "CatchCare"

return Config


local Config = {
	SHINY_CHANCE = 100,
	ENCOUNTER_BASE_CHANCE = 60,
	XP_MULTIPLIER = 2.67,
	-- Place IDs for teleportation
	MAIN_GAME_PLACE_ID = 71897468985259,
	BATTLE_HUB_PLACE_ID = 118790003195513,
	TRADE_HUB_PLACE_ID = 87280409692047,
	REQUIREMENT_FAILURE_PLACE_ID = 335351731,
	-- Admin system configuration
	ADMIN_GROUP_ID = 335351731,
	ADMIN_RANK = 255, -- Minimum rank for admin (typically 255 for owners)
	MOD_RANK = 100, -- Minimum rank for mod (adjust as needed)
	-- Battle system configuration
	WILD_ESCAPE_FAILURE_ENABLED = false, -- When false, wild battles always allow escape (unless blocked by trapping abilities)
	ENEMY_DAMAGE_MULT = 1.0, -- Set <1.0 for easier battles; Pokémon-faithful default is 1.0
	BATTLE_SANITY_CHECKS = false, -- When true, runs lightweight Gen 9 battle sanity checks at server startup
}

return Config
--!strict
--[[
	Battle Module
	Central export for all battle-related server modules
	Provides clean API for battle system functionality
]]

local BattleStateManager = require(script.BattleStateManager)
local BattleValidator = require(script.BattleValidator)
local DamageCalculator = require(script.DamageCalculator)
local AIController = require(script.AIController)
local XPManager = require(script.XPManager)
local Obedience = require(script.Obedience)

return {
	-- State Management
	StateManager = BattleStateManager,
	
	-- Validation
	Validator = BattleValidator,
	
	-- Combat
	DamageCalculator = DamageCalculator,
	
	-- AI
	AIController = AIController,
	
	-- Progression
	XPManager = XPManager,
	
	-- Obedience
	Obedience = Obedience,
}

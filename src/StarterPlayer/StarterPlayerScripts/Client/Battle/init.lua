--!strict
--[[
	Battle Module (Client)
	Central export for all battle-related client modules
	Provides clean API for client battle system functionality
]]

local ClientBattleState = require(script.ClientBattleState)
local MessageQueue = require(script.MessageQueue)
local AnimationController = require(script.AnimationController)
local UIController = require(script.UIController)
local CameraController = require(script.CameraController)
local BattleSceneManager = require(script.BattleSceneManager)
local ActionHandler = require(script.ActionHandler)
local BattleUIManager = require(script.BattleUIManager)
local CombatEffects = require(script.CombatEffects)
local StepProcessor = require(script.StepProcessor)
local PartyIntegration = require(script.PartyIntegration)
local SwitchHandler = require(script.SwitchHandler)
local PostBattleHandler = require(script.PostBattleHandler)
local BattleOptionsManager = require(script.BattleOptionsManager)
local BattleMessageGenerator = require(script.BattleMessageGenerator)

return {
	-- State Management
	StateManager = ClientBattleState,
	
	-- Message System
	MessageQueue = MessageQueue,
	
	-- Animation
	AnimationController = AnimationController,
	
	-- UI
	UIController = UIController,
	UIManager = BattleUIManager,
	
	-- Camera
	CameraController = CameraController,
	
	-- Scene Management
	SceneManager = BattleSceneManager,
	
	-- Action Handling
	ActionHandler = ActionHandler,
	
	-- Combat Effects
	CombatEffects = CombatEffects,
	
	-- Step Processing
	StepProcessor = StepProcessor,
	
	-- Party Integration
	PartyIntegration = PartyIntegration,
	
	-- Switch Handling
	SwitchHandler = SwitchHandler,
	
	-- Post-Battle
	PostBattleHandler = PostBattleHandler,
	
	-- Battle Options
	BattleOptionsManager = BattleOptionsManager,
	
	-- Message Generation
	MessageGenerator = BattleMessageGenerator,
}

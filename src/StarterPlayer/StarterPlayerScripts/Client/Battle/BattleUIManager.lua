--!strict
--[[
	BattleUIManager.lua
	Manages battle UI button connections and interactions
	Handles all UI event wiring and state management
]]

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local BattleUI = GameUI:WaitForChild("BattleUI")

local BattleUIManager = {}
BattleUIManager.__index = BattleUIManager

export type BattleUIManagerType = typeof(BattleUIManager.new())
export type ButtonCallback = () -> ()

--[[
	Creates a new battle UI manager instance
	@param actionHandler The action handler reference
	@param partyIntegration The party integration reference (optional)
	@return BattleUIManager
]]
function BattleUIManager.new(actionHandler: any, partyIntegration: any?): any
	local self = setmetatable({}, BattleUIManager)
	
	self._actionHandler = actionHandler
	self._partyIntegration = partyIntegration
	self._battleUI = BattleUI
	self._battleOptions = BattleUI:WaitForChild("BattleOptions")
	self._moveOptions = BattleUI:WaitForChild("MoveOptions")
	
	-- Button references
	self._fightButton = self._battleOptions:FindFirstChild("Fight")
	self._creaturesButton = self._battleOptions:FindFirstChild("Creatures")
	self._bagButton = self._battleOptions:FindFirstChild("Bag")
	self._runButton = self._battleOptions:FindFirstChild("Run")
	
	-- Move buttons
	self._moveButtons = {}
	for i = 1, 4 do
		local moveButton = self._moveOptions:FindFirstChild("Move" .. i)
		if moveButton then
			self._moveButtons[i] = moveButton
		end
	end
	
	-- Connection storage
	self._connections = {}
	
	return self
end

--[[
	Connects all battle UI buttons
]]
function BattleUIManager:ConnectButtons()
    -- Legacy wiring disabled; BattleOptionsManager handles interactions
    self:_disconnectAll()
    print("[BattleUIManager] Button wiring disabled (OptionsManager in use)")
end

--[[
	Updates move buttons with creature's moves
	@param creature The creature data
]]
function BattleUIManager:UpdateMoveButtons(creature: any)
	if not creature then
		return
	end
	
	local MovesModule = require(game:GetService("ReplicatedStorage").Shared.Moves)
	local moves = creature.CurrentMoves or creature.Moves or {}
	
	for i = 1, 4 do
		local button = self._moveButtons[i]
		if button then
			local move = moves[i]
			local moveName: string? = nil
			local moveDef: any = nil
			if typeof(move) == "string" then
				moveName = move
				moveDef = MovesModule[moveName]
			elseif typeof(move) == "table" then
				-- Legacy: if table points to move def, find its key
				for k, v in pairs(MovesModule) do
					if v == move then
						moveName = k
						moveDef = v
						break
					end
				end
			end
			
			if moveName and moveDef then
				-- Update button text
				local nameLabel = button:FindFirstChild("MoveName")
				if nameLabel and nameLabel:IsA("TextLabel") then
					nameLabel.Text = moveName
				end
				
				-- Update type
				local typeLabel = button:FindFirstChild("Type")
				if typeLabel and typeLabel:IsA("TextLabel") then
					typeLabel.Text = (moveDef.Type and next(MovesModule) and (function()
						-- Attempt to find type name by matching table identity back to Types
						local Types = require(game:GetService("ReplicatedStorage").Shared.Types)
						for tName, tDef in pairs(Types) do
							if tDef == moveDef.Type then return tName end
						end
						return "Normal"
					end)()) or "Normal"
				end
				
				-- Update PP (if implemented)
				local ppLabel = button:FindFirstChild("PP")
				if ppLabel and ppLabel:IsA("TextLabel") then
					local currentPP = move.CurrentPP or move.PP or 0
					local maxPP = move.PP or 0
					ppLabel.Text = string.format("PP: %d/%d", currentPP, maxPP)
				end
				
				button.Visible = true
				button.Active = true
			else
				button.Visible = false
				button.Active = false
			end
		end
	end
end

--[[
	Shows battle options
]]
function BattleUIManager:ShowBattleOptions()
	self._battleOptions.Visible = true
	self._moveOptions.Visible = false
	
	-- Enable buttons
	for _, button in ipairs({self._fightButton, self._creaturesButton, self._bagButton, self._runButton}) do
		if button then
			button.Active = true
		end
	end
end

--[[
	Shows move options
]]
function BattleUIManager:ShowMoveOptions()
	self._battleOptions.Visible = false
	self._moveOptions.Visible = true
	
	-- Enable move buttons
	for _, button in pairs(self._moveButtons) do
		if button and button.Visible then
			button.Active = true
		end
	end
end

--[[
	Hides all battle UI
]]
function BattleUIManager:HideAll()
	self._battleOptions.Visible = false
	self._moveOptions.Visible = false
end

--[[
	Disconnects all button connections
]]
function BattleUIManager:Cleanup()
	self:_disconnectAll()
end

--[[
	Internal: Fight button clicked
]]
function BattleUIManager:_onFightClicked() end

--[[
	Internal: Creatures button clicked
]]
function BattleUIManager:_onCreaturesClicked() end

--[[
	Internal: Bag button clicked
]]
function BattleUIManager:_onBagClicked() end

--[[
	Internal: Run button clicked
]]
function BattleUIManager:_onRunClicked() end

--[[
	Internal: Move button clicked
	@param moveIndex The move index
]]
function BattleUIManager:_onMoveClicked(moveIndex: number) end

--[[
	Internal: Disconnects all connections
]]
function BattleUIManager:_disconnectAll()
	for _, connection in ipairs(self._connections) do
		if connection then
			connection:Disconnect()
		end
	end
	self._connections = {}
end

return BattleUIManager

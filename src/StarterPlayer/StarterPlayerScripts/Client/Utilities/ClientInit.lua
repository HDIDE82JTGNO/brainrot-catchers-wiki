--!strict
--[[
	ClientInit.lua
	Initializes client-side battle system
	This script should be required early in the client initialization
]]

local Players = game:GetService("Players")

-- Defer requiring BattleSystemV2 until GameUI and its children exist to avoid startup deadlocks
local function initBattleSystem()
    local player = Players.LocalPlayer
    local pg = player:WaitForChild("PlayerGui")
    local gameUi = pg:WaitForChild("GameUI")
    -- Ensure required frames exist before requiring modules that depend on them
    gameUi:WaitForChild("TopBar")
    gameUi:WaitForChild("BattleUI")

    local BattleSystemV2 = require(script.Parent.BattleSystemV2)
    local battleSystem = BattleSystemV2.new()
    battleSystem:Initialize()
    print("[ClientInit] BattleSystemV2 initialized and ready")
    return battleSystem
end

return initBattleSystem()
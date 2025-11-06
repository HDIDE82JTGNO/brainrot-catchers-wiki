local AutoSave = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Events = ReplicatedStorage:WaitForChild("Events")

local CharacterFunctions = require(script.Parent:WaitForChild("CharacterFunctions"))
local Say = require(script.Parent:WaitForChild("Say"))
local ClientData = require(script.Parent.Parent.Plugins:WaitForChild("ClientData"))

local MIN_INTERVAL_SEC = 45 -- don't try more often than this
local lastAttemptAt = 0

local function isNpcChatActive(): boolean
    local ok, active = pcall(function()
        return Say and Say.IsActive and Say:IsActive() or false
    end)
    return ok and active == true
end

local function isInBattle(): boolean
    local pd
    pcall(function() pd = ClientData:Get() end)
    return (pd and pd.InBattle == true) or false
end

local function isMovementEnabled(): boolean
    local ok, canMove = pcall(function()
        return CharacterFunctions and CharacterFunctions.CheckCanMove and CharacterFunctions:CheckCanMove() or true
    end)
    return ok and (canMove == true)
end

function AutoSave:CanSaveNow(): boolean
    -- Conditions: movement enabled AND not in NPC chat AND not in battle
    if not isMovementEnabled() then return false end
    if isNpcChatActive() then return false end
    if isInBattle() then return false end
    return true
end

function AutoSave:_tick()
    local now = os.clock()
    if (now - lastAttemptAt) < MIN_INTERVAL_SEC then return end
    lastAttemptAt = now
    -- Respect player setting
    local pd
    pcall(function() pd = ClientData:Get() end)
    local enabled = (pd and pd.Settings and pd.Settings.AutoSave) == true
    if not enabled then return end
    if not self:CanSaveNow() then return end
    -- Fire manual save to server (server rate limits as extra protection)
    Events.Request:InvokeServer({"ManualSave"})
end

function AutoSave:Start()
    if self._conn then return end
    self._conn = RunService.Heartbeat:Connect(function()
        self:_tick()
    end)
end

function AutoSave:Stop()
    if self._conn then self._conn:Disconnect() self._conn = nil end
end

return AutoSave



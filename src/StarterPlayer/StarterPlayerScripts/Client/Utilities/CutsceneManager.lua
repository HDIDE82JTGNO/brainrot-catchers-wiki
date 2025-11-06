-- CutsceneManager.lua
-- Modular, typed cutscene system with event gating and UI/input suppression

local PlayersService = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = require(script.Parent.Parent:WaitForChild("UI"))
local CharacterFunctions = require(script.Parent:WaitForChild("CharacterFunctions"))
local CutsceneRegistry = require(script.Parent:WaitForChild("CutsceneRegistry"))
local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

export type CutsceneFn = (ctx: any) -> boolean

local CutsceneManager = {}
CutsceneManager.__index = CutsceneManager

local _registry: {[string]: CutsceneFn} = {}
local _running: {[string]: boolean} = {}

-- Handle object passed into cutscenes to allow async completion signaling
export type CutsceneHandle = {
    End: (self: any) -> (),
    IsEnded: (self: any) -> boolean,
    WaitEnd: (self: any) -> (),
}

local CutsceneHandle = {}
CutsceneHandle.__index = CutsceneHandle

function CutsceneHandle.new(name: string)
    local self = setmetatable({}, CutsceneHandle)
    self._name = name
    self._ended = false
    self._endedEvent = Instance.new("BindableEvent")
    return self
end

function CutsceneHandle:End(): ()
    if self._ended == true then return end
    self._ended = true
    self._endedEvent:Fire()
end

function CutsceneHandle:IsEnded(): boolean
    return self._ended == true
end

function CutsceneHandle:WaitEnd(): ()
    if self._ended == true then return end
    self._endedEvent.Event:Wait()
end

local function startContext(cutsceneName: string): ()
	_running[cutsceneName] = true
	UI.TopBar:SetSuppressed(true)
	UI.TopBar:Hide()
	-- Register cutscene as active
	CutsceneRegistry:Start(cutsceneName)
	CharacterFunctions:CanMove(false)
end

local function endContext(cutsceneName: string): ()
	_running[cutsceneName] = false
	pcall(function()
		UI.TopBar:SetSuppressed(false)
		UI.TopBar:Show()
	end)
	-- Re-enable movement at cutscene end; if any module-level suppression is active, this will be ignored
	CharacterFunctions:CanMove(true)
	-- Unregister cutscene
	CutsceneRegistry:End(cutsceneName)
    -- Belt-and-suspenders: ensure TopBar restoration after UI settles
    task.defer(function()
        pcall(function()
            UI.TopBar:SetSuppressed(false)
            UI.TopBar:Show()
        end)
    end)
end

function CutsceneManager:Register(name: string, fn: CutsceneFn): ()
	_registry[name] = fn
	DBG:print("[CutsceneManager] Register cutscene:", name)
end

function CutsceneManager:IsRunning(name: string): boolean
	return _running[name] == true
end

function CutsceneManager:Run(name: string, ctx: any): boolean
	if _running[name] then return false end
	local fn = _registry[name]
	if not fn then return false end
	DBG:print("[CutsceneManager] Run cutscene:", name)
	startContext(name)
    local ok = false
    local handle = CutsceneHandle.new(name)
    local success, result = pcall(function()
        return fn(ctx, handle)
    end)
    local endedImmediately = (success and result == true) or handle:IsEnded()
    if success and endedImmediately then
        ok = true
    elseif success and not endedImmediately then
        -- Wait for module to explicitly end
        handle:WaitEnd()
        ok = true
    else
        DBG:print("[CutsceneManager] Error while running cutscene:", name, result)
    end
	endContext(name)
	DBG:print("[CutsceneManager] Cutscene finished:", name)
    -- Ensure TopBar is visible after cutscene teardown
    pcall(function()
        UI.TopBar:SetSuppressed(false)
        UI.TopBar:Show()
    end)
    -- Cleanup handle event
    pcall(function()
        if handle and handle._endedEvent then handle._endedEvent:Destroy() end
    end)
	return ok
end

-- Gate by client event flag; set to true on success
function CutsceneManager:RunOnceEvent(eventName: string, name: string, ctx: any): ()
	local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
	local Events = ReplicatedStorage:WaitForChild("Events")
	local data = ClientData:Get()
	if not data or not data.Events then return end
	local state = data.Events[eventName]
	DBG:print("[CutsceneManager] Event state before run:", eventName, tostring(state))
	if state then return end
	DBG:print("[CutsceneManager] RunOnceEvent gating:", eventName, "->", name)
	local ok = self:Run(name, ctx)
	if ok then
		pcall(function()
			Events.Request:InvokeServer({"SetEvent", eventName, true})
		end)
	else
		DBG:print("[CutsceneManager] Not marking event as complete due to failure:", eventName)
	end
end

-- Lazy require a cutscene module by ModuleScript name under Client/Cutscenes and register
function CutsceneManager:RegisterModule(cutsceneName: string, moduleName: string): boolean
	local folder = script.Parent.Parent:FindFirstChild("Cutscenes")
	if not folder then return false end
	local ok, mod = pcall(function()
		return require(folder:WaitForChild(moduleName))
	end)
	if ok and type(mod) == "function" then
		self:Register(cutsceneName, mod)
		return true
	end
	return false
end

-- Convenience: gate + lazy register + run once
function CutsceneManager:RunOnceModule(eventName: string, cutsceneName: string, moduleName: string, ctx: any): ()
	local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
	local data = ClientData:Get()
	if not data or not data.Events then return end
	if data.Events[eventName] == true then return end
	self:RegisterModule(cutsceneName, moduleName)
	self:RunOnceEvent(eventName, cutsceneName, ctx)
end

return CutsceneManager



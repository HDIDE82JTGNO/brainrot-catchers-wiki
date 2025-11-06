local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LOS = {}

local ActiveTriggers = {}
local TriggeredOnce = {}
local LastTriggeredAt = {}
local CutsceneRegistry = require(script.Parent:WaitForChild("CutsceneRegistry"))
local EncounterZone = require(script.Parent:WaitForChild("EncounterZone"))
local MusicManager = require(script.Parent:WaitForChild("MusicManager"))

-- Client-side grace window to suppress LOS right after spawn/restore
local GraceUntil: number? = nil
function LOS:SetGraceUntil(t: number)
    GraceUntil = t
end

local function showExclamation(npcModel: Model)
	if not npcModel or not npcModel:IsA("Model") then return end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return end
	local template = assets:FindFirstChild("Exclamation")
	if not template then return end
	local head = npcModel:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		head = npcModel:FindFirstChild("HumanoidRootPart")
	end
	if not (head and head:IsA("BasePart")) then
		head = npcModel.PrimaryPart
	end
	if not (head and head:IsA("BasePart")) then return end
	local clone = template:Clone()
	clone.Parent = head
	clone:FindFirstChildOfClass("ParticleEmitter"):Emit(1)
	task.delay(1, function()
		pcall(function()
			if clone then clone:Destroy() end
		end)
	end)
end

local function getPlayerPosition()
	local player = Players.LocalPlayer
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or nil
end

local function isWithinDistance(a: Vector3, b: Vector3, maxDist: number)
	return (a - b).Magnitude <= maxDist
end

local function isInLineOfSight(npcRoot: BasePart, playerPos: Vector3, fovDeg: number)
	local npcLook = npcRoot.CFrame.LookVector
	local toPlayer = (playerPos - npcRoot.Position).Unit
	local dot = npcLook:Dot(toPlayer)
	local angle = math.deg(math.acos(math.clamp(dot, -1, 1)))
	return angle <= (fovDeg * 0.5)
end

function LOS:SetupOnceTrigger(npcModel: Model, config)
    -- config: {MaxDistance, FOV, OnTrigger, UniqueKey}
	if not npcModel or not config or not config.OnTrigger then return end
	local hrp = npcModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local key = config.UniqueKey or (npcModel:GetFullName() .. "::LOS")
	if TriggeredOnce[key] then return end

	local conn
	conn = RunService.Heartbeat:Connect(function()
		local playerPos = getPlayerPosition()
		if not playerPos then return end
		if config.MaxDistance and not isWithinDistance(playerPos, hrp.Position, config.MaxDistance) then return end
		if config.FOV and not isInLineOfSight(hrp, playerPos, config.FOV) then return end
        -- Gate by cutscene/encounter state
        if CutsceneRegistry and CutsceneRegistry.IsAnyActive and CutsceneRegistry:IsAnyActive() then return end
        if EncounterZone and EncounterZone.IsInEncounter and EncounterZone:IsInEncounter() then return end
        if GraceUntil and os.clock() < GraceUntil then return end
        -- Visual exclamation
        showExclamation(npcModel)
        -- Trainer LOS intro sting only if this NPC is a trainer (has Dialogue.LineOfSight == true)
        local dialogueModule = npcModel:FindFirstChild("Dialogue")
        if dialogueModule then
            local ok, dlg = pcall(require, dialogueModule)
            if ok and type(dlg) == "table" and dlg.LineOfSight == true then
                -- Also raise cinematic black bars right when the sting plays
                local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
                local gameUI = pg and pg:FindFirstChild("GameUI")
                local blackBars = gameUI and gameUI:FindFirstChild("BlackBars")
                if blackBars and blackBars:IsA("ImageLabel") then
                    local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
                    UIFunctions:BlackBars(true, blackBars)
                end
				TweenService:Create(workspace.CurrentCamera, TweenInfo.new(0.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out), {FieldOfView = 60}):Play()
                MusicManager:PlayTrainerIntro()
            end
        end
        -- Fire once
		TriggeredOnce[key] = true
		if conn then conn:Disconnect() end
        -- Pass both the model and its HRP for convenience; extra args are ignored by older handlers
        config.OnTrigger(npcModel, hrp)
	end)

	ActiveTriggers[npcModel] = conn
end

--[=[
	Sets up a re-arming LOS trigger that can fire multiple times until a stop condition is met.
	Intended for trainers: it re-triggers after a loss, and stops permanently once defeated.

	config: {
		MaxDistance: number?,
		FOV: number?,
		OnTrigger: (npcModel: Model, npcHRP: BasePart?) -> (),
		UniqueKey: string?,
		CooldownSeconds: number?,
		ShouldStop: (() -> boolean)?, -- return true to stop monitoring (e.g., trainer defeated)
	}
]=]
function LOS:SetupRearmingTrigger(npcModel: Model, config)
	if not npcModel or not config or not config.OnTrigger then return end
	local hrp = npcModel:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local key = config.UniqueKey or (npcModel:GetFullName() .. "::LOS_REARM")
	local cooldown = (type(config.CooldownSeconds) == "number" and config.CooldownSeconds >= 0) and config.CooldownSeconds or 2

	local conn
	conn = RunService.Heartbeat:Connect(function()
        -- Optional permanent stop
		if typeof(config.ShouldStop) == "function" then
			local ok, stop = pcall(config.ShouldStop)
			if ok and stop == true then
				if conn then conn:Disconnect() end
				ActiveTriggers[npcModel] = nil
				return
			end
		end

		local playerPos = getPlayerPosition()
		if not playerPos then return end
		if config.MaxDistance and not isWithinDistance(playerPos, hrp.Position, config.MaxDistance) then return end
		if config.FOV and not isInLineOfSight(hrp, playerPos, config.FOV) then return end

        -- Global gating: cutscene and active encounter should block LOS triggers
        if CutsceneRegistry and CutsceneRegistry.IsAnyActive and CutsceneRegistry:IsAnyActive() then return end
        if EncounterZone and EncounterZone.IsInEncounter and EncounterZone:IsInEncounter() then return end
        if GraceUntil and os.clock() < GraceUntil then return end

        -- Cooldown guard to avoid rapid retriggers
		local last = LastTriggeredAt[key]
		if last and (os.clock() - last) < cooldown then
			return
		end

        LastTriggeredAt[key] = os.clock()
        -- Visual exclamation
        showExclamation(npcModel)
        -- Trainer LOS intro sting only if this NPC is a trainer (has Dialogue.LineOfSight == true)
        local dialogueModule = npcModel:FindFirstChild("Dialogue")
        if dialogueModule then
            local ok, dlg = pcall(require, dialogueModule)
            if ok and type(dlg) == "table" and dlg.LineOfSight == true then
                -- Also raise cinematic black bars right when the sting plays
                local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
                local gameUI = pg and pg:FindFirstChild("GameUI")
                local blackBars = gameUI and gameUI:FindFirstChild("BlackBars")
                if blackBars and blackBars:IsA("ImageLabel") then
                    local UIFunctions = require(script.Parent.Parent.UI.UIFunctions)
                    UIFunctions:BlackBars(true, blackBars)
                end
                MusicManager:PlayTrainerIntro()
            end
        end
		config.OnTrigger(npcModel, hrp)
	end)

	ActiveTriggers[npcModel] = conn
end

function LOS:Clear(npcModel: Model)
	local conn = ActiveTriggers[npcModel]
	if conn then conn:Disconnect() end
	ActiveTriggers[npcModel] = nil
end

return LOS



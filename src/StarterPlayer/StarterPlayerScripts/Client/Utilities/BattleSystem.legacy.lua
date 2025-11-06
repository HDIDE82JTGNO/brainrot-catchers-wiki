--[[

local BattleSystem = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))
local Events = ReplicatedStorage:WaitForChild("Events")
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local UI = require(script.Parent.Parent.UI)
local UIFunctions = require(script.Parent.Parent.UI:WaitForChild("UIFunctions"))
local MusicManager = require(script.Parent.MusicManager)
local HologramSpawnEffect = require(script.Parent.HologramSpawnEffect)

--// Battle System Modules (Refactored - available for future use)
-- local Battle = require(script.Parent.Parent.Battle)
-- local ClientBattleState = Battle.StateManager
-- local MessageQueue = Battle.MessageQueue
-- local AnimationController = Battle.AnimationController
-- local UIController = Battle.UIController

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local BattleUI = GameUI:WaitForChild("BattleUI")

-- Battle state
local CurrentBattle = nil
local BattleScene = nil
local PlayerCreatureModel = nil
local FoeCreatureModel = nil
local Camera = Workspace.CurrentCamera
local PlayerIdleTrack = nil
local FoeIdleTrack = nil
local ActiveCameraTween = nil
local FoeFaintedThisTurn = false
local FoeFaintedAnnounced = false
local PlayerFaintedAnnounced = false
local UITransitionInProgress = false
local ActiveBattleOptionsTween = nil
local ActiveMoveOptionsTween = nil
local PlayerFaintTweened = false
local FoeFaintTweened = false
local LocallyFaintedSlots = {}
local YouUIPosition = nil
local FoeUIPosition = nil

-- Camera cycle state (Shield-style)
local CameraCycle = {
    running = false,
    thread = nil,
    tweens = {},
    version = 0,
}

-- UI Animation functions
local function slideUIOut(uiFrame, direction)
	if not uiFrame then return end
	
	local originalPosition = uiFrame.Position
	-- Use a fixed large value instead of AbsoluteSize to ensure it goes off screen
	local screenSize = 1000
	local targetX
	if direction == "left" then
		targetX = -screenSize
	elseif direction == "right" then
		targetX = screenSize
	else
		DBG:warn("Invalid direction for slideUIOut:", direction)
		return
	end
	
	DBG:print("Sliding UI", uiFrame.Name, "to", direction, "targetX:", targetX)
	
	local slideTween = TweenService:Create(uiFrame, 
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), 
		{Position = UDim2.new(0, targetX, originalPosition.Y.Scale, originalPosition.Y.Offset)}
	)
	slideTween:Play()
	return slideTween
end

local function slideUIIn(uiFrame, originalPosition)
	if not uiFrame then return end
	
	local slideTween = TweenService:Create(uiFrame, 
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), 
		{Position = originalPosition}
	)
	slideTween:Play()
	return slideTween
end

-- Tween a Model's scale from startScale to endScale over tweenInfo
local function tweenScale(startScale: number, endScale: number, tweenInfo: TweenInfo, model: Model)
	-- Safety check: ensure model exists and is valid
	if not model or not model.Parent then
		DBG:warn("tweenScale: Model is nil or has no parent, skipping tween")
		return
	end
	
	local elapsed = 0
	local scale = 0
	local tweenConnection

	local function onStep(deltaTime: number)
		-- Safety check: ensure model still exists during tween
		if not model or not model.Parent then
			DBG:warn("tweenScale: Model destroyed during tween, disconnecting")
			tweenConnection:Disconnect()
			return
		end
		
		elapsed = math.min(elapsed + deltaTime, tweenInfo.Time)

		local alpha = TweenService:GetValue(elapsed / tweenInfo.Time, tweenInfo.EasingStyle, tweenInfo.EasingDirection)

		scale = startScale + alpha * (endScale - startScale)

		pcall(function()
			model:ScaleTo(scale)
		end)

		if elapsed >= tweenInfo.Time then
			tweenConnection:Disconnect()
			-- Cleanup: destroy the model once the faint scale tween completes
			task.delay(0.1, function() -- Small delay to ensure tween is complete
				pcall(function()
					if model and model.Parent then
						model:Destroy()
					end
				end)
			end)
		end
	end

	tweenConnection = RunService.Heartbeat:Connect(onStep)
end

-- Level UI System (Client-side display only)
local function calculateXPForLevel(level)
    -- Pokémon-style XP formula: XP = level^3 * growth_rate
    -- Using "Medium Fast" growth rate (same as most starters)
    return math.floor(level * level * level)
end

local function calculateXPProgress(creature)
    if not creature or not creature.Level then
        return 0, 100, 0 -- currentXP, neededXP, progress (0-1)
    end
    
    local currentLevel = creature.Level
    -- Use XPProgress (0-100) instead of absolute XP
    local xpProgress = creature.XPProgress or 0 -- 0-100 scale
    
    -- Clamp to valid range
    xpProgress = math.clamp(xpProgress, 0, 100)
    
    local progress = xpProgress / 100 -- Convert to 0-1 scale
    
    return xpProgress, 100, progress
end

local function updateLevelUI(creature, shouldTween)
    DBG:print("=== UPDATE LEVEL UI DEBUG ===")
    DBG:print("Creature:", creature and creature.Name or "nil")
    DBG:print("Should tween:", shouldTween)
    DBG:print("YouUI exists:", YouUI ~= nil)
    
    if not creature then
        DBG:warn("updateLevelUI: No creature provided")
        return
    end
    
    -- Ensure we have the UI references
    if not YouUI then
        DBG:warn("updateLevelUI: YouUI not found, trying to get it from BattleUI")
        DBG:print("BattleUI exists:", BattleUI ~= nil)
        if BattleUI then
            DBG:print("BattleUI children:")
            for _, child in ipairs(BattleUI:GetChildren()) do
                DBG:print("  -", child.Name, "(" .. child.ClassName .. ")")
            end
            -- Try to get YouUI from BattleUI
            YouUI = BattleUI:FindFirstChild("You")
            DBG:print("YouUI found after retry:", YouUI ~= nil)
        end
        if not YouUI then
            DBG:warn("updateLevelUI: Still no YouUI found, cannot update level UI")
            return
        end
    end
    
    -- Ensure UI elements exist before proceeding
    local LvProgress = YouUI:FindFirstChild("LvProgress")
    local LvBackdrop = YouUI:FindFirstChild("LvBackdrop")
    
    if not LvProgress or not LvBackdrop then
        DBG:warn("updateLevelUI: Level UI elements not found - LvProgress:", LvProgress ~= nil, "LvBackdrop:", LvBackdrop ~= nil)
        return
    end
    
    DBG:print("LvProgress found:", LvProgress ~= nil)
    DBG:print("LvBackdrop found:", LvBackdrop ~= nil)
    
    local currentLevel = creature.Level or 1
    local nextLevel = currentLevel + 1
    
    -- Initialize XP data if missing (client-side fallback)
    if not creature.XPProgress then
        creature.XPProgress = 0
        DBG:print("Client-side XP initialization: Set XPProgress to 0 for", creature.Name)
    end
    
    local currentXP, neededXP, progress = calculateXPProgress(creature)
    
    DBG:print("Creature data - Level:", currentLevel, "XPProgress:", creature.XPProgress)
    DBG:print("XP Progress - Current:", currentXP, "Needed:", neededXP, "Progress:", progress)
    
    -- Update level text
    local CurrentLevelLabel = LvBackdrop:FindFirstChild("CurrentLevel")
    local NextLevelLabel = LvBackdrop:FindFirstChild("NextLevel")
    
    DBG:print("CurrentLevelLabel found:", CurrentLevelLabel ~= nil)
    DBG:print("NextLevelLabel found:", NextLevelLabel ~= nil)
    
    if CurrentLevelLabel then
        CurrentLevelLabel.Text = "Lv. " .. tostring(currentLevel)
        DBG:print("Set CurrentLevel text to:", CurrentLevelLabel.Text)
    else
        DBG:warn("CurrentLevelLabel not found in LvBackdrop")
    end
    
    if NextLevelLabel then
        NextLevelLabel.Text = "Lv. " .. tostring(nextLevel)
        DBG:print("Set NextLevel text to:", NextLevelLabel.Text)
    else
        DBG:warn("NextLevelLabel not found in LvBackdrop")
    end
    
    -- Update progress bar size
    -- Size format: {progress, 0}, {0.22, 0}
    -- When max XP: {1, 0}, {0.22, 0}
    -- When 0 XP: {0, 0}, {0.22, 0}
    local newSize = UDim2.new(progress, 0, 0.22, 0)
    local currentSize = LvProgress.Size
    
    -- Only tween if the size actually changed AND shouldTween is true
    if currentSize.X.Scale ~= newSize.X.Scale and shouldTween then
        DBG:print("Tweening LvProgress from", currentSize.X.Scale, "to", newSize.X.Scale)
        
        -- Create tween info for smooth animation
        local tweenInfo = TweenInfo.new(
            0.5, -- Duration
            Enum.EasingStyle.Quad, -- Easing style
            Enum.EasingDirection.Out, -- Easing direction
            0, -- Repeat count
            false, -- Reverses
            0 -- Delay
        )
        
        -- Create and play the tween
        local tween = game:GetService("TweenService"):Create(LvProgress, tweenInfo, {Size = newSize})
        tween:Play()
        
        -- Wait for tween to complete
        tween.Completed:Connect(function()
            DBG:print("LvProgress tween completed")
        end)
    else
        -- No change needed or shouldTween is false, just set directly
        LvProgress.Size = newSize
        if shouldTween then
            DBG:print("Set LvProgress size to:", newSize, "(no tween needed)")
        else
            DBG:print("Set LvProgress size to:", newSize, "(instant update)")
        end
    end
    
    DBG:print("LvProgress current size:", LvProgress.Size)
    
    DBG:print("=== END UPDATE LEVEL UI DEBUG ===")
end

local AnimationCache = setmetatable({}, { __mode = "k" }) -- weak keys: Model -> { Idle=track, Attack=track, Damaged=track }

local function getAnimator(model)
    if not model then return nil end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then
        animator = Instance.new("Animator")
        animator.Parent = humanoid
    end
    return animator
end

function BattleSystem:PreloadAnimations(model)
    if not model then return end
    local animationsFolder = model:FindFirstChild("Animations")
    if not animationsFolder then return end
    local animator = getAnimator(model)
    if not animator then return end
    local cache = {}
    local function loadTrack(name, priority)
        local anim = animationsFolder:FindFirstChild(name)
        if anim then
            local track = animator:LoadAnimation(anim)
            track.Priority = priority
            cache[name] = track
        end
    end
    loadTrack("Idle", Enum.AnimationPriority.Idle)
    -- Ensure combat anims override everything
    loadTrack("Attack", Enum.AnimationPriority.Action4)
    loadTrack("Damaged", Enum.AnimationPriority.Action4)
    AnimationCache[model] = cache
end

local function getCachedTrack(model, name)
    local cache = AnimationCache[model]
    if cache then return cache[name] end
    return nil
end

-- Helper: find first alive creature in party (client-side)
local function FindFirstAliveCreatureClient(party)
    if not party then return nil, nil end
    for i = 1, #party do
        local creature = party[i]
        if creature then
            local hpPercent = creature.CurrentHP
            local hpLegacy = creature.Stats and creature.Stats.HP
            local isAlive = (hpPercent ~= nil and hpPercent > 0) or (hpPercent == nil and hpLegacy and hpLegacy > 0)
            if LocallyFaintedSlots[i] then isAlive = false end
            if isAlive then
                return creature, i
            end
        end
    end
    return nil, nil
end

local function MarkSlotFainted(slotIndex)
    if not slotIndex then return end
    LocallyFaintedSlots[slotIndex] = true
    local ClientData = require(script.Parent.Parent.Plugins:WaitForChild("ClientData"))
    local data = ClientData:Get()
    if data and data.Party and data.Party[slotIndex] then
        data.Party[slotIndex].CurrentHP = 0
        data.Party[slotIndex].Stats = data.Party[slotIndex].Stats or {}
        data.Party[slotIndex].Stats.HP = 0
        -- Proactively refresh Party UI
        local UI = require(script.Parent.Parent.UI)
        if UI and UI.Party and UI.Party.UpdatePartyDisplay then
            pcall(function() UI.Party:UpdatePartyDisplay() end)
        end
    end
end

-- Camera positions will be read from workspace parts

-- Battle UI elements
local BattleNotification = BattleUI:WaitForChild("BattleNotification")
local BattleOptions = BattleUI:WaitForChild("BattleOptions")
local MoveOptions = BattleUI:WaitForChild("MoveOptions")
local FoeUI = BattleUI:WaitForChild("Foe")
local YouUI = BattleUI:WaitForChild("You")
-- Battle switching variables
local PartyInBattle = false
local SwitchMode = "None" -- "None", "Switch", "Forced"
local FadingOutPlayerModel = false
local PendingSwitchSlot: number? = nil
local SendOutButton: TextButton? = nil
local CancelButton: TextButton? = nil
local SendOutCreatureText: TextLabel? = nil
local SendOutCreatureIcon: ImageLabel? = nil
local SendOutUIStroke: UIStroke? = nil
local SwitchButtonConnection = nil
local CancelButtonConnection = nil

-- Colors for SendOut button
local SendOutValidColor = Color3.fromRGB(64, 224, 255)
local SendOutValidStroke = Color3.fromRGB(17, 60, 68)
local SendOutInvalidColor = Color3.fromRGB(255, 61, 61)
local SendOutInvalidStroke = Color3.fromRGB(79, 19, 19)

-- Initialize party UI references
local function initializePartyUI()
	DBG:print("=== INITIALIZE PARTY UI ===")
	DBG:print("SendOut button already exists:", SendOutButton ~= nil)
	DBG:print("Cancel button already exists:", CancelButton ~= nil)
	
	if SendOutButton and CancelButton then 
		DBG:print("Both buttons already exist, returning")
		return 
	end
	
	local PartyModule = UI and UI.Party
	DBG:print("PartyModule exists:", PartyModule ~= nil)
	if not PartyModule then 
		DBG:print("No PartyModule found")
		return 
	end
	
	local PartyUI = PartyModule:GetGui()
	DBG:print("PartyUI found:", PartyUI ~= nil)
	
	if not PartyUI then 
		DBG:print("Missing PartyUI")
		return 
	end
	
	DBG:print("Looking for SendOut button in Party...")
	SendOutButton = PartyUI:FindFirstChild("SendOut")
	DBG:print("SendOut button found:", SendOutButton ~= nil)
	
	DBG:print("Looking for Cancel button in Party...")
	CancelButton = PartyUI:FindFirstChild("Cancel")
	DBG:print("Cancel button found:", CancelButton ~= nil)
	
	if SendOutButton then
		SendOutCreatureText = SendOutButton:FindFirstChild("SendOutCreatureText")
		SendOutCreatureIcon = SendOutButton:FindFirstChild("CreatureIcon")
		SendOutUIStroke = SendOutButton:FindFirstChildOfClass("UIStroke")
		DBG:print("SendOut children found - Text:", SendOutCreatureText ~= nil, "Icon:", SendOutCreatureIcon ~= nil, "Stroke:", SendOutUIStroke ~= nil)
	end
	
	DBG:print("=== END INITIALIZE PARTY UI ===")
end

-- Update SendOut button appearance
local function updateSendOutButton(creatureData, slotIndex)
	if not SendOutButton or not SendOutCreatureText or not SendOutUIStroke then return end
	
	local isValid = false
	local text = ""
	
	-- Determine alive using compact save (CurrentHP is 0-100%) or legacy Stats.HP
	local hpPercent = creatureData and creatureData.CurrentHP
	local hpLegacy = creatureData and creatureData.Stats and creatureData.Stats.HP
    local isAlive = (hpPercent == nil and (hpLegacy == nil or hpLegacy > 0)) or (typeof(hpPercent) == "number" and hpPercent > 0)
    if LocallyFaintedSlots[slotIndex] then
        isAlive = false
    end

	if creatureData and isAlive then
		-- Check if it's not the current creature (compare slot indices)
		DBG:print("=== UPDATE SEND OUT BUTTON ===")
		DBG:print("Slot index:", slotIndex)
		DBG:print("Current PlayerCreatureIndex:", CurrentBattle and CurrentBattle.PlayerCreatureIndex or "nil")
		DBG:print("Are they equal?", slotIndex == (CurrentBattle and CurrentBattle.PlayerCreatureIndex))
		
		if CurrentBattle and CurrentBattle.PlayerCreatureIndex and slotIndex ~= CurrentBattle.PlayerCreatureIndex then
			isValid = true
			-- Use nickname if available, otherwise use creature name
			local displayName = creatureData.Nickname or creatureData.Name
			text = "Send out " .. displayName
			DBG:print("Valid switch - text:", text)
		else
			text = "Already out"
			DBG:print("Already out - text:", text)
		end
	else
		text = "Fainted"
		DBG:print("Fainted - text:", text)
	end
	
	-- Update text
	SendOutCreatureText.Text = text
	
	-- Update colors
	if isValid then
		SendOutButton.BackgroundColor3 = SendOutValidColor
		SendOutUIStroke.Color = SendOutValidStroke
	else
		SendOutButton.BackgroundColor3 = SendOutInvalidColor
		SendOutUIStroke.Color = SendOutInvalidStroke
	end
	
	-- Update text stroke color
	local textStroke = SendOutCreatureText:FindFirstChildOfClass("UIStroke")
	if textStroke then
		textStroke.Color = isValid and SendOutValidStroke or SendOutInvalidStroke
	end
	
	-- Update creature icon (same logic as Party.lua)
	if SendOutCreatureIcon and creatureData then
		local creaturesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
		local baseCreature = creaturesModule[creatureData.Name]
		if baseCreature and baseCreature.Sprite then
			SendOutCreatureIcon.Image = baseCreature.Sprite
		else
			warn("No sprite found for creature:", creatureData.Name)
			SendOutCreatureIcon.Image = ""
		end
	end
end

-- Set button visibility
local function setBattleButtonsVisible(visible)
	DBG:print("=== SET BATTLE BUTTONS VISIBLE ===")
	DBG:print("Setting visibility to:", visible)
	
	-- SendOut button should only be visible when a creature is selected
	if SendOutButton then 
		SendOutButton.Visible = false -- Always start hidden
		SendOutButton.Active = false
		SendOutButton.BackgroundTransparency = 1
		DBG:print("SendOut button - Hidden by default")
	else
		DBG:print("SendOut button is nil!")
	end
	
	-- Cancel button visibility depends on switch mode
	if CancelButton then 
		-- Hide Cancel button during forced switches
		local cancelVisible = visible and SwitchMode ~= "Forced"
		CancelButton.Visible = cancelVisible
		CancelButton.Active = cancelVisible
		CancelButton.BackgroundTransparency = cancelVisible and 0 or 1
		DBG:print("Cancel button - Visible:", CancelButton.Visible, "Active:", CancelButton.Active, "Transparency:", CancelButton.BackgroundTransparency, "SwitchMode:", SwitchMode)
	else
		DBG:print("Cancel button is nil!")
	end
	
	DBG:print("=== END SET BATTLE BUTTONS VISIBLE ===")
end

-- Handle creature selection for switching
function BattleSystem:OnCreatureSelected(creatureData, slotIndex)
	DBG:print("=== CREATURE SELECTED CALLBACK TRIGGERED ===")
	DBG:print("PartyInBattle:", PartyInBattle)
	DBG:print("Creature:", creatureData and creatureData.Name or "nil")
	DBG:print("Slot:", slotIndex)
	
	if not PartyInBattle then 
		DBG:print("Not in battle, ignoring selection")
		return 
	end
	
	PendingSwitchSlot = slotIndex
	
	-- Show SendOut button now that a creature is selected
	if SendOutButton then
		SendOutButton.Visible = true
		SendOutButton.Active = true
		SendOutButton.BackgroundTransparency = 0
		DBG:print("SendOut button made visible")
	else
		DBG:print("SendOut button is nil!")
	end
	
	-- Update SendOut button with creature data
	updateSendOutButton(creatureData, slotIndex)
	
	DBG:print("=== END CREATURE SELECTED ===")
end

-- Handle SendOut button click
function BattleSystem:AttemptSwitch()
	DBG:print("=== ATTEMPT SWITCH ===")
	DBG:print("PendingSwitchSlot:", PendingSwitchSlot)
	DBG:print("PartyInBattle:", PartyInBattle)
	
	if not PendingSwitchSlot or not PartyInBattle then 
		DBG:print("Cannot switch - missing data")
		return 
	end
	
	-- Validate the switch
	local ClientData = require(script.Parent.Parent.Plugins:WaitForChild("ClientData"))
	local playerData = ClientData:Get()
	local creature = playerData.Party and playerData.Party[PendingSwitchSlot]
	
	DBG:print("Creature found:", creature ~= nil)
	DBG:print("Creature name:", creature and creature.Name or "nil")
	
	-- Fixed: use CurrentHP percent (0-100) instead of legacy Stats.HP for faint checks
	local hpPercent = creature and creature.CurrentHP
    local hpLegacy = creature and creature.Stats and creature.Stats.HP
    local isFainted = (hpPercent ~= nil and hpPercent <= 0) or (hpPercent == nil and hpLegacy ~= nil and hpLegacy <= 0)
    if not creature or isFainted then
		DBG:warn("Cannot switch to fainted creature")
		return
	end
	
	DBG:print("Current PlayerCreatureIndex:", CurrentBattle and CurrentBattle.PlayerCreatureIndex or "nil")
	DBG:print("PendingSwitchSlot:", PendingSwitchSlot)
	DBG:print("Are they equal?", PendingSwitchSlot == (CurrentBattle and CurrentBattle.PlayerCreatureIndex))
	
	if CurrentBattle and CurrentBattle.PlayerCreatureIndex and PendingSwitchSlot == CurrentBattle.PlayerCreatureIndex then
		DBG:warn("Cannot switch to current creature")
		return
	end
	
	-- Hide Party UI
	local PartyModule = UI and UI.Party
	if PartyModule then
		PartyModule:Close()
	end
	
	-- The switch message will be shown by the server response
	
	-- Send switch request to server (server determines if forced based on game state)
	DBG:print("Sending switch request to server - Slot:", PendingSwitchSlot)
	local success, errorMsg = pcall(function()
		Events.Request:InvokeServer({"SwitchCreature", PendingSwitchSlot})
	end)
	
	-- Only reset state if server call succeeded
	if success then
		-- Do nothing - reset happens after server response in HandleTurnResult  
		-- Don't clear things here because server might return errors
	else
		DBG:warn("Server switch call failed:", errorMsg)
		-- Reset on client error
		SwitchMode = "None"
		PendingSwitchSlot = nil
	end
end

-- Handle Cancel button click
function BattleSystem:CancelSwitch()
	if not PartyInBattle then return end
	
	-- Hide Party UI
	local PartyModule = UI and UI.Party
	if PartyModule then
		PartyModule:Close()
	end
	
	-- Reset state
	SwitchMode = "None"
	PendingSwitchSlot = nil
	
	-- Show battle options if not forced switch
	if SwitchMode ~= "Forced" then
		BattleSystem:BattleOptionsToggle(true)
	end
end

-- Handle party opened during battle
function BattleSystem:OnPartyOpened()
	DBG:print("=== ON PARTY OPENED ===")
	-- Only mark in-battle if an active battle exists
	PartyInBattle = CurrentBattle ~= nil
	
	-- Initialize party UI references
	initializePartyUI()
	DBG:print("SendOut button found:", SendOutButton ~= nil)
	DBG:print("Cancel button found:", CancelButton ~= nil)
	
	-- Make buttons visible only when in battle
	if PartyInBattle then
		setBattleButtonsVisible(true)
	else
		setBattleButtonsVisible(false)
	end
	DBG:print("SendOut button visible:", SendOutButton and SendOutButton.Visible)
	DBG:print("Cancel button visible:", CancelButton and CancelButton.Visible)
	
	-- Set up the selection callback here instead of in setupPartyCallbacks
	local PartyModule = UI and UI.Party
	if PartyModule then
		DBG:print("Setting up selection callback in OnPartyOpened...")
		PartyModule:SetSelectionChangedCallback(function(creatureData, slotIndex)
			DBG:print("Selection callback triggered from Party module")
			BattleSystem:OnCreatureSelected(creatureData, slotIndex)
		end)
		DBG:print("Selection callback set in OnPartyOpened")
	else
		DBG:print("No PartyModule found in OnPartyOpened!")
	end
	
	-- Connect buttons if not already connected
	if SendOutButton and not SwitchButtonConnection then
		DBG:print("Connecting SendOut button...")
		SwitchButtonConnection = UIFunctions:NewButton(
			SendOutButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				DBG:print("SendOut button clicked!")
				BattleSystem:AttemptSwitch()
			end
		)
		DBG:print("SendOut button connected:", SwitchButtonConnection ~= nil)
	end
	
	if CancelButton and not CancelButtonConnection then
		DBG:print("Connecting Cancel button...")
		CancelButtonConnection = UIFunctions:NewButton(
			CancelButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				DBG:print("Cancel button clicked!")
				BattleSystem:CancelSwitch()
			end
		)
		DBG:print("Cancel button connected:", CancelButtonConnection ~= nil)
	end
	
	DBG:print("=== END ON PARTY OPENED ===")
end

-- Handle party closed
function BattleSystem:OnPartyClosed()
	PartyInBattle = false
	setBattleButtonsVisible(false)
	SwitchMode = "None"
	PendingSwitchSlot = nil
	
	-- Disconnect buttons
	if SwitchButtonConnection then
		UIFunctions:ClearConnection(SendOutButton)
		SwitchButtonConnection = nil
	end
	
	if CancelButtonConnection then
		UIFunctions:ClearConnection(CancelButton)
		CancelButtonConnection = nil
	end
end

-- Update player creature model in workspace (where it's actually spawned)
function BattleSystem:UpdatePlayerCreatureModel(newCreatureData)
	DBG:print("=== UPDATING PLAYER CREATURE MODEL ===")
	DBG:print("New creature:", newCreatureData.Name)
	
    -- Check if we have a reference to the current player creature model
    if not PlayerCreatureModel or not PlayerCreatureModel.PrimaryPart then
        DBG:warn("No valid PlayerCreatureModel/PrimaryPart found; spawning fresh at spawn point")
        -- Mirror initial spawn path for consistency
        if not (BattleScene and BattleScene:FindFirstChild("Essentials")) then return end
        local Essentials = BattleScene:FindFirstChild("Essentials")
        local PlayerSpawn = Essentials and Essentials:FindFirstChild("PlayerCreatureSpawn")
        if not PlayerSpawn then return end
        -- Use the same routine as initial spawn to ensure identical behavior
        BattleSystem:SpawnCreatureModel(newCreatureData, PlayerSpawn, true)
        -- Update UI after spawn
        if YouUI then BattleSystem:UpdateCreatureUI(YouUI, newCreatureData) end
        DBG:print("Spawned new PlayerCreatureModel via SpawnCreatureModel for consistency")
        return
    end
	
	-- Get spawn point from battle scene to position new model correctly
	local Essentials = BattleScene:WaitForChild("Essentials")
	local PlayerSpawn = Essentials:WaitForChild("PlayerCreatureSpawn")
	
	-- Get the creature model from ReplicatedStorage
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local CreatureModels = Assets:WaitForChild("CreatureModels")
	local newCreatureModel = CreatureModels:FindFirstChild(newCreatureData.Name)
	
	if not newCreatureModel then
		DBG:warn("No model found for creature:", newCreatureData.Name)
		return
	end
	
    -- Store the old model's position (safe since we validated PrimaryPart)
    local oldPosition = PlayerCreatureModel:GetPrimaryPartCFrame()
	
	-- Clone and spawn via the same path as initial spawn to avoid drift
	local oldModel = PlayerCreatureModel
	-- Helper to perform the new spawn and UI refresh
	local function spawnNew()
		-- Spawn new model using canonical routine (ensures Status UI removal, shiny, idle)
		BattleSystem:SpawnCreatureModel(newCreatureData, PlayerSpawn, true)
		-- Ensure camera returns to default for clarity on switching
		BattleSystem:MoveCameraToWideView()
		-- Update the battle UI to reflect the new creature (force refresh even if reference stale)
		local ui = YouUI or (BattleUI and BattleUI:FindFirstChild("You"))
		if ui then
			BattleSystem:UpdateCreatureUI(ui, newCreatureData)
			DBG:print("Updated battle UI for new creature:", newCreatureData.Name)
			-- Update level UI for the new creature immediately
			DBG:print("Updating level UI for switched creature:", newCreatureData.Name)
			updateLevelUI(newCreatureData, false)
			-- Emit deferred Go message, if any, now that model is present
			if CurrentBattle and CurrentBattle.PendingGoMessage then
				DBG:print("BATTLE: Showing Go message:", CurrentBattle.PendingGoMessage)
				BattleSystem:ShowBattleMessage(CurrentBattle.PendingGoMessage)
				CurrentBattle.PendingGoMessage = nil

				-- For forced switches, ensure battle options are shown after the "Go!" message
				if CurrentBattle and CurrentBattle.SwitchMode == "Forced" then
					DBG:print("BATTLE: Setting up battle options callback after Go message")
					BattleSystem:OnBattleMessagesDrained(function()
						DBG:print("BATTLE: Go message drained, showing battle options")
						BattleSystem:StartNextTurn()
					end)
				end
			elseif CurrentBattle and CurrentBattle.SwitchMode == "Forced" then
				-- No "Go!" message, but still need to show battle options for forced switch
				DBG:print("BATTLE: No Go message, showing battle options immediately")
				BattleSystem:StartNextTurn()
			end
		else
			DBG:warn("YouUI not found - cannot update battle UI")
		end
		DBG:print("Player creature model updated successfully")
	end

	-- Play a hologram fade-out on the old model before replacing to avoid popping
	if oldModel and oldModel.Parent and not FadingOutPlayerModel then
		DBG:print("VOLUNTARY SWITCH: Starting hologram fade-out for old model")
		FadingOutPlayerModel = true
		local HologramSpawnEffect = require(script.Parent.HologramSpawnEffect)
		HologramSpawnEffect:CreateFadeOut(oldModel, function()
			if oldModel and oldModel.Parent then
				oldModel:Destroy()
				DBG:print("VOLUNTARY SWITCH: Old model destroyed after hologram fade-out")
			end
			FadingOutPlayerModel = false
			spawnNew()
		end)
	else
		DBG:print("VOLUNTARY SWITCH: Skipping hologram fade-out - oldModel:", oldModel ~= nil, "Parent:", oldModel and oldModel.Parent ~= nil, "FadingOutPlayerModel:", FadingOutPlayerModel)
		if oldModel and oldModel.Parent then oldModel:Destroy() end
		spawnNew()
	end
end

-- Utility: color lerp between two Color3 values
local function LerpColor3(a: Color3, b: Color3, t: number): Color3
    t = math.clamp(t, 0, 1)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

-- Initialize battle system
function BattleSystem:Init()
	DBG:print("Initializing BattleSystem")
	
	-- Hide battle UI initially
	BattleUI.Visible = false
	BattleOptions.Visible = false
	MoveOptions.Visible = false
	
	-- Initialize battle UI interactions
	BattleSystem:SetupBattleUIInteractions()
	
	-- Connect battle request handler
	Events.Communicate.OnClientEvent:Connect(function(EventType, Data)
		if EventType == "StartBattle" then
			BattleSystem:StartBattle(Data)
		elseif EventType == "EnemyTurn" then
			BattleSystem:HandleEnemyTurn(Data)
		elseif EventType == "TurnComplete" then
			BattleSystem:HandleTurnComplete(Data)
		elseif EventType == "EscapeSuccess" then
			BattleSystem:HandleEscapeSuccess()
		elseif EventType == "EscapeFailure" then
			BattleSystem:HandleEscapeFailure()
		elseif EventType == "TurnResult" then
			BattleSystem:HandleTurnResult(Data)
		elseif EventType == "BattleMessage" then
			DBG:print("Received BattleMessage:", Data)
			BattleSystem:ShowBattleMessage(Data)
		elseif EventType == "ClientData" then
			DBG:print("Received ClientData update from server")
			-- Update the current battle creature data with fresh server data
			if CurrentBattle and CurrentBattle.PlayerCreatureIndex and Data.Party then
				local updatedCreature = Data.Party[CurrentBattle.PlayerCreatureIndex]
				if updatedCreature then
					DBG:print("Updating battle creature data with fresh server data")
					-- Update the battle creature with fresh data
					CurrentBattle.PlayerCreature.Level = updatedCreature.Level
					CurrentBattle.PlayerCreature.XPProgress = updatedCreature.XPProgress
					CurrentBattle.PlayerCreature.Stats = updatedCreature.Stats
					CurrentBattle.PlayerCreature.MaxStats = updatedCreature.MaxStats
					CurrentBattle.PlayerCreature.CurrentHP = updatedCreature.CurrentHP
					
					-- Do NOT update the XP UI here; defer XP bar changes to when the XP BattleMessage is displayed
					-- This ensures the animation timing aligns with the visible message, not when data is received
					DBG:print("Deferred XP UI update to BattleMessage timing (no immediate UI change)")
				end
			end
		end
	end)
end

-- Initialize party callbacks
local function setupPartyCallbacks()
	print("=== SETUP PARTY CALLBACKS CALLED ===")
	DBG:print("=== SETUP PARTY CALLBACKS ===")
	local PartyModule = UI and UI.Party
	DBG:print("UI module exists:", UI ~= nil)
	DBG:print("PartyModule exists:", PartyModule ~= nil)
	if not PartyModule then 
		DBG:print("No PartyModule found!")
		return 
	end
	
	-- Selection callback is now set up in OnPartyOpened() instead
	DBG:print("Selection callback will be set up when party opens")
	
	DBG:print("Setting up open/close callbacks...")
	PartyModule:SetOpenCloseCallbacks(function()
		BattleSystem:OnPartyOpened()
	end, function()
		BattleSystem:OnPartyClosed()
	end)
	
	DBG:print("=== END SETUP PARTY CALLBACKS ===")
end

-- Start a battle
function BattleSystem:StartBattle(BattleInfo)
	DBG:print("Starting battle:", BattleInfo.Type)
	DBG:print("Battle data received:", BattleInfo)
	
	-- Ensure FOV is at 50 when starting encounters
	workspace.CurrentCamera.FieldOfView = 50
	
	-- Reset faint flags for new battle
	PlayerFaintTweened = false
	FoeFaintTweened = false
	PlayerFaintedAnnounced = false
	LocallyFaintedSlots = {}
	
	-- DEBUG: Check party data before battle starts
	local ClientData = require(script.Parent.Parent.Plugins:WaitForChild("ClientData"))
	local playerData = ClientData:Get()
	DBG:print("=== PARTY DEBUG - BEFORE BATTLE ===")
	DBG:print("Party exists:", playerData.Party ~= nil)
	DBG:print("Party length:", playerData.Party and #playerData.Party or "nil")
	if playerData.Party then
		for i, creature in ipairs(playerData.Party) do
			DBG:print("Party[" .. i .. "]:", creature.Name, "Level:", creature.Level)
		end
	end
	
	-- Create a deep copy of battle data to prevent modifying original party data
	CurrentBattle = {
		Type = BattleInfo.Type,
		PlayerCreatureIndex = BattleInfo.PlayerCreatureIndex,
		PlayerCreature = BattleInfo.PlayerCreature and {
			Nickname = BattleInfo.PlayerCreature.Nickname,
			Name = BattleInfo.PlayerCreature.Name,
			Level = BattleInfo.PlayerCreature.Level,
			XPProgress = BattleInfo.PlayerCreature.XPProgress,
			Stats = BattleInfo.PlayerCreature.Stats and {
				HP = BattleInfo.PlayerCreature.Stats.HP,
				Attack = BattleInfo.PlayerCreature.Stats.Attack,
				Defense = BattleInfo.PlayerCreature.Stats.Defense,
				Speed = BattleInfo.PlayerCreature.Stats.Speed
			},
			MaxStats = BattleInfo.PlayerCreature.MaxStats and {
				HP = BattleInfo.PlayerCreature.MaxStats.HP,
				Attack = BattleInfo.PlayerCreature.MaxStats.Attack,
				Defense = BattleInfo.PlayerCreature.MaxStats.Defense,
				Speed = BattleInfo.PlayerCreature.MaxStats.Speed
			},
			CurrentMoves = BattleInfo.PlayerCreature.CurrentMoves,
			Gender = BattleInfo.PlayerCreature.Gender,
			Shiny = BattleInfo.PlayerCreature.Shiny,
			-- YOffset deprecated
		},
		FoeCreature = BattleInfo.FoeCreature and {
			Name = BattleInfo.FoeCreature.Name,
			Level = BattleInfo.FoeCreature.Level,
			Stats = BattleInfo.FoeCreature.Stats and {
				HP = BattleInfo.FoeCreature.Stats.HP,
				Attack = BattleInfo.FoeCreature.Stats.Attack,
				Defense = BattleInfo.FoeCreature.Stats.Defense,
				Speed = BattleInfo.FoeCreature.Stats.Speed
			},
			MaxStats = BattleInfo.FoeCreature.MaxStats and {
				HP = BattleInfo.FoeCreature.MaxStats.HP,
				Attack = BattleInfo.FoeCreature.MaxStats.Attack,
				Defense = BattleInfo.FoeCreature.MaxStats.Defense,
				Speed = BattleInfo.FoeCreature.MaxStats.Speed
			},
			CurrentMoves = BattleInfo.FoeCreature.CurrentMoves,
			Gender = BattleInfo.FoeCreature.Gender,
			Shiny = BattleInfo.FoeCreature.Shiny,
			-- YOffset deprecated
		},
		ChunkName = BattleInfo.ChunkName,
		IsStatic = BattleInfo.IsStatic,
		IsBoss = BattleInfo.IsBoss,
		Message = BattleInfo.Message,
		TrainerName = BattleInfo.TrainerName
	}
	
	-- Initialize turn-based system
	CurrentBattle.PlayerTurnUsed = false
	CurrentBattle.EnemyTurnUsed = false
	CurrentBattle.TurnNumber = 1
	CurrentBattle.EscapeAttempts = 0
	FoeFaintedThisTurn = false
	FoeFaintedAnnounced = false
	
    -- Suppress TopBar during battle to avoid visibility races
    pcall(function() UI.TopBar:SetSuppressed(true) end)
	-- Don't show battle UI yet - wait for exclamation mark animation to complete
	-- BattleUI.Visible = true
	
	-- Load battle scene
	local sceneLoaded = BattleSystem:LoadBattleScene(BattleInfo.ChunkName)
	if not sceneLoaded then
		DBG:error("Failed to load battle scene, ending battle")
		BattleSystem:EndBattle()
		return
	end
	
	-- Wait for scene to load
	task.wait(0.05)
	
	-- Setup camera
	BattleSystem:SetupCamera()
	-- Ensure any previous camera cycles/tweens are stopped before intro starts
	BattleSystem:StopCameraCycle()
	if ActiveCameraTween then
		pcall(function() ActiveCameraTween:Cancel() end)
		ActiveCameraTween = nil
	end
	
	-- Spawn creatures
	BattleSystem:SpawnCreatures()
	
	-- Setup UI
	print("=== ABOUT TO CALL SETUP UI ===")
	BattleSystem:SetupUI()
	print("=== FINISHED CALLING SETUP UI ===")
	
	-- Setup party callbacks for switching
	-- Snapshot party before evolutions so we can detect changes after battle
	local ClientData = require(script.Parent.Parent.Plugins:WaitForChild("ClientData"))
	local snapshot = {}
	local data = ClientData:Get()
	if data and data.Party then
		for i, c in ipairs(data.Party) do
			snapshot[i] = { Name = c.Name, Level = c.Level }
		end
	end
	BattleSystem.PreBattlePartySnapshot = snapshot
	print("=== ABOUT TO CALL SETUP PARTY CALLBACKS ===")
	setupPartyCallbacks()
	print("=== FINISHED CALLING SETUP PARTY CALLBACKS ===")
	
	-- Gate ALL battle intros behind the exclamation mark animation
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local ExclamationMark = GameUI:WaitForChild("ExclamationMark")
	
	-- Start the exclamation mark animation immediately and wait for it to complete
	local UIFunctions = require(script.Parent.Parent.UI:WaitForChild("UIFunctions"))
	UIFunctions:DoExclamationMark(ExclamationMark)
	DBG:print("Exclamation mark grow animation completed at StartBattle")
	
	-- Wait a moment to let the exclamation mark be visible
	task.wait(0.3)
	
	-- Wait for foe creature animation to start (foe is already spawned in SpawnCreatures)
	BattleSystem:WaitForCreatureAnimations()
	
	-- Exclamation mark fade-out will happen in intro sequence
	
	-- Store original UI positions for slide animations
	YouUIPosition = YouUI.Position
	FoeUIPosition = FoeUI.Position
	
	-- Initialize level UI immediately after battle data is set up
	DBG:print("Initializing level UI for battle start")
	updateLevelUI(CurrentBattle.PlayerCreature, false) -- Instant update for battle start
	
	-- Handle battle intro (this spawns player creature and shows messages)
	if BattleInfo.Type == "Wild" then
		BattleSystem:WildEncounterIntro()
	elseif BattleInfo.Type == "Trainer" then
		BattleSystem:TrainerBattleIntro()
	end
end

-- Load battle scene from PlayerGui (server should have already cloned it there)
function BattleSystem:LoadBattleScene(ChunkName)
	DBG:print("Loading battle scene for chunk:", ChunkName)
	
	local PlayerGui = game.Players.LocalPlayer:WaitForChild("PlayerGui")
	
	-- Look for the battle scene in PlayerGui
	local BattleSceneName = "BattleScene_" .. ChunkName
	BattleScene = PlayerGui:FindFirstChild(BattleSceneName)
	
	if not BattleScene then
		DBG:warn("No battle scene found for chunk:", ChunkName, "trying Chunk1")
		-- Fallback to Chunk1
		BattleScene = PlayerGui:FindFirstChild("BattleScene_Chunk1")
	end
	
	if not BattleScene then
		DBG:error("No battle scene found in PlayerGui!")
		return false
	end
	
	-- Move the battle scene to workspace
	BattleScene.Parent = Workspace
	
	DBG:print("Battle scene loaded:", BattleScene.Name)
	return true
end

-- Setup camera for battle
function BattleSystem:SetupCamera()
	DBG:print("Setting up battle camera")
	
	-- Store original camera settings BEFORE changing them
	BattleSystem.OriginalCameraType = Camera.CameraType
	BattleSystem.OriginalFOV = Camera.FieldOfView
	
	-- Set camera to scriptable
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.FieldOfView = 50
	
	-- Don't set camera position here - let the intro sequence handle it
	-- This prevents the Default position from showing before the intro animation
end

-- Start Shield-style camera cycling when idle at options
function BattleSystem:StartCameraCycle()
    if CameraCycle.running then return end
    CameraCycle.running = true
    CameraCycle.version += 1
    local myVersion = CameraCycle.version
    -- Clear any previous tweens
    for _, t in ipairs(CameraCycle.tweens) do pcall(function() t:Cancel() end) end
    CameraCycle.tweens = {}

    local function getCameraPoints()
        if not BattleScene then return nil end
        local CameraPoints = BattleScene:FindFirstChild("CameraPoints")
        if not CameraPoints then return nil end
        return CameraPoints
    end

    local function getDefault()
        local cp = getCameraPoints()
        if not cp then return nil end
        return cp:FindFirstChild("Default")
    end

    local function foldersToCycle()
        local cp = getCameraPoints()
        if not cp then return {} end
        local list = {}
        for _, child in ipairs(cp:GetChildren()) do
            if child:IsA("Folder") and child.Name ~= "Default" then
                table.insert(list, child)
            end
        end
        table.sort(list, function(a,b) return a.Name < b.Name end)
        return list
    end

    local function resolvePoints(folder)
        -- Prefer parts named "1" and "2" if present
        local p1 = folder:FindFirstChild("1")
        local p2 = folder:FindFirstChild("2")
        if p1 and p2 and p1:IsA("BasePart") and p2:IsA("BasePart") then
            return p1, p2
        end
        -- Otherwise, collect all BaseParts and pick the first two by name
        local parts = {}
        for _, ch in ipairs(folder:GetChildren()) do
            if ch:IsA("BasePart") then table.insert(parts, ch) end
        end
        table.sort(parts, function(a, b) return a.Name < b.Name end)
        return parts[1], parts[2]
    end

    local defaultPart = getDefault()
    if defaultPart then
        Camera.CFrame = defaultPart.CFrame
    end

    CameraCycle.thread = task.spawn(function()
        local sineInfo = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        while CameraCycle.running and myVersion == CameraCycle.version do
            -- Stay on default for 5 seconds
            task.wait(5)
            if not CameraCycle.running or myVersion ~= CameraCycle.version then break end

            -- Cycle through each folder, jump to 1 then tween to 2
            for _, folder in ipairs(foldersToCycle()) do
                if not CameraCycle.running or myVersion ~= CameraCycle.version then break end
                local part1, part2 = resolvePoints(folder)
                if part1 and part2 then
                    Camera.CFrame = part1.CFrame -- instant to 1
                    local tween = TweenService:Create(Camera, sineInfo, {CFrame = part2.CFrame})
                    table.insert(CameraCycle.tweens, tween)
                    tween:Play()
                    local completed = false
                    tween.Completed:Connect(function()
                        completed = true
                    end)
                    local elapsed = 0
                    while CameraCycle.running and myVersion == CameraCycle.version and not completed and elapsed < (sineInfo.Time + 0.1) do
                        task.wait(0.1)
                        elapsed += 0.1
                    end
                    -- cleanup finished tweens
                    local newTweens = {}
                    for _, t in ipairs(CameraCycle.tweens) do
                        if t.PlaybackState ~= Enum.PlaybackState.Completed then
                            table.insert(newTweens, t)
                        end
                    end
                    CameraCycle.tweens = newTweens
                elseif part1 then
                    -- Only one point found; hold briefly to avoid stalling the loop
                    Camera.CFrame = part1.CFrame
                    local elapsed = 0
                    while CameraCycle.running and myVersion == CameraCycle.version and elapsed < 1.0 do
                        task.wait(0.1)
                        elapsed += 0.1
                    end
                end
            end
        end
    end)
end

-- Stop camera cycle and snap back to default
function BattleSystem:StopCameraCycle()
    if not CameraCycle.running then return end
    CameraCycle.running = false
    CameraCycle.version += 1
    for _, t in ipairs(CameraCycle.tweens) do pcall(function() t:Cancel() end) end
    CameraCycle.tweens = {}
    if BattleScene then
        local cp = BattleScene:FindFirstChild("CameraPoints")
        if cp then
            local def = cp:FindFirstChild("Default")
            if def then
                Camera.CFrame = def.CFrame
            end
        end
    end
end

-- Spawn creature models
function BattleSystem:SpawnCreatures()
	DBG:print("Spawning creature models")
	
	-- Get spawn points
	local Essentials = BattleScene:WaitForChild("Essentials")
	local PlayerSpawn = Essentials:WaitForChild("PlayerCreatureSpawn")
	local FoeSpawn = Essentials:WaitForChild("FoeCreatureSpawn")
	
	-- Spawn foe creature first; player will be spawned after intro camera completes
	DBG:print("Spawning foe creature:", CurrentBattle.FoeCreature.Name)
	BattleSystem:SpawnCreatureModel(CurrentBattle.FoeCreature, FoeSpawn, false)
	DBG:print("Foe creature spawned, FoeCreatureModel:", FoeCreatureModel and FoeCreatureModel.Name or "nil")
end

-- Spawn a single creature model
function BattleSystem:SpawnCreatureModel(CreatureData, SpawnPoint, IsPlayer)
	DBG:print("Spawning creature:", CreatureData.Name, "at spawn point:", SpawnPoint.Name)
	
	-- Get creature model from ReplicatedStorage
	local Assets = ReplicatedStorage:WaitForChild("Assets")
	local CreatureModels = Assets:WaitForChild("CreatureModels")
	local CreatureModel = CreatureModels:WaitForChild(CreatureData.Name)
	
	if not CreatureModel then
		DBG:warn("Creature model not found:", CreatureData.Name)
		return
	end
	
    -- Clone the model but don't parent it yet
	local Model = CreatureModel:Clone()
    
    -- Position the model at spawn point
    Model:SetPrimaryPartCFrame(SpawnPoint.CFrame + Vector3.new(0, 5, 0))
    
    -- Parent the model and determine hologram usage
	Model.Parent = Workspace
    local PrimaryPart = Model:FindFirstChild("HumanoidRootPart") or Model.PrimaryPart or Model:FindFirstChild("Torso")
    local useHologram = (IsPlayer == true) or (CurrentBattle and CurrentBattle.Type == "Trainer" and not IsPlayer)

    -- Helper to set transparency on all BaseParts in the model (except HumanoidRootPart)
    local function setModelTransparency(m, alpha)
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
                d.Transparency = alpha
            end
        end
    end

    -- If using the hologram effect, spawn off-screen to avoid texture artifacts; otherwise, keep visible
    local originalCFrame = PrimaryPart and PrimaryPart.CFrame or (Model:GetPrimaryPartCFrame())
    if useHologram then
        -- Move far below the map temporarily (off-screen)
        local offscreen = (originalCFrame and (originalCFrame * CFrame.new(0, -1000, 0))) or (SpawnPoint.CFrame * CFrame.new(0, -1000, 0))
        if PrimaryPart then
            PrimaryPart.CFrame = offscreen
        else
            Model:MoveTo((SpawnPoint.Position) + Vector3.new(0, -1000, 0))
        end
    end
	
	-- Destroy Status GUI from HumanoidRootPart
	local HRP = Model:FindFirstChild("HumanoidRootPart")
	if HRP then
		local StatusGUI = HRP:FindFirstChild("Status")
		if StatusGUI then
			StatusGUI:Destroy()
			DBG:print("Destroyed Status GUI from creature:", CreatureData.Name)
		end
	end
	
	-- Apply shiny recolor if needed (no highlight)
	if CreatureData.Shiny then
		local CreaturesData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
		local species = CreaturesData and CreaturesData[CreatureData.Name]
		local shinyColors = species and species.ShinyColors
		if shinyColors then
			for _, d in ipairs(Model:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("MeshPart") then
					local newColor = shinyColors[d.Name]
					if newColor then
						pcall(function()
							d.Color = newColor
						end)
					end
				end
			end
			DBG:print("Applied shiny recolor to creature:", CreatureData.Name)
		end
	end
	
	-- Store reference before playing animation
	if IsPlayer then
		PlayerCreatureModel = Model
		-- Reset faint flag when spawning a new player creature
		PlayerFaintTweened = false
	else
		FoeCreatureModel = Model
		-- Reset faint flag when spawning a new foe creature
		FoeFaintTweened = false
	end
	
    -- Preload animations for instant play after hologram effect
    BattleSystem:PreloadAnimations(Model)

    -- If not using hologram (e.g., wild foe), teleport to spawn and start idle immediately
    if not useHologram then
        if PrimaryPart and originalCFrame then
            PrimaryPart.CFrame = originalCFrame
        else
            Model:SetPrimaryPartCFrame(SpawnPoint.CFrame + Vector3.new(0, 5, 0))
        end
        -- Start idle animation
        local track = getCachedTrack(Model, "Idle")
        if track then
            pcall(function() track:Play() end)
            DBG:print("Started cached idle animation for:", Model.Name, "IsPlayer:", IsPlayer)
        else
            track = BattleSystem:PlayCreatureAnimation(Model, "Idle")
            DBG:print("Started new idle animation for:", Model.Name, "IsPlayer:", IsPlayer)
        end
        if track then
            if IsPlayer then
                PlayerIdleTrack = track
                DBG:print("Set PlayerIdleTrack")
            else
                FoeIdleTrack = track
                DBG:print("Set FoeIdleTrack")
            end
        else
            DBG:warn("No idle track created for:", Model.Name)
        end
        
        -- Slide UI back in when creature spawns (for non-hologram spawns)
        if IsPlayer and YouUIPosition then
            local youRef = YouUI or (BattleUI and BattleUI:FindFirstChild("You"))
            if youRef then
                slideUIIn(youRef, YouUIPosition)
            end
        elseif not IsPlayer and FoeUIPosition then
            slideUIIn(FoeUI, FoeUIPosition)
        end
        
        -- If this is the player's spawn as part of a switch, emit deferred "Go X!" now
        if IsPlayer and CurrentBattle and CurrentBattle.PendingGoMessage then
            DBG:print("BATTLE: Showing Go message (non-hologram):", CurrentBattle.PendingGoMessage)
            BattleSystem:ShowBattleMessage(CurrentBattle.PendingGoMessage)
            CurrentBattle.PendingGoMessage = nil

            -- For forced switches, ensure battle options are shown after the "Go!" message
            if CurrentBattle and CurrentBattle.SwitchMode == "Forced" then
                DBG:print("BATTLE: Setting up battle options callback after Go message (non-hologram)")
                BattleSystem:OnBattleMessagesDrained(function()
                    DBG:print("BATTLE: Go message drained, showing battle options")
                    BattleSystem:StartNextTurn()
                end)
            end
        elseif IsPlayer and CurrentBattle and CurrentBattle.SwitchMode == "Forced" then
            -- No "Go!" message, but still need to show battle options for forced switch
            DBG:print("BATTLE: No Go message, showing battle options immediately (non-hologram)")
            BattleSystem:StartNextTurn()
        end

        DBG:print("Creature spawned:", CreatureData.Name, "Shiny:", CreatureData.Shiny)
        -- Clear pending spawn flag so enemy can act
        if IsPlayer and CurrentBattle then
            CurrentBattle.SwitchSpawnPending = nil
        end
		return
	end
	
    -- Create hologram spawn effect sized to the model bounds, centered at target spawn
    local effectPosition = (originalCFrame and originalCFrame.Position) or SpawnPoint.Position
    print("=== BATTLE SYSTEM HOLOGRAM DEBUG ===")
    print("Using hologram effect for creature:", CreatureData.Name)
    print("Effect position:", effectPosition)
    print("Model size:", Model:GetExtentsSize())
    
    HologramSpawnEffect:CreateForModel(Model, effectPosition, {
        onPeak = function()
            -- Small delay to ensure perfect timing with hologram visibility
            task.wait(0.2)
            -- Teleport model from off-screen exactly when hologram is fully visible
            if PrimaryPart and originalCFrame then
                PrimaryPart.CFrame = originalCFrame
            else
                Model:SetPrimaryPartCFrame(SpawnPoint.CFrame + Vector3.new(0, 5, 0))
            end
        end,
        onDone = function()
            -- Start idle animation as the hologram starts to fade out
            local track = getCachedTrack(Model, "Idle")
            if track then
                pcall(function() track:Play() end)
            else
                track = BattleSystem:PlayCreatureAnimation(Model, "Idle")
            end
            if track then
                if IsPlayer then
                    PlayerIdleTrack = track
                else
                    FoeIdleTrack = track
                end
            end
            
            -- Slide UI back in when creature spawns
            if IsPlayer and YouUIPosition then
                local youRef = YouUI or (BattleUI and BattleUI:FindFirstChild("You"))
                if youRef then
                    slideUIIn(youRef, YouUIPosition)
                end
            elseif not IsPlayer and FoeUIPosition then
                slideUIIn(FoeUI, FoeUIPosition)
            end
            
            -- If this is the player's spawn as part of a switch, emit deferred "Go X!" now
            if IsPlayer and CurrentBattle and CurrentBattle.PendingGoMessage then
                DBG:print("BATTLE: Showing Go message (hologram):", CurrentBattle.PendingGoMessage)
                BattleSystem:ShowBattleMessage(CurrentBattle.PendingGoMessage)
                CurrentBattle.PendingGoMessage = nil

                -- For forced switches, ensure battle options are shown after the "Go!" message
                if CurrentBattle and CurrentBattle.SwitchMode == "Forced" then
                    DBG:print("BATTLE: Setting up battle options callback after Go message (hologram)")
                    BattleSystem:OnBattleMessagesDrained(function()
                        DBG:print("BATTLE: Go message drained, showing battle options")
                        BattleSystem:StartNextTurn()
                    end)
                end
            elseif IsPlayer and CurrentBattle and CurrentBattle.SwitchMode == "Forced" then
                -- No "Go!" message, but still need to show battle options for forced switch
                DBG:print("BATTLE: No Go message, showing battle options immediately (hologram)")
                BattleSystem:StartNextTurn()
            end

            DBG:print("Creature spawned with hologram effect:", CreatureData.Name, "Shiny:", CreatureData.Shiny)
            -- Clear pending spawn flag so enemy can act
            if IsPlayer and CurrentBattle then
                CurrentBattle.SwitchSpawnPending = nil
            end
        end
    })
end

-- Play animation on creature model
function BattleSystem:PlayCreatureAnimation(Model, AnimationName)
	local Animations = Model and Model:FindFirstChild("Animations")
	if not (Model and Animations) then
		DBG:warn("No Animations folder found in creature model:", Model and Model.Name)
		return nil
	end
	local Animation = Animations:FindFirstChild(AnimationName)
	if not Animation then
		DBG:warn("Animation not found:", AnimationName, "in creature model:", Model.Name)
		return nil
	end
	-- Prefer Animator over Humanoid:LoadAnimation
    local Animator = getAnimator(Model)
    if not Animator then return nil end
    -- Use cache if exists; otherwise load and store
    local cached = getCachedTrack(Model, AnimationName)
    local track = cached
    if not track then
        track = Animator:LoadAnimation(Animation)
        if AnimationName == "Idle" then
            track.Priority = Enum.AnimationPriority.Idle
        else
            track.Priority = Enum.AnimationPriority.Action
        end
        AnimationCache[Model] = AnimationCache[Model] or {}
        AnimationCache[Model][AnimationName] = track
    end
	-- Set priority for layering
	if AnimationName == "Idle" then
		track.Priority = Enum.AnimationPriority.Idle
	else
		track.Priority = Enum.AnimationPriority.Action
	end
    pcall(function()
        track:Play()
    end)
	DBG:print("Playing animation:", AnimationName, "on creature:", Model.Name)
	return track
end

-- Level UI System (Client-side display only)
-- Duplicate XP functions removed - using the ones at the top of the file



-- Play effectiveness sound based on damage effectiveness
local function playEffectivenessSound(effectiveness)
    local Sounds = game.ReplicatedStorage:WaitForChild("Audio"):WaitForChild("SFX"):WaitForChild("Hits")
    local soundName = "Normal" -- Default
    
    if effectiveness == "SuperEffective" then
        soundName = "SuperEffective"
    elseif effectiveness == "NotVeryEffective" then
        soundName = "NotVeryEffective"
    end
    
    local sound = Sounds:FindFirstChild(soundName)
    if sound then
        local soundClone = sound:Clone()
        soundClone.Parent = workspace
        soundClone:Play()
        soundClone.Ended:Connect(function()
            soundClone:Destroy()
        end)
        DBG:print("Playing effectiveness sound:", soundName)
    else
        DBG:warn("Effectiveness sound not found:", soundName)
    end
end

-- Play attack animation and invoke callback on "Hit" marker, then revert to Idle
function BattleSystem:PlayAttackWithHit(Model, onHit, onComplete, effectiveness)
    if not Model then if onHit then onHit() end return end
    -- Stop idle if it's this model
    if Model == PlayerCreatureModel and PlayerIdleTrack and PlayerIdleTrack.IsPlaying then
        pcall(function() PlayerIdleTrack:Stop(0.1) end)
    elseif Model == FoeCreatureModel and FoeIdleTrack and FoeIdleTrack.IsPlaying then
        pcall(function() FoeIdleTrack:Stop(0.1) end)
    end
    local track = getCachedTrack(Model, "Attack")
    if not track then
        DBG:warn("Attack animation missing for", Model.Name)
        if onHit then onHit() end
		return
    end
    pcall(function() track:Stop(0) track.TimePosition = 0 end)
    DBG:print("[Anim] Attack start:", Model.Name)
    -- Bind to marker if available
    local ok, signal = pcall(function() return track:GetMarkerReachedSignal("Hit") end)
    if ok and signal then
        signal:Connect(function()
            DBG:print("[Anim] Attack HIT marker reached:", Model.Name)
            -- Play effectiveness sound when hit marker is reached
            if effectiveness then
                playEffectivenessSound(effectiveness)
            end
            if onHit then onHit() end
        end)
    else
        task.delay(0.25, function()
            DBG:print("[Anim] Attack fallback HIT (no marker):", Model.Name)
            -- Play effectiveness sound for fallback hit
            if effectiveness then
                playEffectivenessSound(effectiveness)
            end
            if onHit then onHit() end
        end)
    end
    track.Stopped:Connect(function()
        local idleTrack = BattleSystem:PlayCreatureAnimation(Model, "Idle")
        if Model == PlayerCreatureModel then PlayerIdleTrack = idleTrack else FoeIdleTrack = idleTrack end
        DBG:print("[Anim] Attack end:", Model.Name)
        if onComplete then onComplete() end
    end)
    pcall(function() track:Play() end)
end

-- Play damaged animation, then revert to Idle
function BattleSystem:PlayDamaged(Model, onComplete)
    if not Model then return end
    -- Stop idle if it's this model
    if Model == PlayerCreatureModel and PlayerIdleTrack and PlayerIdleTrack.IsPlaying then
        pcall(function() PlayerIdleTrack:Stop(0.1) end)
    elseif Model == FoeCreatureModel and FoeIdleTrack and FoeIdleTrack.IsPlaying then
        pcall(function() FoeIdleTrack:Stop(0.1) end)
    end
    local track = getCachedTrack(Model, "Damaged")
    if not track then DBG:warn("Damaged animation missing for", Model.Name) return end
    pcall(function() track:Stop(0) track.TimePosition = 0 end)
    DBG:print("[Anim] Damaged start:", Model.Name)
    track.Stopped:Connect(function()
        local idleTrack = BattleSystem:PlayCreatureAnimation(Model, "Idle")
        if Model == PlayerCreatureModel then PlayerIdleTrack = idleTrack else FoeIdleTrack = idleTrack end
        DBG:print("[Anim] Damaged end:", Model.Name)
        if onComplete then onComplete() end
    end)
    pcall(function() track:Play() end)
end

-- Setup battle UI
function BattleSystem:SetupUI()
	DBG:print("Setting up battle UI")
	
	-- Update foe UI
	BattleSystem:UpdateCreatureUI(FoeUI, CurrentBattle.FoeCreature)
	
	-- Update player UI
	BattleSystem:UpdateCreatureUI(YouUI, CurrentBattle.PlayerCreature)
	
	-- Setup creature amount indicators
	BattleSystem:SetupCreatureAmountUI()
end

-- Update creature UI information
function BattleSystem:UpdateCreatureUI(UIFrame, CreatureData)
	if not CreatureData then
		DBG:warn("CreatureData is nil in UpdateCreatureUI")
		return
	end
	
	DBG:print("UpdateCreatureUI - CreatureData:", CreatureData)
	DBG:print("UpdateCreatureUI - Stats:", CreatureData.Stats)
	DBG:print("UpdateCreatureUI - MaxStats:", CreatureData.MaxStats)
	
	-- Early guard against incomplete creature data during swapping
	if not CreatureData.Stats or not CreatureData.MaxStats then
		DBG:warn("UpdateCreatureUI called on incomplete creature data!")
		-- Re-fetch from Current Battle if possible
		if CurrentBattle and CurrentBattle.PlayerCreature and CurrentBattle.PlayerCreature.MaxStats then
			DBG:print("Re-loading MaxStats missing fields from CurrentBattle PlayerCreature")
			if not CreatureData.MaxStats then
				CreatureData.MaxStats = CurrentBattle.PlayerCreature.MaxStats  -- Read fresh reference
			end
			DBG:print("Stats fixed:", CreatureData.Stats ~= nil, "MaxStats restored:", CreatureData.MaxStats ~= nil)
		end
	end
	
	local CreatureName = UIFrame:FindFirstChild("CreatureName")
	local Level = UIFrame:FindFirstChild("Level")
	local HPBar = UIFrame:FindFirstChild("HPBar")
	local HPAmountLabel = HPBar and HPBar:FindFirstChild("HPAmount")
    local Gender = UIFrame:FindFirstChild("Gender") or UIFrame:FindFirstChild("GenderIcon")
	
	-- Update creature name (use nickname if available)
	if CreatureName then
		local displayName = CreatureData.Nickname or CreatureData.Name or "Unknown"
		CreatureName.Text = displayName
	end
	
	-- Update level
	if Level then
		Level.Text = "Lv." .. (CreatureData.Level or 1)
	end
	
	-- Update HP text using the correct path: HPBar.HPAmount.Text
	if HPAmountLabel and CreatureData.Stats and CreatureData.MaxStats then
		local currentHP = CreatureData.Stats.HP
		local maxHP = CreatureData.MaxStats.HP
		if HPAmountLabel:IsA("TextLabel") then
			HPAmountLabel.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
		elseif HPAmountLabel:FindFirstChild("Text") then
			HPAmountLabel:FindFirstChild("Text").Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
		end
		DBG:print("Updated HP label:", currentHP .. "/" .. maxHP)
	else
		DBG:warn("HP label update failed - HPAmountLabel:", HPAmountLabel, "Stats:", CreatureData.Stats, "MaxStats:", CreatureData.MaxStats)
	end
	
	-- Update gender icon (using same method as Party UI)
    if Gender and CreatureData.Gender ~= nil then
		-- Set gender icon using ImageRectOffset (same as Party UI)
		if CreatureData.Gender == 0 then
			-- Male icon
			Gender.ImageRectOffset = Vector2.new(510, 75)
		elseif CreatureData.Gender == 1 then
			-- Female icon  
			Gender.ImageRectOffset = Vector2.new(0, 75)
		end
		Gender.Visible = true
	else
		if Gender then
			Gender.Visible = false
		end
	end
	
	-- Update CreatureType frame color and text based on creature type
	local TypeFrame = UIFrame:FindFirstChild("CreatureType")
	if TypeFrame then
		local TypeText = TypeFrame:FindFirstChild("TypeText")
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
		local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
		local typeName = nil
		-- Prefer direct type on CreatureData; fallback to species base type
		local typeRef = CreatureData.Type or (CreatureData.Name and Creatures[CreatureData.Name] and Creatures[CreatureData.Name].Type)
		if typeRef then
			if type(typeRef) == "table" then
				-- Could be array of names or array of type tables
				local first = typeRef[1]
				if typeof(first) == "string" then
					typeName = first
				elseif type(first) == "table" then
					for tName, tData in pairs(TypesModule) do
						if tData == first then typeName = tName break end
					end
				end
			end
		end
		if typeName and TypesModule[typeName] then
			local color = TypesModule[typeName].uicolor
			TypeFrame.BackgroundColor3 = color
			local stroke = TypeFrame:FindFirstChild("UIStroke")
			if stroke then
				stroke.Color = Color3.new(math.max(0, color.R * 0.6), math.max(0, color.G * 0.6), math.max(0, color.B * 0.6))
			end
			if TypeText and TypeText:IsA("TextLabel") then
				TypeText.Text = typeName
			end
		else
			if TypeText and TypeText:IsA("TextLabel") then
				TypeText.Text = "Unknown"
			end
		end
	end

    -- Update HP bar with animation
    if CreatureData.Stats and CreatureData.MaxStats then
        local isPlayerUI = (UIFrame == YouUI)
        -- If deferring player's HP update until foe "Hit", skip now
        if not (isPlayerUI and CurrentBattle and CurrentBattle.DeferPlayerHPUntilHit) then
            BattleSystem:UpdateHPBar(UIFrame, CreatureData.Stats.HP, CreatureData.MaxStats.HP, isPlayerUI)
        end
	end
end

-- Setup creature amount indicators
function BattleSystem:SetupCreatureAmountUI()
	-- This would clone the template for each creature in the party
	-- For now, just show the basic UI
	DBG:print("Setting up creature amount UI")
end

-- Wait for creature animations to be playing (only foe for wild encounters)
function BattleSystem:WaitForCreatureAnimations()
	DBG:print("Waiting for creature animations to start playing")
	
	-- For wild encounters, only wait for foe animation since player is spawned later
	local maxWaitTime = 2 -- Maximum wait time in seconds
	local startTime = tick()
	
	while tick() - startTime < maxWaitTime do
		local foeAnimating = false
		
		-- Check if foe creature is animating using track.IsPlaying
		if FoeIdleTrack and FoeIdleTrack.IsPlaying then
			foeAnimating = true
			DBG:print("Foe animation check: FoeIdleTrack is playing")
		elseif FoeCreatureModel then
			local Humanoid = FoeCreatureModel:FindFirstChildOfClass("Humanoid")
			if Humanoid then
				local tracks = Humanoid:GetPlayingAnimationTracks()
				foeAnimating = tracks[1] ~= nil and tracks[1].IsPlaying == true
				DBG:print("Foe animation check: Humanoid tracks found:", #tracks, "playing:", foeAnimating)
			else
				DBG:print("Foe animation check: No Humanoid found in FoeCreatureModel")
			end
		else
			DBG:print("Foe animation check: No FoeCreatureModel found")
		end
		
		-- If foe is animating, we're good to go (player will be spawned later in intro)
		if foeAnimating then
			DBG:print("Foe creature animation is playing, proceeding")
			return
		end
		
		task.wait(0.1)
	end
	
	DBG:warn("Timeout waiting for foe creature animation, proceeding anyway")
end

-- Wild encounter intro sequence
function BattleSystem:WildEncounterIntro()
	DBG:print("Starting wild encounter intro")
	
    -- Hard stop any idle camera cycling and tweens before intro transitions
    BattleSystem:StopCameraCycle()
    if ActiveCameraTween then
        pcall(function() ActiveCameraTween:Cancel() end)
        ActiveCameraTween = nil
    end

	-- Set camera to FoeZoomOut position immediately (no animation)
	BattleSystem:SetCameraPosition("FoeZoomOut", 1)

	-- Exclamation mark animation is now handled centrally in StartBattle
	
	-- Show battle message and then shiny callout if applicable
	BattleSystem:ShowBattleMessage(CurrentBattle.Message)
	if CurrentBattle and CurrentBattle.FoeCreature and CurrentBattle.FoeCreature.Shiny then
		BattleSystem:ShowBattleMessage("It's sparkling!")
	end
	BattleSystem:AddHighlightToCreature(FoeCreatureModel)
	
	-- Fade out exclamation mark as soon as highlight is created on foe
	local UIFunctions = require(script.Parent.Parent.UI:WaitForChild("UIFunctions"))
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:FindFirstChild("GameUI")
	local ExclamationMark = GameUI and GameUI:FindFirstChild("ExclamationMark")
	if ExclamationMark then
		UIFunctions:FadeOutExclamationMark(ExclamationMark)
		DBG:print("Exclamation mark fade out completed in WildEncounterIntro")
	end
    task.wait(1.5)
	BattleSystem:AnimateFoeZoomOut()
	
	-- Then move to wide view (Default)
	BattleSystem:MoveCameraToWideView()

	-- After zoom-out completes and wide view is set, spawn player's creature with announcement
	local Essentials = BattleScene:FindFirstChild("Essentials")
	local PlayerSpawn = Essentials and Essentials:FindFirstChild("PlayerCreatureSpawn")
	if PlayerSpawn and CurrentBattle and CurrentBattle.PlayerCreature then
		local creatureName = CurrentBattle.PlayerCreature.Nickname or CurrentBattle.PlayerCreature.Name or "Your creature"
		BattleSystem:ShowBattleMessage("Go " .. creatureName .. "!")
		BattleSystem:SpawnCreatureModel(CurrentBattle.PlayerCreature, PlayerSpawn, true)
		updateLevelUI(CurrentBattle.PlayerCreature, false)
	end
    -- Ensure any intro messages finish before options and camera cycle start
    BattleSystem:WaitForMessages()
    
    -- Wait for player creature model to fully spawn before showing options
    local maxWait = 3 -- 3 second timeout
    local startTime = tick()
    while not PlayerCreatureModel and (tick() - startTime) < maxWait do
        task.wait(0.1)
    end
    
    -- Additional small wait to ensure animations have started
    task.wait(0.2)
    
    BattleSystem:ShowBattleOptions()
    task.spawn(function()
        BattleSystem:StartCameraCycle()
    end)
end

-- Trainer battle intro sequence
function BattleSystem:TrainerBattleIntro()
	DBG:print("Starting trainer battle intro")
	
    -- Hard stop any idle camera cycling and tweens before intro transitions
    BattleSystem:StopCameraCycle()
    if ActiveCameraTween then
        pcall(function() ActiveCameraTween:Cancel() end)
        ActiveCameraTween = nil
    end
	
	-- Position camera in front of trainer (for now, use foe spawn point)
	BattleSystem:PositionCameraInFrontOfFoe()

	-- Exclamation mark animation is now handled centrally in StartBattle
	
	-- Show battle message
	BattleSystem:ShowBattleMessage(CurrentBattle.Message)
	
	-- Wait
	task.wait(0.5)
	
	-- Move to wide view
	BattleSystem:MoveCameraToWideView()

	-- After intro completes and wide view is set, spawn player's creature with announcement
	local Essentials = BattleScene:FindFirstChild("Essentials")
	local PlayerSpawn = Essentials and Essentials:FindFirstChild("PlayerCreatureSpawn")
	if PlayerSpawn and CurrentBattle and CurrentBattle.PlayerCreature then
		local creatureName = CurrentBattle.PlayerCreature.Nickname or CurrentBattle.PlayerCreature.Name or "Your creature"
		BattleSystem:ShowBattleMessage("Go " .. creatureName .. "!")
		BattleSystem:SpawnCreatureModel(CurrentBattle.PlayerCreature, PlayerSpawn, true)
		updateLevelUI(CurrentBattle.PlayerCreature, false)
	end
    -- Ensure any intro messages finish before options and camera cycle start
    BattleSystem:WaitForMessages()
    
    -- Wait for player creature model to fully spawn before showing options
    local maxWait = 3 -- 3 second timeout
    local startTime = tick()
    while not PlayerCreatureModel and (tick() - startTime) < maxWait do
        task.wait(0.1)
    end
    
    -- Additional small wait to ensure animations have started
    task.wait(0.2)
    
    BattleSystem:ShowBattleOptions()
    task.spawn(function()
        BattleSystem:StartCameraCycle()
    end)
end

-- Set camera to position from workspace parts
function BattleSystem:SetCameraPosition(positionName, index)
	index = index or 1
	
	DBG:print("=== SetCameraPosition called ===")
	DBG:print("Position name:", positionName)
	DBG:print("Index:", index)
	
	if not BattleScene then
		DBG:warn("No BattleScene found")
		return false
	end
	
	-- Get camera points from the battle scene
	local CameraPoints = BattleScene:FindFirstChild("CameraPoints")
	if not CameraPoints then
		DBG:warn("CameraPoints folder not found in battle scene")
		return false
	end
	
	-- Handle Default as a single part
	if positionName == "Default" then
		local DefaultPart = CameraPoints:FindFirstChild("Default")
		if not DefaultPart then
			DBG:warn("Default camera part not found")
			return false
		end
		
		DBG:print("Found Default camera part:", DefaultPart.Name)
		DBG:print("Default camera CFrame:", DefaultPart.CFrame)
		
		-- Set camera to the default position
		Camera.CFrame = DefaultPart.CFrame
		DBG:print("Camera set to Default position")
		return true
	end
	
	-- Handle other positions with folders
	local PositionFolder = CameraPoints:FindFirstChild(positionName)
	if not PositionFolder then
		DBG:warn("Camera position folder not found:", positionName)
		return false
	end
	
	local CameraPart = PositionFolder:FindFirstChild(tostring(index))
	if not CameraPart then
		DBG:warn("Camera part not found:", positionName, index)
		return false
	end
	
	DBG:print("Found camera part:", CameraPart.Name)
	DBG:print("Camera part CFrame:", CameraPart.CFrame)
	
	-- Set camera to the part's position
	Camera.CFrame = CameraPart.CFrame
	
	DBG:print("Camera position set successfully:", positionName, index and "[" .. index .. "]" or "")
	return true
end

-- Animate camera transition between two positions
function BattleSystem:AnimateCameraTransition(positionName, duration)
	duration = duration or 3
	
	DBG:print("=== AnimateCameraTransition called ===")
	DBG:print("Position name:", positionName)
	DBG:print("Duration:", duration)
	
	if not BattleScene then
		DBG:warn("No BattleScene found")
		return false
	end
	
	-- Get camera points from the battle scene
	local CameraPoints = BattleScene:FindFirstChild("CameraPoints")
	if not CameraPoints then
		DBG:warn("CameraPoints folder not found in battle scene")
		return false
	end
	
	-- Handle Default as a single part (instant, no animation)
	if positionName == "Default" then
		local DefaultPart = CameraPoints:FindFirstChild("Default")
		if not DefaultPart then
			DBG:warn("Default camera part not found")
			return false
		end
		
		DBG:print("Setting camera to Default position (instant)")
		
		-- Set camera instantly to Default position
		Camera.CFrame = DefaultPart.CFrame
		
		-- Wait for duration (for consistency with other functions)
		task.wait(duration)
		
		DBG:print("Camera set to Default position (instant)")
		return true
	end
	
	-- Handle other positions with animation from 1 to 2
	local PositionFolder = CameraPoints:FindFirstChild(positionName)
	if not PositionFolder then
		DBG:warn("Camera position folder not found:", positionName)
		return false
	end
	
	local Part1 = PositionFolder:FindFirstChild("1")
	local Part2 = PositionFolder:FindFirstChild("2")
	
	if not Part1 or not Part2 then
		DBG:warn("Camera parts 1 or 2 not found for:", positionName)
		return false
	end
	
	-- Set initial position
	Camera.CFrame = Part1.CFrame
	DBG:print("Set camera to position 1, starting animation to position 2")
	
	-- Create camera tween using TweenService
	local CameraTweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    -- Stop any existing camera tween before starting a new one
    if ActiveCameraTween then
        pcall(function() ActiveCameraTween:Cancel() end)
        ActiveCameraTween = nil
    end
	local CameraTween = TweenService:Create(Camera, CameraTweenInfo, {CFrame = Part2.CFrame})
    ActiveCameraTween = CameraTween
	
	-- Start camera animation
	CameraTween:Play()
	
	-- Wait for camera animation to complete
	CameraTween.Completed:Wait()
    ActiveCameraTween = nil
	
	DBG:print("Camera animation completed to position 2")
	return true
end

-- Position camera in front of foe creature (using FoeZoomOut animation)
function BattleSystem:PositionCameraInFrontOfFoe()
	BattleSystem:AnimateCameraTransition("FoeZoomOut", 3)
	DBG:print("Positioned camera in front of foe creature")
end

-- Animate camera from FoeZoomOut part 1 to part 2
function BattleSystem:AnimateFoeZoomOut()
	DBG:print("Animating FoeZoomOut from part 1 to part 2")
	
	if not BattleScene then
		DBG:warn("No BattleScene found")
		return false
	end
	
	-- Get camera points from the battle scene
	local CameraPoints = BattleScene:FindFirstChild("CameraPoints")
	if not CameraPoints then
		DBG:warn("CameraPoints folder not found in battle scene")
		return false
	end
	
	local FoeZoomOutFolder = CameraPoints:FindFirstChild("FoeZoomOut")
	if not FoeZoomOutFolder then
		DBG:warn("FoeZoomOut folder not found")
		return false
	end
	
	local Part1 = FoeZoomOutFolder:FindFirstChild("1")
	local Part2 = FoeZoomOutFolder:FindFirstChild("2")
	
	if not Part1 or not Part2 then
		DBG:warn("FoeZoomOut parts 1 or 2 not found")
		return false
	end
	
	-- Camera should already be at part 1, animate to part 2
	local CameraTweenInfo = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    -- Stop any existing camera tween before starting a new one
    if ActiveCameraTween then
        pcall(function() ActiveCameraTween:Cancel() end)
        ActiveCameraTween = nil
    end
    local CameraTween = TweenService:Create(Camera, CameraTweenInfo, {CFrame = Part2.CFrame})
    ActiveCameraTween = CameraTween
	
	-- Start camera animation
	CameraTween:Play()
	
	-- Wait for camera animation to complete
    CameraTween.Completed:Wait()
    ActiveCameraTween = nil
	
	DBG:print("FoeZoomOut animation completed to part 2")
	return true
end

-- Move camera to wide view (using Default position) - INSTANT
function BattleSystem:MoveCameraToWideView()
	BattleSystem:SetCameraPosition("Default")
	DBG:print("Moved camera to wide view (instant)")
end

-- Add highlight to creature and start fade out immediately
function BattleSystem:AddHighlightToCreature(Model)
	if not Model then return end
	
	local Highlight = Instance.new("Highlight")
	Highlight.Name = "BattleHighlight"
	Highlight.OutlineTransparency = 1
	Highlight.FillTransparency = 0 -- Start at 0 (fully visible)
	Highlight.FillColor = Color3.new(0, 0, 0)
	Highlight.Parent = Model
	
	DBG:print("Added highlight to creature:", Model.Name)
	
	-- Start fade out immediately and independently
	local HighlightTweenInfo = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local HighlightTween = TweenService:Create(Highlight, HighlightTweenInfo, {FillTransparency = 1})
	task.delay(0.75, function()
	HighlightTween:Play()
	end)
	
	-- Clean up highlight when fade completes
	HighlightTween.Completed:Connect(function()
		Highlight:Destroy()
		DBG:print("Highlight fade out completed and destroyed")
	end)
end

-- Fade out highlight
function BattleSystem:FadeOutHighlight()
	if not FoeCreatureModel then return end
	
	local Highlight = FoeCreatureModel:FindFirstChild("BattleHighlight")
	if not Highlight then return end
	
	local TweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local Tween = TweenService:Create(Highlight, TweenInfo, {FillTransparency = 1})
	
	Tween:Play()
	Tween.Completed:Connect(function()
		Highlight:Destroy()
	end)
	
	DBG:print("Faded out highlight")
end

-- Show battle message with smooth animations and typewriter effect
-- Queue messages to ensure strict order and no overlap
local BattleMessageQueue = {}
local BattleMessageHistory = {}
local ShowingBattleMessage = false
local BattleMessageDrainCallbacks = {}
local SuppressPostFaintMessages = false
-- Removed global dedupe; server should avoid duplicates. Client will only guard
-- against back-to-back duplicates inside a single enemy action sequence.

local function ShowBattleMessageNow(Message)
	-- Add message to history
	table.insert(BattleMessageHistory, Message)
	
	DBG:print("Showing battle message:", Message)
	local MessageLabel = BattleNotification:FindFirstChild("Message")
	if not MessageLabel then
		DBG:warn("Message label not found in BattleNotification")
		return
	end
	BattleNotification.Position = UDim2.new(0, 0, 1, 0)
	BattleNotification.Visible = true
	MessageLabel.Text = Message
	
	-- Check if this is an XP message and trigger animation
	local isXPMessage = CurrentBattle and CurrentBattle.PlayerCreature and string.find(Message, "XP", 1, true)
	local creatureData = isXPMessage and CurrentBattle.PlayerCreature or nil
	
	local SlideInInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	local SlideInTween = TweenService:Create(BattleNotification, SlideInInfo, {Position = UDim2.new(0, 0, 0.527, 0)})
	SlideInTween:Play()
	local Length = #Message
	MessageLabel.MaxVisibleGraphemes = 0
	task.wait(0.25)
	for count = 1, Length do
		MessageLabel.MaxVisibleGraphemes = count
		task.wait(0.012)
	end
	MessageLabel.MaxVisibleGraphemes = -1
	
	-- Trigger XP animation after typing is complete but before the wait period
	if isXPMessage and creatureData then
		DBG:print("XP message typing complete, triggering level UI animation")
		updateLevelUI(creatureData, true) -- Tween for XP gain
	end
	
	task.wait(0.55)
	local SlideOutInfo = TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	local SlideOutTween = TweenService:Create(BattleNotification, SlideOutInfo, {Position = UDim2.new(0, 0, 1, 0)})
	SlideOutTween:Play()
	
	-- Trigger faint tween exactly when the faint message is displayed
    if type(Message) == "string" then
		if string.find(Message, "fainted!", 1, true) then
            SuppressPostFaintMessages = true
			-- Determine whose message it is by prefix keyword
			-- We only tween once per side; reset flags when a new battle starts elsewhere
			if CurrentBattle and CurrentBattle.FoeCreature and string.find(Message, CurrentBattle.FoeCreature.Name or "", 1, true) then
                if not FoeFaintTweened and FoeCreatureModel then
					FoeFaintTweened = true
					
					-- Slide Foe UI out to the right
					slideUIOut(FoeUI, "right")
					
					-- Use hologram fade-out effect instead of size tween
                    HologramSpawnEffect:CreateFadeOut(FoeCreatureModel, function()
                        -- Hide/remove foe model after faint effect completes
                        pcall(function()
                            if FoeCreatureModel and FoeCreatureModel.Parent then
                                FoeCreatureModel:Destroy()
                                FoeCreatureModel = nil
                            end
                        end)
                    end)
				end
			elseif CurrentBattle and CurrentBattle.PlayerCreature then
				local ourName = CurrentBattle.PlayerCreature.Nickname or CurrentBattle.PlayerCreature.Name or "Your creature"
				if string.find(Message, ourName, 1, true) then
                    if not PlayerFaintTweened and PlayerCreatureModel then
						PlayerFaintTweened = true
						
						-- Slide You UI out to the left
						slideUIOut(YouUI, "left")
						
						-- Use hologram fade-out effect instead of size tween
                        HologramSpawnEffect:CreateFadeOut(PlayerCreatureModel, function()
                            -- Mark fainted slot so Party UI forbids switching back
                            if CurrentBattle and CurrentBattle.PlayerCreatureIndex then
                                MarkSlotFainted(CurrentBattle.PlayerCreatureIndex)
                            end
                            -- Remove the player model after faint
                            pcall(function()
                                if PlayerCreatureModel and PlayerCreatureModel.Parent then
                                    PlayerCreatureModel:Destroy()
                                    PlayerCreatureModel = nil
                                end
                            end)
                        end)
					end
				end
			end
		end
	end
	task.wait(0.55)
	BattleNotification.Visible = false
end

local function ProcessBattleMessageQueue()
	if ShowingBattleMessage then return end
	ShowingBattleMessage = true
    while #BattleMessageQueue > 0 do
		local msg = table.remove(BattleMessageQueue, 1)
		ShowBattleMessageNow(msg)
	end
	ShowingBattleMessage = false
    -- Notify all on-drain callbacks
    local callbacks = BattleMessageDrainCallbacks
    BattleMessageDrainCallbacks = {}
    for _, cb in ipairs(callbacks) do
        local ok, err = pcall(cb)
        if not ok then
            DBG:warn("Battle message drain callback error:", err)
        end
    end
    SuppressPostFaintMessages = false
end

function BattleSystem:ShowBattleMessage(Message)
    if SuppressPostFaintMessages and type(Message) == "string" then
        if string.find(Message, "flinched and couldn't move!", 1, true) or string.find(Message:lower(), "critical", 1, true) then
            return
        end
    end
    table.insert(BattleMessageQueue, Message)
	task.spawn(ProcessBattleMessageQueue)
end

function BattleSystem:OnBattleMessagesDrained(callback)
    table.insert(BattleMessageDrainCallbacks, callback)
    task.spawn(ProcessBattleMessageQueue)
    
    -- If there are no messages in queue and none showing, execute callbacks immediately
    if not ShowingBattleMessage and #BattleMessageQueue == 0 then
        task.spawn(function()
            local callbacks = BattleMessageDrainCallbacks
            BattleMessageDrainCallbacks = {}
            for _, cb in ipairs(callbacks) do
                local ok, err = pcall(cb)
                if not ok then
                    DBG:warn("BATTLE: Message drain callback error:", err)
                end
            end
        end)
    end
end

-- Block until the current battle message queue fully drains
function BattleSystem:WaitForMessages()
    -- Simple yield until queue empties and no message is showing
    while ShowingBattleMessage or (#BattleMessageQueue > 0) do
        RunService.Heartbeat:Wait()
    end
end

-- Toggle move options with sliding animation
function BattleSystem:MoveOptionsToggle(show, _skipCross)
    if UITransitionInProgress and not show then
        -- allow hide during transition but cancel in-flight tween first
    elseif UITransitionInProgress then
        return
    end
    
    -- Cancel any existing tween
    if ActiveMoveOptionsTween then
        pcall(function() ActiveMoveOptionsTween:Cancel() end)
        ActiveMoveOptionsTween = nil
    end
    
    if show == true then
        UITransitionInProgress = true
        if not _skipCross then
            BattleSystem:BattleOptionsToggle(false, true)
        end
		MoveOptions.Visible = true
		MoveOptions.Position = UDim2.new(1.3, 0, 0.165, 0)
        local SlideInInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
        ActiveMoveOptionsTween = TweenService:Create(MoveOptions, SlideInInfo, {Position = UDim2.new(0.778, 0, 0.165, 0)})
        ActiveMoveOptionsTween.Completed:Connect(function()
            ActiveMoveOptionsTween = nil
            UITransitionInProgress = false
        end)
        ActiveMoveOptionsTween:Play()
		-- Update move buttons with current creature's moves
		BattleSystem:UpdateMoveButtons()
	else
		-- Hide
        local SlideOutInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
        ActiveMoveOptionsTween = TweenService:Create(MoveOptions, SlideOutInfo, {Position = UDim2.new(1.3, 0, 0.165, 0)})
        ActiveMoveOptionsTween.Completed:Connect(function()
			MoveOptions.Visible = false
            ActiveMoveOptionsTween = nil
		end)
        ActiveMoveOptionsTween:Play()
	end
end

-- Toggle battle options with sliding animation
function BattleSystem:BattleOptionsToggle(show, _skipCross)
    if UITransitionInProgress and not show then
        -- allow hide during transition but cancel in-flight tween first
    elseif UITransitionInProgress then
        return
    end
    
    -- Cancel any existing tween
    if ActiveBattleOptionsTween then
        pcall(function() ActiveBattleOptionsTween:Cancel() end)
        ActiveBattleOptionsTween = nil
    end
    
    if show == true then
        UITransitionInProgress = true
        if not _skipCross then
            BattleSystem:MoveOptionsToggle(false, true)
        end
		BattleOptions.Visible = true
		BattleOptions.Position = UDim2.new(1.3, 0, 0.165, 0)
        local SlideInInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
        ActiveBattleOptionsTween = TweenService:Create(BattleOptions, SlideInInfo, {Position = UDim2.new(0.778, 0, 0.165, 0)})
        ActiveBattleOptionsTween.Completed:Connect(function()
            ActiveBattleOptionsTween = nil
            UITransitionInProgress = false
        end)
        ActiveBattleOptionsTween:Play()
        -- Do not start/stop the camera cycle here; it should run until a move is actually used
		-- Connect battle option buttons
		BattleSystem:ConnectBattleOptionButtons()
	else
		-- Hide
        local SlideOutInfo = TweenInfo.new(0.35, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
        ActiveBattleOptionsTween = TweenService:Create(BattleOptions, SlideOutInfo, {Position = UDim2.new(1.3, 0, 0.165, 0)})
        ActiveBattleOptionsTween.Completed:Connect(function()
			BattleOptions.Visible = false
            ActiveBattleOptionsTween = nil
		end)
        ActiveBattleOptionsTween:Play()
	end
end

-- Connect battle option buttons
function BattleSystem:ConnectBattleOptionButtons()
	local FightButton = BattleOptions:FindFirstChild("Fight")
	local RunButton = BattleOptions:FindFirstChild("Run")
	local CreaturesButton = BattleOptions:FindFirstChild("Creatures")
	local BagButton = BattleOptions:FindFirstChild("Bag")
	
	-- Use UIFunctions:NewButton for proper button setup
	if FightButton then
		-- Set OGSize attribute for animations to work
		FightButton:SetAttribute("OGSize", FightButton.Size)
		
		UIFunctions:NewButton(
			FightButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
			BattleSystem:MoveOptionsToggle(true)
			end
		)
	end
	
	if RunButton then
		-- Set OGSize attribute for animations to work
		RunButton:SetAttribute("OGSize", RunButton.Size)
		
		UIFunctions:NewButton(
			RunButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				DBG:print("Attempting to run from battle!!!")
			BattleSystem:RunFromBattle()
			end
		)
	end
	
	if CreaturesButton then
		UIFunctions:NewButton(
			CreaturesButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:OpenCreaturesMenu()
			end
		)
	end
	
	if BagButton then
		UIFunctions:NewButton(
			BagButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:OpenBagMenu()
			end
		)
	end
end

-- Show battle options (wrapper function)
function BattleSystem:ShowBattleOptions()
	DBG:print("BATTLE: Showing battle options")
	BattleSystem:BattleOptionsToggle(true)
end

-- Show move options (wrapper function)
function BattleSystem:ShowMoveOptions()
	DBG:print("Showing move options")
	BattleSystem:MoveOptionsToggle(true)
end

-- Update move buttons
function BattleSystem:UpdateMoveButtons()
	local CreatureData = CurrentBattle.PlayerCreature
	local Moves = CreatureData.CurrentMoves or {}
    local TypesModule = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
    
	-- Get MovesModule for move name lookup
	local MovesModule = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
    
    local function getTypeNames(typeRef)
        local names = {}
        if type(typeRef) == "table" then
            for _, t in ipairs(typeRef) do
                if type(t) == "string" then table.insert(names, t)
                elseif type(t) == "table" then
                    for typeName, data in pairs(TypesModule) do
                        if data == t then table.insert(names, typeName) break end
                    end
                end
            end
        end
        return names
    end
    
    local foeTypes = {}
    if CurrentBattle.FoeCreature and CurrentBattle.FoeCreature.Type then
        foeTypes = getTypeNames(CurrentBattle.FoeCreature.Type)
    end
	
	for i = 1, 4 do
		local MoveButton = MoveOptions:FindFirstChild("Move" .. i)
		if MoveButton then
			local MoveName = MoveButton:FindFirstChild("MoveName")
			local MoveType = MoveButton:FindFirstChild("MoveType")
			
			if i <= #Moves and Moves[i] then
				MoveButton.Visible = true
				
				-- Get move name by matching move properties (same as Party UI)
				local moveName = "Unknown Move"
				local moveType = nil
				local currentMove = Moves[i]
				
				-- Helper function to compare type objects by their uicolor
				local function typesEqual(type1, type2)
					if not type1 or not type2 then return false end
					return type1.uicolor == type2.uicolor
				end
				
				-- Match move properties against MovesModule
				for moveKey, moveData in pairs(MovesModule) do
					local powerMatch = moveData.BasePower == currentMove.BasePower
					local accuracyMatch = moveData.Accuracy == currentMove.Accuracy
					local priorityMatch = moveData.Priority == currentMove.Priority
					local typeMatch = typesEqual(moveData.Type, currentMove.Type)
					
					if powerMatch and accuracyMatch and priorityMatch and typeMatch then
						moveName = moveKey
						moveType = moveData.Type
						break
					end
				end
				
				-- Update move name
				if MoveName then
					MoveName.Text = moveName
				end
				
                -- Update move type
				if MoveType then
					if moveType then
						-- Find type name from type object
                        for typeName, typeData in pairs(TypesModule) do
							if typeData == moveType then
								MoveType.Text = typeName
								break
							end
						end
					else
						MoveType.Text = "Normal"
					end
				end
                
                -- Color move button and its stroke to the move type color
                do
                    local typeNameForColor = MoveType and MoveType.Text or nil
                    local typeData = typeNameForColor and TypesModule[typeNameForColor]
                    if typeData then
                        MoveButton.BackgroundColor3 = typeData.uicolor
                        local stroke = MoveButton:FindFirstChild("UIStroke")
                        if stroke then
                            local c = typeData.uicolor
                            stroke.Color = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
                        end
                    end
                end
                
                -- Toggle effectiveness icons
                local se = MoveButton:FindFirstChild("SuperEffective")
                local nve = MoveButton:FindFirstChild("NotVeryEffective")
                if se then se.Visible = false end
                if nve then nve.Visible = false end
                if moveType and #foeTypes > 0 then
                    local moveTypeName = nil
                    for typeName, typeData in pairs(TypesModule) do
                        if typeData == moveType then moveTypeName = typeName break end
                    end
                    local moveData = moveTypeName and TypesModule[moveTypeName]
                    if moveData then
                        local result = "neutral"
                        for _, foeTypeName in ipairs(foeTypes) do
                            if table.find(moveData.strongTo, foeTypeName) then result = "se" break end
                            if table.find(moveData.resist, foeTypeName) then if result ~= "se" then result = "nve" end end
                            if table.find(moveData.immuneTo, foeTypeName) then if result ~= "se" then result = "nve" end end
                        end
                        if result == "se" and se then se.Visible = true end
                        if result == "nve" and nve then nve.Visible = true end
                    end
				end
			else
				MoveButton.Visible = false
			end
		end
	end
end

-- Run from battle with Pokemon-style escape mechanics
function BattleSystem:RunFromBattle()
	DBG:print("Player attempting to run from battle")
	
	if not CurrentBattle then
		DBG:warn("No current battle to run from")
		return
	end
	
	-- Check if this is a trainer battle (can never run - NO TURN CONSUMED)
	if CurrentBattle.Type == "Trainer" then
		BattleSystem:ShowBattleMessage("You can't run from a trainer battle!")
		-- No turn consumed for trainer battles
		return
	end
	
	-- Check if this is a static/boss encounter (can never run - NO TURN CONSUMED)
	if CurrentBattle.IsStatic or CurrentBattle.IsBoss then
		BattleSystem:ShowBattleMessage("You can't run away!")
		-- No turn consumed for static/boss battles
		return
	end
	
	-- For wild encounters, attempt escape (TURN CONSUMED)
	if CurrentBattle.Type == "Wild" then
		-- Consume player's turn
		CurrentBattle.PlayerTurnUsed = true
		DBG:print("Player turn consumed for escape attempt")
		
		-- Hide both UI options when player makes a choice
		BattleSystem:BattleOptionsToggle(false)
		BattleSystem:MoveOptionsToggle(false)
		
		-- Notify server of escape attempt - server will handle the logic
		local Events = game.ReplicatedStorage.Events
		if Events and Events.Request then
			Events.Request:InvokeServer({"AttemptEscape"})
		end
		
		-- Server will respond with either escape success or enemy turn
	end
end

-- Calculate escape chance using Pokemon formula
function BattleSystem:CalculateEscapeChance()
	if not CurrentBattle or not CurrentBattle.PlayerCreature or not CurrentBattle.FoeCreature then
		DBG:warn("Missing battle data for escape calculation")
		return false
	end
	
	local PlayerCreature = CurrentBattle.PlayerCreature
	local FoeCreature = CurrentBattle.FoeCreature
	
	-- Get speeds
	local PlayerSpeed = PlayerCreature.Stats and PlayerCreature.Stats.Speed or 0
	local FoeSpeed = FoeCreature.Stats and FoeCreature.Stats.Speed or 0
	
	-- Escape attempts counter
	local EscapeAttempts = CurrentBattle.EscapeAttempts or 0
	
	-- Pokemon escape formula: ((your_speed * 32) / (opponent_speed / 4 % 256)) + 30 * escape_attempts
	local SpeedRatio = (PlayerSpeed * 32) / ((FoeSpeed / 4) % 256)
	local EscapeBonus = 30 * EscapeAttempts
	local EscapeChance = SpeedRatio + EscapeBonus
	
	DBG:print("Escape calculation:")
	DBG:print("Player Speed:", PlayerSpeed)
	DBG:print("Foe Speed:", FoeSpeed)
	DBG:print("Speed Ratio:", SpeedRatio)
	DBG:print("Escape Attempts:", EscapeAttempts)
	DBG:print("Escape Bonus:", EscapeBonus)
	DBG:print("Total Escape Chance:", EscapeChance)
	
	-- If chance > 255, always escape
	if EscapeChance > 255 then
		DBG:print("Escape guaranteed (chance > 255)")
		return true
	end
	
	-- Otherwise, roll against 0-255
	local RandomRoll = math.random(0, 255)
	DBG:print("Random roll:", RandomRoll, "vs", EscapeChance)
	
	local Success = RandomRoll < EscapeChance
	DBG:print("Escape", Success and "successful" or "failed")
	
	return Success
end

-- Fade out exclamation mark
function BattleSystem:FadeOutExclamationMark()
	DBG:print("Fading out exclamation mark")
	
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local ExclamationMark = GameUI:WaitForChild("ExclamationMark")
	
	if ExclamationMark then
        -- Start encounter music as soon as the exclamation appears
        pcall(function() MusicManager:StartEncounterMusic() end)
		ExclamationMark.ImageTransparency = 0
		
		-- Set FOV and show UI immediately when fade starts
		Camera.FieldOfView = 50
		BattleUI.Visible = true
		DBG:print("Battle UI shown and FOV reset to 50")
		
		local FadeOutInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local FadeOutTween = TweenService:Create(ExclamationMark, FadeOutInfo, {ImageTransparency = 1})
		FadeOutTween:Play()
		
		-- Return the tween so callers can wait for it to complete
		return FadeOutTween
	else
		DBG:warn("ExclamationMark not found in GameUI")
		-- If no exclamation mark, show battle UI immediately
		BattleUI.Visible = true
		return nil
	end
end

-- Setup battle UI interactions
function BattleSystem:SetupBattleUIInteractions()
	DBG:print("Setting up battle UI interactions")
	
	-- Setup Battle Options buttons
	BattleSystem:SetupBattleOptionsButtons()
	
	-- Setup Move Options buttons
	BattleSystem:SetupMoveOptionsButtons()
	
	-- Setup HP bar animations
	BattleSystem:SetupHPBars()
end

-- Setup battle options buttons (Fight, Run, Creatures, Bag)
function BattleSystem:SetupBattleOptionsButtons()
	local FightButton = BattleOptions:FindFirstChild("Fight")
	local RunButton = BattleOptions:FindFirstChild("Run")
	local CreaturesButton = BattleOptions:FindFirstChild("Creatures")
	local BagButton = BattleOptions:FindFirstChild("Bag")
	
	-- Use UIFunctions:NewButton for proper button setup
	if FightButton then
		-- Set OGSize attribute for animations to work
		FightButton:SetAttribute("OGSize", FightButton.Size)
		
		UIFunctions:NewButton(
			FightButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:SelectMove()
			end
		)
	end
	
	if RunButton then
		-- Set OGSize attribute for animations to work
		RunButton:SetAttribute("OGSize", RunButton.Size)
		
		UIFunctions:NewButton(
			RunButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:RunFromBattle()
			end
		)
	end
	
	if CreaturesButton then
		UIFunctions:NewButton(
			CreaturesButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:OpenCreaturesMenu()
			end
		)
	end
	
	if BagButton then
		UIFunctions:NewButton(
			BagButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:OpenBagMenu()
			end
		)
	end
end

-- Setup move options buttons
function BattleSystem:SetupMoveOptionsButtons()
	local Move1Button = MoveOptions:FindFirstChild("Move1")
	local Move2Button = MoveOptions:FindFirstChild("Move2")
	local Move3Button = MoveOptions:FindFirstChild("Move3")
	local Move4Button = MoveOptions:FindFirstChild("Move4")
	local BackButton = MoveOptions:FindFirstChild("Back")
	
	-- Use UIFunctions:NewButton for proper button setup
	if Move1Button then
		UIFunctions:NewButton(
			Move1Button,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:SelectMove(1)
			end
		)
	end
	
	if Move2Button then
		UIFunctions:NewButton(
			Move2Button,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:SelectMove(2)
			end
		)
	end
	
	if Move3Button then
		UIFunctions:NewButton(
			Move3Button,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:SelectMove(3)
			end
		)
	end
	
	if Move4Button then
		UIFunctions:NewButton(
			Move4Button,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:SelectMove(4)
			end
		)
	end
	
	if BackButton then
		UIFunctions:NewButton(
			BackButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				BattleSystem:ReturnToBattleOptions()
			end
		)
	end
end

-- Setup HP bars with animations
function BattleSystem:SetupHPBars()
	-- This will be called when HP needs to be updated
	DBG:print("HP bars setup complete")
end

-- Select move (opens move options)
function BattleSystem:SelectMove(moveIndex)
	if moveIndex then
		-- Execute specific move
		BattleSystem:ExecuteMove(moveIndex)
	else
		-- Open move selection
		BattleSystem:MoveOptionsToggle(true)
	end
end

-- Execute a move
function BattleSystem:ExecuteMove(moveIndex)
	DBG:print("Executing move:", moveIndex)
	
	if not CurrentBattle or not CurrentBattle.PlayerCreature then
		DBG:warn("No battle or player creature found")
		return
	end
	
	-- Check if player turn is already used
	if CurrentBattle.PlayerTurnUsed then
		DBG:warn("Player turn already used this round")
		return
	end
	
	local PlayerCreature = CurrentBattle.PlayerCreature
	local Moves = PlayerCreature.CurrentMoves or {}
	
	if moveIndex > #Moves or not Moves[moveIndex] then
		DBG:warn("Invalid move index:", moveIndex)
		return
	end
	
    local SelectedMove = Moves[moveIndex]
    -- Resolve human-readable move name if possible
    local moveName = nil
    do
        local MovesModule = require(game.ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
        if type(SelectedMove) == "string" then
            moveName = SelectedMove
        elseif type(SelectedMove) == "table" and SelectedMove.Name then
            moveName = SelectedMove.Name
        else
            -- try to match by properties similar to UpdateMoveButtons
            local function typesEqual(type1, type2)
                if not type1 or not type2 then return false end
                return type1.uicolor == type2.uicolor
            end
            for moveKey, moveData in pairs(MovesModule) do
                local powerMatch = moveData.BasePower == SelectedMove.BasePower
                local accuracyMatch = moveData.Accuracy == SelectedMove.Accuracy
                local priorityMatch = moveData.Priority == SelectedMove.Priority
                local typeMatch = typesEqual(moveData.Type, SelectedMove.Type)
                if powerMatch and accuracyMatch and priorityMatch and typeMatch then
                    moveName = moveKey
                    break
                end
            end
        end
    end
    DBG:print("Resolved selected move name:", moveName or "Unknown")
	
	-- Consume player's turn
	CurrentBattle.PlayerTurnUsed = true
	DBG:print("Player turn consumed for move execution")
	
	-- Hide both UI options when player makes a choice
	BattleSystem:MoveOptionsToggle(false)
	BattleSystem:BattleOptionsToggle(false)
	
    -- Build payload for server with resolved name where possible
    local movePayload = SelectedMove
    if type(movePayload) ~= "table" then
        movePayload = { Name = moveName or tostring(SelectedMove) }
    else
        movePayload = table.clone(movePayload)
        if moveName and not movePayload.Name then
            movePayload.Name = moveName
        end
    end
    -- Stop the idle camera cycle immediately when a move is actually used
    task.spawn(function()
        BattleSystem:StopCameraCycle()
    end)
    -- Send move to server for processing
    BattleSystem:ProcessMove(movePayload)
	
	-- Server will handle enemy turn response
	-- No need to call ProcessEnemyTurn() here
end

-- Process move execution
function BattleSystem:ProcessMove(MoveData)
	DBG:print("Processing move:", MoveData.Name)
	
	-- Send move to server for processing
	local Events = game.ReplicatedStorage.Events
	if Events and Events.Request then
		Events.Request:InvokeServer({"ExecuteMove", MoveData})
	end
end

-- Open creatures menu
function BattleSystem:OpenCreaturesMenu()
	DBG:print("Opening creatures menu")
	
	-- Set switch mode based on whether current creature is alive
	local isCurrentCreatureAlive = CurrentBattle and CurrentBattle.PlayerCreature and CurrentBattle.PlayerCreature.Stats and CurrentBattle.PlayerCreature.Stats.HP > 0
	SwitchMode = isCurrentCreatureAlive and "Switch" or "Forced"
	
	-- Hide battle options and stop camera cycle when opening party for switching
	BattleSystem:BattleOptionsToggle(false)
	BattleSystem:MoveOptionsToggle(false)
	BattleSystem:StopCameraCycle()
	
	-- Open party menu with battle context
	local UI = require(script.Parent.Parent.UI)
	if UI and UI.Party then
		UI.Party:Open()
	end
end

-- Open bag menu
function BattleSystem:OpenBagMenu()
	DBG:print("Opening bag menu")
	-- This would open the bag menu
	local UI = require(script.Parent.Parent.UI)
	if UI and UI.Bag then
		UI.Bag:Open()
	end
end

-- Return to battle options
function BattleSystem:ReturnToBattleOptions()
	BattleSystem:MoveOptionsToggle(false)
	BattleSystem:BattleOptionsToggle(true)
end

-- Update HP bars with animation
function BattleSystem:UpdateHPBar(creatureUI, currentHP, maxHP, isPlayer)
    DBG:print("Updating HP bar - Current:", currentHP, "Max:", maxHP)
    
	-- Locate the exact elements per your hierarchy:
	-- Bar frame to size/color: You/Foe.HPAmount (Frame)
	-- Label for text: You/Foe.HPBar.HPAmount (TextLabel)
	local BarFrame = creatureUI:FindFirstChild("HPAmount")
	local HPBar = creatureUI:FindFirstChild("HPBar")
	local Label = HPBar and HPBar:FindFirstChild("HPAmount")
	if not BarFrame or not BarFrame:IsA("Frame") then
		DBG:warn("BarFrame (You/Foe.HPAmount) not found or not a Frame")
		return
	end
    
    -- Calculate HP percentage
    local HPPercentage = 0
    if maxHP and maxHP > 0 then
        HPPercentage = math.max(0, math.min(1, currentHP / maxHP))
    end
    
	-- Only scale the bar's width based on its original full size; do not change height or position
	-- Cache original full size once (used as 100% baseline)
	if BarFrame:GetAttribute("FullXScale") == nil then
		BarFrame:SetAttribute("FullXScale", BarFrame.Size.X.Scale)
		BarFrame:SetAttribute("FullXOffset", BarFrame.Size.X.Offset)
		BarFrame:SetAttribute("FullYScale", BarFrame.Size.Y.Scale)
		BarFrame:SetAttribute("FullYOffset", BarFrame.Size.Y.Offset)
	end
	local fullXScale = BarFrame:GetAttribute("FullXScale") or BarFrame.Size.X.Scale
	local fullXOffset = BarFrame:GetAttribute("FullXOffset") or BarFrame.Size.X.Offset
	local fullYScale = BarFrame:GetAttribute("FullYScale") or BarFrame.Size.Y.Scale
	local fullYOffset = BarFrame:GetAttribute("FullYOffset") or BarFrame.Size.Y.Offset
    -- Respect original sizing mode: scale or offset
    local targetSize
    if fullXScale and fullXScale > 0 then
		targetSize = UDim2.new(fullXScale * HPPercentage, fullXOffset, fullYScale, fullYOffset)
    else
		targetSize = UDim2.new(0, math.floor((fullXOffset) * HPPercentage + 0.5), fullYScale, fullYOffset)
    end
    local HPBarTweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(BarFrame, HPBarTweenInfo, {Size = targetSize}):Play()
    
    -- Color transition from green (full) to red (empty)
	local green = Color3.fromRGB(5, 255, 68)
	local red = Color3.fromRGB(255, 3, 3)
	local color = LerpColor3(red, green, HPPercentage)
	TweenService:Create(BarFrame, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundColor3 = color}):Play()
    
	-- Set HP text on exact path: creatureUI.HPBar.HPAmount.Text
	local amountLabel = Label and Label:FindFirstChild("Text")
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
		amountLabel.Visible = true
	elseif Label and Label:IsA("TextLabel") then
		-- If HPAmount is the TextLabel itself
		Label.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
		Label.Visible = true
	else
		DBG:print("HP label not found at HPBar.HPAmount.Text")
	end
    
    DBG:print("HP bar updated to", math.floor(HPPercentage * 100 + 0.5), "%")
end

-- After HP changes, check for faint conditions and resolve
function BattleSystem:CheckFaintAndResolve()
    if not CurrentBattle then return end
    local playerHP = CurrentBattle.PlayerCreature and CurrentBattle.PlayerCreature.Stats and CurrentBattle.PlayerCreature.Stats.HP or nil
    local foeHP = CurrentBattle.FoeCreature and CurrentBattle.FoeCreature.Stats and CurrentBattle.FoeCreature.Stats.HP or nil
    
    if foeHP and foeHP <= 0 then
        -- Do not tween here; the tween is triggered exactly when faint message is displayed
        BattleSystem:OnBattleMessagesDrained(function()
            if not CurrentBattle then return end
            if CurrentBattle.Type == "Wild" then
                BattleSystem:RunAwaySequence()
            elseif CurrentBattle.Type == "Trainer" then
                DBG:print("Trainer foe fainted - next creature logic not implemented yet")
                BattleSystem:StartNextTurn()
            end
        end)
        return
    end
    
    if playerHP and playerHP <= 0 then
        -- Do not tween here; the tween is triggered exactly when faint message is displayed
        local ourName = CurrentBattle.PlayerCreature.Nickname or CurrentBattle.PlayerCreature.Name or "Your creature"
        BattleSystem:ShowBattleMessage(ourName .. " fainted!")
        -- After messages drain, either force a switch or handle defeat
        BattleSystem:OnBattleMessagesDrained(function()
            if not CurrentBattle then return end
            local playerData = ClientData:Get()
            local creature, idx = FindFirstAliveCreatureClient(playerData and playerData.Party or nil)
            if creature and idx then
                -- Force switch UI open
                SwitchMode = "Forced"
                local PartyModule = UI and UI.Party
                if PartyModule then
                    PartyModule:Open()
                    -- Ensure Cancel button is hidden for forced switch
                    setBattleButtonsVisible(true)
                end
            else
                -- All creatures fainted - this logic is now handled in the new defeat sequence
                -- This block is intentionally left empty to prevent duplicate defeat sequences
            end
        end)
    end
end

-- Process enemy turn
function BattleSystem:ProcessEnemyTurn()
	DBG:print("Processing enemy turn")
	
	if not CurrentBattle then
		DBG:warn("No current battle for enemy turn")
		return
	end
	
	-- Check if enemy turn is already used
	if CurrentBattle.EnemyTurnUsed then
		DBG:warn("Enemy turn already used this round")
		return
	end
	
	-- Consume enemy's turn
	CurrentBattle.EnemyTurnUsed = true
	DBG:print("Enemy turn consumed")
	
	-- Wait for server to process enemy turn
	-- The server will send back the enemy's action via Events.Communicate
	DBG:print("Waiting for server to process enemy turn...")
	
	-- Note: Enemy turn completion will be handled by server response
	-- This function just marks the turn as used, server handles the rest
end

-- Handle enemy turn from server
function BattleSystem:HandleEnemyTurn(Data)
	DBG:print("Received enemy turn from server:", Data)
	
	if not CurrentBattle then
		DBG:warn("No current battle for enemy turn")
		return
	end
	
	-- Show enemy action message
	if Data.Message then
		BattleSystem:ShowBattleMessage(Data.Message)
	end
	
	-- Mark enemy turn as used
	CurrentBattle.EnemyTurnUsed = true
	
	-- Check if both turns are complete
	if CurrentBattle.PlayerTurnUsed and CurrentBattle.EnemyTurnUsed then
		-- Wait a bit then start next turn
		task.wait(2)
		BattleSystem:StartNextTurn()
	end
end

-- Handle turn completion from server
function BattleSystem:HandleTurnComplete(Data)
	DBG:print("Turn completed:", Data)
	
	if not CurrentBattle then
		DBG:warn("No current battle for turn completion")
		return
	end
	
	-- Start next turn
	BattleSystem:StartNextTurn()
end

-- Handle escape success from server
function BattleSystem:HandleEscapeSuccess()
	DBG:print("Escape success received from server")
	BattleSystem:ShowBattleMessage("Got away safely!")
	task.wait(1)
	
	-- Don't reset FOV here - let RunAwaySequence handle it during blackout
	BattleSystem:RunAwaySequence()
end

-- Handle escape failure from server
function BattleSystem:HandleEscapeFailure()
	DBG:print("Escape failure received from server")
	BattleSystem:ShowBattleMessage("Unable to get away!")
	-- Increment escape attempts for next try
	CurrentBattle.EscapeAttempts = (CurrentBattle.EscapeAttempts or 0) + 1
	-- Server will handle enemy turn or send bundled result
end

-- Handle bundled server turn result
function BattleSystem:HandleTurnResult(Data)
	DBG:print("TurnResult received", Data)
	
	-- Initialize switch tracking variables
	local SwitchHandledThisTurn = false
	local SwitchModelUpdated = false
	local forcedSwitchThisTurn = false
	-- Buffer authoritative HP snapshot for use at animation Hit markers
	if CurrentBattle then
		CurrentBattle.PendingHP = Data and Data.HP or nil
		-- Defer player's HP UI update until foe's Hit
		if Data and Data.HP and Data.HP.Player ~= nil then
			CurrentBattle.DeferPlayerHPUntilHit = true
		end
		--DEBUG: Print which HP we have now and whose creature this is
		if Data and Data.PlayerCreature then
			DBG:print("Damage context - creature:", Data.PlayerCreature.Name)
		end
		if Data and Data.HP then
			DBG:print("Server HP values - Player:", Data.HP.Player, "PlayerMax:", Data.HP.PlayerMax)
		else
			DBG:print("Server sending no HP values.")
		end
	end

	--CRITICAL FIX: Update creature data first BEFORE applying damage
	-- to ensure damage goes to the current switched creature
	if Data and Data.PlayerCreature then
		CurrentBattle.PlayerCreature = Data.PlayerCreature
		CurrentBattle.PlayerCreatureIndex = Data.PlayerCreatureIndex
		DBG:print("FIXING: Switched to correct creature AND HP", Data.PlayerCreature.Name, "- HP:", Data.PlayerCreature.Stats.HP)
		-- Update level UI immediately with fresh server data
		updateLevelUI(CurrentBattle.PlayerCreature, false) -- Instant update for creature switch
		-- Also refresh the You UI panel now that the creature changed
		local ui = YouUI or (BattleUI and BattleUI:FindFirstChild("You"))
		if ui then
			BattleSystem:UpdateCreatureUI(ui, CurrentBattle.PlayerCreature)
		else
			DBG:warn("YouUI not found during server switch data refresh")
		end
		-- PREVENT duplicate updates by clearing Data.PlayerCreature after use
		Data.PlayerCreature = nil  
	end

	-- Optimized turn sequence management
	local function finishTurn()
		-- After all animations and delays
		if not CurrentBattle then return end

		-- Handle battle end conditions
		local foeHP = CurrentBattle.FoeCreature and CurrentBattle.FoeCreature.Stats and CurrentBattle.FoeCreature.Stats.HP or 0
		if foeHP <= 0 then
			if CurrentBattle.Type == "Wild" then
				BattleSystem:OnBattleMessagesDrained(function()
					BattleSystem:RunAwaySequence()
				end)
			elseif CurrentBattle.Type == "Trainer" then
				BattleSystem:OnBattleMessagesDrained(function()
					BattleSystem:StartNextTurn()
				end)
			end
			return
		end

		-- Reset turn flags and start next turn
		CurrentBattle.PlayerTurnUsed = true
		CurrentBattle.EnemyTurnUsed = true
		BattleSystem:OnBattleMessagesDrained(function()
			BattleSystem:StartNextTurn()
		end)
	end

	local function processEnemyActions(enemyActions, onDone)
		-- If we forced-switched this turn due to a faint, skip enemy actions
		if forcedSwitchThisTurn then
			DBG:print("Skipping enemy actions due to forced switch this turn")
			forcedSwitchThisTurn = false
			return onDone()
		end

		onDone = onDone or finishTurn
		if not enemyActions or #enemyActions == 0 then
			return onDone()
		end

		local idx = 1
		local lastShownMessage = nil
		local function processNextAction()
			local enemyAction = enemyActions[idx]
			if not enemyAction then
				onDone()
				return
			end

			local message = enemyAction.Message or (enemyAction.Move and string.format("Foe used %s!", tostring(enemyAction.Move))) or nil

			-- Show message if it's different from the last one
			if message and message ~= lastShownMessage then
				BattleSystem:ShowBattleMessage(message)
				lastShownMessage = message
			end

			-- Handle player damage
			if enemyAction.HPDelta and enemyAction.HPDelta.Player then
				task.wait(0.5) -- Wait for message to display
				local effectiveness = enemyAction.Effectiveness or "Normal"

				BattleSystem:PlayAttackWithHit(FoeCreatureModel, function()
					local playerCreature = CurrentBattle and CurrentBattle.PlayerCreature
					if not playerCreature or not playerCreature.Stats or not playerCreature.MaxStats then
						idx += 1
						return processNextAction()
					end

					local currentHP = playerCreature.Stats.HP or 0
					local damage = enemyAction.HPDelta.Player or 0
					local newHP = math.max(0, currentHP + damage)
					local newMax = CurrentBattle.PendingHP and CurrentBattle.PendingHP.PlayerMax or playerCreature.MaxStats.HP

					-- Use server-provided HP if available
					if CurrentBattle.PendingHP and CurrentBattle.PendingHP.Player then
						newHP = CurrentBattle.PendingHP.Player
					end

					playerCreature.Stats.HP = newHP
					BattleSystem:UpdateHPBar(YouUI, newHP, newMax, true)

					-- Clear pending HP data
					if CurrentBattle then
						CurrentBattle.DeferPlayerHPUntilHit = nil
						CurrentBattle.PendingHP = nil
					end

					BattleSystem:PlayDamaged(PlayerCreatureModel)

					-- Show effectiveness messages
					if effectiveness == "SuperEffective" or effectiveness == 2 or effectiveness == 4 then
						BattleSystem:ShowBattleMessage("It's super effective!")
					elseif effectiveness == "NotVeryEffective" or effectiveness == 0.5 or effectiveness == 0.25 then
						BattleSystem:ShowBattleMessage("It's not very effective...")
					end

					if enemyAction.Critical then
						BattleSystem:ShowBattleMessage("A critical hit!")
					end

					-- Handle fainting
					if newHP <= 0 and not PlayerFaintedAnnounced then
						PlayerFaintedAnnounced = true
						SuppressPostFaintMessages = true
						local creatureName = playerCreature.Nickname or playerCreature.Name or "Your creature"
						BattleSystem:ShowBattleMessage(creatureName .. " fainted!")

						-- End enemy actions and trigger forced switch/defeat
						enemyActions = {}
						BattleSystem:OnBattleMessagesDrained(function()
							local playerData = ClientData:Get()
							local creatureAlive = FindFirstAliveCreatureClient(playerData and playerData.Party or nil)

							if creatureAlive then
								SwitchMode = "Forced"
								BattleSystem:BattleOptionsToggle(false)
								BattleSystem:MoveOptionsToggle(false)
								local PartyModule = UI and UI.Party
								if PartyModule then
									PartyModule:Open()
									setBattleButtonsVisible(true)
								end
							else
								CurrentBattle.DefeatSequenceTriggered = true
								BattleSystem:BattleOptionsToggle(false)
								BattleSystem:MoveOptionsToggle(false)

								local trainerName = CurrentBattle.TrainerName or "Trainer"
								local ok, studsLost = pcall(function()
									return Events.Request:InvokeServer({"HandleTrainerLoss"})
								end)
								local lost = (ok and type(studsLost) == "number") and studsLost or 0

								if CurrentBattle.Type == "Trainer" then
									BattleSystem:ShowBattleMessage(trainerName .. " has no more creatures left to battle!")
									BattleSystem:ShowBattleMessage(trainerName .. " dropped " .. tostring(lost) .. " studs!")
									BattleSystem:OnBattleMessagesDrained(function()
										BattleSystem:BlackoutToCatchCare(trainerName, lost)
									end)
								else
									BattleSystem:ShowBattleMessage("You have no more creatures left to battle!")
									BattleSystem:ShowBattleMessage("You dropped " .. tostring(lost) .. " studs!")
									BattleSystem:OnBattleMessagesDrained(function()
										BattleSystem:BlackoutToCatchCare("Wild encounter", lost)
									end)
								end
							end
						end)
					end
				end, function()
					task.wait(0.77) -- Wait for damage animation
					idx += 1
					processNextAction()
				end, effectiveness)
			else
				-- Handle non-damaging moves or other actions
				if enemyAction.Move then
					local effectiveness = enemyAction.Effectiveness or "Normal"
					BattleSystem:PlayAttackWithHit(FoeCreatureModel, function() end, function()
						task.wait(0.4)
						idx += 1
						processNextAction()
					end, effectiveness)
				else
					idx += 1
					processNextAction()
				end
			end
		end

		processNextAction()
	end

	-- Ensure UI stays hidden during turn resolution (including switching)
	BattleSystem:BattleOptionsToggle(false)
	BattleSystem:MoveOptionsToggle(false)

	-- Process turn result
	local enemyActions = (Data and Data.Enemy) or {}
	-- Reset per-turn switch guard
	local SwitchHandledThisTurn = false
	-- Guard: if we perform a forced switch (due to faint), enemy should NOT act this turn
	local forcedSwitchThisTurn = false

	if Data and Data.Friendly then
		local handledFriendly = false
		for _, entry in ipairs(Data.Friendly) do
			if entry == "FailedRunAttempt" then
				BattleSystem:ShowBattleMessage("Unable to get away!")
				CurrentBattle.EscapeAttempts = (CurrentBattle.EscapeAttempts or 0) + 1
			elseif type(entry) == "table" then
                if entry.Type == "Switch" then
					-- Handle creature switch
					DBG:print("Processing switch result")
                    
                    -- Only set switch handling flag and update creature data on the first switch message
                    if not SwitchHandledThisTurn then
                        -- CRITICAL: Trust server's SwitchMode determination as authoritative
                        local serverForced = (Data and Data.SwitchMode == "Forced")
                        local wasForced = serverForced
                        DBG:print("Switch mode determination - Server:", Data and Data.SwitchMode or "nil", "Client forced:", wasForced)
                        forcedSwitchThisTurn = wasForced or forcedSwitchThisTurn
                        SwitchHandledThisTurn = true

                        -- Mark that we must wait for model spawn to complete before enemy acts
                        if CurrentBattle then
                            CurrentBattle.SwitchSpawnPending = true
                        end
                        
                        -- Update the current battle data with the new creature (only on the first switch message)
                        if Data.PlayerCreatureIndex then
                            CurrentBattle.PlayerCreatureIndex = Data.PlayerCreatureIndex
                            DBG:print("Updated PlayerCreatureIndex to:", Data.PlayerCreatureIndex)
                        end
                    end
					
					-- Process switch messages: always defer "Go X!" until the model actually spawns
					if entry.Message and type(entry.Message) == "string" then
						DBG:print("BATTLE: Processing switch message:", entry.Message)
						local msgLower = string.lower(entry.Message)
						local isGoMsg = (string.find(msgLower, "go ", 1, true) ~= nil)
						DBG:print("BATTLE: Message lower:", msgLower, "Is Go message:", isGoMsg, "SwitchMode:", Data and Data.SwitchMode)
						DBG:print("BATTLE: Full message for debugging:", entry.Message)
						if isGoMsg then
							-- Defer until spawn completes
							if CurrentBattle then
								CurrentBattle.PendingGoMessage = entry.Message
								DBG:print("BATTLE: Deferred Go message:", entry.Message)
								DBG:print("BATTLE: CurrentBattle.PendingGoMessage set to:", CurrentBattle.PendingGoMessage)
							else
								DBG:print("BATTLE: ERROR - No CurrentBattle when trying to defer Go message")
							end
						else
							-- Non-Go messages (e.g., "come back") show immediately
							DBG:print("BATTLE: Showing non-Go message immediately:", entry.Message)
							BattleSystem:ShowBattleMessage(entry.Message)
							-- Give a bit longer time for come-back line to breathe
							task.wait(1.2)
						end
					else
						DBG:print("BATTLE: No message in switch entry or message is not a string - entry:", entry)
					end
				if Data.PlayerCreature then
					-- Always adopt authoritative creature data from server on switch
					CurrentBattle.PlayerCreature = Data.PlayerCreature
					DBG:print("Updated PlayerCreature to:", Data.PlayerCreature.Name)
					-- Update level UI with fresh server data
					updateLevelUI(CurrentBattle.PlayerCreature, false) -- Instant update for creature switch
				end
					-- Update the creature model and UI (only on the first switch message to avoid duplicates)
					if not SwitchModelUpdated then
						SwitchModelUpdated = true
                        if wasForced then
							DBG:print("Forced switch detected; spawning immediately and suppressing 'come back' flow")
							-- Spawn immediately without waiting for any switch message
							local Essentials = BattleScene and BattleScene:FindFirstChild("Essentials")
							local PlayerSpawn = Essentials and Essentials:FindFirstChild("PlayerCreatureSpawn")
							if PlayerSpawn then
								-- Ensure previous model is cleaned up to prevent duplicates
								if PlayerCreatureModel and PlayerCreatureModel.Parent then
									local old = PlayerCreatureModel
									local HologramSpawnEffect = require(script.Parent.HologramSpawnEffect)
									HologramSpawnEffect:CreateFadeOut(old, function()
										if old and old.Parent then old:Destroy() end
									end)
								end
								BattleSystem:SpawnCreatureModel(CurrentBattle.PlayerCreature, PlayerSpawn, true)
								updateLevelUI(CurrentBattle.PlayerCreature, false)
								-- Force refresh of You UI panel
								local ui = YouUI or (BattleUI and BattleUI:FindFirstChild("You"))
								if ui then
									BattleSystem:UpdateCreatureUI(ui, CurrentBattle.PlayerCreature)
								else
									DBG:warn("YouUI not found during forced switch UI refresh")
								end
							end
						else
							-- Normal switch flow
							BattleSystem:UpdatePlayerCreatureModel(CurrentBattle.PlayerCreature)
							updateLevelUI(CurrentBattle.PlayerCreature, false)
							task.wait(0.5)
						end
					end
				else
					local creatureName = CurrentBattle.PlayerCreature.Nickname or CurrentBattle.PlayerCreature.Name
					local message = entry.Message or (entry.Type == "Move" and entry.Move and string.format("%s used %s!", creatureName, tostring(entry.Move))) or nil
					if message then BattleSystem:ShowBattleMessage(message) end
					
					-- Process attack damage if this is a move that deals damage
                    if entry.HPDelta and entry.HPDelta.Enemy then
						handledFriendly = true
						-- Get effectiveness from entry
						local effectiveness = entry.Effectiveness or "Normal"
						-- Check for flinch BEFORE processing attack
						if entry.FlinchTarget == "Enemy" then
							-- Foe flinched - show message and skip attack
							local foeName = CurrentBattle.FoeCreature and (CurrentBattle.FoeCreature.Name or "The foe") or "The foe"
							BattleSystem:ShowBattleMessage(foeName .. " flinched and couldn't move!")
							-- Wait for flinch message to fully display before continuing
							BattleSystem:OnBattleMessagesDrained(function()
								-- After flinch message, process enemy actions or finish turn
								if not FoeFaintedAnnounced then
									processEnemyActions(enemyActions, finishTurn)
								else
									finishTurn()
								end
							end)
						else
							-- No flinch - proceed with normal attack
                            BattleSystem:PlayAttackWithHit(PlayerCreatureModel, function()
								if CurrentBattle and CurrentBattle.FoeCreature and CurrentBattle.FoeCreature.Stats and CurrentBattle.FoeCreature.MaxStats then
									local newHP = nil
									local newMax = CurrentBattle.FoeCreature.MaxStats.HP
									if CurrentBattle.PendingHP and CurrentBattle.PendingHP.Enemy and CurrentBattle.PendingHP.EnemyMax then
										newHP = CurrentBattle.PendingHP.Enemy
										newMax = CurrentBattle.PendingHP.EnemyMax
									else
										newHP = math.max(0, (CurrentBattle.FoeCreature.Stats.HP or 0) + entry.HPDelta.Enemy)
									end
									CurrentBattle.FoeCreature.Stats.HP = newHP
									BattleSystem:UpdateHPBar(FoeUI, newHP, newMax, false)
									BattleSystem:PlayDamaged(FoeCreatureModel)
									
                                    -- Show effectiveness and critical messages BEFORE checking faint
                                    if effectiveness == "SuperEffective" or effectiveness == 2 or effectiveness == 4 then
                                        BattleSystem:ShowBattleMessage("It's super effective!")
                                        BattleSystem:OnBattleMessagesDrained(function() end)
                                    elseif effectiveness == "NotVeryEffective" or effectiveness == 0.5 or effectiveness == 0.25 then
                                        BattleSystem:ShowBattleMessage("It's not very effective...")
                                        BattleSystem:OnBattleMessagesDrained(function() end)
                                    end
                                    if entry.Critical == true then
                                        BattleSystem:ShowBattleMessage("A critical hit!")
                                        BattleSystem:OnBattleMessagesDrained(function() end)
                                    end
									
									if newHP <= 0 and not FoeFaintedAnnounced then 
										-- Set suppression flag immediately when we detect foe fainting
										SuppressPostFaintMessages = true
										-- Show fainted message and clear enemy actions
										local foeName = CurrentBattle.FoeCreature.Name or "Foe"
										BattleSystem:ShowBattleMessage(foeName .. " fainted!")
										-- Note: Tween is now handled in ShowBattleMessageNow when the message is displayed
										FoeFaintedAnnounced = true
										enemyActions = {}
										
										-- XP processing is now handled server-side for security
									end
								end
							end, function()
								-- Wait for our damaged animation to complete, then longer pause before enemy move
								task.wait(0.77)
								-- Only process enemy actions if foe hasn't fainted
								if not FoeFaintedAnnounced then
									processEnemyActions(enemyActions, finishTurn)
								else
									finishTurn()
								end
							end, effectiveness)
						end
					end
					if entry.HPDelta and entry.HPDelta.Player then
						local currentHP = CurrentBattle.PlayerCreature.Stats.HP or 0
						local damage = entry.HPDelta.Player
						local newHP = math.max(0, currentHP + damage)
						
						CurrentBattle.PlayerCreature.Stats.HP = newHP
						BattleSystem:UpdateHPBar(YouUI, newHP, CurrentBattle.PlayerCreature.MaxStats.HP, true)
						-- Tween our model out on faint when we actually show the faint message elsewhere
					end
				end
			end
		end
    end

    -- Process enemy actions (unless forced switch occurred)
    if not forcedSwitchThisTurn then
        -- If a switch happened, wait for model spawn to finish (or timeout) before enemy acts
        if CurrentBattle and CurrentBattle.SwitchSpawnPending == true then
            local start = tick()
            while CurrentBattle and CurrentBattle.SwitchSpawnPending == true and (tick() - start) < 5 do
                RunService.Heartbeat:Wait()
            end
        end
        processEnemyActions(enemyActions, finishTurn)
    else
        DBG:print("Skipping enemy actions due to forced switch this turn")
        forcedSwitchThisTurn = false
        -- For forced switches, the "Go!" message and battle options are handled in the spawn callback
        -- No need to do anything here as the spawn callback will handle the transition
    end
end

-- Start next turn
function BattleSystem:StartNextTurn()
	DBG:print("BATTLE: Starting next turn")

	if not CurrentBattle then
		DBG:warn("BATTLE: No current battle for next turn")
		return
	end

	DBG:print("BATTLE: Battle type:", CurrentBattle.Type, "SwitchMode:", CurrentBattle.SwitchMode)
	
	-- Increment turn number
	CurrentBattle.TurnNumber = CurrentBattle.TurnNumber + 1
	DBG:print("BATTLE: Turn number:", CurrentBattle.TurnNumber)
	
	-- Reset turn flags
	CurrentBattle.PlayerTurnUsed = false
	CurrentBattle.EnemyTurnUsed = false
	FoeFaintedThisTurn = false
	FoeFaintedAnnounced = false
	PlayerFaintedAnnounced = false
	
	-- Show battle options for player's turn
	BattleSystem:ShowBattleOptions()
    -- Start Shield-style camera cycle when player is idle at options
    task.spawn(function()
        BattleSystem:StartCameraCycle()
    end)
	
	DBG:print("Player's turn - select an action")
end

-- Run away sequence with blackout transition
function BattleSystem:RunAwaySequence()
	DBG:print("Starting run away sequence")
	
	-- Get UI references
	local PlayerGui = game.Players.LocalPlayer.PlayerGui
	local GameUI = PlayerGui:WaitForChild("GameUI")
	local Blackout = GameUI:WaitForChild("Blackout")
	local TopBar = GameUI:WaitForChild("TopBar")
	
	-- Hide battle UI first
	BattleUI.Visible = false
	
	-- Start blackout fade in
	Blackout.Visible = true
	Blackout.BackgroundTransparency = 1
	
	-- Fade to black
	local FadeInTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	})
	FadeInTween:Play()
	
	-- Wait for fade to complete
	FadeInTween.Completed:Wait()
	
	-- Wait 0.5 seconds as requested
	task.wait(0.5)
	
	-- Clean up battle scene during blackout
	if BattleScene then
		BattleScene:Destroy()
		BattleScene = nil
	end
	
	if PlayerCreatureModel then
		PlayerCreatureModel:Destroy()
		PlayerCreatureModel = nil
	end
	
	if FoeCreatureModel then
		FoeCreatureModel:Destroy()
		FoeCreatureModel = nil
	end
	
	-- Reset camera FOV during blackout (when screen is fully black)
	Camera.FieldOfView = 70
	DBG:print("Camera FOV reset to 70 during blackout")
	
	-- Reset camera to normal mode
	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = game.Players.LocalPlayer.Character:WaitForChild("Humanoid")
	
	-- Clear battle data
	CurrentBattle = nil

    -- End encounter to re-enable movement and reset exclamation mark
    local EncounterZone = require(script.Parent:WaitForChild("EncounterZone"))
    EncounterZone:EndEncounter()

    -- End encounter music and restore chunk music (with fade)
    pcall(function()
        local MusicManager = require(script.Parent.MusicManager)
        MusicManager:EndEncounterMusic()
        -- Also ensure chunk music is set for the current chunk after blackout completes
        task.delay(0.1, function()
            local ChunkLoader = require(script.Parent:WaitForChild("ChunkLoader"))
            local chunk = ChunkLoader:GetCurrentChunk()
            if chunk and chunk.Essentials then
                MusicManager:SetChunkMusic(chunk.Essentials)
            end
        end)
        -- Explicitly stop any active camera tween
        if ActiveCameraTween then
            pcall(function() ActiveCameraTween:Cancel() end)
            ActiveCameraTween = nil
        end
    end)
	
	-- DEBUG: Check party data after battle ends
	local ClientData = require(script.Parent.Parent.Plugins:WaitForChild("ClientData"))
	local playerData = ClientData:Get()
	DBG:print("=== PARTY DEBUG - AFTER BATTLE ===")
	DBG:print("Party exists:", playerData.Party ~= nil)
	DBG:print("Party length:", playerData.Party and #playerData.Party or "nil")
	if playerData.Party then
		for i, creature in ipairs(playerData.Party) do
			DBG:print("Party[" .. i .. "]:", creature.Name, "Level:", creature.Level)
		end
	else
		DBG:warn("PARTY IS NIL AFTER BATTLE!")
	end
	
	-- End encounter to re-enable movement properly
	local EncounterZone = require(script.Parent:WaitForChild("EncounterZone"))
	EncounterZone:EndEncounter()
	DBG:print("Encounter ended after run away")
	
	-- Fade out blackout
	local FadeOutTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})

	-- Show evolution UI while the screen is still black, before fading back in
	pcall(function()
		local EvolutionUI = require(script.Parent:WaitForChild("EvolutionUI"))
		local pre = BattleSystem.PreBattlePartySnapshot
		EvolutionUI:MaybeShowFromSnapshot(pre)
	end)

	FadeOutTween:Play()

    -- Show TopBar after fade out
    FadeOutTween.Completed:Connect(function()
		Blackout.Visible = false
		DBG:print("Blackout hidden, TopBar state before:", TopBar and TopBar.Visible or "TopBar is nil")
		
        if not TopBar then
			DBG:warn("TopBar is nil!")
		end
		
		-- Ensure camera is properly reset for movement
		Camera.CameraType = Enum.CameraType.Custom
		Camera.CameraSubject = game.Players.LocalPlayer.Character:WaitForChild("Humanoid")
		Camera.FieldOfView = 70
		DBG:print("Camera reset - Type:", Camera.CameraType, "Subject:", Camera.CameraSubject)
		
		-- Ensure character can move using the proper CharacterFunctions
		local CharacterFunctions = require(script.Parent:WaitForChild("CharacterFunctions"))
		CharacterFunctions:CanMove(true)
		DBG:print("Character movement restored using CharacterFunctions:CanMove(true)")
		
        -- Lift suppression and show TopBar after battle cleanup completes
        pcall(function() UI.TopBar:SetSuppressed(false) end)
        UI.TopBar:Show()
        DBG:print("TopBar shown using UI.TopBar:Show() method")
        -- Small delay to ensure everything is properly reset
        task.wait(0.1)
		
		DBG:print("Run away sequence completed - TopBar should be visible and functional")
	end)
	
	DBG:print("Run away sequence completed")
end

-- Blackout, load CatchCare, position at fallback spawn, and initiate Miranda heal dialogue
function BattleSystem:BlackoutToCatchCare(trainerName, studsLost)
    DBG:print("Starting BlackoutToCatchCare sequence")
    -- Get UI references
    local PlayerGui = game.Players.LocalPlayer.PlayerGui
    local GameUI = PlayerGui:WaitForChild("GameUI")
    local Blackout = GameUI:WaitForChild("Blackout")
    local TopBar = GameUI:WaitForChild("TopBar")

    -- Hide battle UI first
    BattleUI.Visible = false
    BattleOptions.Visible = false
    MoveOptions.Visible = false

    -- Stop encounter music immediately when blackout starts
    pcall(function() MusicManager:EndEncounterMusic() end)
    
    -- Start blackout fade in
    Blackout.Visible = true
    Blackout.BackgroundTransparency = 1
    local FadeInTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 0})
    FadeInTween:Play()
    FadeInTween.Completed:Wait()
    task.wait(0.25)

    -- Clean up battle scene during blackout
    if BattleScene then BattleScene:Destroy() BattleScene = nil end
    if PlayerCreatureModel then PlayerCreatureModel:Destroy() PlayerCreatureModel = nil end
    if FoeCreatureModel then FoeCreatureModel:Destroy() FoeCreatureModel = nil end
    Camera.FieldOfView = 70
    Camera.CameraType = Enum.CameraType.Custom
    Camera.CameraSubject = game.Players.LocalPlayer.Character:WaitForChild("Humanoid")
    CurrentBattle = nil

    -- End encounter to re-enable movement properly
    local EncounterZone = require(script.Parent:WaitForChild("EncounterZone"))
    EncounterZone:EndEncounter()

    -- Check if we're in Chunk1 - if so, teleport to Healer Tom instead of CatchCare
    local ChunkLoader = require(script.Parent:WaitForChild("ChunkLoader"))
    local currentChunk = ChunkLoader:GetCurrentChunk() and ChunkLoader:GetCurrentChunk().Model and ChunkLoader:GetCurrentChunk().Model.Name
    
    if currentChunk == "Chunk1" then
        -- Special handling for Chunk1 - teleport to Healer Tom
        DBG:print("Player defeated in Chunk1 - teleporting to Healer Tom")
        local player = game.Players.LocalPlayer
        local character = player.Character or player.CharacterAdded:Wait()
        local hrp = character:WaitForChild("HumanoidRootPart")
        
        -- Find Healer Tom in Chunk1 (he's in the NPCs folder)
        local Chunk = ChunkLoader:GetCurrentChunk()
        if Chunk and Chunk.Model then
            local NPCs = Chunk.Model:FindFirstChild("NPCs")
            if NPCs then
                local healerTom = NPCs:FindFirstChild("Healer Tom")
                if healerTom and healerTom:FindFirstChild("HumanoidRootPart") then
                    -- Teleport in front of Healer Tom, not on his head
                    local healerPosition = healerTom.HumanoidRootPart.Position
                    local healerCFrame = healerTom.HumanoidRootPart.CFrame
                    local forwardDirection = healerCFrame.LookVector
                    local teleportPosition = healerPosition + forwardDirection * 5 + Vector3.new(0, 0, 0)
                    hrp.CFrame = CFrame.new(teleportPosition, healerPosition)
                    DBG:print("Teleported in front of Healer Tom")
                    
                    -- Restore TopBar before triggering dialogue
                    UI.TopBar:SetSuppressed(false)
                    UI.TopBar:Show()
                    
                    -- Trigger healing dialogue with Healer Tom
                    task.wait(0.5) -- Wait for teleport to complete
                    local UI = require(script.Parent.Parent.UI)
                    if UI and UI.HealerTom then
                        UI.HealerTom:StartHealingDialogue()
                        DBG:print("Started healing dialogue with Healer Tom")
                    else
                        DBG:warn("Healer Tom UI not found - cannot start healing dialogue")
                    end
                end
            end
        end
    else
        -- Normal CatchCare loading for other chunks
        local ok = ChunkLoader:ClientRequestChunk("CatchCare")
        DBG:print("Requested CatchCare chunk load:", ok and true or false)
        task.wait(0.2)

        -- Position player at Essentials.ChunkSpawnFallBack
        local Chunk = ChunkLoader:GetCurrentChunk()
        if Chunk and Chunk.Essentials then
            local spawn = Chunk.Essentials:FindFirstChild("ChunkSpawnFallBack")
            local player = game.Players.LocalPlayer
            local character = player.Character or player.CharacterAdded:Wait()
            local hrp = character:WaitForChild("HumanoidRootPart")
            if spawn and hrp then
                hrp.CFrame = spawn.CFrame
            end
        end
    end

    -- Fade out blackout
    local FadeOutTween = TweenService:Create(Blackout, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {BackgroundTransparency = 1})
    FadeOutTween:Play()
    FadeOutTween.Completed:Wait()
    Blackout.Visible = false

    -- Start Miranda conversation and heal
    local UI = require(script.Parent.Parent.UI)
    -- Clear TopBar suppression before hiding for dialogue
    if UI and UI.TopBar then 
        UI.TopBar:SetSuppressed(false)
        UI.TopBar:Hide() 
    end
    local Chunk2 = ChunkLoader:GetCurrentChunk()
    local npc = Chunk2 and Chunk2.Model and Chunk2.Model:FindFirstChild("NPCs") and Chunk2.Model.NPCs:FindFirstChild("Miranda")
    local Say = require(script.Parent.Say)
    Say:Say("Miranda", true, {"Oh hi! You need your creatures healed? Allow me!"}, npc)
    local success, healOk = pcall(function()
        return Events.Request:InvokeServer({"HealParty"})
    end)
    if success and healOk then
        Say:Say("Miranda", true, {"Done! Take care of them!"}, npc)
    else
        Say:Say("Miranda", true, {"Hmm, that didn't work. Come back when you're nearby."}, npc)
    end
    if UI and UI.TopBar then UI.TopBar:Show() end

    -- Ensure movement is restored
    local CharacterFunctions = require(script.Parent:WaitForChild("CharacterFunctions"))
    CharacterFunctions:CanMove(true)
    
    -- Resume chunk music after blackout
    task.wait(0.5) -- Small delay to ensure everything is settled
    local currentChunk = ChunkLoader:GetCurrentChunk()
    if currentChunk and currentChunk.Essentials then
        pcall(function() MusicManager:SetChunkMusic(currentChunk.Essentials) end)
    end
    
    DBG:print("BlackoutToCatchCare completed")
end

-- End battle and cleanup
function BattleSystem:EndBattle()
	DBG:print("Ending battle")
	
	-- Hide battle UI immediately
	BattleUI.Visible = false
	
	-- Stop any active camera tweens
	BattleSystem:StopCameraCycle()
	if ActiveCameraTween then
		pcall(function() ActiveCameraTween:Cancel() end)
		ActiveCameraTween = nil
	end
	
	-- Clean up battle scene
	if BattleScene then
		BattleScene:Destroy()
		BattleScene = nil
	end
	
	-- Clean up creature models
	if PlayerCreatureModel then
		PlayerCreatureModel:Destroy()
		PlayerCreatureModel = nil
	end
	
	if FoeCreatureModel then
		FoeCreatureModel:Destroy()
		FoeCreatureModel = nil
	end
	
	-- Reset camera to normal
	Camera.CameraType = Enum.CameraType.Custom
	Camera.FieldOfView = 70
	
	-- Clear all battle state flags
	CurrentBattle = nil
	FoeFaintedThisTurn = false
	FoeFaintedAnnounced = false
	PlayerFaintedAnnounced = false
	PlayerFaintTweened = false
	FoeFaintTweened = false
	
	-- Clear animation tracks
	PlayerIdleTrack = nil
	FoeIdleTrack = nil

    -- End encounter to re-enable movement and reset encounter state
    local EncounterZone = require(script.Parent:WaitForChild("EncounterZone"))
    EncounterZone:EndEncounter()

    -- End encounter music and restore chunk music (with fade)
    pcall(function()
        local MusicManager = require(script.Parent.MusicManager)
        MusicManager:EndEncounterMusic()
        task.delay(0.1, function()
            local ChunkLoader = require(script.Parent:WaitForChild("ChunkLoader"))
            local chunk = ChunkLoader:GetCurrentChunk()
            if chunk and chunk.Essentials then
                MusicManager:SetChunkMusic(chunk.Essentials)
            end
        end)
    end)
	
	-- Re-enable movement
	local CharacterFunctions = require(script.Parent.CharacterFunctions)
	CharacterFunctions:CanMove(true)

	-- Lift TopBar suppression and show
	pcall(function() UI.TopBar:SetSuppressed(false) end)
	UI.TopBar:Show()

	-- After cleanup, attempt to show evolution UI if any party member evolved
	local ok, EvolutionUI = pcall(function()
		return require(script:WaitForChild("EvolutionUI"))
	end)
	if ok and EvolutionUI then
		local pre = BattleSystem.PreBattlePartySnapshot
		pcall(function()
			EvolutionUI:MaybeShowFromSnapshot(pre)
		end)
	end
	
	DBG:print("Battle ended and cleaned up - all state reset")
	
	-- Print all battle messages when battle ends
	print("=== BATTLE MESSAGE HISTORY ===")
	print("BattleMessageHistory:", BattleMessageHistory)
	print("=== END BATTLE MESSAGE HISTORY ===")
end

return BattleSystem


]]--
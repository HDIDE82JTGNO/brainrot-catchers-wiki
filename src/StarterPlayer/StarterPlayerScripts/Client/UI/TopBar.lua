local TopBar = {}
TopBar.__index = TopBar

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local TopBarControl = require(script.Parent:WaitForChild("TopBarControl"))
local BagModule = require(script.Parent:WaitForChild("Bag"))
local PartyModule = require(script.Parent:WaitForChild("Party"))
local SaveModule = require(script.Parent:WaitForChild("Save"))
local SettingsModule = require(script.Parent:WaitForChild("Settings"))
local CharacterFunctions = require(script.Parent.Parent.Utilities.CharacterFunctions)

local Audio = script.Parent.Parent:WaitForChild("Assets"):WaitForChild("Audio")
local LocalPlayer = Players.LocalPlayer

-- Store animation track for reliable stopping
local TopBarLoopTrack = nil
-- Global suppression to avoid race conditions (e.g., during battle)
local SuppressShow = false
-- Suppress all TopBar interactions during critical operations (e.g., saving)
local SuppressInteractions = false


-- Track menu state for NPC interaction prevention
local IsMenuOpen = false
local IsHiding = false

local function StopTopBarAnimation()
	local Character = LocalPlayer.Character
	if not Character then
		return
	end
	
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return
	end
	
	-- Stop stored animation track directly
	if TopBarLoopTrack then
		TopBarLoopTrack:Stop()
		TopBarLoopTrack = nil
	end
	
	-- Also stop any TopBar animations by name as backup
	for _, track in pairs(Humanoid:GetPlayingAnimationTracks()) do
		if track.Animation then
			local animName = track.Animation.Name
			if animName == "TopBar_Loop" then
				track:Stop()
			end
		end
	end
end

-- TopBar animation system
local function PlayTopBarAnimation()
	-- Stop any existing TopBar animations first
	StopTopBarAnimation()
	
	local Character = LocalPlayer.Character
	if not Character then
		return
	end
	
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return
	end
	
	-- Try to find the animations in StarterPlayerScripts.Client.Assets.Animations.TopBar
	local StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
	local Client = StarterPlayerScripts:WaitForChild("Client")
	local Assets = Client:WaitForChild("Assets")
	
	if Assets then
		local Animations = Assets:FindFirstChild("Animations")
		if Animations then
			local TopBarAnimations = Animations:FindFirstChild("TopBar")
			if TopBarAnimations then
				-- Play TopBar_Loop animation directly
				local LoopAnimation = TopBarAnimations:FindFirstChild("TopBar_Loop")
				if LoopAnimation then
					TopBarLoopTrack = Humanoid:LoadAnimation(LoopAnimation)
					TopBarLoopTrack.Looped = true
					TopBarLoopTrack:Play()
				end
			end
		end
	end
end

function TopBar:Create()
	local self = setmetatable({}, TopBar)
	
	local Set = TweenInfo.new(0.25, Enum.EasingStyle.Circular, Enum.EasingDirection.Out)
	
	self.TopBarFrame = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("TopBar")
	self.Which = self.TopBarFrame:WaitForChild("Which")
	
	local function UpdateWhichZIndex(Target: GuiButton)
		self.Which.ZIndex = Target.ZIndex 
	end

	local function HoverOnTopBarButton(Target: GuiButton)
		self.Which.Position = Target.Position
		self.Which.Size = UDim2.new(0, 0, 0, 0)
		if Target.Name == "Save" then
			self.Which.Text = "Progress"
		else
			self.Which.Text = Target.Name
		end
		self.Which.Visible = true
		UpdateWhichZIndex(Target)
		TweenService:Create(self.Which, Set, {Position = Target.Position + UDim2.new(0, 0, 0.4, 0)}):Play()
		TweenService:Create(self.Which, Set, {Size = UDim2.new(0.226, 0, 0.36, 0)}):Play()
	end

	local function HoverOffTopBarButton(Target: GuiButton)
		TweenService:Create(self.Which, Set, {Position = Target.Position}):Play()
		TweenService:Create(self.Which, Set, {Size = UDim2.new(0, 0, 0, 0)}):Play()
		task.delay(Set.Time,function()
			if self.Which.Size == UDim2.new(0, 0, 0, 0) then
				self.Which.Visible = false
			end
		end)
	end
	
	--Button Connections:
	
    --Track state (store on self so it's visible to other methods)
    self.CurrentState = nil

	local function SetTop(inst, bool)
		if bool == false then
			inst.ZIndex = -3
			inst.Shadow.ZIndex = -1
			inst.Icon.ZIndex = -1
			inst.IconShadow.ZIndex = -2
		else
			inst.ZIndex = 1
			inst.Shadow.ZIndex = -1
			inst.Icon.ZIndex = 2
			inst.IconShadow.ZIndex = 1
		end
	end
	

	local TopButtons = {"Party", "Bag", "Save", "Settings"}

	local function StateVisualChange()
		for _, name in ipairs(TopButtons) do
			local button = self.TopBarFrame:WaitForChild(name)
			SetTop(button, name == self.CurrentState)
		end
	end
	
	-- Make StateVisualChange accessible to other methods
	self.StateVisualChange = StateVisualChange

	local function CloseCurrent()
        if self.CurrentState == "Save" then
			SaveModule:Close()
        elseif self.CurrentState == "Settings" then
			SettingsModule:Close()
         elseif self.CurrentState == "Party" then
			PartyModule:Close()
        elseif self.CurrentState == "Bag" then
			BagModule:Close()
		end
		
		-- Stop TopBar animations and re-enable movement when closing menus
		StopTopBarAnimation()
		CharacterFunctions:CanMove(true)
		
		-- Update menu state
		IsMenuOpen = false
        self.CurrentState = nil
	end

    -- Expose control hooks for other modules (e.g., Save) without requiring TopBar directly
    TopBarControl.SetInteractionsSuppressed = function(value: boolean)
        SuppressInteractions = value == true
    end
    TopBarControl.RefreshState = function()
        if self.StateVisualChange then self:StateVisualChange() end
    end
    TopBarControl.ClearActive = function()
        CloseCurrent()
    end
    TopBarControl.Show = function()
        self:Show()
    end
    TopBarControl.NotifyClosed = function(stateName: string)
        if self.CurrentState == stateName then
            self.CurrentState = nil
            self.StateVisualChange()
        end
    end


	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("Party"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
		function()
			-- Prevent opening menus during hide animation or when interactions are suppressed
			if SuppressInteractions then return end
			-- Prevent opening menus during hide animation
			if IsHiding then
				return
			end
			
			Audio.SFX.Click:Play()
            if self.CurrentState == "Party" then
				CloseCurrent()
			else
                if self.CurrentState ~= nil then
					CloseCurrent()
					task.wait(0.15)
				end
				-- Start TopBar animations and disable movement when opening menu
				PlayTopBarAnimation()
				CharacterFunctions:CanMove(false)
				IsMenuOpen = true
				PartyModule:Open({})
                self.CurrentState = "Party"
			end
			StateVisualChange()
			UpdateWhichZIndex(self.TopBarFrame:WaitForChild("Party"))
		end,
		HoverOnTopBarButton,
		HoverOffTopBarButton
	)
	
	
	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("Bag"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
		function()
			-- Prevent opening menus during hide animation or when interactions are suppressed
			if SuppressInteractions then return end
			-- Prevent opening menus during hide animation
			if IsHiding then
				return
			end
			
			Audio.SFX.Click:Play()
            if self.CurrentState == "Bag" then
				CloseCurrent()
			else
                if self.CurrentState ~= nil then
					CloseCurrent()
					task.wait(0.15)
				end
				-- Start TopBar animations and disable movement when opening menu
				PlayTopBarAnimation()
				CharacterFunctions:CanMove(false)
				IsMenuOpen = true
				BagModule:Open()
                self.CurrentState = "Bag"
			end
			StateVisualChange()
			UpdateWhichZIndex(self.TopBarFrame:WaitForChild("Bag"))
		end,
		HoverOnTopBarButton,
		HoverOffTopBarButton
	)
	-- Save button
	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("Save"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
		function()
			-- Prevent opening menus during hide animation or when interactions are suppressed
			if SuppressInteractions then return end
			-- Prevent opening menus during hide animation
			if IsHiding then
				return
			end
			
			Audio.SFX.Click:Play()
            if self.CurrentState == "Save" then
				CloseCurrent()
			else
                if self.CurrentState ~= nil then
					CloseCurrent()
					task.wait(0.15) 
				end
				-- Start TopBar animations and disable movement when opening menu
				PlayTopBarAnimation()
				CharacterFunctions:CanMove(false)
				IsMenuOpen = true
				SaveModule:Open()
                self.CurrentState = "Save"
			end
			StateVisualChange()
			UpdateWhichZIndex(self.TopBarFrame:WaitForChild("Save"))
		end,
		HoverOnTopBarButton,
		HoverOffTopBarButton
	)

	-- Settings button
	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("Settings"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
		function()
			-- Prevent opening menus during hide animation or when interactions are suppressed
			if SuppressInteractions then return end
			-- Prevent opening menus during hide animation
			if IsHiding then
				return
			end
			
			Audio.SFX.Click:Play()
            if self.CurrentState == "Settings" then
				CloseCurrent()
			else
                if self.CurrentState ~= nil then
					CloseCurrent()
					task.wait(0.15)
				end
				-- Start TopBar animations and disable movement when opening menu
				PlayTopBarAnimation()
				CharacterFunctions:CanMove(false)
				IsMenuOpen = true
				SettingsModule:Open()
                self.CurrentState = "Settings"
			end
			StateVisualChange()
			UpdateWhichZIndex(self.TopBarFrame:WaitForChild("Settings"))
		end,
		HoverOnTopBarButton,
		HoverOffTopBarButton
	)
	
	return self
end

function TopBar:Show()
    -- Guard: skip showing when globally suppressed (e.g., during battle/cutscenes)
    if SuppressShow == true then
        return
    end
	self.TopBarFrame.Visible = true
	local Set = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	TweenService:Create(self.TopBarFrame, Set, {Position = UDim2.new(self.TopBarFrame.Position.X.Scale,0,0.081,0)}):Play()
	task.delay(0.4,function()
		self.TopBarFrame.Party.Active = true
		self.TopBarFrame.Bag.Active = true
		self.TopBarFrame.Save.Active = true
		self.TopBarFrame.Settings.Active = true
	end)
end

function TopBar:Hide()
	-- Prevent new menu interactions during hide animation
	IsHiding = true
	
	-- Close any currently open pages
	BagModule:Close()
	PartyModule:Close()
	SaveModule:Close()
	SettingsModule:Close()
	
	-- Stop TopBar animations and re-enable movement when hiding TopBar
	StopTopBarAnimation()
	CharacterFunctions:CanMove(true)
	
	-- Update menu state
	IsMenuOpen = false
	
    -- Reset the internal state
    self.CurrentState = nil
	
	self.TopBarFrame.Party.Active = false
	self.TopBarFrame.Bag.Active = false
	self.TopBarFrame.Save.Active = false
	self.TopBarFrame.Settings.Active = false
	
	-- Update visual state to reflect no active button
	self.StateVisualChange()
	
	local Set = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	TweenService:Create(self.TopBarFrame, Set, {Position = UDim2.new(self.TopBarFrame.Position.X.Scale,0,-0.1,0)}):Play()
	task.delay(0.4,function()
		self.TopBarFrame.Visible = false
		IsHiding = false -- Allow menu interactions again after hide animation completes
	end)
end

-- Immediate hide without tween, used on critical transitions (e.g., battle start)
function TopBar:HideImmediate()
    -- Stop any animations and reset state instantly
    StopTopBarAnimation()
    IsMenuOpen = false
    self.CurrentState = nil
    self.TopBarFrame.Party.Active = false
    self.TopBarFrame.Bag.Active = false
    self.TopBarFrame.Save.Active = false
    self.TopBarFrame.Settings.Active = false
    self.StateVisualChange()
    self.TopBarFrame.Visible = false
end

function TopBar:GetState()
	return self.TopBarFrame.Party.Active
end

function TopBar:IsMenuOpen()
	return IsMenuOpen or IsHiding
end

-- Public API to control suppression
function TopBar:SetSuppressed(value)
    SuppressShow = value == true
end

function TopBar:IsSuppressed()
    return SuppressShow == true
end

return TopBar
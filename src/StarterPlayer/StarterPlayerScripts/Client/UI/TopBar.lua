local TopBar = {}
TopBar.__index = TopBar

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local TopBarControl = require(script.Parent:WaitForChild("TopBarControl"))
local BagModule = require(script.Parent:WaitForChild("Bag"))
local PartyModule = require(script.Parent:WaitForChild("Party"))
local DexModule = require(script.Parent:WaitForChild("Dex"))
local SaveModule = require(script.Parent:WaitForChild("Save"))
local SettingsModule = require(script.Parent:WaitForChild("Settings"))
local CTRLModule = require(script.Parent:WaitForChild("CTRL"))
local ChallengesModule = require(script.Parent:WaitForChild("Challenges"))
local ShopModule = require(script.Parent:WaitForChild("Shop"))
local WorldInfoModule = require(script.Parent:WaitForChild("WorldInfo"))
local CharacterFunctions = require(script.Parent.Parent.Utilities.CharacterFunctions)
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
local Say = require(script.Parent.Parent.Utilities.Say)

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

-- Port-A-Vault gamepass ID
local PORTAVAULT_GAMEPASS_ID = 1656188952

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
		self.Which.Text = Target.Name
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
			-- Set ZIndex for child elements if they exist
			if inst:FindFirstChild("Shadow") then inst.Shadow.ZIndex = -1 end
			if inst:FindFirstChild("Icon") then inst.Icon.ZIndex = -1 end
			if inst:FindFirstChild("IconShadow") then inst.IconShadow.ZIndex = -2 end
			-- Challenges button uses ChallengeText instead of Icon
			if inst:FindFirstChild("ChallengeText") then inst.ChallengeText.ZIndex = -1 end
		else
			inst.ZIndex = 1
			if inst:FindFirstChild("Shadow") then inst.Shadow.ZIndex = -1 end
			if inst:FindFirstChild("Icon") then inst.Icon.ZIndex = 2 end
			if inst:FindFirstChild("IconShadow") then inst.IconShadow.ZIndex = 1 end
			-- Challenges button uses ChallengeText instead of Icon
			if inst:FindFirstChild("ChallengeText") then inst.ChallengeText.ZIndex = 2 end
		end
	end
	

	local TopButtons = {"Party", "Bag", "Dex", "CTRL", "Challenges"}

	local function StateVisualChange()
		for _, name in ipairs(TopButtons) do
			local button = self.TopBarFrame:FindFirstChild(name)
			if button then
				SetTop(button, name == self.CurrentState)
			end
		end
	end
	
	-- Make StateVisualChange accessible to other methods
	self.StateVisualChange = StateVisualChange

	-- Check Port-A-Vault gamepass ownership and update CB button visibility
	local function checkPortAVaultOwnership()
		local cbButton = self.TopBarFrame:FindFirstChild("CB")
		if not cbButton then return end
		
		local success, ownsGamepass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, PORTAVAULT_GAMEPASS_ID)
		end)
		
		if success and ownsGamepass then
			cbButton.Visible = true
		else
			cbButton.Visible = false
		end
	end
	
	-- Expose function to refresh CB button visibility (for Shop.lua to call)
	self.CheckPortAVaultOwnership = checkPortAVaultOwnership

	-- Store original ChallengeText for restoration
	local OriginalChallengeText = nil
	
	-- Helper: Set Challenges mode (hide/show other buttons, change text)
	local function SetChallengesMode(isOpen)
		local challengesButton = self.TopBarFrame:FindFirstChild("Challenges")
		local challengeText = challengesButton and challengesButton:FindFirstChild("ChallengeText")
		
		if isOpen then
			-- Store original text and change to "Close"
			if challengeText then
				OriginalChallengeText = OriginalChallengeText or challengeText.Text
				challengeText.Text = "Close"
			end
			-- Hide all other buttons
			for _, name in ipairs({"Party", "Bag", "Dex", "CTRL"}) do
				local button = self.TopBarFrame:FindFirstChild(name)
				if button then
					button.Visible = false
				end
			end
		else
			-- Restore original text
			if challengeText and OriginalChallengeText then
				challengeText.Text = OriginalChallengeText
			end
			-- Show all other buttons
			for _, name in ipairs({"Party", "Bag", "Dex", "CTRL"}) do
				local button = self.TopBarFrame:FindFirstChild(name)
				if button then
					button.Visible = true
				end
			end
		end
	end

	local function CloseCurrent()
        if self.CurrentState == "Party" then
			PartyModule:Close()
        elseif self.CurrentState == "Bag" then
			BagModule:Close()
		elseif self.CurrentState == "Dex" then
			DexModule:Close()
		elseif self.CurrentState == "CTRL" then
			CTRLModule:Close()
		elseif self.CurrentState == "Challenges" then
			ChallengesModule:Close()
			-- Restore other buttons when closing Challenges
			SetChallengesMode(false)
		end
		
	
		pcall(function()
			SaveModule:Close()
		end)
		pcall(function()
			SettingsModule:Close()
		end)
		pcall(function()
			ShopModule:Close()
		end)
		
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

	-- Dex button
	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("Dex"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
		function()
			-- Prevent opening menus during hide animation or when interactions are suppressed
			if SuppressInteractions then return end
			if IsHiding then
				return
			end

			Audio.SFX.Click:Play()
			
			-- Check if player has any creatures in their party
			local playerData = ClientData:Get()
			local hasCreatures = false
			if playerData and playerData.Party and type(playerData.Party) == "table" then
				hasCreatures = #playerData.Party > 0
			end
			
			if not hasCreatures then
				-- Close any open menu first before showing the message
				if self.CurrentState ~= nil then
					CloseCurrent()
				end
				-- Player doesn't have any creatures, use Say instead
				local character = LocalPlayer.Character
				if character then
					Say:Say("You", true, {"I can't find my dex..."}, character)
					task.delay(0.5,function()
						self:SetSuppressed(false)
						self:Show()
					end)
				end
				return
			end
			
			if self.CurrentState == "Dex" then
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
				DexModule:Open()
				self.CurrentState = "Dex"
			end

			StateVisualChange()
			UpdateWhichZIndex(self.TopBarFrame:WaitForChild("Dex"))
		end,
		HoverOnTopBarButton,
		HoverOffTopBarButton
	)

	-- CTRL button
	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("CTRL"),
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
			
			-- Check if player has at least 1 badge
			local playerData = ClientData:Get()
			local badges = 0
			if playerData and playerData.Badges then
				badges = tonumber(playerData.Badges) or 0
			end
			
			if badges < 1 then
				-- Close any open menu first before showing the message
				if self.CurrentState ~= nil then
					CloseCurrent()
				end
				-- Player doesn't have at least 1 badge, use Say instead
				local character = LocalPlayer.Character
				if character then
					Say:Say("You", true, {"I shouldn't use this until I'm ready."}, character)
					task.delay(0.5,function()
						self:SetSuppressed(false)
						self:Show()
					end)
				end
				return
			end
			
            if self.CurrentState == "CTRL" then
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
				CTRLModule:Open()
                self.CurrentState = "CTRL"
			end
			StateVisualChange()
			UpdateWhichZIndex(self.TopBarFrame:WaitForChild("CTRL"))
		end,
		HoverOnTopBarButton,
		HoverOffTopBarButton
	)

	-- Challenges button (no "Which" text on hover)
	UIFunctions:NewButton(
		self.TopBarFrame:WaitForChild("Challenges"),
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
			
            if self.CurrentState == "Challenges" then
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
				ChallengesModule:Open()
                self.CurrentState = "Challenges"
				-- Hide other buttons and change text to "Close"
				SetChallengesMode(true)
			end
			StateVisualChange()
		end,
		function() end, -- No hover on effect (no "Which" text)
		function() end  -- No hover off effect
	)

	-- CB (Port-A-Vault) button
	local cbButton = self.TopBarFrame:FindFirstChild("CB")
	if cbButton then
		-- Initially hide CB button, will be shown if player owns gamepass
		cbButton.Visible = false
		
		UIFunctions:NewButton(
			cbButton,
			{"Action"},
			{ Click = "One", HoverOn = "One", HoverOff = "One" },
			0.7,
			function()
				-- Prevent opening menus during hide animation or when interactions are suppressed
				if SuppressInteractions then return end
				if IsHiding then
					return
				end
				
				Audio.SFX.Click:Play()
				
				-- Validate with server before opening vault
				local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
				local Request = Events:WaitForChild("Request")
				
				local success, result = pcall(function()
					return Request:InvokeServer({"OpenVault"})
				end)
				
				if success and result == true then
					-- Server confirmed ownership, open vault
					local UI = require(script.Parent)
					if UI and UI.Vault and UI.Vault.Open then
						-- Close any open menus first
						if self.CurrentState ~= nil then
							CloseCurrent()
							task.wait(0.15)
						end
						-- Hide TopBar before opening vault
						self:Hide()
						UI.Vault:Open()
					else
						-- Access denied - show error message
						local character = LocalPlayer.Character
						if character then
							Say:Say("You", true, {"You need the Port-A-Vault gamepass to use this feature."}, character)
						end
					end
				else
					-- Request failed
					local character = LocalPlayer.Character
					if character then
						Say:Say("You", true, {"Unable to access vault. Please try again later."}, character)
					end
				end
			end,
			HoverOnTopBarButton,
			HoverOffTopBarButton
		)
		
		-- Check ownership on creation
		checkPortAVaultOwnership()
	end
	
	return self
end

function TopBar:Show()
    -- Guard: skip showing when globally suppressed (e.g., during battle/cutscenes)
    if SuppressShow == true then
        return
    end
	self.TopBarFrame.Visible = true
	local Set = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	TweenService:Create(self.TopBarFrame, Set, {Position = UDim2.new(self.TopBarFrame.Position.X.Scale,0,0.13,0)}):Play()
	task.delay(0.4,function()
		self.TopBarFrame.Party.Active = true
		self.TopBarFrame.Bag.Active = true
		self.TopBarFrame.Dex.Active = true
		self.TopBarFrame.CTRL.Active = true
		self.TopBarFrame.Challenges.Active = true
	end)
	
	-- Show WorldInfo when TopBar shows
	pcall(function()
		WorldInfoModule:Show()
	end)
end

function TopBar:Hide()
	-- Prevent new menu interactions during hide animation
	IsHiding = true
	
	-- Close any currently open pages
	BagModule:Close()
	PartyModule:Close()
	DexModule:Close()
	SaveModule:Close()
	SettingsModule:Close()
	CTRLModule:Close()
	ChallengesModule:Close()
	pcall(function()
		ShopModule:Close()
	end)

	-- Stop TopBar animations and re-enable movement when hiding TopBar
	StopTopBarAnimation()
	CharacterFunctions:CanMove(true)
	
	-- Update menu state
	IsMenuOpen = false
	
    -- Reset the internal state
    self.CurrentState = nil
	
	self.TopBarFrame.Party.Active = false
	self.TopBarFrame.Bag.Active = false
	self.TopBarFrame.Dex.Active = false
	self.TopBarFrame.CTRL.Active = false
	self.TopBarFrame.Challenges.Active = false
	
	-- Update visual state to reflect no active button
	self.StateVisualChange()
	
	local Set = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	TweenService:Create(self.TopBarFrame, Set, {Position = UDim2.new(self.TopBarFrame.Position.X.Scale,0,-0.1,0)}):Play()
	task.delay(0.4,function()
		self.TopBarFrame.Visible = false
		IsHiding = false -- Allow menu interactions again after hide animation completes
	end)
	
	-- Hide WorldInfo when TopBar hides
	pcall(function()
		WorldInfoModule:Hide()
	end)
end

-- Immediate hide without tween, used on critical transitions (e.g., battle start)
function TopBar:HideImmediate()
    -- Stop any animations and reset state instantly
    StopTopBarAnimation()
    IsMenuOpen = false
    self.CurrentState = nil
    
    -- Close all modules immediately
    pcall(function() BagModule:Close() end)
    pcall(function() PartyModule:Close() end)
    pcall(function() DexModule:Close() end)
    pcall(function() SaveModule:Close() end)
    pcall(function() SettingsModule:Close() end)
    pcall(function() CTRLModule:Close() end)
    pcall(function() ChallengesModule:Close() end)
    pcall(function() ShopModule:Close() end)
    
    self.TopBarFrame.Party.Active = false
    self.TopBarFrame.Bag.Active = false
    self.TopBarFrame.Dex.Active = false
    self.TopBarFrame.CTRL.Active = false
    self.TopBarFrame.Challenges.Active = false
    self.StateVisualChange()
    self.TopBarFrame.Visible = false
	
	-- Hide WorldInfo immediately too
	pcall(function()
		WorldInfoModule:Hide()
	end)
end

function TopBar:GetState()
	return self.TopBarFrame.Party.Active
end

function TopBar:IsMenuOpen()
	-- Check internal state first
	if IsMenuOpen or IsHiding then
		return true
	end
	
	-- Also check if ShopModule or CatchCareShop are actually open (they can be opened independently)
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if pg then
		local gameUI = pg:FindFirstChild("GameUI")
		if gameUI then
			-- Check ShopModule (Robux shop)
			local shopUI = gameUI:FindFirstChild("Shop")
			if shopUI and shopUI:IsA("ScreenGui") and shopUI.Visible then
				return true
			end
			
			-- Check CatchCareShop (in-game shop)
			local catchCareShop = gameUI:FindFirstChild("CatchCareShop")
			if catchCareShop and catchCareShop:IsA("Frame") and catchCareShop.Visible then
				return true
			end
		end
	end
	
	return false
end

-- Public API to control suppression
function TopBar:SetSuppressed(value)
    SuppressShow = value == true
end

function TopBar:IsSuppressed()
    return SuppressShow == true
end

return TopBar
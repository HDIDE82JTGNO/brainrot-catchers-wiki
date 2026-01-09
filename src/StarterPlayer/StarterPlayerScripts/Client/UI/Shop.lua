--!nocheck
local ShopModule = {}
local isOpen = false

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local MarketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local Players: Players = game:GetService("Players")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local CharacterFunctions = require(script.Parent.Parent.Utilities:WaitForChild("CharacterFunctions"))
local TopBarControl = require(script.Parent:WaitForChild("TopBarControl"))

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")
local LocalPlayer = Players.LocalPlayer

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.new(0.786, 0, 0.832, 0)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

--// Product and Gamepass IDs
local PRODUCT_IDS = {
	GiantPack = 3502520258,
	PlusPack = 3502519477,
	PowerPack = 3502519215,
	RegularPack = 3502518875,
	StarterPack = 3502450743,
}

local GAMEPASS_IDS = {
	EXPSharePlus = 1656774306,
	PortAVault = 1656188952,
	VaultPlus = 1656816296,
}

--// Price Formatting Function
local function formatRobuxPrice(price: number): string
	return string.format("%d Robux", price)
end

-- Update developer product prices (GetProductInfo already returns regional prices)
local function updateDeveloperProductPrices(shopUI: ScreenGui)
	local shopMain = shopUI:FindFirstChild("ShopMain")
	if not shopMain then return end
	
	local studsGrid = shopMain:FindFirstChild("StudsGrid")
	if not studsGrid then return end
	
	-- Update prices for each product
	for buttonName, productId in pairs(PRODUCT_IDS) do
		local button = studsGrid:FindFirstChild(buttonName)
		if button then
			local priceLabel = button:FindFirstChild("Price")
			if priceLabel and priceLabel:IsA("TextLabel") then
				-- Get regional price directly from MarketplaceService
				local success, productInfo = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				
				if success and productInfo and productInfo.PriceInRobux then
					priceLabel.Text = formatRobuxPrice(productInfo.PriceInRobux)
				else
					priceLabel.Text = "Loading..."
				end
			end
		end
	end
end

-- Purchase functions
local function purchaseDeveloperProduct(productId: number)
	pcall(function()
		MarketplaceService:PromptProductPurchase(LocalPlayer, productId)
	end)
end

local function purchaseGamepass(gamepassId: number)
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, gamepassId)
	end)
end

-- Helper function to switch tabs
local function switchTab(shopUI: ScreenGui, tabName: string)
	local shopMain = shopUI:FindFirstChild("ShopMain")
	if not shopMain then return end
	
	local tabsContainer = shopMain:FindFirstChild("TabsContainer")
	if not tabsContainer then return end
	
	-- Hide all grids
	local boostsGrid = shopMain:FindFirstChild("BoostsGrid")
	local studsGrid = shopMain:FindFirstChild("StudsGrid")
	local upgradesGrid = shopMain:FindFirstChild("UpgradesGrid")
	
	if boostsGrid then boostsGrid.Visible = false end
	if studsGrid then studsGrid.Visible = false end
	if upgradesGrid then upgradesGrid.Visible = false end
	
	-- Show the selected grid
	if tabName == "Boosts" and boostsGrid then
		boostsGrid.Visible = true
	elseif tabName == "Studs" and studsGrid then
		studsGrid.Visible = true
	elseif tabName == "Upgrades" and upgradesGrid then
		upgradesGrid.Visible = true
	end
end

function ShopModule:Init(All)
	local ShopUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Shop")
	
	-- Set up Close button
	local CloseButton = ShopUI:WaitForChild("Topbar"):WaitForChild("Close")
	if CloseButton then
		UIFunctions:NewButton(
			CloseButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				Audio.SFX.Click:Play()
				ShopModule:Close()
			end
		)
	end
	
	-- Set up tab buttons
	local shopMain = ShopUI:FindFirstChild("ShopMain")
	if shopMain then
		local tabsContainer = shopMain:FindFirstChild("TabsContainer")
		if tabsContainer then
			-- Helper function to set up tab button
			local function setupTabButton(button: GuiButton, tabName: string)
				if not button then return end
				-- Ensure OGSize is set before hover animations can fire
				-- Store the current size as OGSize to prevent hover animation issues
				button:SetAttribute("OGSize", button.Size)
				UIFunctions:NewButton(
					button,
					{"Action"},
					{}, -- No animations to prevent size issues
					0.7,
					function()
						Audio.SFX.Click:Play()
						switchTab(ShopUI, tabName)
					end
				)
			end
			
			-- Boosts tab
			setupTabButton(tabsContainer:FindFirstChild("Boosts"), "Boosts")
			
			-- Studs tab
			setupTabButton(tabsContainer:FindFirstChild("Studs"), "Studs")
			
			-- Upgrades tab
			setupTabButton(tabsContainer:FindFirstChild("Upgrades"), "Upgrades")
		end
		
		-- Set up developer product purchase buttons (StudsGrid)
		local studsGrid = shopMain:FindFirstChild("StudsGrid")
		if studsGrid then
			for buttonName, productId in pairs(PRODUCT_IDS) do
				local button = studsGrid:FindFirstChild(buttonName)
				if button and button:IsA("GuiButton") then
					-- Ensure button has a valid size before setting OGSize
					if button.Size.X.Scale > 0 and button.Size.Y.Scale > 0 then
						button:SetAttribute("OGSize", button.Size)
					end
					UIFunctions:NewButton(
						button,
						{"Action"},
						{Click = "One", HoverOn = "One", HoverOff = "One"},
						0.7,
						function()
							Audio.SFX.Click:Play()
							purchaseDeveloperProduct(productId)
						end
					)
				end
			end
		end
		
		-- Set up gamepass purchase buttons (UpgradesGrid)
		local upgradesGrid = shopMain:FindFirstChild("UpgradesGrid")
		if upgradesGrid then
			for buttonName, gamepassId in pairs(GAMEPASS_IDS) do
				local button = upgradesGrid:FindFirstChild(buttonName)
				if button and button:IsA("GuiButton") then
					-- Ensure button has a valid size before setting OGSize
					if button.Size.X.Scale > 0 and button.Size.Y.Scale > 0 then
						button:SetAttribute("OGSize", button.Size)
					end
					UIFunctions:NewButton(
						button,
						{"Action"},
						{Click = "One", HoverOn = "One", HoverOff = "One"},
						0.7,
						function()
							Audio.SFX.Click:Play()
							purchaseGamepass(gamepassId)
						end
					)
				end
			end
		end
	end
	
	-- Listen for gamepass purchase completion
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if player == LocalPlayer and wasPurchased then
			-- Check if Port-A-Vault was purchased
			if gamepassId == GAMEPASS_IDS.PortAVault then
				-- Refresh CB button visibility in TopBar
				task.spawn(function()
					local UI = require(script.Parent)
					if UI and UI.TopBar and UI.TopBar.CheckPortAVaultOwnership then
						UI.TopBar:CheckPortAVaultOwnership()
					end
				end)
			end
			
			-- Check if Vault+ was purchased
			if gamepassId == GAMEPASS_IDS.VaultPlus then
				-- Refresh client data to get updated box count from server
				task.spawn(function()
					local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")
					local Request = Events:WaitForChild("Request")
					-- Request fresh data from server (server will add boxes automatically)
					pcall(function()
						local freshData = Request:InvokeServer({"DataGet"})
						if freshData then
							local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
							ClientData:ServerForceUpdateData(freshData)
						end
					end)
				end)
			end
			
			-- Check if EXP Share+ was purchased
			if gamepassId == GAMEPASS_IDS.EXPSharePlus then
				-- Bonus applies automatically on next battle, no action needed
				-- This handler is here for potential future UI updates
			end
		end
	end)
end

--// Shop Open
function ShopModule:Open(All)
	All = All or {} -- Make All parameter optional
	if isOpen then return end -- Already open, don't open again
	
	-- Initialize shop if not already done
	if not ShopModule._initialized then
		ShopModule:Init(All)
		ShopModule._initialized = true
	end
	
	isOpen = true
	local Shop: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
			Close: GuiButton,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Shop")
	
	Audio.SFX.Open:Play()

	Shop.Visible = true
	Shop.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(Shop, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	Shop.Position = UDim2.new(0.5, 0, 0.5, 0)

	-- Shadow
	if Shop:FindFirstChild("Shadow") and Shop.Shadow:FindFirstChild("Image") then
		Shop.Shadow.Image.ImageTransparency = 1
		TweenService:Create(Shop.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 0.5,
		}):Play()
	end

	-- Topbar
	if Shop:FindFirstChild("Topbar") then
		Shop.Topbar.Size = UDim2.fromScale(1, 0.165)
		TweenService:Create(Shop.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.107),
		}):Play()

		-- Icon + Shadow
		if Shop.Topbar:FindFirstChild("Icon") then
			Shop.Topbar.Icon.Rotation = 25
			Shop.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
			TweenService:Create(Shop.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Rotation = 0,
				Position = UDim2.new(0.041, 0, 0.185, 0),
			}):Play()
		end
		
		if Shop.Topbar:FindFirstChild("IconShadow") then
			Shop.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)
			TweenService:Create(Shop.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.066, 0, 0.526, 0),
			}):Play()
		end

		-- Title
		if Shop.Topbar:FindFirstChild("Title") then
			Shop.Topbar.Title.MaxVisibleGraphemes = 0
			TweenService:Create(Shop.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				MaxVisibleGraphemes = 4,
			}):Play()
		end
	end

	-- Darken
	if Shop:FindFirstChild("Darken") then
		Shop.Darken.Size = CLOSED_SIZE
		TweenService:Create(Shop.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.new(4.0125*1.2, 0,6.0945*1.2, 0),
		}):Play()
	end
	
	-- Set default tab to Studs (show StudsGrid, hide others)
	local shopMain = Shop:FindFirstChild("ShopMain")
	if shopMain then
		local boostsGrid = shopMain:FindFirstChild("BoostsGrid")
		local studsGrid = shopMain:FindFirstChild("StudsGrid")
		local upgradesGrid = shopMain:FindFirstChild("UpgradesGrid")
		
		-- Hide all grids first
		if boostsGrid then boostsGrid.Visible = false end
		if upgradesGrid then upgradesGrid.Visible = false end
		
		-- Show StudsGrid by default
		if studsGrid then
			studsGrid.Visible = true
		end
		
		-- Update developer product prices
		updateDeveloperProductPrices(Shop)
	end
end

--// Shop Close
function ShopModule:Close(All)
	All = All or {} -- Make All parameter optional
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
	-- Inform TopBar that Shop is closing to clear menu state
	pcall(function()
		TopBarControl.ClearActive()
	end)
	local Shop: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
			Close: GuiButton,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Shop")

	Audio.SFX.Close:Play()
	
	-- Ensure movement is re-enabled and any TopBar loop animation is stopped when closing Shop
	pcall(function()
		CharacterFunctions:CanMove(true)
		local character = game.Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do
				if track.Animation and track.Animation.Name == "TopBar_Loop" then
					track:Stop()
				end
			end
		end
	end)
	
	task.delay(0.1, function()
		TweenService:Create(Shop, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)

	if Shop:FindFirstChild("Shadow") and Shop.Shadow:FindFirstChild("Image") then
		TweenService:Create(Shop.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			ImageTransparency = 1,
		}):Play()
	end

	if Shop:FindFirstChild("Topbar") then
		TweenService:Create(Shop.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
			Size = UDim2.fromScale(1, 0.1),
		}):Play()

		if Shop.Topbar:FindFirstChild("Icon") then
			TweenService:Create(Shop.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Rotation = 25,
				Position = UDim2.new(0.05, 0, 0.341, 0),
			}):Play()
		end
		
		if Shop.Topbar:FindFirstChild("IconShadow") then
			TweenService:Create(Shop.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
				Position = UDim2.new(0.084, 0, 0.682, 0),
			}):Play()
		end

		if Shop.Topbar:FindFirstChild("Title") then
			TweenService:Create(Shop.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				MaxVisibleGraphemes = 0,
			}):Play()
		end
	end

	if Shop:FindFirstChild("Darken") then
		TweenService:Create(Shop.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end

	task.delay(0.4, function()
		Shop.Visible = false
	end)
end

return ShopModule


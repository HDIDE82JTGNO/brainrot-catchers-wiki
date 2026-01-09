--!nocheck
local SaveModule = {}
local isOpen = false

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local Say = require(script.Parent.Parent.Utilities.Say)
local CharacterFunctions = require(script.Parent.Parent.Utilities.CharacterFunctions)
local TopBarControl = require(script.Parent:WaitForChild("TopBarControl"))

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")
local RS = game:GetService("ReplicatedStorage")
local Events = RS:WaitForChild("Events")
local Request = Events:WaitForChild("Request")
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local Players = game:GetService("Players")
local RS_Storage = game:GetService("ReplicatedStorage")
local SharedPlayerData = require(RS_Storage:WaitForChild("Shared"):WaitForChild("PlayerData"))
local Creatures = require(RS_Storage:WaitForChild("Shared"):WaitForChild("Creatures"))

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.fromScale(0.626,0.571)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

function SaveModule:Init(All)
	--Populate Save

	-- Populate Party and Badge panels every time Init called
	self:RefreshPanels()

	UIFunctions:NewButton(
		game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Save"):WaitForChild("ConfirmSave"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
		function()
			Audio.SFX.Click:Play()
			print("Attempt save!")
			-- Disable button and set title to Saving..
			local pg = Players.LocalPlayer.PlayerGui
			local gui = pg:WaitForChild("GameUI")
			local confirm = gui:WaitForChild("Save"):WaitForChild("ConfirmSave")
			pcall(function()
				local title = confirm:FindFirstChild("Title")
				if title and title:IsA("TextLabel") then
					title.Text = "Saving.."
				end
				confirm.Active = false
				confirm.AutoButtonColor = false
			end)
			-- Suppress TopBar interactions during save
			pcall(function()
				TopBarControl.SetInteractionsSuppressed(true)
			end)

			local ok, reason = Request:InvokeServer({"ManualSave"})
			if ok == true then
				print("[Save] Manual save succeeded")
				-- Play save notification and close Save UI
				pcall(function()
					local frame = gui and gui:FindFirstChild("SaveNotification")
					if frame and UIFunctions and UIFunctions.SaveNotificationSuccess then
						UIFunctions:SaveNotificationSuccess(frame)
					end
				end)
				SaveModule:Close()
			else
				warn("[Save] Manual save failed")
				SaveModule:Close()
				pcall(function()
					Say:Say("System", true, { reason == "RateLimited" and "You're saving too quickly! Please wait." or "Failed to save! Please try again soon." })
				end)
			end
			-- Re-enable button and restore title
			pcall(function()
				local title = confirm:FindFirstChild("Title")
				if title and title:IsA("TextLabel") then
					title.Text = "Save"
				end
				confirm.Active = true
				confirm.AutoButtonColor = true
			end)
			-- Lift TopBar suppression after save flow completes
			pcall(function()
				TopBarControl.SetInteractionsSuppressed(false)
				-- Ensure TopBar is visible again after system Say (rate limit/fail path)
				TopBarControl.Show()
				-- Reset TopBar state visuals to avoid stale selection
				TopBarControl.RefreshState()
			end)
		end
	)
	
	-- Set up Close button
	local SaveUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Save")
	local CloseButton = SaveUI:WaitForChild("Topbar"):WaitForChild("Close")
	if CloseButton then
		UIFunctions:NewButton(
			CloseButton,
			{"Action"},
			{Click = "One", HoverOn = "One", HoverOff = "One"},
			0.7,
			function()
				Audio.SFX.Click:Play()
				SaveModule:Close()
			end
		)
	end
	
end

--// Save Open
function SaveModule:Open(All)
	if isOpen then return end -- Already open, don't open again
	
	isOpen = true
	pcall(function()
		TopBarControl.SetInteractionsSuppressed(false)
	end)
	local Save: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Save")
	
	Audio.SFX.Open:Play()

	Save.Visible = true
	Save.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(Save, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	Save.Position = UDim2.new(0.56, 0,0.1, 0)
	TweenService:Create(Save, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5,0,0.5,0),
	}):Play()

	-- Shadow
	Save.Shadow.Image.ImageTransparency = 1
	TweenService:Create(Save.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 0.5,
	}):Play()

	-- Topbar
	Save.Topbar.Size = UDim2.fromScale(1, 0.165)
	TweenService:Create(Save.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.107),
	}):Play()

	-- Icon + Shadow
	Save.Topbar.Icon.Rotation = 25
	Save.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
	Save.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)

	TweenService:Create(Save.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 0,
		Position = UDim2.new(0.041, 0, 0.185, 0),
	}):Play()
	TweenService:Create(Save.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.066, 0, 0.526, 0),
	}):Play()

	-- Title
	Save.Topbar.Title.MaxVisibleGraphemes = 0
	TweenService:Create(Save.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 8,
	}):Play()

	-- Refresh data-driven panels and text when opening
	self:RefreshPanels()

	-- Darken
	Save.Darken.Size = CLOSED_SIZE
	TweenService:Create(Save.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.new(4.0125*1.2, 0,6.0945*1.2, 0),	
	}):Play()
end

--// Save Close
function SaveModule:Close(All)
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
	-- Inform TopBar state machine that Save panel is closed
	pcall(function()
		TopBarControl.NotifyClosed("Save")
	end)
	local Save: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Save")

	Audio.SFX.Close:Play()

	-- Ensure movement is re-enabled and any TopBar loop animation is stopped when closing via Save
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
		TweenService:Create(Save, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)
	
	task.delay(0.15,function()
		TweenService:Create(Save, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.56, 0,0.1, 0),
		}):Play()
	end)

	TweenService:Create(Save.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	}):Play()

	TweenService:Create(Save.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.1),
	}):Play()

	TweenService:Create(Save.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 25,
		Position = UDim2.new(0.05, 0, 0.341, 0),
	}):Play()
	TweenService:Create(Save.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.084, 0, 0.682, 0),
	}):Play()

	TweenService:Create(Save.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 0,
	}):Play()

	TweenService:Create(Save.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = CLOSED_SIZE,
	}):Play()

	task.delay(0.4, function()
		Save.Visible = false
	end)
end

-- return at end of file

-- Panel refresh, date/dex titles, and UI data binding
function SaveModule:RefreshPanels()
    local player = Players.LocalPlayer
    local gui = player.PlayerGui:WaitForChild("GameUI"):WaitForChild("Save")

    -- Dynamic titles
    local function ordinal(n:number): string
        local k = n % 100
        if k >= 11 and k <= 13 then return tostring(n).."th" end
        local t = n % 10
        if t == 1 then return tostring(n).."st" end
        if t == 2 then return tostring(n).."nd" end
        if t == 3 then return tostring(n).."rd" end
        return tostring(n).."th"
    end

    local months = {"January","February","March","April","May","June","July","August","September","October","November","December"}
    local now = os.date("*t")
    local hour = now.hour
    local ampm = (hour >= 12) and "pm" or "am"
    local hour12 = hour % 12
    if hour12 == 0 then hour12 = 12 end
    local minute = string.format("%02d", now.min)
    local dateText = string.format("Date: %s %s %d @%s:%s%s",
        ordinal(now.day), months[now.month], now.year, tostring(hour12), minute, ampm)

    local data = ClientData:Get()
    local totalOwned = 0
    if data then
        -- Count party creatures (1-6)
        if data.Party then
            for i = 1, 6 do
                if data.Party[i] ~= nil then
                    totalOwned += 1
                end
            end
        end
        -- Count all boxed creatures across all boxes
        if data.Boxes and typeof(data.Boxes) == "table" then
            for _, box in ipairs(data.Boxes) do
                if typeof(box) == "table" then
                    for _, creature in ipairs(box) do
                        if creature ~= nil then
                            totalOwned += 1
                        end
                    end
                end
            end
        end
    end

    pcall(function()
        local DateFrame = gui:FindFirstChild("Date", true)
        if DateFrame and DateFrame:FindFirstChild("Title") then
            DateFrame.Title.Text = dateText
        end
        local DexFrame = gui:FindFirstChild("Dex", true)
        if DexFrame and DexFrame:FindFirstChild("Title") then
            DexFrame.Title.Text = string.format("Dex: %d", totalOwned)
        end
    end)

    -- Party list sprites
    pcall(function()
        local PartyList = gui:FindFirstChild("PartyList", true)
        local container = PartyList and PartyList:FindFirstChild("Container")
        if container and data and data.Party then
            for i = 1, 6 do
                local slot = container:FindFirstChild(tostring(i))
                if slot and slot:IsA("ImageLabel") then
                    local creature = data.Party[i]
                    if creature then
                        -- Prefer shiny sprite when flagged; fall back to species/default sprite
                        local sprite: string? = nil
                        local useShiny = (creature.Shiny == true)
                        if useShiny then
                            sprite = creature.ShinySprite
                            if not sprite and creature.Name and Creatures[creature.Name] then
                                sprite = Creatures[creature.Name].ShinySprite or Creatures[creature.Name].Sprite
                            end
                        else
                            sprite = creature.Sprite
                            if not sprite and creature.Name and Creatures[creature.Name] then
                                sprite = Creatures[creature.Name].Sprite
                            end
                        end
                        if sprite then
                            slot.Visible = true
                            slot.Image = sprite
                        else
                            slot.Visible = false
                        end
                        slot.ImageTransparency = 0
                    else
                        slot.Visible = false
                    end
                end
            end
        end
    end)

    -- Badge list transparency
    pcall(function()
        local BadgeList = gui:FindFirstChild("BadgeList", true)
        local container = BadgeList and BadgeList:FindFirstChild("Container")
        if container and data then
            local badges = tonumber(data.Badges) or 0
            for i = 1, 6 do
                local slot = container:FindFirstChild(tostring(i))
                if slot and slot:IsA("ImageLabel") then
                    if i <= badges then
                        slot.ImageTransparency = 0
                    else
                        slot.ImageTransparency = 0.75
                    end
                end
            end
        end
    end)
end

return SaveModule


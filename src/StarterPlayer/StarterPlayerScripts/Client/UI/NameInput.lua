--!strict

-- NameInput.lua
-- UI helper to prompt the player for a name and validate via server filter
-- Usage:
--   local NameInput = require(script.Parent.NameInput)
--   local value = NameInput:Input(true) -- yields; returns string on success, nil on cancel

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local Say = require(script.Parent.Parent:WaitForChild("Utilities"):WaitForChild("Say"))

export type NameInput = {
	Input: (self: NameInput, canCancel: boolean) -> (string?),
}

local NameInput: NameInput = {} :: any
NameInput.__index = NameInput

-- Internal helpers
local function getGameUI(): ScreenGui
	return PlayerGui:WaitForChild("GameUI") :: ScreenGui
end

local function getInputGui(): Frame
	return getGameUI():WaitForChild("InputName") :: Frame
end

local function getRequest(): RemoteFunction
	return ReplicatedStorage:WaitForChild("Events"):WaitForChild("Request") :: RemoteFunction
end

local function getCancelButton(container: Instance): GuiButton?
	local btn = container:FindFirstChild("Cancel")
	if btn and btn:IsA("GuiButton") then return btn end
	-- Backwards compatibility: some UIs call this "No"
	local alt = container:FindFirstChild("No")
	if alt and alt:IsA("GuiButton") then return alt end
	return nil
end

local function getDoneButton(container: Instance): GuiButton?
	local btn = container:FindFirstChild("Done")
	if btn and btn:IsA("GuiButton") then return btn end
	return nil
end

local function getInputField(container: Instance): TextBox?
	local input = container:FindFirstChild("Input")
	if not input then return nil end
	local field = (input :: Instance):FindFirstChild("InputField")
	if field and field:IsA("TextBox") then
		return field
	end
	return nil
end

local function trim(str: string): string
	return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isLocallyValidName(name: string): boolean
	-- Length 1..12, letters/numbers/spaces and ' - . ! ?
	if #name < 1 or #name > 12 then return false end
	if not name:match("^[%a0-9 '%-%.%!%?]+$") then return false end
	return true
end

local function isInappropriateFromFilter(filtered: string): boolean
	-- Treat empty, whitespace-only, or strings with # as invalid
	if filtered == nil then return true end
	if trim(filtered) == "" then return true end
	if filtered:find("#") then return true end
	return false
end

-- Core API
function NameInput:Input(canCancel: boolean): string?
	local ui = getInputGui()
	local field = getInputField(ui)
	local doneBtn = getDoneButton(ui)
	local cancelBtn = getCancelButton(ui)
	if not field or not doneBtn then
		warn("[NameInput] Missing InputField or Done button in InputName UI")
		return nil
	end

	-- Configure Cancel visibility and hook if available
	local cancelConn: any = nil
	if cancelBtn then
		cancelBtn.Visible = canCancel == true
		if canCancel == true then
			UIFunctions:NewButton(cancelBtn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
				ui.Visible = false
			end)
			-- We track cleanup via ClearConnection later
		end
	end

	-- Show UI and clear current text
	ui.Visible = true
	field.Text = ""
	field:CaptureFocus()

	local result: string? = nil
	local confirmed = false

	local function onDone()
		local raw = field.Text or ""
		raw = trim(raw)
		if not isLocallyValidName(raw) then
			Say:Say("", true, {"Name must be 1-12 chars, letters/numbers and ' - . ! ?"})
			field.Text = ""
			field:CaptureFocus()
			return
		end

		local filtered: string? = nil
		local ok = pcall(function()
			filtered = getRequest():InvokeServer({"FilterName", raw})
		end)
		if not ok or type(filtered) ~= "string" or isInappropriateFromFilter(filtered :: string) then
			Say:Say("", true, {"Innapropriate Name!"})
			field.Text = ""
			field:CaptureFocus()
			return
		end

		result = filtered
		confirmed = true
		ui.Visible = false
	end

	-- Hook Done button via UIFunctions
	UIFunctions:NewButton(doneBtn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, onDone)

	-- Yield until closed (confirmed or canceled)
	repeat task.wait() until ui.Visible == false or confirmed == true

	-- Cleanup button connections
	UIFunctions:ClearConnection(doneBtn)
	if cancelBtn then
		UIFunctions:ClearConnection(cancelBtn)
	end

	return result
end

return NameInput

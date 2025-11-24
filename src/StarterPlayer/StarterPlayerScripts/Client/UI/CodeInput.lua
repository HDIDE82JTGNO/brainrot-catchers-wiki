--!strict
--[[
	CodeInput.lua
	UI helper to prompt the player for a code string
	Usage:
		local CodeInput = require(script.Parent.CodeInput)
		local code = CodeInput:Input(true) -- yields; returns string on success, nil on cancel
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local Say = require(script.Parent.Parent:WaitForChild("Utilities"):WaitForChild("Say"))

export type CodeInput = {
	Input: (self: CodeInput, canCancel: boolean) -> (string?),
}

local CodeInput: CodeInput = {} :: any
CodeInput.__index = CodeInput

-- Internal helpers
local function getGameUI(): ScreenGui
	return PlayerGui:WaitForChild("GameUI") :: ScreenGui
end

local function getInputGui(): Frame
	return getGameUI():WaitForChild("InputName") :: Frame
end

local function getCancelButton(container: Instance): GuiButton?
	local btn = container:FindFirstChild("Cancel")
	if btn and btn:IsA("GuiButton") then return btn end
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

-- Core API
function CodeInput:Input(canCancel: boolean): string?
	local ui = getInputGui()
	local field = getInputField(ui)
	local doneBtn = getDoneButton(ui)
	local cancelBtn = getCancelButton(ui)
	if not field or not doneBtn then
		warn("[CodeInput] Missing InputField or Done button in InputName UI")
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
		
		-- Basic validation: code must be at least 1 character
		if #raw < 1 then
			Say:Say("", true, {"Please enter a code."})
			field.Text = ""
			field:CaptureFocus()
			return
		end
		
		-- Limit code length to prevent abuse
		if #raw > 50 then
			Say:Say("", true, {"Code is too long. Maximum 50 characters."})
			field.Text = ""
			field:CaptureFocus()
			return
		end

		result = raw
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

return CodeInput


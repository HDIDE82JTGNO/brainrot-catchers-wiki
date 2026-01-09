--!strict
-- Handles incoming battle/trade requests with a simple queue and accept/decline UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Events")
local LocalPlayer = Players.LocalPlayer

type RequestData = {
	RequestId: any?,
	FromUserId: number?,
	FromDisplayName: string?,
	Type: string?, -- "Battle" | "Trade"
	InfoText: string?,
	LevelMode: string?, -- "keep" | "50" | "100"
}

local CurrentRequest = {}
CurrentRequest.__index = CurrentRequest

local _queue: {RequestData} = {}
local _showing: RequestData? = nil
local _connections: {RBXScriptConnection} = {}

local function getUI()
	local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local gameUI = pg and pg:FindFirstChild("GameUI")
	local frame = gameUI and gameUI:FindFirstChild("CurrentRequest")
	return frame
end

local function clearConnections()
	for _, c in ipairs(_connections) do
		if c.Connected then c:Disconnect() end
	end
	table.clear(_connections)
end

local function mapLevelMode(mode: string?): string
	if mode == "50" then return "Lv. 50" end
	if mode == "100" then return "Lv. 100" end
	return "All SameLevel"
end

local function headshot(userId: number?): string
	if not userId then return "" end
	return "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(userId) .. "&width=150&height=150&format=png"
end

local function hideUI()
	local frame = getUI()
	if frame then
		frame.Visible = false
	end
	_showing = nil
	clearConnections()
end

local function showNext()
	if _showing or #_queue == 0 then return end
	local data = table.remove(_queue, 1)
	_showing = data

	local frame = getUI()
	if not frame then
		_showing = nil
		return
	end

	local reqType = frame:FindFirstChild("RequestType", true)
	local displayText = reqType and reqType:FindFirstChild("DisplayText")
	local icon = frame:FindFirstChild("Icon", true)
	local displayName = frame:FindFirstChild("DisplayName", true)
	local requestInfo = frame:FindFirstChild("RequestInfo", true)
	local acceptBtn = frame:FindFirstChild("Accept", true)
	local declineBtn = frame:FindFirstChild("Decline", true)

	if displayText and displayText:IsA("TextLabel") then
		displayText.Text = (data.Type == "Trade") and "Trade Request" or "Battle Request"
	end
	if displayName and displayName:IsA("TextLabel") then
		displayName.Text = data.FromDisplayName or "Unknown"
	end
	if icon and icon:IsA("ImageLabel") then
		icon.Image = headshot(data.FromUserId)
	end
	if requestInfo and requestInfo:IsA("TextLabel") then
		if data.Type == "Trade" then
			requestInfo.Text = "Wants to trade!"
		else
			local modeLabel = mapLevelMode(data.LevelMode)
			requestInfo.Text = ("1v1  |  %s | Default"):format(modeLabel)
		end
	end

	frame.Visible = true

	local function sendReply(accepted: boolean)
		if not _showing then return end
		local verb = (_showing.Type == "Trade") and "TradeRequestReply" or "BattleRequestReply"
		Events.Request:InvokeServer({verb, {
			RequestId = _showing.RequestId,
			FromUserId = _showing.FromUserId,
			Accepted = accepted,
		}})
		if accepted and _showing.Type == "Trade" then
			print("[Trade] Accepted trade request from", _showing.FromDisplayName or "Player")
		end
	end

	if acceptBtn and acceptBtn:IsA("TextButton") then
		table.insert(_connections, acceptBtn.MouseButton1Click:Connect(function()
			sendReply(true)
			-- Clear queue because we're now busy
			table.clear(_queue)
			hideUI()
		end))
	end

	if declineBtn and declineBtn:IsA("TextButton") then
		table.insert(_connections, declineBtn.MouseButton1Click:Connect(function()
			sendReply(false)
			hideUI()
			showNext()
		end))
	end
end

function CurrentRequest:AddRequest(data: RequestData)
	table.insert(_queue, data)
	if not _showing then
		showNext()
	end
end

function CurrentRequest:HandleIncoming(eventType: string, payload: any)
	if eventType == "BattleRequestIncoming" then
		if type(payload) ~= "table" then return end
		self:AddRequest({
			RequestId = payload.RequestId,
			FromUserId = payload.FromUserId,
			FromDisplayName = payload.FromDisplayName or "Player",
			Type = "Battle",
			LevelMode = payload.LevelMode,
		})
	elseif eventType == "TradeRequestIncoming" then
		if type(payload) ~= "table" then return end
		self:AddRequest({
			RequestId = payload.RequestId,
			FromUserId = payload.FromUserId,
			FromDisplayName = payload.FromDisplayName or "Player",
			Type = "Trade",
		})
	elseif eventType == "ClearRequests" then
		table.clear(_queue)
		hideUI()
	end
end

return CurrentRequest


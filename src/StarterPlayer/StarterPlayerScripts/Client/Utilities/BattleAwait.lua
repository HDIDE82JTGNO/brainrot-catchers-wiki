--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattleAwait = {}

local Events = ReplicatedStorage:WaitForChild("Events")
local Communicate = Events:WaitForChild("Communicate")

local RelocationSignals = require(script.Parent:WaitForChild("RelocationSignals"))

-- Waits for a BattleOver event followed by relocation back to overworld.
-- Returns (success, reasonString?) where reasonString may be "Win"/"Lose"/etc.
function BattleAwait.waitForBattleOverAndRelocation(timeoutSeconds: number?): (boolean, string?)
	local timeout = (type(timeoutSeconds) == "number" and timeoutSeconds or 90)
	local gotBattleOver = false
	local reason: string? = nil

	local battleConn: RBXScriptConnection? = nil
	local relocateConn: RBXScriptConnection? = nil

	local done = false
	local ok = false

	local function cleanup()
		if battleConn then battleConn:Disconnect() battleConn = nil end
		if relocateConn then relocateConn:Disconnect() relocateConn = nil end
	end

	battleConn = Communicate.OnClientEvent:Connect(function(eventType, data)
		if eventType ~= "BattleOver" then return end
		gotBattleOver = true
		if type(data) == "table" and type(data.Reason) == "string" then
			reason = data.Reason
		end
	end)

	relocateConn = RelocationSignals.OnPostBattleRelocated(function(_ctx)
		if not gotBattleOver then
			-- Ignore relocations that might not be battle-driven
			return
		end
		ok = true
		done = true
	end)

	local t0 = os.clock()
	while not done and (os.clock() - t0) < timeout do
		task.wait(0.1)
	end
	cleanup()
	return ok, reason
end

return BattleAwait



local RS = game:GetService("ReplicatedStorage")
local Request = RS:WaitForChild("Events"):WaitForChild("Request")
local DBG = require(RS:WaitForChild("Shared"):WaitForChild("DBG"))
local ClientData = {}

local CD = false
local Current = nil

--We request our own client data.
function ClientData:Init()
    if CD == true or Current then return Current end --If we are on a cooldown, just send back the current data we have stored.
    CD = true
    local Response = nil
    local attempts = 0
    local maxAttempts = 6 -- ~1.95s total with backoff below
    local delayMs = 0.05
    while attempts < maxAttempts and Response == nil do
        attempts += 1
        local ok, res = pcall(function()
            return Request:InvokeServer({"DataGet"})
        end)
        if ok then Response = res end
        if Response == nil then
            task.wait(delayMs)
            delayMs = math.min(delayMs * 2, 0.5)
        end
    end
    -- Fallback: try subscribe to a one-time update from server if available
    if Response == nil then
        local Events = RS:WaitForChild("Events")
        local Communicate = Events:WaitForChild("Communicate")
        local received = false
        local conn
        conn = Communicate.OnClientEvent:Connect(function(t, data)
            if t == "ClientData" and data ~= nil then
                Response = data
                received = true
                if conn then conn:Disconnect() end
            end
        end)
        -- Wait briefly for server push (e.g., after load completes)
        local start = os.clock()
        while not received and (os.clock() - start) < 1.0 do
            task.wait(0.05)
        end
        if conn then conn:Disconnect() end
    end
    Current = Response
    CD = false
    return Current
end

--Server forcefully updates our client data.
function ClientData:ServerForceUpdateData(Data)
	Current = Data
	DBG:print("CLIENT DATA: Force updated by server")
	DBG:print("Data received:", Current)
	-- Notify UI modules that rely on client data to refresh
	local UI = require(script.Parent.Parent.UI)

	if UI then
		-- Party UI (auto-loads on open)
		if UI.Party and UI.Party.UpdatePartyDisplay then
			pcall(function()
				-- Guard: do not refresh Party while client is mid-animation
				if not UI.Party.IsAnimating then
					print("[ClientData] ServerForceUpdateData -> Party.UpdatePartyDisplay() (not animating)")
					UI.Party:UpdatePartyDisplay()
				else
					print("[ClientData] ServerForceUpdateData SKIPPED (Party animating)")
				end
			end)
		end

		-- Bag UI: inventory changes
		if UI.Bag and UI.Bag.RefreshBag then
			pcall(function()
				print("[ClientData] ServerForceUpdateData -> Bag.RefreshBag()")
				UI.Bag:RefreshBag()
			end)
		end

		-- Dex UI: new captures / box changes
		if UI.Dex and UI.Dex.Refresh then
			pcall(function()
				print("[ClientData] ServerForceUpdateData -> Dex.Refresh()")
				UI.Dex:Refresh()
			end)
		end
	end
end

function ClientData:GotSuccessfulSave()
	--Server told us our data has successfully saved
	print("CLIENT: GotSuccessfulSave!")
end

function ClientData:Get() return ClientData:Init() end

return ClientData
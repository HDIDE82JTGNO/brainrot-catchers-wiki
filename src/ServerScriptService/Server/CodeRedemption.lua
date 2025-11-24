--!strict
--[[
	CodeRedemption.lua
	Handles code redemption system with Pastebin integration
	Allows dynamic code updates without server restarts
]]

local CodeRedemption = {}

-- Dependencies (will be injected)
local ClientData: any = nil
local DBG: any = nil
local ServerFunctions: any = nil

-- Pastebin URL for code list (update this with your actual Pastebin raw URL)
local PASTEBIN_URL = "https://pastebin.com/raw/0GxUSXYx"

-- Cache for fetched codes (refreshed periodically)
local _cachedCodes: {[string]: boolean} = {}
local _lastFetchTime: number = 0
local CACHE_DURATION: number = 300 -- 5 minutes

--[[
	Initialize CodeRedemption with dependencies
]]
function CodeRedemption.Initialize(dependencies: {[string]: any})
	ClientData = dependencies.ClientData
	DBG = dependencies.DBG
	ServerFunctions = dependencies.ServerFunctions
end

--[[
	Fetch codes from Pastebin
	@return table Array of code strings, or empty table on error
]]
function CodeRedemption.FetchCodesFromPastebin(): {string}
	local HttpService = game:GetService("HttpService")
	
	local success, result = pcall(function()
		return HttpService:RequestAsync({
			Url = PASTEBIN_URL,
			Method = "GET",
		})
	end)
	
	if not success or not result then
		DBG:warn("[CodeRedemption] Failed to fetch codes from Pastebin")
		return {}
	end
	
	if result.Success ~= true or not result.Body then
		DBG:warn("[CodeRedemption] Pastebin request failed:", result.StatusCode)
		return {}
	end
	
	local parseSuccess, decoded = pcall(function()
		return HttpService:JSONDecode(result.Body)
	end)
	
	if not parseSuccess or type(decoded) ~= "table" then
		DBG:warn("[CodeRedemption] Failed to parse Pastebin JSON. Body:", result.Body)
		if not parseSuccess then
			DBG:warn("[CodeRedemption] Parse error:", decoded)
		end
		return {}
	end
	
	-- Convert array to lookup table for faster checking
	local codes: {[string]: boolean} = {}
	for _, code in ipairs(decoded) do
		if type(code) == "string" then
			codes[code:upper()] = true
		end
	end
	
	_cachedCodes = codes
	_lastFetchTime = os.time()
	
	DBG:print("[CodeRedemption] Fetched", #decoded, "codes from Pastebin")
	return decoded
end

--[[
	Get cached codes, refreshing if needed
	@return table Lookup table of code strings
]]
function CodeRedemption.GetCodes(): {[string]: boolean}
	local now = os.time()
	if now - _lastFetchTime > CACHE_DURATION or next(_cachedCodes) == nil then
		CodeRedemption.FetchCodesFromPastebin()
	end
	return _cachedCodes
end

--[[
	Check if a code exists and is valid
	@param code The code string to check
	@return boolean True if code exists
]]
function CodeRedemption.CodeExists(code: string): boolean
	if type(code) ~= "string" or code == "" then
		return false
	end
	
	local codes = CodeRedemption.GetCodes()
	return codes[code:upper()] == true
end

--[[
	Check if a player has already redeemed a code
	@param Player The player
	@param code The code string (will be normalized to uppercase)
	@return boolean True if already redeemed
]]
function CodeRedemption.HasRedeemedCode(Player: Player, code: string): boolean
	local PlayerData = ClientData:Get(Player)
	if not PlayerData then return false end
	
	PlayerData.RedeemedCodes = PlayerData.RedeemedCodes or {}
	local normalizedCode = code:upper()
	return PlayerData.RedeemedCodes[normalizedCode] == true
end

--[[
	Mark a code as redeemed for a player
	@param Player The player
	@param code The code string (will be normalized to uppercase)
]]
function CodeRedemption.MarkCodeRedeemed(Player: Player, code: string): ()
	local PlayerData = ClientData:Get(Player)
	if not PlayerData then return end
	
	PlayerData.RedeemedCodes = PlayerData.RedeemedCodes or {}
	local normalizedCode = code:upper()
	PlayerData.RedeemedCodes[normalizedCode] = true
	
	if ClientData.UpdateClientData then
		ClientData:UpdateClientData(Player, PlayerData)
	end
end

--[[
	Code reward handlers
	Each function receives the Player and should grant rewards via ServerFunctions:GrantItem
	Function names must match pattern: OnClaim_<CODE_NAME>
]]

-- Example: TESTING code
function CodeRedemption.OnClaim_TESTING(Player: Player): ()
	ServerFunctions:GrantItem(Player, "Potion", 1)
	DBG:print("[CodeRedemption] TESTING code redeemed by", Player.Name)
end

-- Example: FREEPOTION code
function CodeRedemption.OnClaim_FREEPOTION(Player: Player): ()
	ServerFunctions:GrantItem(Player, "Potion", 1)
	DBG:print("[CodeRedemption] FREEPOTION code redeemed by", Player.Name)
end

-- Example: XMAS2025 code
function CodeRedemption.OnClaim_XMAS2025(Player: Player): ()
	ServerFunctions:GrantItem(Player, "Potion", 1)
	ServerFunctions:GrantItem(Player, "Apple", 3)
	DBG:print("[CodeRedemption] XMAS2025 code redeemed by", Player.Name)
end

--[[
	Execute code reward handler
	@param Player The player
	@param code The code string
	@return boolean, string Success status and message
]]
function CodeRedemption.ExecuteCodeReward(Player: Player, code: string): (boolean, string)
	if type(code) ~= "string" or code == "" then
		return false, "Invalid code format."
	end
	
	local normalizedCode = code:upper()
	local handlerName = "OnClaim_" .. normalizedCode
	local handler = CodeRedemption[handlerName]
	
	if type(handler) ~= "function" then
		return false, "Code reward handler not found."
	end
	
	local success, err = pcall(function()
		handler(Player)
	end)
	
	if not success then
		DBG:warn("[CodeRedemption] Error executing code reward:", err)
		return false, "Failed to grant rewards."
	end
	
	return true, "Code redeemed successfully!"
end

--[[
	Redeem a code for a player
	@param Player The player
	@param code The code string to redeem
	@return boolean, string Success status and message
]]
function CodeRedemption.RedeemCode(Player: Player, code: string): (boolean, string)
	if type(code) ~= "string" then
		return false, "Invalid code format."
	end
	
	-- Normalize code to uppercase
	local normalizedCode = code:upper():gsub("%s+", "") -- Remove whitespace
	
	if normalizedCode == "" then
		return false, "Code cannot be empty."
	end
	
	-- Check if code exists
	if not CodeRedemption.CodeExists(normalizedCode) then
		return false, "Code does not exist or has expired."
	end
	
	-- Check if already redeemed
	if CodeRedemption.HasRedeemedCode(Player, normalizedCode) then
		return false, "You have already redeemed this code."
	end
	
	-- Execute reward handler
	local success, message = CodeRedemption.ExecuteCodeReward(Player, normalizedCode)
	if not success then
		return false, message
	end
	
	-- Mark as redeemed
	CodeRedemption.MarkCodeRedeemed(Player, normalizedCode)
	
	return true, message
end

return CodeRedemption


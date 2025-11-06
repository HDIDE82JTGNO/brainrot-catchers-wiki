local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local WebhookService = {}

-- Static webhook URL
local webhookURL = "https://webhook.lewisakura.moe/api/webhooks/1412867552279003337/Do_z5dXi0ogWWw7DxGCzFYCyAU_cnmjc5TeTVd-sBUFb2TtlfmyJBtirpAvw6xT4Ui_e"

-- Helper function to get Roblox avatar URL from UserId
local function getAvatarURL(userId)
	return "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(userId) .. "&width=420&height=420&format=png"
end

-- Sends a rich embed to the static Discord webhook
-- title: string - embed title
-- description: string - main content
-- playerOrUserId: Player object or number (optional) - to get avatar automatically
-- color: number (optional) - embed color in decimal format
function WebhookService:SendEmbed(title, description, playerOrUserId, color)
	assert(title and description, "Title and description are required")
	
	warn("TRYING")

	local embed = {
		["title"] = title,
		["description"] = description,
		["color"] = color or 0x1ABC9C, -- default teal color
		["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ"), -- UTC timestamp
		["footer"] = {
			["text"] = "Brainrot Catchers",
		}
	}

	local data = {
		["embeds"] = {embed}
	}

	-- Set avatar if player or UserId is passed
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		data["avatar_url"] = getAvatarURL(playerOrUserId.UserId)
	elseif typeof(playerOrUserId) == "number" then
		data["avatar_url"] = getAvatarURL(playerOrUserId)
	end

	local jsonData = HttpService:JSONEncode(data)

	local success, response = pcall(function()
		return HttpService:PostAsync(webhookURL, jsonData, Enum.HttpContentType.ApplicationJson)
	end)

	if success then
		print("Embed sent successfully!")
	else
		warn("Failed to send embed: " .. tostring(response))
	end
end

return WebhookService

local DeviceService = {}
DeviceService.__index = DeviceService

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VRService = game:GetService("VRService")
local TextService = game:GetService("TextService")
local Enumate = require(script:WaitForChild("_Enum"))

local sub = string.sub
local match = string.match
local len = string.len
local lower = string.lower

-- Create Signals
local function createSignal()
	local bindable = Instance.new("BindableEvent")
	local signal = {}

	function signal:Connect(fn)
		return bindable.Event:Connect(fn)
	end

	function signal:Fire(...)
		bindable:Fire(...)
	end

	return signal
end

-- Signals we create events so gurt
DeviceService.CheckDeviceType = createSignal()
DeviceService.CheckDevicePlatform = createSignal()

-- Text check setup
local TextSettings = {
	16,
	"SourceSans",
	Vector2.one * 1000,
}

local invalidSize = TextService:GetTextSize("\u{FFFF}", unpack(TextSettings))

local function isValidCharacter(character)
	local size = TextService:GetTextSize(character, unpack(TextSettings))
	return size.Magnitude ~= invalidSize.Magnitude
end

local function getArchitecture()
	local address = tonumber(sub(tostring{math.huge}, 8))
	if len(tostring(address)) <= 10 then
		return 32
	end
	return 64
end

-- Device Type detection
function DeviceService:_internalDetect()
	wait()

	local size = workspace.CurrentCamera.ViewportSize

	if UserInputService.TouchEnabled then
		if tonumber(size.X) >= 1024 and tonumber(size.Y) >= 768 then
			return Enumate.DeviceType.Tablet
		elseif tonumber(size.X) >= 800 and tonumber(size.Y) >= 480 then
			return Enumate.DeviceType.Phone
		elseif tonumber(size.X) < 800 then
			return Enumate.DeviceType.SmallPhone
		else
			return Enumate.DeviceType.Unknown
		end
	else
		if UserInputService.KeyboardEnabled and UserInputService.MouseEnabled then
			return Enumate.DeviceType.Computer
		elseif UserInputService.GamepadEnabled then
			return Enumate.DeviceType.Console
		end
	end
end

--get platform i just got ts off devforum thank you @ChatGGPT from dev forum and @SomeFedoraGuy
function DeviceService:GetDevicePlatform()
	local version = version()
	local Desktop = match(version, "^0%.") ~= nil
	local Console = GuiService:IsTenFootInterface() or (match(version, "^1%.") ~= nil)
	local Mobile = match(version, "^2%.") ~= nil
	local VR = UserInputService.VREnabled and VRService.VREnabled

	if GuiService.IsWindows then
		if Mobile then
			return Enumate.Platform.UWP
		elseif Console then
			return Enumate.Platform.XboxOne
		elseif isValidCharacter("\u{E0FF}") then
			return Enumate.Platform.Linux
		end
		return Enumate.Platform.Windows
	elseif Desktop then
		return Enumate.Platform.OSX
	elseif Console then
		local ButtonSelect = lower(UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonSelect))
		if match(ButtonSelect, "ps4") then
			return Enumate.Platform.PS4
		elseif match(ButtonSelect, "ps5") then
			return Enumate.Platform.PS5
		elseif match(ButtonSelect, "xbox") then
			return Enumate.Platform.XboxOne
		end
	elseif Mobile then
		if VR then
			return Enumate.Platform.MetaOS
		elseif getArchitecture() == 32 or not isValidCharacter("\u{F8FF}") then
			if not UserInputService.TouchEnabled then
				return Enumate.Platform.Linux
			end
			return Enumate.Platform.Android
		end
		return Enumate.Platform.IOS
	elseif VR then
		return Enumate.Platform.VR
	end

	return Enumate.Platform.Unknown
end

function DeviceService:IsInGroup(deviceType, group)
	return bit32.band(group, deviceType) ~= 0
end

-- Call this to fire device + platform info
function DeviceService:Emit()
	local device = self:_internalDetect()
	local platform = self:GetDevicePlatform()

	self.CheckDeviceType:Fire(device)
	self.CheckDevicePlatform:Fire(platform)
end

function DeviceService:Init()
	local device = self:_internalDetect()
	local platform = self:GetDevicePlatform()

	task.defer(function()
		self.CheckDeviceType:Fire(device)
		self.CheckDevicePlatform:Fire(platform)
	end)
end

-- Exports
DeviceService.Enumate = Enumate
DeviceService.DeviceType = Enumate.DeviceType

return DeviceService

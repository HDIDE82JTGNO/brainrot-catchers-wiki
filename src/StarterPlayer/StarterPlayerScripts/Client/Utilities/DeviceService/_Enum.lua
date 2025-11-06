local Enumate = {}

Enumate.DeviceType = {
	Phone = 0x01,
	Tablet = 0x02,
	SmallPhone = 0x04,
	Console = 0x08,
	Computer = 0x10,
	Unknown = 0xFFFF,
	Potato = 0x40,
	Name = {
		[0x01] = "Phone",
		[0x02] = "Tablet",
		[0x04] = "SmallPhone",
		[0x08] = "Console",
		[0x10] = "Computer",
		[0x40] = "Potato",
		[0xFFFF] = "Unknown",
	}
}

Enumate.Platform = {
	UWP = 0x1a,
	XboxOne = 0x1b,
	Linux = 0x1c,
	Windows = 0x1d,
	OSX = 0x1e,
	PS4 = 0x1f,
	PS5 = 0x2a,
	Android = 0x2b,
	IOS = 0x2c,
	VR = 0x2d,
	MetaOS = 0x2e,
	Unknown = 0xFFFF,
	Name = {
		[0x1a] = "UWP",
		[0x1b] = "XboxOne",
		[0x1c] = "Linux",
		[0x1d] = "Windows",
		[0x1e] = "OSX",
		[0x1f] = "PS4",
		[0x2a] = "PS5",
		[0x2b] = "Android",
		[0x2c] = "IOS",
		[0x2d] = "VR",
		[0x2e] = "MetaOS",
		[0xFFFF] = "Unknown"
	}
}

Enumate.DeviceGroup = {
	Mobile = bit32.bor(Enumate.DeviceType.Phone, Enumate.DeviceType.Tablet, Enumate.DeviceType.SmallPhone),
	Desktop = bit32.bor(Enumate.DeviceType.Computer, Enumate.DeviceType.Console),
}

Enumate.PlatformGroup = {
	Mobile = bit32.bor(Enumate.Platform.IOS,Enumate.Platform.Android),
	Desktop = bit32.bor(Enumate.Platform.Windows,Enumate.Platform.Linux,Enumate.Platform.OSX,Enumate.Platform.UWP),
	Console = bit32.bor(Enumate.Platform.PS4,Enumate.Platform.PS5,Enumate.Platform.XboxOne),
}

return Enumate 
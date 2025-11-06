local DBG = {}

local Enabled = true

function DBG:Init(DebugEnabled:boolean)
	Enabled = DebugEnabled
end

function DBG:print(...)
	if Enabled then
		print(...)
	end
end

function DBG:warn(...)
	if Enabled then
		warn(...)
	end
end

return DBG


local DayNightApi = {}

function DayNightApi.apply(ServerFunctions, deps)
	local DayNightCycle = deps.DayNightCycle

	function ServerFunctions:GetCurrentTimePeriod()
		return DayNightCycle:GetCurrentPeriod()
	end

	function ServerFunctions:GetTimeOfDay()
		return DayNightCycle:GetTimeOfDay()
	end

	function ServerFunctions:IsDay()
		return DayNightCycle:IsDay()
	end

	function ServerFunctions:IsDusk()
		return DayNightCycle:IsDusk()
	end

	function ServerFunctions:IsNight()
		return DayNightCycle:IsNight()
	end

	function ServerFunctions:GetFormattedTime()
		return DayNightCycle:GetFormattedTime()
	end

	function ServerFunctions:GetTimeUntilNextPeriod()
		return DayNightCycle:GetTimeUntilNextPeriod()
	end

	function ServerFunctions:GetDayNightCycle()
		return DayNightCycle
	end

	DayNightCycle:Initialize()
end

return DayNightApi


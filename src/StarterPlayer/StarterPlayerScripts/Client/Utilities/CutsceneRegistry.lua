-- CutsceneRegistry
-- Tracks active cutscenes without globals and provides a clean API

--!strict

export type Registry = {
	Start: (self: Registry, name: string) -> (),
	End: (self: Registry, name: string) -> (),
	IsActive: (self: Registry, name: string) -> boolean,
	IsAnyActive: (self: Registry) -> boolean,
	GetActiveNames: (self: Registry) -> {string},
}

local CutsceneRegistry = {}
CutsceneRegistry.__index = CutsceneRegistry

function CutsceneRegistry.new(): Registry
	local self: any = setmetatable({}, CutsceneRegistry)
	self._active = {} :: {[string]: boolean}
	return (self :: Registry)
end

function CutsceneRegistry:Start(name: string): ()
	(self :: any)._active[name] = true
end

function CutsceneRegistry:End(name: string): ()
	(self :: any)._active[name] = false
end

function CutsceneRegistry:IsActive(name: string): boolean
	return ((self :: any)._active[name] == true)
end

function CutsceneRegistry:IsAnyActive(): boolean
	for _, isActive in pairs((self :: any)._active) do
		if isActive == true then
			return true
		end
	end
	return false
end

function CutsceneRegistry:GetActiveNames(): {string}
	local out = {} :: {string}
	for name, isActive in pairs((self :: any)._active) do
		if isActive == true then
			table.insert(out, name)
		end
	end
	return out
end

local DefaultRegistry = CutsceneRegistry.new()
return DefaultRegistry



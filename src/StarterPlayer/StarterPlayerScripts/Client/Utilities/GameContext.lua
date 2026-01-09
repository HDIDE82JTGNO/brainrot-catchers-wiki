local Workspace = game:GetService("Workspace")

local DEFAULT_CONTEXT = "Story"
local VALID_CONTEXTS = {
	Story = true,
	Trade = true,
	Battle = true,
}

local GameContext = {}
local currentContext = DEFAULT_CONTEXT

local function normalizeContext(value: any): string
	if type(value) ~= "string" then
		return DEFAULT_CONTEXT
	end

	if VALID_CONTEXTS[value] then
		return value
	end

	return DEFAULT_CONTEXT
end

local function setContext(nextValue: any): string
	currentContext = normalizeContext(nextValue)
	return currentContext
end

-- Initialize from workspace attribute (defaults to Story if missing/invalid)
setContext(Workspace:GetAttribute("Context"))

-- Keep local cache in sync with workspace attribute changes
pcall(function()
	Workspace:GetAttributeChangedSignal("Context"):Connect(function()
		setContext(Workspace:GetAttribute("Context"))
	end)
end)

function GameContext:Get(): string
	return currentContext
end

function GameContext:Is(target: string): boolean
	return currentContext == target
end

-- For modes that require a specific starting chunk (e.g., Trade, Battle)
function GameContext:GetTargetChunk(): string?
	if currentContext == "Trade" then
		return "Trade"
	end

	if currentContext == "Battle" then
		return "Battle"
	end

	return nil
end

-- Allow manual override if needed by other systems
function GameContext:Set(value: string): string
	return setContext(value)
end

return GameContext

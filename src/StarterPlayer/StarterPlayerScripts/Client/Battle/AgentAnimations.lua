--!strict
--[[
	AgentAnimations.lua
	Helper module for playing animations on agent (trainer NPC) models during battles
	Provides safe wrappers that check for agent existence and battle type
]]

local TrainerIntroController = require(script.Parent.Parent.Utilities.TrainerIntroController)

local AgentAnimations = {}

-- Animation IDs
local ANIMATION_IDS = {
	NormalDamage = "120974733168132",
	SuperEffectiveDamage = "90321270878901",
	SendOut = "78441710358556",
	Action = "112853490819909",
}

-- Preloaded animation tracks cache
local _preloadedTracks: {[string]: AnimationTrack?} = {}

--[[
	Internal: Gets the active agent if available
	@return TrainerIntroAgent? The active agent, or nil if not available
]]
local function getActiveAgent()
	return TrainerIntroController:GetActive()
end

--[[
	Internal: Ensures animator exists on agent
	@param agent The agent
	@return Animator? The animator, or nil if not available
]]
local function ensureAnimator(agent: any): Animator?
	if not agent or not agent.Model then
		return nil
	end
	
	local humanoid = agent.Model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator
	else
		local ac = agent.Model:FindFirstChildOfClass("AnimationController")
		if not ac then
			ac = Instance.new("AnimationController")
			ac.Parent = agent.Model
		end
		local animator = ac:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = ac
		end
		return animator
	end
end

--[[
	Preloads all agent animations for faster playback
	Should be called when the agent becomes available (e.g., at battle start)
]]
function AgentAnimations:PreloadAnimations()
	local agent = getActiveAgent()
	if not agent then
		print("[AgentAnimations] Cannot preload - no active agent")
		return
	end
	
	local animator = ensureAnimator(agent)
	if not animator then
		print("[AgentAnimations] Cannot preload - no animator found")
		return
	end
	
	print("[AgentAnimations] Preloading agent animations...")
	
	-- Clear any existing preloaded tracks
	_preloadedTracks = {}
	
	-- Preload each animation
	for name, assetId in pairs(ANIMATION_IDS) do
		local anim = Instance.new("Animation")
		if string.find(assetId, "rbxassetid://", 1, true) then
			anim.AnimationId = assetId
		else
			anim.AnimationId = "rbxassetid://" .. assetId
		end
		
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		
		if ok and track then
			track.Looped = false
			pcall(function()
				track.Priority = Enum.AnimationPriority.Action
			end)
			_preloadedTracks[name] = track
			print("[AgentAnimations] Preloaded animation:", name)
		else
			warn("[AgentAnimations] Failed to preload animation:", name)
			_preloadedTracks[name] = nil
		end
	end
	
	print("[AgentAnimations] Animation preloading complete")
end

--[[
	Internal: Plays a preloaded animation or loads it on demand
	@param animationName The name of the animation (key in ANIMATION_IDS)
	@param fadeTime Optional fade time
	@return AnimationTrack? The animation track
]]
local function playPreloadedAnimation(animationName: string, fadeTime: number?): AnimationTrack?
	local agent = getActiveAgent()
	if not agent then
		return nil
	end
	
	-- Try to use preloaded track first
	local track = _preloadedTracks[animationName]
	if track then
		local ft = (type(fadeTime) == "number" and fadeTime >= 0) and fadeTime or 0.1
		pcall(function()
			track:Play(ft)
		end)
		-- Track playing tracks for cleanup
		if agent._playingTracks then
			table.insert(agent._playingTracks, track)
		end
		return track
	end
	
	-- Fallback to loading on demand if not preloaded
	local assetId = ANIMATION_IDS[animationName]
	if assetId then
		return agent:PlayAnimation(assetId, fadeTime, false)
	end
	
	return nil
end

--[[
	Plays a normal/not very effective damage reaction animation on the agent
	Should be called when the player's move deals normal or not very effective damage to the agent's creature
]]
function AgentAnimations:PlayNormalDamageReaction()
	playPreloadedAnimation("NormalDamage", 0.1)
end

--[[
	Plays a super effective damage reaction animation on the agent
	Should be called when the player's move deals super effective damage to the agent's creature
]]
function AgentAnimations:PlaySuperEffectiveDamageReaction()
	playPreloadedAnimation("SuperEffectiveDamage", 0.1)
end

--[[
	Plays a creature send-out animation on the agent
	Should be called when the agent sends out a new creature
]]
function AgentAnimations:PlaySendOutAnimation()
	playPreloadedAnimation("SendOut", 0.1)
end

--[[
	Plays an action animation on the agent
	Should be called when the agent uses a move or item
]]
function AgentAnimations:PlayActionAnimation()
	playPreloadedAnimation("Action", 0.1)
end

return AgentAnimations


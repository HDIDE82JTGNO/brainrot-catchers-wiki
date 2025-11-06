--!strict

local NPCAnimations = {}
NPCAnimations.__index = NPCAnimations

export type EmotionName =
	"Thinking" | "Talking" | "Smug" | "Sleepy" | "Shy" | "Sad" |
	"Neutral" | "Happy" | "Excited" | "Confused" | "Bored" | "Angry" | "Nervous"

local EMOTION_TO_ASSET: {[string]: string} = {
	Thinking = "rbxassetid://96330194627339",
	Talking = "rbxassetid://110437102401052",
	Smug = "rbxassetid://116184509431414",
	Sleepy = "rbxassetid://112602001209074",
	Shy = "rbxassetid://124965534094622",
	Sad = "rbxassetid://72116622449493",
	Neutral = "rbxassetid://123980712848501",
	Happy = "rbxassetid://94328949610609",
	Excited = "rbxassetid://104821505506421",
	Confused = "rbxassetid://75794920166998",
	Bored = "rbxassetid://93939354651160",
	Angry = "rbxassetid://87629702370664",
	Nervous = "rbxassetid://139976336817715",
}

local function getAnimator(model: Model): Animator?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

-- Preloaded animation tracks cache
local preloadedTracks: {[string]: AnimationTrack} = {}

-- Preload all emotion animations
local function preloadAnimations()
	for emotion, assetId in pairs(EMOTION_TO_ASSET) do
		local anim = Instance.new("Animation")
		anim.AnimationId = assetId
		-- Store the animation object for later use
		preloadedTracks[emotion] = anim
	end
end

local function loadAnimation(animator: Animator, emotion: string): AnimationTrack?
	local anim = preloadedTracks[emotion]
	if not anim then return nil end
	
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true
		return track
	end
	return nil
end

-- Preload animations when module is required
preloadAnimations()

-- Expose asset ids for external preloaders
function NPCAnimations:GetAllAssetIds(): {string}
	local ids = {}
	for _, assetId in pairs(EMOTION_TO_ASSET) do
		table.insert(ids, assetId)
	end
	return ids
end

-- Stops any existing idle/emotion tracks we created previously
function NPCAnimations:StopEmotion(model: Model)
	local animator = getAnimator(model)
	if not animator then return end
	
	-- Stop all idle priority tracks
	for _, obj in ipairs(animator:GetPlayingAnimationTracks()) do
		if obj.Priority == Enum.AnimationPriority.Idle then
			pcall(function() obj:Stop() end)
		end
	end
	
	-- Restore original animation if we stored one
	local originalAnim = model:GetAttribute("OriginalAnimation")
	if originalAnim and originalAnim ~= "" then
		-- Load and play the original animation
		local anim = Instance.new("Animation")
		anim.AnimationId = originalAnim
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Idle
			track.Looped = true
			pcall(function() track:Play() end)
		end
		-- Clear the stored animation
		model:SetAttribute("OriginalAnimation", nil)
	end
end

-- Plays an emotion loop on the NPC model
function NPCAnimations:PlayEmotionLoop(model: Model, emotion: EmotionName)
	-- Respect custom dialogue animation flag; never override
	if model:GetAttribute("HasCustomDialogueAnim") == true then
		return
	end
	local animator = getAnimator(model)
	if not animator then return end
	
	-- Store the current animation as the original if we haven't already
	local originalAnim = model:GetAttribute("OriginalAnimation")
	if not originalAnim or originalAnim == "" then
		-- Find the current idle animation to store as original
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Idle then
				-- Store the animation ID
				local animId = track.Animation.AnimationId
				model:SetAttribute("OriginalAnimation", animId)
				break
			end
		end
	end
	
	-- Stop any existing idle/emotion tracks to avoid layering
	for _, obj in ipairs(animator:GetPlayingAnimationTracks()) do
		if obj.Priority == Enum.AnimationPriority.Idle then
			pcall(function() obj:Stop() end)
		end
	end
	
	local track = loadAnimation(animator, emotion)
	if track then
		pcall(function() track:Play() end)
	end
end

return NPCAnimations



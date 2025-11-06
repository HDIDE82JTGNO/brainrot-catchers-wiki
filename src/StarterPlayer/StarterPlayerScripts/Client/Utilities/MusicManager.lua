local MusicManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local DBG = require(ReplicatedStorage.Shared.DBG)
local ClientData = require(script.Parent.Parent.Plugins.ClientData)

-- Music settings
local FADE_OUT_TIME = 1.5
local FADE_IN_TIME = 2.0
local FULL_VOLUME = 1.0 -- 100% volume for chunks with music
local REDUCED_VOLUME = 0.4 -- 60% volume for chunks without music

-- Current music tracking
local CurrentMusic = nil
local CurrentMusicConnection = nil
local CurrentVolume = FULL_VOLUME
local OriginalVolume = FULL_VOLUME -- Track the original volume before reduction
local IsReduced = false -- Track if we're currently in reduced volume state
local VolumeBeforeMute = FULL_VOLUME -- Track volume before muting

-- Encounter music tracking
local EncounterMusic = nil
local TrainerIntroMusic = nil -- EyesMeet
local TrainerBattleMusic = nil
local ENCOUNTER_VOLUME = 1.0
local ENCOUNTER_FADE_IN = 0.6
local ENCOUNTER_FADE_OUT = 0.6
local ChunkResumeVolume = FULL_VOLUME

-- Victory track tracking
local VictoryMusic = nil
local VICTORY_VOLUME = 1.0
local VICTORY_FADE_IN = 0.6
local VICTORY_FADE_OUT = 0.8

-- Optional one-shot override for next trainer battle track
local TrainerBattleOverrideName: string? = nil

-- Create a sound object for music
local function CreateMusicSound(soundId, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0 -- Start at 0 for fade in
	sound.Looped = true
	sound.Parent = SoundService
	return sound
end

-- Query if victory music is currently playing
function MusicManager:IsVictoryPlaying(): boolean
    return VictoryMusic ~= nil
end

local function GetSoundIdFromSound(sound: Sound?)
    if sound and sound:IsA("Sound") then
        return sound.SoundId
    end
    return nil
end

-- Get the volume from ChunkMusic object
local function GetChunkMusicVolume(chunkMusic)
	if chunkMusic and chunkMusic:IsA("Sound") then
		return chunkMusic.Volume
	end
	return FULL_VOLUME -- Default to full volume if no volume specified
end

-- Fade out current music
local function FadeOutMusic()
	if not CurrentMusic then
		return
	end
	
	DBG:print("Fading out current music")
	
	local fadeOutTween = TweenService:Create(CurrentMusic, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0
	})
	
	fadeOutTween:Play()
	fadeOutTween.Completed:Connect(function()
		if CurrentMusic then
			CurrentMusic:Stop()
			CurrentMusic:Destroy()
			CurrentMusic = nil
		end
	end)
end

-- Utility: safely stop and destroy a sound with fade
local function FadeOutAndDestroy(sound: Sound?, duration: number)
    if not sound then return end
    local fade = TweenService:Create(sound, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 0 })
    fade.Completed:Connect(function()
        pcall(function()
            sound:Stop()
            sound:Destroy()
        end)
    end)
    fade:Play()
end

-- Stop all trainer intro stings defensively (handles multiple starts)
local function StopAllTrainerIntro()
    -- Stop reference if present
    if TrainerIntroMusic then
        local im = TrainerIntroMusic
        TrainerIntroMusic = nil
        FadeOutAndDestroy(im, 0.3)
    end
    -- Also scan SoundService for any lingering stings created earlier
    for _, child in ipairs(SoundService:GetChildren()) do
        if child:IsA("Sound") and child.Name == "TrainerIntro_EyesMeet" then
            FadeOutAndDestroy(child, 0.3)
        end
    end
end

-- Fade in new music
local function FadeInMusic(soundId, targetVolume)
	-- Check if music is muted
	local playerData = ClientData:Get()
	local isMuted = (playerData and playerData.Settings and playerData.Settings.MuteMusic) == true
	if isMuted then
		DBG:print("Music is muted, not playing new music")
		return
	end
	
	-- Create and play new music
	CurrentMusic = CreateMusicSound(soundId, targetVolume)
	CurrentMusic:Play()
	CurrentVolume = targetVolume
	OriginalVolume = targetVolume -- Set original volume for new music
	VolumeBeforeMute = targetVolume -- Initialize volume before mute
	IsReduced = false -- Reset reduced state for new music
	DBG:print("New music started - Current volume:", CurrentVolume, "Original volume:", OriginalVolume, "VolumeBeforeMute:", VolumeBeforeMute, "IsReduced:", IsReduced)
	
	DBG:print("Fading in new music:", soundId, "at volume:", targetVolume)
	
	local fadeInTween = TweenService:Create(CurrentMusic, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = targetVolume
	})
	
	fadeInTween:Play()
end

-- Handle music mute setting changes
local function OnMuteMusicChanged(isMuted)
	DBG:print("=== OnMuteMusicChanged called ===")
	DBG:print("isMuted:", isMuted)
	DBG:print("CurrentMusic exists:", CurrentMusic ~= nil)
	if CurrentMusic then
		DBG:print("CurrentVolume:", CurrentVolume)
		DBG:print("CurrentMusic.Volume:", CurrentMusic.Volume)
	end
	
	if isMuted then
		-- Mute current music
		if CurrentMusic then
			-- Only store volume if it's not already 0 (not already muted)
			if CurrentMusic.Volume > 0 then
				VolumeBeforeMute = CurrentMusic.Volume
				DBG:print("Muting current music, storing volume:", VolumeBeforeMute)
			else
				DBG:print("Music already muted, keeping stored volume:", VolumeBeforeMute)
			end
			local muteTween = TweenService:Create(CurrentMusic, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = 0
			})
			muteTween:Play()
		else
			DBG:print("No current music to mute")
		end
	else
		-- Unmute current music
		if CurrentMusic then
			DBG:print("Unmuting current music to volume:", VolumeBeforeMute)
			local unmuteTween = TweenService:Create(CurrentMusic, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = VolumeBeforeMute
			})
			unmuteTween:Play()
		else
			DBG:print("No current music to unmute")
		end
	end
end

-- Set music for a chunk
function MusicManager:SetChunkMusic(chunkEssentials)
	DBG:print("=== SetChunkMusic called ===")
	DBG:print("Current volume:", CurrentVolume, "Original volume:", OriginalVolume, "IsReduced:", IsReduced)
	
	-- Check if chunk has music
	local chunkMusic = chunkEssentials:FindFirstChild("ChunkMusic")
	DBG:print("ChunkMusic found:", chunkMusic ~= nil)
	if chunkMusic then
		DBG:print("ChunkMusic type:", chunkMusic.ClassName)
		DBG:print("ChunkMusic SoundId:", chunkMusic.SoundId)
		DBG:print("ChunkMusic Volume:", chunkMusic.Volume)
	end
	
	if not chunkMusic or not chunkMusic:IsA("Sound") then
		-- No music in this chunk - reduce volume of current music
		if CurrentMusic then
			-- Store the original volume if we haven't already reduced it
			if not IsReduced then
				OriginalVolume = CurrentVolume
				DBG:print("Stored original volume:", OriginalVolume)
			end
			local reducedVolume = OriginalVolume * REDUCED_VOLUME
			CurrentVolume = reducedVolume
			IsReduced = true
			DBG:print("No ChunkMusic found, reducing current music volume from", OriginalVolume, "to", reducedVolume, "(60% of original)")
			DBG:print("Current volume set to:", CurrentVolume, "IsReduced:", IsReduced)
			local reduceTween = TweenService:Create(CurrentMusic, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = reducedVolume
			})
			reduceTween:Play()
		else
			DBG:print("No ChunkMusic found and no current music playing")
		end
		return
	end
	
	local newSoundId = chunkMusic.SoundId
	local chunkMusicVolume = GetChunkMusicVolume(chunkMusic)
	DBG:print("Chunk music - SoundId:", newSoundId, "Volume:", chunkMusicVolume)
	
	-- Check if SoundId is empty or invalid
	if not newSoundId or newSoundId == "" or newSoundId == "rbxasset://sounds/action_footsteps_plastic.mp3" then
		if CurrentMusic then
			-- Store the original volume if we haven't already reduced it
			if not IsReduced then
				OriginalVolume = CurrentVolume
				DBG:print("Stored original volume:", OriginalVolume)
			end
			local reducedVolume = OriginalVolume * REDUCED_VOLUME
			CurrentVolume = reducedVolume
			IsReduced = true
			DBG:print("ChunkMusic has empty/invalid SoundId, reducing current music volume from", OriginalVolume, "to", reducedVolume, "(60% of original)")
			DBG:print("Current volume set to:", CurrentVolume, "IsReduced:", IsReduced)
			local reduceTween = TweenService:Create(CurrentMusic, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = reducedVolume
			})
			reduceTween:Play()
		end
		return
	end
	
	
	-- If it's the same music, check if we should reduce or restore
	if CurrentMusic and CurrentMusic.SoundId == newSoundId then
		-- If we're not currently reduced, this is likely an indoor area - reduce volume
		if not IsReduced then
			OriginalVolume = CurrentVolume
			local reducedVolume = OriginalVolume * REDUCED_VOLUME
			CurrentVolume = reducedVolume
			IsReduced = true
			DBG:print("Same music as current, treating as indoor area - reducing volume from", OriginalVolume, "to", reducedVolume, "(60% of original)")
			DBG:print("Stored original volume:", OriginalVolume, "Current volume set to:", CurrentVolume, "IsReduced:", IsReduced)
			local reduceTween = TweenService:Create(CurrentMusic, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = reducedVolume
			})
			reduceTween:Play()
		else
			-- We're already reduced, this is likely returning to the original area - restore volume
			DBG:print("Same music as current, restoring to original volume:", OriginalVolume)
			CurrentVolume = OriginalVolume
			IsReduced = false
			DBG:print("Current volume set to:", CurrentVolume, "IsReduced:", IsReduced)
			local restoreTween = TweenService:Create(CurrentMusic, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = OriginalVolume
			})
			restoreTween:Play()
		end
		return
	end
	
	-- Different music - fade out current and fade in new
	FadeOutMusic()
	
	-- Wait for fade out to complete, then fade in new music at chunk's volume
	task.wait(FADE_OUT_TIME + 0.1)
	FadeInMusic(newSoundId, chunkMusicVolume)
end

-- Stop all music
function MusicManager:StopMusic()
	DBG:print("Stopping all music")
	FadeOutMusic()
end

-- Set a one-shot override track name for the next trainer battle BGM
function MusicManager:SetTrainerBattleTrackOverride(trackName: string?)
    TrainerBattleOverrideName = trackName
end

-- Play short trainer intro sting (EyesMeet), stopping chunk music
function MusicManager:PlayTrainerIntro()
    -- Prevent overlapping intros
    StopAllTrainerIntro()
    local Audio = ReplicatedStorage:FindFirstChild("Audio")
    local Soundtrack = Audio and Audio:FindFirstChild("Soundtrack")
    local eyes = Soundtrack and Soundtrack:FindFirstChild("EyesMeet")
    local id = GetSoundIdFromSound(eyes)
    if not id then return end
    -- Fade out current chunk music fully
    FadeOutMusic()
    -- Create one-shot sting
    TrainerIntroMusic = Instance.new("Sound")
    TrainerIntroMusic.Name = "TrainerIntro_EyesMeet"
    TrainerIntroMusic.SoundId = id
    TrainerIntroMusic.Volume = 0
    TrainerIntroMusic.Looped = false
    TrainerIntroMusic.Parent = SoundService
    TrainerIntroMusic:Play()
    TweenService:Create(TrainerIntroMusic, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 1 }):Play()
end

-- Start trainer battle BGM (TrainerBattle1/2). Ends EyesMeet if still playing.
function MusicManager:StartTrainerBattleMusic()
    local Audio = ReplicatedStorage:FindFirstChild("Audio")
    local Soundtrack = Audio and Audio:FindFirstChild("Soundtrack")
    if not Soundtrack then return end
    -- Ensure any chunk music is fully stopped before starting trainer BGM (root-level gate)
    FadeOutMusic()
    -- Stop any encounter music (trainer uses dedicated BGM)
    if EncounterMusic then
        local em = EncounterMusic
        EncounterMusic = nil
        FadeOutAndDestroy(em, ENCOUNTER_FADE_OUT)
    end
    -- Fade out any trainer intro sting(s)
    StopAllTrainerIntro()
    -- Choose override if present, else 1 or 2
    local node = nil
    if typeof(TrainerBattleOverrideName) == "string" and TrainerBattleOverrideName ~= "" then
        node = Soundtrack:FindFirstChild(TrainerBattleOverrideName)
        -- Clear override after using it once
        TrainerBattleOverrideName = nil
    end
    if not node then
        local pick = math.random(1, 2)
        node = (pick == 1) and Soundtrack:FindFirstChild("TrainerBattle1") or Soundtrack:FindFirstChild("TrainerBattle2")
    end
    local id = GetSoundIdFromSound(node)
    if not id then return end
    TrainerBattleMusic = Instance.new("Sound")
    TrainerBattleMusic.SoundId = id
    TrainerBattleMusic.Volume = 0
    TrainerBattleMusic.Looped = true
    TrainerBattleMusic.Parent = SoundService
    TrainerBattleMusic:Play()
    TweenService:Create(TrainerBattleMusic, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = 1 }):Play()
end

-- End trainer battle BGM
function MusicManager:EndTrainerBattleMusic()
    -- Ensure any lingering trainer intro stings are removed
    StopAllTrainerIntro()
    if TrainerBattleMusic then
        local tb = TrainerBattleMusic
        TrainerBattleMusic = nil
        FadeOutAndDestroy(tb, 0.6)
    end
end

-- Update mute setting
function MusicManager:UpdateMuteSetting(isMuted)
	OnMuteMusicChanged(isMuted)
end

-- Clean up when chunk unloads
function MusicManager:Cleanup()
	-- Don't stop music when chunk unloads, let it continue playing
	-- unless we're loading a new chunk with different music
	DBG:print("MusicManager cleanup - keeping current music playing")
end

-- Initialize music manager
function MusicManager:Init()
	DBG:print("Initializing MusicManager")
	
	-- Listen for settings changes
	-- This would be called when settings are updated
	-- For now, we'll handle it through the settings module
end

-- Start encounter music: fade down current chunk music (without destroying), play encounter track
function MusicManager:StartEncounterMusic()
    DBG:print("=== StartEncounterMusic called ===")
    local playerData = ClientData:Get()
    local isMuted = (playerData and playerData.Settings and playerData.Settings.MuteMusic) == true
    if isMuted then
        DBG:print("Music muted; skipping encounter music")
        return
    end
    if EncounterMusic then
        return
    end
    -- Fade down current chunk music but do not destroy it
    if CurrentMusic then
        ChunkResumeVolume = (IsReduced and OriginalVolume) or CurrentMusic.Volume or FULL_VOLUME
        local downTween = TweenService:Create(CurrentMusic, TweenInfo.new(ENCOUNTER_FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = 0
        })
        downTween:Play()
    end
    -- Pick a random encounter soundtrack (wild only)
    DBG:print("Looking for Audio folder...")
    local Audio = ReplicatedStorage:WaitForChild("Audio")
    DBG:print("Audio folder found:", Audio.Name)
    
    local Soundtrack = Audio:FindFirstChild("Soundtrack")
    DBG:print("Soundtrack folder found:", Soundtrack and Soundtrack.Name or "nil")
    
    local pickId = nil
    if Soundtrack then
        local cand = math.random(1, 2)
        local chosen = cand == 1 and Soundtrack:FindFirstChild("Encounter1") or Soundtrack:FindFirstChild("Encounter2")
        DBG:print("Chosen encounter track:", chosen and chosen.Name or "nil")
        pickId = GetSoundIdFromSound(chosen)
        DBG:print("Sound ID:", pickId)
    end
    if not pickId then
        DBG:print("No encounter soundtrack found; skipping")
        return
    end
    EncounterMusic = Instance.new("Sound")
    EncounterMusic.SoundId = pickId
    EncounterMusic.Volume = 0
    EncounterMusic.Looped = true
    EncounterMusic.Parent = SoundService
    DBG:print("Created encounter music sound, starting playback...")
    EncounterMusic:Play()
    DBG:print("Encounter music started playing")
    TweenService:Create(EncounterMusic, TweenInfo.new(ENCOUNTER_FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Volume = ENCOUNTER_VOLUME
    }):Play()
    DBG:print("Encounter music fade-in tween started")
end

-- End encounter music: fade out encounter, restore chunk music to previous volume
function MusicManager:EndEncounterMusic()
    if EncounterMusic then
        local em = EncounterMusic
        EncounterMusic = nil
        local fade = TweenService:Create(em, TweenInfo.new(ENCOUNTER_FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = 0
        })
        fade.Completed:Connect(function()
            pcall(function()
                em:Stop()
                em:Destroy()
            end)
        end)
        fade:Play()
    end
    -- If victory music is playing, do not restore chunk music yet
    if self.IsVictoryPlaying and self:IsVictoryPlaying() then
        return
    end
    if CurrentMusic then
        local target = ChunkResumeVolume or OriginalVolume or FULL_VOLUME
        IsReduced = false
        OriginalVolume = target
        CurrentVolume = target
        TweenService:Create(CurrentMusic, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = target
        }):Play()
    end
end

-- Play victory music for wild battle capture, fading out encounter music
function MusicManager:PlayVictoryWild()
    local Audio = ReplicatedStorage:FindFirstChild("Audio")
    local Soundtrack = Audio and Audio:FindFirstChild("Soundtrack")
    local victory = Soundtrack and Soundtrack:FindFirstChild("Victory_Wild")
    local id = GetSoundIdFromSound(victory)
    if not id then return end
    -- Fade out encounter music if playing
    if EncounterMusic then
        local em = EncounterMusic
        EncounterMusic = nil
        TweenService:Create(em, TweenInfo.new(ENCOUNTER_FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = 0
        }):Play()
        task.delay(ENCOUNTER_FADE_OUT + 0.1, function()
            pcall(function() em:Stop(); em:Destroy() end)
        end)
    end
    -- Start victory track
    VictoryMusic = Instance.new("Sound")
    VictoryMusic.SoundId = id
    VictoryMusic.Volume = 0
    VictoryMusic.Looped = false
    VictoryMusic.Parent = SoundService
    VictoryMusic:Play()
    TweenService:Create(VictoryMusic, TweenInfo.new(VICTORY_FADE_IN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Volume = VICTORY_VOLUME
    }):Play()
end

-- Stop victory music and restore chunk music
function MusicManager:EndVictory()
    if VictoryMusic then
        local vm = VictoryMusic
        VictoryMusic = nil
        TweenService:Create(vm, TweenInfo.new(VICTORY_FADE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Volume = 0
        }):Play()
        task.delay(VICTORY_FADE_OUT + 0.1, function()
            pcall(function() vm:Stop(); vm:Destroy() end)
        end)
    end
    -- Also ensure encounter music is stopped
    self:EndEncounterMusic()
end

return MusicManager

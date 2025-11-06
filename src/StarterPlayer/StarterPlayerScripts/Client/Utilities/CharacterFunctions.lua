-- Services
local LocalPlayer = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local PlayerModule = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
local Controls = require(PlayerModule):GetControls()

local DBG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DBG"))

-- Character Handling
local CharacterFunctions = {}

local CanMoveNow = true
local MovementSuppressed = false -- When true, ignore external enable requests
local Character = nil
local Humanoid = nil


function CharacterFunctions:Init(TEMP_Character)
	Character = TEMP_Character
	Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
	CharacterFunctions:CanJump(false) -- Set jump to false by default
	Humanoid.WalkSpeed = 19
	DBG:print("WalkSpeed set to: 19")
end

function CharacterFunctions:CheckCanMove()
	return CanMoveNow
end

function CharacterFunctions:CanMove(bool:boolean)
	if bool == true then
		-- Respect suppression: do not re-enable movement while suppressed
		if MovementSuppressed == true then
			DBG:print("CanMove(true) ignored due to suppression")
			return
		end
		-- Re-enable movement by restoring Humanoid speeds
		CanMoveNow = true
        -- Re-enable user input controls instead of zeroing WalkSpeed
        pcall(function()
            Controls:Enable()
        end)
        if Humanoid then
            Humanoid.WalkSpeed = 19
        end
        DBG:print("Movement enabled via Controls:Enable()")
	else
        -- Disable movement via PlayerModule controls so MoveTo still works
		CanMoveNow = false
        pcall(function()
            Controls:Disable()
        end)
		DBG:print("Movement disabled via Controls:Disable()")
	end
end

-- Suppression API mirrors TopBar suppression semantics
function CharacterFunctions:SetSuppressed(value: boolean)
	MovementSuppressed = value == true
	-- If lifting suppression and movement was previously disabled, do not auto-enable here;
	-- callers should explicitly call CanMove(true) when appropriate.
	DBG:print("CharacterFunctions suppression set to:", tostring(MovementSuppressed))
end

function CharacterFunctions:IsSuppressed(): boolean
	return MovementSuppressed == true
end

function CharacterFunctions:CanJump(bool:boolean)
	if Humanoid then
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, bool)
		DBG:print("Jump set to: "..tostring(bool))
	end
end

function CharacterFunctions:Get(XInCharacter:string)
	if not Character then
		DBG:print("Character not initialized")
		return nil
	end
	if XInCharacter == "Humanoid" then
		return Humanoid
	end
	if XInCharacter == "HumanoidRootPart" then
		return Character:FindFirstChild("HumanoidRootPart")
	end
	return nil
end

return CharacterFunctions
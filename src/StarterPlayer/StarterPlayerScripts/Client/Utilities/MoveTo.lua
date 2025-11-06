--!strict

-- MoveTo.lua
-- Reusable, robust character MoveTo helper with control suppression and safe fallbacks

local Players = game:GetService("Players")

local MoveTo = {}

export type MoveOptions = {
	minWalkSpeed: number?,
	timeout: number?,
	delayAfter: number?,
	preserveFacing: boolean?,
	arriveRadius: number?,
	retryInterval: number?,
	onStart: (() -> ())?,
	onComplete: ((boolean) -> ())?,
}

local function getCharacterHumanoid(): (Model?, Humanoid?, BasePart?)
	local player = Players.LocalPlayer
	local character = player and (player.Character or player.CharacterAdded:Wait())
	if not character then return nil, nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, hrp
end

-- Moves the local player's character to target position using Humanoid:MoveTo
-- Applies temporary control suppression, ensures basic movement flags, and restores state.
function MoveTo.MoveToTarget(target: Vector3, opts: MoveOptions?): boolean
	local character, humanoid, hrp = getCharacterHumanoid()
	if not character or not humanoid or not hrp then
		return false
	end

    local CharacterFunctions = require(script.Parent.CharacterFunctions)
    local minWalk = (opts and opts.minWalkSpeed) or 12
    local timeout = (opts and opts.timeout) or 1.5
    local delayAfter = (opts and opts.delayAfter) or 0.5
    local preserveFacing = ((opts and opts.preserveFacing) ~= nil) and (opts :: MoveOptions).preserveFacing or true
    local arriveRadius = (opts and opts.arriveRadius) or 1.75
    local retryInterval = (opts and opts.retryInterval) or 0.4

	local prevSpeed = humanoid.WalkSpeed
	local reached = false
	local conn: RBXScriptConnection? = nil

	-- Pre-move setup
	pcall(function()
		if type(prevSpeed) ~= "number" or prevSpeed < minWalk then
			humanoid.WalkSpeed = minWalk
		end
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end)

	CharacterFunctions:SetSuppressed(true)
	CharacterFunctions:CanMove(false)

    -- Start MoveTo with completion/timeout
	conn = humanoid.MoveToFinished:Connect(function()
		reached = true
	end)
	pcall(function()
		humanoid:MoveTo(target)
	end)

	local startT = os.clock()
    local lastIssue = startT
    while not reached and os.clock() - startT < timeout do
        task.wait(0.05)
        -- Consider arrived when close enough in the horizontal plane
        if hrp then
            local p = hrp.Position
            local planarDist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
            if planarDist <= arriveRadius then
                reached = true
                break
            end
        end
        -- Periodically re-issue MoveTo in case pathing stalled
        if os.clock() - lastIssue >= retryInterval then
            pcall(function()
                humanoid:MoveTo(target)
            end)
            lastIssue = os.clock()
        end
	end
	pcall(function()
		if conn then conn:Disconnect() end
	end)

	-- Fallback snap if not reached in time
	if not reached and hrp then
		local lookDir = hrp.CFrame.LookVector
		if preserveFacing then
			hrp.CFrame = CFrame.new(target, target + lookDir)
		else
			hrp.CFrame = CFrame.new(target)
		end
	end

	-- Restore state slightly after motion settles
	task.delay(delayAfter, function()
		pcall(function()
			if type(prevSpeed) == "number" then
				humanoid.WalkSpeed = prevSpeed
			end
			humanoid:Move(Vector3.new(0, 0, 0))
		end)
		CharacterFunctions:SetSuppressed(false)
		CharacterFunctions:CanMove(true)
	end)

	return reached
end

-- Moves an arbitrary humanoid toward a target point with retries and timeout.
-- This does not modify local player control or TopBar state; intended for NPCs.
function MoveTo.MoveHumanoidToTarget(humanoid: Humanoid, hrp: BasePart?, target: Vector3, opts: MoveOptions?): boolean
	if not humanoid then return false end
	local minWalk = (opts and opts.minWalkSpeed) or 12
	local timeout = (opts and opts.timeout) or 3.0
	local arriveRadius = (opts and opts.arriveRadius) or 2.0
	local retryInterval = (opts and opts.retryInterval) or 0.4
	local onStart = opts and opts.onStart or nil
	local onComplete = opts and opts.onComplete or nil

local prevSpeed = humanoid.WalkSpeed
local prevAnchored: boolean? = (hrp and hrp.Anchored) or nil
local reached = false
local conn: RBXScriptConnection? = nil
local gyro: BodyGyro? = nil
local createdGyro = false


pcall(function()
		if type(prevSpeed) ~= "number" or prevSpeed < minWalk then
			humanoid.WalkSpeed = minWalk
		end
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		if hrp then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
			-- Add a BodyGyro to keep the NPC upright and facing the target horizontally
			gyro = hrp:FindFirstChild("BC_MoveToGyro") :: BodyGyro?
			if not gyro then
				gyro = Instance.new("BodyGyro")
				gyro.Name = "BC_MoveToGyro"
				gyro.P = 3000
				gyro.D = 200
				-- Constrain control to pitch/roll only (no yaw) to avoid unintended spinning
				gyro.MaxTorque = Vector3.new(400000, 0, 400000)
				gyro.Parent = hrp
				createdGyro = true
			end
			-- Initialize with current flat forward direction (no yaw forcing)
			local look = hrp.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) else flatLook = flatLook.Unit end
			gyro.CFrame = CFrame.new(hrp.Position, hrp.Position + flatLook)

			hrp.Anchored = false
		end
	end)

	conn = humanoid.MoveToFinished:Connect(function()
		reached = true
	end)
	pcall(function()
		humanoid:MoveTo(target)
	end)

	local startT = os.clock()
	local lastIssue = startT
	local began = false
	local initialPlanarDist: number? = nil
	while not reached and os.clock() - startT < timeout do
		task.wait(0.05)
		if hrp then
			local p = hrp.Position
			-- Keep upright using current flat look; do not control yaw
			if gyro then
				local lookNow = hrp.CFrame.LookVector
				local flatNow = Vector3.new(lookNow.X, 0, lookNow.Z)
				if flatNow.Magnitude < 0.01 then flatNow = Vector3.new(0, 0, -1) else flatNow = flatNow.Unit end
				gyro.CFrame = CFrame.new(p, p + flatNow)
			end
			local planarDist = (Vector3.new(p.X, 0, p.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
			-- Initialize baseline once
			if initialPlanarDist == nil then
				initialPlanarDist = planarDist
			end
			-- Fire onStart once we have actually closed distance by a small amount
			if not began and initialPlanarDist ~= nil and (initialPlanarDist - planarDist) >= 0.4 then
				began = true
				pcall(function() if onStart then onStart() end end)
			end
			-- Fallback: if some time passed and velocity confirms motion, also trigger
			if not began and (os.clock() - startT) > 0.4 then
				local vel = hrp.AssemblyLinearVelocity
				local speed2d = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
				if speed2d > 0.75 then
					began = true
					pcall(function() if onStart then onStart() end end)
				end
			end
			if planarDist <= arriveRadius then
				reached = true
				break
			end
		end
		if os.clock() - lastIssue >= retryInterval then
			pcall(function()
				humanoid:MoveTo(target)
			end)
			lastIssue = os.clock()
		end
	end
	pcall(function()
		if conn then conn:Disconnect() end
		if type(prevSpeed) == "number" then
			humanoid.WalkSpeed = prevSpeed
		end
		humanoid:Move(Vector3.new(0, 0, 0))
		-- Restore humanoid flags
		if hrp and prevAnchored ~= nil then
			hrp.Anchored = prevAnchored
		end
		if gyro and createdGyro then
			pcall(function() gyro:Destroy() end)
		end
		pcall(function() if onComplete then onComplete(reached) end end)
	end)

	return reached
end

return MoveTo



--!nocheck
local PartyModule = {}
local isOpen = false

-- Callback variables
local SelectionChangedCallback
local OnOpenCallback
local OnCloseCallback

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local RunService: RunService = game:GetService("RunService")
local UserInputService: UserInputService = game:GetService("UserInputService")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))
local SummaryUI = require(script.Parent:WaitForChild("Summary"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
local CreatureSpawner = require(script.Parent.Parent:WaitForChild("Utilities"):WaitForChild("CreatureSpawner"))

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Request = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Request")
local TweenService = game:GetService("TweenService")
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local SpeciesAbilities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SpeciesAbilities"))
local Items = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local MovesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Moves"))
local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.fromScale(0.68, 0.68)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)
local TWEEN_TIME = 0.3
local TWEEN_STYLE = Enum.EasingStyle.Quart
local TWEEN_DIRECTION = Enum.EasingDirection.Out
local MOVE_ANIMATION_TIME = 0.2
local STAT_ANIMATION_TIME = 0.5
local COLOR_ANIMATION_TIME = 0.3

-- Forward declare to avoid nil during click handler compilation
local LoadSummary
local ComputeCurrentAndMaxHP
local setup3DPreview
local connectSummaryButtons

-- Prevent server-driven refreshes during local drag/tween finalize
local IsAnimating = false

-- Store connections to prevent duplicates
local SlotConnections = {}
local OriginalBackgrounds: { [number]: Color3 } = {}

-- Track if summary is already being shown to prevent duplicates
local SummaryShowing = false
local LastSummaryCall = 0
local SUMMARY_DEBOUNCE_TIME = 0 -- disabled per spec
local SelectedIndex: number? = nil
local AllowDrag: boolean = true

local function setAnimating(flag: boolean)
    IsAnimating = flag
    -- expose to other modules (e.g., ClientData) for refresh guard
    PartyModule.IsAnimating = flag
end

-- Track orbit input connections for the 3D preview per container (weak keys)
local OrbitConnections = setmetatable({}, { __mode = "k" })

-- Track move tooltip hover connections per Summary (weak keys)
local MoveHoverConnections = setmetatable({}, { __mode = "k" })

--// Drag & Drop State
local Slots: {TextButton}? = nil -- indexed 1..6, fixed buttons under Party.List
local OriginalPositions: { [number]: UDim2 } = {}
local OriginalCenters: { [number]: number } = {}
local CurrentOrder: { [number]: number } = {1,2,3,4,5,6} -- newIndex -> oldIndex
local ActiveCount: number = 0
local DragSetupDone: boolean = false

local function validateMapping(active: number): boolean
    local seen: {[number]: boolean} = {}
    for i = 1, active do
        local idx = CurrentOrder[i]
        if type(idx) ~= "number" or idx < 1 or idx > active or seen[idx] then
            print("[PartyUI] validateMapping: invalid or duplicate mapping detected; resetting to identity", i, idx)
            for j = 1, 6 do CurrentOrder[j] = j end
            return false
        end
        seen[idx] = true
    end
    return true
end

local DragState = {
	IsDragging = false,
	DragIndex = nil :: number?,
	HoverIndex = nil :: number?,
	Button = nil :: TextButton?,
	OriginalZ = nil :: number?,
	StartMouse = nil :: Vector2?,
	Moved = false,

	Offset = Vector2.new(0,0),
	ConnChanged = nil :: RBXScriptConnection?,
	ConnEnded = nil :: RBXScriptConnection?,
}

local function shallowCloneProps(src: GuiObject, dst: GuiObject)
	-- Copy key visuals relevant for the drag clone
	dst.Size = src.Size
	dst.AnchorPoint = src.AnchorPoint
	dst.BackgroundColor3 = src.BackgroundColor3
	dst.BackgroundTransparency = src.BackgroundTransparency
	dst.BorderSizePixel = src.BorderSizePixel
	dst.ZIndex = (src.ZIndex or 1) + 100
end

local function getListAndSlots(PartyUI: ScreenGui)
	local List = PartyUI:WaitForChild("List")
	if not Slots then
		Slots = {}
		for i = 1, 6 do
			local btn = List:FindFirstChild(tostring(i))
			if btn and btn:IsA("TextButton") then
				Slots[i] = btn
				OriginalPositions[i] = btn.Position
				OriginalCenters[i] = btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y * 0.5)
				OriginalBackgrounds[i] = btn.BackgroundColor3
			else
				-- Missing slot; leave hole
				Slots[i] = nil :: any
			end
		end
	end
	return List, Slots
end

local function refreshActiveHighlight()
	return true --used to have highlight -  not anymore
end

local function computeHoverIndexFromY(mouseY: number): number?
	if ActiveCount < 1 then return nil end
	-- Use original static centers to avoid jitter from live shifting
	for i = 1, ActiveCount - 1 do
		local c1 = OriginalCenters[i]
		local c2 = OriginalCenters[i + 1]
		if c1 and c2 then
			local midY = (c1 + c2) * 0.5
			if mouseY < midY then
				return i
			end
		end
	end
	return ActiveCount
end

local function computeCentersY(): {number}
    local centers: {number} = {}
    if not Slots then return centers end
    for i = 1, 6 do
        local btn = Slots[i]
        if btn and btn.Visible then
            centers[i] = OriginalCenters[i] or (btn.AbsolutePosition.Y + (btn.AbsoluteSize.Y * 0.5))
        end
    end
    return centers
end

local function clampHoverIndex(idx: number?): number?
	if not idx then return nil end
	if ActiveCount < 1 then return nil end
	if idx < 1 then return 1 end
	if idx > ActiveCount then return ActiveCount end
	return idx
end

local function applyPreviewShift()
	-- Shift other buttons to indicate where the dragged slot would drop
	if not Slots or not DragState.DragIndex then return end
	local s = DragState.DragIndex
    for i = 1, 6 do
        local btn = Slots[i]
        if btn and btn.Visible and i ~= s then
			local targetIndex = i
			if DragState.HoverIndex then
				local h = DragState.HoverIndex
                if s < h and i > s and i <= h then
					targetIndex = i - 1
				elseif s > h and i < s and i >= h then
					targetIndex = i + 1
				end
			end
			if OriginalPositions[targetIndex] then
                TweenService:Create(btn, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Position = OriginalPositions[targetIndex]
				}):Play()
			end
		end
	end
end

local function resetSlotsPositions()
	if not Slots then return end
	for i = 1, 6 do
		local btn = Slots[i]
		if btn and OriginalPositions[i] then
			btn.Position = OriginalPositions[i]
		end
	end
end

local function moveInArray(t: {number}, fromIndex: number, toIndex: number)
	if fromIndex == toIndex then return end
	local val = table.remove(t, fromIndex)
	table.insert(t, toIndex, val)
end

local function sendReorderToServer(order: {number})
	local ok = false
	pcall(function()
		ok = Request:InvokeServer({"ReorderParty", order}) == true
	end)
	return ok
end

local function renderSlotFromCreature(btn: TextButton, creatureData: any, slotIndex: number?)
	-- Update basic fields in an existing slot button
	local CreatureName = btn:FindFirstChild("CreatureName")
	local CreatureLevel = btn:FindFirstChild("CreatureLevel")
	local CreatureIcon = btn:FindFirstChild("CreatureIcon")
	local HP = btn:FindFirstChild("HP")
	local Shiny = btn:FindFirstChild("Shiny")
	local TradeLockedIcon = btn:FindFirstChild("TradeLocked")
	local HeldItemIcon = btn:FindFirstChild("HeldItem")
	local GenderIcon = btn:FindFirstChild("Gender")
	local CreatureHP = btn:FindFirstChild("CreatureHP")
	local FollowButton = btn:FindFirstChild("FollowButton")
	local StatusIcon = FollowButton and FollowButton:FindFirstChild("Status")

	if creatureData then
		if CreatureName and CreatureName:IsA("TextLabel") then
			CreatureName.Text = creatureData.Nickname or creatureData.Name or "---"
		end
		if CreatureLevel and CreatureLevel:IsA("TextLabel") then
			CreatureLevel.Text = creatureData.Level and ("Lv." .. tostring(creatureData.Level)) or "Lv.--"
		end
		if CreatureIcon and CreatureIcon:IsA("ImageLabel") then
			local BaseCreature = Creatures[creatureData.Name]
			if BaseCreature then
				local useShiny = creatureData.Shiny == true
				local img = (useShiny and BaseCreature.ShinySprite) or BaseCreature.Sprite
				if img then
					CreatureIcon.Image = img
				end
			end
		end
		if HP and HP:IsA("Frame") then
			local currentHP, maxHP = ComputeCurrentAndMaxHP(creatureData)
			local hpPercent = math.clamp(currentHP / math.max(1, maxHP), 0, 1)
			local maxWidthScale = 0.511
			local heightScale = 0.143
			HP.Visible = currentHP > 0
			HP.Size = UDim2.new(maxWidthScale * hpPercent, 0, heightScale, 0)
		end
		if CreatureHP and CreatureHP:IsA("TextLabel") then
			local currentHP, maxHP = ComputeCurrentAndMaxHP(creatureData)
			CreatureHP.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
		end
		if Shiny and Shiny:IsA("ImageLabel") then
			Shiny.Visible = creatureData.Shiny == true
		end
		if TradeLockedIcon and TradeLockedIcon:IsA("ImageLabel") then
			TradeLockedIcon.Visible = creatureData.TradeLocked == true
		end
		-- Held item icon/image
		if HeldItemIcon and HeldItemIcon:IsA("ImageLabel") then
			local heldName = creatureData.HeldItem
			local hasHeld = type(heldName) == "string" and heldName ~= ""
			HeldItemIcon.Visible = hasHeld
			if hasHeld then
				local def = Items and Items[heldName]
				HeldItemIcon.Image = (def and def.Image) or "rbxassetid://0"
			end
		end
		-- Gender icon sprite region
		if GenderIcon and GenderIcon:IsA("ImageLabel") then
			local g = creatureData.Gender
			if g == 0 then
				GenderIcon.ImageRectOffset = Vector2.new(510, 75) -- Male
				GenderIcon.Visible = true
			elseif g == 1 or g == 2 then
				GenderIcon.ImageRectOffset = Vector2.new(0, 75) -- Female
				GenderIcon.Visible = true
			else
				GenderIcon.Visible = false
			end
		end
		
		-- Update FollowButton Status icon
		if StatusIcon and StatusIcon:IsA("ImageLabel") and slotIndex then
			local spawnedSlot = CreatureSpawner:GetSpawnedSlotIndex()
			print("[PartyUI] renderSlotFromCreature - slotIndex:", slotIndex, "spawnedSlot:", spawnedSlot, "StatusIcon:", StatusIcon)
			
			if spawnedSlot == slotIndex then
				-- Spawned: use spawned icon
				StatusIcon.Image = "rbxassetid://125802977251327"
				print("[PartyUI] Set status icon to spawned for slot", slotIndex)
			else
				-- Not spawned: use not spawned icon
				StatusIcon.Image = "rbxassetid://113482931893438"
				print("[PartyUI] Set status icon to not spawned for slot", slotIndex)
			end
		elseif not StatusIcon then
			warn("[PartyUI] StatusIcon not found for slot", slotIndex)
		elseif not slotIndex then
			warn("[PartyUI] No slotIndex provided to renderSlotFromCreature")
		end
		
		btn.AutoButtonColor = true
		btn.Active = true
		btn.Visible = true
	else
		-- Empty: hide button entirely
		btn.Visible = false
	end
end

local function renderAllSlots(PartyData)
	if not Slots then return end
	ActiveCount = math.min(#(PartyData.Party or {}), 6)
    print("[PartyUI] renderAllSlots; partyLen=", #(PartyData.Party or {}), "ActiveCount=", ActiveCount)
	for i = 1, 6 do
		local btn = Slots[i]
		if btn then
			local srcIndex = CurrentOrder[i]
			local creature = (PartyData.Party and srcIndex and PartyData.Party[srcIndex]) or nil
            local name = creature and (creature.Nickname or creature.Name) or "nil"
            print("[PartyUI] render slot", i, "<-", srcIndex, name)
			renderSlotFromCreature(btn, creature, srcIndex)
		end
	end
end

local function renderSlotIndex(PartyData, index: number)
	if not Slots or not Slots[index] then return end
	local srcIndex = CurrentOrder[index]
	local creature = (PartyData.Party and srcIndex and PartyData.Party[srcIndex]) or nil
    local name = creature and (creature.Nickname or creature.Name) or "nil"
    print("[PartyUI] renderSlotIndex", index, "<-", srcIndex, name)
	renderSlotFromCreature(Slots[index], creature, srcIndex)
end

local function beginDrag(PartyUI: ScreenGui, index: number, inputPosition: Vector2)
	if not Slots or not Slots[index] then return end
	if index < 1 or index > ActiveCount then return end
	if DragState.IsDragging then return end
    DragState.IsDragging = true
	DragState.DragIndex = index
	DragState.HoverIndex = index

	local btn = Slots[index]
    -- Use actual button for dragging (no zindex mass changes per request)
    DragState.Button = btn
    DragState.OriginalZ = btn.ZIndex

    -- Compute offset to button center (AnchorPoint 0.5, 0.5)
    local btnCenter = btn.AbsolutePosition + (btn.AbsoluteSize * 0.5)
    DragState.Offset = Vector2.new(0, 0) -- Always put button center at cursor
    DragState.StartMouse = inputPosition

    local function updateDragPosition(mousePos: Vector2)
        if not DragState.Button then return end
        local parentAbs = DragState.Button.Parent and DragState.Button.Parent.AbsolutePosition or Vector2.new(0,0)
        -- Zero offset ensures we pin button center to cursor
        local target = mousePos - parentAbs
        DragState.Button.Position = UDim2.fromOffset(target.X, target.Y)
        
		-- Determine hover index using static midpoints so space doesn't collapse
        DragState.HoverIndex = clampHoverIndex(computeHoverIndexFromY(mousePos.Y))
        applyPreviewShift()
		refreshActiveHighlight()
	end

	-- Connections for mouse move and release
	DragState.ConnChanged = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local pos = (input and input.Position) and Vector2.new(input.Position.X, input.Position.Y) or UserInputService:GetMouseLocation()
            updateDragPosition(pos)
		end
	end)
	DragState.ConnEnded = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			-- Finish drag (or click if not moved)
			-- Stop further hover/preview updates immediately to avoid flicker
			if DragState.ConnChanged then DragState.ConnChanged:Disconnect() end
			local finalIndex = DragState.HoverIndex or index
			local fromIndex = index
			-- Snap/tween to target if moved; also tween the target-slot button back to fromIndex to avoid overlaps
			local didMove = false
			if DragState.StartMouse then
				didMove = (DragState.StartMouse - (UserInputService:GetMouseLocation())).Magnitude > 2
			end
			print("[PartyUI] endDrag orderBefore=", table.concat(CurrentOrder, ","))
			-- Lock out server-driven renders and new drags during finalize window
			if didMove then setAnimating(true) end
			local tweensToWait = 0
			local finalizeOnce = false
				local function afterTweens()
					-- After tweens, reset positions and re-render from authoritative data
					if not finalizeOnce then
						finalizeOnce = true
						-- One-frame guard to avoid overlap with a new drag in the same frame
						task.defer(function()
							RunService.Heartbeat:Wait()
							setAnimating(false)
							local partyDataRefresh = ClientData:Get()
							resetSlotsPositions()
							renderAllSlots(partyDataRefresh)
						end)
					end
				end
			local function onCompleted()
				tweensToWait -= 1
				if tweensToWait <= 0 then afterTweens() end
			end
			if didMove and DragState.Button and OriginalPositions[finalIndex] then
				-- Tween all buttons back to their canonical positions to avoid overlaps
				for ii = 1, ActiveCount do
					local b = Slots[ii]
					if b and OriginalPositions[ii] then
						local tween = TweenService:Create(b, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
							Position = OriginalPositions[ii]
						})
						tweensToWait += 1
						tween.Completed:Connect(onCompleted)
						tween:Play()
					end
				end
			elseif DragState.Button and OriginalPositions[fromIndex] and not didMove then
				-- Click without move: snap back quickly
				local t = TweenService:Create(DragState.Button, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Position = OriginalPositions[fromIndex]
				})
				tweensToWait += 1
				t.Completed:Connect(onCompleted)
				t:Play()
			end
			-- Reset preview positions is handled by render after tween completion

			-- Commit reorder only if it was a drag (moved). Do NOT mutate CurrentOrder here.
			if didMove and finalIndex and finalIndex ~= fromIndex then
				local order = {}
				for i = 1, ActiveCount do order[i] = i end
				local v = table.remove(order, fromIndex)
				table.insert(order, finalIndex, v)
				print("[PartyUI] send ReorderParty order=", table.concat(order, ","))
				sendReorderToServer(order)
			end

			-- Clear state
			if DragState.ConnEnded then DragState.ConnEnded:Disconnect() end
            -- Restore ZIndex for all siblings
            if DragState.OriginalZMap then
                for obj, z in pairs(DragState.OriginalZMap) do
                    obj.ZIndex = z
                end
            end
            -- Re-enable layout
            if DragState.Layout and DragState.LayoutWasEnabled ~= nil then
                DragState.Layout.Enabled = DragState.LayoutWasEnabled
            end
			DragState.IsDragging = false
			DragState.DragIndex = nil
			DragState.HoverIndex = nil
			DragState.StartMouse = nil
			DragState.Button = nil
            DragState.OriginalZ = nil
            DragState.Layout = nil
            DragState.LayoutWasEnabled = nil
            DragState.OriginalZMap = nil
		refreshActiveHighlight()
		end
	end)

	-- Initialize clone at current cursor (ensure Vector2)
	local startPos = Vector2.new(inputPosition.X, inputPosition.Y)
    updateDragPosition(startPos)
end

local function ensureDragHandlers(PartyUI: ScreenGui)
	print("[PartyUI] ensureDragHandlers called; DragSetupDone=", DragSetupDone)
	if DragSetupDone then 
		print("[PartyUI] DragSetupDone is true, skipping handler setup")
		return 
	end
	
	local _, slotButtons = getListAndSlots(PartyUI)
	if not slotButtons then 
		print("[PartyUI] No slot buttons found, skipping handler setup")
		return 
	end
	
	print("[PartyUI] Setting up drag handlers for", #slotButtons, "slots")
	
	-- Clean up any existing connections first to prevent duplicates
	for i = 1, 6 do
		if SlotConnections[i] then
			print("[PartyUI] Cleaning up existing connections for slot", i)
			for _, connection in ipairs(SlotConnections[i]) do
				if connection and connection.Connected then
					connection:Disconnect()
				end
			end
		end
		SlotConnections[i] = {}
	end
	
	for i = 1, 6 do
		local btn = slotButtons[i]
		if btn then
			print("[PartyUI] Setting up handlers for slot", i)
			
			-- Setup FollowButton click handler
			local FollowButton = btn:FindFirstChild("FollowButton")
			if FollowButton and FollowButton:IsA("GuiButton") then
				local followClickConnection = FollowButton.MouseButton1Click:Connect(function()
					print("[PartyUI] FollowButton clicked for slot", i)
					-- Prevent event bubbling to parent button
					
					local data = ClientData:Get()
					local srcIndex = CurrentOrder[i]
					local creature = data and data.Party and srcIndex and data.Party[srcIndex]
					if creature then
						print("[PartyUI] Sending toggle spawn request for slot", srcIndex, "creature:", creature.Name)
						-- Request spawn/despawn from server
						local Request = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Request")
						local success, result = pcall(function()
							return Request:InvokeServer({"ToggleCreatureSpawn", srcIndex})
						end)
						if success and result then
							print("[PartyUI] Toggle spawn request successful for slot", srcIndex)
							-- Status icon will update via event listener in Init()
						else
							warn("[PartyUI] Failed to toggle spawn for slot", srcIndex, "result:", result)
						end
					else
						warn("[PartyUI] No creature found in slot", srcIndex)
					end
				end)
				table.insert(SlotConnections[i], followClickConnection)
				print("[PartyUI] FollowButton handler connected for slot", i)
			else
				warn("[PartyUI] FollowButton not found for slot", i, "button:", btn.Name)
			end
			
			-- Summary on click: only fire if not dragging and not moved
			local clickConnection = btn.MouseButton1Click:Connect(function()
				print("[PartyUI] Click handler fired for slot", i)
				if DragState.IsDragging then return end
				if DragState.StartMouse then
					local moved = (DragState.StartMouse - UserInputService:GetMouseLocation()).Magnitude > 2
					if moved then return end
				end
				local data = ClientData:Get()
				local srcIndex = CurrentOrder[i]
				local creature = data and data.Party and srcIndex and data.Party[srcIndex]
				if creature then
				local summary = LoadSummary and LoadSummary(data, creature, i) or nil
				if summary then
					SelectedIndex = i
					refreshActiveHighlight()
					PartyModule:LoadCreatureSummary(summary, i)
				end
				end
			end)
			table.insert(SlotConnections[i], clickConnection)
			print("[PartyUI] Click connection created for slot", i, "Total connections:", #SlotConnections[i])
			
			-- Drag start: only when drag is allowed (prevents accidental drags in battle)
			if AllowDrag then
				local downConnection = btn.MouseButton1Down:Connect(function(x, y)
					print("[PartyUI] Down handler fired for slot", i)
					local pos = Vector2.new(x, y)
					local thisIndex = i
					-- Delay before starting drag; if released before 0.2s, treat as click
					local started = true
					task.delay(0.2, function()
						if not started then return end
						if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
							beginDrag(PartyUI, thisIndex, pos)
						end
					end)
					local releaseConn; releaseConn = UserInputService.InputEnded:Connect(function(input)
						if input.UserInputType == Enum.UserInputType.MouseButton1 then
							started = false
							releaseConn:Disconnect()
						end
					end)
				end)
				table.insert(SlotConnections[i], downConnection)
				print("[PartyUI] Down connection created for slot", i, "Total connections:", #SlotConnections[i])
			else
				print("[PartyUI] Drag disabled; skipping down handler for slot", i)
			end
		else
			print("[PartyUI] No button found for slot", i)
		end
	end
	DragSetupDone = true
	print("[PartyUI] Drag handlers setup complete. DragSetupDone set to true")
end

-- Function to reset drag handlers (useful for cleanup)
local function resetDragHandlers()
	-- Clean up all existing connections
	for i = 1, 6 do
		if SlotConnections[i] then
			for _, connection in ipairs(SlotConnections[i]) do
				if connection and connection.Connected then
					connection:Disconnect()
				end
			end
			SlotConnections[i] = {}
		end
	end
	DragSetupDone = false
end

local function DarkenColor3(base: Color3, factor: number): Color3
	factor = math.clamp(factor or 1, 0, 1)
	return Color3.new(base.R * factor, base.G * factor, base.B * factor)
end

-- Compute current and max HP with robust fallbacks
function ComputeCurrentAndMaxHP(creatureData: any): (number, number)
	if not creatureData then return 0, 1 end
	-- Prefer server-provided MaxStats when available
	local maxFromServer = creatureData.MaxStats and creatureData.MaxStats.HP
	-- Compute fallback using StatCalc based on base stats, level and IVs
	local statsFallback, maxStatsFallback = StatCalc.ComputeStats(creatureData.Name, creatureData.Level, creatureData.IVs)
	local maxHP = (typeof(maxFromServer) == "number" and maxFromServer > 0 and maxFromServer)
		or (maxStatsFallback and maxStatsFallback.HP)
		or (creatureData.Stats and creatureData.Stats.HP)
		or (creatureData.BaseStats and creatureData.BaseStats.HP)
		or 1

	-- Determine current HP
	local percent = creatureData.CurrentHP
	local currentHP: number
	if typeof(percent) == "number" then
		percent = math.clamp(percent, 0, 100)
		currentHP = math.floor(maxHP * (percent / 100) + 0.5)
	elseif creatureData.Stats and typeof(creatureData.Stats.HP) == "number" then
		local statsHP = creatureData.Stats.HP
		-- If Stats.HP exceeds max (could be misused), clamp to max
		currentHP = math.clamp(statsHP, 0, maxHP)
	else
		currentHP = maxHP
	end

	-- Ensure sane bounds
	currentHP = math.clamp(currentHP, 0, math.max(1, maxHP))
	maxHP = math.max(1, maxHP)
	return currentHP, maxHP
end

function LoadSummary(PartyData, CreatureData, slotIndex)
	-- Make sure the creature exists in creature data
	local Base = Creatures[CreatureData.Name]
	if not Base then 
		warn("Creature not found in Creatures data:", CreatureData.Name)
		return nil 
	end
	
    -- Compute stats/max from compact data and include CurrentHP for UI
    local stats, maxStats = StatCalc.ComputeStats(CreatureData.Name, CreatureData.Level, CreatureData.IVs, CreatureData.Nature)
    local currentHPPercent = CreatureData.CurrentHP
    local currentHP
    if currentHPPercent == nil then
        currentHPPercent = 100
        currentHP = maxStats.HP
    else
        currentHPPercent = math.clamp(currentHPPercent, 0, 100)
        currentHP = math.floor(maxStats.HP * (currentHPPercent / 100) + 0.5)
    end

    -- Build learned moves for UI from Learnset at or below current level (latest 4)
    local learnedMoves = {}
    if Base.Learnset then
        local flat = {}
        for lvl, movesAt in pairs(Base.Learnset) do
            for _, mv in ipairs(movesAt) do
                table.insert(flat, { lvl = lvl, move = mv })
            end
        end
        table.sort(flat, function(a, b)
            if a.lvl == b.lvl then return tostring(a.move) < tostring(b.move) end
            return a.lvl < b.lvl
        end)
        local recent = {}
        for i = #flat, 1, -1 do
            local e = flat[i]
            if e.lvl <= (CreatureData.Level or 1) and not table.find(recent, e.move) and MovesModule[e.move] then
                table.insert(recent, e.move)
                if #recent == 4 then break end
            end
        end
        for i = #recent, 1, -1 do
            table.insert(learnedMoves, recent[i])
        end
    end

    -- Return combined data for display
    warn("[PartyUI] LoadSummary Weight Debug - Instance WeightKg:", CreatureData and CreatureData.WeightKg)

    return {
		SlotIndex = slotIndex,
		-- Base creature data
		DexNumber = Base.DexNumber,
		BaseName = Base.Name,
		Description = Base.Description,
		BaseType = Base.Type,
		BaseStats = Base.BaseStats,
		LearnableMoves = Base.LearnableMoves,
		Sprite = Base.Sprite,
		
		-- Player's creature data
		Name = CreatureData.Name,
		Nickname = CreatureData.Nickname,
		Level = CreatureData.Level,
		Shiny = CreatureData.Shiny,
		Gender = CreatureData.Gender,
        Stats = stats,
        MaxStats = maxStats,
        CurrentHP = currentHPPercent,
		IVs = CreatureData.IVs,
        CurrentMoves = CreatureData.CurrentMoves or learnedMoves,
        OT = CreatureData.OT,
        TradeLocked = CreatureData.TradeLocked,
        Nature = CreatureData.Nature,
		CatchData = CreatureData.CatchData,
		-- Instance weight (for size class computation)
		WeightKg = CreatureData.WeightKg,
	}
end

function PartyModule:Init()
	-- Initialize CreatureSpawner
	print("[PartyUI] Initializing CreatureSpawner...")
	CreatureSpawner:Init()
	print("[PartyUI] CreatureSpawner initialized")
	
	-- Listen for spawn state changes to update UI
	local Events = ReplicatedStorage:WaitForChild("Events")
	local Communicate = Events:WaitForChild("Communicate")
	Communicate.OnClientEvent:Connect(function(eventType, data)
		if eventType == "CreatureSpawned" or eventType == "CreatureDespawned" then
			print("[PartyUI] Spawn state changed:", eventType, "data:", data)
			-- Wait a frame to ensure CreatureSpawner has updated its state
			RunService.Heartbeat:Wait()
			local spawnedSlot = CreatureSpawner:GetSpawnedSlotIndex()
			print("[PartyUI] Current spawned slot index:", spawnedSlot)
			-- Refresh party display to update status icons
			print("[PartyUI] Calling UpdatePartyDisplay after spawn state change")
			PartyModule:UpdatePartyDisplay()
		end
	end)
	
	-- Initialize party display
	self:UpdatePartyDisplay()
end

function PartyModule:UpdatePartyDisplay()
	local PartyUI = self:GetGui()
	if not PartyUI then return end
	if IsAnimating then return end
	local PartyData = ClientData:Get()
	print("[PartyUI] UpdatePartyDisplay invoked; IsAnimating=", IsAnimating, "DragSetupDone=", DragSetupDone)

	-- Ensure slots and drag handlers are wired once
	getListAndSlots(PartyUI)
	
	-- Only setup drag handlers if enabled and not already done
	-- Ensure click handlers are always present; add drag handlers only when allowed
	if AllowDrag then
		if not DragSetupDone then
			print("[PartyUI] Setting up handlers (click + drag enabled)")
			ensureDragHandlers(PartyUI)
		else
			print("[PartyUI] Handlers already setup")
		end
	else
		-- If drag was previously set up, clear then set up click-only handlers
		if DragSetupDone then
			print("[PartyUI] Drag disabled; resetting handlers to rebind click-only")
			resetDragHandlers()
		end
		print("[PartyUI] Setting up handlers (click-only; drag disabled)")
		ensureDragHandlers(PartyUI)
	end

	-- Initialize order to identity each time based on ActiveCount
	ActiveCount = math.min(#(PartyData.Party or {}), 6)
	for i = 1, 6 do CurrentOrder[i] = i end

	-- Render current party into fixed slots
	resetSlotsPositions()
	renderAllSlots(PartyData)
	refreshActiveHighlight()

	-- Hide summary initially
	local Summary = PartyUI:WaitForChild("Summary")
	Summary.Visible = false
end

function PartyModule:CreateCreatureButton(List, Template, slotIndex, creatureData)
	-- Clone the template
	local CreatureButton = Template:Clone()
	CreatureButton.Name = "Creature" .. slotIndex
	CreatureButton.Visible = true
	CreatureButton.LayoutOrder = slotIndex
	CreatureButton.Parent = List
	
	-- Update creature name (use nickname if available)
	local CreatureName = CreatureButton:WaitForChild("CreatureName")
	local displayName = creatureData.Nickname or creatureData.Name
	CreatureName.Text = displayName
	
	-- Update creature level
	local CreatureLevel = CreatureButton:WaitForChild("CreatureLevel")
	CreatureLevel.Text = "Lv." .. creatureData.Level
	
	-- Update creature icon
	local CreatureIcon = CreatureButton:WaitForChild("CreatureIcon")
	
	-- Set creature icon from Creatures module
	local BaseCreature = Creatures[creatureData.Name]
	if BaseCreature then
		local useShiny = creatureData.Shiny == true
		local img = (useShiny and BaseCreature.ShinySprite) or BaseCreature.Sprite
		if img then
			CreatureIcon.Image = img
		else
			warn("No sprite found for creature:", creatureData.Name)
		end
	else
		warn("No sprite found for creature:", creatureData.Name)
	end
	-- CreatureIcon.Image = creatureData.Sprite -- Uncomment if you have creature sprites
	
	-- Update HP bar (ensure proper max and percent)
	local HP = CreatureButton:WaitForChild("HP")
	-- HP is a Frame whose Size scales with current HP
	    -- CurrentHP is percent (0-100); compute absolute for UI
	    local percent = creatureData.CurrentHP
	    if percent == nil then percent = 100 end
	    percent = math.clamp(percent, 0, 100)
	    local maxHP = (creatureData.MaxStats and creatureData.MaxStats.HP)
			or (creatureData.Stats and creatureData.Stats.HP)
			or (creatureData.BaseStats and creatureData.BaseStats.HP)
	        or 1
	    local currentHP = math.floor(maxHP * (percent / 100) + 0.5)
	local maxWidthScale = 0.761
	local heightScale = 0.234
	local hpPercent = math.clamp(currentHP / math.max(1, maxHP), 0, 1)
	if currentHP <= 0 then
		HP.Visible = false
	else
		HP.Visible = true
		HP.Size = UDim2.new(maxWidthScale * hpPercent, 0, heightScale, 0)
	end

	-- Update HP text label if present: CreatureHP (TextLabel)
	local CreatureHP = CreatureButton:FindFirstChild("CreatureHP")
    if CreatureHP and CreatureHP:IsA("TextLabel") then
        CreatureHP.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
	end
	
	-- Show/hide shiny indicator
	local Shiny = CreatureButton:WaitForChild("Shiny")
	Shiny.Visible = creatureData.Shiny

	-- Show trade lock icon if present on template
	local TradeLockedIcon = CreatureButton:FindFirstChild("TradeLocked")
	if TradeLockedIcon and TradeLockedIcon:IsA("ImageLabel") then
		TradeLockedIcon.Visible = creatureData.TradeLocked == true
	end
	
	-- Set up click handler
	CreatureButton.MouseButton1Click:Connect(function()
		self:LoadCreatureSummary(creatureData, slotIndex)
	end)
end

function PartyModule:LoadCreatureSummary(creatureData, slotIndex)
	print("[PartyUI] LoadCreatureSummary called for slot", slotIndex, "SummaryShowing:", SummaryShowing)

	-- Debounce disabled to allow rapid navigation
	SummaryShowing = true
	
	print("[PartyUI] === LOAD CREATURE SUMMARY ===")
	print("[PartyUI] Creature:", creatureData and creatureData.Name or "nil")
	print("[PartyUI] Slot:", slotIndex)
	
	local PartyUI = self:GetGui()
	if not PartyUI then return end
	local Summary = PartyUI:WaitForChild("Summary")
	local List = PartyUI:FindFirstChild("List")
	
	-- Show summary immediately per new spec and hide list
	if List then List.Visible = false end
	Summary.Visible = true
	SelectedIndex = slotIndex
	refreshActiveHighlight()

	-- Delegate summary UI rendering to shared module and stop here to avoid duplicate logic
	SummaryUI:Render(Summary, creatureData)

	-- Notify battle integration about the current selection so SendOut updates
	if SelectionChangedCallback then
		SelectionChangedCallback(creatureData, slotIndex)
	end

	-- Ability UI wiring (Summary.AdditionalInfo.HA, Summary.Ability.AbilityText, Summary.Hidden.HiddenText)
	local function getHiddenAbilityName(speciesName: string?): string?
		if not speciesName then return nil end
		local pool = SpeciesAbilities[speciesName]
		if type(pool) ~= "table" then return nil end
		local hiddenName: string? = nil
		local minChance = math.huge
		for _, entry in ipairs(pool) do
			local ch = tonumber(entry.Chance) or 0
			-- Treat very low chance (<=2) as hidden; fallback to lowest chance
			if ch <= 2 then
				hiddenName = entry.Name
				break
			end
			if ch < minChance then
				minChance = ch
				hiddenName = entry.Name
			end
		end
		return hiddenName
	end

	local abilityName = tostring(creatureData.Ability or "")
	local speciesName = creatureData.BaseName or creatureData.Name
	local hiddenName = getHiddenAbilityName(speciesName)
	local hasHidden = (abilityName ~= "" and hiddenName ~= nil and abilityName == hiddenName)

	-- Ability text
	do
		local abilityFrame = Summary:FindFirstChild("Ability")
		if abilityFrame and abilityFrame:IsA("Frame") then
			local abilityText = abilityFrame:FindFirstChild("AbilityText")
			if abilityText and abilityText:IsA("TextLabel") then
				abilityText.Text = abilityName ~= "" and abilityName or "—"
			end
		end
	end

	-- Hidden ability pill and text
	do
		local additionalInfo = Summary:FindFirstChild("AdditionalInfo")
		local ha = additionalInfo and additionalInfo:FindFirstChild("HA")
		if ha and ha:IsA("GuiObject") then
			ha.Visible = hasHidden
		end
		local hiddenFrame = Summary:FindFirstChild("Hidden")
		if hiddenFrame and hiddenFrame:IsA("Frame") then
			hiddenFrame.Visible = hasHidden
			local hiddenText = hiddenFrame:FindFirstChild("HiddenText")
			if hiddenText and hiddenText:IsA("TextLabel") then
				hiddenText.Text = hasHidden and hiddenName or ""
			end
		end
	end

	connectSummaryButtons(self, PartyUI)
	return
	
--[[ LEGACY SUMMARY RENDERING BELOW (now handled by Summary module)
	-- Update creature name (use nickname if available)
	local CreatureName = Summary:WaitForChild("CreatureName")
	local displayName = creatureData.Nickname or creatureData.Name
	CreatureName.Text = displayName
	
	-- Update EffortLabel and StatsLabel with creature name/nickname
	local EffortLabel = Summary:FindFirstChild("EffortLabel")
	if EffortLabel then
		EffortLabel.Text = displayName .. "'s Effort (0-31)"
	end
	
	local StatsLabel = Summary:FindFirstChild("StatsLabel")
	if StatsLabel then
		StatsLabel.Text = displayName .. "'s Stats"
	end
	
	-- Update level
	local Level = Summary:WaitForChild("Level")
	Level.Text = "Lv." .. creatureData.Level

	-- Update Nature text and Catch data
	local NatureFrame = Summary:FindFirstChild("Nature")
	if NatureFrame then
		local NatureText = NatureFrame:FindFirstChild("NatureText")
		if NatureText and NatureText:IsA("TextLabel") then
			NatureText.Text = tostring(creatureData.Nature or "Unknown")
		end
	end

	local function ordinal(n: number): string
		local j = n % 10
		local k = n % 100
		if j == 1 and k ~= 11 then return "st" end
		if j == 2 and k ~= 12 then return "nd" end
		if j == 3 and k ~= 13 then return "rd" end
		return "th"
	end

	local caughtWhenLabel = Summary:FindFirstChild("CaughtWhen")
	local caughtByLabel = Summary:FindFirstChild("CaughtBy")
	local cd = creatureData.CatchData
	if cd and type(cd) == "table" then
		if caughtWhenLabel and caughtWhenLabel:IsA("TextLabel") then
			local ts = tonumber(cd.CaughtWhen)
			if ts then
				local d = os.date("*t", ts)
				local dateStr = string.format("%d%s %s %d", d.day, ordinal(d.day), os.date("%b", ts), d.year)
				caughtWhenLabel.Text = "Caught: " .. dateStr
			else
				caughtWhenLabel.Text = "Caught: Unknown"
			end
		end
		if caughtByLabel and caughtByLabel:IsA("TextLabel") then
			local byId = tonumber(cd.CaughtBy)
			if byId then
				local success, nameOrErr = pcall(function()
					return game:GetService("Players"):GetNameFromUserIdAsync(byId)
				end)
				caughtByLabel.Text = "by " .. (success and nameOrErr or tostring(byId))
			else
				caughtByLabel.Text = "by Unknown"
			end
		end
	else
		if caughtWhenLabel and caughtWhenLabel:IsA("TextLabel") then
			caughtWhenLabel.Text = "Caught: Unknown"
		end
		if caughtByLabel and caughtByLabel:IsA("TextLabel") then
			caughtByLabel.Text = "by Unknown"
		end
	end
	
	-- Set creature type(s) UI
	local function setTypeFrame(frame: Frame?, typeName: string?)
		if not frame or not typeName then return end
		local typeText = frame:FindFirstChild("TypeText")
		if TypesModule[typeName] then
			local c = TypesModule[typeName].uicolor
			frame.BackgroundColor3 = c
			local darker = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
			local stroke = frame:FindFirstChild("UIStroke")
			if stroke then
				stroke.Color = darker
			end
			-- Also update the UIStroke on the inner TypeText label to the darker outline
			if typeText and typeText:IsA("TextLabel") then
				local txtStroke = typeText:FindFirstChild("UIStroke")
				if txtStroke then
					txtStroke.Color = darker
				end
			end
		end
		if typeText and typeText:IsA("TextLabel") then
			typeText.Text = typeName or "Unknown"
		end
	end

	local FirstType = Summary:FindFirstChild("FirstType")
	local SecondType = Summary:FindFirstChild("SecondType")

	-- Determine types list
	local typesList = {}
	local baseTypes = creatureData.BaseType or (Creatures[creatureData.Name] and Creatures[creatureData.Name].Type)
	if typeof(baseTypes) == "table" then
		for i, t in ipairs(baseTypes) do
			typesList[i] = typeof(t) == "string" and t or nil
		end
	elseif typeof(baseTypes) == "string" then
		typesList[1] = baseTypes
	end

	if FirstType or SecondType then
		-- New dual-type UI
		setTypeFrame(FirstType, typesList[1])
		if SecondType then
			if typesList[2] then
				SecondType.Visible = true
				setTypeFrame(SecondType, typesList[2])
			else
				SecondType.Visible = false
			end
		end
	else
		-- Back-compat: Summary.Type
		local TypeFrame = Summary:FindFirstChild("Type")
		if TypeFrame and TypeFrame:IsA("Frame") then
			setTypeFrame(TypeFrame, typesList[1])
		end
	end

	-- Size/Weight UI
	local SizeFrame = Summary:FindFirstChild("SizeFrame")
	if SizeFrame and SizeFrame:IsA("Frame") then
		local SizeClassObj = SizeFrame:FindFirstChild("SizeClass")
		-- Be robust: find ActualWeight anywhere under SizeFrame if not nested in SizeClass
		local ActualWeightLabel = (SizeClassObj and SizeClassObj:FindFirstChild("ActualWeight")) or SizeFrame:FindFirstChild("ActualWeight", true)
		-- Determine weights
		local baseData = Creatures[creatureData.Name]
		local baseWeight = baseData and baseData.BaseWeightKg or nil
		local weight = creatureData.WeightKg or baseWeight
		warn("[PartyUI] Weight Debug - BaseWeight:", baseWeight, "Instance Weight:", creatureData.WeightKg, "Chosen Weight:", weight)
		local function getClass(actual:number?, base:number?): string
			if type(actual) ~= "number" or type(base) ~= "number" or base <= 0 then return "?" end
			local delta = (actual - base) / base
			if delta <= -0.3 then return "XS" end
			if delta <= -0.1 then return "S" end
			if delta < 0.1 then return "M" end
			if delta < 0.3 then return "L" end
			return "XL"
		end
		local class = getClass(weight, baseWeight)
		if SizeClassObj and SizeClassObj:IsA("TextLabel") then
			SizeClassObj.Text = class
		end
		if ActualWeightLabel and ActualWeightLabel:IsA("TextLabel") then
			if type(weight) == "number" then
				ActualWeightLabel.Text = tostring(weight) .. "KG"
				warn("[PartyUI] Weight Debug - Set ActualWeight text to", ActualWeightLabel.Text)
			else
				ActualWeightLabel.Text = "--"
				warn("[PartyUI] Weight Debug - No weight; set '--'")
			end
		end
	end
	
	-- Update gender icon (now in AdditionalInfo frame)
	local AdditionalInfo = Summary:WaitForChild("AdditionalInfo")
	local GenderIcon = AdditionalInfo:WaitForChild("GenderIcon")
	if creatureData.Gender == 0 then
		-- Male
		GenderIcon.ImageRectOffset = Vector2.new(510, 75)
	else
		-- Female
		GenderIcon.ImageRectOffset = Vector2.new(0, 75)
	end
	
	-- Update stats
	local HP = Summary:WaitForChild("HP")
	local HPMax = HP:WaitForChild("Max")
	local HPCurrent = HP:FindFirstChild("Current")
	local CreatureHP = Summary:FindFirstChild("CreatureHP")
	
	-- CurrentHP is percent (0-100); show scalar current/max using MaxStats if available
	local percent = creatureData.CurrentHP
	if percent == nil then percent = 100 end
	percent = math.clamp(percent, 0, 100)
    local _, maxStatsFallback = StatCalc.ComputeStats(creatureData.Name, creatureData.Level, creatureData.IVs, creatureData.Nature)
	local maxHP = (creatureData.MaxStats and creatureData.MaxStats.HP)
		or (maxStatsFallback and maxStatsFallback.HP)
		or (creatureData.Stats and creatureData.Stats.HP)
		or 1
	local currentScalar = math.floor(maxHP * (percent / 100) + 0.5)
	HPMax.Text = tostring(maxHP)
	if CreatureHP and CreatureHP:IsA("TextLabel") then
		CreatureHP.Text = "HP: " .. tostring(currentScalar) .. "/" .. tostring(maxHP)
	end
	
	-- Animate HP bar visual to match list buttons mapping
	if HPCurrent then
		local hpPercent = math.clamp(currentScalar / math.max(1, maxHP), 0, 1)
		local fullXScale = 0.456
		local fullYScale = 0.049
		HPCurrent.Size = UDim2.new(fullXScale * hpPercent, 0, fullYScale, 0)
	end
	
	local Attack = Summary:WaitForChild("Attack")
	local AttackCurrent = Attack:FindFirstChild("Current")
	
	-- Animate Attack bar visual
	if AttackCurrent then
		AttackCurrent.Size = UDim2.new(0, 0, 1, 0) -- Start empty
		local attackTween = TweenService:Create(AttackCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), {
			Size = UDim2.new(1, 0, 1, 0) -- Fill to full
		})
		attackTween:Play()
	end
	
	local Defense = Summary:WaitForChild("Defense")
	local DefenseCurrent = Defense:FindFirstChild("Current")
	
	-- Animate Defense bar visual
	if DefenseCurrent then
		DefenseCurrent.Size = UDim2.new(0, 0, 1, 0) -- Start empty
		local defenseTween = TweenService:Create(DefenseCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), {
			Size = UDim2.new(1, 0, 1, 0) -- Fill to full
		})
		defenseTween:Play()
	end
	
	local Speed = Summary:WaitForChild("Speed")
	local SpeedCurrent = Speed:FindFirstChild("Current")
	
	-- Animate Speed bar visual
	if SpeedCurrent then
		SpeedCurrent.Size = UDim2.new(0, 0, 1, 0) -- Start empty
		local speedTween = TweenService:Create(SpeedCurrent, TweenInfo.new(STAT_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), {
			Size = UDim2.new(1, 0, 1, 0) -- Fill to full
		})
		speedTween:Play()
	end
	
    -- Update moves (support both string names and legacy move tables)
    if creatureData.CurrentMoves then
        -- Tooltip setup
        local Summary = PartyUI:FindFirstChild("Summary")
        local MoveInfo = Summary and Summary:FindFirstChild("MoveInfo")
        local uis = game:GetService("UserInputService")
	        if MoveInfo and not MoveInfo:GetAttribute("HoverFollowConnected") then
	            MoveInfo.Visible = false
	            MoveInfo:SetAttribute("HoverFollowConnected", true)
            uis.InputChanged:Connect(function(input)
                if MoveInfo.Visible and input.UserInputType == Enum.UserInputType.MouseMovement then
                    local pos = input.Position
                    local padX, padY = 220, 145 -- pixel padding relative to cursor
                    local parent: any = MoveInfo.Parent
                    local parentSize = parent and parent.AbsoluteSize or Vector2.new(1920, 1080)
                    local px = math.max(1, parentSize.X)
                    local py = math.max(1, parentSize.Y)
                    local xScale = (pos.X - padX) / px
                    local yScale = (pos.Y - padY) / py
                    -- Clamp to [0,1] to avoid drifting off parent bounds
                    xScale = math.clamp(xScale, 0, 1)
                    yScale = math.clamp(yScale, 0, 1)
                    MoveInfo.Position = UDim2.new(xScale, 0, yScale, 0)
                end
            end)
        end
	        -- Ensure a fresh set of per-move hover connections on each render
	        if MoveInfo then
	            MoveInfo.Visible = false
	        end
	        -- Remove old connections tracked for this summary
	        if MoveHoverConnections and MoveHoverConnections[Summary] and MoveHoverConnections[Summary].PerMove then
	            for _, c in ipairs(MoveHoverConnections[Summary].PerMove) do
	                if c and c.Connected then c:Disconnect() end
	            end
	            MoveHoverConnections[Summary].PerMove = {}
	        end
	        -- Clear HoverBound flags so we can rebind handlers for the new creature
	        if Summary then
	            for i = 1, 4 do
	                local mf = Summary:FindFirstChild("Move" .. i)
	                if mf then mf:SetAttribute("HoverBound", nil) end
	            end
	        end
        for i = 1, 4 do
			local MoveFrame = Summary:WaitForChild("Move" .. i)
			local MoveName = MoveFrame:WaitForChild("MoveName")
			local MoveStat = MoveFrame:WaitForChild("Stat")

			local entry = creatureData.CurrentMoves[i]
			local resolvedName: string? = nil
			local moveDef: any = nil
			if typeof(entry) == "string" then
				resolvedName = entry
				moveDef = MovesModule[resolvedName]
			elseif typeof(entry) == "table" then
				-- Legacy: table identity match
				for k, v in pairs(MovesModule) do
					if v == entry then
						resolvedName = k
						moveDef = v
						break
					end
				end
			end

            if resolvedName and moveDef then
				MoveName.Text = resolvedName
				MoveStat.Text = "Power: " .. tostring(moveDef.BasePower)

				-- Visuals based on type color
				local typeColor = moveDef.Type and moveDef.Type.uicolor or Color3.new(0.5, 0.5, 0.5)
				MoveFrame.BackgroundTransparency = 1
				MoveFrame.Visible = true
				TweenService:Create(MoveFrame, TweenInfo.new(MOVE_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { BackgroundTransparency = 0 }):Play()
				TweenService:Create(MoveFrame, TweenInfo.new(COLOR_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { BackgroundColor3 = typeColor }):Play()
				local UIStroke = MoveFrame:FindFirstChild("UIStroke")
				if UIStroke then
					local darker = Color3.new(math.max(0, typeColor.R * 0.6), math.max(0, typeColor.G * 0.6), math.max(0, typeColor.B * 0.6))
					TweenService:Create(UIStroke, TweenInfo.new(COLOR_ANIMATION_TIME, TWEEN_STYLE, TWEEN_DIRECTION), { Color = darker }):Play()
				end

                -- Hover: show MoveInfo tooltip
                if MoveInfo and MoveFrame:GetAttribute("HoverBound") ~= true then
                    -- Write current move data as attributes to avoid stale closures when navigating
                    MoveFrame:SetAttribute("MoveName", resolvedName)
                    MoveFrame:SetAttribute("MovePower", moveDef.BasePower or 0)
                    MoveFrame:SetAttribute("MoveDescription", tostring(moveDef.Description or ""))
                    MoveFrame:SetAttribute("TypeColorR", typeColor.R)
                    MoveFrame:SetAttribute("TypeColorG", typeColor.G)
                    MoveFrame:SetAttribute("TypeColorB", typeColor.B)
                    local function show()
                        MoveInfo.Visible = true
                        local r = MoveFrame:GetAttribute("TypeColorR") or typeColor.R
                        local g = MoveFrame:GetAttribute("TypeColorG") or typeColor.G
                        local b = MoveFrame:GetAttribute("TypeColorB") or typeColor.B
                        local currentTypeColor = Color3.new(r, g, b)
                        MoveInfo.BackgroundColor3 = currentTypeColor
                        local infoStroke = MoveInfo:FindFirstChild("UIStroke")
                        if infoStroke then
                            local darker = Color3.new(math.max(0, currentTypeColor.R * 0.6), math.max(0, currentTypeColor.G * 0.6), math.max(0, currentTypeColor.B * 0.6))
                            infoStroke.Color = darker
                        end
                        local nameLabel = MoveInfo:FindFirstChild("MoveName")
                        local statLabel = MoveInfo:FindFirstChild("Stat")
                        local descLabel = MoveInfo:FindFirstChild("Description")
                        local n = MoveFrame:GetAttribute("MoveName") or resolvedName
                        local p = MoveFrame:GetAttribute("MovePower") or moveDef.BasePower
                        local d = MoveFrame:GetAttribute("MoveDescription") or (moveDef.Description or "")
                        if nameLabel and nameLabel:IsA("TextLabel") then nameLabel.Text = tostring(n) end
                        if statLabel and statLabel:IsA("TextLabel") then statLabel.Text = "Power: " .. tostring(p) end
                        if descLabel and descLabel:IsA("TextLabel") then descLabel.Text = tostring(d) end
                        -- Darken strokes for any child text labels
                        for _, obj in ipairs(MoveInfo:GetDescendants()) do
                            if obj:IsA("UIStroke") and obj.Parent and obj.Parent:IsA("TextLabel") then
                                local darker = Color3.new(math.max(0, currentTypeColor.R * 0.6), math.max(0, currentTypeColor.G * 0.6), math.max(0, currentTypeColor.B * 0.6))
                                obj.Color = darker
                            end
                        end
                    end
                    local function hide()
                        MoveInfo.Visible = false
                    end
                    -- store connections for cleanup on re-render/close
                    if MoveHoverConnections[Summary] then
                        MoveHoverConnections[Summary].PerMove = MoveHoverConnections[Summary].PerMove or {}
                        table.insert(MoveHoverConnections[Summary].PerMove, MoveFrame.MouseEnter:Connect(show))
                        table.insert(MoveHoverConnections[Summary].PerMove, MoveFrame.MouseLeave:Connect(hide))
                    else
                        MoveFrame.MouseEnter:Connect(show)
                        MoveFrame.MouseLeave:Connect(hide)
                    end
                    MoveFrame:SetAttribute("HoverBound", true)
                end
			else
				-- Empty/unknown: fully hide this move slot and clear any stale tooltip attributes
				MoveFrame.Visible = false
				MoveFrame:SetAttribute("HoverBound", nil)
				MoveFrame:SetAttribute("MoveName", nil)
				MoveFrame:SetAttribute("MovePower", nil)
				MoveFrame:SetAttribute("MoveDescription", nil)
				MoveFrame:SetAttribute("TypeColorR", nil)
				MoveFrame:SetAttribute("TypeColorG", nil)
				MoveFrame:SetAttribute("TypeColorB", nil)
			end
		end
	end

	-- IV visualizer (HPIV, AttackIV, DefenseIV, SPDIV)
	local function SetIVFrame(frameName: string, value: number?, baseColor: Color3)
		local frame = Summary:FindFirstChild(frameName)
		if not frame then return end
		local iv = typeof(value) == "number" and math.clamp(value, 0, 31) or 0
		local StatLabel = frame:FindFirstChild("Stat")
		if StatLabel and StatLabel:IsA("TextLabel") then
			StatLabel.Text = tostring(iv)
		end
		-- Darken the provided base color based on IV value (0-31)
		local ratio = iv / 31
		local shade = 0.35 + (0.65 * ratio) -- 35% at 0 IV, up to full at 31 IV
		local color = DarkenColor3(baseColor, shade)
		frame.BackgroundColor3 = color
		local stroke = frame:FindFirstChild("UIStroke")
		if stroke then
			local darker = Color3.new(math.max(0, color.R * 0.6), math.max(0, color.G * 0.6), math.max(0, color.B * 0.6))
			stroke.Color = darker
		end
	end

	if creatureData.IVs then
		SetIVFrame("HPIV", creatureData.IVs.HP, Color3.fromRGB(38, 255, 0))
		SetIVFrame("AttackIV", creatureData.IVs.Attack, Color3.fromRGB(255, 78, 47))
		SetIVFrame("DefenseIV", creatureData.IVs.Defense, Color3.fromRGB(47, 158, 255))
		SetIVFrame("SPDIV", creatureData.IVs.Speed, Color3.fromRGB(250, 189, 45))
	end

	-- Update TradeLocked badge in summary, if present (now in AdditionalInfo frame)
	local AdditionalInfo = Summary:FindFirstChild("AdditionalInfo")
	if AdditionalInfo then
		local TradeLockedBadge = AdditionalInfo:FindFirstChild("TradeLocked")
		if TradeLockedBadge and TradeLockedBadge:IsA("ImageLabel") then
			TradeLockedBadge.Visible = creatureData.TradeLocked == true
		end
	end

	-- Update OT username in Summary.OT (TextLabel)
	local OTLabel = Summary:FindFirstChild("OT")
	if OTLabel and OTLabel:IsA("TextLabel") then
		local userId = creatureData.OT
		if typeof(userId) == "number" and userId > 0 then
			local Players = game:GetService("Players")
			local success, nameOrErr = pcall(function()
				return Players:GetNameFromUserIdAsync(userId)
			end)
			if success and typeof(nameOrErr) == "string" then
				OTLabel.Text = "OT: " .. nameOrErr
			else
				OTLabel.Text = "OT: Unknown"
			end
		else
			OTLabel.Text = "OT: Unknown"
		end
	end
	
    -- Show/hide shiny indicator (now in AdditionalInfo frame)
    local AdditionalInfo = Summary:FindFirstChild("AdditionalInfo")
    if AdditionalInfo then
        local Shiny = AdditionalInfo:FindFirstChild("Shiny")
        if Shiny then
            Shiny.Visible = creatureData.Shiny
        end
    end

	print("=== CHECKING SELECTION CALLBACK ===")
	print("SelectionChangedCallback exists:", SelectionChangedCallback ~= nil)
	print("SelectionChangedCallback type:", type(SelectionChangedCallback))
	if SelectionChangedCallback then
		print("Calling SelectionChangedCallback...")
		SelectionChangedCallback(creatureData, slotIndex)
	else
		print("No SelectionChangedCallback set!")
	end
	print("=== END CHECKING SELECTION CALLBACK ===")

	-- Update 3D Preview for the current creature
	setup3DPreview(Summary, creatureData)

	-- Ensure summary navigation buttons are connected
connectSummaryButtons(self, PartyUI)
--]]
end

function PartyModule:GetGui()
	local player = game.Players.LocalPlayer
	if not player then return nil end
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	local gameUi = playerGui:FindFirstChild("GameUI")
	if not gameUi then return nil end
	return gameUi:FindFirstChild("Party")
end

-- Create or update the 3D preview viewport
setup3DPreview = function(Summary: Frame, creatureData: any)
	local container = Summary:FindFirstChild("3DPreview")
	if not container or not container:IsA("Frame") then return end

	-- Remove only prior dynamic viewport elements; preserve decorative UI (shadows, strokes, etc.)
	local previous = container:FindFirstChild("Viewport")
	if previous and previous:IsA("ViewportFrame") then
		previous:Destroy()
	end

	-- Create ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Viewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.ZIndex = 15
	viewport.BackgroundTransparency = 1
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Ambient = Color3.fromRGB(255, 255, 255)
	viewport.Parent = container

	-- WorldModel is required for animations to play inside a ViewportFrame
	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "WorldModel"
	worldModel.Parent = viewport

	-- Camera for viewport
	local cam = Instance.new("Camera")
	cam.Name = "ViewportCamera"
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	-- Try to locate a rig/model by species name under ReplicatedStorage.CreatureModels
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local modelsFolder = ReplicatedStorage:FindFirstChild("Assets")
	modelsFolder = modelsFolder and modelsFolder:FindFirstChild("CreatureModels") or nil
	local modelTemplate: Instance? = nil
	if modelsFolder then
		modelTemplate = modelsFolder:FindFirstChild(tostring(creatureData.BaseName or creatureData.Name))
	end

	if modelTemplate and modelTemplate:IsA("Model") then
		local model = modelTemplate:Clone()
		model.Parent = worldModel
		-- Apply shiny recolor in preview if needed
		if creatureData.Shiny then
			local Creatures = require(game:GetService("ReplicatedStorage").Shared.Creatures)
			local base = Creatures[creatureData.BaseName or creatureData.Name]
			local shinyColors = base and base.ShinyColors
			if shinyColors then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") or d:IsA("MeshPart") then
						local newColor = shinyColors[d.Name]
						if newColor then
							pcall(function()
								d.Color = newColor
							end)
						end
					end
				end
			end
		end
		-- Compute bounds to place camera
		-- Prefer HumanoidRootPart for framing
		local hrp = model:FindFirstChild("HumanoidRootPart")
		local anchor: BasePart? = hrp and hrp:IsA("BasePart") and hrp or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not model.PrimaryPart and anchor then model.PrimaryPart = anchor end
		if anchor then
			-- Move model so HRP/anchor sits at origin for consistent framing
			local targetCF = CFrame.new(0, 0, 0)
			model:PivotTo(targetCF)

			-- Set default facing: HRP orientation 0, -180, 0 and autofit camera
			local primary: BasePart? = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
			if primary and primary:IsA("BasePart") then
				model.PrimaryPart = primary
			end
			-- Ensure model HRP starts at orientation 0,0,0
			model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, 0))
			-- Drag accumulators are initialized later in the orbit handler
			local size = model:GetExtentsSize()
			-- Revert to auto-fit camera calculation (position + lookat)
			local target = (model.PrimaryPart and model.PrimaryPart.Position) or Vector3.new(0, size.Y * 0.5, 0)
			local vFov = math.rad(cam.FieldOfView)
			local vp = container.AbsoluteSize
			local aspect = (vp.Y > 0) and (vp.X / vp.Y) or 1
			local hFov = 2 * math.atan(math.tan(vFov * 0.5) * aspect)
			local halfHeight = math.max(0.5, size.Y * 0.5)
			local halfWidth = math.max(0.5, math.max(size.X, size.Z) * 0.5)
			local distV = halfHeight / math.tan(vFov * 0.5)
			local distH = halfWidth / math.tan(hFov * 0.5)
			local padding = 1.2
			local distance = math.max(4, math.max(distV, distH) * padding)
			local forward = Vector3.new(0, 0, -1)
			local camPos = -(target - (forward.Unit * distance))
			-- Set viewport camera orientation to 0, -180, 0 while preserving computed position
			cam.CFrame = CFrame.new(camPos) * CFrame.Angles(0, math.rad(-180), 0)
			cam.Focus = CFrame.new(target)
			warn("[PartyUI] CameraFit | size=", size, "vp=", vp, "aspect=", aspect, "vFov=", cam.FieldOfView, "hFov=", math.deg(hFov), "distV=", distV, "distH=", distH, "chosen=", distance)
			warn("[PartyUI] CameraFit | target=", target, "camPos=", camPos)
		end
		-- Attempt to play idle if present (support Humanoid or AnimationController)
		local animator: Animator? = nil
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			animator = humanoid:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
		else
			local animController = model:FindFirstChildOfClass("AnimationController")
			if not animController then
				animController = Instance.new("AnimationController")
				animController.Parent = model
			end
			animator = animController:FindFirstChildOfClass("Animator")
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = animController
			end
		end
		local animFolder = model:FindFirstChild("Animations")
		local idle = animFolder and animFolder:FindFirstChild("Idle") or model:FindFirstChild("Idle")
		if idle and idle:IsA("Animation") and animator then
			local track = animator:LoadAnimation(idle)
			track.Priority = Enum.AnimationPriority.Idle
			track.Looped = true
			track:Play()
			warn("[PartyUI] Played Idle animation")
		else
			warn("[PartyUI] Idle animation not found")
		end
	else
		-- Fallback: show the creature sprite in an ImageLabel overlay
		local Creatures = require(game:GetService("ReplicatedStorage").Shared.Creatures)
		local base = Creatures[creatureData.BaseName or creatureData.Name]
		local spriteId = base and base.Sprite or nil
		if spriteId then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Image = spriteId
			img.Size = UDim2.fromScale(1, 1)
			img.ZIndex = 15
			img.Parent = container
		else
			viewport:Destroy() -- nothing to render
		end
	end

	-- Bind simple orbit: drag to rotate model around Y while camera stays fixed
	-- Clean any previous connections for this container
	if OrbitConnections[container] then
		for _, conn in ipairs(OrbitConnections[container]) do
			if conn and conn.Connected then conn:Disconnect() end
		end
		OrbitConnections[container] = nil
	end

	local conns = {}
	OrbitConnections[container] = conns

    local dragging = false
    local lastX: number? = nil
    local lastY: number? = nil
    local rotateSpeed = math.rad(0.35) -- radians per pixel (slightly faster)
    local yawAccum = 0
    local pitchAccum = 0

    -- Use auto-fit camera computed above; do NOT override with fixed origin
    warn("[PartyUI] Camera: using auto-fit; not overriding with fixed origin")

	local function onInputBegan(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			lastX = input.Position.X
			lastY = input.Position.Y
		end
	end
	local function onInputEnded(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			lastX = nil
		end
	end
	    local function onInputChanged(input: InputObject)
	        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
	            if lastX and lastY then
	                local dx = input.Position.X - lastX
	                local dy = input.Position.Y - lastY
	                lastX = input.Position.X
	                lastY = input.Position.Y
                -- Update yaw/pitch: right drag -> yaw right; dragging DOWN -> pitch DOWN (positive pitch)
                yawAccum += (dx * rotateSpeed)
                pitchAccum += (dy * rotateSpeed)
	                -- Clamp pitch to avoid flipping (about +/- 80 degrees)
	                local maxPitch = math.rad(80)
	                if pitchAccum > maxPitch then pitchAccum = maxPitch end
	                if pitchAccum < -maxPitch then pitchAccum = -maxPitch end
	                if worldModel and #worldModel:GetChildren() > 0 then
	                    local m = worldModel:GetChildren()[1]
	                    if m and m:IsA("Model") then
	                        local hrp = m:FindFirstChild("HumanoidRootPart")
	                        if hrp and hrp:IsA("BasePart") then
	                            m.PrimaryPart = hrp
						local pos = hrp.Position
						-- Force roll to 0 so model never tilts sideways; apply only yaw/pitch
						local newRoot = CFrame.new(pos) * CFrame.Angles(pitchAccum, yawAccum, 0)
	                            m:PivotTo(newRoot)
	                        else
	                            local cf = m:GetPivot()
	                            local newPivot = cf * CFrame.Angles(-dy * rotateSpeed, dx * rotateSpeed, 0)
	                            m:PivotTo(newPivot)
	                        end
	                    end
	                end
	            end
	        end
	    end

	-- Connect to container and UIS; store for cleanup
	local c1 = container.InputBegan:Connect(onInputBegan)
	local c2 = container.InputEnded:Connect(onInputEnded)
	local c3 = game:GetService("UserInputService").InputChanged:Connect(onInputChanged)
	table.insert(conns, c1)
	table.insert(conns, c2)
	table.insert(conns, c3)
end

-- Wire up Previous, Next, and Back (SummaryClose) buttons
connectSummaryButtons = function(self, PartyUI: ScreenGui)
	if not PartyUI then return end
	local Summary = PartyUI:FindFirstChild("Summary")
	if not Summary then return end

	-- Prevent duplicate connections by storing on Summary
	if Summary:GetAttribute("NavConnected") then return end
	Summary:SetAttribute("NavConnected", true)

	local function getPartyData()
		return ClientData:Get()
	end

	local function navigate(delta: number)
		local data = getPartyData()
		local party = data and data.Party or {}
		if not party then return end
		-- ActiveCount may not be initialized here; compute from party length
		local count = math.min(#party, 6)
		if count <= 0 then return end
		local current = SelectedIndex or 1
		local nextIndex = ((current - 1 + delta) % count) + 1
		SelectedIndex = nextIndex
		refreshActiveHighlight()
		-- Build enriched summary data to keep UI consistent
		local srcIndex = CurrentOrder[nextIndex] or nextIndex
		local creature = party[srcIndex]
		if not creature then return end
		local summaryData = LoadSummary(data, creature, nextIndex)
		self:LoadCreatureSummary(summaryData, nextIndex)
	end

	local prevBtn = Summary:FindFirstChild("Previous")
	if prevBtn and prevBtn:IsA("TextButton") then
		prevBtn.MouseButton1Click:Connect(function()
			navigate(-1)
		end)
	end

	local nextBtn = Summary:FindFirstChild("Next")
	if nextBtn and nextBtn:IsA("TextButton") then
		nextBtn.MouseButton1Click:Connect(function()
			navigate(1)
		end)
	end

	local closeBtn = Summary:FindFirstChild("SummaryClose")
	if closeBtn and closeBtn:IsA("TextButton") then
		closeBtn.MouseButton1Click:Connect(function()
			-- Show party list and hide summary
			local list = PartyUI:FindFirstChild("List")
			if list then list.Visible = true end
			Summary.Visible = false
			-- Clear 3D preview content to free resources
			local container = Summary:FindFirstChild("3DPreview")
			if container then
				for _, child in ipairs(container:GetChildren()) do child:Destroy() end
			end
			Summary:SetAttribute("NavConnected", nil)
		end)
	end
end

function PartyModule:GetSummary()
	local gui = self:GetGui()
	return gui and gui:FindFirstChild("Summary") or nil
end

function PartyModule:SetSelectionChangedCallback(callback)
	print("=== SET SELECTION CHANGED CALLBACK ===")
	print("Callback function:", callback)
	print("Callback type:", type(callback))
	print("Previous SelectionChangedCallback:", SelectionChangedCallback)
	SelectionChangedCallback = callback
	print("SelectionChangedCallback set to:", SelectionChangedCallback)
	print("=== END SET SELECTION CHANGED CALLBACK ===")
end

function PartyModule:SetOpenCloseCallbacks(onOpen, onClose)
	OnOpenCallback = onOpen
	OnCloseCallback = onClose
end

function PartyModule:SelectSlot(slotIndex)
	local partyData = ClientData:Get()
	if not partyData or not partyData.Party then return end
	local creature = partyData.Party[slotIndex]
	if not creature then return end
	local summaryData = LoadSummary(partyData, creature)
	if summaryData then
		self:LoadCreatureSummary(summaryData, slotIndex)
	end
end

--// Party Open
function PartyModule:Open(All)
	if isOpen then return end -- Already open, don't open again
	
	isOpen = true
	-- Disable drag while in battle context (when opened from battle)
	AllowDrag = (All ~= "Battle")
	-- Reset summary showing flag when party opens
	SummaryShowing = false
	local Party: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Party")
	
	Audio.SFX.Open:Play()

	-- Update party display before opening
	self:UpdatePartyDisplay()

	-- Ensure List is visible and Summary hidden when opening (reset from previous summary state)
	local gui = self:GetGui()
	if gui then
		local List = gui:FindFirstChild("List")
		if List then List.Visible = true end
		local Summary = gui:FindFirstChild("Summary")
		if Summary then Summary.Visible = false end
	end

	Party.Visible = true
	Party.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(Party, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	Party.Position = UDim2.new(0.31, 0,0.1, 0)
	TweenService:Create(Party, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5,0,0.5,0),
	}):Play()

	-- Shadow
	Party.Shadow.Image.ImageTransparency = 1
	TweenService:Create(Party.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 0.5,
	}):Play()

	-- Topbar
	Party.Topbar.Size = UDim2.fromScale(1, 0.165)
	TweenService:Create(Party.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.107),
	}):Play()

	-- Icon + Shadow
	Party.Topbar.Icon.Rotation = 25
	Party.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
	Party.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)

	TweenService:Create(Party.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 0,
		Position = UDim2.new(0.041, 0, 0.185, 0),
	}):Play()
	TweenService:Create(Party.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.066, 0, 0.526, 0),
	}):Play()

	-- Title
	Party.Topbar.Title.MaxVisibleGraphemes = 0
	TweenService:Create(Party.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 8,
	}):Play()

	-- Darken
	Party.Darken.Size = CLOSED_SIZE
	TweenService:Create(Party.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.new(4.0125, 0,6.0945, 0),
	}):Play()

	if OnOpenCallback then
		OnOpenCallback()
	end
end

--// Party Close
function PartyModule:Close(All)
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
	local Party: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Party")

	Audio.SFX.Close:Play()
	
	task.delay(0.1, function()
		TweenService:Create(Party, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)
	
	task.delay(0.15,function()
		TweenService:Create(Party, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.31, 0,0.1, 0),
		}):Play()
	end)

	TweenService:Create(Party.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	}):Play()

	TweenService:Create(Party.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.1),
	}):Play()

	TweenService:Create(Party.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 25,
		Position = UDim2.new(0.05, 0, 0.341, 0),
	}):Play()
	TweenService:Create(Party.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.084, 0, 0.682, 0),
	}):Play()

	TweenService:Create(Party.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 0,
	}):Play()

	TweenService:Create(Party.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = CLOSED_SIZE,
	}):Play()

	task.delay(0.4, function()
		Party.Visible = false
		-- Reset summary showing flag when party closes
		SummaryShowing = false
		-- Cleanup move hover connections for current summary, if any
		local gui = self:GetGui()
		local summary = gui and gui:FindFirstChild("Summary") or nil
		if summary and MoveHoverConnections[summary] then
			local bucket = MoveHoverConnections[summary]
			if bucket.Follow and bucket.Follow.Connected then bucket.Follow:Disconnect() end
			if bucket.PerMove then
				for _, c in ipairs(bucket.PerMove) do
					if c and c.Connected then c:Disconnect() end
				end
			end
			MoveHoverConnections[summary] = nil
		end
		if OnCloseCallback then
			OnCloseCallback()
		end
	end)
end

return PartyModule


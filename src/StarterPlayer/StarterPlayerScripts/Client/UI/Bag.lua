--!nocheck
local BagModule = {}
local isOpen = false
local inBattle = false
local isTrainerBattle = false
local selectedItem: string? = nil
local selectingCreature = false -- Track if we're in creature selection mode
local selectingAction: string? = nil -- "Use" or "Give" while selecting a creature
local connections: {RBXScriptConnection}? = {}
local creatureButtonConnections: {[number]: RBXScriptConnection?} = {}
local creatureOptionsOffConn: RBXScriptConnection? = nil
local currentCategoryName: string = "Heals"
local _initialized = false
local OnOpenCallback: (() -> ())? = nil
local OnCloseCallback: (() -> ())? = nil

--// Services/Modules for data
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemsModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local CreaturesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
local Say = require(script.Parent.Parent:WaitForChild("Utilities"):WaitForChild("Say"))
local StatCalc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StatCalc"))
-- (deduped above)

local refreshCreatureList -- forward declaration
local updateItemSelection -- forward declaration

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.fromScale(0.693, 0.71)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

-- Module-level functions for creature list and item selection
local function canCreatureLearnMove(creatureName: string, mlItemName: string): boolean
	local creatureData = CreaturesModule[creatureName]
	if not creatureData or not creatureData.Learnset then
		return false
	end
	
	-- Extract move name from ML item name
	-- Try patterns like "ML: MoveName" or just assume the item name is the move name
	local moveName = mlItemName
	if string.find(mlItemName, "ML:") then
		moveName = string.gsub(mlItemName, "ML:%s*", "")
	end
	
	-- Check if move exists in creature's learnset at any level
	for level, moves in pairs(creatureData.Learnset) do
		for _, move in ipairs(moves) do
			if move == moveName then
				return true
			end
		end
	end
	return false
end

local function refreshCreatureList_impl()
	local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
	local creaturesContainer = BagGui:FindFirstChild("Creatures")
	if not creaturesContainer then return end
    -- Always reset floating CreatureOptions to root and hide by default
    do
        local options = creaturesContainer:FindFirstChild("CreatureOptions", true)
        if options and options:IsA("Frame") then
            options.Parent = creaturesContainer
            options.Visible = false
        end
        if creatureOptionsOffConn and creatureOptionsOffConn.Connected then
            creatureOptionsOffConn:Disconnect()
        end
        creatureOptionsOffConn = nil
    end
	
	local partyData = ClientData:Get()
	local party = partyData and partyData.Party or {}
	
	-- Helper function to handle creature selection
    local function onCreatureClick(slotIndex: number)
        if not selectingCreature or not selectedItem then return end
		
        -- Send server request with slot index
        local Events = game.ReplicatedStorage:WaitForChild("Events")
        local result = nil
        local success = false
        local action = selectingAction or "Use"
        print("[Bag] onCreatureClick action=", action, " slot=", slotIndex, " item=", tostring(selectedItem))
        pcall(function()
            if action == "Give" then
                result = Events.Request:InvokeServer({
                    "GiveItem",
                    {
                        Name = selectedItem,
                        SlotIndex = slotIndex,
                    }
                })
            else
                result = Events.Request:InvokeServer({
                    "UseItem",
                    {
                        Name = selectedItem,
                        Context = inBattle and "Battle" or "Overworld",
                        SlotIndex = slotIndex
                    }
                })
            end
            success = result ~= nil
        end)
        print("[Bag] onCreatureClick response ok=", success, " result=", typeof(result) == "table" and game:GetService("HttpService"):JSONEncode(result) or tostring(result))
		
		-- Exit selection mode
        selectingCreature = false
        selectingAction = nil
		
		-- Display server response
        local message = result or (action == "Give" and "Cannot give item." or "Cannot use item.")
        if success and result == true then
            message = (action == "Give") and "Item given!" or "Item used!"
        elseif result == false then
            message = (action == "Give") and "Cannot give item." or "Cannot use item."
        elseif type(result) == "string" then
            message = result
        end
		
		-- Close the non-dismissable selection prompt before showing result
		pcall(function() Say:Exit() end)
		-- Show message in Say; allow player to dismiss
		Say:Say("", true, {message}, nil, nil)
		
        -- Refresh creature list and UI (keep bag open)
        refreshCreatureList()
        updateItemSelection()
	end
	
	-- Update each slot (1-6)
	for slotIndex = 1, 6 do
		local slotButton = creaturesContainer:FindFirstChild(tostring(slotIndex))
		if not slotButton or not slotButton:IsA("GuiObject") then continue end
		
		local creatureData = party[slotIndex]
		
		-- Set visibility based on whether there's a creature in this slot
		slotButton.Visible = creatureData ~= nil
		
		-- Clear any previous connection for this slot
		local existingConnection = creatureButtonConnections[slotIndex]
		if existingConnection then
			if existingConnection.Connected then
				existingConnection:Disconnect()
			end
			creatureButtonConnections[slotIndex] = nil
		end

        -- Make creature clickable when in selection mode
        if selectingCreature and creatureData then
			-- Add click handler
			local conn = UIFunctions:NewButton(
				slotButton,
				{"Action"},
				{ Click = "One", HoverOn = "One", HoverOff = "One" },
				0.7,
				function()
					Audio.SFX.Click:Play()
					onCreatureClick(slotIndex)
				end
			)
			if conn then
				creatureButtonConnections[slotIndex] = conn
			end
        elseif (not selectingCreature) and creatureData then
            -- When not selecting a target: show CreatureOptions only if creature has a held item
            local conn = UIFunctions:NewButton(
                slotButton,
                {"Action"},
                { Click = "One", HoverOn = "One", HoverOff = "One" },
                0.7,
                function()
                    Audio.SFX.Click:Play()
                    -- Guard: do nothing if selection mode was toggled during click
                    if selectingCreature then return end
                    local heldName = creatureData and creatureData.HeldItem
                    -- If no held item, hide any open options and return
                    if type(heldName) ~= "string" or heldName == "" then
                        local existing = creaturesContainer:FindFirstChild("CreatureOptions", true)
                        if existing and existing:IsA("Frame") then
                            existing.Parent = creaturesContainer
                            existing.Visible = false
                        end
                        if creatureOptionsOffConn and creatureOptionsOffConn.Connected then
                            creatureOptionsOffConn:Disconnect()
                        end
                        creatureOptionsOffConn = nil
                        return
                    end
                    -- Hide any existing options before showing this one
                    do
                        local existing = creaturesContainer:FindFirstChild("CreatureOptions", true)
                        if existing and existing:IsA("Frame") then
                            existing.Parent = creaturesContainer
                            existing.Visible = false
                        end
                        if creatureOptionsOffConn and creatureOptionsOffConn.Connected then
                            creatureOptionsOffConn:Disconnect()
                        end
                        creatureOptionsOffConn = nil
                    end
                    local options = creaturesContainer:FindFirstChild("CreatureOptions")
                    if not (options and options:IsA("Frame")) then return end
                    options.Parent = slotButton
                    options.Visible = true
                    -- Always record the current target slot/type so the handler uses the right one
                    options:SetAttribute("TargetType", "Party")
                    options:SetAttribute("TargetSlot", slotIndex)
                    -- Wire TakeItem only once
                    if options:GetAttribute("Bound") ~= true then
                        local takeBtn = options:FindFirstChild("TakeItem")
                        if takeBtn and (takeBtn:IsA("TextButton") or takeBtn:IsA("ImageButton")) then
                            UIFunctions:NewButton(takeBtn, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.7, function()
                                Audio.SFX.Click:Play()
                                local Events = game.ReplicatedStorage:WaitForChild("Events")
                                local targetSlot = tonumber(options:GetAttribute("TargetSlot")) or -1
                                print("[Bag] TakeHeldItem request for party slot:", targetSlot)
                                local ok, res = pcall(function()
                                    return Events.Request:InvokeServer({
                                        "TakeHeldItem",
                                        { Location = { Type = "Party", SlotIndex = targetSlot } }
                                    })
                                end)
                                print("[Bag] TakeHeldItem response ok=", ok, " res=", typeof(res) == "table" and ("Success=" .. tostring(res.Success) .. ", ItemName=" .. tostring(res.ItemName)) or tostring(res))
                                if ok and type(res) == "table" and res.Success == true then
                                    local itemName = tostring(res.ItemName or "Item")
                                    --Say:Say("", true, {itemName .. " was taken and placed in your bag."}, nil, nil)
                                    --uppdate local data and UI
                                    creatureData.HeldItem = nil
                                    options.Parent = creaturesContainer
                                    options.Visible = false
                                    if creatureOptionsOffConn and creatureOptionsOffConn.Connected then
                                        creatureOptionsOffConn:Disconnect()
                                    end
                                    creatureOptionsOffConn = nil
                                    refreshCreatureList()
                                else
                                    Say:Say("", true, {"Unable to take item. Please try again later."}, nil, nil)
                                end
                            end)
                        end
                        options:SetAttribute("Bound", true)
                    end
                    -- Always update target slot attribute on re-open
                    options:SetAttribute("TargetSlot", slotIndex)
                    -- Global off-click to dismiss
                    local UIS = game:GetService("UserInputService")
                    creatureOptionsOffConn = UIS.InputBegan:Connect(function(input, gp)
                        if gp then return end
                        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                        task.defer(function()
                            if not options or not options.Parent then return end
                            local mouse = game.Players.LocalPlayer:GetMouse()
                            local pos = Vector2.new(mouse.X, mouse.Y)
                            local absPos = options.AbsolutePosition
                            local absSize = options.AbsoluteSize
                            local inside = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
                            if not inside then
                                options.Parent = creaturesContainer
                                options.Visible = false
                                if creatureOptionsOffConn and creatureOptionsOffConn.Connected then
                                    creatureOptionsOffConn:Disconnect()
                                end
                                creatureOptionsOffConn = nil
                            end
                        end)
                    end)
                end
            )
            if conn then
                creatureButtonConnections[slotIndex] = conn
            end
		end
		
		if creatureData then
			-- Get creature base data
			local baseData = CreaturesModule[creatureData.Name]
			if not baseData then continue end
			
			-- Update creature name
			local creatureName = slotButton:FindFirstChild("CreatureName")
			if creatureName and creatureName:IsA("TextLabel") then
				creatureName.Text = creatureData.Nickname or creatureData.Name
			end
			
			-- Update creature icon (use shiny sprite if applicable)
			local creatureIcon = slotButton:FindFirstChild("CreatureIcon")
			if creatureIcon and creatureIcon:IsA("ImageLabel") then
				if creatureData.Shiny and baseData.ShinySprite then
					creatureIcon.Image = baseData.ShinySprite
				else
					creatureIcon.Image = baseData.Sprite
				end
			end
			
			-- Update shiny indicator
			local shinyIndicator = slotButton:FindFirstChild("Shiny")
			if shinyIndicator and shinyIndicator:IsA("ImageLabel") then
				shinyIndicator.Visible = creatureData.Shiny == true
			end

			-- Update held item indicator/image
			local heldItemIcon = slotButton:FindFirstChild("HeldItem")
			if heldItemIcon and heldItemIcon:IsA("ImageLabel") then
				local heldName = creatureData.HeldItem
				local hasHeld = type(heldName) == "string" and heldName ~= ""
				heldItemIcon.Visible = hasHeld
				if hasHeld then
					local def = ItemsModule[heldName]
					heldItemIcon.Image = (def and def.Image) or "rbxassetid://0"
				end
			end

			-- Update gender icon if present
			local genderIcon = slotButton:FindFirstChild("Gender")
			if genderIcon and genderIcon:IsA("ImageLabel") then
				local g = creatureData.Gender
				if g == 0 then
					genderIcon.ImageRectOffset = Vector2.new(510, 75) -- Male
					genderIcon.Visible = true
				elseif g == 1 or g == 2 then
					genderIcon.ImageRectOffset = Vector2.new(0, 75) -- Female (fallback)
					genderIcon.Visible = true
				else
					genderIcon.Visible = false
				end
			end
			
			-- Calculate HP
			local currentHP = 0
			local maxHP = 0
			
			-- Compute stats if MaxStats is missing
			if not creatureData.MaxStats or not creatureData.MaxStats.HP or creatureData.MaxStats.HP == 0 then
				local stats, maxStats = StatCalc.ComputeStats(
					creatureData.Name,
					creatureData.Level or 1,
					creatureData.IVs or {},
					creatureData.Nature
				)
				creatureData.Stats = stats
				creatureData.MaxStats = maxStats
			end
			
			if creatureData.MaxStats and creatureData.MaxStats.HP then
				maxHP = creatureData.MaxStats.HP
				if creatureData.CurrentHP ~= nil then
					-- CurrentHP is a percentage (0-100)
					currentHP = math.floor(maxHP * (creatureData.CurrentHP / 100) + 0.5)
				elseif creatureData.Stats and creatureData.Stats.HP then
					currentHP = creatureData.Stats.HP
				else
					currentHP = maxHP
				end
			end
			
			-- Update HP display
			local hpMain = slotButton:FindFirstChild("HPMain")
			if hpMain and hpMain:IsA("Frame") then
				local hpBar = hpMain:FindFirstChild("HP")
				local hpText = hpMain:FindFirstChild("CreatureHP")
				
				if hpBar and hpBar:IsA("Frame") then
					-- Set HP bar size (max size is {1, 0}, {0.729, 0})
					local hpPercent = maxHP > 0 and (currentHP / maxHP) or 0
					hpBar.Size = UDim2.new(hpPercent, 0, 0.729, 0)
				end
				
				if hpText and hpText:IsA("TextLabel") then
					hpText.Text = "HP: " .. tostring(currentHP) .. "/" .. tostring(maxHP)
				end
			end
			
			-- Handle UseNotifier for ML items
			local useNotifier = slotButton:FindFirstChild("UseNotifier")
			if useNotifier and useNotifier:IsA("TextLabel") then
				if selectedItem then
					local itemDef = ItemsModule[selectedItem]
					if itemDef and itemDef.Category == "MoveLearners" then
						-- Show UseNotifier, hide HPMain
						if hpMain then
							hpMain.Visible = false
						end
						useNotifier.Visible = true
						
						-- Check if creature can learn the move
						local canLearn = canCreatureLearnMove(creatureData.Name, selectedItem)
						if canLearn then
							useNotifier.Text = "Can learn"
							useNotifier.TextColor3 = Color3.fromRGB(0, 255, 0) -- Green
						else
							useNotifier.Text = "Cannot learn"
							useNotifier.TextColor3 = Color3.fromRGB(255, 0, 0) -- Red
						end
					else
						-- Hide UseNotifier, show HPMain
						useNotifier.Visible = false
						if hpMain then
							hpMain.Visible = true
						end
					end
				else
					-- No item selected, hide UseNotifier, show HPMain
					useNotifier.Visible = false
					if hpMain then
						hpMain.Visible = true
					end
				end
			end
		end
	end
end

refreshCreatureList = refreshCreatureList_impl

local function isItemUsableInContext(itemName: string?): boolean
	if not itemName then return false end
	local def = ItemsModule[itemName]
	if not def then return false end
	-- Disallow capture items during trainer battles client-side for clarity
	if inBattle and isTrainerBattle and itemName == "Capture Cube" then
		return false
	end
	return (inBattle and (def.UsableInBattle == true)) or ((not inBattle) and (def.UsableInOverworld == true))
end

local function isItemGiveable(itemName: string?): boolean
    if not itemName then return false end
    local def = ItemsModule[itemName]
    if not def then return false end
    -- Allow giving for all categories except MoveLearners
    if def.Category == "MoveLearners" then return false end
    return true
end

local function updateItemSelection_impl()
	-- This function updates item selection visuals
	local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
	local outer = BagGui:FindFirstChild("List")
	if not outer then return end
	local listRoot = outer:FindFirstChild("List")
	if not listRoot then return end
	
	-- Update template background colors
	for _, child in ipairs(listRoot:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Template" and child.Name ~= "Nothing" then
			if child.Name == selectedItem then
				-- Selected: #c79042
				child.BackgroundColor3 = Color3.fromRGB(199, 144, 66)
			else
				-- Not selected: rgb(255, 185, 85)
				child.BackgroundColor3 = Color3.fromRGB(255, 185, 85)
			end
		end
	end
	
	-- Update description text
	local descriptionFrame = BagGui:FindFirstChild("Description")
	if descriptionFrame then
		local descriptionText = descriptionFrame:FindFirstChild("DescriptionText")
		if descriptionText and descriptionText:IsA("TextLabel") then
			if selectedItem then
				local itemDef = ItemsModule[selectedItem]
				if itemDef then
					descriptionText.Text = itemDef.Description or ""
				else
					descriptionText.Text = ""
				end
			else
				descriptionText.Text = ""
			end
		end
	end
	
	-- Update Use and Give button visibility
	local optionsFrame = BagGui:FindFirstChild("Options")
	if optionsFrame then
		local useBtn = optionsFrame:FindFirstChild("Use")
		local giveBtn = optionsFrame:FindFirstChild("Give")
		
		if selectedItem then
			local itemDef = ItemsModule[selectedItem]
			local canUse = (inBattle and (itemDef.UsableInBattle == true)) or ((not inBattle) and (itemDef.UsableInOverworld == true))
			-- Disallow capture items during trainer battles
			if inBattle and isTrainerBattle and selectedItem == "Capture Cube" then
				canUse = false
			end
			
			if useBtn and useBtn:IsA("GuiObject") then
				useBtn.Visible = canUse
				
				-- Update Use button text based on selection mode
				local useTitle = useBtn:FindFirstChild("Title")
				if useTitle and useTitle:IsA("TextLabel") then
					if selectingCreature then
						useTitle.Text = "Cancel"
					else
						useTitle.Text = "Use"
					end
				end
			end
			
			-- Give button visibility logic (can be used in overworld for non-battle items)
            if giveBtn and giveBtn:IsA("GuiObject") then
                -- Give only in overworld, not during selection, and item must be giveable
                giveBtn.Visible = not selectingCreature and not inBattle and isItemGiveable(selectedItem)
            end
		else
			if useBtn and useBtn:IsA("GuiObject") then
				useBtn.Visible = false
			end
			if giveBtn and giveBtn:IsA("GuiObject") then
				giveBtn.Visible = false
			end
		end
	end
	
	-- Refresh creature list to update UseNotifier
	refreshCreatureList()
end

updateItemSelection = updateItemSelection_impl

local function handleUseButtonClick()
	if not selectedItem then return end

    -- Cancel selection mode if already active
    if selectingCreature then
        selectingCreature = false
        selectingAction = nil
        Say:Exit()
        updateItemSelection()
        refreshCreatureList()
        return
    end

	-- Ensure item usable in this context
	if not isItemUsableInContext(selectedItem) then
		print("[Bag] Use clicked while item not usable in this context; ignoring")
		return
	end

	local itemDef = ItemsModule[selectedItem]
	local isHealItem = itemDef and itemDef.Category == "Heals"

	-- All usable items outside battle require player to pick a target creature
    if not inBattle then
        selectingCreature = true
        selectingAction = "Use"
        local prompt = "Select a creature to use this item on."
        if itemDef and itemDef.Category == "MoveLearners" then
            prompt = "Select a creature to teach this move."
        end
        -- Lock the prompt (cannot be clicked off)
        Say:Say("", false, {prompt}, nil, nil)
        updateItemSelection()
        refreshCreatureList()
        return
    end

	-- In battle, use item immediately (server determines target)
	local Events = game.ReplicatedStorage:WaitForChild("Events")
	local ok = false
	pcall(function()
		ok = Events.Request:InvokeServer({"UseItem", { Name = selectedItem, Context = inBattle and "Battle" or "Overworld" }}) == true
	end)
    if ok then
        refreshCreatureList()
        -- Close the bag after using a capture item during battle
        local def = ItemsModule[selectedItem]
        if inBattle and def and def.Category == "CaptureCubes" then
            BagModule:Close()
            -- Restore battle options UI so player can continue
            local okRestore, err = pcall(function()
                local gui = game.Players.LocalPlayer.PlayerGui
                local bo = gui:FindFirstChild("GameUI") and gui.GameUI:FindFirstChild("BattleUI") and gui.GameUI.BattleUI:FindFirstChild("BattleOptions")
                if bo then
                    bo.Visible = true
                    for _, child in ipairs(bo:GetChildren()) do
                        if child:IsA("TextButton") or child:IsA("ImageButton") then
                            child.Active = true
                            child.Visible = true
                        end
                    end
                end
            end)
            if not okRestore then
                warn("[Bag] Failed to restore battle options after capture use:", err)
            end
        end
    end
end

function BagModule:Init(All)
	--Populate Bag

	-- Helpers
	local function getInventory(): {[string]: number}
		local data = ClientData:Get() or {}
		data.Items = data.Items or {}
		return data.Items
	end

    local function clearList(listFrame: Instance)
        local keep: {[string]: boolean} = {
            Template = true,
            Nothing = true,
            UIListLayout = true,
            UIPadding = true,
        }
        for _, child in ipairs(listFrame:GetChildren()) do
            -- Remove any row clone while preserving structural/layout elements explicitly listed
            if child:IsA("GuiObject") and not keep[child.Name] then
                child:Destroy()
            end
        end
		if connections then
			for _, c in ipairs(connections) do
				pcall(function() if c and c.Connected then c:Disconnect() end end)
			end
			connections = {}
		end
		selectedItem = nil
	end

	local function setConfirmState(confirmBtn: TextButton?, itemName: string?)
		if not confirmBtn then return end
		-- If no selection, hide and disable
		if not itemName then
			confirmBtn.Visible = false
			confirmBtn.Active = false
			confirmBtn.AutoButtonColor = false
			return
		end

		-- Set item icon image in ConfirmUse button
		local itemIcon = confirmBtn:FindFirstChild("ItemIcon")
		if itemIcon and itemIcon:IsA("ImageLabel") then
			local def = ItemsModule[itemName]
			if def then
				itemIcon.Image = def.Image or "rbxassetid://0"
			end
		end

		local usable = isItemUsableInContext(itemName)
		-- Show only when usable in this context
		confirmBtn.Visible = usable
		confirmBtn.Active = usable
		confirmBtn.AutoButtonColor = usable
		-- Green when usable (confirm), red when blocked
		local colorUsable = Color3.fromRGB(80, 180, 80)
		local colorBlocked = Color3.fromRGB(200, 50, 50)
		local target = usable and colorUsable or colorBlocked
		confirmBtn.BackgroundColor3 = target
		-- Also recolor any UIStroke on the button and its text descendants
		for _, desc in ipairs(confirmBtn:GetDescendants()) do
			if desc:IsA("UIStroke") then
				desc.Color = target
			elseif desc:IsA("TextLabel") or desc:IsA("TextButton") then
				pcall(function()
					if desc.TextStrokeColor3 ~= nil then
						desc.TextStrokeColor3 = target
					end
				end)
				local textStroke = desc:FindFirstChildWhichIsA("UIStroke")
				if textStroke then
					textStroke.Color = target
				end
			end
		end
	end


	-- Update the visible filter title text in the Bag UI (e.g., "Capture Cubes")
	local function setFilterTitle(category: string)
		local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
		local outer = BagGui:FindFirstChild("List")
		if not outer then return end
		local currentFilter = outer:FindFirstChild("CurrentFilter")
		if not currentFilter then return end
		local title = currentFilter:FindFirstChild("Title")
		if not (title and title:IsA("TextLabel")) then return end
		local pretty = ({
			Heals = "Heals",
			Items = "Items",
			CaptureCubes = "Capture Cubes",
			MoveLearners = "ML",
		})[category] or category
		title.Text = pretty
	end

    local function populate(category: string)
        currentCategoryName = category
        local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
        local outer = BagGui:FindFirstChild("List")
        local outerPath = BagGui:GetFullName() .. ".List"
        print("[Bag] populate category:", category, "outer:", outerPath, outer ~= nil)
        if not outer then return end
        local listRoot = outer:FindFirstChild("List")
        local innerPath = outer:GetFullName() .. ".List"
        print("[Bag] inner:", innerPath, listRoot ~= nil)
        if not listRoot then return end
        local template = listRoot:FindFirstChild("Template")
        local templatePath = listRoot:GetFullName() .. ".Template"
        print("[Bag] template:", templatePath, template ~= nil, template and template.ClassName)
        if not template then return end
        if not (template:IsA("GuiObject")) then
            print("[Bag] Template is not a GuiObject; abort populate")
            return
        end
		clearList(listRoot)
		local inv = getInventory()
        local added = 0
        local total = 0
		for itemName, count in pairs(inv) do
            total += 1
			local def = ItemsModule[itemName]
			if def and def.Category == category and count > 0 then
				local row = template:Clone()
				row.Visible = true
				row.Name = itemName
				row.Parent = listRoot
				-- Set default background color (not selected)
				row.BackgroundColor3 = Color3.fromRGB(255, 185, 85)
				-- Try to populate common fields if present
				local nameLbl = row:FindFirstChild("Name") or row:FindFirstChild("ItemName")
				if nameLbl and nameLbl:IsA("TextLabel") then
					nameLbl.Text = itemName
				end
				local countLbl = row:FindFirstChild("Count") or row:FindFirstChild("Qty")
				if countLbl and countLbl:IsA("TextLabel") then
					countLbl.Text = "x" .. tostring(count)
				end
				-- Description is now shown in Bag.Description.DescriptionText, not in template
				-- Set item icon image
				local itemIcon = row:FindFirstChild("ItemIcon")
				if itemIcon and itemIcon:IsA("ImageLabel") then
					itemIcon.Image = def.Image or "rbxassetid://0"
				end
				-- Click to select
				local conn = UIFunctions:NewButton(
					row,
					{"Action"},
					{ Click = "One", HoverOn = "One", HoverOff = "One" },
					0.7,
					function()
						Audio.SFX.Click:Play()
						selectedItem = itemName
						local confirmBtn = BagGui:FindFirstChild("ConfirmUse", true)
						if confirmBtn and confirmBtn:IsA("TextButton") then
							setConfirmState(confirmBtn, selectedItem)
						end
						-- Update selection visuals and description
						updateItemSelection()
                        print("[Bag] Selected item:", selectedItem)
					end
				)
				if connections and conn then table.insert(connections, conn) end
                added += 1
			end
		end
        print("[Bag] Inventory entries:", total, "Added to list:", added)
        -- Show/hide Nothing stub
                local nothing = listRoot:FindFirstChild("Nothing")
                if nothing and nothing:IsA("GuiObject") then
            nothing.Visible = (added == 0)
            print("[Bag] Nothing visible:", nothing.Visible)
        end
		-- Update confirm state based on current selection (or none)
		local confirmBtn = BagGui:FindFirstChild("ConfirmUse", true)
		if confirmBtn and confirmBtn:IsA("TextButton") then
			setConfirmState(confirmBtn, selectedItem)
		end
		-- Update the UI label for the active filter
		setFilterTitle(category)
		-- Update item selection visuals
		updateItemSelection()
	end

	-- Wire ConfirmUse and Cancel buttons if present
	local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
	local ConfirmUse = BagGui:FindFirstChild("ConfirmUse", true)
	local Cancel = BagGui:FindFirstChild("Cancel", true)
	local function isButton(inst: Instance?): boolean
		return inst and (inst:IsA("TextButton") or inst:IsA("ImageButton"))
	end

	local function bindUseButton(button: Instance?)
		if not isButton(button) then return end
		UIFunctions:NewButton(button, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.7, function()
			Audio.SFX.Click:Play()
			handleUseButtonClick()
		end)
	end

    local function bindGiveButton(button: Instance?)
        if not isButton(button) then return end
        UIFunctions:NewButton(button, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.7, function()
            Audio.SFX.Click:Play()
            if not selectedItem then return end
            if inBattle then return end -- Give only in overworld
            if not isItemGiveable(selectedItem) then return end
            -- Enter selection mode for Give
            selectingCreature = true
            selectingAction = "Give"
            Say:Say("", false, {"Select a creature to give this item to."}, nil, nil)
            updateItemSelection()
            refreshCreatureList()
        end)
    end

	if isButton(ConfirmUse) then
		bindUseButton(ConfirmUse)
        ConfirmUse.Visible = false
	end
    if isButton(Cancel) then
        -- Cancel only visible in battle
        Cancel.Visible = inBattle
        UIFunctions:NewButton(Cancel, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.7, function()
			Audio.SFX.Click:Play()
            BagModule:Close()
            -- If in battle, re-show battle options immediately
            if inBattle then
                local ok, err = pcall(function()
                    local UI = require(script.Parent.Parent.UI)
                    -- Ask BattleSystemV2 to reshow via its options manager if available
                    local Starter = game:GetService("StarterPlayer").StarterPlayerScripts.Client.Battle
                    -- Fallback: use UIController directly if battle UI exists
                    local Rep = game:GetService("ReplicatedStorage")
                    -- A light touch: just toggle the BattleOptions frame back on
                    local gui = game.Players.LocalPlayer.PlayerGui
                    local bo = gui:FindFirstChild("GameUI") and gui.GameUI:FindFirstChild("BattleUI") and gui.GameUI.BattleUI:FindFirstChild("BattleOptions")
                    if bo then
                        bo.Visible = true
                        for _, child in ipairs(bo:GetChildren()) do
                            if child:IsA("TextButton") or child:IsA("ImageButton") then
                                child.Active = true
                                child.Visible = true
                            end
                        end
                    end
                end)
                if not ok then warn("[Bag] Failed to restore battle options:", err) end
            end
		 end)
	end
	
	-- Wire Use and Give buttons in Options frame
	local OptionsFrame = BagGui:FindFirstChild("Options")
	if OptionsFrame then
		local UseBtn = OptionsFrame:FindFirstChild("Use")
		local GiveBtn = OptionsFrame:FindFirstChild("Give")
		
		if UseBtn and UseBtn ~= ConfirmUse then
			bindUseButton(UseBtn)
		end

		bindGiveButton(GiveBtn)
	end
	
	UIFunctions:NewButton(
		game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag"):WaitForChild("SortBy"):WaitForChild("Items"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
        function()
			Audio.SFX.Click:Play()
            print("[Bag] Sort by Items clicked")
			populate("Items")
		end
	)
	
	UIFunctions:NewButton(
		game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag"):WaitForChild("SortBy"):WaitForChild("Heals"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
        function()
			Audio.SFX.Click:Play()
            print("[Bag] Sort by Heals clicked")
			populate("Heals")
		end
	)
	
	UIFunctions:NewButton(
		game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag"):WaitForChild("SortBy"):WaitForChild("CaptureCubes"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
        function()
			Audio.SFX.Click:Play()
            print("[Bag] Sort by CaptureCubes clicked")
			populate("CaptureCubes")
		end
	)
	
	UIFunctions:NewButton(
		game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag"):WaitForChild("SortBy"):WaitForChild("MoveLearners"),
		{"Action"},
		{ Click = "One", HoverOn = "One", HoverOff = "One" },
		0.7,
        function()
			Audio.SFX.Click:Play()
            print("[Bag] Sort by MoveLearners clicked")
			populate("MoveLearners")
		end
	)

	-- Initial population default: Heals
	populate("Heals")
	
	-- Initial creature list refresh
	refreshCreatureList()

	_initialized = true
	
end

function BagModule:SetCallbacks(onOpen: (() -> ())?, onClose: (() -> ())?)
    OnOpenCallback = onOpen
    OnCloseCallback = onClose
end

--// Refresh Bag UI with updated inventory
function BagModule:RefreshBag()
    if not _initialized then
        print("[Bag] Cannot refresh - not initialized")
        return
    end
    
    -- Get the current category being displayed
    local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
    local currentCategory = currentCategoryName or "Heals"
    
    print("[Bag] Refreshing bag UI for category:", currentCategory)
    
    -- Re-populate the current category
    local outer = BagGui:FindFirstChild("List")
    if not outer then return end
    local listRoot = outer:FindFirstChild("List")
    if not listRoot then return end
    local template = listRoot:FindFirstChild("Template")
    if not template or not template:IsA("GuiObject") then return end
    
    -- Clear and repopulate
    local function clearList(listFrame: Instance)
        local keep: {[string]: boolean} = {
            Template = true,
            Nothing = true,
            UIListLayout = true,
            UIPadding = true,
        }
        for _, child in ipairs(listFrame:GetChildren()) do
            if child:IsA("GuiObject") and not keep[child.Name] then
                child:Destroy()
            end
        end
        if connections then
            for _, c in ipairs(connections) do
                pcall(function() if c and c.Connected then c:Disconnect() end end)
            end
            connections = {}
        end
        -- Preserve selectedItem to avoid disrupting the user's current page/selection
    end
    
    local function getInventory(): {[string]: number}
        local data = ClientData:Get() or {}
        data.Items = data.Items or {}
        return data.Items
    end
    
    local function setConfirmState(confirmBtn: TextButton?, itemName: string?)
        if not confirmBtn then return end
        if not itemName then
            confirmBtn.Visible = false
            confirmBtn.Active = false
            confirmBtn.AutoButtonColor = false
            return
        end
        -- Set item icon image in ConfirmUse button
        local itemIcon = confirmBtn:FindFirstChild("ItemIcon")
        if itemIcon and itemIcon:IsA("ImageLabel") then
            local def = ItemsModule[itemName]
            if def then
                itemIcon.Image = def.Image or "rbxassetid://0"
            end
        end
        local usable = isItemUsableInContext(itemName)
        confirmBtn.Visible = usable
        confirmBtn.Active = usable
        confirmBtn.AutoButtonColor = usable
        local colorUsable = Color3.fromRGB(80, 180, 80)
        local colorBlocked = Color3.fromRGB(200, 50, 50)
        local target = usable and colorUsable or colorBlocked
        confirmBtn.BackgroundColor3 = target
        for _, desc in ipairs(confirmBtn:GetDescendants()) do
            if desc:IsA("UIStroke") then
                desc.Color = target
            elseif desc:IsA("TextLabel") or desc:IsA("TextButton") then
                pcall(function()
                    if desc.TextStrokeColor3 ~= nil then
                        desc.TextStrokeColor3 = target
                    end
                end)
                local textStroke = desc:FindFirstChildWhichIsA("UIStroke")
                if textStroke then
                    textStroke.Color = target
                end
            end
        end
    end
    
    clearList(listRoot)
    local inv = getInventory()
    local added = 0
    local total = 0
    for itemName, count in pairs(inv) do
        total += 1
        local def = ItemsModule[itemName]
        if def and def.Category == currentCategory and count > 0 then
            local row = template:Clone()
            row.Visible = true
            row.Name = itemName
            row.Parent = listRoot
            -- Set default background color (not selected)
            row.BackgroundColor3 = Color3.fromRGB(255, 185, 85)
            local nameLbl = row:FindFirstChild("Name") or row:FindFirstChild("ItemName")
            if nameLbl and nameLbl:IsA("TextLabel") then
                nameLbl.Text = itemName
            end
            local countLbl = row:FindFirstChild("Count") or row:FindFirstChild("Qty")
            if countLbl and countLbl:IsA("TextLabel") then
                countLbl.Text = "x" .. tostring(count)
            end
            -- Description is now shown in Bag.Description.DescriptionText, not in template
            -- Set item icon image
            local itemIcon = row:FindFirstChild("ItemIcon")
            if itemIcon and itemIcon:IsA("ImageLabel") then
                itemIcon.Image = def.Image or "rbxassetid://0"
            end
            local conn = UIFunctions:NewButton(
                row,
                {"Action"},
                { Click = "One", HoverOn = "One", HoverOff = "One" },
                0.7,
                function()
                    Audio.SFX.Click:Play()
                    selectedItem = itemName
                    local confirmBtn = BagGui:FindFirstChild("ConfirmUse", true)
                    if confirmBtn and confirmBtn:IsA("TextButton") then
                        setConfirmState(confirmBtn, selectedItem)
                    end
                    -- Update selection visuals and description
                    updateItemSelection()
                    print("[Bag] Selected item:", selectedItem)
                end
            )
            if connections and conn then table.insert(connections, conn) end
            added += 1
        end
    end
    print("[Bag] Refreshed inventory entries:", total, "Added to list:", added)
    local nothing = listRoot:FindFirstChild("Nothing")
    if nothing and nothing:IsA("GuiObject") then
        nothing.Visible = (added == 0)
    end
    local confirmBtn = BagGui:FindFirstChild("ConfirmUse", true)
    if confirmBtn and confirmBtn:IsA("TextButton") then
        setConfirmState(confirmBtn, selectedItem)
    end
    
    -- Refresh creature list and update selection visuals
    refreshCreatureList()
    updateItemSelection()
end

--// Bag Open
function BagModule:Open(All)
	if isOpen then return end -- Already open, don't open again
	
	isOpen = true
    -- Ensure setup is done once
    if not _initialized then
        pcall(function() self:Init(All) end)
    end
    -- Detect context (battle vs overworld) via presence of BattleUI
    local GameUI = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI")
    -- In battle only when BattleUI is visible, or when caller passes explicit Context = "Battle"
	inBattle = (All and All.Context == "Battle") or ((GameUI:FindFirstChild("BattleUI") and GameUI.BattleUI.Visible) == true)
	isTrainerBattle = (All and All.IsTrainer == true) or false
    -- Reset selection and confirm visibility when opening
    selectedItem = nil
    local confirmBtn = game.Players.LocalPlayer.PlayerGui.GameUI.Bag:FindFirstChild("ConfirmUse", true)
    if confirmBtn and confirmBtn:IsA("TextButton") then
        confirmBtn.Visible = false
        confirmBtn.Active = false
        confirmBtn.AutoButtonColor = false
    end
	-- Set the filter title when opening (default to current category or "Heals")
    local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
    local currentCategory = "Heals" -- Default category
    local sortBy = BagGui:FindFirstChild("SortBy")
    if sortBy then
        for _, button in ipairs(sortBy:GetChildren()) do
            if button:IsA("TextButton") and button.BackgroundColor3 == Color3.fromRGB(80, 180, 80) then
                currentCategory = button.Name
                break
            end
        end
    end
    -- Set filter title directly and remember currentCategory
    local outer = BagGui:FindFirstChild("List")
    if outer then
        local currentFilter = outer:FindFirstChild("CurrentFilter")
        if currentFilter then
            local title = currentFilter:FindFirstChild("Title")
            if title and title:IsA("TextLabel") then
                local pretty = ({
                    Heals = "Heals",
                    Items = "Items",
                    CaptureCubes = "Capture Cubes",
                    MoveLearners = "ML",
                })[currentCategory] or currentCategory
                title.Text = pretty
            end
        end
    end
    currentCategoryName = currentCategory
    -- Ensure Cancel visibility reflects battle context
    local cancelBtn = game.Players.LocalPlayer.PlayerGui.GameUI.Bag:FindFirstChild("Cancel", true)
    if cancelBtn and cancelBtn:IsA("GuiObject") then
        cancelBtn.Visible = inBattle
    end
	local Bag: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
	
	Audio.SFX.Open:Play()

	Bag.Visible = true
	Bag.Size = CLOSED_SIZE

	-- Main Frame
	TweenService:Create(Bag, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = OPEN_SIZE,
	}):Play()
	
	Bag.Position = UDim2.new(0.435, 0,0.1, 0)
	TweenService:Create(Bag, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5,0,0.5,0),
	}):Play()

	-- Shadow
	Bag.Shadow.Image.ImageTransparency = 1
	TweenService:Create(Bag.Shadow.Image, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 0.5,
	}):Play()

	-- Topbar
	Bag.Topbar.Size = UDim2.fromScale(1, 0.165)
	TweenService:Create(Bag.Topbar, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.107),
	}):Play()

	-- Icon + Shadow
	Bag.Topbar.Icon.Rotation = 25
	Bag.Topbar.Icon.Position = UDim2.new(0.05, 0, 0.341, 0)
	Bag.Topbar.IconShadow.Position = UDim2.new(0.084, 0, 0.682, 0)

	TweenService:Create(Bag.Topbar.Icon, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 0,
		Position = UDim2.new(0.041, 0, 0.185, 0),
	}):Play()
	TweenService:Create(Bag.Topbar.IconShadow, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.066, 0, 0.526, 0),
	}):Play()

	-- Title
	Bag.Topbar.Title.MaxVisibleGraphemes = 0
	TweenService:Create(Bag.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 8,
	}):Play()

	-- Darken
	Bag.Darken.Size = CLOSED_SIZE
	TweenService:Create(Bag.Darken, TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.new(4.0125, 0,6.0945, 0),
	}):Play()

	-- Refresh creature list and update selection visuals
	refreshCreatureList()
	updateItemSelection()

    if OnOpenCallback then
        pcall(OnOpenCallback)
    end
end

--// Bag Close
function BagModule:Close(All)
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
    -- If we were waiting for a creature selection, cancel cleanly
    if selectingCreature then
        selectingCreature = false
        selectingAction = nil
        pcall(function()
            Say:Exit()
        end)
        -- Hide any floating CreatureOptions and clear off-click handler
        local ok = pcall(function()
            local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
            local creaturesContainer = BagGui:FindFirstChild("Creatures")
            if creaturesContainer then
                local options = creaturesContainer:FindFirstChild("CreatureOptions", true)
                if options and options:IsA("Frame") then
                    options.Parent = creaturesContainer
                    options.Visible = false
                end
            end
        end)
        if creatureOptionsOffConn and creatureOptionsOffConn.Connected then
            creatureOptionsOffConn:Disconnect()
        end
        creatureOptionsOffConn = nil
        -- Refresh UI state so buttons/text reset
        pcall(function()
            updateItemSelection()
            refreshCreatureList()
        end)
    end
	local Bag: ScreenGui & {
		Shadow: { Image: ImageLabel },
		Topbar: {
			Size: UDim2,
			Icon: ImageLabel,
			IconShadow: ImageLabel,
			Title: TextLabel,
		},
		Darken: Frame,
	} = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")

	Audio.SFX.Close:Play()
	
	task.delay(0.1, function()
		TweenService:Create(Bag, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Size = CLOSED_SIZE,
		}):Play()
	end)
	
	task.delay(0.15,function()
		TweenService:Create(Bag, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.435, 0,0.1, 0),
		}):Play()
	end)

	TweenService:Create(Bag.Shadow.Image, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageTransparency = 1,
	}):Play()

	TweenService:Create(Bag.Topbar, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 0.1),
	}):Play()

	TweenService:Create(Bag.Topbar.Icon, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Rotation = 25,
		Position = UDim2.new(0.05, 0, 0.341, 0),
	}):Play()
	TweenService:Create(Bag.Topbar.IconShadow, TweenInfo.new(0.25, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.084, 0, 0.682, 0),
	}):Play()

	TweenService:Create(Bag.Topbar.Title, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		MaxVisibleGraphemes = 0,
	}):Play()

	TweenService:Create(Bag.Darken, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Size = CLOSED_SIZE,
	}):Play()

	task.delay(0.4, function()
		Bag.Visible = false
        if OnCloseCallback then
            pcall(OnCloseCallback)
        end
	end)
end

return BagModule


--!nocheck
local BagModule = {}
local isOpen = false
local inBattle = false
local isTrainerBattle = false
local selectedItem: string? = nil
local connections: {RBXScriptConnection}? = {}
local _initialized = false
local OnOpenCallback: (() -> ())? = nil
local OnCloseCallback: (() -> ())? = nil

--// Services/Modules for data
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemsModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Items"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))
-- (deduped above)

--// Services
local TweenService: TweenService = game:GetService("TweenService")
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))

local Audio = script.Parent.Parent.Assets:WaitForChild("Audio")

--// Animation Constants
local OPEN_SIZE: UDim2 = UDim2.fromScale(0.626, 0.571)
local CLOSED_SIZE: UDim2 = UDim2.fromScale(0, 0)

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
		})[category] or category
		title.Text = pretty
	end

    local function populate(category: string)
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
				-- Try to populate common fields if present
				local nameLbl = row:FindFirstChild("Name") or row:FindFirstChild("ItemName")
				if nameLbl and nameLbl:IsA("TextLabel") then
					nameLbl.Text = itemName
				end
				local countLbl = row:FindFirstChild("Count") or row:FindFirstChild("Qty")
				if countLbl and countLbl:IsA("TextLabel") then
					countLbl.Text = "x" .. tostring(count)
				end
				local descLbl = row:FindFirstChild("Description")
				if descLbl and descLbl:IsA("TextLabel") then
					descLbl.Text = def.Description
				end
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
	end

	-- Wire ConfirmUse and Cancel buttons if present
	local BagGui = game.Players.LocalPlayer.PlayerGui:WaitForChild("GameUI"):WaitForChild("Bag")
	local ConfirmUse = BagGui:FindFirstChild("ConfirmUse", true)
	local Cancel = BagGui:FindFirstChild("Cancel", true)
	local function isButton(inst: Instance?): boolean
		return inst and (inst:IsA("TextButton") or inst:IsA("ImageButton"))
	end
	if isButton(ConfirmUse) then
		UIFunctions:NewButton(ConfirmUse, {"Action"}, { Click = "One", HoverOn = "One", HoverOff = "One" }, 0.7, function()
			Audio.SFX.Click:Play()
			if not selectedItem then return end
			-- Revalidate usability at click time to prevent accidental use
			if not isItemUsableInContext(selectedItem) then
				print("[Bag] ConfirmUse clicked while item not usable in this context; ignoring")
				return
			end
			-- Fire request to server to use item; server enforces context and turn usage
			local Events = game.ReplicatedStorage:WaitForChild("Events")
			local ok = false
			pcall(function()
				ok = Events.Request:InvokeServer({"UseItem", { Name = selectedItem, Context = inBattle and "Battle" or "Overworld" }}) == true
			end)
			if ok then
				BagModule:Close()
			end
		end)
        -- Hide until a usable item is selected
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

	-- Initial population default: Heals
	populate("Heals")

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
    local currentCategory = "Heals" -- Default category
    
    -- Try to determine current category from UI state
    local sortBy = BagGui:FindFirstChild("SortBy")
    if sortBy then
        for _, button in ipairs(sortBy:GetChildren()) do
            if button:IsA("TextButton") and button.BackgroundColor3 == Color3.fromRGB(80, 180, 80) then
                currentCategory = button.Name
                break
            end
        end
    end
    
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
        selectedItem = nil
    end
    
    local function getInventory(): {[string]: number}
        local data = ClientData:Get() or {}
        data.Items = data.Items or {}
        return data.Items
    end
    
    local function isItemUsableInContext(itemName: string?): boolean
        if not itemName then return false end
        local def = ItemsModule[itemName]
        if not def then return false end
        return (inBattle and (def.UsableInBattle == true)) or ((not inBattle) and (def.UsableInOverworld == true))
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
            local nameLbl = row:FindFirstChild("Name") or row:FindFirstChild("ItemName")
            if nameLbl and nameLbl:IsA("TextLabel") then
                nameLbl.Text = itemName
            end
            local countLbl = row:FindFirstChild("Count") or row:FindFirstChild("Qty")
            if countLbl and countLbl:IsA("TextLabel") then
                countLbl.Text = "x" .. tostring(count)
            end
            local descLbl = row:FindFirstChild("Description")
            if descLbl and descLbl:IsA("TextLabel") then
                descLbl.Text = def.Description
            end
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
    -- Set filter title directly
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
                })[currentCategory] or currentCategory
                title.Text = pretty
            end
        end
    end
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

    if OnOpenCallback then
        pcall(OnOpenCallback)
    end
end

--// Bag Close
function BagModule:Close(All)
	if not isOpen then return end -- Not open, don't close
	
	isOpen = false
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


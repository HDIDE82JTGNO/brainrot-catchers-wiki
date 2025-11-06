local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local GameUI = PlayerGui:WaitForChild("GameUI")
local Audio = script.Parent.Parent:WaitForChild("Assets"):WaitForChild("Audio")
local SFX = ReplicatedStorage:WaitForChild("Audio"):WaitForChild("SFX")
local SummaryUI = require(script.Parent:WaitForChild("Summary"))
local UIFunctions = require(script.Parent:WaitForChild("UIFunctions"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Creatures = require(Shared:WaitForChild("Creatures"))

local UtilitiesFolder = script.Parent.Parent:WaitForChild("Utilities")
local Say = require(UtilitiesFolder:WaitForChild("Say"))
local CharacterFunctions = require(UtilitiesFolder:WaitForChild("CharacterFunctions"))
local ClientData = require(script.Parent.Parent:WaitForChild("Plugins"):WaitForChild("ClientData"))

local Events = ReplicatedStorage:WaitForChild("Events")
local Request = Events:WaitForChild("Request")

local Vault = {}
-- Predefined Box Background IDs (expandable)
local BOX_BACKGROUNDS: {number} = {
    140677672905926, -- CatchInc
    81042384701409,  -- BC's logo
    89197109127471,  -- Yellow studs
    122211658648741, -- Blue studs
    104351619158315, -- Red studs
    82088477616564,  -- Shiny (1)
}

local function getDefaultBackgroundForBox(index: number): string
    if #BOX_BACKGROUNDS == 0 then return "" end
    local i = math.max(1, ((index - 1) % #BOX_BACKGROUNDS) + 1)
    return tostring(BOX_BACKGROUNDS[i])
end

local function setCurrentBoxBackground(imageContainer: Instance?, bgId: string?)
    if not imageContainer then return end
    if not bgId or bgId == "" then return end
    local url = "rbxassetid://" .. tostring(bgId)
    if imageContainer:IsA("ImageLabel") or imageContainer:IsA("ImageButton") then
        (imageContainer :: any).Image = url
    end
end

local function getBackgroundForBoxIndex(boxes: {any}, index: number): string
    local entry = boxes[index]
    local bgId = entry and (entry :: any).Background
    if not bgId or bgId == "" then
        bgId = getDefaultBackgroundForBox(index)
    end
    return tostring(bgId)
end

local function setBoxListEntryBackground(entry: Instance, bgId: string)
    if not entry or not bgId then return end
    local container: Instance? = entry:FindFirstChild("Backdrop")
        or entry:FindFirstChild("Background")
        or entry:FindFirstChild("BG")
    if not container then
        local bx = entry:FindFirstChild("Box")
        if bx and (bx:IsA("ImageLabel") or bx:IsA("ImageButton")) then
            container = bx
        end
    end
    setCurrentBoxBackground(container, bgId)
end


-- Internal state
local _currentBoxIndex = 1
local _swapState = { from = nil } -- from = { where = "Box"|"Party", box = number?, index = number }
local _pendingBoxesOrder = nil -- snapshot to send on close
local _pendingParty = nil -- snapshot party to send on close

local function getGui()
    local gui = GameUI:FindFirstChild("Vault")
    if gui then return gui end
    return nil
end

-- Screen flash animation used on Vault open/close
local function playVaultFlash(isOpening: boolean)
    local container = GameUI
    if not container then return end

    local b = Instance.new("Frame")
    b.Size = UDim2.fromScale(2, 0)
    b.Position = UDim2.fromScale(0.5, 0.5)
    b.AnchorPoint = Vector2.new(0.5, 0.5)
    b.Parent = container
    b.BorderSizePixel = 0
    b.ZIndex = 1000
    b.BackgroundColor3 = Color3.fromRGB(135, 227, 255)

    TweenService:Create(b, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
        Size = UDim2.fromScale(2, 2),
        BackgroundColor3 = Color3.fromRGB(53, 174, 255),
    }):Play()

    task.delay(1.5, function()
        TweenService:Create(b, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
            BackgroundTransparency = 1,
        }):Play()
    end)

    task.delay(2.3, function()
        if b then b:Destroy() end
    end)
end

local function coalesceBoxes(pd)
    local boxes = (pd and pd.Boxes) or {}
    local out = {}
    for i, entry in ipairs(boxes) do
        local name = (type(entry) == "table" and entry.Name) or ("Box " .. tostring(i))
        local list = (type(entry) == "table" and entry.Creatures) or {}
        table.insert(out, { Name = tostring(name), Creatures = list })
    end
    if #out == 0 then
        table.insert(out, { Name = "Box 1", Creatures = {} })
    end
    return out
end

local function clampToMax30(creatures: {any}): {any}
    local out = {}
    for i = 1, math.min(#creatures, 30) do
        out[i] = creatures[i]
    end
    return out
end

local function clearChildrenExcept(container, keepSet)
    for _, child in ipairs(container:GetChildren()) do
        if not keepSet[child.ClassName] and child.Name ~= "UIGridLayout" and child.Name ~= "UIAspectRatioConstraint" and child.Name ~= "UIPadding" then
            -- additionally keep templates by specific names if present
            if not keepSet[child.Name] then
                child:Destroy()
            end
        end
    end
end

local function clearAllChildren(inst)
    for _, child in ipairs(inst:GetChildren()) do
        child:Destroy()
    end
end

local function showCreatureOptions(rootButton, handlers, context)
    local gui = getGui()
    if not gui then return end
    -- Remove any existing options under other boxes
    local function purgeExisting()
        for _, b in ipairs(gui:GetDescendants()) do
            if b.Name == "CreatureOptions" and b:IsA("Frame") then
                -- Do not destroy the template living directly under Vault
                if b.Parent ~= gui then
                    b:Destroy()
                end
            end
        end
    end
    purgeExisting()
    -- Ensure BoxOptions is hidden while CreatureOptions is shown (mutual exclusivity)
    do
        local bo = gui:FindFirstChild("BoxOptions_Active")
        if bo and bo:IsA("Frame") then
            bo.Visible = false
        end
    end
    -- Locate CreatureOptions strictly under Vault (GameUI.Vault.CreatureOptions)
    local template = gui:FindFirstChild("CreatureOptions")
    if not template then
        template = gui:WaitForChild("CreatureOptions")
    end
    local options = template:Clone()
    options.Visible = true
    options.Parent = rootButton
    -- If slot is empty, keep only Swap button
    if context and context.isEmpty == true then
        for _, child in ipairs(options:GetChildren()) do
            if child:IsA("GuiObject") and child.Name ~= "Swap" then
                child:Destroy()
            end
        end
    end

    -- If swap already selected on this same creature, label as Cancel
    do
        local same = false
        if _swapState.from and context then
            if _swapState.from.where == context.where and _swapState.from.index == context.index then
                if context.where == "Box" then
                    same = (_swapState.from.box == context.box)
                else
                    same = true
                end
            end
        end
        if same then
            local swapBtn = options:FindFirstChild("Swap")
            if swapBtn then
                local title = swapBtn:FindFirstChild("Title")
                if title and title:IsA("TextLabel") then
                    title.Text = "Cancel"
                end
            end
        end
    end
    -- Wire buttons
    local function bind(btnName: string, cb: ()->())
        local b = options:FindFirstChild(btnName)
        if b and b:IsA("TextButton") then
            b.MouseButton1Click:Connect(function()
                options:Destroy()
                cb()
            end)
        end
    end
    bind("Swap", handlers.onSwap)
    bind("Summary", handlers.onSummary)
    bind("TakeItem", handlers.onTakeItem)
    bind("Desync", handlers.onDesync)

    -- Click-off-to-dismiss
    local UIS = game:GetService("UserInputService")
    local conn
    conn = UIS.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        task.defer(function()
            if not options or not options.Parent then if conn then conn:Disconnect() end return end
            local mouse = LocalPlayer:GetMouse()
            local pos = Vector2.new(mouse.X, mouse.Y)
            local absPos = options.AbsolutePosition
            local absSize = options.AbsoluteSize
            local inside = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
            if not inside then
                options:Destroy()
                if conn then conn:Disconnect() end
            end
        end)
    end)
    options.Destroying:Connect(function()
        if conn then conn:Disconnect() end
    end)
end

local function setIconState(button, creature)
    local icon = button:FindFirstChild("CreatureIcon")
    if icon and icon:IsA("ImageLabel") then
        local base = Creatures[creature.Name]
        if base then
            local useShiny = creature.Shiny == true
            icon.Image = (useShiny and base.ShinySprite) or base.Sprite
        end
    end
    local shiny = button:FindFirstChild("Shiny")
    local shinyShadow = button:FindFirstChild("ShinyShadow")
    if shiny and shiny:IsA("ImageLabel") then shiny.Visible = creature.Shiny == true end
    if shinyShadow and shinyShadow:IsA("ImageLabel") then shinyShadow.Visible = creature.Shiny == true end
    local held = button:FindFirstChild("HeldItem")
    local heldShadow = button:FindFirstChild("HeldItemShadow")
    local hasHeld = creature.HeldItem ~= nil and creature.HeldItem ~= ""
    if held and held:IsA("ImageLabel") then held.Visible = hasHeld end
    if heldShadow and heldShadow:IsA("ImageLabel") then heldShadow.Visible = hasHeld end
end

local function renderCurrentBox()
    local gui = getGui(); if not gui then return end
    local middle = gui:FindFirstChild("Middle")
    if not middle then return end
    local currentBox = middle:FindFirstChild("CurrentBox")
    if not currentBox then return end
    local boxTemplate = gui:FindFirstChild("BoxTemplate")
    if not boxTemplate then return end

    local pd = ClientData:Get()
    local boxes = _pendingBoxesOrder or coalesceBoxes(pd)
    local entry = boxes[_currentBoxIndex]
    local list = (entry and entry.Creatures) or {}

    -- Update header title with current box name
    do
        local titleLabel = middle:FindFirstChild("Title")
        if titleLabel and titleLabel:IsA("TextLabel") then
            titleLabel.Text = tostring((entry and entry.Name) or ("Box " .. tostring(_currentBoxIndex)))
        end
    end

    -- Apply background to CurrentBox (ImageLabel/ImageButton)
    do
        local bgId = (entry and (entry :: any).Background)
        if not bgId or bgId == "" then
            bgId = getDefaultBackgroundForBox(_currentBoxIndex)
        end
        setCurrentBoxBackground(currentBox, bgId)
    end

    clearChildrenExcept(currentBox, { UIGridLayout = true, UIAspectRatioConstraint = true, UIPadding = true })

    for i = 1, 30 do
        local creature = list[i]
        local b = boxTemplate:Clone()
        b.Visible = true
        b.Name = "BoxBtn_" .. tostring(i)
        b.Parent = currentBox
        if creature then
            setIconState(b, creature)
        else
            clearAllChildren(b)
        end

        b.MouseButton1Click:Connect(function()
            local isEmpty = creature == nil
            if isEmpty and _swapState.from == nil then return end
            local ctx = { where = "Box", box = _currentBoxIndex, index = i, isEmpty = isEmpty }
            showCreatureOptions(b, {
                onSwap = function()
                    if _swapState.from == nil then
                        _swapState.from = ctx
                        return
                    end
                    -- cancel if same target
                    if _swapState.from.where == ctx.where and _swapState.from.index == ctx.index and (_swapState.from.where ~= "Box" or _swapState.from.box == ctx.box) then
                        _swapState.from = nil
                        return
                    end
                    local from = _swapState.from
                    local to = ctx
                    _swapState.from = nil
                    -- perform swap across party/boxes
                    local pd2 = ClientData:Get()
                    local boxes2 = _pendingBoxesOrder or coalesceBoxes(pd2)
                    local party2 = _pendingParty or table.clone(pd2.Party or {})
                    local function getRef(loc)
                        if loc.where == "Box" then
                            local box = boxes2[loc.box]
                            return box and box.Creatures, loc.index
                        else
                            return party2, loc.index
                        end
                    end
                    local listA, idxA = getRef(from)
                    local listB, idxB = getRef(to)
                    if listA and listB then
                        listA[idxA], listB[idxB] = listB[idxB], listA[idxA]
                        _pendingBoxesOrder = boxes2
                        _pendingParty = party2
                        renderCurrentBox()
                        Vault:PopulateBoxList()
                        Vault:RenderParty()
                    end
                end,
                onSummary = function()
                    if creature then Vault:ShowSummary(creature) end
                end,
                onTakeItem = function()
                    if not creature or not creature.HeldItem or creature.HeldItem == "" then
                        local nm = creature.Nickname or creature.Name or "This creature"
                        Say:Say("", true, {nm .. " isn't holding an item!"})
                        return
                    end
                    local ok, res = pcall(function()
                        return Request:InvokeServer({"TakeHeldItem", { Location = { Type = ctx.where, BoxIndex = ctx.box, SlotIndex = ctx.index } }})
                    end)
                    if ok and res and res.Success and res.ItemName then
                        local nm = creature.Nickname or creature.Name or "this creature"
                        Say:Say("", true, {res.ItemName .. " was taken from " .. nm .. " and placed in your bag."})
                        -- clear locally for immediate feedback
                        creature.HeldItem = nil
                        setIconState(b, creature)
                    else
                        warn("[Vault] TakeHeldItem failed:", "ok=", ok, "res=", res and (res.Success and "Success" or tostring(res.Success)), res and res.ItemName)
                        Say:Say("", true, {"Unable to take item. Please try again later."})
                    end
                end,
                onDesync = function()
                    if not creature then return end
                    Say:Say("", false, {"Are you sure you want to Desync this creature? This will remove it from your data."})
                    local yes1 = Say:YieldChoice()
                    if yes1 ~= true then Say:Exit(); return end
                    Say:Say("", false, {"This action CANNOT be undone, are you sure?"})
                    local yes2 = Say:YieldChoice()
                    Say:Exit()
                    if yes2 == true then
                        local ok, res = pcall(function()
                            return Request:InvokeServer({"DesyncCreature", { Location = { Type = ctx.where, BoxIndex = ctx.box, SlotIndex = ctx.index } }})
                        end)
                        if ok and res == true then
                            -- remove locally
                            if ctx.where == "Box" then
                                table.remove(list, i)
                            else
                                local pd3 = ClientData:Get()
                                local party = _pendingParty or table.clone(pd3.Party or {})
                                table.remove(party, ctx.index)
                                _pendingParty = party
                            end
                            renderCurrentBox()
                            Vault:PopulateBoxList()
                            Vault:RenderParty()
                            Say:Say("", false, {"Creature successfully desynced."})
                        else
                            Say:Say("", true, {"Unable to desync creature. Please try again later."})
                        end
                    end
                end,
            }, ctx)
        end)
    end
end

function Vault:PopulateBoxList()
    local gui = getGui(); if not gui then return end
    local boxList = gui:FindFirstChild("BoxList")
    if not boxList then return end
    local entryTemplate = boxList:FindFirstChild("BoxTemplate")
    if not entryTemplate then return end

    clearChildrenExcept(boxList, { UIListLayout = true, BoxTemplate = true })

    local pd = ClientData:Get()
    local boxes = _pendingBoxesOrder or coalesceBoxes(pd)
    for i, entry in ipairs(boxes) do
        local e = entryTemplate:Clone()
        e.Visible = true
        e.Name = "Entry_" .. tostring(i)
        e.Parent = boxList
        local title = e:FindFirstChild("Title")
        if title and title:IsA("TextLabel") then
            title.Text = entry.Name or ("Box " .. tostring(i))
        end
        -- Apply box background to entry preview
        do
            local bgId = getBackgroundForBoxIndex(boxes, i)
            setBoxListEntryBackground(e, bgId)
        end
        local subBox = e:FindFirstChild("Box")
        if subBox then
            clearChildrenExcept(subBox, { UIGridLayout = true, UIAspectRatioConstraint = true, UIPadding = true })
            -- Use ImageLabel variant for BoxList tiles
            local boxTemplate = gui:FindFirstChild("BoxTemplate_IL")
            if not boxTemplate then
                -- Fallback guard: do nothing if IL template is missing
                return
            end
            for j = 1, 30 do
                local creature = (entry.Creatures or {})[j]
                local b = boxTemplate:Clone()
                b.Visible = true
                b.Name = "Mini_" .. tostring(j)
                b.Parent = subBox
                if creature then
                    setIconState(b, creature)
                else
                    clearAllChildren(b)
                end
                -- Ensure no click behavior in list
                if b:IsA("GuiButton") then
                    b.Active = false
                    b.AutoButtonColor = false
                end
                for _, d in ipairs(b:GetDescendants()) do
                    if d:IsA("GuiButton") then
                        d.Active = false
                        d.AutoButtonColor = false
                    end
                end
            end
        end
        -- Switch to this box when box area clicked
        local buttonArea = e:FindFirstChild("Box") or e
        if buttonArea and buttonArea:IsA("GuiObject") then
            buttonArea.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    _currentBoxIndex = i
                    renderCurrentBox()
                end
            end)
    end
end

function Vault:RenderParty()
    local gui = getGui(); if not gui then return end
    local partyRoot = gui:FindFirstChild("Party")
    if not partyRoot then return end
    -- Keep anchor frames named "1".."6" and layout helpers
    local keep = { UIGridLayout = true, UIAspectRatioConstraint = true, UIPadding = true }
    for i = 1, 6 do keep[tostring(i)] = true end
    clearChildrenExcept(partyRoot, keep)

    local pd = ClientData:Get()
    local party = _pendingParty or (pd and pd.Party) or {}
    local boxTemplate = gui:FindFirstChild("BoxTemplate")
    if not boxTemplate then return end
    for i = 1, 6 do
        local creature = party[i]
        local b = boxTemplate:Clone()
        b.Visible = true
        b.Name = "PartyBtn_" .. tostring(i)
        b.Parent = partyRoot
        -- Position to anchor frame
        local anchor = partyRoot:FindFirstChild(tostring(i))
        if anchor and anchor:IsA("GuiObject") then
            b.Position = anchor.Position
            b.AnchorPoint = anchor.AnchorPoint
            b.Size = anchor.Size
        end
        if creature then
            setIconState(b, creature)
        else
            clearAllChildren(b)
        end

        b.MouseButton1Click:Connect(function()
            local isEmpty = creature == nil
            if isEmpty and _swapState.from == nil then return end
            local ctx = { where = "Party", index = i, isEmpty = isEmpty }
            showCreatureOptions(b, {
                    onSwap = function()
                        if _swapState.from == nil then
                            _swapState.from = ctx
                            return
                        end
                        if _swapState.from.where == ctx.where and _swapState.from.index == ctx.index then
                            _swapState.from = nil
                            return
                        end
                        local from = _swapState.from
                        local to = ctx
                        _swapState.from = nil
                        local pd2 = ClientData:Get()
                        local boxes2 = _pendingBoxesOrder or coalesceBoxes(pd2)
                        local party2 = _pendingParty or table.clone(pd2.Party or {})
                        local function getRef(loc)
                            if loc.where == "Box" then
                                local box = boxes2[loc.box]
                                return box and box.Creatures, loc.index
                            else
                                return party2, loc.index
                            end
                        end
                        local listA, idxA = getRef(from)
                        local listB, idxB = getRef(to)
                        if listA and listB then
                            listA[idxA], listB[idxB] = listB[idxB], listA[idxA]
                            _pendingBoxesOrder = boxes2
                            _pendingParty = party2
                            renderCurrentBox()
                            Vault:PopulateBoxList()
                            Vault:RenderParty()
                        end
                    end,
                    onSummary = function()
                        if creature then Vault:ShowSummary(creature) end
                    end,
                    onTakeItem = function()
                        if not creature or not creature.HeldItem or creature.HeldItem == "" then
                            local nm = creature.Nickname or creature.Name or "This creature"
                            Say:Say("", true, {nm .. " isn't holding an item!"})
                            return
                        end
                        local ok, res = pcall(function()
                            return Request:InvokeServer({"TakeHeldItem", { Location = { Type = ctx.where, SlotIndex = ctx.index } }})
                        end)
                    if ok and res and res.Success and res.ItemName then
                            local nm = creature.Nickname or creature.Name or "this creature"
                            Say:Say("", true, {res.ItemName .. " was taken from " .. nm .. " and placed in your bag."})
                            creature.HeldItem = nil
                            setIconState(b, creature)
                        else
                        warn("[Vault] TakeHeldItem (party) failed:", "ok=", ok, "res=", res and (res.Success and "Success" or tostring(res.Success)), res and res.ItemName)
                            Say:Say("", true, {"Unable to take item. Please try again later."})
                        end
                    end,
                    onDesync = function()
                        if not creature then return end
                        Say:Say("", false, {"Are you sure you want to Desync this creature? This will remove it from your data."})
                        local yes1 = Say:YieldChoice()
                        if yes1 ~= true then Say:Exit(); return end
                        Say:Say("", false, {"This action CANNOT be undone, are you sure?"})
                        local yes2 = Say:YieldChoice()
                        Say:Exit()
                        if yes2 == true then
                            local ok, res = pcall(function()
                                return Request:InvokeServer({"DesyncCreature", { Location = { Type = ctx.where, SlotIndex = ctx.index } }})
                            end)
                            if ok and res == true then
                                local pd3 = ClientData:Get()
                                local party3 = _pendingParty or table.clone(pd3.Party or {})
                                table.remove(party3, ctx.index)
                                _pendingParty = party3
                                Vault:RenderParty()
                            else
                                Say:Say("", true, {"Unable to desync creature. Please try again later."})
                            end
                        end
                    end,
                }, ctx)
            end)
        end
    end
end

function Vault:ShowSummary(creatureData)
    local gui = getGui(); if not gui then return end
    local summary = gui:FindFirstChild("Summary"); if not summary then return end
    -- Hide main lists if present
    local middle = gui:FindFirstChild("Middle")
    if middle then middle.Visible = false end
    summary.Visible = true
    -- Delegate rendering to shared Summary UI
    SummaryUI:Render(summary, creatureData)

    -- Back button inside summary
    local closeBtn = summary:FindFirstChild("SummaryClose") or summary:FindFirstChild("Close")
    if closeBtn and closeBtn:IsA("TextButton") then
        closeBtn.MouseButton1Click:Connect(function()
            summary.Visible = false
            if middle then middle.Visible = true end
            local mi = summary:FindFirstChild("MoveInfo"); if mi then mi.Visible = false end
        end)
    end
end

local function snapshotBoxesForSave()
    local pd = ClientData:Get()
    local boxes = _pendingBoxesOrder or coalesceBoxes(pd)
    local outBoxes = {}
    for i, entry in ipairs(boxes) do
        outBoxes[i] = { Name = tostring(entry.Name or ("Box " .. tostring(i))), Creatures = clampToMax30(entry.Creatures or {}) }
    end
    return { Boxes = outBoxes }
end

function Vault:Open()
    local gui = getGui(); if not gui then return end
    _swapState.from = nil
    _pendingBoxesOrder = nil

    -- Initial render
    _currentBoxIndex = 1
    self:PopulateBoxList()
    renderCurrentBox()
    self:RenderParty()

    -- Ensure summary starts hidden every open
    do
        local summary = gui:FindFirstChild("Summary")
        local middle = gui:FindFirstChild("Middle")
        if summary then summary.Visible = false end
        if middle then middle.Visible = true end
        local mi = summary and summary:FindFirstChild("MoveInfo")
        if mi then mi.Visible = false end
    end

    -- Prevent player movement while Vault is open
    pcall(function()
        CharacterFunctions:SetSuppressed(true)
        CharacterFunctions:CanMove(false)
    end)

    -- Hide Vault UI until the flash fully covers the screen
    gui.Visible = false

    -- Play open SFX and screen flash
    pcall(function()
        local s = SFX and SFX:FindFirstChild("BootUp")
        if s and s:IsA("Sound") then s:Play() end
    end)
    playVaultFlash(true)

    -- Reveal Vault after flash covers the screen (matches first tween duration)
    task.delay(0.75, function()
        if gui and gui.Parent then
            gui.Visible = true
        end
    end)

    -- Wire close once
    if not gui:GetAttribute("ConnectionsMade") then
        gui:SetAttribute("ConnectionsMade", true)
        local closeBtn = gui:FindFirstChild("Close")
        if closeBtn and closeBtn:IsA("TextButton") then
            closeBtn.MouseButton1Click:Connect(function()
                -- play close sfx/flash
                pcall(function()
                    local s = SFX and SFX:FindFirstChild("ShutOff")
                    if s and s:IsA("Sound") then s:Play() end
                end)
                playVaultFlash(false)
                -- send pending ordering to server
                local payload = snapshotBoxesForSave()
                local pd = ClientData:Get()
                payload.Party = _pendingParty or (pd and pd.Party) or {}
                pcall(function()
                    Request:InvokeServer({"UpdateVaultBoxes", payload})
                end)
                -- Properly show TopBar via UI module API
                pcall(function()
                    local UI = require(script.Parent)
                    if UI and UI.TopBar and UI.TopBar.Show then
                        UI.TopBar:Show()
                    end
                end)
                -- Hide the Vault only after the flash has fully covered the screen
                task.delay(0.75, function()
                    if gui and gui.Parent then
                        gui.Visible = false
                        -- Also reset summary visibility so it won't persist next time
                        local summary = gui:FindFirstChild("Summary")
                        local middle = gui:FindFirstChild("Middle")
                        if summary then summary.Visible = false end
                        if middle then middle.Visible = true end
                        local mi = summary and summary:FindFirstChild("MoveInfo")
                        if mi then mi.Visible = false end
                        -- Re-enable movement now that Vault is fully closed
                        pcall(function()
                            CharacterFunctions:SetSuppressed(false)
                            CharacterFunctions:CanMove(true)
                        end)
                    end
                end)
            end)
        end
        -- Wire Middle.Settings (Box options)
        local middle = gui:FindFirstChild("Middle")
        local settingsBtn = middle and middle:FindFirstChild("Settings")
		if settingsBtn and settingsBtn:IsA("GuiButton") then
			UIFunctions:NewButton(settingsBtn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
				-- Open/Show BoxOptions overlay (single instance, toggled visible)
				local options = gui:FindFirstChild("BoxOptions_Active")
				if not options or not options:IsA("Frame") then
					local template = gui:FindFirstChild("BoxOptions") or gui:WaitForChild("BoxOptions")
					if not template then return end
					options = template:Clone()
					options.Name = "BoxOptions_Active"
					options.Parent = gui
				end
				-- Hide any CreatureOptions currently shown (mutual exclusivity)
				for _, b in ipairs(gui:GetDescendants()) do
					if b.Name == "CreatureOptions" and b:IsA("Frame") and b.Parent ~= gui then
						b:Destroy()
					end
				end
				options.Visible = true

				local function closeOptions()
					if options and options.Parent then options.Visible = false end
				end

                -- ChangeName
                do
                    local btn = options:FindFirstChild("ChangeName")
                    if btn and btn:IsA("GuiButton") then
                        UIFunctions:NewButton(btn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
                            closeOptions()
                            local NameInput = require(script.Parent:WaitForChild("NameInput"))
                            local newName = NameInput:Input(true)
                            if type(newName) == "string" and newName ~= "" then
                                local ok, success = pcall(function()
                                    return Request:InvokeServer({"RenameBox", { BoxIndex = _currentBoxIndex, Name = newName }})
                                end)
                                if ok and success == true then
                                    -- Refresh UI and optimistically set visible titles
                                    renderCurrentBox()
                                    Vault:PopulateBoxList()
                                    local gui2 = getGui()
                                    if gui2 then
                                        local middle2 = gui2:FindFirstChild("Middle")
                                        local title2 = middle2 and middle2:FindFirstChild("Title")
                                        if title2 and title2:IsA("TextLabel") then
                                            title2.Text = newName
                                        end
                                        local boxList = gui2:FindFirstChild("BoxList")
                                        if boxList then
                                            local entry = boxList:FindFirstChild("Entry_" .. tostring(_currentBoxIndex))
                                            local entryTitle = entry and entry:FindFirstChild("Title")
                                            if entryTitle and entryTitle:IsA("TextLabel") then
                                                entryTitle.Text = newName
                                            end
                                        end
                                    end
                                else
                                    Say:Say("", true, {"Unable to rename box. Please try again."})
                                end
                            end
                        end)
                    end
                end

                -- ChangeBG
                do
                    local btn = options:FindFirstChild("ChangeBG")
                    if btn and btn:IsA("GuiButton") then
                        UIFunctions:NewButton(btn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
                            -- Show ChangeBG menu
                            options.Visible = false
                            local changeBg = gui:FindFirstChild("ChangeBG") or gui:WaitForChild("ChangeBG")
                            if not changeBg then return end
                            changeBg.Visible = true

                            local listRoot = changeBg:FindFirstChild("BGList")
                            local contents = listRoot and listRoot:FindFirstChild("Contents")
                            local template = contents and contents:FindFirstChild("Template")
                            if not (contents and template and template:IsA("ImageButton")) then return end

                            -- Clear previous tiles (keep Template and layout helpers)
                            for _, child in ipairs(contents:GetChildren()) do
                                if child ~= template and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
                                    child:Destroy()
                                end
                            end

                            -- Populate with available backgrounds
                            for _, id in ipairs(BOX_BACKGROUNDS) do
                                local b = template:Clone()
                                b.Visible = true
                                b.Name = "BG_" .. tostring(id)
                                b.Image = "rbxassetid://" .. tostring(id)
                                b.Parent = contents
                                b.MouseButton1Click:Connect(function()
                                    -- Persist selection on server
                                    local ok, success = pcall(function()
                                        return Request:InvokeServer({"SetBoxBackground", { BoxIndex = _currentBoxIndex, Background = tostring(id) }})
                                    end)
                                    if ok and success == true then
                                        -- Update local snapshot and UI
                                        local pd5 = ClientData:Get()
                                        local boxes5 = _pendingBoxesOrder or coalesceBoxes(pd5)
                                        if boxes5[_currentBoxIndex] then
                                            (boxes5[_currentBoxIndex] :: any).Background = tostring(id)
                                            _pendingBoxesOrder = boxes5
                                        end
                                        -- Apply immediately to CurrentBox
                                        setCurrentBoxBackground((gui:FindFirstChild("Middle") and gui.Middle:FindFirstChild("CurrentBox")), tostring(id))
                                        -- Update BoxList entry preview
                                        do
                                            local boxList = gui:FindFirstChild("BoxList")
                                            local entry = boxList and boxList:FindFirstChild("Entry_" .. tostring(_currentBoxIndex))
                                            if entry then
                                                setBoxListEntryBackground(entry, tostring(id))
                                            end
                                        end
                                    else
                                        Say:Say("", true, {"Unable to change background. Please try again later."})
                                    end
                                    changeBg.Visible = false
                                end)
                            end

                            -- Click-off-to-dismiss for ChangeBG
                            local UIS = game:GetService("UserInputService")
                            local conn
                            conn = UIS.InputBegan:Connect(function(input, gameProcessed)
                                if gameProcessed then return end
                                if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                                task.defer(function()
                                    if not changeBg or not changeBg.Parent then if conn then conn:Disconnect() end return end
                                    -- If click outside the ChangeBG frame, hide it
                                    local mouse = LocalPlayer:GetMouse()
                                    local pos = Vector2.new(mouse.X, mouse.Y)
                                    local absPos = changeBg.AbsolutePosition
                                    local absSize = changeBg.AbsoluteSize
                                    local inside = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
                                    if not inside then
                                        changeBg.Visible = false
                                        if conn then conn:Disconnect() end
                                    end
                                end)
                            end)
                            changeBg.AncestryChanged:Connect(function()
                                if not changeBg:IsDescendantOf(gui) then
                                    if conn then conn:Disconnect() end
                                end
                            end)
                        end)
                    end
                end

                -- DesyncBox
                do
                    local btn = options:FindFirstChild("DesyncBox")
                    if btn and btn:IsA("GuiButton") then
                        UIFunctions:NewButton(btn, {"Action"}, {Click = "One", HoverOn = "One", HoverOff = "One"}, 0.25, function()
                            closeOptions()
                            Say:Say("", false, {"Are you sure you want to Desync this box? This will remove ALL creatures from this box."})
                            local yes1 = Say:YieldChoice()
                            if yes1 ~= true then Say:Exit(); return end
                            Say:Say("", false, {"This action CANNOT be undone, are you sure?"})
                            local yes2 = Say:YieldChoice()
                            Say:Exit()
                            if yes2 == true then
                                local ok, success = pcall(function()
                                    return Request:InvokeServer({"DesyncBox", { BoxIndex = _currentBoxIndex }})
                                end)
                                if ok and success == true then
                                    -- Update local snapshot so UI reflects emptiness immediately
                                    local pd4 = ClientData:Get()
                                    local boxes4 = _pendingBoxesOrder or coalesceBoxes(pd4)
                                    if boxes4[_currentBoxIndex] then
                                        boxes4[_currentBoxIndex].Creatures = {}
                                        _pendingBoxesOrder = boxes4
                                    end
                                    renderCurrentBox()
                                    Vault:PopulateBoxList()
                                    Vault:RenderParty()
                                    Say:Say("", true, {"Box successfully desynced."})
                                else
                                    Say:Say("", true, {"Unable to desync box. Please try again later."})
                                end
                            end
                        end)
                    end
                end

				-- Click-off-to-dismiss (like CreatureOptions) → hide instead of destroy
                local UIS = game:GetService("UserInputService")
                local conn
                conn = UIS.InputBegan:Connect(function(input, gameProcessed)
                    if gameProcessed then return end
                    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
                    task.defer(function()
						if not options or not options.Parent then if conn then conn:Disconnect() end return end
                        local mouse = LocalPlayer:GetMouse()
                        local pos = Vector2.new(mouse.X, mouse.Y)
                        local absPos = options.AbsolutePosition
                        local absSize = options.AbsoluteSize
                        local inside = pos.X >= absPos.X and pos.X <= absPos.X + absSize.X and pos.Y >= absPos.Y and pos.Y <= absPos.Y + absSize.Y
                        if not inside then
							closeOptions()
							if conn then conn:Disconnect() end
                        end
                    end)
                end)
				options.AncestryChanged:Connect(function()
					if not options:IsDescendantOf(gui) then
						if conn then conn:Disconnect() end
					end
				end)
            end)
        end
    end

end

return Vault



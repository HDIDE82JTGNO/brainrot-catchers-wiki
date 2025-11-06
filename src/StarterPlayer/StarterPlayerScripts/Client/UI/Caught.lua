local CaughtUI = {}

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Request = ReplicatedStorage:WaitForChild("Events"):WaitForChild("Request")

-- Avoid requiring parent UI to prevent circular dependency
local PartyUI = require(script.Parent:WaitForChild("Party"))
local Say = require(script.Parent.Parent.Utilities.Say)
local CreatureViewer = require(script.Parent:WaitForChild("CreatureViewer"))
local ClientData = require(script.Parent.Parent.Plugins.ClientData)
local MusicManager = require(script.Parent.Parent.Utilities.MusicManager)
local Creatures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Creatures"))
local TypesModule = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local function getGui()
    local player = game.Players.LocalPlayer
    if not player then return nil end
    local pg = player:FindFirstChild("PlayerGui")
    if not pg then return nil end
    local gameUi = pg:FindFirstChild("GameUI")
    if not gameUi then return nil end
    return gameUi:FindFirstChild("Caught")
end

-- Populate Info1 fields based on creatureData and base species
local function populateInfo1(CaughtGui: ScreenGui, creatureData)
    local Info1 = CaughtGui:WaitForChild("Info1")
    local icon = Info1:FindFirstChild("CreatureIcon")
    local nameLabel = Info1:FindFirstChild("CreatureName")
    local genderIcon = Info1:FindFirstChild("GenderIcon")
    local dexNumber = Info1:FindFirstChild("DexNumber")
    local creatureLevel = Info1:FindFirstChild("CreatureLevel")

    local base = Creatures[creatureData.Name]
    if icon and icon:IsA("ImageLabel") and base and base.Sprite then
        icon.Image = base.Sprite
    end
    if nameLabel and nameLabel:IsA("TextLabel") then
        nameLabel.Text = creatureData.Nickname or creatureData.Name
    end
    if genderIcon and genderIcon:IsA("ImageLabel") then
        if creatureData.Gender == 0 then
            genderIcon.ImageRectOffset = Vector2.new(510, 75)
        else
            genderIcon.ImageRectOffset = Vector2.new(0, 75)
        end
    end
    if dexNumber and dexNumber:IsA("TextLabel") and base and base.DexNumber then
        dexNumber.Text = "No. " .. tostring(base.DexNumber)
    end
    if creatureLevel and creatureLevel:IsA("TextLabel") then
        creatureLevel.Text = "Lv. " .. tostring(creatureData.Level)
    end
end

local function populateInfo2(CaughtGui: ScreenGui, creatureData)
    local Info2 = CaughtGui:WaitForChild("Info2")
    local base = Creatures[creatureData.Name]
    if not base then return end

    local FirstType = Info2:FindFirstChild("FirstType")
    local SecondType = Info2:FindFirstChild("SecondType")
    local SizeClass = Info2:FindFirstChild("SizeClass")
    local ActualWeight = Info2:FindFirstChild("ActualWeight")
    local ClassValue = Info2:FindFirstChild("ClassValue")
    local Description = Info2:FindFirstChild("Description")

    -- Types (match Party.lua behavior: color frames and text)
    local function setTypeFrame(frame: Instance?, typeName: string?)
        if not frame or not typeName or type(typeName) ~= "string" or typeName == "" then
            if frame and frame:IsA("Frame") then
                frame.Visible = (frame == FirstType) -- show first as placeholder, hide second
            end
            if frame and frame:IsA("TextLabel") then
                frame.Text = "-"
            end
            return
        end
        local typeData = TypesModule[typeName]
        if frame:IsA("Frame") then
            if typeData and typeData.uicolor then
                frame.BackgroundColor3 = typeData.uicolor
                local stroke = frame:FindFirstChild("UIStroke")
                if stroke then
                    local c = typeData.uicolor
                    stroke.Color = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
                end
            end
            local typeText = frame:FindFirstChild("TypeText")
            if typeText and typeText:IsA("TextLabel") then
                typeText.Text = typeName
				local ttStroke = typeText:FindFirstChild("UIStroke")
				if ttStroke and typeData and typeData.uicolor then
					local c = typeData.uicolor
					ttStroke.Color = Color3.new(math.max(0, c.R * 0.6), math.max(0, c.G * 0.6), math.max(0, c.B * 0.6))
				end
            end
            frame.Visible = true
        elseif frame:IsA("TextLabel") then
            frame.Text = typeName
        end
    end

    -- Determine types list from base.Type
    local typesList = {}
    if typeof(base.Type) == "table" then
        for i, t in ipairs(base.Type) do
            typesList[i] = typeof(t) == "string" and t or nil
        end
    elseif typeof(base.Type) == "string" then
        typesList[1] = base.Type
    end

    if FirstType then
        setTypeFrame(FirstType, typesList[1])
    end
    if SecondType then
        if typesList[2] then
            setTypeFrame(SecondType, typesList[2])
            SecondType.Visible = true
        else
            SecondType.Visible = false
        end
    end

    -- Size class and weight
    local baseWeight = base.BaseWeightKg
    local weight = creatureData.WeightKg or baseWeight
    local sizeClass = "?"
    if type(weight) == "number" and type(baseWeight) == "number" and baseWeight > 0 then
        local delta = (weight - baseWeight) / baseWeight
        if delta <= -0.3 then sizeClass = "XS"
        elseif delta <= -0.1 then sizeClass = "S"
        elseif delta < 0.1 then sizeClass = "M"
        elseif delta < 0.3 then sizeClass = "L"
        else sizeClass = "XL" end
    end
    if SizeClass and SizeClass:IsA("TextLabel") then
        SizeClass.Text = sizeClass
    end
    if ActualWeight and ActualWeight:IsA("TextLabel") then
        ActualWeight.Text = type(weight) == "number" and (tostring(weight) .. "KG") or "--"
    end

    if ClassValue and ClassValue:IsA("TextLabel") then
        ClassValue.Text = tostring(base.Class or "Basic")
    end
    if Description and Description:IsA("TextLabel") then
        Description.Text = tostring(base.Description or "")
    end
end

-- Public: Show the caught screen for a given creature instance (CreatureInstance)
function CaughtUI:Show(creatureData)
    local gui = getGui()
    if not gui then return end

    gui.Visible = true
    -- Ensure panels start hidden
    local Info1 = gui:WaitForChild("Info1")
    local Info2 = gui:WaitForChild("Info2")
    Info1.Visible = false
    Info2.Visible = false

    -- Setup 3D preview container position as specified
    local preview = gui:WaitForChild("3DPreview")
    preview.Position = UDim2.new(0.5, 0, 0.6, 0)

    -- Load 3D model
    CreatureViewer:Load(preview, {
        Name = creatureData.Name,
        BaseName = creatureData.Name,
        Shiny = creatureData.Shiny,
    })

    -- Dex registration narration (wait for user proceed)
    Say:Say("", true, { (creatureData.Name .. "'s data has been added to the database!") })

    -- Tween preview and show Info1
    TweenService:Create(preview, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.26, 0, 0.5, 0)
    }):Play()

    Info1.Visible = true
    populateInfo1(gui, creatureData)

    -- Show and populate Info2
    Info2.Visible = true
    populateInfo2(gui, creatureData)

    -- Wait for an additional click/step before nickname prompt
    Say:Say("", true, {
        "" -- blank step
    })
    -- Move preview back to center after blank step
    TweenService:Create(preview, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0.6, 0)
    }):Play()
  
    Info1.Visible = false
    Info2.Visible = false

    -- Step 2: Nickname prompt (keep Say UI visible for choices)
    local display = creatureData.Name
    Say:Say("", false, {"Would you like to give " .. creatureData.Name .. " a nickname?"})
    local wantsNickname = Say:YieldChoice() -- reuse Yes/No for now
    Say:Exit()
    if wantsNickname == true then
        -- Reuse name input UI from ChunkEvents sequence
        local player = game.Players.LocalPlayer
        local pg = player.PlayerGui
        local gameUi = pg:WaitForChild("GameUI")
        local InputName = gameUi:WaitForChild("InputName")
        InputName.Visible = true

        local NameConfirmed = false
        local Nick = ""
        local function isValidNickname(n)
            if type(n) ~= "string" then return false end
            if #n < 1 or #n > 12 then return false end
            -- Allow letters (any case), digits, spaces, and symbols ' - . ! ?
            -- Using %a for letters to avoid forcing uppercase only
            if not n:match("^[%a0-9 '%-%.%!%?]+$") then return false end
            return true
        end
        local function onDone()
            local field = InputName.Input.InputField
            local txt = field.Text
            if isValidNickname(txt) then
                -- Server profanity filter
                local ok, filtered = pcall(function()
                    return Request:InvokeServer({"FilterName", txt})
                end)
                Nick = (ok and filtered) or txt
                NameConfirmed = true
                InputName.Visible = false
            else
                Say:Say("", true, {"Name must be 1-12 chars, letters/numbers and ' - . ! ?"})
            end
        end
        local function onNo()
            InputName.Visible = false
        end
        local c1 = InputName.Done.MouseButton1Click:Connect(onDone)
        local c2 = InputName.No.MouseButton1Click:Connect(onNo)
        repeat task.wait() until not InputName.Visible or NameConfirmed
        if c1.Connected then c1:Disconnect() end
        if c2.Connected then c2:Disconnect() end
        if NameConfirmed and #Nick > 0 then
            creatureData.Nickname = Nick
            display = Nick
        end
    end

    -- Step 3: Destination prompt with custom options (keep Say UI visible)
    Say:Say("", false, {"Where do you want to send " .. display .. " to?"})
    -- Build custom options using Say.Choice.Template system
    local SayUI = game.Players.LocalPlayer.PlayerGui.GameUI.Say
    local Choice = SayUI:WaitForChild("Choice")
    local YesBtn = Choice:WaitForChild("Yes")
    local NoBtn = Choice:WaitForChild("No")
    local Template = Choice:WaitForChild("Template")
    local Layout = Choice:WaitForChild("UIListLayout")

    -- Hide default Yes/No
    YesBtn.Visible = false
    NoBtn.Visible = false

    -- Create options
    local options = {
        { Name = "Add to your party", Key = "party" },
        { Name = "Send to a box", Key = "box" },
    }
    local selectedKey = nil
    local clones = {}
    for _, opt in ipairs(options) do
        local b = Template:Clone()
        b.Name = "Opt_" .. opt.Key
        b.Visible = true
        b.Parent = Choice
        local label = b:FindFirstChild("Label")
        if label and label:IsA("TextLabel") then
            label.Text = opt.Name
        end
        b.MouseButton1Click:Connect(function()
            selectedKey = opt.Key
        end)
        table.insert(clones, b)
    end

    SayUI.Visible = true
    Choice.Visible = true
    repeat task.wait() until selectedKey ~= nil
    Choice.Visible = false
    Say:Exit()

    -- Cleanup: restore original hierarchy ordering (Layout, No, Yes, Template)
    for _, b in ipairs(clones) do b:Destroy() end
    YesBtn.Visible = true
    NoBtn.Visible = true

    if selectedKey == "party" then
        -- Check party capacity and add or prompt swap
        local data = ClientData:Get()
        local party = (data and data.Party) or {}
        if #party >= 6 then
            -- Open Party UI to swap (reuse existing party module)
            PartyUI:Open("Battle")
            -- For now, cancel returns to the same prompt (not implemented fully)
            Say:Say("", true, {"Party is full. Swap via Party UI or cancel to choose again."})
        else
            -- Server: finalize capture into party
            local ok = Request:InvokeServer({"FinalizeCapture", {Nickname = creatureData.Nickname, Destination = "Party"}})
            if ok then
                Say:Say("", true, {display .. " was added to your party."})
            else
                Say:Say("", true, {"Failed to add to party. Try sending to a box."})
            end
        end
    elseif selectedKey == "box" then
        -- Server: finalize capture into box
        local ok = Request:InvokeServer({"FinalizeCapture", {Nickname = creatureData.Nickname, Destination = "Box"}})
        if ok then
            Say:Say("", true, {display .. " was sent to a box."})
        else
            Say:Say("", true, {"Failed to send to a box. Please try again."})
        end
    end

    -- Step 4: Cleanup with blackout transition
    local pg = game.Players.LocalPlayer:WaitForChild("PlayerGui")
    local gameUi = pg:WaitForChild("GameUI")
    local Blackout = gameUi:WaitForChild("Blackout")
    -- Fade in blackout
    Blackout.Visible = true
    Blackout.BackgroundTransparency = 1
    TweenService:Create(Blackout, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        BackgroundTransparency = 0
    }):Play()
    task.wait(0.32)
    -- Hide Caught UI while black
    gui.Visible = false
    -- Fade out blackout back to normal gameplay and restore TopBar early
    -- Restore TopBar using module API (consistent with other modules), but avoid blocking on require
    local UI = nil
    local ok, mod = pcall(function()
        return require(script.Parent) -- UI/init.lua returns the UI instance table
    end)
    if ok then UI = mod end
    if UI and UI.TopBar and UI.TopBar.SetSuppressed and UI.TopBar.Show then
        UI.TopBar:SetSuppressed(false)
        UI.TopBar:Show()
    else
        warn("UNABLE TO SHOW TOPBAR!")
    end
    TweenService:Create(Blackout, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
        BackgroundTransparency = 1
    }):Play()
    task.delay(0.32, function()
        Blackout.Visible = false
        -- End victory music and resume chunk music after summary completes
        pcall(function()
            MusicManager:EndVictory()
            -- Defer chunk music to MusicManager:EndEncounterMusic guard; do not call SetChunkMusic here
        end)
    end)
end

return CaughtUI



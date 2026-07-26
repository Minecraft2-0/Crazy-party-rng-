        local half = size / 2
        local corners = {}
        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                for z = -1, 1, 2 do
                    local offset = Vector3.new(half.X * x, half.Y * y, half.Z * z)
                    table.insert(corners, (cframe * CFrame.new(offset)).Position)
                end
            end
        end
        return corners
    end
end

-- Create a bounding box object for a mob
local function createBox(mob)
    local boxData = {}

    -- 4 lines for the rectangle
    boxData.OutlineTop    = Drawing.new("Line")
    boxData.OutlineBottom = Drawing.new("Line")
    boxData.OutlineLeft   = Drawing.new("Line")
    boxData.OutlineRight  = Drawing.new("Line")

    for _, line in ipairs({boxData.OutlineTop, boxData.OutlineBottom, boxData.OutlineLeft, boxData.OutlineRight}) do
        line.Color = Color3.fromRGB(255, 255, 255)
        line.Thickness = 2
        line.Transparency = 1
        line.Visible = false
    end

    -- HP bar (we’ll draw it as a separate vertical line or rectangle)
    boxData.HPBar = Drawing.new("Line")
    boxData.HPBar.Thickness = 3
    boxData.HPBar.Color = Color3.fromRGB(0, 255, 0)
    boxData.HPBar.Transparency = 1
    boxData.HPBar.Visible = false

    -- Text label for name + distance
    boxData.Label = Drawing.new("Text")
    boxData.Label.Center = true
    boxData.Label.Outline = true
    boxData.Label.Font = 2  -- 0=UI,1=System,2=Plex,3=Monospace
    boxData.Label.Size = 13
    boxData.Label.Color = Color3.fromRGB(255, 255, 255)
    boxData.Label.Text = ""
    boxData.Label.Visible = false

    MobESPBoxes[mob] = boxData
end

-- Remove bounding box objects for a mob
local function removeBox(mob)
    local boxData = MobESPBoxes[mob]
    if boxData then
        for _, obj in pairs(boxData) do
            obj:Remove() -- remove the Drawing object
        end
        MobESPBoxes[mob] = nil
    end
end

-- Update bounding box for a mob
local function updateBox(mob, dist)
    local boxData = MobESPBoxes[mob]
    if not boxData then
        createBox(mob)
        boxData = MobESPBoxes[mob]
    end

    local hrp = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Head")
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then
        -- Not a valid mob, remove if needed
        removeBox(mob)
        return
    end

    local corners = getModelCorners(mob)
    if #corners == 0 then
        removeBox(mob)
        return
    end

    -- Project corners to 2D, find minX,minY and maxX,maxY
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    local onScreen = false
    for _, corner in ipairs(corners) do
        local screenPos = worldToViewport(corner)
        if screenPos then
            onScreen = true
            local x, y = screenPos.X, screenPos.Y
            if x < minX then minX = x end
            if y < minY then minY = y end
            if x > maxX then maxX = x end
            if y > maxY then maxY = y end
        end
    end

    -- If none of the corners are on-screen, hide the box
    if not onScreen then
        for _, obj in pairs(boxData) do
            obj.Visible = false
        end
        return
    end

    -- Box corners in screen space
    local boxWidth = maxX - minX
    local boxHeight = maxY - minY

    -- Make sure we have a minimum box size
    if boxWidth < 2 or boxHeight < 2 then
        for _, obj in pairs(boxData) do
            obj.Visible = false
        end
        return
    end

    -- Position the lines
    boxData.OutlineTop.Visible = true
    boxData.OutlineTop.From = Vector2.new(minX, minY)
    boxData.OutlineTop.To   = Vector2.new(maxX, minY)

    boxData.OutlineBottom.Visible = true
    boxData.OutlineBottom.From = Vector2.new(minX, maxY)
    boxData.OutlineBottom.To   = Vector2.new(maxX, maxY)

    boxData.OutlineLeft.Visible = true
    boxData.OutlineLeft.From = Vector2.new(minX, minY)
    boxData.OutlineLeft.To   = Vector2.new(minX, maxY)

    boxData.OutlineRight.Visible = true
    boxData.OutlineRight.From = Vector2.new(maxX, minY)
    boxData.OutlineRight.To   = Vector2.new(maxX, maxY)

    -- HP bar on the left side
    local hpPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
    local barHeight = boxHeight * hpPercent
    boxData.HPBar.Visible = true
    boxData.HPBar.From = Vector2.new(minX - 4, maxY)     -- bottom
    boxData.HPBar.To   = Vector2.new(minX - 4, maxY - barHeight) -- top
    boxData.HPBar.Color = Color3.fromRGB(0, 255, 0)

    -- Label for name + distance, placed above the top
    boxData.Label.Visible = true
    boxData.Label.Text = string.format("%s  %.0fm", mob.Name, dist)
    boxData.Label.Position = Vector2.new((minX + maxX)/2, minY - 16)
end

-- Heartbeat update for bounding boxes
local function updateBoundingBoxes()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        -- Hide all boxes if local player not ready
        for mob, boxData in pairs(MobESPBoxes) do
            for _, obj in pairs(boxData) do
                obj.Visible = false
            end
        end
        return
    end

    local playerPos = LocalPlayer.Character.HumanoidRootPart.Position

    -- First, gather valid mobs
    local validMobs = {}
    for _, mob in ipairs(Workspace.Mobs:GetChildren()) do
        local hrp = mob:FindFirstChild("HumanoidRootPart")
                    or mob:FindFirstChild("Head")
                    or mob:FindFirstChild("Torso")
        if hrp then
            local dist = (playerPos - hrp.Position).Magnitude
            if ESPConfig.Enabled and dist <= ESPConfig.MaxDistance then
                validMobs[mob] = dist
            end
        end
    end

    -- Update or create boxes for valid mobs
    for mob, dist in pairs(validMobs) do
        updateBox(mob, dist)
    end

    -- Remove or hide boxes for any that are not valid
    for mob, _ in pairs(MobESPBoxes) do
        if not validMobs[mob] then
            removeBox(mob)
        end
    end
end

table.insert(Connections, RunService.RenderStepped:Connect(function()
    if ESPConfig.Enabled then
        updateBoundingBoxes()
    else
        -- If ESP is off, hide or remove all boxes
        for mob, _ in pairs(MobESPBoxes) do
            removeBox(mob)
        end
    end
end))

---------------------
-- UI Creation
---------------------
local UI = {}

function UI.enableDrag(frame)
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    local function update(input)
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then update(input) end
    end)
end

function UI.createMainGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "KillAuraGUI"
    screenGui.Parent = PlayerGui
    screenGui.ResetOnSpawn = false

    local mainFrame = Instance.new("Frame")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 220, 0, 240)
    mainFrame.Position = UDim2.new(0.4, 0, 0.3, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(0, 255, 0)
    stroke.Parent = mainFrame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = mainFrame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = mainFrame

    UI.enableDrag(mainFrame)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 25)
    title.BackgroundTransparency = 1
    title.Text = "Crazy Party RPG"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.AnchorPoint = Vector2.new(0.5, 0)
    title.Position = UDim2.new(0.5, 0, 0, 0)
    title.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = mainFrame

    local function createToggleRow(name, labelText, order, toggleCallback)
        local rowFrame = Instance.new("Frame")
        rowFrame.Name = name
        rowFrame.Size = UDim2.new(1, 0, 0, 25)
        rowFrame.BackgroundTransparency = 1
        rowFrame.LayoutOrder = order
        rowFrame.Parent = mainFrame

        local label = Instance.new("TextLabel")
        label.Name = name.."Label"
        label.Size = UDim2.new(1, -70, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.Gotham
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = rowFrame

        local button = Instance.new("TextButton")
        button.Name = name.."Button"
        button.Size = UDim2.new(0, 60, 1, 0)
        button.Position = UDim2.new(1, -60, 0, 0)
        button.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.Gotham
        button.TextSize = 14
        button.Text = "OFF"
        button.Parent = rowFrame

        local function setState(isOn)
            if isOn then
                TweenService:Create(button, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(0, 180, 0) }):Play()
                button.Text = "ON"
            else
                TweenService:Create(button, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(120, 0, 0) }):Play()
                button.Text = "OFF"
            end
        end

        button.MouseButton1Click:Connect(function()
            toggleCallback(setState)
        end)
    end

    local function createCycleRow(name, labelText, order, options, cycleCallback)
        local rowFrame = Instance.new("Frame")
        rowFrame.Name = name
        rowFrame.Size = UDim2.new(1, 0, 0, 25)
        rowFrame.BackgroundTransparency = 1
        rowFrame.LayoutOrder = order
        rowFrame.Parent = mainFrame

        local label = Instance.new("TextLabel")
        label.Name = name.."Label"
        label.Size = UDim2.new(1, -70, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = labelText .. ": " .. options[1]
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.Gotham
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = rowFrame

        local button = Instance.new("TextButton")
        button.Name = name.."Button"
        button.Size = UDim2.new(0, 60, 1, 0)
        button.Position = UDim2.new(1, -60, 0, 0)
        button.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.Gotham
        button.TextSize = 14
        button.Text = options[1]
        button.Parent = rowFrame

        local currentIndex = 1
        button.MouseButton1Click:Connect(function()
            currentIndex = currentIndex % #options + 1
            local newOption = options[currentIndex]
            button.Text = newOption
            label.Text = labelText .. ": " .. newOption
            cycleCallback(newOption)
        end)
    end

    createToggleRow("CamTrack", "Cam Track", 1, function(setState)
        State.TrackEnabled = not State.TrackEnabled
        setState(State.TrackEnabled)
    end)

    createToggleRow("KillAuraToggle", "Kill Aura", 2, function(setState)
        State.Enabled = not State.Enabled
        setState(State.Enabled)
        if not State.Enabled then State.LastAttack = 0 end
    end)

    createToggleRow("ESPToggle", "ESP", 3, function(setState)
        ESPConfig.Enabled = not ESPConfig.Enabled
        setState(ESPConfig.Enabled)
        -- If turned off, remove all boxes immediately
        if not ESPConfig.Enabled then
            for mob, _ in pairs(MobESPBoxes) do
                removeBox(mob)
            end
        end
    end)

    createCycleRow("TargetMode", "Target Mode", 4, {"distance", "health"}, function(newOption)
        Config.TargetingMode = newOption
    end)

    local distanceLabel = Instance.new("TextLabel")
    distanceLabel.Name = "DistanceLabel"
    distanceLabel.Size = UDim2.new(1, 0, 0, 20)
    distanceLabel.BackgroundTransparency = 1
    distanceLabel.Text = "Distance: " .. ESPConfig.MaxDistance
    distanceLabel.TextColor3 = Color3.new(1, 1, 1)
    distanceLabel.Font = Enum.Font.Gotham
    distanceLabel.TextSize = 14
    distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
    distanceLabel.LayoutOrder = 5
    distanceLabel.Parent = mainFrame

    local sliderRow = Instance.new("Frame")
    sliderRow.Name = "SliderRow"
    sliderRow.Size = UDim2.new(1, 0, 0, 10)
    sliderRow.BackgroundTransparency = 1
    sliderRow.LayoutOrder = 6
    sliderRow.Parent = mainFrame

    local sliderBG = Instance.new("Frame")
    sliderBG.Name = "SliderBG"
    sliderBG.Size = UDim2.new(1, 0, 1, 0)
    sliderBG.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    sliderBG.BorderSizePixel = 0
    sliderBG.Parent = sliderRow

    local sliderFill = Instance.new("Frame")
    sliderFill.Name = "SliderFill"
    sliderFill.Size = UDim2.new((ESPConfig.MaxDistance - 100) / 900, 0, 1, 0)
    sliderFill.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
    sliderFill.BorderSizePixel = 0
    sliderFill.Parent = sliderBG

    local sliderKnob = Instance.new("TextButton")
    sliderKnob.Name = "SliderKnob"
    sliderKnob.Size = UDim2.new(0, 12, 1, 0)
    sliderKnob.Position = UDim2.new((ESPConfig.MaxDistance - 100) / 900, -6, 0, 0)
    sliderKnob.BackgroundColor3 = Color3.new(1, 1, 1)
    sliderKnob.BorderSizePixel = 0
    sliderKnob.Text = ""
    sliderKnob.Parent = sliderBG

    local draggingSlider = false
    local function updateSlider(mouseX)
        local absPos = sliderBG.AbsolutePosition.X
        local relX = math.clamp(mouseX - absPos, 0, sliderBG.AbsoluteSize.X)
        local pct = relX / sliderBG.AbsoluteSize.X
        ESPConfig.MaxDistance = math.floor(100 + pct * 900)
        sliderFill.Size = UDim2.new(pct, 0, 1, 0)
        sliderKnob.Position = UDim2.new(pct, -6, 0, 0)
        distanceLabel.Text = "Distance: " .. ESPConfig.MaxDistance
    end

    sliderKnob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = true
        end
    end)
    sliderKnob.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlider(input.Position.X)
        end
    end)

    return screenGui
end

local mainGui = UI.createMainGUI()

local function showNotification(screenGui)
    local notifFrame = Instance.new("Frame")
    notifFrame.Name = "NotificationFrame"
    notifFrame.Size = UDim2.new(0, 300, 0, 70)
    notifFrame.Position = UDim2.new(1, -10, 0, 10)
    notifFrame.AnchorPoint = Vector2.new(1, 0)
    notifFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    notifFrame.BorderSizePixel = 0
    notifFrame.ZIndex = 10
    notifFrame.Parent = screenGui

    local notifCorner = Instance.new("UICorner")
    notifCorner.CornerRadius = UDim.new(0, 8)
    notifCorner.Parent = notifFrame

    local mainLabel = Instance.new("TextLabel")
    mainLabel.Name = "NotificationLabel"
    mainLabel.Size = UDim2.new(1, -10, 0.6, 0)
    mainLabel.Position = UDim2.new(0, 5, 0, 0)
    mainLabel.BackgroundTransparency = 1
    mainLabel.Text = "Executed Successfully..."
    mainLabel.Font = Enum.Font.GothamBold
    mainLabel.TextSize = 18
    mainLabel.TextColor3 = Color3.new(1, 1, 1)
    mainLabel.ZIndex = 11
    mainLabel.Parent = notifFrame

    local closingLabel = Instance.new("TextLabel")
    closingLabel.Name = "ClosingLabel"
    closingLabel.Size = UDim2.new(1, -10, 0.4, 0)
    closingLabel.Position = UDim2.new(0, 5, 0.6, 0)
    closingLabel.BackgroundTransparency = 1
    closingLabel.Text = "Closing in 5 Seconds"
    closingLabel.Font = Enum.Font.Gotham
    closingLabel.TextSize = 16
    closingLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    closingLabel.ZIndex = 11
    closingLabel.Parent = notifFrame

    notifFrame.Size = UDim2.new(0, 0, 0, 0)
    local tweenIn = TweenService:Create(notifFrame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0, 300, 0, 70) })
    tweenIn:Play()
    tweenIn.Completed:Wait()

    task.wait(5)

    local tweenOut = TweenService:Create(notifFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(0, 0, 0, 0) })
    tweenOut:Play()
    tweenOut.Completed:Wait()
    notifFrame:Destroy()
end

showNotification(mainGui)

-------------------------------------
-- Debug & Quick Toggle Functionality
-------------------------------------
local function dumpState()
    print("--------- KillAura State Dump ---------")
    print("KillAura Enabled: " .. tostring(State.Enabled))
    print("Camera Track Enabled: " .. tostring(State.TrackEnabled))
    print("Weapon: " .. State.Weapon)
    if State.HumanoidRootPart then
        print("HRP Position: " .. tostring(State.HumanoidRootPart.Position))
    else
        print("HRP: nil")
    end
    print("Last Attack Time: " .. State.LastAttack)
    print("ESP Enabled: " .. tostring(ESPConfig.Enabled))
    print("ESP Max Distance: " .. ESPConfig.MaxDistance)
    print("Targeting Mode: " .. Config.TargetingMode)
    print("Debug Log:")
    for i, log in ipairs(State.DebugLog) do
        print(i, log)
    end
    print("---------------------------------------")
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed then
        if input.KeyCode == Enum.KeyCode.V then
            dumpState()
        end
        if input.KeyCode == Enum.KeyCode.X then
            State.Enabled = not State.Enabled
            local toggleRow = mainGui.MainFrame:FindFirstChild("KillAuraToggle")
            if toggleRow then
                local button = toggleRow:FindFirstChild("KillAuraToggleButton")
                if button then
                    if State.Enabled then
                        TweenService:Create(button, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(0, 180, 0) }):Play()
                        button.Text = "ON"
                    else
                        TweenService:Create(button, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(120, 0, 0) }):Play()
                        button.Text = "OFF"
                    end
                end
            end
        end
    end
end)

---------------------

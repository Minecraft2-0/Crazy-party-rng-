

-- Services
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local UserInputService= game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace       = game:GetService("Workspace")
local Camera          = Workspace.CurrentCamera

local LocalPlayer     = Players.LocalPlayer
local PlayerGui       = LocalPlayer:WaitForChild("PlayerGui")

-- Global cleanup check (ensuring a single instance)
if _G.KillAuraCleanup then
    _G.KillAuraCleanup()
end
local existingGUI = PlayerGui:FindFirstChild("KillAuraGUI")
if existingGUI then
    existingGUI:Destroy()
end

-- Config and State
local Config = {
    MAX_RANGE         = 20,    -- Range for target detection
    COOLDOWN          = 0.2,   -- Time between attacks
    TRACK_LERP_SPEED  = 0.1,   -- Camera tracking lerp speed
    DEBUG_MODE        = false,
    TargetingMode     = "distance",
}
local ESPConfig = {
    Enabled     = false,
    MaxDistance = 500,
}
local State = {
    Enabled         = false,
    TrackEnabled    = false,
    Weapon          = "Unarmed",
    HumanoidRootPart= nil,
    LastAttack      = 0,
    DebugLog        = {},
}

-- Fly variables
local nowe = false
local speeds = 1
local tpwalking = false

local DamageEvent = ReplicatedStorage:WaitForChild("GameContents"):WaitForChild("Remotes"):WaitForChild("DamageEvent")
local Connections = {}

local function debugLog(msg)
    if Config.DEBUG_MODE then
        print("[KillAura DEBUG]: " .. msg)
        table.insert(State.DebugLog, msg)
    end
end

------------------------------------------
-- Target Acquisition & Damage Processing
------------------------------------------
local function getSortedTargets()
    local targets = {}
    if not State.HumanoidRootPart then return targets end
    local playerPos = State.HumanoidRootPart.Position

    for _, mob in ipairs(Workspace.Mobs:GetChildren()) do
        local targetPart = mob:FindFirstChild("HumanoidRootPart")
                        or mob:FindFirstChild("Head")
                        or mob:FindFirstChild("Torso")
        if targetPart then
            local distance = (playerPos - targetPart.Position).Magnitude
            if distance <= Config.MAX_RANGE then
                table.insert(targets, { mob = mob, part = targetPart, distance = distance })
            end
        end
    end

    if Config.TargetingMode == "health" then
        table.sort(targets, function(a, b)
            local humanoidA = a.mob:FindFirstChildOfClass("Humanoid")
            local humanoidB = b.mob:FindFirstChildOfClass("Humanoid")
            if humanoidA and humanoidB then
                return humanoidA.Health < humanoidB.Health
            else
                return a.distance < b.distance
            end
        end)
    else
        table.sort(targets, function(a, b) return a.distance < b.distance end)
    end

    return targets
end

local function processDamage()
    if not State.Enabled or not State.HumanoidRootPart then return end
    local now = os.clock()
    if now - State.LastAttack < Config.COOLDOWN then return end

    local targets = getSortedTargets()
    if #targets > 0 then
        local nearest = targets[1]
        DamageEvent:FireServer(nearest.part, State.Weapon)
        State.LastAttack = now
    end
end

local function updateWeapon(character)
    local tool = character:FindFirstChildOfClass("Tool")
    State.Weapon = tool and tool.Name or "Unarmed"
end

local function onCharacterAdded(character)
    State.HumanoidRootPart = character:WaitForChild("HumanoidRootPart")
    
    character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then updateWeapon(character) end
    end)
    character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then updateWeapon(character) end
    end)
    updateWeapon(character)
end

if LocalPlayer.Character then
    task.spawn(onCharacterAdded, LocalPlayer.Character)
end
table.insert(Connections, LocalPlayer.CharacterAdded:Connect(onCharacterAdded))
table.insert(Connections, RunService.Heartbeat:Connect(processDamage))

---------------------
-- Camera Tracking
---------------------
local function trackTarget()
    if not State.TrackEnabled or not State.HumanoidRootPart then return end
    local targets = getSortedTargets()
    if #targets > 0 then
        local nearest = targets[1]
        local camPos = Camera.CFrame.Position
        local desiredCFrame = CFrame.new(camPos, nearest.part.Position)
        Camera.CFrame = Camera.CFrame:Lerp(desiredCFrame, Config.TRACK_LERP_SPEED)
    end
end
table.insert(Connections, RunService.RenderStepped:Connect(trackTarget))

--------------------------------------------------------------------------------
-- BOUNDING BOX ESP
--------------------------------------------------------------------------------
local MobESPBoxes = {}

local function worldToViewport(pos)
    local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
    if onScreen then
        return Vector2.new(screenPos.X, screenPos.Y)
    end
    return nil
end

local function getModelCorners(model)
    if not model.PrimaryPart then
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        if not root then return {} end
        local size = root.Size * 1.25
        local cframe = root.CFrame
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
    else
        local cframe, size = model:GetBoundingBox()
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

local function createBox(mob)
    local boxData = {}
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

    boxData.HPBar = Drawing.new("Line")
    boxData.HPBar.Thickness = 3
    boxData.HPBar.Color = Color3.fromRGB(0, 255, 0)
    boxData.HPBar.Transparency = 1
    boxData.HPBar.Visible = false

    boxData.Label = Drawing.new("Text")
    boxData.Label.Center = true
    boxData.Label.Outline = true
    boxData.Label.Font = 2
    boxData.Label.Size = 13
    boxData.Label.Color = Color3.fromRGB(255, 255, 255)
    boxData.Label.Text = ""
    boxData.Label.Visible = false

    MobESPBoxes[mob] = boxData
end

local function removeBox(mob)
    local boxData = MobESPBoxes[mob]
    if boxData then
        for _, obj in pairs(boxData) do
            obj:Remove()
        end
        MobESPBoxes[mob] = nil
    end
end

local function updateBox(mob, dist)
    local boxData = MobESPBoxes[mob]
    if not boxData then
        createBox(mob)
        boxData = MobESPBoxes[mob]
    end

    local hrp = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Head")
    local humanoid = mob:FindFirstChildOfClass("Humanoid")
    if not hrp or not humanoid then
        removeBox(mob)
        return
    end

    local corners = getModelCorners(mob)
    if #corners == 0 then
        removeBox(mob)
        return
    end

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

    if not onScreen then
        for _, obj in pairs(boxData) do
            obj.Visible = false
        end
        return
    end

    local boxWidth = maxX - minX
    local boxHeight = maxY - minY

    if boxWidth < 2 or boxHeight < 2 then
        for _, obj in pairs(boxData) do
            obj.Visible = false
        end
        return
    end

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

    local hpPercent = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
    local barHeight = boxHeight * hpPercent
    boxData.HPBar.Visible = true
    boxData.HPBar.From = Vector2.new(minX - 4, maxY)
    boxData.HPBar.To   = Vector2.new(minX - 4, maxY - barHeight)
    boxData.HPBar.Color = Color3.fromRGB(0, 255, 0)

    boxData.Label.Visible = true
    boxData.Label.Text = string.format("%s  %.0fm", mob.Name, dist)
    boxData.Label.Position = Vector2.new((minX + maxX)/2, minY - 16)
end

local function updateBoundingBoxes()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        for mob, boxData in pairs(MobESPBoxes) do
            for _, obj in pairs(boxData) do
                obj.Visible = false
            end
        end
        return
    end

    local playerPos = LocalPlayer.Character.HumanoidRootPart.Position
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

    for mob, dist in pairs(validMobs) do
        updateBox(mob, dist)
    end

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
    mainFrame.Size = UDim2.new(0, 220, 0, 310) -- Увеличили высоту под кнопку флая и ползунок
    mainFrame.Position = UDim2.new(0.4, 0, 0.3, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(35, 15, 55) -- Тёмно-фиолетовый фон
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(255, 0, 0)
    stroke.Parent = mainFrame

    -- RGB эффект для обводки
    RunService.RenderStepped:Connect(function()
        local hue = tick() % 5 / 5
        stroke.Color = Color3.fromHSV(hue, 1, 1)
    end)

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
    end)

    -- Ряд управления полетом (Fly Toggle)
    createToggleRow("FlyToggle", "Fly", 4, function(setState)
        nowe = not nowe
        setState(nowe)
        
        local speaker = Players.LocalPlayer
        if nowe then
            for i = 1, speeds do
                task.spawn(function()
                    local hb = RunService.Heartbeat	
                    tpwalking = true
                    local chr = speaker.Character
                    local hum = chr and chr:FindFirstChildWhichIsA("Humanoid")
                    while tpwalking and hb:Wait() and chr and hum and hum.Parent do
                        if hum.MoveDirection.Magnitude > 0 then
                            chr:TranslateBy(hum.MoveDirection)
                        end
                    end
                end)
            end
            if speaker.Character and speaker.Character:FindFirstChild("Animate") then
                speaker.Character.Animate.Disabled = true
            end
            local Char = speaker.Character
            local Hum = Char and (Char:FindFirstChildOfClass("Humanoid") or Char:FindFirstChildOfClass("AnimationController"))
            if Hum then
                for _,v in next, Hum:GetPlayingAnimationTracks() do
                    v:AdjustSpeed(0)
                end
            end
            if speaker.Character and speaker.Character:FindFirstChild("Humanoid") then
                speaker.Character.Humanoid.PlatformStand = true
                speaker.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Swimming)
            end
            
            -- Логика движения полета
            task.spawn(function()
                local plr = Players.LocalPlayer
                local char = plr.Character
                if not char then return end
                local rootPart = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
                if not rootPart then return end
                
                local bg = Instance.new("BodyGyro", rootPart)
                bg.P = 9e4
                bg.maxTorque = Vector3.new(9e9, 9e9, 9e9)
                bg.cframe = rootPart.CFrame
                
                local bv = Instance.new("BodyVelocity", rootPart)
                bv.velocity = Vector3.new(0, 0.1, 0)
                bv.maxForce = Vector3.new(9e9, 9e9, 9e9)
                
                local ctrl = {f = 0, b = 0, l = 0, r = 0}
                local lastctrl = {f = 0, b = 0, l = 0, r = 0}
                local maxspeed = 50
                local speedVal = 0
                
                local uis = game:GetService("UserInputService")
                local conn1, conn2
                
                conn1 = uis.InputBegan:Connect(function(input)
                    if input.KeyCode == Enum.KeyCode.W then ctrl.f = 1 end
                    if input.KeyCode == Enum.KeyCode.S then ctrl.b = -1 end
                    if input.KeyCode == Enum.KeyCode.A then ctrl.l = -1 end
                    if input.KeyCode == Enum.KeyCode.D then ctrl.r = 1 end
                end)
                
                conn2 = uis.InputEnded:Connect(function(input)
                    if input.KeyCode == Enum.KeyCode.W then ctrl.f = 0 end
                  

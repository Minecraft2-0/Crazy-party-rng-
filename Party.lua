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
    DEBUG_MODE        = false,
    TargetingMode     = "distance", -- "distance" or "health"
}
local ESPConfig = {
    Enabled     = false,       -- Toggle for ESP
    MaxDistance = 500,         -- Default max distance for ESP
}
local FlyConfig = {
    Enabled  = false,
    Speed    = 1,             -- Начальная скорость
    MinSpeed = 1,             -- Минимальная скорость
    MaxSpeed = 10,            -- Максимальная скорость
}

local State = {
    Enabled         = false,
    Weapon          = "Unarmed",
    HumanoidRootPart= nil,
    LastAttack      = 0,
    DebugLog        = {},
}

local FlyState = {
    Flying = false,
    BodyGyro = nil,
    BodyVelocity = nil,
    RenderConnection = nil,
}

local DamageEvent = ReplicatedStorage:WaitForChild("GameContents"):WaitForChild("Remotes"):WaitForChild("DamageEvent")
local Connections = {}  -- Holds all event connections

-- Cleanup Function
_G.KillAuraCleanup = function()
    for _, conn in ipairs(Connections) do
        if conn then conn:Disconnect() end
    end
    if FlyState.RenderConnection then
        FlyState.RenderConnection:Disconnect()
    end
    if FlyState.BodyGyro then FlyState.BodyGyro:Destroy() end
    if FlyState.BodyVelocity then FlyState.BodyVelocity:Destroy() end
end

------------------------------------------
-- Target Acquisition & Damage Processing
------------------------------------------
local function getSortedTargets()
    local targets = {}
    if not State.HumanoidRootPart then return targets end
    local playerPos = State.HumanoidRootPart.Position

    local mobsFolder = Workspace:FindFirstChild("Mobs")
    if not mobsFolder then return targets end

    for _, mob in ipairs(mobsFolder:GetChildren()) do
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

-- Update the currently equipped weapon
local function updateWeapon(character)
    local tool = character:FindFirstChildOfClass("Tool")
    State.Weapon = tool and tool.Name or "Unarmed"
end

-- Character handling
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

------------------------------------------
-- FLY LOGIC (Mobile & PC Compatible)
------------------------------------------
local function toggleFly(enable)
    FlyConfig.Enabled = enable
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")

    if not hum or not root then return end

    if enable then
        FlyState.Flying = true

        -- Disable default physics states
        hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Landed, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Running, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
        hum:ChangeState(Enum.HumanoidStateType.Swimming)

        hum.PlatformStand = true

        -- Setup BodyGyro and BodyVelocity
        FlyState.BodyGyro = Instance.new("BodyGyro")
        FlyState.BodyGyro.P = 9e4
        FlyState.BodyGyro.maxTorque = Vector3.new(9e9, 9e9, 9e9)
        FlyState.BodyGyro.cframe = root.CFrame
        FlyState.BodyGyro.Parent = root

        FlyState.BodyVelocity = Instance.new("BodyVelocity")
        FlyState.BodyVelocity.velocity = Vector3.new(0, 0.1, 0)
        FlyState.BodyVelocity.maxForce = Vector3.new(9e9, 9e9, 9e9)
        FlyState.BodyVelocity.Parent = root

        FlyState.RenderConnection = RunService.RenderStepped:Connect(function()
            if not FlyState.Flying or not root or not hum then return end
            
            local moveDir = hum.MoveDirection
            local baseSpeed = 50 * FlyConfig.Speed
            
            FlyState.BodyGyro.cframe = Camera.CFrame
            
            if moveDir.Magnitude > 0 then
                -- Direct motion based on camera view angle
                FlyState.BodyVelocity.velocity = Camera.CFrame:VectorToWorldSpace(
                    CFrame.new(Vector3.zero, Camera.CFrame.LookVector):VectorToWorldSpace(moveDir)
                ) * baseSpeed
            else
                FlyState.BodyVelocity.velocity = Vector3.new(0, 0, 0)
            end
        end)
    else
        FlyState.Flying = false
        if FlyState.RenderConnection then FlyState.RenderConnection:Disconnect() end
        if FlyState.BodyGyro then FlyState.BodyGyro:Destroy() end
        if FlyState.BodyVelocity then FlyState.BodyVelocity:Destroy() end

        hum.PlatformStand = false
        hum:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Flying, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.GettingUp, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Physics, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        hum:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
        hum:ChangeState(Enum.HumanoidStateType.Running)
    end
end

--------------------------------------------------------------------------------
-- BOUNDING BOX ESP (2D lines + text + HP bar)
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
    local cframe, size
    if model.PrimaryPart then
        cframe, size = model:GetBoundingBox()
    else
        local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        if not root then return {} end
        cframe, size = root.CFrame, root.Size * 1.25
    end
    
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

    if not onScreen or (maxX - minX) < 2 or (maxY - minY) < 2 then
        for _, obj in pairs(boxData) do obj.Visible = false end
        return
    end

    local boxHeight = maxY - minY

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

    boxData.Label.Visible = true
    boxData.Label.Text = string.format("%s  %.0fm", mob.Name, dist)
    boxData.Label.Position = Vector2.new((minX + maxX)/2, minY - 16)
end

table.insert(Connections, RunService.RenderStepped:Connect(function()
    if not ESPConfig.Enabled or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        for mob in pairs(MobESPBoxes) do removeBox(mob) end
        return
    end

    local playerPos = LocalPlayer.Character.HumanoidRootPart.Position
    local validMobs = {}
    local mobsFolder = Workspace:FindFirstChild("Mobs")

    if mobsFolder then
        for _, mob in ipairs(mobsFolder:GetChildren()) do
            local hrp = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Head") or mob:FindFirstChild("Torso")
            if hrp then
                local dist = (playerPos - hrp.Position).Magnitude
                if dist <= ESPConfig.MaxDistance then
                    validMobs[mob] = dist
                end
            end
        end
    end

    for mob, dist in pairs(validMobs) do updateBox(mob, dist) end
    for mob in pairs(MobESPBoxes) do
        if not validMobs[mob] then removeBox(mob) end
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
    mainFrame.Size = UDim2.new(0, 220, 0, 210)
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
    title.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
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

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 4)
        btnCorner.Parent = button

        button.MouseButton1Click:Connect(function()
            local isNowOn = toggleCallback()
            if isNowOn then
                TweenService:Create(button, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(0, 180, 0) }):Play()
                button.Text = "ON"
            else
                TweenService:Create(button, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(120, 0, 0) }):Play()
                button.Text = "OFF"
            end
        end)
    end

    -- Слайдер скорости Fly (совместимый с ПК и Сенсорным экраном)
    local function createSliderRow(name, labelText, order, minVal, maxVal, defaultVal, callback)
        local sliderFrame = Instance.new("Frame")
        sliderFrame.Name = name
        sliderFrame.Size = UDim2.new(1, 0, 0, 35)
        sliderFrame.BackgroundTransparency = 1
        sliderFrame.LayoutOrder = order
        sliderFrame.Parent = mainFrame

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 15)
        label.BackgroundTransparency = 1
        label.Text = string.format("%s: %d", labelText, defaultVal)
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = sliderFrame

        local barBack

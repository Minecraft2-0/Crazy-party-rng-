--[[ 
   Crazy Party RPG V3.7.0 [FIXED]
   ==========================================================
   Fixed syntax cutoff at the end and added safety checks for Drawing API.
]]--

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

-- Global cleanup check
if _G.KillAuraCleanup then
    _G.KillAuraCleanup()
end

-- Config and State
local Config = {
    MAX_RANGE         = 20,
    COOLDOWN          = 0.2,
    TRACK_LERP_SPEED  = 0.1,
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

local DamageEvent = ReplicatedStorage:WaitForChild("GameContents"):WaitForChild("Remotes"):WaitForChild("DamageEvent")
local Connections = {}

local function debugLog(msg)
    if Config.DEBUG_MODE then
        print("[KillAura DEBUG]: " .. msg)
        table.insert(State.DebugLog, msg)
    end
end

-- Cleanup Function
_G.KillAuraCleanup = function()
    for _, conn in ipairs(Connections) do
        if conn then conn:Disconnect() end
    end
    local gui = PlayerGui:FindFirstChild("KillAuraGUI")
    if gui then gui:Destroy() end
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
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
    if not root then return {} end
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

local function createBox(mob)
    if not Drawing then return end
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
            pcall(function() obj:Remove() end)
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
    if not boxData then return end

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

    if not onScreen or (maxX - minX < 2) or (maxY - minY < 2) then
        for _, obj in pairs(boxData) do obj.Visible = false end
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
    local barHeight = (maxY - minY) * hpPercent
    boxData.HPBar.Visible = true
    boxData.HPBar.From = Vector2.new(minX - 4, maxY)
    boxData.HPBar.To   = Vector2.new(minX - 4, maxY - barHeight)

    boxData.Label.Visible = true
    boxData.Label.Text = string.format("%s  %.0fm", mob.Name, dist)
    boxData.Label.Position = Vector2.new((minX + maxX)/2, minY - 16)
end

local function updateBoundingBoxes()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        for mob, boxData in pairs(MobESPBoxes) do
            for _, obj in pairs(boxData) do obj.Visible = false end
        end
        return
    end

    local playerPos = LocalPlayer.Character.HumanoidRootPart.Position
    local validMobs = {}
    local mobsFolder = Workspace:FindFirstChild("Mobs")

    if mobsFolder then
        for _, mob in ipairs(mobsFolder:GetChildren()) do
            local hrp = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Head")
            if hrp then
                local dist = (playerPos - hrp.Position).Magnitude
                if ESPConfig.Enabled and dist <= ESPConfig.MaxDistance then
                    validMobs[mob] = dist
                end
            end
        end
    end

    for mob, dist in pairs(validMobs) do updateBox(mob, dist) end
    for mob, _ in pairs(MobESPBoxes) do
        if not validMobs[mob] then removeBox(mob) end
    end
end

table.insert(Connections, RunService.RenderStepped:Connect(function()
    if ESPConfig.Enabled then
        updateBoundingBoxes()
    else
        for mob, _ in pairs(MobESPBoxes) do removeBox(mob) end
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
    mainFrame.Size = UDim2.new(0, 220, 0, 180)
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

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = mainFrame

    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, 8)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 8)
    padding.PaddingBottom = UDim.new(0, 8)
    padding.Parent = mainFrame

    UI.enableDrag(mainFrame)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 20)
    title.BackgroundTransparency = 1
    title.Text = "Crazy Party RPG"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.Parent = mainFrame

    local function createToggleRow(name, labelText, order, toggleCallback)
        local rowFrame = Instance.new("Frame")
        rowFrame.Name = name
        rowFrame.Size = UDim2.new(1, 0, 0, 25)
        rowFrame.BackgroundTransparency = 1
        rowFrame.LayoutOrder = order
        rowFrame.Parent = mainFrame

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -70, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = labelText
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.Gotham
        label.TextSize = 14
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = rowFrame

        local button = Instance.new("TextButton")
        button.Size = UDim2.new(0, 60, 1, 0)
        button.Position = UDim2.new(1, -60, 0, 0)
        button.BackgroundColor3 = Color3.fromRGB(120, 0, 0)
        button.TextColor3 = Color3.new(1, 1, 1)
        button.Font = Enum.Font.Gotham
        button.TextSize = 14
        button.Text = "OFF"
        button.Parent = rowFrame

        button.MouseButton1Click:Connect(function()
            toggleCallback(function(isOn)
                if isOn then
                    TweenService:Create(button, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(0, 180, 0) }):Play()
                    button.Text = "ON"
                else
                    TweenService:Create(button, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(120, 0, 0) }):Play()
                    button.Text = "OFF"
                end
            end)
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
end

UI.createMainGUI()

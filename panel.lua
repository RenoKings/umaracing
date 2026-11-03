local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

--// Theme
local C = {
    bg       = Color3.fromRGB(18, 18, 22),
    surface  = Color3.fromRGB(28, 28, 34),
    stroke   = Color3.fromRGB(48, 48, 58),
    text     = Color3.fromRGB(235, 235, 240),
    sub      = Color3.fromRGB(140, 140, 155),
    accent   = Color3.fromRGB(99, 102, 241),
    off      = Color3.fromRGB(58, 58, 70),
    danger   = Color3.fromRGB(239, 68, 68),
}
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold

--// Helpers
local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function round(o, r) return new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
local function outline(o)
    return new("UIStroke", {Color = C.stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
end
local function tween(o, props, t)
    TweenService:Create(o, TweenInfo.new(t or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end
local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end
local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end
local function getHumanoid()
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

--// Connection bookkeeping (disconnected on close)
local conns = {}
local function bind(signal, fn)
    local c = signal:Connect(fn)
    conns[#conns + 1] = c
    return c
end

--// Root
local playerGui = player:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("Panel")
if old then old:Destroy() end

local gui = new("ScreenGui", {
    Name = "Panel",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(300, 190),
    Position = UDim2.new(0.5, -150, 0.5, -95),
    BackgroundColor3 = C.bg,
    BorderSizePixel = 0,
}, gui)
round(window, 12)
outline(window)

--// Header (drag area + tabs + close)
local header = new("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundTransparency = 1,
}, window)

local dragArea = new("Frame", {
    Name = "DragArea",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Active = true,
    ZIndex = 1,
}, header)

local tabBar = new("Frame", {
    Name = "Tabs",
    Size = UDim2.new(1, -96, 0, 28),
    Position = UDim2.fromOffset(10, 8),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
    ZIndex = 2,
}, header)
round(tabBar, 8)

local closeBtn = new("TextButton", {
    Name = "Close",
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -38, 0, 8),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "×",
    TextColor3 = C.sub,
    Font = FONT_B,
    TextSize = 20,
    ZIndex = 2,
}, header)
round(closeBtn, 8)
closeBtn.MouseEnter:Connect(function()
    tween(closeBtn, {TextColor3 = C.danger})
end)
closeBtn.MouseLeave:Connect(function()
    tween(closeBtn, {TextColor3 = C.sub})
end)

local content = new("Frame", {
    Name = "Content",
    Size = UDim2.new(1, 0, 1, -44),
    Position = UDim2.fromOffset(0, 44),
    BackgroundTransparency = 1,
}, window)

--// Minimize
local FULL_SIZE, MINI_SIZE = UDim2.fromOffset(300, 190), UDim2.fromOffset(72, 44)
local minimized = false

local minBtn = new("TextButton", {
    Name = "Minimize",
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.new(1, -70, 0, 8),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "–",
    TextColor3 = C.sub,
    Font = FONT_B,
    TextSize = 20,
    ZIndex = 2,
}, header)
round(minBtn, 8)
minBtn.MouseEnter:Connect(function() tween(minBtn, {TextColor3 = C.text}) end)
minBtn.MouseLeave:Connect(function() tween(minBtn, {TextColor3 = C.sub}) end)

minBtn.Activated:Connect(function()
    minimized = not minimized
    content.Visible = not minimized
    tabBar.Visible = not minimized
    minBtn.Text = minimized and "+" or "–"
    tween(window, {Size = minimized and MINI_SIZE or FULL_SIZE}, 0.2)
end)

--// Tabs
local TABS ={"Control", "Stamina", "Speed"}
local pages, tabBtns = {}, {}

local function selectTab(name)
    for n, page in pairs(pages) do page.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        local on = (n == name)
        tween(b, {BackgroundTransparency = on and 0 or 1, TextColor3 = on and C.text or C.sub})
    end
end

for i, name in ipairs(TABS) do
    local b = new("TextButton", {
        Name = name,
        Size = UDim2.new(1 / #TABS, -4, 1, -4),
        Position = UDim2.new((i - 1) / #TABS, 2, 0, 2),
        BackgroundColor3 = C.accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = name,
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 13,
    }, tabBar)
    round(b, 6)
    tabBtns[name] = b

    local page = new("Frame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, content)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 2),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
    }, page)
    new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, page)
    pages[name] = page

    b.Activated:Connect(function() selectTab(name) end)
end

--// Toggle row (init = initial state)
local function makeToggle(parent, text, onChange, init)
    local on = init == true

    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
    }, parent)
    round(row, 8)

    new("TextLabel", {
        Size = UDim2.new(1, -64, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)

    local track = new("Frame", {
        Size = UDim2.fromOffset(36, 20),
        Position = UDim2.new(1, -48, 0.5, -10),
        BackgroundColor3 = on and C.accent or C.off,
        BorderSizePixel = 0,
    }, row)
    round(track, 10)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = on and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    round(knob, 7)

    row.Activated:Connect(function()
        on = not on
        tween(track, {BackgroundColor3 = on and C.accent or C.off})
        tween(knob, {Position = on and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3)})
        onChange(on)
    end)
end

--// State
local autoQTE, easyControl, infStamina = false, false, false
local speedOn, speedMult = true, 1.1

--// Control tab
makeToggle(pages.Control, "Auto QTE", function(v) autoQTE = v end)
makeToggle(pages.Control, "Easy Control", function(v)
    easyControl = v
    if not v then
        local hum = getHumanoid()
        if hum then hum.AutoRotate = true end
    end
end)

-- Auto QTE: di-throttle, GetDescendants() tiap frame bikin FPS drop
local qteTimer = 0
bind(RunService.Heartbeat, function(dt)
    if not autoQTE then return end
    qteTimer += dt
    if qteTimer < 0.25 then return end
    qteTimer = 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            pcall(function()
                obj:InputHoldBegin()
                obj:InputHoldEnd()
            end)
        end
    end
end)

-- Easy Control: pakai Humanoid.MoveDirection (support joystick mobile + keyboard)
bind(RunService.Heartbeat, function()
    if not easyControl then return end
    local hum = getHumanoid()
    if not hum or hum.Health <= 0 then return end
    local root = hum.RootPart
    if not root then return end

    hum.AutoRotate = false

    local md = hum.MoveDirection
    local flat = Vector3.new(md.X, 0, md.Z)
    local vel = root.AssemblyLinearVelocity

    if flat.Magnitude > 0.01 then
        flat = flat.Unit
        local ws = hum.WalkSpeed
        root.AssemblyLinearVelocity = Vector3.new(flat.X * ws, vel.Y, flat.Z * ws)
        root.CFrame = root.CFrame:Lerp(CFrame.lookAt(root.Position, root.Position + flat), 0.3)
    elseif hum.FloorMaterial ~= Enum.Material.Air then
        -- stop instan pas joystick dilepas (hanya di tanah)
        root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
    end
end)

--// Stamina tab
makeToggle(pages.Stamina, "Infinite Stamina", function(v) infStamina = v end)

local function findStamina()
    for _, holder in ipairs({player.Character, player}) do
        if holder then
            local v = holder:FindFirstChild("Stamina")
            if v and v:IsA("ValueBase") and v.Value ~= nil and type(v.Value) == "number" then
                return v, holder
            end
        end
    end
end

bind(RunService.Heartbeat, function()
    if not infStamina then return end
    local stamina, holder = findStamina()
    if not stamina then return end
    -- NumberValue gak punya .MaxValue (itu bikin error di versi lama), cari sibling MaxStamina / attribute
    local m = holder:FindFirstChild("MaxStamina")
    local maxV = (m and type(m.Value) == "number" and m.Value)
        or stamina:GetAttribute("Max")
        or math.max(100, stamina.Value)
    if stamina.Value < maxV then stamina.Value = maxV end
end)

--// Speed tab (multiplier dari WalkSpeed bawaan game)
do
    local MIN, MAX, STEP = 1.1, 1.5, 0.05

    makeToggle(pages.Speed, "Speed Boost", function(v) speedOn = v end, true)

    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 64),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, pages.Speed)
    round(card, 8)

    new("TextLabel", {
        Size = UDim2.new(0.5, -12, 0, 18),
        Position = UDim2.fromOffset(12, 10),
        BackgroundTransparency = 1,
        Text = "Multiplier",
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)

    local valueLabel = new("TextLabel", {
        Size = UDim2.new(0.5, -12, 0, 18),
        Position = UDim2.new(0.5, 0, 0, 10),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.accent,
        Font = FONT_B,
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, card)

    local hit = new("Frame", {
        Size = UDim2.new(1, -24, 0, 28),
        Position = UDim2.fromOffset(12, 30),
        BackgroundTransparency = 1,
        Active = true,
    }, card)

    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 6),
        Position = UDim2.new(0, 0, 0.5, -3),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, hit)
    round(bar, 3)

    local fill = new("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
    }, bar)
    round(fill, 3)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(16, 16),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, bar)
    round(knob, 8)

    local function setMult(m)
        m = math.clamp(m, MIN, MAX)
        m = MIN + math.floor((m - MIN) / STEP + 0.5) * STEP
        speedMult = math.floor(m * 100 + 0.5) / 100
        local rr = (speedMult - MIN) / (MAX - MIN)
        fill.Size = UDim2.fromScale(rr, 1)
        knob.Position = UDim2.fromScale(rr, 0.5)
        valueLabel.Text = string.format("%.2fx", speedMult)
    end
    local function fromInput(input)
        local r = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
        setMult(MIN + math.clamp(r, 0, 1) * (MAX - MIN))
    end
    setMult(speedMult)

    local sliding = false
    hit.InputBegan:Connect(function(input)
        if isPointer(input) then
            sliding = true
            fromInput(input)
        end
    end)
    bind(UserInputService.InputChanged, function(input)
        if sliding and isMove(input) then fromInput(input) end
    end)
    bind(UserInputService.InputEnded, function(input)
        if isPointer(input) then sliding = false end
    end)
end

-- Base WalkSpeed dilacak: kalau game ngubah WalkSpeed (sprint, stamina habis, dll),
-- nilai itu jadi base baru, lalu dikali multiplier.
local lastHum, baseWS, lastWS
bind(RunService.Heartbeat, function()
    local hum = getHumanoid()
    if not hum then return end
    if hum ~= lastHum then
        lastHum, baseWS, lastWS = hum, nil, nil
    end

    local ws = hum.WalkSpeed
    if lastWS == nil or math.abs(ws - lastWS) > 1e-3 then
        baseWS = ws
    end

    local target = speedOn and baseWS * speedMult or baseWS
    if math.abs(ws - target) > 1e-3 then hum.WalkSpeed = target end
    lastWS = target
end)

--// Window drag
do
    local dragging, dragStart, startPos
    dragArea.InputBegan:Connect(function(input)
        if isPointer(input) then
            dragging = true
            dragStart = input.Position
            startPos = window.Position
        end
    end)
    bind(UserInputService.InputChanged, function(input)
        if dragging and isMove(input) then
            local d = input.Position - dragStart
            window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end)
    bind(UserInputService.InputEnded, function(input)
        if isPointer(input) then dragging = false end
    end)
end

--// Close (restore semua)
closeBtn.Activated:Connect(function()
    for _, c in ipairs(conns) do c:Disconnect() end
    local hum = getHumanoid()
    if hum then
        hum.AutoRotate = true
        if baseWS and hum == lastHum then hum.WalkSpeed = baseWS end
    end
    gui:Destroy()
end)

selectTab(TABS[1])

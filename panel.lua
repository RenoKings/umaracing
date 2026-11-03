--// Panel v5 — ringan: loop cuma nyala kalau fiturnya aktif, tanpa scan berat
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G

-- bersihin instance lama (termasuk loop-nya) kalau script dieksekusi ulang
if env.__PanelCleanup then pcall(env.__PanelCleanup) end
local oldGui = playerGui:FindFirstChild("Panel")
if oldGui then oldGui:Destroy() end

--// Theme
local C = {
    bg      = Color3.fromRGB(17, 17, 22),
    surface = Color3.fromRGB(27, 27, 34),
    stroke  = Color3.fromRGB(50, 50, 62),
    text    = Color3.fromRGB(235, 235, 242),
    sub     = Color3.fromRGB(135, 135, 152),
    accent  = Color3.fromRGB(99, 102, 241),
    accent2 = Color3.fromRGB(139, 92, 246),
    off     = Color3.fromRGB(55, 55, 68),
    danger  = Color3.fromRGB(239, 68, 68),
    ok      = Color3.fromRGB(74, 222, 128),
}
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold
local WIN_W, WIN_H = 270, 168

--// Helpers
local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function round(o, r) new("UICorner", {CornerRadius = UDim.new(0, r)}, o) end
local function isPointer(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function isMove(i)
    return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end
local function getHumanoid()
    local ch = player.Character
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function ease(o, props)
    TweenService:Create(o, TweenInfo.new(0.12, Enum.EasingStyle.Quad), props):Play()
end

-- Connect hanya saat fitur aktif; balikin setter on/off
local function hook(signal, fn)
    local c
    return function(on)
        if on and not c then
            c = signal:Connect(fn)
        elseif not on and c then
            c:Disconnect()
            c = nil
        end
    end
end

--// ======================= FITUR =======================
local speedMult = 1.1

-- Auto QTE: tekan QTEButton pas Pointer sejajar SuccessLine
local function press(btn)
    local fake = {
        UserInputType = Enum.UserInputType.Touch,
        UserInputState = Enum.UserInputState.Begin,
        KeyCode = Enum.KeyCode.Unknown,
        Position = Vector3.new(btn.AbsolutePosition.X, btn.AbsolutePosition.Y, 0),
    }
    if getconnections then
        for _, sig in ipairs({btn.Activated, btn.MouseButton1Click, btn.MouseButton1Down, btn.InputBegan}) do
            pcall(function()
                for _, c in ipairs(getconnections(sig)) do
                    if c.Function then task.spawn(c.Function, fake) end
                end
            end)
        end
    elseif firesignal then
        pcall(function()
            firesignal(btn.MouseButton1Down)
            firesignal(btn.MouseButton1Click)
            firesignal(btn.Activated)
        end)
    end
end

local function angDiff(a, b) return (a - b + 180) % 360 - 180 end
local lastQ, prevD = 0, nil
local setQTE = hook(RunService.RenderStepped, function()
    local q = playerGui:FindFirstChild("QTEGui")
    local sc = q and q.Enabled and q:FindFirstChild("SkillCheck")
    if not (sc and sc.Visible) then prevD = nil; return end
    local ptr, line = sc:FindFirstChild("Pointer"), sc:FindFirstChild("SuccessLine")
    local bg = playerGui:FindFirstChild("QTEButtonGui")
    local btn = bg and bg:FindFirstChild("QTEButton")
    if not (ptr and line and btn) then return end
    local d = angDiff(ptr.Rotation, line.Rotation)
    local vd = prevD and angDiff(d, prevD) or 0
    prevD = d
    if os.clock() - lastQ < 0.5 then return end
    if math.abs(d + vd * 2) < 5 then
        lastQ = os.clock()
        press(btn)
    end
end)

-- Infinite Stamina: Info.Stamina + config sprint di memori client
local sprintCfg, origBase, stamScan, stamChar = nil, nil, 0, nil
local function findSprintCfg()
    if not getgc then return end
    for _, t in ipairs(getgc(true)) do
        if type(t) == "table" then
            local ok, hit = pcall(function()
                return rawget(t, "BaseStaminaUseRate") ~= nil and rawget(t, "CurrentStaminaUseRate") ~= nil
            end)
            if ok and hit then return t end
        end
    end
end
local setStamLoop = hook(RunService.Heartbeat, function(dt)
    if player.Character ~= stamChar then stamChar = player.Character; sprintCfg = nil; stamScan = 0 end
    if not sprintCfg then
        stamScan -= dt
        if stamScan <= 0 then
            stamScan = 2
            sprintCfg = findSprintCfg()
            if sprintCfg then origBase = sprintCfg.BaseStaminaUseRate end
        end
    end
    if sprintCfg then
        pcall(function()
            sprintCfg.BaseStaminaUseRate = 0
            sprintCfg.CurrentStaminaUseRate = 0
        end)
    end
    local info = player:FindFirstChild("Info")
    local st = info and info:FindFirstChild("Stamina")
    local mx = info and info:FindFirstChild("MaxStamina")
    if st and mx and st.Value < mx.Value then st.Value = mx.Value end
end)
local function setStamina(on)
    setStamLoop(on)
    if not on and sprintCfg and origBase then
        pcall(function() sprintCfg.BaseStaminaUseRate = origBase end)
    end
end

-- Easy Control: karakter langsung ngadep arah kamera (ngikut geseran layar)
local function easyStep()
    local hum = getHumanoid()
    local root = hum and hum.Health > 0 and hum.RootPart
    if not root then return end
    local look = workspace.CurrentCamera.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then return end
    flat = flat.Unit

    local v = root.AssemblyLinearVelocity
    local h = Vector3.new(v.X, 0, v.Z)
    local moving = h.Magnitude > 2
    if moving and h.Unit:Dot(flat) < 0 then return end -- lagi Look Back

    hum.AutoRotate = false
    root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
    if moving then
        root.AssemblyLinearVelocity = flat * h.Magnitude + Vector3.new(0, v.Y, 0)
    end
end
local function setEasy(on)
    pcall(function() RunService:UnbindFromRenderStep("PanelEasyControl") end)
    if on then
        RunService:BindToRenderStep("PanelEasyControl", Enum.RenderPriority.Last.Value, easyStep)
    else
        local hum = getHumanoid()
        if hum then hum.AutoRotate = true end
    end
end

-- Speed: timpa attribute PaceSpeedMult di character
local paceOrig, paceSet
local setSpeedLoop = hook(RunService.Heartbeat, function()
    local ch = player.Character
    local cur = ch and ch:GetAttribute("PaceSpeedMult")
    if cur == nil then return end
    if cur ~= paceSet then paceOrig = cur end
    if cur ~= speedMult then ch:SetAttribute("PaceSpeedMult", speedMult) end
    paceSet = speedMult
end)
local function setSpeed(on)
    setSpeedLoop(on)
    if not on then
        local ch = player.Character
        if ch and paceOrig and paceSet then ch:SetAttribute("PaceSpeedMult", paceOrig) end
        paceSet = nil
    end
end

-- Hold Speed: pin field `speed` di state sprint (yang dibaca bar speed + dikirim ke server) ke % dari CurrentMaxSpeed
local holdPct = 0.5
local holdStates, holdScan, holdChar = {}, 0, nil
local function findSprintStates()
    local list = {}
    if not getgc then return list end
    for _, t in ipairs(getgc(true)) do
        if type(t) == "table" then
            local ok, hit = pcall(function()
                return type(rawget(t, "speed")) == "number" and rawget(t, "sprintKeys") ~= nil
                    and rawget(t, "lastSpeedIncreaseRemote") ~= nil
            end)
            if ok and hit then list[#list + 1] = t end
        end
    end
    return list
end
local function holdStep(dt)
    if player.Character ~= holdChar then holdChar = player.Character; holdStates = {}; holdScan = 0 end
    if #holdStates == 0 then
        holdScan -= dt
        if holdScan > 0 then return end
        holdScan = 2
        holdStates = findSprintStates()
        if not sprintCfg then
            sprintCfg = findSprintCfg()
            if sprintCfg then origBase = sprintCfg.BaseStaminaUseRate end
        end
        return
    end
    local max = (sprintCfg and tonumber(sprintCfg.CurrentMaxSpeed)) or 160
    local target = holdPct * max
    for _, st in ipairs(holdStates) do
        pcall(function() st.speed = target end)
    end
end
local holdA = hook(RunService.RenderStepped, holdStep)
local holdB = hook(RunService.Heartbeat, holdStep)
local function setHold(on) holdA(on); holdB(on) end

--// ======================= UI =======================
local gui = new("ScreenGui", {
    Name = "Panel",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0, 80),
    BackgroundColor3 = C.bg,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
}, gui)
round(window, 12)
new("UIStroke", {Color = C.stroke, Thickness = 1}, window)

-- Bubble (minimized)
local bubble = new("TextButton", {
    Name = "Bubble",
    Size = UDim2.fromOffset(40, 40),
    BackgroundColor3 = C.accent,
    AutoButtonColor = false,
    Text = "P",
    TextColor3 = Color3.new(1, 1, 1),
    Font = FONT_B,
    TextSize = 17,
    Visible = false,
}, gui)
round(bubble, 20)
new("UIStroke", {Color = Color3.new(1, 1, 1), Transparency = 0.8, Thickness = 1}, bubble)
new("UIGradient", {
    Color = ColorSequence.new(C.accent, C.accent2),
    Rotation = 45,
}, bubble)
local dot = new("Frame", {
    Size = UDim2.fromOffset(10, 10),
    Position = UDim2.new(1, -11, 0, 1),
    BackgroundColor3 = C.ok,
    BorderSizePixel = 0,
    Visible = false,
}, bubble)
round(dot, 5)
new("UIStroke", {Color = C.bg, Thickness = 2}, dot)

local active = {}
local function setActive(key, on)
    active[key] = on or nil
    dot.Visible = next(active) ~= nil
end

-- Drag generik (tap = onTap kalau gak geser)
local function draggable(handle, target, onTap)
    handle.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        local start, from, moved = input.Position, target.Position, false
        local cMove, cEnd
        cMove = UIS.InputChanged:Connect(function(i)
            if not isMove(i) then return end
            local d = i.Position - start
            if d.Magnitude > 6 then moved = true end
            if moved then
                target.Position = UDim2.new(from.X.Scale, from.X.Offset + d.X, from.Y.Scale, from.Y.Offset + d.Y)
            end
        end)
        cEnd = UIS.InputEnded:Connect(function(i)
            if isPointer(i) then
                cMove:Disconnect()
                cEnd:Disconnect()
                if not moved and onTap then onTap() end
            end
        end)
    end)
end

local function minimize()
    local p = window.AbsolutePosition
    bubble.Position = UDim2.fromOffset(p.X, p.Y)
    window.Visible = false
    bubble.Visible = true
end
local function restore()
    local vp, p = gui.AbsoluteSize, bubble.AbsolutePosition
    window.Position = UDim2.fromOffset(
        math.clamp(p.X, 4, math.max(4, vp.X - WIN_W - 4)),
        math.clamp(p.Y, 4, math.max(4, vp.Y - WIN_H - 4))
    )
    bubble.Visible = false
    window.Visible = true
end

-- Header: tabs + minimize + close
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 40),
    BackgroundTransparency = 1,
    Active = true,
}, window)
draggable(header, window)
draggable(bubble, bubble, restore)

local tabBar = new("Frame", {
    Size = UDim2.new(1, -74, 0, 26),
    Position = UDim2.fromOffset(10, 7),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
}, header)
round(tabBar, 8)

local function headerBtn(text, x, hoverColor)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(26, 26),
        Position = UDim2.new(1, x, 0, 7),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = text,
        TextColor3 = C.sub,
        Font = FONT_B,
        TextSize = 18,
    }, header)
    round(b, 8)
    b.MouseEnter:Connect(function() b.TextColor3 = hoverColor end)
    b.MouseLeave:Connect(function() b.TextColor3 = C.sub end)
    return b
end
local minBtn = headerBtn("–", -62, C.text)
local closeBtn = headerBtn("×", -34, C.danger)
minBtn.Activated:Connect(minimize)

local content = new("Frame", {
    Size = UDim2.new(1, 0, 1, -40),
    Position = UDim2.fromOffset(0, 40),
    BackgroundTransparency = 1,
}, window)

-- Tabs
local TABS = {"Control", "Speed", "Hold"}
local pages, tabBtns = {}, {}
local function selectTab(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, b in pairs(tabBtns) do
        local on = (n == name)
        b.BackgroundTransparency = on and 0 or 1
        b.TextColor3 = on and C.text or C.sub
    end
end
for i, name in ipairs(TABS) do
    local b = new("TextButton", {
        Size = UDim2.new(1 / #TABS, -4, 1, -4),
        Position = UDim2.new((i - 1) / #TABS, 2, 0, 2),
        BackgroundColor3 = C.accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = name,
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 12,
    }, tabBar)
    round(b, 6)
    tabBtns[name] = b
    b.Activated:Connect(function() selectTab(name) end)

    local pg = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, content)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2),
    }, pg)
    new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
    pages[name] = pg
end

-- Toggle row
local function makeToggle(parent, text, init, onChange)
    local on = init == true
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
    }, parent)
    round(row, 8)
    new("TextLabel", {
        Size = UDim2.new(1, -60, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local track = new("Frame", {
        Size = UDim2.fromOffset(32, 18),
        Position = UDim2.new(1, -44, 0.5, -9),
        BackgroundColor3 = on and C.accent or C.off,
        BorderSizePixel = 0,
    }, row)
    round(track, 9)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(12, 12),
        Position = on and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    round(knob, 6)
    row.Activated:Connect(function()
        on = not on
        ease(track, {BackgroundColor3 = on and C.accent or C.off})
        ease(knob, {Position = on and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3)})
        onChange(on)
    end)
end

-- Control tab
makeToggle(pages.Control, "Auto QTE", false, function(v) setActive("qte", v); setQTE(v) end)
makeToggle(pages.Control, "Infinite Stamina", false, function(v) setActive("stam", v); setStamina(v) end)
makeToggle(pages.Control, "Easy Control", false, function(v) setActive("easy", v); setEasy(v) end)

-- Slider generik
local function makeSlider(parent, label, MIN, MAX, STEP, init, fmt, onChange)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 58),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, parent)
    round(card, 8)
    new("TextLabel", {
        Size = UDim2.new(0.6, -12, 0, 18),
        Position = UDim2.fromOffset(12, 8),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local valueLabel = new("TextLabel", {
        Size = UDim2.new(0.4, -12, 0, 18),
        Position = UDim2.new(0.6, 0, 0, 8),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.accent,
        Font = FONT_B,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, card)
    local hit = new("Frame", {
        Size = UDim2.new(1, -24, 0, 26),
        Position = UDim2.fromOffset(12, 28),
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

    local function setVal(m)
        m = math.clamp(m, MIN, MAX)
        m = MIN + math.floor((m - MIN) / STEP + 0.5) * STEP
        m = math.floor(m * 100 + 0.5) / 100
        local r = (m - MIN) / (MAX - MIN)
        fill.Size = UDim2.fromScale(r, 1)
        knob.Position = UDim2.fromScale(r, 0.5)
        valueLabel.Text = fmt(m)
        onChange(m)
    end
    local function fromInput(input)
        local r = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
        setVal(MIN + math.clamp(r, 0, 1) * (MAX - MIN))
    end
    setVal(init)

    hit.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        fromInput(input)
        local cMove, cEnd
        cMove = UIS.InputChanged:Connect(function(i)
            if isMove(i) then fromInput(i) end
        end)
        cEnd = UIS.InputEnded:Connect(function(i)
            if isPointer(i) then cMove:Disconnect(); cEnd:Disconnect() end
        end)
    end)
end

-- Speed tab (PaceSpeedMult)
makeToggle(pages.Speed, "Speed Boost", true, function(v) setActive("speed", v); setSpeed(v) end)
makeSlider(pages.Speed, "Multiplier", 1.1, 1.5, 0.05, 1.1,
    function(v) return string.format("%.2fx", v) end,
    function(v) speedMult = v end)

-- Hold tab (tahan bar speed di level tertentu)
makeToggle(pages.Hold, "Hold Speed", false, function(v) setActive("hold", v); setHold(v) end)
makeSlider(pages.Hold, "Level (% of max)", 0.1, 1.0, 0.05, 0.5,
    function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    function(v) holdPct = v end)

--// Cleanup (close / re-execute)
local function cleanup()
    setQTE(false)
    setStamina(false)
    setEasy(false)
    setSpeed(false)
    setHold(false)
    if gui then gui:Destroy() end
    if env.__PanelCleanup == cleanup then env.__PanelCleanup = nil end
end
env.__PanelCleanup = cleanup
closeBtn.Activated:Connect(cleanup)

setSpeed(true)
setActive("speed", true)
selectTab(TABS[1])

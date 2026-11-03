--// Panel v10 — Easy Control · Infinite Stamina · Speed Boost (+ garis batas bar speed ikut multiplier)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G

if env.__PanelCleanup then pcall(env.__PanelCleanup) end
local oldGui = playerGui:FindFirstChild("Panel")
if oldGui then oldGui:Destroy() end

--// Theme
local C = {
    bg      = Color3.fromRGB(16, 16, 21),
    surface = Color3.fromRGB(26, 26, 33),
    press   = Color3.fromRGB(34, 34, 43),
    stroke  = Color3.fromRGB(48, 48, 60),
    text    = Color3.fromRGB(236, 236, 244),
    sub     = Color3.fromRGB(130, 130, 150),
    accent  = Color3.fromRGB(99, 102, 241),
    accent2 = Color3.fromRGB(139, 92, 246),
    off     = Color3.fromRGB(54, 54, 68),
    danger  = Color3.fromRGB(239, 68, 68),
    ok      = Color3.fromRGB(74, 222, 128),
    warn    = Color3.fromRGB(250, 190, 70),
}
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold
local WIN_W, WIN_H = 250, 240

--// Settings (disimpan otomatis, jadi gak perlu setting ulang tiap execute)
local FILE = "panel_settings.json"
local cfg = {easy = false, stam = false, speed = false, mult = 1.1, wx = -1, wy = -1}
pcall(function()
    if isfile and isfile(FILE) then
        local d = HttpService:JSONDecode(readfile(FILE))
        for k, def in pairs(cfg) do
            if type(d[k]) == type(def) then cfg[k] = d[k] end
        end
    end
end)
cfg.mult = math.clamp(cfg.mult, 1.1, 1.5)
local saveQueued = false
local function save()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.6, function()
        saveQueued = false
        pcall(function() if writefile then writefile(FILE, HttpService:JSONEncode(cfg)) end end)
    end)
end

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
local function dbg(...) if env.PanelDebug then warn("[Panel]", ...) end end

-- Bungkus loop pakai pcall: error 1 frame gak bikin fitur lain mati / spam console
local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            env.PanelLastError = tostring(err)
            dbg("error:", err)
        end
    end
end

-- Connect hanya saat fitur aktif; balikin setter on/off
local function hook(signal, fn)
    local c
    local wrapped = safe(fn)
    return function(on)
        if on and not c then
            c = signal:Connect(wrapped)
        elseif not on and c then
            c:Disconnect()
            c = nil
        end
    end
end

--// ======================= FITUR =======================
local speedMult = cfg.mult
local paceOrig, paceSet
-- true: garis batas digeser TURUN (r0/k) supaya nahan di garis = kecepatan asli tanpa multiplier; false: naik (r0*k)
local LINE_DIV = true

-- Satu kali scan getgc buat dua hal: config sprint (stamina) & tabel visual bar (garis batas speed).
-- Scan dipotong-potong per frame (gak nge-freeze) dan cuma jalan kalau perlu.
local cfgs, vis = {}, {}
local scanAt, scanChar, scanGap, scanning = 0, nil, 3, false

local function lineAlive(t)
    local ln = rawget(t, "line")
    return typeof(ln) == "Instance" and ln:IsDescendantOf(playerGui)
end
local function visAlive()
    for _, t in ipairs(vis) do
        if lineAlive(t) then return true end
    end
    return false
end

local function scan()
    if scanning or not getgc then return end
    scanning = true
    task.spawn(function()
        local c, v = {}, {}
        local ok = pcall(function()
            local all = getgc(true)
            for i = 1, #all do
                local t = all[i]
                if type(t) == "table" then
                    if rawget(t, "BaseStaminaUseRate") ~= nil and rawget(t, "CurrentStaminaUseRate") ~= nil then
                        c[#c + 1] = t
                    elseif rawget(t, "staminaFill") ~= nil and rawget(t, "lastLine") ~= nil and lineAlive(t) then
                        v[#v + 1] = t
                    end
                end
                if i % 3000 == 0 then task.wait() end
            end
        end)
        if ok then
            cfgs, vis = c, v
            -- kosong (lobby / HUD belum ada) -> jarak scan makin jauh; ketemu -> balik 3 dtk
            scanGap = (#c == 0 and #v == 0) and math.min(scanGap * 2, 30) or 3
            dbg("scan", #c, "cfg", #v, "vis")
        end
        scanAt = os.clock()
        scanning = false
    end)
end
local function ensure(needCfg, needVis)
    local ch = player.Character
    if ch ~= scanChar then scanChar = ch; cfgs, vis = {}, {}; scanAt = 0; scanGap = 3 end
    if ((needCfg and #cfgs == 0) or (needVis and not visAlive())) and os.clock() - scanAt > scanGap then
        scan()
    end
end

-- Infinite Stamina
-- Race baru = config sprint baru (tabel lama basi). Deteksi: HUD (lastStamina) bilang stamina turun padahal
-- sudah di-patch -> scan ulang otomatis, jadi gak perlu toggle ulang tiap race.
local origRate = setmetatable({}, {__mode = "k"})
local drainT, drainGap = 0, 2
local function stamLow()
    for _, t in ipairs(vis) do
        local ls = rawget(t, "lastStamina")
        if type(ls) == "number" and ls >= 0 and ls < 0.9 and lineAlive(t) then return true end
    end
    return false
end
local setStamLoop = hook(RunService.Heartbeat, function(dt)
    ensure(true, false)
    for _, t in ipairs(cfgs) do
        pcall(function()
            if origRate[t] == nil then origRate[t] = t.BaseStaminaUseRate end
            t.BaseStaminaUseRate = 0
            t.CurrentStaminaUseRate = 0
        end)
    end
    local info = player:FindFirstChild("Info")
    local st = info and info:FindFirstChild("Stamina")
    local mx = info and info:FindFirstChild("MaxStamina")
    if st and mx and st.Value < mx.Value then st.Value = mx.Value end

    if stamLow() then
        drainT += dt
        if drainT > 0.7 and os.clock() - scanAt > drainGap then
            drainT = 0
            drainGap = math.min(drainGap * 2, 20)
            scan()
        end
    else
        drainT, drainGap = 0, 2
    end
    if os.clock() - scanAt > 15 then scan() end
end)
local function setStamina(on)
    setStamLoop(on)
    if not on then
        drainT, drainGap = 0, 2
        for t, v in pairs(origRate) do pcall(function() t.BaseStaminaUseRate = v end) end
    end
end

-- Easy Control: karakter ngadep arah kamera
local easyStep = safe(function()
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
end)
local function setEasy(on)
    pcall(function() RunService:UnbindFromRenderStep("PanelEasyControl") end)
    if on then
        RunService:BindToRenderStep("PanelEasyControl", Enum.RenderPriority.Last.Value, easyStep)
    else
        local hum = getHumanoid()
        if hum then hum.AutoRotate = true end
    end
end

-- Speed Boost: timpa attribute PaceSpeedMult
local setPaceLoop = hook(RunService.Heartbeat, function()
    local ch = player.Character
    local cur = ch and ch:GetAttribute("PaceSpeedMult")
    if cur == nil then return end
    if cur ~= paceSet then paceOrig = cur end
    if cur ~= speedMult then ch:SetAttribute("PaceSpeedMult", speedMult) end
    paceSet = speedMult
end)

-- Garis batas di bar speed bawaan game (StaminaVision.line, posisi = lastLine = 125/161.2).
-- Digeser langsung di instance-nya; dihitung ulang cuma kalau input berubah (hemat per-frame),
-- dan kalau game nge-reset posisinya otomatis ikut posisi baru.
local lineSt = setmetatable({}, {__mode = "k"})
local lineLogged = false
local lineStep = safe(function()
    ensure(false, true)
    local k = speedMult / (paceOrig or 1)
    local f = LINE_DIV and 1 / k or k
    for _, t in ipairs(vis) do
        local line, r0 = rawget(t, "line"), rawget(t, "lastLine")
        local par = line.Parent
        if par and type(r0) == "number" and r0 > 0 and line:IsDescendantOf(playerGui) then
            local st = lineSt[line]
            if not st then st = {}; lineSt[line] = st end
            local pos = line.Position
            local sz = par.AbsoluteSize
            if st.set ~= pos then st.base = pos; st.r0 = nil end -- posisi baru dari game
            if st.r0 ~= r0 or st.f ~= f or st.sx ~= sz.X or st.sy ~= sz.Y then
                st.r0, st.f, st.sx, st.sy = r0, f, sz.X, sz.Y
                local vertical = sz.Y > sz.X
                local shift = (math.clamp(r0 * f, 0.02, 1) - r0) * (vertical and sz.Y or sz.X)
                local b = st.base
                st.want = vertical
                    and UDim2.new(b.X.Scale, b.X.Offset, b.Y.Scale, b.Y.Offset - shift)
                    or UDim2.new(b.X.Scale, b.X.Offset + shift, b.Y.Scale, b.Y.Offset)
                if not lineLogged then
                    lineLogged = true
                    dbg("line", line:GetFullName(), "r0", r0, "k", k, "vertical", vertical, "shift", shift)
                end
            end
            if pos ~= st.want then line.Position = st.want end
            st.set = st.want
        end
    end
end)
local function setLine(on)
    pcall(function() RunService:UnbindFromRenderStep("PanelLine") end)
    if on then
        RunService:BindToRenderStep("PanelLine", Enum.RenderPriority.Last.Value, lineStep)
    else
        for line, st in pairs(lineSt) do
            if st.base then pcall(function() line.Position = st.base end) end
        end
        table.clear(lineSt)
        lineLogged = false
    end
end

local function setSpeed(on)
    setPaceLoop(on)
    setLine(on)
    if not on then
        local ch = player.Character
        if ch and paceOrig and paceSet then ch:SetAttribute("PaceSpeedMult", paceOrig) end
        paceSet = nil
    end
end

--// ======================= UI =======================
local gui = new("ScreenGui", {
    Name = "Panel",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local function viewport()
    return (gui.AbsoluteSize.X > 0 and gui.AbsoluteSize) or workspace.CurrentCamera.ViewportSize
end
local function clampXY(x, y, w, h)
    local v = viewport()
    return math.clamp(x, 4, math.max(4, v.X - w - 4)), math.clamp(y, 4, math.max(4, v.Y - h - 4))
end

local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    BackgroundColor3 = C.bg,
    BackgroundTransparency = 0.03,
    BorderSizePixel = 0,
}, gui)
round(window, 14)
new("UIStroke", {Color = C.stroke, Thickness = 1}, window)
local winScale = new("UIScale", {Scale = 1}, window)
do
    local x, y
    if cfg.wx >= 0 and cfg.wy >= 0 then
        x, y = clampXY(cfg.wx, cfg.wy, WIN_W, WIN_H)
    else
        x, y = math.floor((viewport().X - WIN_W) / 2), 80
    end
    window.Position = UDim2.fromOffset(x, y)
end

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
new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 45}, bubble)
local bubScale = new("UIScale", {Scale = 1}, bubble)
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
local function pop(sc)
    sc.Scale = 0.85
    ease(sc, {Scale = 1})
end

local function draggable(handle, target, onTap, onMoved)
    handle.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        local start, from, moved = input.Position, target.Position, false
        local cMove, cEnd
        cMove = UIS.InputChanged:Connect(function(i)
            if not isMove(i) then return end
            local d = i.Position - start
            if d.Magnitude > 6 then moved = true end
            if moved then
                local x, y = clampXY(from.X.Offset + d.X, from.Y.Offset + d.Y, target.AbsoluteSize.X, target.AbsoluteSize.Y)
                target.Position = UDim2.fromOffset(x, y)
            end
        end)
        cEnd = UIS.InputEnded:Connect(function(i)
            if isPointer(i) then
                cMove:Disconnect()
                cEnd:Disconnect()
                if moved then
                    if onMoved then onMoved() end
                elseif onTap then
                    onTap()
                end
            end
        end)
    end)
end

-- Window & bubble masing-masing inget posisinya sendiri
local bubblePlaced = false
local function minimize()
    if not bubblePlaced then
        bubblePlaced = true
        local x, y = clampXY(window.Position.X.Offset, window.Position.Y.Offset, 40, 40)
        bubble.Position = UDim2.fromOffset(x, y)
    end
    window.Visible = false
    bubble.Visible = true
    pop(bubScale)
end
local function restore()
    local x, y = clampXY(window.Position.X.Offset, window.Position.Y.Offset, WIN_W, WIN_H)
    window.Position = UDim2.fromOffset(x, y)
    bubble.Visible = false
    window.Visible = true
    pop(winScale)
end

-- Header
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundTransparency = 1,
    Active = true,
}, window)
draggable(header, window, nil, function()
    cfg.wx, cfg.wy = window.Position.X.Offset, window.Position.Y.Offset
    save()
end)
draggable(bubble, bubble, restore)

local titleDot = new("Frame", {
    Size = UDim2.fromOffset(8, 8),
    Position = UDim2.fromOffset(14, 15),
    BackgroundColor3 = C.accent,
    BorderSizePixel = 0,
}, header)
round(titleDot, 4)
new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 45}, titleDot)
new("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0),
    Position = UDim2.fromOffset(30, 0),
    BackgroundTransparency = 1,
    Text = "Panel",
    TextColor3 = C.text,
    Font = FONT_B,
    TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local function headerBtn(text, x, hoverColor)
    local b = new("TextButton", {
        Size = UDim2.fromOffset(26, 26),
        Position = UDim2.new(1, x, 0, 6),
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

-- Body
local body = new("Frame", {
    Size = UDim2.new(1, 0, 1, -38),
    Position = UDim2.fromOffset(0, 38),
    BackgroundTransparency = 1,
}, window)
new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2)}, body)
new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, body)

local function makeToggle(text, init, onChange)
    local on = init == true
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
    }, body)
    round(row, 9)
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
    row.MouseButton1Down:Connect(function() row.BackgroundColor3 = C.press end)
    row.MouseButton1Up:Connect(function() row.BackgroundColor3 = C.surface end)
    row.MouseLeave:Connect(function() row.BackgroundColor3 = C.surface end)
    row.Activated:Connect(function()
        on = not on
        ease(track, {BackgroundColor3 = on and C.accent or C.off})
        ease(knob, {Position = on and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3)})
        onChange(on)
    end)
end

local function makeSlider(label, MIN, MAX, STEP, init, fmt, onChange)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, body)
    round(card, 9)
    new("TextLabel", {
        Size = UDim2.new(0.6, -12, 0, 18),
        Position = UDim2.fromOffset(12, 6),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local valueLabel = new("TextLabel", {
        Size = UDim2.new(0.4, -12, 0, 18),
        Position = UDim2.new(0.6, 0, 0, 6),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.accent,
        Font = FONT_B,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, card)
    local hit = new("Frame", {
        Size = UDim2.new(1, -24, 0, 22),
        Position = UDim2.fromOffset(12, 24),
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
    local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0}, bar)
    round(fill, 3)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(16, 16),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, bar)
    round(knob, 8)

    local cur
    local function setVal(m)
        m = math.clamp(m, MIN, MAX)
        m = MIN + math.floor((m - MIN) / STEP + 0.5) * STEP
        m = math.floor(m * 100 + 0.5) / 100
        if m == cur then return end
        cur = m
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

local function apply(key, on, setter)
    cfg[key] = on
    setActive(key, on)
    setter(on)
    save()
end

makeToggle("Easy Control", cfg.easy, function(v) apply("easy", v, setEasy) end)
makeToggle("Infinite Stamina", cfg.stam, function(v) apply("stam", v, setStamina) end)
makeToggle("Speed Boost", cfg.speed, function(v) apply("speed", v, setSpeed) end)
makeSlider("Multiplier", 1.1, 1.5, 0.05, cfg.mult,
    function(v) return string.format("%.2fx", v) end,
    function(v)
        speedMult = v
        if v ~= cfg.mult then cfg.mult = v; save() end
    end)

-- Status: titik hijau = fitur nempel di game, kuning = aktif tapi belum ketemu (lobby / race belum mulai), abu = off
local footer = new("Frame", {Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1}, body)
local function statusItem(text, x)
    local d = new("Frame", {
        Size = UDim2.fromOffset(7, 7),
        Position = UDim2.new(0, x, 0.5, -3),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, footer)
    round(d, 4)
    new("TextLabel", {
        Size = UDim2.fromOffset(80, 16),
        Position = UDim2.new(0, x + 12, 0.5, -8),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, footer)
    return d
end
local dotStam = statusItem("Stamina", 4)
local dotBar = statusItem("Speed bar", 92)
local function refreshStatus()
    dotStam.BackgroundColor3 = (not cfg.stam) and C.off or ((#cfgs > 0) and C.ok or C.warn)
    dotBar.BackgroundColor3 = (not cfg.speed) and C.off or (visAlive() and C.ok or C.warn)
end
task.spawn(function()
    while gui.Parent do
        if window.Visible then pcall(refreshStatus) end
        task.wait(0.5)
    end
end)

--// Cleanup (close / re-execute)
local function cleanup()
    setStamina(false)
    setEasy(false)
    setSpeed(false)
    if gui then gui:Destroy() end
    if env.__PanelCleanup == cleanup then env.__PanelCleanup = nil end
end
env.__PanelCleanup = cleanup
closeBtn.Activated:Connect(cleanup)

-- Terapkan setting tersimpan
if cfg.easy then setActive("easy", true); setEasy(true) end
if cfg.stam then setActive("stam", true); setStamina(true) end
if cfg.speed then setActive("speed", true); setSpeed(true) end

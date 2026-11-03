--// Panel v8 — Easy Control · Infinite Stamina · Speed Boost (+ garis batas bar speed ikut multiplier)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

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
    stroke  = Color3.fromRGB(48, 48, 60),
    text    = Color3.fromRGB(236, 236, 244),
    sub     = Color3.fromRGB(130, 130, 150),
    accent  = Color3.fromRGB(99, 102, 241),
    accent2 = Color3.fromRGB(139, 92, 246),
    off     = Color3.fromRGB(54, 54, 68),
    danger  = Color3.fromRGB(239, 68, 68),
    ok      = Color3.fromRGB(74, 222, 128),
}
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold
local WIN_W, WIN_H = 250, 218

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
local paceOrig, paceSet

-- Satu kali scan getgc buat dua hal: config sprint (stamina) & tabel visual bar (garis batas speed).
-- Discan ulang cuma kalau karakter ganti / hasil kosong / stamina keliatan masih nguras / tiap 20 dtk (stamina aktif).
local cfgs, vis = {}, {}
local scanAt, scanChar = 0, nil
local function scan()
    scanAt = os.clock()
    local c, v = {}, {}
    if getgc then
        for _, t in ipairs(getgc(true)) do
            if type(t) == "table" then
                if rawget(t, "BaseStaminaUseRate") ~= nil and rawget(t, "CurrentStaminaUseRate") ~= nil then
                    c[#c + 1] = t
                elseif rawget(t, "staminaFill") ~= nil and rawget(t, "lastLine") ~= nil
                    and typeof(rawget(t, "line")) == "Instance" then
                    v[#v + 1] = t
                end
            end
        end
    end
    cfgs, vis = c, v
    dbg("scan", #c, "cfg", #v, "vis")
end
local function ensure(needCfg, needVis)
    local ch = player.Character
    if ch ~= scanChar then scanChar = ch; cfgs, vis = {}, {}; scanAt = 0 end
    if ((needCfg and #cfgs == 0) or (needVis and #vis == 0)) and os.clock() - scanAt > 3 then scan() end
end

-- Infinite Stamina
local origRate = setmetatable({}, {__mode = "k"})
local lowN = 0
local setStamLoop = hook(RunService.Heartbeat, function()
    ensure(true, false)
    pcall(function()
        for _, t in ipairs(cfgs) do
            if origRate[t] == nil then origRate[t] = t.BaseStaminaUseRate end
            t.BaseStaminaUseRate = 0
            t.CurrentStaminaUseRate = 0
        end
    end)
    local info = player:FindFirstChild("Info")
    local st = info and info:FindFirstChild("Stamina")
    local mx = info and info:FindFirstChild("MaxStamina")
    if not (st and mx) then return end
    if st.Value < mx.Value - 1 then
        lowN += 1 -- masih nguras = config baru yang belum ke-patch, scan ulang otomatis
        if lowN > 20 and os.clock() - scanAt > 3 then lowN = 0; scan() end
    else
        lowN = 0
    end
    if st.Value < mx.Value then st.Value = mx.Value end
    if os.clock() - scanAt > 20 then scan() end
end)
local function setStamina(on)
    setStamLoop(on)
    if not on then
        lowN = 0
        for t, v in pairs(origRate) do pcall(function() t.BaseStaminaUseRate = v end) end
    end
end

-- Easy Control: karakter ngadep arah kamera
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
-- Digeser langsung di instance-nya sebesar (lastLine × multiplier/pace asli); kalau game nge-reset posisinya
-- (lastLine berubah) otomatis dihitung ulang dari posisi baru game.
local lineSt = setmetatable({}, {__mode = "k"})
local lineLogged = false
local function lineStep()
    ensure(false, true)
    local k = speedMult / (paceOrig or 1)
    for _, t in ipairs(vis) do
        local line, r0 = rawget(t, "line"), rawget(t, "lastLine")
        local par = line.Parent
        if par and type(r0) == "number" and r0 > 0 and line:IsDescendantOf(playerGui) then
            local st = lineSt[line]
            if not st then st = {}; lineSt[line] = st end
            local pos = line.Position
            if st.set ~= pos then st.base = pos end
            local sz = par.AbsoluteSize
            local vertical = sz.Y > sz.X
            local shift = (math.clamp(r0 * k, 0, 1) - r0) * (vertical and sz.Y or sz.X)
            local b = st.base
            local want = vertical
                and UDim2.new(b.X.Scale, b.X.Offset, b.Y.Scale, b.Y.Offset - shift)
                or UDim2.new(b.X.Scale, b.X.Offset + shift, b.Y.Scale, b.Y.Offset)
            if want ~= pos then line.Position = want end
            st.set = want
            if not lineLogged then
                lineLogged = true
                dbg("line", line:GetFullName(), "r0", r0, "k", k, "vertical", vertical, "shift", shift)
            end
        end
    end
end
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

local function clampXY(x, y, w, h)
    local v = (gui.AbsoluteSize.X > 0 and gui.AbsoluteSize) or workspace.CurrentCamera.ViewportSize
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
do
    local v = (gui.AbsoluteSize.X > 0 and gui.AbsoluteSize) or workspace.CurrentCamera.ViewportSize
    window.Position = UDim2.fromOffset(math.floor((v.X - WIN_W) / 2), 80)
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
                local x, y = clampXY(from.X.Offset + d.X, from.Y.Offset + d.Y, target.AbsoluteSize.X, target.AbsoluteSize.Y)
                target.Position = UDim2.fromOffset(x, y)
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
end
local function restore()
    local x, y = clampXY(window.Position.X.Offset, window.Position.Y.Offset, WIN_W, WIN_H)
    window.Position = UDim2.fromOffset(x, y)
    bubble.Visible = false
    window.Visible = true
end

-- Header
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundTransparency = 1,
    Active = true,
}, window)
draggable(header, window)
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

makeToggle("Easy Control", false, function(v) setActive("easy", v); setEasy(v) end)
makeToggle("Infinite Stamina", false, function(v) setActive("stam", v); setStamina(v) end)
makeToggle("Speed Boost", true, function(v) setActive("speed", v); setSpeed(v) end)
makeSlider("Multiplier", 1.1, 1.5, 0.05, 1.1,
    function(v) return string.format("%.2fx", v) end,
    function(v) speedMult = v end)

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

setSpeed(true)
setActive("speed", true)

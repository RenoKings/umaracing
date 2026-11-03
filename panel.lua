--// Panel v6 — Hold dihapus, Speed Limit ikut Infinite Stamina, QTE geometri, fix minimize
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
local WIN_W = 270
local PAGE_H = {Control = 168, Speed = 256}

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

-- Auto QTE: deteksi sudut arrow vs red (geometri layar, kebal offset rotasi), tekan via beberapa jalur
local QTE_LEAD = 0.05 -- detik, kompensasi latensi input
local function dbg(...) if env.PanelDebug then warn("[Panel]", ...) end end
local function angDiff(a, b) return (a - b + 180) % 360 - 180 end
local function center(o) return o.AbsolutePosition + o.AbsoluteSize / 2 end
local function dirDeg(o, pivot)
    local v = center(o) - pivot
    return math.deg(math.atan2(v.Y, v.X))
end
local function mkInput(kind, btn)
    if kind == "key" then
        return {
            UserInputType = Enum.UserInputType.Keyboard,
            UserInputState = Enum.UserInputState.Begin,
            KeyCode = Enum.KeyCode.Space,
            Position = Vector3.zero,
        }
    end
    local c = center(btn)
    return {
        UserInputType = Enum.UserInputType.Touch,
        UserInputState = Enum.UserInputState.Begin,
        KeyCode = Enum.KeyCode.Unknown,
        Position = Vector3.new(c.X, c.Y, 0),
    }
end
local function fireSig(sig, ...)
    local n = 0
    if getconnections then
        for _, c in ipairs(getconnections(sig)) do
            if c.Function then n += 1; task.spawn(c.Function, ...) end
        end
    elseif firesignal then
        n = 1; firesignal(sig, ...)
    end
    return n
end
-- 1) langsung ke handler QTEButton
local function routeButton(btn)
    local inp, n = mkInput("touch", btn), 0
    for _, sig in ipairs({btn.InputBegan, btn.MouseButton1Down, btn.MouseButton1Click, btn.Activated}) do
        n += fireSig(sig, inp)
    end
    return n
end
-- 2) handler UIS.InputBegan milik script QTE/QuickTime (Space)
local function routeUIS(btn)
    if not getconnections then return 0 end
    local inp, n = mkInput("key", btn), 0
    for _, c in ipairs(getconnections(UIS.InputBegan)) do
        local f = c.Function
        if f then
            local ok, fe = pcall(getfenv, f)
            local s = ok and type(fe) == "table" and fe.script
            local nm = s and typeof(s) == "Instance" and s:GetFullName():lower() or ""
            if nm:find("qte") or nm:find("quicktime") then
                n += 1
                task.spawn(f, inp, false)
            end
        end
    end
    return n
end
-- 3) VirtualInputManager (kalau executor support)
local function routeVIM()
    local ok = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        vim:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
        task.wait(0.03)
        vim:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
    end)
    return ok and 1 or 0
end

local qteBusy, lastQ, prevD = false, 0, nil
local function pressQTE(btn, ptr)
    if qteBusy then return end
    qteBusy = true
    task.spawn(function()
        for i, r in ipairs({routeButton, routeUIS, routeVIM}) do
            local rot = ptr.Rotation
            local ok, n = pcall(r, btn)
            dbg("QTE route", i, ok, n)
            task.wait(0.15)
            -- pointer udah berhenti/ilang = QTE kepencet, gak usah coba jalur berikutnya
            local q = playerGui:FindFirstChild("QTEGui")
            local sc = q and q.Enabled and q:FindFirstChild("SkillCheck")
            if not (sc and sc.Visible and ptr.Parent and ptr.Rotation ~= rot) then break end
        end
        qteBusy = false
    end)
end

local setQTE = hook(RunService.RenderStepped, function(dt)
    local q = playerGui:FindFirstChild("QTEGui")
    local sc = q and q.Enabled and q:FindFirstChild("SkillCheck")
    if not (sc and sc.Visible) then prevD = nil; return end
    local ptr, line = sc:FindFirstChild("Pointer"), sc:FindFirstChild("SuccessLine")
    local bg = playerGui:FindFirstChild("QTEButtonGui")
    local btn = bg and bg:FindFirstChild("QTEButton")
    if not (ptr and line and btn) then return end

    local arrow, red = ptr:FindFirstChild("arrow"), line:FindFirstChild("red")
    local d
    if arrow and red and arrow.AbsoluteSize.X > 0 and red.AbsoluteSize.X > 0 then
        local pivot = center(ptr)
        d = angDiff(dirDeg(arrow, pivot), dirDeg(red, pivot))
    else
        d = angDiff(ptr.Rotation, line.Rotation)
    end
    local vel = prevD and dt > 0 and angDiff(d, prevD) / dt or 0
    local pred = d + vel * QTE_LEAD
    local crossed = prevD and (prevD * pred <= 0) and math.abs(pred) < 40
    prevD = d
    if qteBusy or os.clock() - lastQ < 0.8 then return end
    if crossed or math.abs(pred) < 4 then
        lastQ = os.clock()
        dbg(string.format("QTE press d=%.1f vel=%.0f pred=%.1f", d, vel, pred))
        pressQTE(btn, ptr)
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
local limA, limB
local function setStamina(on)
    setStamLoop(on)
    if limA then limA(on); limB(on) end
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

-- Speed Limit (ikut Infinite Stamina): batas atas field `speed` di state sprint = % dari CurrentMaxSpeed.
-- Cuma clamp (bukan pin), jadi bar tetap naik natural sampai garis batas.
local limitPct = 0.75
local capStates, capNext, capChar = {}, 0, nil
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
local function limitStep()
    if player.Character ~= capChar then capChar = player.Character; capStates = {}; capNext = 0 end
    if #capStates == 0 then
        if os.clock() < capNext then return end
        capNext = os.clock() + 2
        capStates = findSprintStates()
        if not sprintCfg then
            sprintCfg = findSprintCfg()
            if sprintCfg then origBase = sprintCfg.BaseStaminaUseRate end
        end
        return
    end
    local cap = limitPct * ((sprintCfg and tonumber(sprintCfg.CurrentMaxSpeed)) or 161.2)
    for _, st in ipairs(capStates) do
        pcall(function() if st.speed > cap then st.speed = cap end end)
    end
end
limA = hook(RunService.RenderStepped, limitStep)
limB = hook(RunService.Heartbeat, limitStep)

--// ======================= UI =======================
local gui = new("ScreenGui", {
    Name = "Panel",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local window = new("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(WIN_W, PAGE_H.Control),
    Position = UDim2.fromOffset(60, 80),
    BackgroundColor3 = C.bg,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
}, gui)
round(window, 12)
new("UIStroke", {Color = C.stroke, Thickness = 1}, window)
do -- tengah layar (posisi pure offset biar gak ada campuran scale/inset)
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
local function clampXY(x, y, w, h)
    local v = (gui.AbsoluteSize.X > 0 and gui.AbsoluteSize) or workspace.CurrentCamera.ViewportSize
    return math.clamp(x, 4, math.max(4, v.X - w - 4)), math.clamp(y, 4, math.max(4, v.Y - h - 4))
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

-- Window & bubble masing-masing inget posisinya sendiri (gak saling geser / ke-clamp ke atas)
local refreshReadout
local bubblePlaced = false
local function minimize()
    if not bubblePlaced then -- pertama kali: muncul di pojok kiri-atas window
        bubblePlaced = true
        local x, y = clampXY(window.Position.X.Offset, window.Position.Y.Offset, 40, 40)
        bubble.Position = UDim2.fromOffset(x, y)
    end
    window.Visible = false
    bubble.Visible = true
    if refreshReadout then refreshReadout() end
end
local function restore()
    local x, y = clampXY(window.Position.X.Offset, window.Position.Y.Offset, window.AbsoluteSize.X, window.AbsoluteSize.Y)
    window.Position = UDim2.fromOffset(x, y)
    bubble.Visible = false
    window.Visible = true
    if refreshReadout then refreshReadout() end
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
local TABS = {"Control", "Speed"}
local curTab = "Control"
local pages, tabBtns = {}, {}
local function selectTab(name)
    curTab = name
    window.Size = UDim2.fromOffset(WIN_W, PAGE_H[name])
    local x, y = clampXY(window.Position.X.Offset, window.Position.Y.Offset, WIN_W, PAGE_H[name])
    window.Position = UDim2.fromOffset(x, y)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    if refreshReadout then refreshReadout() end
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
local updateMarker
makeToggle(pages.Control, "Infinite Stamina", false, function(v)
    setActive("stam", v); setStamina(v)
    if updateMarker then updateMarker() end
end)
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

-- Speed Limit (cuma kepake kalau Infinite Stamina ON) + readout bar
local rdFill, rdMarker, rdText
function updateMarker()
    if rdMarker then
        rdMarker.Position = UDim2.fromScale(limitPct, 0.5)
        rdMarker.BackgroundColor3 = active.stam and C.danger or C.sub
    end
end
makeSlider(pages.Speed, "Speed Limit", 0.4, 1.0, 0.05, limitPct,
    function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    function(v) limitPct = v; updateMarker() end)

local rdCard = new("Frame", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
}, pages.Speed)
round(rdCard, 8)
new("TextLabel", {
    Size = UDim2.new(0.62, -12, 0, 16), Position = UDim2.fromOffset(12, 6),
    BackgroundTransparency = 1, Text = "Speed bar (limit ikut Inf. Stamina)",
    TextColor3 = C.sub, Font = FONT, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
}, rdCard)
rdText = new("TextLabel", {
    Size = UDim2.new(0.38, -12, 0, 16), Position = UDim2.new(0.62, 0, 0, 6),
    BackgroundTransparency = 1, Text = "0 / 0", TextColor3 = C.accent,
    Font = FONT_B, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
}, rdCard)
local rdBar = new("Frame", {
    Size = UDim2.new(1, -24, 0, 8), Position = UDim2.fromOffset(12, 28),
    BackgroundColor3 = C.off, BorderSizePixel = 0,
}, rdCard)
round(rdBar, 4)
rdFill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0}, rdBar)
round(rdFill, 4)
rdMarker = new("Frame", {
    Size = UDim2.fromOffset(3, 16), AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(limitPct, 0.5), BackgroundColor3 = C.sub,
    BorderSizePixel = 0, ZIndex = 3,
}, rdBar)
updateMarker()

local function readoutStep()
    local maxS = (sprintCfg and tonumber(sprintCfg.CurrentMaxSpeed)) or 161.2
    local cur
    local st = capStates[1]
    if st and type(st.speed) == "number" then
        cur = st.speed
    else
        local hum = getHumanoid()
        local r = hum and hum.RootPart
        if r then
            local v = r.AssemblyLinearVelocity
            cur = Vector3.new(v.X, 0, v.Z).Magnitude
        end
    end
    cur = cur or 0
    local ratio = math.clamp(cur / maxS, 0, 1)
    rdFill.Size = UDim2.fromScale(ratio, 1)
    rdFill.BackgroundColor3 = (active.stam and ratio >= limitPct - 0.01) and C.danger or C.accent
    rdText.Text = string.format("%d / %d", math.floor(cur + 0.5), math.floor(limitPct * maxS + 0.5))
end
local setReadout = hook(RunService.RenderStepped, readoutStep)
function refreshReadout()
    setReadout(window.Visible and curTab == "Speed")
end

--// Cleanup (close / re-execute)
local function cleanup()
    setQTE(false)
    setStamina(false)
    setEasy(false)
    setSpeed(false)
    setReadout(false)
    if gui then gui:Destroy() end
    if env.__PanelCleanup == cleanup then env.__PanelCleanup = nil end
end
env.__PanelCleanup = cleanup
closeBtn.Activated:Connect(cleanup)

setSpeed(true)
setActive("speed", true)
selectTab(TABS[1])

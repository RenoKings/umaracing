--// Panel v19 — Presets · Easy Control · Stamina (Off/Semi/Infinite) · Speed Boost · Auto QTE · Visual
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G
local Terrain = workspace:FindFirstChildOfClass("Terrain")

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
local WIN_W, WIN_H = 260, 320

-- Preset (edit di sini kalau mau ganti nilai). sm: 0 = Off, 1 = Semi, 2 = Infinite
local PRESETS = {
    {name = "Safe",   easy = true, sm = 0, mult = 1.50, col = C.ok},
    {name = "Medium", easy = true, sm = 0, mult = 1.10, col = C.warn},
    {name = "Semi",   easy = true, sm = 1, mult = 1.10, col = C.accent},
    {name = "Aggro",  easy = true, sm = 2, mult = 1.25, col = C.danger}, -- cuma sesekali, rawan kedeteksi
}
-- Semi Infinity: stamina TIDAK beneran infinite, cuma boros lebih lambat + isi lebih cepat
local SEMI_USE, SEMI_REGEN = 0.45, 1.8
-- Auto Stamina QTE: detik "maju" dari titik bintang (kompensasi jalur input + urutan render)
local STAM_LEAD = 0.03
-- Auto Gate QTE: detik setelah lingkaran muncul (dump: 0.48-0.69s = Great, tengahnya ~0.58)
local GATE_T = 0.58

--// Settings (disimpan otomatis)
local FILE = "panel_settings.json"
local cfg = {
    easy = false, sm = 0, speed = false, mult = 1.1, qGate = false, qStam = false,
    light = false, tex = false, fx = false, tone = 0.6,
    preset = "",
    wx = -1, wy = -1,
}
pcall(function()
    if isfile and isfile(FILE) then
        local d = HttpService:JSONDecode(readfile(FILE))
        for k, def in pairs(cfg) do
            if type(d[k]) == type(def) then cfg[k] = d[k] end
        end
    end
end)
cfg.mult = math.clamp(cfg.mult, 1.1, 1.5)
cfg.tone = math.clamp(cfg.tone, 0.2, 1)
cfg.sm = math.clamp(math.floor(cfg.sm), 0, 2)
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

--// ======================= GAMEPLAY =======================
local speedMult = cfg.mult
local paceOrig, paceSet

-- Scan getgc (dipotong per frame, gak nge-freeze): config sprint (stamina) + tabel HUD (buat deteksi stamina turun)
local cfgs, vis = {}, {}
local scanAt, scanChar, scanGap, scanning = 0, nil, 3, false

local function lineAlive(t)
    local ln = rawget(t, "line")
    return typeof(ln) == "Instance" and ln:IsDescendantOf(playerGui)
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
            scanGap = (#c == 0 and #v == 0) and math.min(scanGap * 2, 30) or 3
            dbg("scan", #c, "cfg", #v, "hud")
        end
        scanAt = os.clock()
        scanning = false
    end)
end
local function ensure()
    local ch = player.Character
    if ch ~= scanChar then scanChar = ch; cfgs, vis = {}, {}; scanAt = 0; scanGap = 3 end
    if #cfgs == 0 and os.clock() - scanAt > scanGap then scan() end
end

-- Stamina: mode 0 = Off, 1 = Semi (boros lebih lambat + isi lebih cepat), 2 = Infinite
-- Config sprint ditemukan lewat getgc. Nilai asli dicatat per tabel (ratio Current/Base juga) supaya bisa dipulihkan.
local stO = setmetatable({}, {__mode = "k"})
local stamMode = 0
local function patchCfg(t, mode)
    local o = stO[t]
    if not o then
        local bu, cu = rawget(t, "BaseStaminaUseRate"), rawget(t, "CurrentStaminaUseRate")
        if type(bu) ~= "number" or type(cu) ~= "number" or bu == 0 then return end
        local br = rawget(t, "BaseStaminaRegenRate")
        o = {use = bu, ratio = cu / bu, regen = type(br) == "number" and br or nil}
        stO[t] = o
    end
    local ku = (mode == 2) and 0 or SEMI_USE
    local bu = o.use * ku
    if rawget(t, "BaseStaminaUseRate") ~= bu then pcall(rawset, t, "BaseStaminaUseRate", bu) end
    local cu = bu * o.ratio
    if rawget(t, "CurrentStaminaUseRate") ~= cu then pcall(rawset, t, "CurrentStaminaUseRate", cu) end
    if mode == 1 and o.regen then
        local r = o.regen * SEMI_REGEN
        if rawget(t, "BaseStaminaRegenRate") ~= r then pcall(rawset, t, "BaseStaminaRegenRate", r) end
    elseif mode == 2 and o.regen and rawget(t, "BaseStaminaRegenRate") ~= o.regen then
        pcall(rawset, t, "BaseStaminaRegenRate", o.regen)
    end
end
local function restoreCfg()
    for t, o in pairs(stO) do
        pcall(rawset, t, "BaseStaminaUseRate", o.use)
        pcall(rawset, t, "CurrentStaminaUseRate", o.use * o.ratio)
        if o.regen then pcall(rawset, t, "BaseStaminaRegenRate", o.regen) end
    end
    stO = setmetatable({}, {__mode = "k"})
end

-- Infinite saja: HUD (lastStamina) turun padahal sudah di-patch -> race baru / config baru -> scan ulang.
local drainT, drainGap = 0, 2
local function stamLow()
    for _, t in ipairs(vis) do
        local ls = rawget(t, "lastStamina")
        if type(ls) == "number" and ls >= 0 and ls < 0.9 and lineAlive(t) then return true end
    end
    return false
end
local leakAt = 0 -- terakhir server ngirim stamina < max padahal Infinite aktif
local stWatch, stConn, stamEvConn
local function watchStamina(st, mx)
    if stWatch == st then return end
    if stConn then stConn:Disconnect() end
    stWatch = st
    stConn = st:GetPropertyChangedSignal("Value"):Connect(function()
        if st.Value < mx.Value then st.Value = mx.Value end
    end)
end
local evGap = 1.5
local onStamEvent = safe(function(v)
    local info = player:FindFirstChild("Info")
    local mx = info and info:FindFirstChild("MaxStamina")
    if type(v) ~= "number" or not mx or v >= mx.Value - 1 then return end
    leakAt = os.clock()
    if os.clock() - scanAt > evGap then
        evGap = math.min(evGap * 2, 30)
        scan()
    end
end)
local stAcc, infoSt, infoMx = 0, nil, nil
local setStamLoop = hook(RunService.Heartbeat, function(dt)
    stAcc += dt
    if stAcc < 0.15 then return end
    dt, stAcc = stAcc, 0
    ensure()
    for i = 1, #cfgs do patchCfg(cfgs[i], stamMode) end
    if stamMode == 2 then
        if not (infoSt and infoSt.Parent and infoMx and infoMx.Parent) then
            local info = player:FindFirstChild("Info")
            infoSt = info and info:FindFirstChild("Stamina")
            infoMx = info and info:FindFirstChild("MaxStamina")
        end
        local st, mx = infoSt, infoMx
        if os.clock() - leakAt > 5 then evGap = 1.5 end
        if st and mx then
            watchStamina(st, mx)
            if st.Value < mx.Value then st.Value = mx.Value end
        end
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
    end
    if os.clock() - scanAt > 30 then scan() end
end)
local function setStamina(m)
    stamMode = m
    setStamLoop(m > 0)
    if m == 2 then
        if not stamEvConn then
            local rem = game:GetService("ReplicatedStorage"):FindFirstChild("remotes")
            local ev = rem and rem:FindFirstChild("UpdateClientStamina")
            if ev and ev:IsA("RemoteEvent") then stamEvConn = ev.OnClientEvent:Connect(onStamEvent) end
        end
    else
        if stamEvConn then stamEvConn:Disconnect(); stamEvConn = nil end
        if stConn then stConn:Disconnect(); stConn = nil; stWatch = nil end
        drainT, drainGap = 0, 2
    end
    if m == 0 then restoreCfg() end
end

-- Easy Control: karakter ngadep arah kamera
local easyStep = safe(function()
    local hum = getHumanoid()
    local root = hum and hum.Health > 0 and hum.RootPart
    if not root then return end
    local cam = workspace.CurrentCamera
    -- kamera cutscene / ulti biasanya bukan Custom
    if cam.CameraType ~= Enum.CameraType.Custom then
        if not hum.AutoRotate then hum.AutoRotate = true end
        return
    end
    local look = cam.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then return end
    flat = flat.Unit

    local v = root.AssemblyLinearVelocity
    local h = Vector3.new(v.X, 0, v.Z)
    local moving = h.Magnitude > 2
    -- Arah acuan = arah lari sekarang (kalau lagi lari) atau arah hadap karakter (kalau diam).
    -- Kamera nyimpang jauh dari acuan = Look Back / kamera ulti di belakang -> JANGAN diikutin.
    local ref
    if moving then
        ref = h.Unit
    else
        local rl = root.CFrame.LookVector
        ref = Vector3.new(rl.X, 0, rl.Z)
        if ref.Magnitude < 0.01 then return end
        ref = ref.Unit
    end
    if flat:Dot(ref) < 0.35 then
        if not hum.AutoRotate then hum.AutoRotate = true end
        return
    end

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
local paceAcc = 0
local setPaceLoop = hook(RunService.Heartbeat, function(dt)
    paceAcc += dt
    if paceAcc < 0.1 then return end
    paceAcc = 0
    local ch = player.Character
    local cur = ch and ch:GetAttribute("PaceSpeedMult")
    if cur == nil then return end
    if cur ~= paceSet then paceOrig = cur end
    if cur ~= speedMult then ch:SetAttribute("PaceSpeedMult", speedMult) end
    paceSet = speedMult
end)
local function setSpeed(on)
    setPaceLoop(on)
    if not on then
        local ch = player.Character
        if ch and paceOrig and paceSet then ch:SetAttribute("PaceSpeedMult", paceOrig) end
        paceSet = nil
    end
end

--// ======================= AUTO QTE =======================
-- Dua modul terpisah (toggle masing-masing). Event-driven: gak ada loop per-frame saat idle.
--  * Gate   : QTEGui.GateQTE muncul tiap beat (4x). Tap di tengah lingkaran GATE_T detik setelah muncul
--             (dump: 0.48-0.69s = Great). Pakai task.delay, nol biaya per-frame.
--  * Stamina: QTEGui.StaminaQTE. Pointer (Time) muter ±265°/s searah jarum jam; Star (anak Timeframe, dipasang
--             pakai Position lalu diputar bareng Timeframe) = titik Great (±10°). RenderStepped nyala HANYA selama
--             satu QTE hidup (~1.5 dtk), lalu putus lagi.
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")

local function centerOf(o) return o.AbsolutePosition + o.AbsoluteSize / 2 end
local function absRot(o)
    local ok, r = pcall(function() return o.AbsoluteRotation end)
    return (ok and r) or o.Rotation
end
local function newInput(pos)
    return {
        UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin,
        KeyCode = Enum.KeyCode.Unknown, Position = Vector3.new(pos.X, pos.Y, 0), Delta = Vector3.zero,
    }
end
local function guiInset()
    local ok, v = pcall(function() return GuiService:GetGuiInset() end)
    return (ok and v) or Vector2.zero
end

-- Hitung tap otomatis yang diterima game (ditampilkan di tab QTE)
local qCount, qLabel = {gate = 0, stam = 0}, {}

--// ---- Cara kirim input (dicoba berurutan, yang berhasil diingat) ----
-- Fire langsung connection QTEButton (jalur stamina QTE: "QTEButton press Touch")
local function fireButton(b)
    if not (b and getconnections) then return false end
    local any, inp = false, newInput(centerOf(b))
    for _, name in ipairs({"InputBegan", "Activated", "MouseButton1Down", "MouseButton1Click", "TouchTap"}) do
        local ok, cs = pcall(getconnections, b[name])
        if ok and cs then
            for _, c in ipairs(cs) do
                any = true
                pcall(function()
                    if name == "InputBegan" then c:Fire(inp, false)
                    elseif name == "Activated" then c:Fire(inp, 1)
                    else c:Fire() end
                end)
            end
        end
    end
    return any
end
-- Shotgun: fire semua handler UIS.InputBegan (Function-nya gak kebaca di Delta, jadi gak bisa difilter)
local function fireAllUis(pos)
    if not getconnections then return false end
    local ok, cs = pcall(getconnections, UIS.InputBegan)
    if not (ok and cs) then return false end
    local inp, any = newInput(pos), false
    for _, c in ipairs(cs) do
        any = true
        pcall(function() c:Fire(inp, false) end)
    end
    return any
end
local function vimTouch(x, y)
    VIM:SendTouchEvent(7, 0, x, y)
    task.wait(0.03)
    VIM:SendTouchEvent(7, 2, x, y)
    return true
end
local METHODS = {
    btn = function(qb) return fireButton(qb) end,
    uis = function(_, pos) return fireAllUis(pos) end,
    uisI = function(_, pos) -- sama seperti uis tapi posisi + inset (kalau game bandingin ke koordinat layar)
        local i = guiInset()
        if i.Magnitude < 1 then return false end
        return fireAllUis(pos + i)
    end,
    touch = function(_, pos) -- koordinat layar VIM = koordinat GUI + GuiInset
        local i = guiInset()
        return vimTouch(pos.X + i.X, pos.Y + i.Y)
    end,
    touch0 = function(_, pos) -- tanpa inset (dicoba cuma kalau inset <> 0)
        if guiInset().Magnitude < 1 then return false end
        return vimTouch(pos.X, pos.Y)
    end,
    mouse = function(_, pos)
        local i = guiInset()
        VIM:SendMouseButtonEvent(pos.X + i.X, pos.Y + i.Y, 0, true, game, 0)
        task.wait(0.03)
        VIM:SendMouseButtonEvent(pos.X + i.X, pos.Y + i.Y, 0, false, game, 0)
        return true
    end,
}
local ORDER = {
    gate = {"uis", "uisI", "touch", "touch0", "mouse", "btn"},
    stam = {"btn", "touch", "touch0", "uis"},
}
local bestM = {gate = 1, stam = 1}

-- "Diterima" = game nge-spawn fx_ring (di frame) / StaminaQTEState (di QTEGui) saat input masuk, atau frame diganti.
-- Dipantau lewat event (bukan polling) dan cuma jalan pas ngirim input.
local function press(frame, kind, pos)
    task.spawn(function()
        local qg = frame.Parent
        if not qg then return end
        local qb = playerGui:FindFirstChild("QTEButtonGui")
        qb = qb and qb:FindFirstChild("QTEButton")
        pos = pos or (qb and centerOf(qb)) or (workspace.CurrentCamera.ViewportSize / 2)

        local seen = false
        local function onAdd(ch)
            if ch.Name == "fx_ring" or ch.Name == "StaminaQTEState" then seen = true end
        end
        local c1, c2 = frame.ChildAdded:Connect(onAdd), qg.ChildAdded:Connect(onAdd)

        local order = ORDER[kind]
        local done = false
        for k = 0, #order - 1 do
            local i = (bestM[kind] - 1 + k) % #order + 1
            local ok, r = pcall(METHODS[order[i]], qb, pos)
            if ok and r then
                for _ = 1, 6 do
                    if seen or not frame.Parent then break end
                    task.wait()
                end
                if seen or not frame.Parent then
                    bestM[kind] = i
                    done = true
                    qCount[kind] += 1
                    local lb = qLabel[kind]
                    if lb then lb.Text = qCount[kind] .. " tap" end
                    dbg("press ok", kind, order[i])
                    break
                end
            end
        end
        c1:Disconnect()
        c2:Disconnect()
        if not done then dbg("press: semua cara gagal", kind) end
    end)
end

--// ---- Watcher: pantau QTEGui.ChildAdded, tanpa loop ----
-- Satu watcher per modul; QTEGui bisa di-recreate game, jadi tunggu + sambung ulang kalau perlu.
local function makeWatcher(onFrame)
    local alive, conns = false, {}
    local function disconnectAll()
        for _, c in ipairs(conns) do c:Disconnect() end
        table.clear(conns)
    end
    local function attach(qg)
        conns[#conns + 1] = qg.ChildAdded:Connect(function(ch)
            if alive then pcall(onFrame, ch) end
        end)
        conns[#conns + 1] = qg.AncestryChanged:Connect(function(_, parent)
            if parent == nil and alive then
                disconnectAll()
                task.spawn(function()
                    local ng = playerGui:WaitForChild("QTEGui", 30)
                    if ng and alive then attach(ng) end
                end)
            end
        end)
    end
    return function(on)
        if on == alive then return end
        alive = on
        if not on then disconnectAll(); return end
        task.spawn(function()
            local qg = playerGui:WaitForChild("QTEGui", 30)
            if qg and alive then attach(qg) end
        end)
    end
end

--// ---- Modul 1: Gate QTE ----
-- Titik tap = tengah lingkaran sebenarnya (median pusat child Background/Duration/Overlay/Input).
-- Frame GateQTE sendiri punya UIAspectRatioConstraint & ukuran {1,0},{1,0} -> pusat frame BUKAN pusat tombol.
local function gateTarget(f)
    local xs, ys = {}, {}
    for _, n in ipairs({"Background", "Duration", "Overlay", "Input"}) do
        local o = f:FindFirstChild(n)
        if o and o:IsA("GuiObject") and o.AbsoluteSize.X > 4 and o.AbsoluteSize.Y > 4 then
            local c = centerOf(o)
            xs[#xs + 1], ys[#ys + 1] = c.X, c.Y
        end
    end
    if #xs == 0 then return centerOf(f) end
    table.sort(xs); table.sort(ys)
    local m = (#xs + 1) // 2
    local x = (#xs % 2 == 1) and xs[m] or (xs[m] + xs[m + 1]) / 2
    local y = (#ys % 2 == 1) and ys[m] or (ys[m] + ys[m + 1]) / 2
    dbg("gate target", math.floor(x), math.floor(y), "frame", centerOf(f))
    return Vector2.new(x, y)
end

local gateSeen = setmetatable({}, {__mode = "k"})
local setGate = makeWatcher(function(f)
    if f.Name ~= "GateQTE" or not f:IsA("GuiButton") or gateSeen[f] then return end
    gateSeen[f] = true
    local t0 = os.clock()
    dbg("gate beat")
    task.delay(math.max(0, GATE_T - (os.clock() - t0)), function()
        if f.Parent then press(f, "gate", gateTarget(f)) end
    end)
end)

--// ---- Modul 2: Stamina QTE ----
local function dumpQte(frame)
    warn("[Panel] ---- dump", frame.Name, frame.AbsolutePosition, frame.AbsoluteSize)
    local base = #frame:GetFullName() + 2
    for _, o in ipairs(frame:GetDescendants()) do
        if o:IsA("GuiObject") then
            warn(string.format("[Panel] %s <%s> vis=%s rot=%.1f absRot=%.1f pos=(%d,%d) size=(%d,%d)",
                o:GetFullName():sub(base), o.ClassName, tostring(o.Visible), o.Rotation, absRot(o),
                o.AbsolutePosition.X, o.AbsolutePosition.Y, o.AbsoluteSize.X, o.AbsoluteSize.Y))
        end
    end
end

-- Satu sesi per frame, RenderStepped hidup cuma selama QTE.
-- Dibanding v18: tanpa jeda intro 0.25s, kecepatan pointer diukur dari jendela 0.2s (tanpa smoothing yang
-- bikin lag), sudut Star ikut diputar sesuai rotasi Timeframe (AbsolutePosition mengabaikan rotasi),
-- dan tap ditembakkan STAM_LEAD detik lebih awal buat nutup delay input.
local function runStamina(frame)
    local t0 = os.clock()
    local tf, tm, star
    local hist, unw, lastR = {}, 0, nil
    local conn, fired = nil, false
    local function stop()
        if conn then conn:Disconnect(); conn = nil end
    end
    conn = RunService.RenderStepped:Connect(function(dt)
        if fired then return stop() end
        if not frame.Parent then return stop() end
        local now = os.clock()
        if not star then
            tf, tm = frame:FindFirstChild("Timeframe"), frame:FindFirstChild("Time")
            star = tf and tf:FindFirstChild("Star")
            if not star then
                if now - t0 > 1 then stop() end
                return
            end
            dbg("qte start")
            if env.PanelDebug then dumpQte(frame) end
        end
        if not (tm and tm.Parent) then return stop() end

        local pr = absRot(tm)
        if lastR then unw += (pr - lastR + 540) % 360 - 180 end
        lastR = pr
        hist[#hist + 1] = {now, unw}
        while #hist > 2 and now - hist[1][1] > 0.2 do table.remove(hist, 1) end
        if #hist < 3 then return end
        local span = now - hist[1][1]
        if span < 0.04 then return end
        local rate = (unw - hist[1][2]) / span -- derajat/detik, bertanda
        if math.abs(rate) < 60 then return end
        local dir, spd = rate > 0 and 1 or -1, math.abs(rate)

        local v = centerOf(star) - centerOf(tf)
        if v.Magnitude < 1 then return end
        local target = math.deg(math.atan2(v.X, -v.Y))
        if env.PanelStarRot ~= false then target += absRot(tf) end
        local remain = ((target - pr) * dir) % 360
        if remain > 360 - spd * dt * 1.5 then remain -= 360 end
        local lead = env.PanelLead or STAM_LEAD
        if remain / spd <= lead + dt * 0.5 then
            fired = true
            stop()
            dbg("qte fire", string.format("rate=%.0f remain=%.1f", rate, remain))
            press(frame, "stam")
        end
    end)
    task.delay(4, stop)
end

local stamSeen = setmetatable({}, {__mode = "k"})
local setStam = makeWatcher(function(f)
    if f.Name ~= "StaminaQTE" or not f:IsA("GuiButton") or stamSeen[f] then return end
    stamSeen[f] = true
    runStamina(f)
end)

--// ======================= VISUAL =======================
local G = {light = false, tex = false, fx = false} -- state runtime

local function same(a, b)
    local ta = typeof(a)
    if ta == "number" then return type(b) == "number" and math.abs(a - b) < 1e-3 end
    if ta == "Color3" then
        return typeof(b) == "Color3" and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 2e-3
    end
    return a == b
end

-- 1) Soft Light & Color
-- softSet: nilai asli dicatat; kalau game ngubah nilainya (ganti map / cuaca) nilai asli baru dipakai lagi sebagai basis.
local soft = setmetatable({}, {__mode = "k"})
local function softSet(obj, prop, compute)
    local ok, cur = pcall(function() return obj[prop] end)
    if not ok then return end
    local per = soft[obj]
    if not per then per = {}; soft[obj] = per end
    local st = per[prop]
    if not st then st = {}; per[prop] = st end
    if st.set == nil or not same(cur, st.set) then st.orig = cur end
    local want = compute(st.orig)
    if not same(cur, want) then pcall(function() obj[prop] = want end) end
    st.set = want
end
local postOff = {}
local POST = {BloomEffect = true, SunRaysEffect = true, DepthOfFieldEffect = true, BlurEffect = true}
local GRAY, BLACK, WARM = Color3.fromRGB(128, 128, 128), Color3.new(0, 0, 0), Color3.fromRGB(255, 243, 226)

-- Lampu di map: Light instance diredupkan, part Neon dibikin polos, BillboardGui/ScreenGui "flare/glare/lens" dimatiin
local lights = {}
local neonOrig = setmetatable({}, {__mode = "k"})
local guiOff = {}
local function isFlareName(n)
    n = n:lower()
    return n:find("flare", 1, true) or n:find("glare", 1, true) or n:find("lens", 1, true)
end
local function lightTrack(d)
    if d.Name == "PanelSkyDome" then return end
    if d:IsA("Light") then
        lights[#lights + 1] = d
        local k = 1 - 0.9 * cfg.tone
        softSet(d, "Brightness", function(o) return o * k end)
    elseif d:IsA("BasePart") then
        if d.Material == Enum.Material.Neon and neonOrig[d] == nil then
            neonOrig[d] = true
            d.Material = Enum.Material.SmoothPlastic
        end
    else
        local c = d.ClassName
        if (c == "BillboardGui" or c == "SurfaceGui") and isFlareName(d.Name) and d.Enabled then
            guiOff[d] = true
            d.Enabled = false
        end
    end
end
local function dimLights(t)
    local k = 1 - 0.9 * t
    local j = 1
    for i = 1, #lights do
        local l = lights[i]
        if l.Parent then
            lights[j] = l
            j += 1
            softSet(l, "Brightness", function(o) return o * k end)
        end
    end
    for i = j, #lights do lights[i] = nil end
end

local function scanFx(e, t)
    local c = e.ClassName
    if POST[c] then
        if e.Enabled then postOff[e] = true; e.Enabled = false end
    elseif c == "Atmosphere" then
        softSet(e, "Glare", function() return 0 end)
        softSet(e, "Haze", function(o) return o * (1 - t) end)
        softSet(e, "Density", function(o) return o * (1 - 0.5 * t) end)
    elseif c == "ColorCorrectionEffect" and e.Name ~= "PanelTone" then
        softSet(e, "Brightness", function(o) return math.min(o, 0) end)
    elseif c == "Sky" then
        softSet(e, "CelestialBodiesShown", function() return false end)
        softSet(e, "StarCount", function() return 0 end)
    end
end

local worldSync, worldPass -- didefinisikan di bagian World

local lightN = 0
local function applyLight()
    local t = cfg.tone
    lightN += 1
    softSet(Lighting, "Brightness", function(o) return o * (1 - 0.35 * t) end)
    softSet(Lighting, "ExposureCompensation", function(o) return o - 0.4 * t end)
    softSet(Lighting, "GlobalShadows", function() return false end)
    softSet(Lighting, "EnvironmentSpecularScale", function(o) return o * (1 - t) end)
    softSet(Lighting, "EnvironmentDiffuseScale", function(o) return o * (1 - 0.5 * t) end)
    softSet(Lighting, "Ambient", function(o) return o:Lerp(GRAY, 0.5 * t) end)
    softSet(Lighting, "OutdoorAmbient", function(o) return o:Lerp(GRAY, 0.5 * t) end)
    softSet(Lighting, "ColorShift_Top", function(o) return o:Lerp(BLACK, t) end)
    softSet(Lighting, "ColorShift_Bottom", function(o) return o:Lerp(BLACK, t) end)

    for _, e in ipairs(Lighting:GetDescendants()) do scanFx(e, t) end
    local cam = workspace.CurrentCamera
    if cam then
        for _, e in ipairs(cam:GetChildren()) do scanFx(e, t) end
    end
    for _, g in ipairs(playerGui:GetChildren()) do
        if g:IsA("ScreenGui") and g.Name ~= "Panel" and g.Enabled and isFlareName(g.Name) then
            guiOff[g] = true
            g.Enabled = false
        end
    end
    if lightN % 3 == 1 then dimLights(t) end -- lampu: cek ulang tiap ~6 dtk (lampu baru langsung diredupkan saat muncul)

    local cc = Lighting:FindFirstChild("PanelTone")
    if not cc then cc = new("ColorCorrectionEffect", {Name = "PanelTone"}, Lighting) end
    cc.Saturation = -0.5 * t
    cc.Contrast = -0.12 * t
    cc.Brightness = -0.04 * t
    cc.TintColor = Color3.new(1, 1, 1):Lerp(WARM, t)
end
local function restoreLight()
    for obj, per in pairs(soft) do
        for prop, st in pairs(per) do
            if st.orig ~= nil then pcall(function() obj[prop] = st.orig end) end
        end
    end
    soft = setmetatable({}, {__mode = "k"})
    for e in pairs(postOff) do
        if e.Parent then pcall(function() e.Enabled = true end) end
    end
    postOff = {}
    for d in pairs(neonOrig) do
        if d.Parent then pcall(function() d.Material = Enum.Material.Neon end) end
    end
    neonOrig = setmetatable({}, {__mode = "k"})
    for g in pairs(guiOff) do
        if g.Parent then pcall(function() g.Enabled = true end) end
    end
    guiOff = {}
    lights = {}
    local cc = Lighting:FindFirstChild("PanelTone")
    if cc then cc:Destroy() end
end
-- Sky abu-abu: bola terbalik (mesh scale negatif) ngikut kamera, Neon = flat tanpa shading
local dome
local skyStep = safe(function()
    local cam = workspace.CurrentCamera
    if not (dome and cam) then return end
    if dome.Parent ~= cam then dome.Parent = cam end
    dome.CFrame = CFrame.new(cam.CFrame.Position)
end)
local function setSky(on)
    pcall(function() RunService:UnbindFromRenderStep("PanelSky") end)
    if on then
        if not dome then
            dome = new("Part", {
                Name = "PanelSkyDome",
                Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
                CastShadow = false, Locked = true,
                Size = Vector3.new(1, 1, 1),
                Material = Enum.Material.Neon,
                Color = Color3.fromRGB(128, 128, 128),
            })
            new("SpecialMesh", {MeshType = Enum.MeshType.Sphere, Scale = Vector3.new(-5000, 5000, 5000)}, dome)
        end
        RunService:BindToRenderStep("PanelSky", Enum.RenderPriority.Last.Value, skyStep)
    elseif dome then
        dome:Destroy()
        dome = nil
    end
end
local lightAcc = 0
local lightLoop = hook(RunService.Heartbeat, function(dt)
    lightAcc += dt
    if lightAcc < 2 then return end
    lightAcc = 0
    applyLight()
end)
local function setLight(on)
    G.light = on
    setSky(on)
    lightLoop(on)
    if on then applyLight() else restoreLight() end
    worldSync()
    worldPass()
end

-- 2) Flat Textures (material polos, tanpa decal/texture/PBR, grass terrain off, quality turun)
-- 3) Hide Effects (partikel, trail, beam, api, asap)
local partOrig = setmetatable({}, {__mode = "k"})
local decOrig = setmetatable({}, {__mode = "k"})
local fxOrig = setmetatable({}, {__mode = "k"})
local saList = {}
local qOrig, decoOrig

local function flatten(d)
    if d:IsA("BasePart") then
        if d == Terrain or d.Name == "PanelSkyDome" then return end
        if d.Material ~= Enum.Material.SmoothPlastic or d.Reflectance ~= 0 then
            if not partOrig[d] then partOrig[d] = {d.Material, d.Reflectance} end
            d.Material = Enum.Material.SmoothPlastic
            d.Reflectance = 0
        end
    elseif d:IsA("Decal") then -- Texture turunan Decal
        if d.Transparency < 1 and decOrig[d] == nil then
            local m = d:FindFirstAncestorOfClass("Model")
            if not (m and m:FindFirstChildOfClass("Humanoid")) then -- wajah karakter dibiarin
                decOrig[d] = d.Transparency
                d.Transparency = 1
            end
        end
    elseif d:IsA("SurfaceAppearance") then
        saList[#saList + 1] = {d, d.Parent}
        d.Parent = nil
    end
end
local function killFx(d)
    local c = d.ClassName
    if c == "ParticleEmitter" then
        if fxOrig[d] == nil then
            fxOrig[d] = {d.Enabled, d.Lifetime}
            d.Enabled = false
            d.Lifetime = NumberRange.new(0)
        end
    elseif c == "Trail" or c == "Beam" or c == "Smoke" or c == "Fire" or c == "Sparkles" then
        if fxOrig[d] == nil and d.Enabled then
            fxOrig[d] = {true}
            d.Enabled = false
        end
    end
end

local worldConn, worldToken = nil, 0
local handle = safe(function(d)
    if G.tex then flatten(d) end
    if G.fx then killFx(d) end
    if G.light then lightTrack(d) end
end)
function worldSync()
    local need = G.tex or G.fx or G.light
    if need and not worldConn then
        worldConn = workspace.DescendantAdded:Connect(handle)
    elseif not need and worldConn then
        worldConn:Disconnect()
        worldConn = nil
    end
end
function worldPass()
    worldToken += 1
    local my = worldToken
    if not (G.tex or G.fx or G.light) then return end
    task.spawn(function()
        local all = workspace:GetDescendants()
        for i = 1, #all do
            if my ~= worldToken then return end
            handle(all[i])
            if i % 600 == 0 then task.wait() end
        end
    end)
end

local function getDeco()
    if not Terrain then return end
    if gethiddenproperty then
        local ok, v = pcall(gethiddenproperty, Terrain, "Decoration")
        if ok then return v end
    end
    local ok, v = pcall(function() return Terrain.Decoration end)
    if ok then return v end
end
local function setDeco(v)
    if not Terrain then return end
    if sethiddenproperty and pcall(sethiddenproperty, Terrain, "Decoration", v) then return end
    pcall(function() Terrain.Decoration = v end)
end

local function setTex(on)
    G.tex = on
    worldToken += 1
    if on then
        if decoOrig == nil then decoOrig = getDeco() end
        setDeco(false)
        if qOrig == nil then pcall(function() qOrig = settings().Rendering.QualityLevel end) end
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
    else
        if decoOrig ~= nil then setDeco(decoOrig); decoOrig = nil end
        if qOrig ~= nil then
            local q = qOrig
            pcall(function() settings().Rendering.QualityLevel = q end)
            qOrig = nil
        end
        for p, o in pairs(partOrig) do
            if p.Parent then pcall(function() p.Material = o[1]; p.Reflectance = o[2] end) end
        end
        partOrig = setmetatable({}, {__mode = "k"})
        for d, tr in pairs(decOrig) do
            if d.Parent then pcall(function() d.Transparency = tr end) end
        end
        decOrig = setmetatable({}, {__mode = "k"})
        for _, e in ipairs(saList) do
            if e[2] and e[2].Parent then pcall(function() e[1].Parent = e[2] end) end
        end
        saList = {}
    end
    worldSync()
    worldPass()
end
local function setFx(on)
    G.fx = on
    worldToken += 1
    if not on then
        for d, o in pairs(fxOrig) do
            if d.Parent then
                pcall(function()
                    d.Enabled = o[1]
                    if o[2] then d.Lifetime = o[2] end
                end)
            end
        end
        fxOrig = setmetatable({}, {__mode = "k"})
    end
    worldSync()
    worldPass()
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
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0.02,
    BorderSizePixel = 0,
}, gui)
round(window, 14)
new("UIStroke", {Color = C.stroke, Thickness = 1}, window)
local winScale = new("UIScale", {Scale = 1}, window)
new("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(24, 24, 32), Color3.fromRGB(13, 13, 18)),
    Rotation = 90,
}, window)
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

local function draggable(handle_, target, onTap, onMoved)
    handle_.InputBegan:Connect(function(input)
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

-- Header: logo + judul + minimize + close
local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 36),
    BackgroundTransparency = 1,
    Active = true,
}, window)
draggable(header, window, nil, function()
    cfg.wx, cfg.wy = window.Position.X.Offset, window.Position.Y.Offset
    save()
end)
draggable(bubble, bubble, restore)

local closeBtn
do
    local logo = new("Frame", {
        Size = UDim2.fromOffset(20, 20),
        Position = UDim2.fromOffset(12, 8),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, header)
    round(logo, 6)
    new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 45}, logo)
    new("TextLabel", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "P",
        TextColor3 = Color3.new(1, 1, 1), Font = FONT_B, TextSize = 13,
    }, logo)
    new("TextLabel", {
        Size = UDim2.fromOffset(50, 36), Position = UDim2.fromOffset(38, 0), BackgroundTransparency = 1,
        Text = "Panel", TextColor3 = C.text, Font = FONT_B, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    local ver = new("TextLabel", {
        Size = UDim2.fromOffset(30, 16), Position = UDim2.fromOffset(86, 10),
        BackgroundColor3 = C.surface, BorderSizePixel = 0,
        Text = "v18", TextColor3 = C.sub, Font = FONT, TextSize = 10,
    }, header)
    round(ver, 8)

    local function headerBtn(text, x, hoverColor)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(24, 24),
            Position = UDim2.new(1, x, 0, 6),
            BackgroundColor3 = C.surface,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = text,
            TextColor3 = C.sub,
            Font = FONT_B,
            TextSize = 16,
        }, header)
        round(b, 8)
        b.MouseEnter:Connect(function() ease(b, {TextColor3 = hoverColor}) end)
        b.MouseLeave:Connect(function() ease(b, {TextColor3 = C.sub}) end)
        b.MouseButton1Down:Connect(function() b.BackgroundColor3 = C.press end)
        b.MouseButton1Up:Connect(function() b.BackgroundColor3 = C.surface end)
        return b
    end
    headerBtn("–", -58, C.text).Activated:Connect(minimize)
    closeBtn = headerBtn("×", -30, C.danger)
end

-- Tabs (indikator geser) + pages
local TABS = {"Main", "QTE", "Visual"}
local pages, tabBtns = {}, {}
local indicator
local function selectTab(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for i, n in ipairs(TABS) do
        local on = (n == name)
        tabBtns[n].TextColor3 = on and Color3.new(1, 1, 1) or C.sub
        if on and indicator then
            ease(indicator, {Position = UDim2.new((i - 1) / #TABS, 3, 0, 3)})
        end
    end
end
do
    local tabBar = new("Frame", {
        Size = UDim2.new(1, -20, 0, 28),
        Position = UDim2.fromOffset(10, 40),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, window)
    round(tabBar, 9)
    new("UIStroke", {Color = C.stroke, Thickness = 1}, tabBar)
    indicator = new("Frame", {
        Size = UDim2.new(1 / #TABS, -6, 1, -6),
        Position = UDim2.new(0, 3, 0, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, tabBar)
    round(indicator, 7)
    new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2), Rotation = 20}, indicator)

    local content = new("Frame", {
        Size = UDim2.new(1, 0, 1, -102),
        Position = UDim2.fromOffset(0, 76),
        BackgroundTransparency = 1,
    }, window)
    for i, name in ipairs(TABS) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / #TABS, 0, 1, 0),
            Position = UDim2.new((i - 1) / #TABS, 0, 0, 0),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = name,
            TextColor3 = C.sub,
            Font = FONT_B,
            TextSize = 12,
            ZIndex = 2,
        }, tabBar)
        tabBtns[name] = b
        b.Activated:Connect(function() selectTab(name) end)

        local pg = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false}, content)
        new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2)}, pg)
        new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
        pages[name] = pg
    end
end

--// Komponen: card (toggle + slider opsional di dalamnya)
local UI = {}

function UI.card(parent, h)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, parent)
    round(card, 10)
    local stroke = new("UIStroke", {Color = C.stroke, Thickness = 1}, card)
    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 0, 18),
        Position = UDim2.fromOffset(0, 8),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, card)
    round(bar, 2)
    return card, stroke, bar
end

-- opts: hint (teks kecil), counter ("gate"/"stam" = jumlah tap otomatis), extra (tinggi tambahan buat slider)
-- return: card, tinggi baris (y awal slider)
function UI.toggle(parent, text, init, onChange, opts)
    opts = opts or {}
    local on = init == true
    local rowH = opts.hint and 40 or 34
    local card, stroke, bar = UI.card(parent, rowH + (opts.extra or 0))
    bar.Size = UDim2.new(0, 3, 0, rowH - 16)
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, rowH),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "",
    }, card)
    local titleW = opts.counter and -120 or -64
    new("TextLabel", {
        Size = UDim2.new(1, titleW, 0, opts.hint and 18 or rowH),
        Position = UDim2.fromOffset(14, opts.hint and 5 or 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    if opts.hint then
        new("TextLabel", {
            Size = UDim2.new(1, titleW, 0, 12),
            Position = UDim2.fromOffset(14, 22),
            BackgroundTransparency = 1,
            Text = opts.hint,
            TextColor3 = C.sub,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, row)
    end
    if opts.counter then
        qLabel[opts.counter] = new("TextLabel", {
            Size = UDim2.fromOffset(54, 14),
            Position = UDim2.new(1, -110, 0, (rowH - 14) / 2),
            BackgroundTransparency = 1,
            Text = qCount[opts.counter] .. " tap",
            TextColor3 = C.sub,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)
    end
    local track = new("Frame", {
        Size = UDim2.fromOffset(36, 20),
        Position = UDim2.new(1, -50, 0, (rowH - 20) / 2),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, row)
    round(track, 10)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    round(knob, 7)

    local function paint(animate)
        local col = on and C.accent or C.off
        local props = {
            {track, {BackgroundColor3 = col}},
            {knob, {Position = on and UDim2.fromOffset(19, 3) or UDim2.fromOffset(3, 3)}},
            {bar, {BackgroundColor3 = col}},
            {stroke, {Color = on and C.accent or C.stroke, Transparency = on and 0.55 or 0}},
        }
        for _, p in ipairs(props) do
            if animate then ease(p[1], p[2]) else for k, v in pairs(p[2]) do p[1][k] = v end end
        end
    end
    paint(false)

    row.MouseButton1Down:Connect(function() card.BackgroundColor3 = C.press end)
    row.MouseButton1Up:Connect(function() card.BackgroundColor3 = C.surface end)
    row.MouseLeave:Connect(function() card.BackgroundColor3 = C.surface end)
    row.Activated:Connect(function()
        on = not on
        paint(true)
        onChange(on)
    end)
    local function set(v)
        v = v == true
        if v == on then return end
        on = v
        paint(true)
        onChange(on)
    end
    return card, rowH, set
end

-- Slider di dalam card (tinggi 40) mulai dari y
function UI.slider(card, y, label, MIN, MAX, STEP, init, fmt, onChange)
    local box = new("Frame", {
        Size = UDim2.new(1, 0, 0, 40),
        Position = UDim2.fromOffset(0, y),
        BackgroundTransparency = 1,
    }, card)
    new("Frame", {
        Size = UDim2.new(1, -28, 0, 1),
        Position = UDim2.fromOffset(14, 0),
        BackgroundColor3 = C.stroke,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
    }, box)
    new("TextLabel", {
        Size = UDim2.new(1, -86, 0, 16),
        Position = UDim2.fromOffset(14, 5),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, box)
    local chip = new("TextLabel", {
        Size = UDim2.fromOffset(56, 16),
        Position = UDim2.new(1, -70, 0, 5),
        BackgroundColor3 = C.press,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = C.accent,
        Font = FONT_B,
        TextSize = 11,
    }, box)
    round(chip, 8)
    local hit = new("Frame", {
        Size = UDim2.new(1, -28, 0, 16),
        Position = UDim2.fromOffset(14, 22),
        BackgroundTransparency = 1,
        Active = true,
    }, box)
    local bar = new("Frame", {
        Size = UDim2.new(1, 0, 0, 5),
        Position = UDim2.new(0, 0, 0.5, -2),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, hit)
    round(bar, 3)
    local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0}, bar)
    round(fill, 3)
    new("UIGradient", {Color = ColorSequence.new(C.accent, C.accent2)}, fill)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(14, 14),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, bar)
    round(knob, 7)
    new("UIStroke", {Color = C.accent, Thickness = 2}, knob)
    local knobScale = new("UIScale", {Scale = 1}, knob)

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
        chip.Text = fmt(m)
        onChange(m)
    end
    local function fromInput(input)
        local r = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
        setVal(MIN + math.clamp(r, 0, 1) * (MAX - MIN))
    end
    setVal(init)
    local function setExt(v) setVal(v) end

    hit.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        fromInput(input)
        ease(knobScale, {Scale = 1.25})
        local cMove, cEnd
        cMove = UIS.InputChanged:Connect(function(i)
            if isMove(i) then fromInput(i) end
        end)
        cEnd = UIS.InputEnded:Connect(function(i)
            if isPointer(i) then
                cMove:Disconnect()
                cEnd:Disconnect()
                ease(knobScale, {Scale = 1})
            end
        end)
    end)
    return setExt
end

local paintPresets -- didefinisikan di tab Main
local function apply(key, on, setter)
    cfg[key] = on
    setActive(key, on)
    setter(on)
    save()
end
local applyingPreset = false
local function manual() -- perubahan manual = bukan preset lagi
    if applyingPreset or cfg.preset == "" then return end
    cfg.preset = ""
    save()
    if paintPresets then paintPresets() end
end

-- Tab Main
local setEasyUI, setSpeedUI, setMultUI, paintStam
local stamBtns = {}
local presetBtns = {}

local function applyStam(m)
    cfg.sm = m
    setActive("stam", m > 0)
    setStamina(m)
    save()
    if paintStam then paintStam() end
end

-- Baris preset (Safe / Medium / Semi / Aggro)
do
    local row = new("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 0}, pages.Main)
    local n = #PRESETS
    for i, p in ipairs(PRESETS) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / n, -4, 1, 0),
            Position = UDim2.new((i - 1) / n, 2, 0, 0),
            BackgroundColor3 = C.surface,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = p.name,
            TextColor3 = C.sub,
            Font = FONT_B,
            TextSize = 11,
        }, row)
        round(b, 8)
        local st = new("UIStroke", {Color = C.stroke, Thickness = 1}, b)
        presetBtns[p.name] = {b, st, p}
        b.Activated:Connect(function()
            applyingPreset = true
            cfg.preset = p.name
            if setEasyUI then setEasyUI(p.easy) end
            applyStam(p.sm)
            if setMultUI then setMultUI(p.mult) end
            if setSpeedUI then setSpeedUI(true) end
            applyingPreset = false
            save()
            paintPresets()
            pop(winScale)
        end)
    end
    function paintPresets()
        for name, e in pairs(presetBtns) do
            local on = (cfg.preset == name)
            ease(e[1], {TextColor3 = on and Color3.new(1, 1, 1) or C.sub, BackgroundColor3 = on and C.press or C.surface})
            ease(e[2], {Color = on and e[3].col or C.stroke})
        end
    end
    paintPresets()
end

do
    local _, _, set = UI.toggle(pages.Main, "Easy Control", cfg.easy, function(v) apply("easy", v, setEasy); manual() end)
    setEasyUI = set
end

-- Stamina: Off / Semi / Infinite
do
    local card, stroke, bar = UI.card(pages.Main, 56)
    new("TextLabel", {
        Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 4), BackgroundTransparency = 1,
        Text = "Stamina", TextColor3 = C.text, Font = FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local modes = {{"Off", 0}, {"Semi", 1}, {"Infinite", 2}}
    for i, m in ipairs(modes) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / 3, -8, 0, 22),
            Position = UDim2.new((i - 1) / 3, 6 + (i - 1) * 0, 0, 28),
            BackgroundColor3 = C.off,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = m[1],
            TextColor3 = C.sub,
            Font = FONT_B,
            TextSize = 11,
        }, card)
        round(b, 7)
        stamBtns[m[2]] = b
        b.Activated:Connect(function()
            if cfg.sm == m[2] then return end
            applyStam(m[2])
            manual()
        end)
    end
    function paintStam()
        for k, b in pairs(stamBtns) do
            local on = cfg.sm == k
            local col = (k == 2) and C.danger or C.accent
            ease(b, {BackgroundColor3 = on and (k == 0 and C.press or col) or C.off, TextColor3 = on and Color3.new(1, 1, 1) or C.sub})
        end
        ease(bar, {BackgroundColor3 = cfg.sm == 0 and C.off or (cfg.sm == 2 and C.danger or C.accent)})
        ease(stroke, {Color = cfg.sm == 0 and C.stroke or (cfg.sm == 2 and C.danger or C.accent), Transparency = cfg.sm == 0 and 0 or 0.55})
    end
    bar.Size = UDim2.new(0, 3, 0, 40)
    paintStam()
end

do
    local card, y, set = UI.toggle(pages.Main, "Speed Boost", cfg.speed, function(v) apply("speed", v, setSpeed); manual() end, {extra = 40})
    setSpeedUI = set
    setMultUI = UI.slider(card, y, "Multiplier", 1.1, 1.5, 0.05, cfg.mult,
        function(v) return string.format("%.2fx", v) end,
        function(v)
            speedMult = v
            if v ~= cfg.mult then cfg.mult = v; save(); manual() end
        end)
end

-- Tab QTE (dua modul terpisah, timing otomatis)
do
    UI.toggle(pages.QTE, "Auto Gate QTE", cfg.qGate, function(v) apply("qGate", v, setGate) end,
        {hint = "Tap tengah lingkaran gate", counter = "gate"})
    UI.toggle(pages.QTE, "Auto Stamina QTE", cfg.qStam, function(v) apply("qStam", v, setStam) end,
        {hint = "Tap pas pointer kena bintang", counter = "stam"})
end

-- Tab Visual
do
    local card, y = UI.toggle(pages.Visual, "Soft Light & Color", cfg.light, function(v) apply("light", v, setLight) end, {extra = 40})
    UI.slider(card, y, "Tone (tinggi = lebih datar)", 0.2, 1, 0.05, cfg.tone,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        function(v)
            cfg.tone = v
            save()
            if G.light then lightAcc = 2; lightN = 0 end -- diterapkan di tick berikutnya (hemat)
        end)
end
UI.toggle(pages.Visual, "Flat Textures", cfg.tex, function(v) apply("tex", v, setTex) end)
UI.toggle(pages.Visual, "Hide Effects", cfg.fx, function(v) apply("fx", v, setFx) end)

-- Status: hijau = nempel di game, kuning = aktif tapi belum ketemu (lobby / race belum mulai), merah = bocor, abu = off
local dotStam, dotQte, dotVis
do
    local footer = new("Frame", {
        Size = UDim2.new(1, -20, 0, 18),
        Position = UDim2.new(0, 10, 1, -24),
        BackgroundTransparency = 1,
    }, window)
    new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        Position = UDim2.fromOffset(0, -4),
        BackgroundColor3 = C.stroke,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
    }, footer)
    local function statusItem(text, x)
        local d = new("Frame", {
            Size = UDim2.fromOffset(7, 7),
            Position = UDim2.new(0, x, 0.5, -3),
            BackgroundColor3 = C.off,
            BorderSizePixel = 0,
        }, footer)
        round(d, 4)
        new("TextLabel", {
            Size = UDim2.fromOffset(60, 16),
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
    dotStam = statusItem("Stamina", 2)
    dotQte = statusItem("QTE", 82)
    dotVis = statusItem("Visual", 140)
end
local function refreshStatus()
    dotStam.BackgroundColor3 = (cfg.sm == 0) and C.off
        or (cfg.sm == 1 and C.ok)
        or ((#cfgs == 0) and C.warn)
        or ((os.clock() - leakAt < 3) and C.danger)
        or C.ok
    dotQte.BackgroundColor3 = (cfg.qGate or cfg.qStam) and C.ok or C.off
    dotVis.BackgroundColor3 = (cfg.light or cfg.tex or cfg.fx) and C.ok or C.off
end
task.spawn(function()
    while gui.Parent do
        if window.Visible then pcall(refreshStatus) end
        task.wait(1)
    end
end)

--// Cleanup (close / re-execute): semua dikembalikan ke aslinya
local function cleanup()
    setStamina(0)
    setEasy(false)
    setSpeed(false)
    setGate(false)
    setStam(false)
    setLight(false)
    setTex(false)
    setFx(false)
    if gui then gui:Destroy() end
    if env.__PanelCleanup == cleanup then env.__PanelCleanup = nil end
end
env.__PanelCleanup = cleanup
closeBtn.Activated:Connect(cleanup)

-- Terapkan setting tersimpan
if cfg.easy then setActive("easy", true); setEasy(true) end
if cfg.sm > 0 then setActive("stam", true); setStamina(cfg.sm) end
if cfg.speed then setActive("speed", true); setSpeed(true) end
if cfg.qGate then setActive("qGate", true); setGate(true) end
if cfg.qStam then setActive("qStam", true); setStam(true) end
if cfg.light then setActive("light", true); setLight(true) end
if cfg.tex then setActive("tex", true); setTex(true) end
if cfg.fx then setActive("fx", true); setFx(true) end
selectTab(TABS[1])

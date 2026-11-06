--// Panel v21 — Presets · Easy Control · Stamina (Off/Semi/Inf) · Speed Boost · Auto QTE · Visual
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
local WIN_W = 264
local _vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 400)
local WIN_H = math.clamp(math.floor(_vp.Y) - 28, 250, 344)

--// Settings (disimpan otomatis)
local FILE = "panel_settings.json"
local cfg = {
    easy = false, stamMode = "off", speed = false, mult = 1.1, qStam = false, preset = "",
    light = false, tex = false, fx = false, tone = 0.6,
    wx = -1, wy = -1,
}
pcall(function()
    if isfile and isfile(FILE) then
        local d = HttpService:JSONDecode(readfile(FILE))
        for k, def in pairs(cfg) do
            if type(d[k]) == type(def) then cfg[k] = d[k] end
        end
        if d.stamMode == nil and d.stam == true then cfg.stamMode = "inf" end -- migrasi v18
    end
end)
if cfg.stamMode ~= "semi" and cfg.stamMode ~= "inf" then cfg.stamMode = "off" end
cfg.mult = math.clamp(cfg.mult, 1.05, 1.5)
cfg.tone = math.clamp(cfg.tone, 0.2, 1)
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

-- Stamina, 3 mode:
--  off  : normal
--  semi : BUKAN infinity. Pemakaian jadi SEMI_USE x, isi ulang jadi SEMI_REGEN x (cuma patch config sprint lokal,
--         nilai stamina server gak disentuh) -> paling aman
--  inf  : pemakaian 0 + nilai stamina dikunci max (risiko tinggi)
local SEMI_USE, SEMI_REGEN = 0.30, 1.8
local DEF_USE = 35
local stamMode = "off"
local origCfg = setmetatable({}, {__mode = "k"})
local function rememberCfg(t)
    local o = origCfg[t]
    if not o then
        local u, c, r = rawget(t, "BaseStaminaUseRate"), rawget(t, "CurrentStaminaUseRate"), rawget(t, "BaseStaminaRegenRate")
        if type(u) ~= "number" or u <= 0 then u = DEF_USE end
        if type(c) ~= "number" or c <= 0 then c = u * 1.1 end
        o = {use = u, cur = c, regen = (type(r) == "number" and r > 0) and r or nil}
        origCfg[t] = o
    end
    return o
end
local function restoreCfgs()
    for t, o in pairs(origCfg) do
        pcall(rawset, t, "BaseStaminaUseRate", o.use)
        pcall(rawset, t, "CurrentStaminaUseRate", o.cur)
        if o.regen then pcall(rawset, t, "BaseStaminaRegenRate", o.regen) end
    end
end

local drainT, drainGap = 0, 2
local function stamLow()
    for _, t in ipairs(vis) do
        local ls = rawget(t, "lastStamina")
        if type(ls) == "number" and ls >= 0 and ls < 0.9 and lineAlive(t) then return true end
    end
    return false
end
local leakAt = 0 -- terakhir server ngirim stamina < max padahal mode inf aktif
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
    local mode = stamMode
    for i = 1, #cfgs do
        local t = cfgs[i]
        local o = rememberCfg(t)
        if mode == "inf" then
            if rawget(t, "BaseStaminaUseRate") ~= 0 or rawget(t, "CurrentStaminaUseRate") ~= 0 then
                pcall(rawset, t, "BaseStaminaUseRate", 0)
                pcall(rawset, t, "CurrentStaminaUseRate", 0)
            end
        elseif mode == "semi" then
            local base, cap = o.use * SEMI_USE, o.cur * SEMI_USE
            if rawget(t, "BaseStaminaUseRate") ~= base then pcall(rawset, t, "BaseStaminaUseRate", base) end
            local c = rawget(t, "CurrentStaminaUseRate")
            if type(c) == "number" and c > cap then pcall(rawset, t, "CurrentStaminaUseRate", cap) end
            if o.regen then
                local r = o.regen * SEMI_REGEN
                if rawget(t, "BaseStaminaRegenRate") ~= r then pcall(rawset, t, "BaseStaminaRegenRate", r) end
            end
        end
    end

    if mode == "inf" then
        if not (infoSt and infoSt.Parent and infoMx and infoMx.Parent) then
            local info = player:FindFirstChild("Info")
            infoSt = info and info:FindFirstChild("Stamina")
            infoMx = info and info:FindFirstChild("MaxStamina")
        end
        if os.clock() - leakAt > 5 then evGap = 1.5 end
        if infoSt and infoMx then
            watchStamina(infoSt, infoMx)
            if infoSt.Value < infoMx.Value then infoSt.Value = infoMx.Value end
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
    if os.clock() - scanAt > (mode == "semi" and 15 or 30) then scan() end
end)
-- Semi: stamina "virtual". Server ngirim nilai ABSOLUT lewat UpdateClientStamina (~10x/dtk), jadi refund relatif ke
-- nilai Info.Stamina yang kita tulis sendiri gak bakal nahan (ketimpa nilai server tiap update).
-- Di sini selisih antar nilai server (bukan nilai yang kita tulis) diskalakan: turun x SEMI_USE, naik kecil x SEMI_REGEN,
-- lalu hasilnya ditulis ke Info.Stamina tiap frame (di atas nilai server, gak pernah ngunci penuh).
local semiV, semiRaw, semiConn
local function semiRemote(v)
    if type(v) ~= "number" then return end
    local info = player:FindFirstChild("Info")
    local mx = info and info:FindFirstChild("MaxStamina")
    local m = mx and mx.Value or 150
    if semiV == nil or semiRaw == nil then semiV, semiRaw = v, v; return end
    local d = v - semiRaw
    semiRaw = v
    if d < 0 then
        semiV += d * SEMI_USE
    elseif d > 0 then
        semiV += d * ((d <= 6) and SEMI_REGEN or 1) -- isi kecil = regen biasa (dipercepat); loncatan besar = bonus/zone, apa adanya
    end
    semiV = math.clamp(math.max(semiV, v), 0, m)
    if env.PanelDebug then dbg("semi raw", v, "virtual", math.floor(semiV + 0.5)) end
end
local semiRemoteSafe = safe(semiRemote)
local semiStep = safe(function()
    if semiV == nil then return end
    local info = player:FindFirstChild("Info")
    local st = info and info:FindFirstChild("Stamina")
    if not st then return end
    local nv = math.floor(semiV + 0.5)
    if st.Value ~= nv then st.Value = nv end
end)
local function setSemi(on)
    pcall(function() RunService:UnbindFromRenderStep("PanelSemi") end)
    if semiConn then semiConn:Disconnect(); semiConn = nil end
    semiV, semiRaw = nil, nil
    if not on then return end
    local rem = game:GetService("ReplicatedStorage"):FindFirstChild("remotes")
    local ev = rem and rem:FindFirstChild("UpdateClientStamina")
    if ev and ev:IsA("RemoteEvent") then semiConn = ev.OnClientEvent:Connect(semiRemoteSafe) end
    local info = player:FindFirstChild("Info")
    local st = info and info:FindFirstChild("Stamina")
    if st then semiV, semiRaw = st.Value, st.Value end
    RunService:BindToRenderStep("PanelSemi", Enum.RenderPriority.Last.Value, semiStep)
end
local function setStamMode(mode)
    if mode ~= "semi" and mode ~= "inf" then mode = "off" end
    if mode == stamMode then return end
    stamMode = mode
    restoreCfgs()
    if stConn then stConn:Disconnect(); stConn = nil; stWatch = nil end
    if stamEvConn then stamEvConn:Disconnect(); stamEvConn = nil end
    drainT, drainGap, evGap = 0, 2, 1.5
    setStamLoop(mode ~= "off")
    setSemi(mode == "semi")
    if mode == "inf" then
        local rem = game:GetService("ReplicatedStorage"):FindFirstChild("remotes")
        local ev = rem and rem:FindFirstChild("UpdateClientStamina")
        if ev and ev:IsA("RemoteEvent") then stamEvConn = ev.OnClientEvent:Connect(onStamEvent) end
    end
    stAcc = 1 -- langsung patch di tick berikutnya
end

-- Easy Control: karakter ngadep arah kamera.
-- Gak ngapa-ngapain (AutoRotate dibalikin) kalau: kamera bukan Custom / subject bukan karakter (cutscene, ulti),
-- kamera ada DI DEPAN arah hadap (cinematic / look back), atau baru selesai cinematic (settle 1 dtk).
-- Rotasi di-smooth (bukan snap) biar gak kelihatan kayak lock.
local EASY_SETTLE = 1.0
local easyHold = 0
local function easyRelease(hum)
    if hum and not hum.AutoRotate then hum.AutoRotate = true end
end
local easyStep = safe(function(dt)
    local hum = getHumanoid()
    local ch = player.Character
    local root = hum and hum.Health > 0 and hum.RootPart
    if not root then return end
    local now = os.clock()
    local cam = workspace.CurrentCamera
    if not cam then return end

    local subj = cam.CameraSubject
    local subjOk = subj == hum or (typeof(subj) == "Instance" and ch ~= nil and subj:IsDescendantOf(ch))
    if cam.CameraType ~= Enum.CameraType.Custom or not subjOk or player:GetAttribute("MVPCutscenePlaying") == true then
        easyHold = now + EASY_SETTLE
        easyRelease(hum)
        return
    end
    if now < easyHold then
        easyRelease(hum)
        return
    end

    local look = cam.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.01 then return end
    flat = flat.Unit

    local v = root.AssemblyLinearVelocity
    local h = Vector3.new(v.X, 0, v.Z)
    local moving = h.Magnitude > 2
    local ref
    if moving then
        ref = h.Unit
    else
        local rl = root.CFrame.LookVector
        ref = Vector3.new(rl.X, 0, rl.Z)
        if ref.Magnitude < 0.01 then return end
        ref = ref.Unit
    end

    -- kamera di depan karakter (cinematic / look back) -> jangan diikutin
    local fromChar = Vector3.new(cam.CFrame.Position.X - root.Position.X, 0, cam.CFrame.Position.Z - root.Position.Z)
    if fromChar.Magnitude > 0.5 and fromChar.Unit:Dot(ref) > 0.2 then
        easyHold = now + EASY_SETTLE
        easyRelease(hum)
        return
    end
    -- arah kamera nyimpang jauh dari arah hadap/lari
    if flat:Dot(ref) < 0.35 then
        easyRelease(hum)
        return
    end

    hum.AutoRotate = false
    local want = CFrame.lookAt(root.Position, root.Position + flat)
    local alpha = 1 - math.exp(-math.clamp(dt or 1 / 60, 0, 0.1) * 16)
    local cf = root.CFrame:Lerp(want, alpha)
    root.CFrame = cf
    if moving then
        local fl = cf.LookVector
        fl = Vector3.new(fl.X, 0, fl.Z)
        if fl.Magnitude > 0.01 then
            root.AssemblyLinearVelocity = fl.Unit * h.Magnitude + Vector3.new(0, v.Y, 0)
        end
    end
end)
local function setEasy(on)
    pcall(function() RunService:UnbindFromRenderStep("PanelEasyControl") end)
    easyHold = os.clock() + 0.3
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
-- Event-driven, gak ada loop per-frame saat idle.
--  * Gate   : QTEGui.GateQTE (4 beat, posisi acak). Tap di tengah lingkaran GATE_T detik setelah frame muncul.
--  * Stamina: QTEGui.StaminaQTE. Pointer (Time) muter, Star = titik Great. Tap diprediksi dari putaran pointer,
--             dikirim lewat QTEButton biar tepat (STAM_LEAD = kompensasi latensi, detik).
-- Tuning manual (opsional, sebelum execute): getgenv().PanelStamLead = 0.05 (detik, makin besar = tap makin awal) ; getgenv().PanelStamSnap = true
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")

local SNAP = env.PanelStamSnap == true -- (opsional, default mati) geser pointer pas di bintang sesaat sebelum tap
local STAM_LEAD = tonumber(env.PanelStamLead) or 0.05

local function centerOf(o) return o.AbsolutePosition + o.AbsoluteSize / 2 end
local function absRot(o)
    local ok, r = pcall(function() return o.AbsoluteRotation end)
    return (ok and r) or o.Rotation
end
local function guiInset()
    local ok, v = pcall(function() return GuiService:GetGuiInset() end)
    return (ok and v) or Vector2.zero
end
-- Posisi di "ruang input" (sama kayak input.Position): ScreenGui IgnoreGuiInset=true -> AbsolutePosition sudah
-- termasuk inset, jadi harus dikurangi. (Bug lama: inset selalu ditambah -> tap geser ke samping/bawah.)
local function inputPos(o)
    local c = centerOf(o)
    local sg = o:FindFirstAncestorOfClass("ScreenGui")
    if sg and sg.IgnoreGuiInset then c = c - guiInset() end
    return c
end
local function newInput(pos)
    return {
        UserInputType = Enum.UserInputType.Touch, UserInputState = Enum.UserInputState.Begin,
        KeyCode = Enum.KeyCode.Unknown, Position = Vector3.new(pos.X, pos.Y, 0), Delta = Vector3.zero,
    }
end

local qCount, qLabel = {stam = 0}, {}

--// ---- Cara kirim input (dicoba berurutan, yang berhasil diingat) ----
local function fireButton(b, pos)
    if not (b and getconnections) then return false end
    local any, inp = false, newInput(pos or centerOf(b))
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

-- Kalibrasi otomatis: bandingkan posisi yang DITERIMA game (UIS.InputBegan) dengan yang dituju,
-- selisihnya dipakai buat tap berikutnya (gate ada 4 beat).
local vimAdj = Vector2.zero
local function vimSend(want, withInset, isMouse)
    local ins = withInset and guiInset() or Vector2.zero
    local s = want + ins + vimAdj
    local got
    local conn = UIS.InputBegan:Connect(function(i)
        if got then return end
        local t = i.UserInputType
        if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
            got = Vector2.new(i.Position.X, i.Position.Y)
        end
    end)
    if isMouse then
        VIM:SendMouseButtonEvent(s.X, s.Y, 0, true, game, 0)
        task.wait(0.04)
        VIM:SendMouseButtonEvent(s.X, s.Y, 0, false, game, 0)
    else
        VIM:SendTouchEvent(7, 0, s.X, s.Y)
        task.wait(0.04)
        VIM:SendTouchEvent(7, 2, s.X, s.Y)
    end
    conn:Disconnect()
    if got then
        local err = want - got
        if err.Magnitude > 4 and err.Magnitude < 150 then
            local n = vimAdj + err
            if n.Magnitude <= 150 then vimAdj = n end
            dbg("calib err", err.X, err.Y, "adj", vimAdj.X, vimAdj.Y)
        end
    end
    return true
end
local METHODS = {
    btn = function(c) return fireButton(c.qb, c.raw) end,
    fbtn = function(c) return fireButton(c.frame, c.pos) end,
    uis = function(c) return fireAllUis(c.pos) end,
    touch = function(c) return vimSend(c.pos, true, false) end,
    touch0 = function(c) -- tanpa inset (cuma kalau inset <> 0)
        if guiInset().Magnitude < 1 then return false end
        return vimSend(c.pos, false, false)
    end,
    mouse = function(c) return vimSend(c.pos, true, true) end,
}
local ORDER = {
    stam = {"btn", "touch", "touch0", "uis"},
}
local bestM = {stam = 1}

-- "Diterima" = game nge-spawn fx_ring / fx_spark (di frame) atau StaminaQTEState (di QTEGui) setelah input masuk.
local function press(frame, kind)
    task.spawn(function()
        local qg = frame.Parent
        if not qg then return end
        local qb = playerGui:FindFirstChild("QTEButtonGui")
        qb = qb and qb:FindFirstChild("QTEButton")
        local tgt = (kind == "stam" and qb) or frame
        local c = {qb = qb, frame = frame, pos = inputPos(tgt), raw = centerOf(tgt)}

        local seen = false
        local function onAdd(ch)
            local n = ch.Name
            if n == "fx_ring" or n == "fx_spark" or n == "StaminaQTEState" then seen = true end
        end
        local c1, c2 = frame.ChildAdded:Connect(onAdd), qg.ChildAdded:Connect(onAdd)

        local order = ORDER[kind]
        local done = false
        for k = 0, #order - 1 do
            local i = (bestM[kind] - 1 + k) % #order + 1
            local ok, r = pcall(METHODS[order[i]], c)
            if ok and r then
                local t = os.clock()
                while not seen and frame.Parent and os.clock() - t < 0.25 do task.wait() end
                if seen or not frame.Parent then
                    bestM[kind] = i
                    done = true
                    qCount[kind] += 1
                    local lb = qLabel[kind]
                    if lb then lb.Text = qCount[kind] .. " tap" end
                    dbg("press ok", kind, order[i], c.pos.X, c.pos.Y)
                    break
                end
            end
            c.pos, c.raw = inputPos(tgt), centerOf(tgt)
        end
        c1:Disconnect()
        c2:Disconnect()
        if not done then dbg("press: semua cara gagal", kind) end
    end)
end

--// ---- Watcher: pantau QTEGui.ChildAdded, tanpa loop ----
local function makeWatcher(onFrame)
    local alive, conns = false, {}
    local function disconnectAll()
        for _, cn in ipairs(conns) do cn:Disconnect() end
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

--// ---- Stamina QTE ----
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

-- RenderStep (priority Last) hidup cuma selama satu QTE.
-- signed = jarak sudut pointer ke Star (+ = Star di depan, - = baru lewat). Tap kalau -passed <= signed <= half.
-- "passed" nangkep kasus frame ke-skip (FPS rendah): dulu kelewat = nunggu 1 putaran penuh = baru kena pas QTE selesai.
-- SNAP: pointer digeser tepat ke Star sesaat sebelum tap, jadi hasilnya gak bergantung ke FPS.
local stamId = 0
local function runStamina(frame)
    stamId += 1
    local name = "PanelStam" .. stamId
    local t0 = os.clock()
    local tf, tm, star
    local parentRot = 0
    local lastR, dir, spd = nil, nil, 0
    local samples, stable, lastTarget = 0, 0, nil
    local bound = true
    local function stop()
        if bound then
            bound = false
            pcall(function() RunService:UnbindFromRenderStep(name) end)
        end
    end
    RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value, function(dt)
        if not bound then return end
        if not frame.Parent then return stop() end
        if dt <= 0 then return end
        local now = os.clock()
        if not star then
            tf, tm = frame:FindFirstChild("Timeframe"), frame:FindFirstChild("Time")
            star = tf and tf:FindFirstChild("Star")
            if not star then
                if now - t0 > 1 then stop() end
                return
            end
            parentRot = absRot(frame)
            dbg("qte start")
            if env.PanelDebug then dumpQte(frame) end
        end
        if not (tm and tm.Parent) then return stop() end

        local pr = tm.Rotation + parentRot
        if not lastR then lastR = pr; return end
        local dR = (pr - lastR + 540) % 360 - 180
        lastR = pr
        if dR ~= 0 then
            dir = dR > 0 and 1 or -1
            samples += 1
            local inst = math.abs(dR) / dt
            spd = spd == 0 and inst or (spd * 0.5 + inst * 0.5)
        end
        if samples < 2 or not dir or spd < 20 then return end

        local v = centerOf(star) - centerOf(tf)
        if v.Magnitude < 1 then return end
        local target = math.deg(math.atan2(v.X, -v.Y)) -- derajat searah jarum jam dari atas
        if lastTarget and math.abs((target - lastTarget + 540) % 360 - 180) < 3 then
            stable += 1
        else
            stable = 0
        end
        lastTarget = target
        if stable < 1 then return end

        local signed = (((target - pr) * dir) + 180) % 360 - 180
        local half = spd * (dt * 0.5 + STAM_LEAD)
        local passed = math.max(spd * dt * 1.5, 12)
        if signed <= half and signed >= -passed then
            stop()
            dbg("stam fire", string.format("signed=%.1f spd=%.0f dt=%.3f dir=%d target=%.0f", signed, spd, dt, dir, target))
            if SNAP then pcall(function() tm.Rotation = target - parentRot end) end
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
        x, y = math.floor((viewport().X - WIN_W) / 2), math.max(8, math.floor((viewport().Y - WIN_H) / 2))
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
        Text = "v21", TextColor3 = C.sub, Font = FONT, TextSize = 10,
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

        local pg = new("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
            ScrollBarThickness = 2, ScrollBarImageColor3 = C.stroke, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        }, content)
        new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6)}, pg)
        new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
        pages[name] = pg
    end
end


--// Komponen UI
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

-- opts: hint, counter ("gate"/"stam"), extra (tinggi tambahan buat slider)
-- return: card, tinggi baris, api {set(v)} (set tanpa memanggil onChange)
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
    local api = {}
    function api.set(v)
        v = v == true
        if v == on then return end
        on = v
        paint(true)
    end
    return card, rowH, api
end

-- Slider di dalam card (tinggi 40) mulai dari y. return api {set(v)} (onChange tetap dipanggil)
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
        Size = UDim2.new(1, -28, 0, 20),
        Position = UDim2.fromOffset(14, 20),
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
        local r = (input.Position.X - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X)
        setVal(MIN + math.clamp(r, 0, 1) * (MAX - MIN))
    end
    setVal(init)

    hit.InputBegan:Connect(function(input)
        if not isPointer(input) then return end
        local sf = card:FindFirstAncestorOfClass("ScrollingFrame")
        if sf then sf.ScrollingEnabled = false end -- jangan ikut scroll pas geser slider
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
                if sf then sf.ScrollingEnabled = true end
                ease(knobScale, {Scale = 1})
            end
        end)
    end)
    return {set = setVal}
end

-- Segmented control (Off / Semi / Inf). options = {{id, text, color, hint}}
function UI.segment(parent, text, options, init, onChange)
    local card, stroke, bar = UI.card(parent, 54)
    bar.Size = UDim2.new(0, 3, 0, 18)
    new("TextLabel", {
        Size = UDim2.fromOffset(70, 34),
        Position = UDim2.fromOffset(14, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local holder = new("Frame", {
        Size = UDim2.fromOffset(150, 24),
        Position = UDim2.new(1, -160, 0, 5),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
    }, card)
    round(holder, 8)
    new("UIStroke", {Color = C.stroke, Thickness = 1}, holder)
    new("UIPadding", {PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2)}, holder)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder}, holder)
    local hintLbl = new("TextLabel", {
        Size = UDim2.new(1, -28, 0, 14),
        Position = UDim2.fromOffset(14, 34),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)

    local cur, btns = nil, {}
    local function paint(animate)
        for _, o in ipairs(options) do
            local sel = o.id == cur
            local props = {
                BackgroundColor3 = sel and (o.color or C.accent) or C.bg,
                TextColor3 = sel and Color3.new(1, 1, 1) or C.sub,
            }
            if animate then ease(btns[o.id], props) else for k, v in pairs(props) do btns[o.id][k] = v end end
            if sel then hintLbl.Text = o.hint or "" end
        end
        local act = cur ~= options[1].id
        local col = act and C.accent or C.off
        if animate then
            ease(bar, {BackgroundColor3 = col})
            ease(stroke, {Color = act and C.accent or C.stroke, Transparency = act and 0.55 or 0})
        else
            bar.BackgroundColor3 = col
            stroke.Color = act and C.accent or C.stroke
            stroke.Transparency = act and 0.55 or 0
        end
    end
    for i, o in ipairs(options) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / #options, 0, 1, 0),
            LayoutOrder = i,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            BackgroundColor3 = C.bg,
            Text = o.text,
            TextColor3 = C.sub,
            Font = FONT_B,
            TextSize = 11,
        }, holder)
        round(b, 6)
        btns[o.id] = b
        b.Activated:Connect(function()
            if cur == o.id then return end
            cur = o.id
            paint(true)
            onChange(o.id)
        end)
    end
    cur = init
    paint(false)
    return {
        set = function(id)
            if id == cur or not btns[id] then return end
            cur = id
            paint(true)
        end,
    }
end

-- Grid preset 2x2 + baris info. list = {{id, text, color, info}}
function UI.presets(parent, list, onPick)
    local card = UI.card(parent, 138)
    new("TextLabel", {
        Size = UDim2.new(1, -28, 0, 14),
        Position = UDim2.fromOffset(14, 6),
        BackgroundTransparency = 1,
        Text = "PRESET",
        TextColor3 = C.sub,
        Font = FONT_B,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local grid = new("Frame", {
        Size = UDim2.new(1, -16, 0, 76),
        Position = UDim2.fromOffset(8, 22),
        BackgroundTransparency = 1,
    }, card)
    new("UIGridLayout", {
        CellSize = UDim2.new(0.5, -3, 0, 35),
        CellPadding = UDim2.fromOffset(6, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)
    local info = new("TextLabel", {
        Size = UDim2.new(1, -28, 0, 30),
        Position = UDim2.fromOffset(14, 102),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, card)

    local chips, sel = {}, nil
    local function select(id)
        sel = id
        for _, p in ipairs(list) do
            local ch = chips[p.id]
            local on = p.id == id
            ease(ch.btn, {BackgroundColor3 = on and C.press or C.bg, TextColor3 = on and C.text or C.sub})
            ease(ch.stroke, {Color = on and p.color or C.stroke, Transparency = on and 0.1 or 0})
            if on then info.Text = p.info end
        end
        if id == nil then info.Text = "Custom - atur manual di bawah." end
    end
    for i, p in ipairs(list) do
        local b = new("TextButton", {
            LayoutOrder = i,
            BackgroundColor3 = C.bg,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = p.text,
            TextColor3 = C.sub,
            Font = FONT_B,
            TextSize = 12,
        }, grid)
        round(b, 9)
        new("UIPadding", {PaddingLeft = UDim.new(0, 18)}, b)
        local st = new("UIStroke", {Color = C.stroke, Thickness = 1}, b)
        local d = new("Frame", {
            Size = UDim2.fromOffset(7, 7),
            Position = UDim2.new(0, -11, 0.5, -3),
            BackgroundColor3 = p.color,
            BorderSizePixel = 0,
        }, b)
        round(d, 4)
        chips[p.id] = {btn = b, stroke = st}
        b.Activated:Connect(function() onPick(p.id) end)
    end
    select(nil)
    return {select = select}
end

--// Apply helpers
local function apply(key, on, setter)
    cfg[key] = on
    setActive(key, on)
    setter(on)
    save()
end
local function applyStam(mode)
    cfg.stamMode = mode
    setActive("stam", mode ~= "off")
    setStamMode(mode)
    save()
end

--// ======================= TAB MAIN =======================
-- Preset: easy, stamina mode, speed on + multiplier
local PLIST = {
    {id = "supersafe", text = "Super Safe", color = C.ok,
        info = "Easy On · Stamina Off · Speed 1.05x. Paling aman, nyaris gak kelihatan."},
    {id = "medium", text = "Medium", color = Color3.fromRGB(163, 230, 53),
        info = "Easy On · Stamina Off · Speed 1.10x. Aman, boost tipis."},
    {id = "semi", text = "Semi Safe", color = Color3.fromRGB(56, 189, 248),
        info = "Easy On · Stamina Semi · Speed 1.10x. Stamina irit & isi cepat, bukan infinity."},
    {id = "agresif", text = "Agresif", color = C.danger,
        info = "Easy On · Stamina Inf · Speed 1.25x. BISA KENA BAN, pakai sesekali aja."},
}
local PRESETS = {
    supersafe = {easy = true, stam = "off", speed = true, mult = 1.05},
    medium    = {easy = true, stam = "off", speed = true, mult = 1.10},
    semi      = {easy = true, stam = "semi", speed = true, mult = 1.10},
    agresif   = {easy = true, stam = "inf", speed = true, mult = 1.25},
}

local presetLock = false
local presetsUI, apiEasy, segStam, apiSpeed, sldSpeed
local function userEdit()
    if presetLock or cfg.preset == "" then return end
    cfg.preset = ""
    if presetsUI then presetsUI.select(nil) end
    save()
end
local function applyPreset(id)
    local p = PRESETS[id]
    if not p then return end
    presetLock = true
    cfg.preset = id
    speedMult = p.mult
    cfg.mult = p.mult
    sldSpeed.set(p.mult)
    apiEasy.set(p.easy);   apply("easy", p.easy, setEasy)
    segStam.set(p.stam);   applyStam(p.stam)
    apiSpeed.set(p.speed); apply("speed", p.speed, setSpeed)
    presetLock = false
    presetsUI.select(id)
    save()
end

presetsUI = UI.presets(pages.Main, PLIST, applyPreset)
do
    local _, _, a = UI.toggle(pages.Main, "Easy Control", cfg.easy, function(v)
        userEdit(); apply("easy", v, setEasy)
    end)
    apiEasy = a
end
segStam = UI.segment(pages.Main, "Stamina", {
    {id = "off",  text = "Off",  color = C.off,
        hint = "Stamina normal"},
    {id = "semi", text = "Semi", color = Color3.fromRGB(34, 160, 98),
        hint = string.format("Pakai -%d%% · isi %.1fx lebih cepat (safe)", math.floor((1 - SEMI_USE) * 100 + 0.5), SEMI_REGEN)},
    {id = "inf",  text = "Inf",  color = Color3.fromRGB(214, 76, 76),
        hint = "Stamina terkunci penuh (risiko tinggi)"},
}, cfg.stamMode, function(id)
    userEdit(); applyStam(id)
end)
do
    local card, y, a = UI.toggle(pages.Main, "Speed Boost", cfg.speed, function(v)
        userEdit(); apply("speed", v, setSpeed)
    end, {extra = 40})
    apiSpeed = a
    sldSpeed = UI.slider(card, y, "Multiplier", 1.05, 1.5, 0.05, cfg.mult,
        function(v) return string.format("%.2fx", v) end,
        function(v)
            speedMult = v
            if v ~= cfg.mult then cfg.mult = v; userEdit(); save() end
        end)
end

--// ======================= TAB QTE =======================
UI.toggle(pages.QTE, "Auto Stamina QTE", cfg.qStam, function(v) apply("qStam", v, setStam) end,
    {hint = "Tap pas pointer kena bintang", counter = "stam"})
UI.toggle(pages.QTE, "Debug log (F9)", env.PanelDebug == true, function(v) env.PanelDebug = v end,
    {hint = "Log tap & stamina ke console (F9)"})

--// ======================= TAB VISUAL =======================
do
    local card, y = UI.toggle(pages.Visual, "Soft Light & Color", cfg.light, function(v) apply("light", v, setLight) end, {extra = 40})
    UI.slider(card, y, "Tone (tinggi = lebih datar)", 0.2, 1, 0.05, cfg.tone,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        function(v)
            cfg.tone = v
            save()
            if G.light then lightAcc = 2; lightN = 0 end
        end)
end
UI.toggle(pages.Visual, "Flat Textures", cfg.tex, function(v) apply("tex", v, setTex) end)
UI.toggle(pages.Visual, "Hide Effects", cfg.fx, function(v) apply("fx", v, setFx) end)

--// Status footer: hijau = nempel, kuning = aktif tapi belum ketemu (lobby), merah = bocor (inf), abu = off
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
    dotStam.BackgroundColor3 = (cfg.stamMode == "off") and C.off
        or ((#cfgs == 0) and C.warn)
        or ((cfg.stamMode == "inf" and os.clock() - leakAt < 3) and C.danger)
        or C.ok
    dotQte.BackgroundColor3 = cfg.qStam and C.ok or C.off
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
    setStamMode("off")
    setEasy(false)
    setSpeed(false)
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
if cfg.stamMode ~= "off" then setActive("stam", true); setStamMode(cfg.stamMode) end
if cfg.speed then setActive("speed", true); setSpeed(true) end
if cfg.qStam then setActive("qStam", true); setStam(true) end
if cfg.light then setActive("light", true); setLight(true) end
if cfg.tex then setActive("tex", true); setTex(true) end
if cfg.fx then setActive("fx", true); setFx(true) end
presetsUI.select(PRESETS[cfg.preset] and cfg.preset or nil)
selectTab(TABS[1])

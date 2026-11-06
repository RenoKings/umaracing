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

local C = {
    bg      = Color3.fromRGB(16, 16, 21),
    surface = Color3.fromRGB(26, 26, 33),
    press   = Color3.fromRGB(34, 34, 43),
    stroke  = Color3.fromRGB(48, 48, 60),
    text    = Color3.fromRGB(236, 236, 244),
    sub     = Color3.fromRGB(130, 130, 150),
    accent  = Color3.fromRGB(240, 118, 72),
    accent2 = Color3.fromRGB(255, 166, 98),
    off     = Color3.fromRGB(54, 54, 68),
    danger  = Color3.fromRGB(239, 68, 68),
    ok      = Color3.fromRGB(74, 222, 128),
}
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold
local WIN_W = 210
local _vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(800, 400)
local WIN_H = math.clamp(math.floor(_vp.Y * 0.62), 170, 230)

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
        if d.stamMode == nil and d.stam == true then cfg.stamMode = "inf" end
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

local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            env.PanelLastError = tostring(err)
            dbg("error:", err)
        end
    end
end

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

local speedMult = cfg.mult
local paceOrig, paceSet

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

local SEMI_USE = math.clamp(tonumber(env.PanelSemiUse) or 0.60, 0.2, 1)
local SEMI_REGEN = math.clamp(tonumber(env.PanelSemiRegen) or 1.30, 1, 3)
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
local leakAt = 0
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
local semiSt, setSemi
local stAcc, infoSt, infoMx = 0, nil, nil
local setStamLoop = hook(RunService.Heartbeat, function(dt)
    stAcc += dt
    if stAcc < 0.15 then return end
    dt, stAcc = stAcc, 0
    if stamMode == "inf" then ensure() end
    local mode = stamMode
    for i = 1, #cfgs do
        local t = cfgs[i]
        local o = rememberCfg(t)
        if mode == "inf" then
            if rawget(t, "BaseStaminaUseRate") ~= 0 or rawget(t, "CurrentStaminaUseRate") ~= 0 then
                pcall(rawset, t, "BaseStaminaUseRate", 0)
                pcall(rawset, t, "CurrentStaminaUseRate", 0)
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
    if mode == "semi" then
        local info = player:FindFirstChild("Info")
        local st = info and info:FindFirstChild("Stamina")
        if st and st ~= semiSt then setSemi(true) end
    end
    if mode == "inf" and os.clock() - scanAt > 90 then scan() end
end)

local semiV, semiRaw, semiConn, semiWriting
local semiTok = 0
setSemi = function(on)
    semiTok += 1
    local tok = semiTok
    if semiConn then semiConn:Disconnect(); semiConn = nil end
    semiV, semiRaw, semiSt = nil, nil, nil
    if not on then return end
    task.spawn(function()
        local info = player:WaitForChild("Info", 15)
        local st = info and info:WaitForChild("Stamina", 15)
        local mx = info and info:WaitForChild("MaxStamina", 15)
        if tok ~= semiTok or not (st and mx) then return end
        semiSt = st
        semiV, semiRaw = st.Value, st.Value
        semiConn = st:GetPropertyChangedSignal("Value"):Connect(function()
            if semiWriting then return end
            local raw, m = st.Value, mx.Value
            local d = raw - semiRaw
            semiRaw = raw
            if d < 0 then
                semiV += d * SEMI_USE
            elseif d > 0 then
                semiV += d * ((d <= 6) and SEMI_REGEN or 1)
            end
            semiV = math.clamp(math.max(semiV, raw), 0, m)
            local nv = math.floor(semiV + 0.5)
            if nv ~= raw then
                semiWriting = true
                st.Value = nv
                semiWriting = false
                semiRaw = raw
            end
            if env.PanelDebug then dbg("semi raw", raw, "virtual", nv) end
        end)
    end)
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
    stAcc = 1
end

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

    if flat:Dot(ref) < (moving and -0.4 or 0.35) then
        easyRelease(hum)
        return
    end

    hum.AutoRotate = false
    local want = CFrame.lookAt(root.Position, root.Position + flat)
    local rate = 18 + math.min(h.Magnitude, 200) * 0.14
    local alpha = 1 - math.exp(-math.clamp(dt or 1 / 60, 0, 0.1) * rate)
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

local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")

local SKIP_FIRST = env.PanelStamSkipFirst ~= false
local SNAP = env.PanelStamSnap == true
local STAM_LEAD = tonumber(env.PanelStamLead) or 0.08

local function centerOf(o) return o.AbsolutePosition + o.AbsoluteSize / 2 end
local function absRot(o)
    local ok, r = pcall(function() return o.AbsoluteRotation end)
    return (ok and r) or o.Rotation
end
local function guiInset()
    local ok, v = pcall(function() return GuiService:GetGuiInset() end)
    return (ok and v) or Vector2.zero
end

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
    touch0 = function(c)
        if guiInset().Magnitude < 1 then return false end
        return vimSend(c.pos, false, false)
    end,
    mouse = function(c) return vimSend(c.pos, true, true) end,
}
local ORDER = {
    stam = {"btn", "touch", "touch0", "uis"},
}
local bestM = {stam = 1}

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

local stamId = 0
local function runStamina(frame)
    stamId += 1
    local name = "PanelStam" .. stamId
    local t0 = os.clock()
    local tf, tm, star
    local parentRot = 0
    local lastR, unwrapped, hist = nil, 0, {}
    local stable, lastTarget = 0, nil
    local skipped, armed = false, not SKIP_FIRST
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
        if not lastR then
            lastR = pr
            hist[1] = {now, 0}
            return
        end
        unwrapped += (pr - lastR + 540) % 360 - 180
        lastR = pr
        hist[#hist + 1] = {now, unwrapped}
        while #hist > 3 and now - hist[1][1] > 0.3 do table.remove(hist, 1) end
        local n = #hist
        local span = hist[n][1] - hist[1][1]
        if n < 3 or span < 0.05 then return end
        local sp = (hist[n][2] - hist[1][2]) / span
        if math.abs(sp) < 20 then return end
        local dir, spd = sp > 0 and 1 or -1, math.abs(sp)

        local v = centerOf(star) - centerOf(tf)
        if v.Magnitude < 1 then return end
        local target = math.deg(math.atan2(v.X, -v.Y))
        if lastTarget and math.abs((target - lastTarget + 540) % 360 - 180) < 3 then
            stable += 1
        else
            stable = 0
        end
        lastTarget = target
        if stable < 1 then return end

        local signed = (((target - pr) * dir) + 180) % 360 - 180
        local tt = signed / spd - STAM_LEAD
        local inWin = signed >= -math.max(spd * dt * 1.5, 12) and tt <= dt
        if inWin and not armed then
            skipped = true
            dbg("stam: lintasan pertama dilewati")
            return
        end
        if not inWin then
            if skipped then armed = true end
            return
        end
        do
            stop()
            if tt > 0.0005 and tt < 0.12 then
                local t1 = os.clock() + tt
                while os.clock() < t1 do end
            end
            dbg("stam fire", string.format("signed=%.1f spd=%.0f dt=%.3f tt=%.4f dir=%d", signed, spd, dt, tt, dir))
            if SNAP then pcall(function() tm.Rotation = target - parentRot end) end
            press(frame, "stam")
        end
    end)
    task.delay(6, stop)
end

local stamSeen = setmetatable({}, {__mode = "k"})
local setStam = makeWatcher(function(f)
    if f.Name ~= "StaminaQTE" or not f:IsA("GuiButton") or stamSeen[f] then return end
    stamSeen[f] = true
    runStamina(f)
end)

local G = {light = false, tex = false, fx = false}

local function same(a, b)
    local ta = typeof(a)
    if ta == "number" then return type(b) == "number" and math.abs(a - b) < 1e-3 end
    if ta == "Color3" then
        return typeof(b) == "Color3" and math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 2e-3
    end
    return a == b
end

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

local worldSync, worldPass

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
    if lightN % 3 == 1 then dimLights(t) end

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
    if lightAcc < 4 then return end
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
    elseif d:IsA("Decal") then
        if d.Transparency < 1 and decOrig[d] == nil then
            local m = d:FindFirstAncestorOfClass("Model")
            if not (m and m:FindFirstChildOfClass("Humanoid")) then
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
    BorderSizePixel = 0,
}, gui)
round(window, 12)
new("UIStroke", {Color = C.stroke, Thickness = 1}, window)
local winScale = new("UIScale", {Scale = 1}, window)
do
    local x, y

    x, y = clampXY(math.floor((viewport().X - WIN_W) / 2), 8, WIN_W, WIN_H)
    window.Position = UDim2.fromOffset(x, y)
end

local function mark(parent, s, hole)
    local box = new("Frame", {Size = UDim2.fromOffset(s, s), BackgroundTransparency = 1}, parent)
    local function diamond(side, color, r)
        local f = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(side, side),
            Rotation = 45,
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, box)
        round(f, r)
        return f
    end
    local outer = diamond(s * 0.66, Color3.new(1, 1, 1), math.max(2, math.floor(s * 0.16)))
    new("UIGradient", {Color = ColorSequence.new(C.accent2, C.accent), Rotation = 90}, outer)
    diamond(s * 0.34, hole, math.max(1, math.floor(s * 0.07)))
    diamond(s * 0.13, C.accent2, 1)
    return box
end

local bubble = new("TextButton", {
    Name = "Bubble",
    Size = UDim2.fromOffset(40, 40),
    BackgroundColor3 = C.surface,
    AutoButtonColor = false,
    Text = "",
    Visible = false,
}, gui)
round(bubble, 20)
new("UIStroke", {Color = C.accent, Transparency = 0.45, Thickness = 1.5}, bubble)
local bubScale = new("UIScale", {Scale = 1}, bubble)
do
    local m = mark(bubble, 26, C.surface)
    m.Position = UDim2.fromOffset(7, 7)
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

local function minimize()
    local x, y = clampXY(window.Position.X.Offset + WIN_W / 2 - 20, window.Position.Y.Offset, 40, 40)
    bubble.Position = UDim2.fromOffset(x, y)
    window.Visible = false
    bubble.Visible = true
    pop(bubScale)
end
local function restore()
    local x, y = clampXY(bubble.Position.X.Offset + 20 - WIN_W / 2, bubble.Position.Y.Offset, WIN_W, WIN_H)
    window.Position = UDim2.fromOffset(x, y)
    bubble.Visible = false
    window.Visible = true
    pop(winScale)
end

local header = new("Frame", {
    Size = UDim2.new(1, 0, 0, 30),
    BackgroundTransparency = 1,
    Active = true,
}, window)
draggable(header, window)
draggable(bubble, bubble, restore)

local closeBtn
do
    local m = mark(header, 22, Color3.fromRGB(22, 22, 29))
    m.Position = UDim2.fromOffset(8, 4)
    new("TextLabel", {
        Size = UDim2.fromOffset(60, 30), Position = UDim2.fromOffset(34, 0), BackgroundTransparency = 1,
        Text = "Panel", TextColor3 = C.text, Font = FONT_B, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    }, header)

    local function headerBtn(text, x, hoverColor)
        local b = new("TextButton", {
            Size = UDim2.fromOffset(22, 22),
            Position = UDim2.new(1, x, 0, 4),
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
    headerBtn("–", -52, C.text).Activated:Connect(minimize)
    closeBtn = headerBtn("×", -27, C.danger)
end

local TABS = {"Main", "QTE", "Visual"}
local pages, tabBtns = {}, {}
local pill
local function selectTab(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for i, n in ipairs(TABS) do
        local on = (n == name)
        tabBtns[n].TextColor3 = on and Color3.new(1, 1, 1) or C.sub
        if on and pill then
            ease(pill, {Position = UDim2.new((i - 1) / #TABS, 2, 0, 2)})
        end
    end
end
do
    local tabBar = new("Frame", {
        Size = UDim2.new(1, -16, 0, 24),
        Position = UDim2.fromOffset(8, 33),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, window)
    round(tabBar, 8)
    new("UIStroke", {Color = C.stroke, Thickness = 1}, tabBar)
    pill = new("Frame", {
        Size = UDim2.new(1 / #TABS, -4, 1, -4),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundColor3 = C.accent,
        BorderSizePixel = 0,
    }, tabBar)
    round(pill, 6)

    local content = new("Frame", {
        Size = UDim2.new(1, 0, 1, -68),
        Position = UDim2.fromOffset(0, 62),
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
            TextSize = 11,
            ZIndex = 2,
        }, tabBar)
        tabBtns[name] = b
        b.Activated:Connect(function() selectTab(name) end)

        local pg = new("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
            ScrollBarThickness = 2, ScrollBarImageColor3 = C.stroke, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        }, content)
        new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4)}, pg)
        new("UIListLayout", {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
        pages[name] = pg
    end
end

local UI = {}

function UI.card(parent, h)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, h),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, parent)
    round(card, 8)
    new("UIStroke", {Color = C.stroke, Thickness = 1}, card)
    return card
end

function UI.toggle(parent, text, init, onChange, opts)
    opts = opts or {}
    local on = init == true
    local rowH = opts.hint and 36 or 30
    local card = UI.card(parent, rowH + (opts.extra or 0))
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, rowH),
        BackgroundTransparency = 1,
        AutoButtonColor = false,
        Text = "",
    }, card)
    local titleW = opts.counter and -104 or -56
    new("TextLabel", {
        Size = UDim2.new(1, titleW, 0, opts.hint and 16 or rowH),
        Position = UDim2.fromOffset(12, opts.hint and 4 or 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    if opts.hint then
        new("TextLabel", {
            Size = UDim2.new(1, titleW, 0, 12),
            Position = UDim2.fromOffset(12, 20),
            BackgroundTransparency = 1,
            Text = opts.hint,
            TextColor3 = C.sub,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, row)
    end
    if opts.counter then
        qLabel[opts.counter] = new("TextLabel", {
            Size = UDim2.fromOffset(54, 14),
            Position = UDim2.new(1, -98, 0, (rowH - 14) / 2),
            BackgroundTransparency = 1,
            Text = qCount[opts.counter] .. " tap",
            TextColor3 = C.sub,
            Font = FONT,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Right,
        }, row)
    end
    local track = new("Frame", {
        Size = UDim2.fromOffset(32, 18),
        Position = UDim2.new(1, -42, 0, (rowH - 18) / 2),
        BackgroundColor3 = C.off,
        BorderSizePixel = 0,
    }, row)
    round(track, 9)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(12, 12),
        Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, track)
    round(knob, 6)

    local function paint(animate)
        local col = on and C.accent or C.off
        local props = {
            {track, {BackgroundColor3 = col}},
            {knob, {Position = on and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3)}},
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

function UI.slider(card, y, label, MIN, MAX, STEP, init, fmt, onChange)
    local box = new("Frame", {
        Size = UDim2.new(1, 0, 0, 34),
        Position = UDim2.fromOffset(0, y),
        BackgroundTransparency = 1,
    }, card)
    new("Frame", {
        Size = UDim2.new(1, -24, 0, 1),
        Position = UDim2.fromOffset(12, 0),
        BackgroundColor3 = C.stroke,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
    }, box)
    new("TextLabel", {
        Size = UDim2.new(1, -80, 0, 14),
        Position = UDim2.fromOffset(12, 4),
        BackgroundTransparency = 1,
        Text = label,
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, box)
    local chip = new("TextLabel", {
        Size = UDim2.fromOffset(48, 14),
        Position = UDim2.new(1, -60, 0, 4),
        BackgroundColor3 = C.press,
        BorderSizePixel = 0,
        Text = "",
        TextColor3 = C.accent,
        Font = FONT_B,
        TextSize = 10,
    }, box)
    round(chip, 7)
    local hit = new("Frame", {
        Size = UDim2.new(1, -24, 0, 16),
        Position = UDim2.fromOffset(12, 17),
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
    local fill = new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.accent, BorderSizePixel = 0}, bar)
    round(fill, 3)
    local knob = new("Frame", {
        Size = UDim2.fromOffset(12, 12),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
    }, bar)
    round(knob, 6)
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
        if sf then sf.ScrollingEnabled = false end
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

function UI.segment(parent, text, options, init, onChange)
    local card = UI.card(parent, 44)
    new("TextLabel", {
        Size = UDim2.fromOffset(60, 28),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = text,
        TextColor3 = C.text,
        Font = FONT,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local holder = new("Frame", {
        Size = UDim2.fromOffset(132, 22),
        Position = UDim2.new(1, -140, 0, 3),
        BackgroundColor3 = C.bg,
        BorderSizePixel = 0,
    }, card)
    round(holder, 8)
    new("UIStroke", {Color = C.stroke, Thickness = 1}, holder)
    new("UIPadding", {PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 2), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 2)}, holder)
    new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder}, holder)
    local hintLbl = new("TextLabel", {
        Size = UDim2.new(1, -24, 0, 12),
        Position = UDim2.fromOffset(12, 28),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
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
            TextSize = 10,
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

function UI.presets(parent, list, onPick)
    local card = UI.card(parent, 72)
    new("TextLabel", {
        Size = UDim2.new(1, -24, 0, 12),
        Position = UDim2.fromOffset(12, 4),
        BackgroundTransparency = 1,
        Text = "PRESET",
        TextColor3 = C.sub,
        Font = FONT_B,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    local grid = new("Frame", {
        Size = UDim2.new(1, -16, 0, 26),
        Position = UDim2.fromOffset(8, 18),
        BackgroundTransparency = 1,
    }, card)
    new("UIGridLayout", {
        CellSize = UDim2.new(0.25, -3, 1, 0),
        CellPadding = UDim2.fromOffset(4, 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)
    local info = new("TextLabel", {
        Size = UDim2.new(1, -20, 0, 24),
        Position = UDim2.fromOffset(10, 46),
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = C.sub,
        Font = FONT,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    }, card)

    local chips = {}
    local function select(id)
        for _, p in ipairs(list) do
            local ch = chips[p.id]
            local on = p.id == id
            ease(ch.btn, {BackgroundColor3 = on and C.press or C.bg, TextColor3 = on and p.color or C.sub})
            ease(ch.stroke, {Color = on and p.color or C.stroke})
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
            TextSize = 10,
        }, grid)
        round(b, 7)
        local st = new("UIStroke", {Color = C.stroke, Thickness = 1}, b)
        chips[p.id] = {btn = b, stroke = st}
        b.Activated:Connect(function() onPick(p.id) end)
    end
    select(nil)
    return {select = select}
end

local function apply(key, on, setter)
    cfg[key] = on
    setter(on)
    save()
end
local function applyStam(mode)
    cfg.stamMode = mode
    setStamMode(mode)
    save()
end

local PLIST = {
    {id = "supersafe", text = "Safe", color = C.ok,
        info = "Super Safe: Easy, Stamina Off, 1.05x. Paling aman."},
    {id = "medium", text = "Medium", color = Color3.fromRGB(163, 230, 53),
        info = "Medium: Easy, Stamina Off, 1.10x. Aman, boost tipis."},
    {id = "semi", text = "Semi", color = Color3.fromRGB(56, 189, 248),
        info = "Semi Safe: Easy, Stamina Semi, 1.10x. Irit, bukan infinity."},
    {id = "agresif", text = "Agresif", color = C.danger,
        info = "Agresif: Easy, Stamina Inf, 1.25x. BISA KENA BAN, sesekali aja."},
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
        hint = "Normal"},
    {id = "semi", text = "Semi", color = Color3.fromRGB(34, 160, 98),
        hint = string.format("Pakai -%d%% · isi %.1fx (safe)", math.floor((1 - SEMI_USE) * 100 + 0.5), SEMI_REGEN)},
    {id = "inf",  text = "Inf",  color = Color3.fromRGB(214, 76, 76),
        hint = "Terkunci penuh (berisiko)"},
}, cfg.stamMode, function(id)
    userEdit(); applyStam(id)
end)
do
    local card, y, a = UI.toggle(pages.Main, "Speed Boost", cfg.speed, function(v)
        userEdit(); apply("speed", v, setSpeed)
    end, {extra = 34})
    apiSpeed = a
    sldSpeed = UI.slider(card, y, "Multiplier", 1.05, 1.5, 0.05, cfg.mult,
        function(v) return string.format("%.2fx", v) end,
        function(v)
            speedMult = v
            if v ~= cfg.mult then cfg.mult = v; userEdit(); save() end
        end)
end

UI.toggle(pages.QTE, "Stamina QTE", cfg.qStam, function(v) apply("qStam", v, setStam) end,
    {hint = "Auto tap bintang", counter = "stam"})
UI.toggle(pages.QTE, "Debug log", env.PanelDebug == true, function(v) env.PanelDebug = v end,
    {hint = "Log ke console (F9)"})

do
    local card, y = UI.toggle(pages.Visual, "Soft Light", cfg.light, function(v) apply("light", v, setLight) end, {extra = 34})
    UI.slider(card, y, "Tone", 0.2, 1, 0.05, cfg.tone,
        function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
        function(v)
            cfg.tone = v
            save()
            if G.light then lightAcc = 2; lightN = 0 end
        end)
end
UI.toggle(pages.Visual, "Flat Textures", cfg.tex, function(v) apply("tex", v, setTex) end)
UI.toggle(pages.Visual, "Hide Effects", cfg.fx, function(v) apply("fx", v, setFx) end)

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

if cfg.easy then setEasy(true) end
if cfg.stamMode ~= "off" then setStamMode(cfg.stamMode) end
if cfg.speed then setSpeed(true) end
if cfg.qStam then setStam(true) end
if cfg.light then setLight(true) end
if cfg.tex then setTex(true) end
if cfg.fx then setFx(true) end
presetsUI.select(PRESETS[cfg.preset] and cfg.preset or nil)
selectTab(TABS[1])

do
    local v = viewport()
    bubble.Position = UDim2.fromOffset(math.floor(v.X / 2 - 20), math.floor(v.Y * 0.2))
    window.Visible = false
    bubble.Visible = true
end

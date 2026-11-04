--// Panel v13 — Easy Control · Infinite Stamina · Speed Boost · Visual (low graphics / soft color)
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
local WIN_W, WIN_H = 250, 240

--// Settings (disimpan otomatis)
local FILE = "panel_settings.json"
local cfg = {
    easy = false, stam = false, speed = false, mult = 1.1,
    light = false, tex = false, fx = false, tone = 0.6,
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

-- Infinite Stamina
-- Race baru = config sprint baru. Deteksi: HUD (lastStamina) bilang stamina turun padahal sudah di-patch -> scan ulang.
local origRate = setmetatable({}, {__mode = "k"})
local drainT, drainGap = 0, 2
local function stamLow()
    for _, t in ipairs(vis) do
        local ls = rawget(t, "lastStamina")
        if type(ls) == "number" and ls >= 0 and ls < 0.9 and lineAlive(t) then return true end
    end
    return false
end
local leakAt = 0 -- terakhir server ngirim stamina < max padahal fitur aktif
local stWatch, stConn, stamEvConn
local function watchStamina(st, mx)
    if stWatch == st then return end
    if stConn then stConn:Disconnect() end
    stWatch = st
    -- begitu ada yang nurunin nilainya, langsung dibalikin (gak nunggu frame berikutnya)
    stConn = st:GetPropertyChangedSignal("Value"):Connect(function()
        if st.Value < mx.Value then st.Value = mx.Value end
    end)
end
-- Server ngirim stamina lewat UpdateClientStamina: kalau nilainya turun = lagi nguras -> scan ulang (tanpa nunggu timer)
local onStamEvent = safe(function(v)
    local info = player:FindFirstChild("Info")
    local mx = info and info:FindFirstChild("MaxStamina")
    if type(v) ~= "number" or not mx or v >= mx.Value - 1 then return end
    leakAt = os.clock()
    if os.clock() - scanAt > 1.5 then scan() end
end)
local setStamLoop = hook(RunService.Heartbeat, function(dt)
    ensure()
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
    if os.clock() - scanAt > 15 then scan() end
end)
local function setStamina(on)
    setStamLoop(on)
    if on then
        if not stamEvConn then
            local rem = game:GetService("ReplicatedStorage"):FindFirstChild("remotes")
            local ev = rem and rem:FindFirstChild("UpdateClientStamina")
            if ev and ev:IsA("RemoteEvent") then stamEvConn = ev.OnClientEvent:Connect(onStamEvent) end
        end
    else
        if stamEvConn then stamEvConn:Disconnect(); stamEvConn = nil end
        if stConn then stConn:Disconnect(); stConn = nil; stWatch = nil end
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
local function setSpeed(on)
    setPaceLoop(on)
    if not on then
        local ch = player.Character
        if ch and paceOrig and paceSet then ch:SetAttribute("PaceSpeedMult", paceOrig) end
        paceSet = nil
    end
end

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

local function applyLight()
    local t = cfg.tone
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
    dimLights(t)

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
    if lightAcc < 0.4 then return end
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

-- Header: tab + minimize + close
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

local tabBar = new("Frame", {
    Size = UDim2.new(1, -84, 0, 26),
    Position = UDim2.fromOffset(10, 6),
    BackgroundColor3 = C.surface,
    BorderSizePixel = 0,
}, header)
round(tabBar, 8)

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

-- Pages
local content = new("Frame", {
    Size = UDim2.new(1, 0, 1, -60),
    Position = UDim2.fromOffset(0, 38),
    BackgroundTransparency = 1,
}, window)

local TABS = {"Main", "Visual"}
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

    local pg = new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false}, content)
    new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2)}, pg)
    new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, pg)
    pages[name] = pg
end

local function makeToggle(parent, text, init, onChange)
    local on = init == true
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
    }, parent)
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

local function makeSlider(parent, label, MIN, MAX, STEP, init, fmt, onChange)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 50),
        BackgroundColor3 = C.surface,
        BorderSizePixel = 0,
    }, parent)
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

-- Tab Main
makeToggle(pages.Main, "Easy Control", cfg.easy, function(v) apply("easy", v, setEasy) end)
makeToggle(pages.Main, "Infinite Stamina", cfg.stam, function(v) apply("stam", v, setStamina) end)
makeToggle(pages.Main, "Speed Boost", cfg.speed, function(v) apply("speed", v, setSpeed) end)
makeSlider(pages.Main, "Multiplier", 1.1, 1.5, 0.05, cfg.mult,
    function(v) return string.format("%.2fx", v) end,
    function(v)
        speedMult = v
        if v ~= cfg.mult then cfg.mult = v; save() end
    end)

-- Tab Visual
makeToggle(pages.Visual, "Soft Light & Color", cfg.light, function(v) apply("light", v, setLight) end)
makeSlider(pages.Visual, "Tone (makin tinggi makin datar)", 0.2, 1, 0.05, cfg.tone,
    function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end,
    function(v)
        cfg.tone = v
        save()
        if G.light then lightAcc = 1 end -- diterapkan di tick berikutnya (hemat)
    end)
makeToggle(pages.Visual, "Flat Textures", cfg.tex, function(v) apply("tex", v, setTex) end)
makeToggle(pages.Visual, "Hide Effects", cfg.fx, function(v) apply("fx", v, setFx) end)

-- Status: hijau = nempel di game, kuning = aktif tapi belum ketemu (lobby / race belum mulai), abu = off
local footer = new("Frame", {
    Size = UDim2.new(1, -20, 0, 18),
    Position = UDim2.new(0, 10, 1, -22),
    BackgroundTransparency = 1,
}, window)
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
local dotStam = statusItem("Stamina", 2)
local dotVis = statusItem("Visual", 90)
local function refreshStatus()
    dotStam.BackgroundColor3 = (not cfg.stam) and C.off
        or ((#cfgs == 0) and C.warn)
        or ((os.clock() - leakAt < 3) and C.danger)
        or C.ok
    dotVis.BackgroundColor3 = (cfg.light or cfg.tex or cfg.fx) and C.ok or C.off
end
task.spawn(function()
    while gui.Parent do
        if window.Visible then pcall(refreshStatus) end
        task.wait(0.5)
    end
end)

--// Cleanup (close / re-execute): semua dikembalikan ke aslinya
local function cleanup()
    setStamina(false)
    setEasy(false)
    setSpeed(false)
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
if cfg.stam then setActive("stam", true); setStamina(true) end
if cfg.speed then setActive("speed", true); setSpeed(true) end
if cfg.light then setActive("light", true); setLight(true) end
if cfg.tex then setActive("tex", true); setTex(true) end
if cfg.fx then setActive("fx", true); setFx(true) end
selectTab(TABS[1])

--// QTE Dump v1 — ringan, TANPA warn/print spam (nulis ke buffer -> file + tombol copy)
--// Cara pakai: execute -> main 1 race (1 gate QTE + 1-2 stamina QTE, tap manual) -> tap tombol "DUMP" di kiri atas
--//            -> isi sudah ke-copy ke clipboard & disimpan ke workspace/qte_dump.txt -> paste/kirim
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local VIM = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local env = (getgenv and getgenv()) or _G

if env.__QteDumpCleanup then pcall(env.__QteDumpCleanup) end

local FILE = "qte_dump.txt"
local HOOK_REMOTES = true -- log FireServer/InvokeServer remote QTE (set false kalau mau lebih aman)
local MAX_LINES = 5000

local T0 = os.clock()
local buf, dirty, alive = {}, false, true
local conns = {}

local function log(...)
    if not alive or #buf >= MAX_LINES then return end
    local n = select("#", ...)
    local p = table.create(n)
    for i = 1, n do p[i] = tostring((select(i, ...))) end
    buf[#buf + 1] = string.format("[%7.3f] %s", os.clock() - T0, table.concat(p, " "))
    dirty = true
end
local function conn(c) conns[#conns + 1] = c; return c end
local function f2(n) return string.format("%.3f", n or 0) end

local function absRot(o)
    local ok, r = pcall(function() return o.AbsoluteRotation end)
    return (ok and r) or o.Rotation
end
local function isFx(o)
    return o.Name:sub(1, 3) == "fx_" or (o.Parent and o.Parent.Name:sub(1, 3) == "fx_")
end

local function ser(v, d)
    d = d or 0
    local t = typeof(v)
    if t == "string" then return string.format("%q", v:sub(1, 40)) end
    if t == "Instance" then return "<" .. v:GetFullName() .. ">" end
    if t == "table" then
        if d >= 2 then return "{...}" end
        local out, n = {}, 0
        for k, x in pairs(v) do
            n += 1
            if n > 8 then out[#out + 1] = "..."; break end
            out[#out + 1] = tostring(k) .. "=" .. ser(x, d + 1)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    return tostring(v)
end

local function describe(o)
    local p = {o.ClassName}
    if o:IsA("GuiObject") then
        p[#p + 1] = "vis=" .. tostring(o.Visible)
        p[#p + 1] = string.format("rot=%.2f abs=%.2f", o.Rotation, absRot(o))
        p[#p + 1] = string.format("abspos=(%.0f,%.0f) abssz=(%.0f,%.0f)", o.AbsolutePosition.X, o.AbsolutePosition.Y, o.AbsoluteSize.X, o.AbsoluteSize.Y)
        p[#p + 1] = "pos=" .. tostring(o.Position) .. " size=" .. tostring(o.Size) .. " anchor=" .. tostring(o.AnchorPoint)
        p[#p + 1] = "bgT=" .. f2(o.BackgroundTransparency)
        p[#p + 1] = "z=" .. o.ZIndex
    end
    if o:IsA("GuiButton") then p[#p + 1] = "active=" .. tostring(o.Active) end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then
        p[#p + 1] = "imgT=" .. f2(o.ImageTransparency) .. " img=" .. tostring(o.Image)
    end
    if o:IsA("TextLabel") or o:IsA("TextButton") then
        p[#p + 1] = "text=" .. string.format("%q", o.Text:sub(1, 20)) .. " txtT=" .. f2(o.TextTransparency)
    end
    if o:IsA("CanvasGroup") then p[#p + 1] = "groupT=" .. f2(o.GroupTransparency) end
    if o:IsA("UIGradient") then
        local kp = {}
        for _, k in ipairs(o.Transparency.Keypoints) do kp[#kp + 1] = string.format("%.2f:%.2f", k.Time, k.Value) end
        p[#p + 1] = string.format("rot=%.2f off=(%.2f,%.2f) en=%s T=[%s]", o.Rotation, o.Offset.X, o.Offset.Y, tostring(o.Enabled), table.concat(kp, " "))
    end
    return table.concat(p, " ")
end

local function dumpTree(root, tag)
    log("TREE", tag, root:GetFullName())
    log("  .", describe(root))
    local base = #root:GetFullName() + 2
    local fx = 0
    for _, o in ipairs(root:GetDescendants()) do
        if isFx(o) then fx += 1
        else log("  ", o:GetFullName():sub(base), describe(o)) end
    end
    if fx > 0 then log("  (fx_* descendants:", fx, ")") end
end

--// ===== info environment =====
local function hasFn(name) return type(env[name]) == "function" or type(_G[name]) == "function" end
log("ENV exec=", (identifyexecutor and select(1, identifyexecutor())) or "?",
    "getconnections=", tostring(getconnections ~= nil), "hookmetamethod=", tostring(hookmetamethod ~= nil),
    "getfenv=", tostring(getfenv ~= nil), "debug.info=", tostring(debug and debug.info ~= nil))
log("ENV SendTouchEvent=", tostring(pcall(function() return VIM.SendTouchEvent end)),
    "viewport=", tostring(workspace.CurrentCamera.ViewportSize), "touch=", tostring(UIS.TouchEnabled), "kb=", tostring(UIS.KeyboardEnabled))

--// ===== handler input yang nempel (kunci buat gate) =====
local function listHandlers(label, sig)
    if not getconnections then log("HANDLERS", label, "getconnections gak ada"); return end
    local ok, cs = pcall(getconnections, sig)
    if not (ok and cs) then log("HANDLERS", label, "gagal"); return end
    log("HANDLERS", label, "count=", #cs)
    for i, c in ipairs(cs) do
        local fn = c.Function
        local sc, nm, src, ln = "-", "-", "-", "-"
        if fn then
            pcall(function() local s = getfenv(fn).script; sc = s and s:GetFullName() or "nil" end)
            pcall(function() nm = tostring(debug.info(fn, "n")) end)
            pcall(function() src = tostring(debug.info(fn, "s")) end)
            pcall(function() ln = tostring(debug.info(fn, "l")) end)
        end
        log("  H" .. i, "script=" .. sc, "fn=" .. nm, "src=" .. src, "line=" .. ln)
    end
end
listHandlers("UIS.InputBegan", UIS.InputBegan)

local qteBtn
task.spawn(function()
    local g = pg:WaitForChild("QTEButtonGui", 15)
    qteBtn = g and g:WaitForChild("QTEButton", 5)
    if qteBtn then
        log("QTEBUTTON", describe(qteBtn))
        listHandlers("QTEButton.InputBegan", qteBtn.InputBegan)
        conn(qteBtn.InputBegan:Connect(function(i)
            log("QTEBUTTON press", i.UserInputType.Name, i.UserInputState.Name)
        end))
        conn(qteBtn:GetPropertyChangedSignal("Visible"):Connect(function()
            log("QTEBUTTON visible=", tostring(qteBtn.Visible))
        end))
    end
end)

--// ===== frame QTE =====
local active = {}     -- sampling aktif
local lastAdd, lastKind = -10, "-"

local function startSample(f, kind)
    lastAdd, lastKind = os.clock(), kind
    active[#active + 1] = {f = f, kind = kind, t0 = os.clock(), last = ""}
    task.defer(function()
        task.wait()
        if f.Parent then dumpTree(f, kind) end
    end)
end

local function gs(o)
    if not o then return "nil" end
    return string.format("v%d r%.2f a%.2f p(%.1f,%.1f) s(%.0f,%.0f)", o.Visible and 1 or 0, o.Rotation, absRot(o),
        o.AbsolutePosition.X, o.AbsolutePosition.Y, o.AbsoluteSize.X, o.AbsoluteSize.Y)
end
local function trans(o)
    if o:IsA("CanvasGroup") then return o.GroupTransparency end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then return o.ImageTransparency end
    if o:IsA("TextLabel") or o:IsA("TextButton") then return o.TextTransparency end
    return o.BackgroundTransparency
end

conn(RunService.RenderStepped:Connect(function()
    if #active == 0 then return end
    for i = #active, 1, -1 do
        local e = active[i]
        local el = os.clock() - e.t0
        local f = e.f
        local limit = e.kind == "GateQTE" and 1.6 or 3.5
        if not f.Parent or el > limit then
            table.remove(active, i)
        elseif e.kind == "GateQTE" then
            local parts, fx = {}, 0
            for _, o in ipairs(f:GetDescendants()) do
                if isFx(o) then
                    if o.Name == "fx_ring" then fx += 1 end
                elseif o:IsA("UIGradient") then
                    parts[#parts + 1] = string.format("%s.grad:r%.1f/o(%.2f,%.2f)", o.Parent.Name, o.Rotation, o.Offset.X, o.Offset.Y)
                elseif o:IsA("GuiObject") then
                    parts[#parts + 1] = string.format("%s.%s:t%.2f/r%.0f/w%.0f/v%d", o.Parent.Name, o.Name, trans(o), absRot(o), o.AbsoluteSize.X, o.Visible and 1 or 0)
                end
            end
            local s = table.concat(parts, " ") .. " fx=" .. fx
            if s ~= e.last then
                e.last = s
                log(string.format("GATE +%.3f", el), s)
            end
        else -- StaminaQTE
            local tf = f:FindFirstChild("Timeframe")
            local g = tf and tf:FindFirstChildOfClass("UIGradient")
            log(string.format("STAM +%.3f", el),
                "Time{" .. gs(f:FindFirstChild("Time")) .. "}",
                "Star{" .. gs(tf and tf:FindFirstChild("Star")) .. "}",
                "Correct{" .. gs(tf and tf:FindFirstChild("Correct")) .. "}",
                "Incorrect{" .. gs(tf and tf:FindFirstChild("Incorrect")) .. "}",
                "TF{" .. gs(tf) .. (g and string.format(" g r%.1f o(%.2f,%.2f)", g.Rotation, g.Offset.X, g.Offset.Y) or "") .. "}",
                "frame{" .. gs(f) .. "}")
        end
    end
end))

local function hookGui(qg)
    log("QTEGui", describe(qg))
    conn(qg:GetPropertyChangedSignal("Enabled"):Connect(function()
        log("QTEGui Enabled=", tostring(qg.Enabled))
        if qg.Enabled then listHandlers("UIS.InputBegan(@QTE)", UIS.InputBegan) end
    end))
    conn(qg.ChildAdded:Connect(function(c)
        if c.Name == "GateQTE" or c.Name == "StaminaQTE" then
            log("ADD", c.Name, c.ClassName)
            startSample(c, c.Name)
        elseif c.Name == "StaminaQTEState" then
            log("ADD StaminaQTEState (hasil tap)")
            task.defer(function()
                task.wait(0.05)
                if c.Parent then dumpTree(c, "StaminaQTEState") end
            end)
        end
    end))
    for _, c in ipairs(qg:GetChildren()) do
        if (c.Name == "GateQTE" or c.Name == "StaminaQTE") and c:IsA("GuiButton") then startSample(c, c.Name) end
    end
end
task.spawn(function()
    local qg = pg:WaitForChild("QTEGui", 15)
    if qg then hookGui(qg) else log("QTEGui gak ketemu") end
end)

--// ===== hasil (Great/Good/...) =====
task.spawn(function()
    local qr = pg:WaitForChild("QTEResult", 15)
    if not qr then return end
    local names = {Great = 1, Good = 1, Normal = 1, Bad = 1, Awful = 1, Perfect = 1, Miss = 1}
    conn(qr.DescendantAdded:Connect(function(o)
        if names[o.Name] and o.Parent and o.Parent.Name == "Anchor" then
            log("RESULT", o.Name, string.format("(sinceFrame=%.3f %s)", os.clock() - lastAdd, lastKind))
        end
    end))
end)

--// ===== input mentah (tap kamu) =====
conn(UIS.InputBegan:Connect(function(i, gp)
    local qg = pg:FindFirstChild("QTEGui")
    if (qg and qg.Enabled) or os.clock() - lastAdd < 1.5 then
        log("INPUT", i.UserInputType.Name, i.KeyCode.Name,
            string.format("(%.0f,%.0f)", i.Position.X, i.Position.Y), "gp=" .. tostring(gp),
            string.format("sinceFrame=%.3f %s", os.clock() - lastAdd, lastKind))
    end
end))

--// ===== remote server -> client =====
task.spawn(function()
    local rs = game:GetService("ReplicatedStorage")
    local function w(path)
        local o = rs
        for _, n in ipairs(path) do o = o and o:WaitForChild(n, 10) end
        if o and o:IsA("RemoteEvent") then
            conn(o.OnClientEvent:Connect(function(...)
                local a = table.pack(...)
                local t = {}
                for k = 1, math.min(a.n, 5) do t[k] = ser(a[k]) end
                log("RECV", o.Name, table.concat(t, ", "))
            end))
        end
    end
    w({"Package", "Remotes", "QTE"})
    w({"remotes", "QuickTimeEventAction"})
end)

--// ===== remote client -> server (filter QTE aja) =====
local WATCH = {QuickTimeEventAction = true, QTE = true, SkillBuilderQTE = true, Result = true}
if HOOK_REMOTES and hookmetamethod and getnamecallmethod then
    pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", (newcclosure or function(f) return f end)(function(self, ...)
            local m = getnamecallmethod()
            if alive and (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" and WATCH[self.Name] then
                local a = table.pack(...)
                local t = {}
                for k = 1, math.min(a.n, 5) do t[k] = ser(a[k]) end
                log("CALL", m, self:GetFullName(), table.concat(t, ", "),
                    string.format("(sinceFrame=%.3f %s)", os.clock() - lastAdd, lastKind))
            end
            return old(self, ...)
        end))
    end)
end

--// ===== simpan / copy =====
local function flush(copy)
    local txt = table.concat(buf, "\n")
    pcall(function() if writefile then writefile(FILE, txt) end end)
    if copy then pcall(function() if setclipboard then setclipboard(txt) end end) end
    dirty = false
end
local DURATION = 100 -- detik, habis itu otomatis salin ke clipboard 1x lalu berhenti

local gui = Instance.new("ScreenGui")
gui.Name = "QteDump"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = pg
local lbl = Instance.new("TextLabel")
lbl.Size = UDim2.fromOffset(120, 24)
lbl.Position = UDim2.fromOffset(8, 64)
lbl.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
lbl.TextColor3 = Color3.new(1, 1, 1)
lbl.Font = Enum.Font.GothamBold
lbl.TextSize = 12
lbl.Text = "DUMP " .. DURATION .. "s"
lbl.Parent = gui
Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)

local function stop()
    alive = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
end
env.__QteDumpCleanup = function()
    stop()
    if gui then gui:Destroy() end
end

task.spawn(function()
    local start = os.clock()
    while alive do
        local left = DURATION - (os.clock() - start)
        if left <= 0 then break end
        lbl.Text = string.format("DUMP %ds (%d)", math.ceil(left), #buf)
        task.wait(0.5)
    end
    if not alive then return end
    log("END")
    alive = true -- biar log("END") masuk
    local txt = table.concat(buf, "\n")
    pcall(function() if writefile then writefile(FILE, txt) end end)
    local ok = pcall(function() setclipboard(txt) end)
    stop()
    lbl.Text = ok and ("COPIED " .. #buf .. " baris") or "SELESAI (clipboard gagal, cek qte_dump.txt)"
    lbl.BackgroundColor3 = ok and Color3.fromRGB(74, 222, 128) or Color3.fromRGB(239, 68, 68)
    task.wait(6)
    gui:Destroy()
end)

log("READY — main 1 gate + 1-2 stamina QTE selama " .. DURATION .. "s, otomatis ke-copy di akhir")

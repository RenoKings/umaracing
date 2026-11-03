-- dump2: jalankan di dalam race. Setelah muncul "[dump2] mulai", LARI (tahan tombol sprint),
-- geser layar kiri/kanan, dan tap QTE kalau muncul. Selesai 20 detik -> hasil di clipboard + dump2.txt
local Players, RunService = game:GetService("Players"), game:GetService("RunService")
local P = Players.LocalPlayer
local out = {}
local function log(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    if #out < 600 then out[#out + 1] = table.concat(t, " ") end
end
local function fmt(v)
    if typeof(v) == "table" then
        local t, n = {}, 0
        for k, x in pairs(v) do n += 1; if n > 8 then break end; t[#t + 1] = tostring(k) .. "=" .. tostring(x) end
        return "{" .. table.concat(t, ", ") .. "}"
    end
    return tostring(v)
end

local char = P.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
local root = hum and hum.RootPart

log("== HUMANOID ==")
if hum then log("AutoRotate", hum.AutoRotate, "WalkSpeed", hum.WalkSpeed, "UseJumpPower", hum.UseJumpPower) end
log("== MOVERS / CONSTRAINTS in character ==")
local movers = {AlignOrientation=1, AlignPosition=1, LinearVelocity=1, AngularVelocity=1, VectorForce=1,
    BodyGyro=1, BodyVelocity=1, BodyPosition=1, BodyForce=1, LineForce=1}
if char then
    for _, d in ipairs(char:GetDescendants()) do
        if movers[d.ClassName] then log(d.ClassName, d:GetFullName()) end
    end
end

log("== QTE UI ==")
for _, n in ipairs({"QTEGui", "QTEButtonGui"}) do
    local g = P.PlayerGui:FindFirstChild(n)
    if g then
        log(n, "Enabled=", g.Enabled)
        for _, d in ipairs(g:GetDescendants()) do
            log("  ", d.ClassName, d:GetFullName():gsub("^.-PlayerGui%.", ""), d:IsA("GuiObject") and ("vis=" .. tostring(d.Visible)) or "")
        end
    end
end
local qb = P.PlayerGui:FindFirstChild("QTEButtonGui") and P.PlayerGui.QTEButtonGui:FindFirstChild("QTEButton")
if qb and getconnections then
    for _, sn in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down", "InputBegan", "TouchTap"}) do
        local ok, cs = pcall(getconnections, qb[sn])
        log("QTEButton." .. sn, "connections=", ok and #cs or "err")
    end
end

-- logger FireServer / InvokeServer
log("== REMOTE CALLS (client -> server) ==")
local counts = {}
if hookmetamethod and getnamecallmethod then
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if (m == "FireServer" or m == "InvokeServer") and typeof(self) == "Instance" then
            local n = self:GetFullName():gsub("^ReplicatedStorage%.", "")
            counts[n] = (counts[n] or 0) + 1
            if counts[n] <= 5 then
                local a = {}
                for i = 1, select("#", ...) do a[#a + 1] = fmt((select(i, ...))) end
                log("CALL", m, n, "(" .. table.concat(a, ", ") .. ")")
            end
        end
        return old(self, ...)
    end))
else
    log("hookmetamethod tidak tersedia di executor ini")
end

-- listener server -> client (info stamina dll)
log("== SERVER -> CLIENT (5 pertama) ==")
local RS = game:GetService("ReplicatedStorage")
for _, path in ipairs({"remotes.UpdateClientStamina", "remotes.UpdateClientStats", "remotes.QuickTimeEventAction", "Package.Remotes.QTE", "Package.Remotes.RaceUIUpdate"}) do
    local r = RS
    for part in path:gmatch("[^.]+") do r = r and r:FindFirstChild(part) end
    if r and r:IsA("RemoteEvent") then
        local n = 0
        r.OnClientEvent:Connect(function(...)
            n += 1
            if n <= 5 then
                local a = {}
                for i = 1, select("#", ...) do a[#a + 1] = fmt((select(i, ...))) end
                log("RECV", path, "(" .. table.concat(a, ", ") .. ")")
            end
        end)
    end
end


-- ===== STAMINA HUNT =====
log("== STAMINA HUNT: value/attribute di mana saja ==")
local function nm(n) n = n:lower(); return n:find("stam") or n:find("energy") end
local roots = {P, workspace:FindFirstChild("Players"), game:GetService("ReplicatedStorage"), P:FindFirstChild("PlayerScripts")}
local found = 0
for _, r in ipairs(roots) do
    for _, d in ipairs(r:GetDescendants()) do
        if d:IsDescendantOf(P.PlayerGui) then continue end
        for k, v in pairs(d:GetAttributes()) do
            if nm(k) and found < 40 then found += 1; log("ATTR", d:GetFullName(), k, tostring(v)) end
        end
        if (d:IsA("ValueBase") or d:IsA("ModuleScript")) and nm(d.Name) and found < 40 then
            found += 1
            log(d.ClassName, d:GetFullName(), d:IsA("ValueBase") and tostring(d.Value) or "")
        end
    end
end

log("== STAMINA HUNT: getgc tables yang punya key stamina ==")
if getgc then
    local n = 0
    for _, t in ipairs(getgc(true)) do
        if typeof(t) == "table" and n < 25 then
            local ok = pcall(function()
                for k, v in pairs(t) do
                    if type(k) == "string" and nm(k) then
                        n += 1
                        local keys = {}
                        local c = 0
                        for kk, vv in pairs(t) do c += 1; if c <= 12 then keys[#keys + 1] = tostring(kk) .. "=" .. tostring(vv) end end
                        log("TABLE key=" .. k, "val=" .. tostring(v), "| " .. table.concat(keys, ", "))
                        break
                    end
                end
            end)
        end
    end
    if n == 0 then log("tidak ada table dengan key stamina") end
else
    log("getgc tidak tersedia")
end
if getloadedmodules then
    log("== LOADED MODULES (nama) ==")
    local names = {}
    for _, m in ipairs(getloadedmodules()) do
        if m:IsDescendantOf(P) or m:IsDescendantOf(game:GetService("ReplicatedStorage")) then names[#names + 1] = m:GetFullName():gsub("^.-PlayerScripts%.", "PS."):gsub("^ReplicatedStorage%.", "RS.") end
    end
    log(table.concat(names, " | "))
end

print("[dump2] mulai 20 detik: LARI, geser layar kiri-kanan, tap QTE")
log("== SAMPLING (tiap 0.5s) ==")
task.spawn(function()
    local cam = workspace.CurrentCamera
    for i = 1, 40 do
        task.wait(0.5)
        char = P.Character
        hum = char and char:FindFirstChildOfClass("Humanoid")
        root = hum and hum.RootPart
        if root then
            local v = root.AssemblyLinearVelocity
            local camYaw = math.deg(math.atan2(-cam.CFrame.LookVector.X, -cam.CFrame.LookVector.Z))
            local rl = root.CFrame.LookVector
            local rootYaw = math.deg(math.atan2(-rl.X, -rl.Z))
            local diff = (camYaw - rootYaw + 540) % 360 - 180
            log(("t=%.1f speed=%.1f WS=%.1f move=%.2f pace=%s base=%s camVsRootYaw=%.0f"):format(
                i * 0.5, Vector3.new(v.X, 0, v.Z).Magnitude, hum.WalkSpeed, hum.MoveDirection.Magnitude,
                tostring(char:GetAttribute("PaceSpeedMult")), tostring(root:GetAttribute("BaselineSpeed")), diff))
        end
    end
    local text = table.concat(out, "\n")
    print(text)
    pcall(function() setclipboard(text) end)
    pcall(function() writefile("dump2.txt", text) end)
    print("[dump2] selesai, " .. #out .. " baris (clipboard + dump2.txt)")
end)

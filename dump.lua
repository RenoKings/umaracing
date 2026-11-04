-- dump3: perekam QTE. Execute SEBELUM race mulai (lobby/gate), lalu main normal & TAP QTE start + QTE tikungan sendiri.
-- Selesai 150 dtk -> hasil di clipboard + dump3.txt
local Players, RS, UIS, RunService = game:GetService("Players"), game:GetService("ReplicatedStorage"),
    game:GetService("UserInputService"), game:GetService("RunService")
local P = Players.LocalPlayer
local PG = P:WaitForChild("PlayerGui")
local t0 = os.clock()
local out = {}
local function log(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    if #out < 1500 then out[#out + 1] = ("[%6.2f] "):format(os.clock() - t0) .. table.concat(t, " ") end
end
local function fmt(v)
    if typeof(v) == "table" then
        local t, n = {}, 0
        for k, x in pairs(v) do n += 1; if n > 8 then break end; t[#t + 1] = tostring(k) .. "=" .. tostring(x) end
        return "{" .. table.concat(t, ", ") .. "}"
    end
    return tostring(v)
end
local function args(...)
    local a = {}
    for i = 1, select("#", ...) do a[#a + 1] = fmt((select(i, ...))) end
    return table.concat(a, ", ")
end

-- 1) remote QTE: kirim & terima
local function isQ(n) n = n:lower(); return n:find("qte") or n:find("quick") end
for _, d in ipairs(RS:GetDescendants()) do
    if d:IsA("RemoteEvent") and isQ(d.Name) then
        d.OnClientEvent:Connect(function(...) log("RECV", d:GetFullName(), "(" .. args(...) .. ")") end)
        log("watch remote", d:GetFullName())
    end
end
pcall(function()
    local old
    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if m == "FireServer" and typeof(self) == "Instance" and isQ(self.Name) then
            log("SEND", self:GetFullName(), "(" .. args(...) .. ")")
        end
        return old(self, ...)
    end))
end)

-- 2) input
UIS.InputBegan:Connect(function(i, gp)
    if i.UserInputType == Enum.UserInputType.Keyboard or i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
        log("INPUT", i.UserInputType.Name, i.KeyCode.Name, "gp=" .. tostring(gp))
    end
end)

-- 3) GUI: Enabled/Visible ScreenGui & elemen QTE, + hasil (QTEResult)
local function watchGui(g)
    if not g:IsA("ScreenGui") then return end
    local n = g.Name:lower()
    if not (n:find("qte") or n:find("quick")) then return end
    log("GUI", g.Name, "Enabled=" .. tostring(g.Enabled))
    g:GetPropertyChangedSignal("Enabled"):Connect(function() log("GUI", g.Name, "Enabled=" .. tostring(g.Enabled)) end)
    for _, d in ipairs(g:GetDescendants()) do
        if d:IsA("GuiObject") then
            d:GetPropertyChangedSignal("Visible"):Connect(function()
                log("VIS", d:GetFullName():gsub("^.-PlayerGui%.", ""), tostring(d.Visible))
            end)
        end
    end
    g.DescendantAdded:Connect(function(d) log("ADD", d:GetFullName():gsub("^.-PlayerGui%.", ""), d.ClassName) end)
end
for _, g in ipairs(PG:GetChildren()) do watchGui(g) end
PG.ChildAdded:Connect(watchGui)

-- 4) sampling pointer / success line / gate saat QTE tampil (tiap frame, maks 400 baris)
local samples = 0
RunService.RenderStepped:Connect(function()
    local qg = PG:FindFirstChild("QTEGui")
    if not (qg and qg.Enabled) or samples > 400 then return end
    local sc = qg:FindFirstChild("SkillCheck")
    if sc and sc.Visible then
        local ptr, line = sc:FindFirstChild("Pointer"), sc:FindFirstChild("SuccessLine")
        if ptr and line then
            samples += 1
            log("SC",
                ("ptr rot=%.1f pos=%s abs=%s | line rot=%.1f pos=%s abs=%s size=%s | sc=%s")
                :format(ptr.Rotation, tostring(ptr.Position), tostring(ptr.AbsolutePosition),
                    line.Rotation, tostring(line.Position), tostring(line.AbsolutePosition),
                    tostring(line.AbsoluteSize), tostring(sc.AbsoluteSize)))
        end
    end
    local gate = qg:FindFirstChild("GateQTE")
    if gate and gate.Visible then
        local gl = gate:FindFirstChild("Glow")
        samples += 1
        log("GATE", gl and ("glow vis=%s tr=%.2f size=%s"):format(tostring(gl.Visible), gl.ImageTransparency, tostring(gl.Size)) or "-")
    end
end)

-- 5) tombol QTEButton + koneksinya
pcall(function()
    local qb = PG:FindFirstChild("QTEButtonGui")
    local b = qb and qb:FindFirstChild("QTEButton")
    if b then
        for _, sn in ipairs({"InputBegan", "Activated", "MouseButton1Click", "MouseButton1Down", "TouchTap"}) do
            local ok, cs = pcall(getconnections, b[sn])
            log("QTEButton." .. sn, "connections=", ok and #cs or "err")
        end
        b.InputBegan:Connect(function(i) log("QTEButton press", i.UserInputType.Name) end)
        log("QTEButton vis=", tostring(b.Visible), "text=", b.Text)
    end
    local sc = PG:FindFirstChild("QTEGui") and PG.QTEGui:FindFirstChild("SkillCheck")
    local key = sc and sc:FindFirstChild("Key")
    if key then
        for _, sn in ipairs({"InputBegan", "Activated", "MouseButton1Click", "MouseButton1Down", "TouchTap"}) do
            local ok, cs = pcall(getconnections, key[sn])
            log("SkillCheck.Key." .. sn, "connections=", ok and #cs or "err")
        end
    end
end)

print("[dump3] mulai 150 detik: tunggu start race, TAP QTE start, lalu QTE tikungan")
task.delay(150, function()
    local text = table.concat(out, "\n")
    pcall(function() setclipboard(text) end)
    pcall(function() writefile("dump3.txt", text) end)
    print("[dump3] selesai, " .. #out .. " baris -> clipboard + dump3.txt")
end)

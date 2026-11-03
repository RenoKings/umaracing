-- Jalankan sekali pas lagi di dalam race. Hasil: console + clipboard + dump.txt
local P = game:GetService("Players").LocalPlayer
local out, CAP = {}, 450
local function log(s) if #out < CAP then out[#out + 1] = s end end

local function attrs(o)
    for k, v in pairs(o:GetAttributes()) do
        log(("ATTR  %s . %s = %s"):format(o:GetFullName(), k, tostring(v)))
    end
end

log("== PLAYER / CHARACTER ==")
local char = P.Character
local hum = char and char:FindFirstChildOfClass("Humanoid")
for _, r in ipairs({P, char, hum}) do
    if r then
        attrs(r)
        for _, c in ipairs(r:GetChildren()) do
            if c.Name ~= "PlayerGui" then
                attrs(c)
                if c:IsA("ValueBase") then
                    log(("VALUE %s = %s"):format(c:GetFullName(), tostring(c.Value)))
                end
            end
        end
    end
end
if hum then log(("HUM WalkSpeed=%s JumpPower=%s"):format(hum.WalkSpeed, hum.JumpPower)) end
local root = hum and hum.RootPart
if root then log(("ROOT vel=%s"):format(tostring(root.AssemblyLinearVelocity))) end

log("== GUI (qte/stamina/energy/speed/sprint/run/bar/space) ==")
local pat = {"qte", "stam", "energy", "speed", "sprint", "run", "bar", "space", "zone"}
local function hit(s)
    s = s:lower()
    for _, p in ipairs(pat) do if s:find(p) then return true end end
end
for _, d in ipairs(P.PlayerGui:GetDescendants()) do
    if d:IsA("GuiObject") and d.Name ~= "Panel" and not d:IsDescendantOf(P.PlayerGui:FindFirstChild("Panel") or d) then
        local txt = (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text or ""
        if d:IsA("GuiButton") or hit(d.Name) or hit(txt) then
            if hit(d.Name) or hit(txt) then
                log(("%s [%s] vis=%s size=%s text=%q"):format(d:GetFullName(), d.ClassName, tostring(d.Visible), tostring(d.Size), txt))
            end
        end
    end
end

log("== REMOTES ==")
for _, d in ipairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
    if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("BindableEvent") then
        log(d.ClassName .. "  " .. d:GetFullName())
    end
end

log("== LOCALSCRIPTS ==")
for _, root2 in ipairs({P.PlayerGui, P:FindFirstChild("PlayerScripts"), char}) do
    if root2 then
        for _, d in ipairs(root2:GetDescendants()) do
            if d:IsA("LocalScript") then log("LS  " .. d:GetFullName()) end
        end
    end
end

local text = table.concat(out, "\n")
print(text)
pcall(function() setclipboard(text) end)
pcall(function() writefile("dump.txt", text) end)
print(("[dump] %d lines (copied to clipboard if supported)"):format(#out))

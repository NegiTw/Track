--[[
    RBX Extensions Launcher — Roblox Client Stub
    ============================================
    Paste this into your executor and run it.
    It sends data about your character to the Extensions Launcher's
    HTTP listener at http://127.0.0.1:8123.

    What it sends (every few seconds):
      • /heartbeat — fps, ping, place id, job id
      • /stats     — health, walkspeed, position
      • /inventory — backpack contents
      • /log       — print() output piped through

    SAFE: this script ONLY OBSERVES your own character and sends
    the data out. It doesn't modify the game, attack the server,
    or do anything that would get you banned for cheating.
]]

local HttpService    = game:GetService("HttpService")
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local Stats          = game:GetService("Stats")

local LAUNCHER_URL   = "http://127.0.0.1:8123"
local HEARTBEAT_RATE = 2     -- seconds between heartbeats
local STATS_RATE     = 2     -- seconds between stat updates
local INVENTORY_RATE = 5     -- seconds between inventory snapshots

local player = Players.LocalPlayer
local accountName = player.Name

-- ── HTTP helper ────────────────────────────────────────────────────────
-- Different executors expose request differently. Try them in order.
local function getRequestFn()
    return (syn and syn.request)
        or (http and http.request)
        or http_request
        or (fluxus and fluxus.request)
        or request
end

local httpRequest = getRequestFn()

local function post(path, data)
    if not httpRequest then return end
    local ok, err = pcall(function()
        httpRequest({
            Url     = LAUNCHER_URL .. path,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(data),
        })
    end)
    if not ok then
        warn("[RBX-Ext] Failed to POST " .. path .. ": " .. tostring(err))
    end
end

-- Confirm the launcher is listening
local function pingLauncher()
    if not httpRequest then
        warn("[RBX-Ext] Your executor doesn't expose a request function.")
        return false
    end
    local ok, response = pcall(function()
        return httpRequest({ Url = LAUNCHER_URL .. "/ping", Method = "GET" })
    end)
    if ok and response and response.Body and response.Body:find("pong") then
        print("[RBX-Ext] Connected to Extensions Launcher ✓")
        return true
    else
        warn("[RBX-Ext] Couldn't reach launcher at " .. LAUNCHER_URL)
        warn("[RBX-Ext] Make sure 'RBX Extensions Launcher' is running and 'Roblox Bridge' is enabled.")
        return false
    end
end

-- ── Data collection ────────────────────────────────────────────────────
local function getHeartbeat()
    return {
        account = accountName,
        place   = tostring(game.PlaceId),
        jobId   = game.JobId or "",
        fps     = math.floor(1 / RunService.Heartbeat:Wait()),
        ping    = math.floor((Stats.Network.ServerStatsItem["Data Ping"]:GetValue() or 0)),
        time    = os.time(),
    }
end

local function getStats()
    local char = player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum then return nil end

    local pos = ""
    if root then
        local p = root.Position
        pos = string.format("%.0f, %.0f, %.0f", p.X, p.Y, p.Z)
    end

    return {
        account   = accountName,
        health    = math.floor(hum.Health),
        maxHealth = math.floor(hum.MaxHealth),
        walkspeed = hum.WalkSpeed,
        position  = pos,
    }
end

local function getInventory()
    local items = {}
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            table.insert(items, {
                name  = tool.Name,
                count = 1,
                type  = tool.ClassName,
            })
        end
    end
    -- Also include currently-equipped tool
    local char = player.Character
    if char then
        local equipped = char:FindFirstChildOfClass("Tool")
        if equipped then
            table.insert(items, {
                name  = equipped.Name .. " (equipped)",
                count = 1,
                type  = equipped.ClassName,
            })
        end
    end
    return { account = accountName, items = items }
end

-- ── Print() interceptor ───────────────────────────────────────────────
-- Hooks the global print so anything printed in-game shows up in the
-- Execution Logs tab of the launcher.
local oldPrint = print
local oldWarn  = warn
_G.print = function(...)
    local args = { ... }
    local parts = {}
    for i, v in ipairs(args) do parts[i] = tostring(v) end
    local msg = table.concat(parts, " ")
    pcall(function()
        post("/log", { account = accountName, level = "info", message = msg })
    end)
    oldPrint(...)
end
_G.warn = function(...)
    local args = { ... }
    local parts = {}
    for i, v in ipairs(args) do parts[i] = tostring(v) end
    local msg = table.concat(parts, " ")
    pcall(function()
        post("/log", { account = accountName, level = "warn", message = msg })
    end)
    oldWarn(...)
end

-- ── Main loop ─────────────────────────────────────────────────────────
if not pingLauncher() then return end

post("/log", { account = accountName, level = "info", message = "Client stub connected" })

task.spawn(function()
    while true do
        local hb = getHeartbeat()
        if hb then post("/heartbeat", hb) end
        task.wait(HEARTBEAT_RATE)
    end
end)

task.spawn(function()
    while true do
        local s = getStats()
        if s then post("/stats", s) end
        task.wait(STATS_RATE)
    end
end)

task.spawn(function()
    while true do
        local inv = getInventory()
        if inv then post("/inventory", inv) end
        task.wait(INVENTORY_RATE)
    end
end)

print("[RBX-Ext] Stub running. Switch to the launcher to see your data.")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

if PlayerGui:FindFirstChild("AutoTradeGUI") then return end

local TradeRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TradeRemotes")
local AddItemToTrade   = TradeRemotes:WaitForChild("AddItemToTrade")
local RespondToRequest = TradeRemotes:WaitForChild("RespondToRequest")
local SetReady         = TradeRemotes:WaitForChild("SetReady")
local ConfirmTrade     = TradeRemotes:WaitForChild("ConfirmTrade")
local GetTradablePlayers = TradeRemotes:WaitForChild("GetTradablePlayers")
local RequestInventory = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestInventory")
local TradeUpdated     = TradeRemotes:WaitForChild("TradeUpdated")

local tradeLists = {
    ["Started Kit"] = {
        {"Legendary Chest", 999999},
        {"Mythical Chest", 999999},
        {"Passive Shard", 999999},
        {"Power Shard", 999999},
        {"Boss Ticket", 999999},
        {"Clan Reroll", 999999},
        {"Void Fragment", 999999},
        {"Hōgyoku Fragment", 999999},
        {"Limitless Ring", 999999},
        {"Dark Ring", 999999},
        {"Blood Ring", 999999},
        {"Dismantle Fang", 999999},
        {"Reiatsu Core", 999999},
        {"Atomic Core", 999999},
        {"Ice Core", 999999,
        {"Frozen Brand", 999999},
        {"Glacier Remnant", 999999},
        {"Battle Shard", 999999},
        {"Frost Relic", 999999},
        {"Crystal Key", 999999},
        {"Wood", 999999},
        {"Iron", 999999},
        {"Obsidian", 999999},
        {"Mythril", 999999},
        {"Adamantite", 999999},
    },
    ["Cosmic Set"] = {
        {"Monster Pulse", 2},
        {"Galaxy Shard", 5},
        {"Star Mark", 8},
        {"Cosmic Essence", 12},
    },
    ["The World Set"] = {
        {"Dominion Brand", 80},
        {"Power Fragment", 20},
        {"Time Remnant", 12},
        {"World Core", 6},
        {"Vampire Omen", 2},
    },
    ["The World Set + Bloodline"] = {
        {"Dominion Brand", 999999},
        {"Power Fragment", 999999},
        {"Time Remnant", 999999},
        {"World Core", 999999},
        {"Vampire Omen", 999999},
		{"Bloodline Stone", 999999},
    },
    ["Mat B10"] = {
        {"Wood", 6000},
        {"Iron", 3000},
        {"Obsidian", 1000},
        {"Mythril", 600},
        {"Adamantite", 200},
    },
}

-- State
local running = false
local autoFullEnabled = false
local autoReceiveEnabled = false
local selectedList = nil
local statusLabel
local autoBtn, receiveBtn
local lastRequestText = ""
local meReady = false
local meConfirmed = false

local function setStatus(msg)
    print("[AutoTrade] " .. msg)
    if statusLabel then statusLabel.Text = "Status: " .. msg end
end

local function isTradeOpen()
    local ui = PlayerGui:FindFirstChild("InTradingUI")
    if not ui then return false end
    if ui.Enabled == false then return false end
    return ui:FindFirstChild("MainFrame") ~= nil
end

-- Get state by inspecting the ReadyIndicator's actual visibility
-- Returns: "ready", "confirmed", or "none"
local function getSideState(holderName)
    local ui = PlayerGui:FindFirstChild("InTradingUI")
    if not ui then return "none" end
    local mf = ui:FindFirstChild("MainFrame"); if not mf then return "none" end
    local fr = mf:FindFirstChild("Frame"); if not fr then return "none" end
    local ct = fr:FindFirstChild("Content"); if not ct then return "none" end

    -- Find any side that contains the holderName
    local holder = nil
    for _, side in ipairs(ct:GetChildren()) do
        local h = side:FindFirstChild(holderName, true)
        if h then holder = h break end
    end

    if not holder then return "none" end

    local ri = holder:FindFirstChild("ReadyIndicator")
    if not ri then return "none" end

    -- Check visibility properly: Visible AND has visible content
    if not ri.Visible then return "none" end

    -- Get the Txt label and check if it's actually rendered (not transparent)
    local txt = ri:FindFirstChild("Txt")
    if not txt then return "none" end

    -- The label always has text "READY", but visibility/transparency changes
    -- Check actual text content for state distinction
    local rawText = (txt.Text or ""):upper():gsub("<[^>]+>", "")

    -- Check if the indicator's visual elements are actually showing
    -- Background transparency or ImageLabel transparency reveals true state
    local visualVisible = false
    for _, child in ipairs(ri:GetDescendants()) do
        if child:IsA("ImageLabel") or child:IsA("Frame") then
            if child.Visible and (child.BackgroundTransparency < 1 or (child:IsA("ImageLabel") and child.ImageTransparency < 1)) then
                visualVisible = true
                break
            end
        end
    end
    -- Also check Txt's transparency itself
    if txt.TextTransparency < 1 and txt.Visible then
        visualVisible = true
    end

    if not visualVisible then return "none" end

    if rawText:find("CONFIRM") then return "confirmed" end
    if rawText:find("READY") then return "ready" end

    return "none"
end

-- React to TradeUpdated
TradeUpdated.OnClientEvent:Connect(function(...)
    if not running then return end
    if not (autoReceiveEnabled or autoFullEnabled) then return end
    if not isTradeOpen() then return end

    task.wait(0.4)

    local p1State = getSideState("Player1Holder")
    local p2State = getSideState("Player2Holder")
    print("[AutoTrade] TradeUpdated → P1:", p1State, "P2:", p2State, "meReady:", meReady, "meConfirmed:", meConfirmed)

    -- Logic: if I haven't readied and ANY side shows ready → that's the other player
    -- If I've readied and a NEW side shows confirmed → that's the other player
    local otherState = "none"
    if not meReady then
        -- Whichever side shows ready is the other player (we know we're not ready)
        if p1State == "ready" or p1State == "confirmed" then otherState = p1State
        elseif p2State == "ready" or p2State == "confirmed" then otherState = p2State end
    else
        -- We're ready. If both show ready, look for one that's confirmed
        if p1State == "confirmed" and p2State == "ready" then otherState = "confirmed"
        elseif p2State == "confirmed" and p1State == "ready" then otherState = "confirmed"
        elseif p1State == "confirmed" and p2State == "confirmed" then otherState = "confirmed" end
    end

    if otherState == "confirmed" and not meConfirmed and meReady then
        meConfirmed = true
        setStatus("✅ Other CONFIRMED → confirming")
        ConfirmTrade:FireServer()
        setStatus("⏱ Waiting 10s after confirm...")
        task.wait(10)
        setStatus("✅ Trade complete!")
        running = false
        meReady = false
        meConfirmed = false
        lastRequestText = ""
    elseif otherState == "ready" and not meReady then
        meReady = true
        setStatus("✅ Other READY → setting ready")
        task.wait(0.4)
        SetReady:FireServer(true)
    end
end)

-- Watch for incoming trade requests
local function watchIncomingRequest()
    while autoReceiveEnabled or autoFullEnabled do
        if not running then
            local reqUI = PlayerGui:FindFirstChild("TradeRequestUI")
            if reqUI then
                for _, d in ipairs(reqUI:GetDescendants()) do
                    if (d:IsA("TextLabel") or d:IsA("TextButton")) then
                        local t = d.Text or ""
                        if (t:find("Incoming Trade") or t:find("wants to trade")) and t ~= lastRequestText then
                            local visible = reqUI.Enabled ~= false
                            if visible then
                                local p = d
                                while p and p ~= reqUI do
                                    if p:IsA("GuiObject") and p.Visible == false then
                                        visible = false
                                        break
                                    end
                                    p = p.Parent
                                end
                            end

                            if visible then
                                lastRequestText = t
                                running = true
                                meReady = false
                                meConfirmed = false

                                local fromName = t:match(">(.-)</") or "Unknown"
                                setStatus("📨 Request from: " .. fromName)
                                task.wait(0.4)

                                setStatus("Accepting...")
                                RespondToRequest:FireServer(true)
                                task.wait(2)

                                if autoFullEnabled and selectedList then
                                    local items = tradeLists[selectedList]
                                    setStatus("Adding items: " .. selectedList)
                                    RequestInventory:FireServer()
                                    task.wait(0.8)
                                    for _, data in ipairs(items) do
                                        local amount = data[2]
                                        setStatus("Adding " .. data[1] .. " x" .. amount)
                                        AddItemToTrade:FireServer("Items", data[1], amount)
                                        task.wait(0.65)
                                    end
                                    setStatus("Setting ready...")
                                    SetReady:FireServer(true)
                                    meReady = true
                                    task.wait(1)
                                    setStatus("Confirming...")
                                    ConfirmTrade:FireServer()
                                    meConfirmed = true
                                    setStatus("⏱ Waiting 10s after confirm...")
                                    task.wait(10)
                                    setStatus("✅ Done!")
                                    running = false
                                    meReady = false
                                    meConfirmed = false
                                    lastRequestText = ""
                                else
                                    setStatus("Accepted! Watching other player...")
                                end
                                break
                            end
                        end
                    end
                end
            end

            if running and not autoFullEnabled and not isTradeOpen() and lastRequestText ~= "" then
                task.wait(2)
                if not isTradeOpen() then
                    setStatus("Trade closed. Watching for next...")
                    running = false
                    meReady = false
                    meConfirmed = false
                    lastRequestText = ""
                end
            end
        end
        task.wait(0.4)
    end
    lastRequestText = ""
end

-- Backup polling loop in case TradeUpdated misses an event
local function backupPoller()
    while autoReceiveEnabled or autoFullEnabled do
        if running and isTradeOpen() then
            local p1State = getSideState("Player1Holder")
            local p2State = getSideState("Player2Holder")

            local otherState = "none"
            if not meReady then
                if p1State == "ready" or p1State == "confirmed" then otherState = p1State
                elseif p2State == "ready" or p2State == "confirmed" then otherState = p2State end
            else
                if p1State == "confirmed" and p2State ~= "none" then otherState = "confirmed"
                elseif p2State == "confirmed" and p1State ~= "none" then otherState = "confirmed" end
            end

            if otherState == "ready" and not meReady then
                meReady = true
                setStatus("✅ [Poll] Other READY → setting ready")
                SetReady:FireServer(true)
                task.wait(1)
            elseif otherState == "confirmed" and not meConfirmed and meReady then
                meConfirmed = true
                setStatus("✅ [Poll] Other CONFIRMED → confirming")
                ConfirmTrade:FireServer()
                task.wait(10)
                setStatus("✅ Trade complete!")
                running = false
                meReady = false
                meConfirmed = false
                lastRequestText = ""
            end
        end
        task.wait(1.5)
    end
end

local function autoScanLoop()
    while autoFullEnabled do
        if not running then
            setStatus("Scanning for players...")
            local ok, result = pcall(function() return GetTradablePlayers:InvokeServer() end)
            if ok and result and type(result) == "table" and #result > 0 then
                for _, target in ipairs(result) do
                    if not autoFullEnabled then break end
                    if not running and target ~= player then
                        setStatus("Sending request: " .. target.Name)
                        local reqRemote = TradeRemotes:FindFirstChild("RequestTrade")
                            or TradeRemotes:FindFirstChild("SendTradeRequest")
                            or TradeRemotes:FindFirstChild("TradeRequest")
                        if reqRemote then reqRemote:FireServer(target)
                        else setStatus("RequestTrade missing - receive only") break end
                        task.wait(5)
                    end
                end
            else
                setStatus("No tradable players found...")
            end
        end
        task.wait(3)
    end
end

-- DEBUG: dump full ReadyIndicator state
local function dumpReadyIndicators()
    local ui = PlayerGui:FindFirstChild("InTradingUI")
    if not ui then print("No UI") return end
    print("======= READY INDICATORS =======")
    for _, h in ipairs({"Player1Holder", "Player2Holder"}) do
        for _, side in ipairs(ui.MainFrame.Frame.Content:GetChildren()) do
            local holder = side:FindFirstChild(h, true)
            if holder then
                local ri = holder:FindFirstChild("ReadyIndicator")
                if ri then
                    print(h .. " [in " .. side.Name .. "]:")
                    print("  ReadyIndicator.Visible =", ri.Visible)
                    if ri:IsA("Frame") then
                        print("  ReadyIndicator.BackgroundTransparency =", ri.BackgroundTransparency)
                    end
                    for _, c in ipairs(ri:GetDescendants()) do
                        local extra = ""
                        if c:IsA("TextLabel") or c:IsA("TextButton") then
                            extra = " Text='" .. (c.Text or "") .. "' TextTrans=" .. tostring(c.TextTransparency)
                        elseif c:IsA("ImageLabel") then
                            extra = " ImgTrans=" .. tostring(c.ImageTransparency) .. " BgTrans=" .. tostring(c.BackgroundTransparency)
                        elseif c:IsA("Frame") then
                            extra = " BgTrans=" .. tostring(c.BackgroundTransparency)
                        end
                        print("    [" .. c.ClassName .. "] " .. c.Name .. " Visible=" .. tostring(c.Visible) .. extra)
                    end
                end
            end
        end
    end
    print("================================")
end

-- ===================== GUI =====================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoTradeGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = PlayerGui
ScreenGui.DisplayOrder = 999999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.IgnoreGuiInset = true

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.Size = UDim2.new(0, 270, 0, 510)
MainFrame.Position = UDim2.new(0.05, 0, 0.1, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local TitleBar = Instance.new("Frame")
TitleBar.Parent = MainFrame
TitleBar.Size = UDim2.new(1, 0, 0, 36)
TitleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Parent = TitleBar
Title.Size = UDim2.new(1, -80, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "🔄 Auto Trade"
Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 18
Title.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = TitleBar
CloseBtn.Size = UDim2.new(0, 28, 0, 24)
CloseBtn.Position = UDim2.new(1, -33, 0, 6)
CloseBtn.Text = "✕"
CloseBtn.BackgroundColor3 = Color3.fromRGB(200,50,50)
CloseBtn.TextColor3 = Color3.fromRGB(255,255,255)
CloseBtn.Font = Enum.Font.SourceSansBold
CloseBtn.TextSize = 15
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseButton1Click:Connect(function()
    autoFullEnabled = false
    autoReceiveEnabled = false
    ScreenGui:Destroy()
end)

local dragging, dragStart, startPos = false, nil, nil
TitleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = i.Position; startPos = MainFrame.Position
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end)

local Content = Instance.new("ScrollingFrame")
Content.Parent = MainFrame
Content.Size = UDim2.new(1, -16, 1, -46)
Content.Position = UDim2.new(0, 8, 0, 42)
Content.BackgroundTransparency = 1
Content.ScrollBarThickness = 4
Content.ScrollBarImageColor3 = Color3.fromRGB(80,80,80)
Content.CanvasSize = UDim2.new(0, 0, 0, 0)

local Layout = Instance.new("UIListLayout")
Layout.Parent = Content
Layout.Padding = UDim.new(0, 7)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Content.CanvasSize = UDim2.new(0,0,0, Layout.AbsoluteContentSize.Y + 10)
end)

statusLabel = Instance.new("TextLabel")
statusLabel.Parent = Content
statusLabel.Size = UDim2.new(1, 0, 0, 32)
statusLabel.BackgroundColor3 = Color3.fromRGB(25,25,25)
statusLabel.TextColor3 = Color3.fromRGB(120,220,120)
statusLabel.Font = Enum.Font.SourceSans
statusLabel.TextSize = 13
statusLabel.Text = "Status: Pick a mode"
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.LayoutOrder = 1
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 6)

receiveBtn = Instance.new("TextButton")
receiveBtn.Parent = Content
receiveBtn.Size = UDim2.new(1, 0, 0, 38)
receiveBtn.BackgroundColor3 = Color3.fromRGB(70,130,200)
receiveBtn.TextColor3 = Color3.fromRGB(255,255,255)
receiveBtn.Font = Enum.Font.SourceSansBold
receiveBtn.TextSize = 15
receiveBtn.Text = "📥 Receive Only (Auto Accept)"
receiveBtn.LayoutOrder = 2
Instance.new("UICorner", receiveBtn).CornerRadius = UDim.new(0, 8)

receiveBtn.MouseButton1Click:Connect(function()
    if autoFullEnabled then setStatus("⚠ Disable Full Auto first!") return end
    autoReceiveEnabled = not autoReceiveEnabled
    if autoReceiveEnabled then
        receiveBtn.Text = "⏹ Stop Receive Mode"
        receiveBtn.BackgroundColor3 = Color3.fromRGB(180,80,40)
        setStatus("Receive ON - watching for requests")
        task.spawn(watchIncomingRequest)
        task.spawn(backupPoller)
    else
        receiveBtn.Text = "📥 Receive Only (Auto Accept)"
        receiveBtn.BackgroundColor3 = Color3.fromRGB(70,130,200)
        running = false
        meReady = false
        meConfirmed = false
        lastRequestText = ""
        setStatus("Receive OFF")
    end
end)

autoBtn = Instance.new("TextButton")
autoBtn.Parent = Content
autoBtn.Size = UDim2.new(1, 0, 0, 38)
autoBtn.BackgroundColor3 = Color3.fromRGB(40,130,40)
autoBtn.TextColor3 = Color3.fromRGB(255,255,255)
autoBtn.Font = Enum.Font.SourceSansBold
autoBtn.TextSize = 15
autoBtn.Text = "▶ Start Full Auto Trade"
autoBtn.LayoutOrder = 3
Instance.new("UICorner", autoBtn).CornerRadius = UDim.new(0, 8)

autoBtn.MouseButton1Click:Connect(function()
    if autoReceiveEnabled then setStatus("⚠ Disable Receive Only first!") return end
    if not selectedList then setStatus("⚠ Select a list first!") return end
    autoFullEnabled = not autoFullEnabled
    if autoFullEnabled then
        autoBtn.Text = "⏹ Stop Full Auto Trade"
        autoBtn.BackgroundColor3 = Color3.fromRGB(180,40,40)
        setStatus("Full Auto ON - scanning...")
        task.spawn(autoScanLoop)
        task.spawn(watchIncomingRequest)
    else
        running = false
        meReady = false
        meConfirmed = false
        lastRequestText = ""
        autoBtn.Text = "▶ Start Full Auto Trade"
        autoBtn.BackgroundColor3 = Color3.fromRGB(40,130,40)
        setStatus("Full Auto OFF")
    end
end)

-- Debug button
local debugBtn = Instance.new("TextButton")
debugBtn.Parent = Content
debugBtn.Size = UDim2.new(1, 0, 0, 30)
debugBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
debugBtn.TextColor3 = Color3.fromRGB(255,255,255)
debugBtn.Font = Enum.Font.SourceSans
debugBtn.TextSize = 13
debugBtn.Text = "🔍 Debug: Dump Ready Indicators"
debugBtn.LayoutOrder = 4
Instance.new("UICorner", debugBtn).CornerRadius = UDim.new(0, 6)
debugBtn.MouseButton1Click:Connect(dumpReadyIndicators)

local sep = Instance.new("TextLabel")
sep.Parent = Content
sep.Size = UDim2.new(1, 0, 0, 18)
sep.BackgroundTransparency = 1
sep.Text = "── Trade List (for Full Auto) ──"
sep.TextColor3 = Color3.fromRGB(130,130,130)
sep.Font = Enum.Font.SourceSans
sep.TextSize = 13
sep.LayoutOrder = 5

local colors = {
    ["Started Kit"]               = Color3.fromRGB(40,130,210),
    ["Cosmic Set"]                = Color3.fromRGB(130,50,200),
    ["The World Set"]             = Color3.fromRGB(180,80,30),
    ["The World Set + Bloodline"] = Color3.fromRGB(160,40,40),
    ["Mat B10"]                   = Color3.fromRGB(50,140,80),
}

local selectedBtn = nil
local order = 6
for tradeName, _ in pairs(tradeLists) do
    local col = colors[tradeName] or Color3.fromRGB(60,60,60)
    local btn = Instance.new("TextButton")
    btn.Parent = Content
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(45,45,45)
    btn.TextColor3 = Color3.fromRGB(220,220,220)
    btn.Font = Enum.Font.SourceSansBold
    btn.TextSize = 15
    btn.Text = tradeName
    btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.LayoutOrder = order
    order += 1
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    btn.MouseButton1Click:Connect(function()
        if selectedBtn then
            selectedBtn.BackgroundColor3 = Color3.fromRGB(45,45,45)
            selectedBtn.TextColor3 = Color3.fromRGB(220,220,220)
        end
        selectedList = tradeName
        btn.BackgroundColor3 = col
        btn.TextColor3 = Color3.fromRGB(255,255,255)
        selectedBtn = btn
        setStatus("Selected: " .. tradeName)
    end)
end

setStatus("Pick a mode: Receive Only or Full Auto")
print("[AutoTrade] Loaded OK")

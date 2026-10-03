-- ====== ULTIMATE EVIL HUB v17.8 ======
-- Cleaned: Removed standalone NPC Killer ESP feature
-- Added: NPC killer fallback in killer-studs display (only if no player killer found)
-- Kept: All other features from v17.7

print("🚀 Ultimate Evil Hub v17.8 loading...")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local Lighting = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer

-- ====== REPAIR MODULE ======
local Repair = {}
Repair.Connections = {}
Repair.Heartbeats = {}
Repair.LastRepairTime = 0
Repair.RepairInterval = 5
Repair.Unloaded = false

function Repair.Connect(signal, callback)
    local conn = signal:Connect(callback)
    table.insert(Repair.Connections, conn)
    return conn
end

function Repair.RegisterHeartbeat(name, signal, callback)
    if Repair.Heartbeats[name] then
        pcall(function() Repair.Heartbeats[name].conn:Disconnect() end)
    end
    local conn = signal:Connect(callback)
    Repair.Heartbeats[name] = {conn = conn, signal = signal, callback = callback}
    return conn
end

function Repair.DisconnectAll()
    for _, conn in ipairs(Repair.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    Repair.Connections = {}
    for _, hb in pairs(Repair.Heartbeats) do
        pcall(function() hb.conn:Disconnect() end)
    end
    Repair.Heartbeats = {}
end

function Repair.CleanOrphans()
    local folders = {"EvilHub_ESP", "EvilHub_Objectives", "EvilHub_HitboxESP", "EvilHub_InfoDisplay", "EvilHub_KillerHealth"}
    for _, folderName in ipairs(folders) do
        local folder = CoreGui:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("Highlight") or child:IsA("BillboardGui") or child:IsA("BoxHandleAdornment") then
                    local adornee = child.Adornee
                    if not adornee or not adornee.Parent then
                        child:Destroy()
                    end
                end
            end
        end
    end
end

function Repair.EnsureHeartbeats()
    for name, hb in pairs(Repair.Heartbeats) do
        local ok = pcall(function() return hb.conn.Connected end)
        if not ok or not hb.conn.Connected then
            local newConn = hb.signal:Connect(hb.callback)
            Repair.Heartbeats[name].conn = newConn
        end
    end
end

function Repair.RunFullRepair()
    if Repair.Unloaded then return end
    local now = tick()
    if now - Repair.LastRepairTime < Repair.RepairInterval then return end
    Repair.LastRepairTime = now
    pcall(Repair.CleanOrphans)
    pcall(Repair.EnsureHeartbeats)
end

task.spawn(function()
    while not Repair.Unloaded do
        task.wait(1)
        pcall(Repair.RunFullRepair)
    end
end)

-- ====== SETTINGS ======
_G.EvilHub = {
    WalkSpeed = false, ForceJump = false, Noclip = false,
    ESP = false, ObjectivesESP = false, StaminaESP = false,
    InfiniteStamina = false, HitboxExpander = false, HitboxESP = false,
    HitboxSize = 3, KillerStuds = false, MapDisplay = false,
    DoubleJump = false, Launch = false, AutoObjective = false,
    KillerHealthESP = false, KillFeed = false, SilentAim = false,
    SilentAimFOV = 150, WalkSpeedValue = 25,
    LaunchKey = Enum.KeyCode.F, FrontflipKey = Enum.KeyCode.P,
    ShakeKey = Enum.KeyCode.H,
    AntiSlow = false,
    LowHPAlert = false,
    AutoTasks = false,
    InstantInteract = false,
    RemoveEffects = false,
    FullBright = false,
    NoFog = false,
}

local ESP_COLORS = {
    Survivor = {Fill = Color3.fromRGB(111, 181, 255), Outline = Color3.fromRGB(138, 210, 255)},
    Killer   = {Fill = Color3.fromRGB(255, 94, 94),  Outline = Color3.fromRGB(255, 0, 0)},
}

local WalkspeedEnabled = false

-- ====== RAYFIELD ======
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Ultimate Evil Hub v17.8",
    Icon = 0,
    LoadingTitle = "Ultimate Evil Hub",
    LoadingSubtitle = "v17.8 • Clean Build",
    Theme = "Amethyst",
    ConfigurationSaving = {Enabled = false},
    Discord = {Enabled = false},
    KeySystem = false,
})

-- ====== HELPER: KEYBIND DROPDOWN ======
local function CreateKeybindDropdown(parent, name, currentKey, callback)
    local keyList = {
        "Space", "F", "G", "H", "J", "K", "L", "P", "Q", "R", "T", "U", "V", "X", "Y", "Z",
        "LeftShift", "RightShift", "LeftControl", "RightControl", "LeftAlt", "RightAlt",
        "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero",
    }
    local currentName = (typeof(currentKey) == "EnumItem" and currentKey.Name) or "F"
    parent:CreateDropdown({
        Name = name,
        Options = keyList,
        CurrentOption = {currentName},
        MultipleOptions = false,
        Flag = name:gsub("%s+", "") .. "_Keybind",
        Callback = function(Option)
            local keyName = Option[1]
            local enumKey = Enum.KeyCode[keyName]
            if enumKey then
                callback(enumKey)
                Rayfield:Notify({Title = "Keybind", Content = name .. " set to " .. keyName, Duration = 2})
            end
        end,
    })
end

-- ====== NPC KILLER FALLBACK (throttled, only used if no player killer) ======
local killerNPCCache = nil
local killerNPCLastScan = 0

local function FindKillerNPC()
    local now = tick()
    if killerNPCCache and killerNPCCache.Parent then
        local hum = killerNPCCache:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            return killerNPCCache
        end
    end
    if now - killerNPCLastScan < 2 then return killerNPCCache end
    killerNPCLastScan = now
    local live = Workspace:FindFirstChild("Live")
    local container = live or Workspace
    for _, obj in ipairs(container:GetChildren()) do
        if obj:IsA("Model") and obj.Name:lower():find("killer") and not obj.Name:lower():find("barrier") then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                killerNPCCache = obj
                return obj
            end
        end
    end
    killerNPCCache = nil
    return nil
end

-- ====== GET OBJECTIVES ======
local function GetActiveObjectives()
    local live = Workspace:FindFirstChild("Live")
    if not live then return nil end
    local map = live:FindFirstChild("Map")
    if not map then return nil end
    local mapModel = map:FindFirstChild("MapModel") or map:FindFirstChild("Mapmodel")
    if not mapModel then return nil end
    return mapModel:FindFirstChild("ActiveObjectives")
end

-- ====== LOW HP SURVIVOR ======
local function GetLowHPSurvivor()
    local closest = nil
    local shortest = math.huge
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health < 50 and hum.Health > 0 then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                if root then
                    local dist = (myRoot.Position - root.Position).Magnitude
                    if dist < shortest then
                        shortest = dist
                        closest = player.Character
                    end
                end
            end
        end
    end
    return closest
end

-- ====== FORCE JUMP ======
local jumpConnection = nil
local forceJumpEnabled = false

local function StartForceJump()
    if jumpConnection then jumpConnection:Disconnect() end
    forceJumpEnabled = true
    jumpConnection = RunService.Heartbeat:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        if humanoid.JumpPower ~= 50 then humanoid.JumpPower = 50 end
        humanoid.UseJumpPower = true
        if char:GetAttribute("JumpPower") ~= 50 then
            char:SetAttribute("JumpPower", 50)
        end
    end)
end

local function StopForceJump()
    forceJumpEnabled = false
    if jumpConnection then
        jumpConnection:Disconnect()
        jumpConnection = nil
    end
end

-- ====== MOVEMENT ======
local function ApplyMovement()
    local char = LocalPlayer.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if WalkspeedEnabled then
        local ws = tonumber(_G.EvilHub.WalkSpeedValue) or 16
        char:SetAttribute("WalkSpeed", ws)
        humanoid.WalkSpeed = ws
    end
end

Repair.Connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.5)
    ApplyMovement()
end)

Repair.RegisterHeartbeat("ApplyMovement", RunService.Heartbeat, ApplyMovement)

-- ====== ANTI SLOW ======
Repair.RegisterHeartbeat("AntiSlow", RunService.Heartbeat, function()
    if not _G.EvilHub.AntiSlow then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed < 28 then
        hum.WalkSpeed = 28
    end
end)

-- ====== INFINITE STAMINA ======
local staminaConnection = nil
local function EnableInfiniteStamina()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    if staminaConnection then staminaConnection:Disconnect() end
    staminaConnection = character:GetAttributeChangedSignal("Stamina"):Connect(function()
        character:SetAttribute("Stamina", 100)
    end)
    character:SetAttribute("Stamina", 100)
end

local function DisableInfiniteStamina()
    if staminaConnection then
        staminaConnection:Disconnect()
        staminaConnection = nil
    end
end

Repair.Connect(LocalPlayer.CharacterAdded, function(char)
    if _G.EvilHub.InfiniteStamina then
        task.wait(0.5)
        if staminaConnection then staminaConnection:Disconnect() end
        staminaConnection = char:GetAttributeChangedSignal("Stamina"):Connect(function()
            char:SetAttribute("Stamina", 100)
        end)
        char:SetAttribute("Stamina", 100)
    end
end)

-- ====== NOCLIP ======
local noclipConnection = nil

local function StartNoclip()
    if noclipConnection then noclipConnection:Disconnect() end
    _G.EvilHub.Noclip = true
    noclipConnection = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

local function StopNoclip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    _G.EvilHub.Noclip = false
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end
end

-- ====== FRONTFLIP ======
local frontflipCooldown = false
local function DoFrontflip()
    if frontflipCooldown then return end
    frontflipCooldown = true
    local char = LocalPlayer.Character
    if not char then frontflipCooldown = false return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid then frontflipCooldown = false return end

    local startCFrame = root.CFrame
    local direction = startCFrame.LookVector

    local bodyGyro = Instance.new("BodyGyro")
    bodyGyro.MaxTorque = Vector3.new(40000, 40000, 40000)
    bodyGyro.P = 3000
    bodyGyro.D = 500
    bodyGyro.CFrame = startCFrame
    bodyGyro.Parent = root

    local bodyVelocity = Instance.new("BodyVelocity")
    bodyVelocity.MaxForce = Vector3.new(40000, 40000, 40000)
    bodyVelocity.Velocity = direction * 30 + Vector3.new(0, 30, 0)
    bodyVelocity.Parent = root

    local startTime = tick()
    local flipDuration = 0.6
    local spinSpeed = 360 / flipDuration
    local spinConnection
    spinConnection = RunService.Heartbeat:Connect(function()
        local elapsed = tick() - startTime
        if elapsed >= flipDuration then
            spinConnection:Disconnect()
            return
        end
        local angle = -math.rad(spinSpeed * elapsed)
        bodyGyro.CFrame = startCFrame * CFrame.Angles(angle, 0, 0)
    end)

    task.delay(flipDuration, function()
        if spinConnection then spinConnection:Disconnect() end
        if bodyGyro then bodyGyro:Destroy() end
        if bodyVelocity then bodyVelocity:Destroy() end
        frontflipCooldown = false
    end)
end

-- ====== SCREEN SHAKE ======
local function ShakeScreen(intensity, duration)
    local Camera = Workspace.CurrentCamera
    local startTime = tick()
    local originalCFrame = Camera.CFrame
    local connection
    connection = RunService.RenderStepped:Connect(function()
        if tick() - startTime > (duration or 0.5) then
            connection:Disconnect()
            Camera.CFrame = originalCFrame
            return
        end
        local offset = Vector3.new(
            math.random(-100, 100) / 1000 * (intensity or 5),
            math.random(-100, 100) / 1000 * (intensity or 5),
            math.random(-100, 100) / 1000 * (intensity or 5)
        )
        Camera.CFrame = originalCFrame + offset
    end)
end

-- ====== DOUBLE JUMP + LAUNCH ======
local doubleJumpEnabled = false
local launchEnabled = false
local lastJumpTime = 0
local jumpCount = 0
local jumpTrackerConnection = nil
local jumpStateConnection = nil

local function BindJumpState(char)
    if jumpStateConnection then jumpStateConnection:Disconnect() end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    jumpStateConnection = humanoid.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
            jumpCount = 0
        end
    end)
end

local function StartJumpTracking()
    if jumpTrackerConnection then jumpTrackerConnection:Disconnect() end
    jumpTrackerConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode ~= Enum.KeyCode.Space then return end
        local c = LocalPlayer.Character
        if not c then return end
        local h = c:FindFirstChildOfClass("Humanoid")
        if not h then return end
        local now = tick()
        if now - lastJumpTime < 0.3 then return end
        lastJumpTime = now
        jumpCount = jumpCount + 1
        if jumpCount == 2 and doubleJumpEnabled then
            local root = c:FindFirstChild("HumanoidRootPart")
            if root then
                local bv = Instance.new("BodyVelocity")
                bv.MaxForce = Vector3.new(0, 40000, 0)
                bv.Velocity = Vector3.new(0, 60, 0)
                bv.Parent = root
                task.delay(0.2, function() bv:Destroy() end)
            end
        end
    end)
    local char = LocalPlayer.Character
    if char then BindJumpState(char) end
end

local function StopJumpTracking()
    if jumpTrackerConnection then
        jumpTrackerConnection:Disconnect()
        jumpTrackerConnection = nil
    end
    if jumpStateConnection then
        jumpStateConnection:Disconnect()
        jumpStateConnection = nil
    end
end

Repair.Connect(LocalPlayer.CharacterAdded, function(char)
    task.wait(0.5)
    if doubleJumpEnabled then BindJumpState(char) end
end)

local function StartLaunch()
    if _G._LaunchKeyConnection then _G._LaunchKeyConnection:Disconnect() end
    _G._LaunchKeyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode ~= _G.EvilHub.LaunchKey then return end
        local c = LocalPlayer.Character
        if not c then return end
        local root = c:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local direction = root.CFrame.LookVector
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(40000, 40000, 40000)
        bv.Velocity = direction * 100 + Vector3.new(0, 80, 0)
        bv.Parent = root
        task.delay(0.4, function() bv:Destroy() end)
    end)
end

local function StopLaunch()
    if _G._LaunchKeyConnection then
        _G._LaunchKeyConnection:Disconnect()
        _G._LaunchKeyConnection = nil
    end
end

-- ====== ROLE DETECTION ======
local function GetPlayerRole(player)
    local char = player.Character
    if not char then return "Survivor" end
    local killerName = char:GetAttribute("KillerName")
    if killerName and killerName ~= "" then return "Killer" end
    if char:GetAttribute("Unstunnable") == true then return "Killer" end
    return "Survivor"
end

-- ====== PLAYER ESP ======
local ESPFolder = nil

local function CreateESPFolder()
    if not ESPFolder or not ESPFolder.Parent then
        ESPFolder = CoreGui:FindFirstChild("EvilHub_ESP")
        if not ESPFolder then
            ESPFolder = Instance.new("Folder")
            ESPFolder.Name = "EvilHub_ESP"
            ESPFolder.Parent = CoreGui
        end
    end
    return ESPFolder
end

local function CreateESP(player)
    if player == LocalPlayer then return end
    if not player.Character then return end
    local espFolder = CreateESPFolder()
    local highlightName = player.Name .. "_Highlight"
    local billboardName = player.Name .. "_ESP"
    local existing = espFolder:FindFirstChild(highlightName)
    if existing then existing:Destroy() end
    local existingBB = espFolder:FindFirstChild(billboardName)
    if existingBB then existingBB:Destroy() end
    local role = GetPlayerRole(player)
    local color = (role == "Killer") and ESP_COLORS.Killer or ESP_COLORS.Survivor
    local highlight = Instance.new("Highlight")
    highlight.Name = highlightName
    highlight.Adornee = player.Character
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillColor = color.Fill
    highlight.FillTransparency = 0.7
    highlight.OutlineColor = color.Outline
    highlight.OutlineTransparency = 0
    highlight.Parent = espFolder
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = billboardName
        billboard.Adornee = hrp
        billboard.Size = UDim2.new(0, 200, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = espFolder
        local label = Instance.new("TextLabel")
        label.Name = "ESPLabel"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = player.Name .. " [" .. role .. "]"
        label.TextColor3 = color.Outline
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.Parent = billboard
    end
end

local function UpdateESP()
    if not _G.EvilHub.ESP then return end
    local folder = CreateESPFolder()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local highlightName = player.Name .. "_Highlight"
            if not folder:FindFirstChild(highlightName) then
                CreateESP(player)
            end
            local billboard = folder:FindFirstChild(player.Name .. "_ESP")
            if billboard then
                local label = billboard:FindFirstChild("ESPLabel")
                if label then
                    local role = GetPlayerRole(player)
                    local text = player.Name .. " [" .. role .. "]"
                    if _G.EvilHub.StaminaESP then
                        local stamina = player.Character:GetAttribute("Stamina")
                        local maxStamina = player.Character:GetAttribute("MaxStamina") or 100
                        if stamina then
                            text = text .. "\n⚡ " .. math.floor(stamina) .. "/" .. math.floor(maxStamina)
                        end
                    end
                    label.Text = text
                end
            end
        end
    end
end

local function DisableESP()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            local highlight = player.Character:FindFirstChild("EvilHub_Highlight")
            if highlight then highlight:Destroy() end
        end
    end
    if ESPFolder then
        for _, obj in ipairs(ESPFolder:GetChildren()) do obj:Destroy() end
    end
end

Repair.RegisterHeartbeat("UpdateESP", RunService.Heartbeat, UpdateESP)

-- ====== LOW HP SURVIVOR ALERT ======
local lastLowHPNotify = 0

Repair.RegisterHeartbeat("LowHPAlert", RunService.Heartbeat, function()
    if not _G.EvilHub.LowHPAlert then return end
    local target = GetLowHPSurvivor()
    if target and tick() - lastLowHPNotify > 5 then
        Rayfield:Notify({
            Title = "⚠️ LOW HP ALERT",
            Content = "A survivor is about to die!",
            Duration = 3
        })
        lastLowHPNotify = tick()
    end
end)

-- ====== OBJECTIVES ESP ======
local ObjectivesFolder = nil
local activeObjectiveHighlights = {}

local function CreateObjectivesFolder()
    if not ObjectivesFolder or not ObjectivesFolder.Parent then
        ObjectivesFolder = CoreGui:FindFirstChild("EvilHub_Objectives")
        if not ObjectivesFolder then
            ObjectivesFolder = Instance.new("Folder")
            ObjectivesFolder.Name = "EvilHub_Objectives"
            ObjectivesFolder.Parent = CoreGui
        end
    end
    return ObjectivesFolder
end

local OBJ_COLORS = {
    Electrical = Color3.fromRGB(255, 255, 0),
    Bluetooth = Color3.fromRGB(0, 255, 255),
    Generators = Color3.fromRGB(255, 165, 0),
    Default = Color3.fromRGB(255, 165, 0)
}

local function IsObjectiveCompleted(objectiveModel)
    if objectiveModel:GetAttribute("Completed") == true then return true end
    if objectiveModel:FindFirstChild("Completed") then return true end
    local main = objectiveModel:FindFirstChild("Main")
    if main then
        local attachment = main:FindFirstChild("Attachment")
        if attachment then
            local prompt = attachment:FindFirstChild("Prompt")
            if prompt and prompt:IsA("ProximityPrompt") then
                if not prompt.Enabled then return true end
            end
        end
    end
    if objectiveModel:GetAttribute("Fixed") == true then return true end
    if objectiveModel:FindFirstChild("Fixed") then return true end
    return false
end

local function CreateObjectiveESP(objectiveModel, category)
    if objectiveModel:FindFirstChild("EvilHub_ObjectiveHighlight") then return end
    local highlight = Instance.new("Highlight")
    highlight.Name = "EvilHub_ObjectiveHighlight"
    highlight.Adornee = objectiveModel
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.7
    highlight.OutlineTransparency = 0
    local color = OBJ_COLORS[category] or OBJ_COLORS.Default
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.Parent = CreateObjectivesFolder()
    local mainPart = objectiveModel:FindFirstChild("Main") or objectiveModel:FindFirstChildWhichIsA("BasePart")
    if mainPart then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = objectiveModel.Name .. "_ObjName"
        billboard.Adornee = mainPart
        billboard.Size = UDim2.new(0, 150, 0, 30)
        billboard.StudsOffset = Vector3.new(0, 3, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = CreateObjectivesFolder()
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "🎯 " .. objectiveModel.Name
        label.TextColor3 = color
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 14
        label.Parent = billboard
    end
    activeObjectiveHighlights[objectiveModel] = highlight
end

local function RemoveObjectiveESP(objectiveModel)
    if activeObjectiveHighlights[objectiveModel] then
        activeObjectiveHighlights[objectiveModel]:Destroy()
        activeObjectiveHighlights[objectiveModel] = nil
    end
    if ObjectivesFolder then
        for _, child in ipairs(ObjectivesFolder:GetChildren()) do
            if child.Adornee == objectiveModel then child:Destroy() end
        end
    end
end

local function UpdateObjectives()
    if not _G.EvilHub.ObjectivesESP then
        if ObjectivesFolder then ObjectivesFolder:ClearAllChildren() end
        activeObjectiveHighlights = {}
        return
    end
    local activeObjectives = GetActiveObjectives()
    if not activeObjectives then return end
    local currentObjectives = {}
    for _, category in ipairs(activeObjectives:GetChildren()) do
        if category:IsA("Folder") then
            for _, objective in ipairs(category:GetChildren()) do
                if objective:IsA("Model") then
                    if not IsObjectiveCompleted(objective) then
                        currentObjectives[objective] = true
                        CreateObjectiveESP(objective, category.Name)
                    else
                        RemoveObjectiveESP(objective)
                    end
                end
            end
        end
    end
    for obj, _ in pairs(activeObjectiveHighlights) do
        if not currentObjectives[obj] or not obj.Parent then
            RemoveObjectiveESP(obj)
        end
    end
end

Repair.RegisterHeartbeat("UpdateObjectives", RunService.Heartbeat, UpdateObjectives)

-- ====== HITBOX EXPANDER + HITBOX ESP ======
local originalData = {}
local HitboxESPFolder = nil
local hitboxESPBoxes = {}

local function ExpandHitbox(player)
    if player == LocalPlayer then return end
    if not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local uid = player.UserId
    if not originalData[uid] then
        originalData[uid] = {Size = hrp.Size, CanCollide = hrp.CanCollide, Transparency = hrp.Transparency}
    end
    local multiplier = _G.EvilHub.HitboxSize or 3
    hrp.Size = originalData[uid].Size * multiplier
    hrp.CanCollide = false
    if not _G.EvilHub.HitboxESP then hrp.Transparency = 0.7 end
end

local function ResetHitbox(player)
    if not player.Character then return end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    local uid = player.UserId
    if hrp and originalData[uid] then
        hrp.Size = originalData[uid].Size
        hrp.Transparency = originalData[uid].Transparency
        hrp.CanCollide = originalData[uid].CanCollide
    end
end

local function UpdateHitboxExpander()
    if not _G.EvilHub.HitboxExpander then
        for _, player in ipairs(Players:GetPlayers()) do ResetHitbox(player) end
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then ExpandHitbox(player) end
    end
end

local function CreateHitboxESPFolder()
    if not HitboxESPFolder or not HitboxESPFolder.Parent then
        HitboxESPFolder = CoreGui:FindFirstChild("EvilHub_HitboxESP")
        if not HitboxESPFolder then
            HitboxESPFolder = Instance.new("Folder")
            HitboxESPFolder.Name = "EvilHub_HitboxESP"
            HitboxESPFolder.Parent = CoreGui
        end
    end
    return HitboxESPFolder
end

local function CreateHitboxBox(player, hrp)
    if player == LocalPlayer then return end
    if hitboxESPBoxes[player] and hitboxESPBoxes[player].Parent then return end
    local box = Instance.new("BoxHandleAdornment")
    box.Name = "EvilHub_HitboxBox"
    box.Adornee = hrp
    box.AlwaysOnTop = true
    box.ZIndex = 5
    box.Size = hrp.Size
    box.Transparency = 0.5
    box.Color3 = Color3.fromRGB(255, 0, 0)
    box.Parent = CreateHitboxESPFolder()
    hitboxESPBoxes[player] = box
end

local function UpdateHitboxESP()
    if not _G.EvilHub.HitboxESP then
        for _, box in pairs(hitboxESPBoxes) do
            if box then box:Destroy() end
        end
        hitboxESPBoxes = {}
        return
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local hrp = player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                CreateHitboxBox(player, hrp)
                local box = hitboxESPBoxes[player]
                if box and box.Parent then box.Size = hrp.Size end
            end
        end
    end
    for player, box in pairs(hitboxESPBoxes) do
        if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
            if box then box:Destroy() end
            hitboxESPBoxes[player] = nil
        end
    end
end

Repair.Connect(Players.PlayerRemoving, function(player)
    if hitboxESPBoxes[player] then
        hitboxESPBoxes[player]:Destroy()
        hitboxESPBoxes[player] = nil
    end
    originalData[player.UserId] = nil
end)

Repair.RegisterHeartbeat("UpdateHitboxExpander", RunService.Heartbeat, UpdateHitboxExpander)
Repair.RegisterHeartbeat("UpdateHitboxESP", RunService.Heartbeat, UpdateHitboxESP)

-- ====== KILLER STUDS + MAP DISPLAY ======
local killerStudsLabel = nil
local mapLabel = nil
local modeLabel = nil

local function CreateInfoGUI()
    if killerStudsLabel and killerStudsLabel.Parent then return end
    local screenGui = CoreGui:FindFirstChild("EvilHub_InfoDisplay")
    if not screenGui then
        screenGui = Instance.new("ScreenGui")
        screenGui.Name = "EvilHub_InfoDisplay"
        screenGui.ResetOnSpawn = false
        screenGui.Parent = CoreGui
    end
    killerStudsLabel = screenGui:FindFirstChild("KillerStudsLabel")
    if not killerStudsLabel then
        killerStudsLabel = Instance.new("TextLabel")
        killerStudsLabel.Name = "KillerStudsLabel"
        killerStudsLabel.Size = UDim2.new(0, 500, 0, 30)
        killerStudsLabel.Position = UDim2.new(0.5, -250, 0, 10)
        killerStudsLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        killerStudsLabel.BackgroundTransparency = 0.3        killerStudsLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        killerStudsLabel.TextStrokeTransparency = 0
        killerStudsLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        killerStudsLabel.Font = Enum.Font.GothamBold
        killerStudsLabel.TextSize = 16
        killerStudsLabel.Text = ""
        killerStudsLabel.Parent = screenGui
    end
    mapLabel = screenGui:FindFirstChild("MapLabel")
    if not mapLabel then
        mapLabel = Instance.new("TextLabel")
        mapLabel.Name = "MapLabel"
        mapLabel.Size = UDim2.new(0, 400, 0, 25)
        mapLabel.Position = UDim2.new(0.5, -200, 0, 45)
        mapLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        mapLabel.BackgroundTransparency = 0.3
        mapLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
        mapLabel.TextStrokeTransparency = 0
        mapLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        mapLabel.Font = Enum.Font.GothamBold
        mapLabel.TextSize = 14
        mapLabel.Text = ""
        mapLabel.Parent = screenGui
    end
    modeLabel = screenGui:FindFirstChild("ModeLabel")
    if not modeLabel then
        modeLabel = Instance.new("TextLabel")
        modeLabel.Name = "ModeLabel"
        modeLabel.Size = UDim2.new(0, 400, 0, 25)
        modeLabel.Position = UDim2.new(0.5, -200, 0, 72)
        modeLabel.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        modeLabel.BackgroundTransparency = 0.3
        modeLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
        modeLabel.TextStrokeTransparency = 0
        modeLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        modeLabel.Font = Enum.Font.GothamBold
        modeLabel.TextSize = 14
        modeLabel.Text = ""
        modeLabel.Parent = screenGui
    end
end

local function UpdateInfoDisplay()
    CreateInfoGUI()
    if not killerStudsLabel then return end
    if _G.EvilHub.KillerStuds then
        local localChar = LocalPlayer.Character
        local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
        if localRoot then
            local playerKiller = nil
            local playerKillerName = nil
            -- Try player killer first
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local killerAttr = player.Character:GetAttribute("KillerName")
                    if killerAttr and killerAttr ~= "" then
                        playerKiller = player
                        playerKillerName = killerAttr
                        break
                    end
                end
            end
            if playerKiller and playerKiller.Character then
                local kRoot = playerKiller.Character:FindFirstChild("HumanoidRootPart")
                if kRoot then
                    local dist = (kRoot.Position - localRoot.Position).Magnitude
                    killerStudsLabel.Text = "🔪 Killer: " .. playerKiller.Name .. " (" .. playerKillerName .. ") | " .. math.floor(dist) .. " studs"
                end
            else
                -- Fallback: NPC killer
                local npc = FindKillerNPC()
                if npc then
                    local npcHum = npc:FindFirstChildOfClass("Humanoid")
                    local npcRoot = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
                    if npcRoot and npcHum then
                        local dist = (npcRoot.Position - localRoot.Position).Magnitude
                        killerStudsLabel.Text = "🔪 Killer (NPC): " .. npc.Name .. " | HP: " .. math.floor(npcHum.Health) .. " | " .. math.floor(dist) .. " studs"
                    end
                else
                    killerStudsLabel.Text = "🔪 Killer: None detected"
                end
            end
        end
    else
        killerStudsLabel.Text = ""
    end
    if _G.EvilHub.MapDisplay then
        local config = ReplicatedStorage:FindFirstChild("Config")
        if config then
            local nextMap = config:FindFirstChild("NextMap")
            if nextMap then
                mapLabel.Text = "🗺️ Map: " .. tostring(nextMap.Value)
            end
            local gamemode = config:FindFirstChild("Gamemode")
            if gamemode then
                local current = gamemode:FindFirstChild("CurrentGamemode")
                if current and current.Value ~= "" then
                    modeLabel.Text = "🎮 Mode: " .. tostring(current.Value)
                else
                    modeLabel.Text = "🎮 Mode: Lobby"
                end
            end
        end
    else
        mapLabel.Text = ""
        modeLabel.Text = ""
    end
end

Repair.RegisterHeartbeat("UpdateInfoDisplay", RunService.Heartbeat, UpdateInfoDisplay)

-- ====== COLOR REFRESH ======
local function RefreshESPColors()
    local folder = CreateESPFolder()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local role = GetPlayerRole(player)
            local color = (role == "Killer") and ESP_COLORS.Killer or ESP_COLORS.Survivor
            local highlight = folder:FindFirstChild(player.Name .. "_Highlight")
            if highlight then
                highlight.FillColor = color.Fill
                highlight.OutlineColor = color.Outline
            end
            local billboard = folder:FindFirstChild(player.Name .. "_ESP")
            if billboard then
                local label = billboard:FindFirstChild("ESPLabel")
                if label then
                    label.TextColor3 = color.Outline
                end
            end
        end
    end
end

-- ====== AUTO OBJECTIVE ======
local autoObjectiveConnection = nil

local function CompleteObjectivesViaValues()
    local activeObj = GetActiveObjectives()
    if not activeObj then return 0 end
    local count = 0
    for _, obj in ipairs(activeObj:GetDescendants()) do
        local progress = obj:FindFirstChildWhichIsA("NumberValue")
        if progress then
            progress.Value = 100
            count = count + 1
        end
        local done = obj:FindFirstChild("Completed")
        if done and done:IsA("BoolValue") then
            done.Value = true
            count = count + 1
        end
    end
    return count
end

local function FireAllObjectiveRemotes()
    local activeObj = GetActiveObjectives()
    if not activeObj then return 0 end
    local count = 0
    for _, obj in ipairs(activeObj:GetDescendants()) do
        if obj:IsA("RemoteEvent") then
            pcall(function() obj:FireServer() end)
            count = count + 1
        end
    end
    return count
end

local function StartAutoObjective()
    if autoObjectiveConnection then autoObjectiveConnection:Disconnect() end
    _G.EvilHub.AutoObjective = true
    autoObjectiveConnection = RunService.Heartbeat:Connect(function()
        if not _G.EvilHub.AutoObjective then return end
        CompleteObjectivesViaValues()
    end)
end

local function StopAutoObjective()
    if autoObjectiveConnection then
        autoObjectiveConnection:Disconnect()
        autoObjectiveConnection = nil
    end
    _G.EvilHub.AutoObjective = false
end

-- ====== INSTANT INTERACT ======
Repair.RegisterHeartbeat("InstantInteract", RunService.Heartbeat, function()
    if not _G.EvilHub.InstantInteract then return end
    local activeObj = GetActiveObjectives()
    if not activeObj then return end
    for _, v in ipairs(activeObj:GetDescendants()) do
        if v:IsA("ProximityPrompt") then
            v.HoldDuration = 0
        end
    end
end)

-- ====== REMOVE EFFECTS ======
Repair.RegisterHeartbeat("RemoveEffects", RunService.Heartbeat, function()
    if not _G.EvilHub.RemoveEffects then return end
    local storage = ReplicatedStorage:FindFirstChild("Storage")
    local effectIndex = storage and storage:FindFirstChild("EffectIndex")
    if not effectIndex then return end
    for _, eff in ipairs(effectIndex:GetChildren()) do
        eff:Destroy()
    end
end)

-- ====== FULL BRIGHT + NO FOG ======
Repair.RegisterHeartbeat("LightingTweaks", RunService.Heartbeat, function()
    if _G.EvilHub.FullBright then
        Lighting.Brightness = 3
        Lighting.GlobalShadows = false
    end
    if _G.EvilHub.NoFog then
        Lighting.FogEnd = 100000
    end
end)

-- ====== KILLER HEALTH ESP ======
local killerHealth = {}
local killerHealthConnections = {}
local killerHealthFolderRef = nil

local function GetKillerHealthFolder()
    if not killerHealthFolderRef or not killerHealthFolderRef.Parent then
        killerHealthFolderRef = CoreGui:FindFirstChild("EvilHub_KillerHealth")
        if not killerHealthFolderRef then
            killerHealthFolderRef = Instance.new("Folder")
            killerHealthFolderRef.Name = "EvilHub_KillerHealth"
            killerHealthFolderRef.Parent = CoreGui
        end
    end
    return killerHealthFolderRef
end

local function SafeConnect(event, callback)
    if not event then return nil end
    if event:IsA("RemoteEvent") then
        return event.OnClientEvent:Connect(callback)
    elseif event:IsA("BindableEvent") then
        return event.Event:Connect(callback)
    end
    return nil
end

local function SetupKillerHealth(player)
    if killerHealthConnections[player] then return end
    local char = player.Character
    if not char then return end
    local events = char:FindFirstChild("Events")
    if not events then return end
    killerHealth[player.UserId] = killerHealth[player.UserId] or 100
    local conns = {}
    local hurt = events:FindFirstChild("Hurt")
    if hurt then
        local c = SafeConnect(hurt, function(dmg)
            killerHealth[player.UserId] = math.max(0, (killerHealth[player.UserId] or 100) - (dmg or 0))
        end)
        if c then table.insert(conns, c) end
    end
    local healed = events:FindFirstChild("Healed")
    if healed then
        local c = SafeConnect(healed, function(amt)
            killerHealth[player.UserId] = math.min(100, (killerHealth[player.UserId] or 100) + (amt or 0))
        end)
        if c then table.insert(conns, c) end
    end
    killerHealthConnections[player] = conns
end

Repair.RegisterHeartbeat("UpdateKillerHealthESP", RunService.Heartbeat, function()
    if not _G.EvilHub.KillerHealthESP then return end
    local folder = GetKillerHealthFolder()
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            SetupKillerHealth(player)
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                local billboard = killerHealthFolderRef:FindFirstChild(player.Name .. "_Health")
                if not billboard then
                    billboard = Instance.new("BillboardGui")
                    billboard.Name = player.Name .. "_Health"
                    billboard.Adornee = hrp
                    billboard.Size = UDim2.new(0, 150, 0, 20)
                    billboard.StudsOffset = Vector3.new(0, 5, 0)
                    billboard.AlwaysOnTop = true
                    billboard.Parent = folder
                    local label = Instance.new("TextLabel")
                    label.Size = UDim2.new(1, 0, 1, 0)
                    label.BackgroundTransparency = 1
                    label.TextColor3 = Color3.fromRGB(255, 80, 80)
                    label.TextStrokeTransparency = 0
                    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                    label.Font = Enum.Font.GothamBold
                    label.TextSize = 14
                    label.Parent = billboard
                end
                local health = killerHealth[player.UserId] or 100
                local label = billboard:FindFirstChildWhichIsA("TextLabel")
                if label then
                    label.Text = "❤️ " .. math.floor(health) .. "/100"
                end
            end
        end
    end
end)

-- ====== KILL FEED ======
local killFeedConnections = {}

local function SetupKillFeed(player)
    if killFeedConnections[player] then return end
    local char = player.Character
    if not char then return end
    local events = char:FindFirstChild("Events")
    if not events then return end
    local conns = {}
    local killed = events:FindFirstChild("KilledPlayer")
    if killed then
        local c = SafeConnect(killed, function(victim)
            if not _G.EvilHub.KillFeed then return end
            Rayfield:Notify({Title = "💀 Kill", Content = player.Name .. " eliminated " .. tostring(victim), Duration = 3})
        end)
        if c then table.insert(conns, c) end
    end
    local won = events:FindFirstChild("WonRound")
    if won then
        local c = SafeConnect(won, function()
            if not _G.EvilHub.KillFeed then return end
            Rayfield:Notify({Title = "🏆 Round Over", Content = player.Name .. " won!", Duration = 4})
        end)
        if c then table.insert(conns, c) end
    end
    killFeedConnections[player] = conns
end

Repair.Connect(Players.PlayerAdded, function(player)
    player.CharacterAdded:Connect(function()
        task.wait(1)
        if _G.EvilHub.KillFeed then
            pcall(SetupKillFeed, player)
        end
    end)
end)

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character then
        pcall(SetupKillFeed, player)
    end
end

-- ====== SILENT AIM ======
local silentAimConnection = nil

local function FindNearestKiller()
    local localChar = LocalPlayer.Character
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")
    if not localRoot then return nil end
    local camera = Workspace.CurrentCamera
    local closest = nil
    local closestDist = math.huge
    -- Player killers
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local role = GetPlayerRole(player)
            if role == "Killer" then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local screenPos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                    if onScreen then
                        local dist = (hrp.Position - localRoot.Position).Magnitude
                        local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
                        local screenPoint = Vector2.new(screenPos.X, screenPos.Y)
                        local fovDist = (screenPoint - screenCenter).Magnitude
                        if fovDist <= (_G.EvilHub.SilentAimFOV or 150) and dist < closestDist then
                            closest = hrp
                            closestDist = dist
                        end
                    end
                end
            end
        end
    end
    -- NPC killer fallback
    if not closest then
        local npc = FindKillerNPC()
        if npc then
            local hrp = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
            if hrp then
                local screenPos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                if onScreen then
                    local dist = (hrp.Position - localRoot.Position).Magnitude
                    local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
                    local screenPoint = Vector2.new(screenPos.X, screenPos.Y)
                    local fovDist = (screenPoint - screenCenter).Magnitude
                    if fovDist <= (_G.EvilHub.SilentAimFOV or 150) then
                        closest = hrp
                    end
                end
            end
        end
    end
    return closest
end

local function StartSilentAim()
    if silentAimConnection then silentAimConnection:Disconnect() end
    _G.EvilHub.SilentAim = true
    silentAimConnection = RunService.RenderStepped:Connect(function()
        if not _G.EvilHub.SilentAim then return end
        local target = FindNearestKiller()
        if target then
            local camera = Workspace.CurrentCamera
            camera.CFrame = CFrame.new(camera.CFrame.Position, target.Position)
        end
    end)
end

local function StopSilentAim()
    if silentAimConnection then
        silentAimConnection:Disconnect()
        silentAimConnection = nil
    end
    _G.EvilHub.SilentAim = false
end

print("  [6/6] Building UI tabs...")

-- ====== TAB 1: MOVEMENT ======
local MovementTab = Window:CreateTab("🏃 Movement", 1)
MovementTab:CreateSection("Speed")

MovementTab:CreateToggle({
    Name = "WalkSpeed",
    CurrentValue = false,
    Flag = "WalkSpeedToggle",
    Callback = function(Value)
        WalkspeedEnabled = Value
        _G.EvilHub.WalkSpeed = Value
    end,
})

MovementTab:CreateSlider({
    Name = "WalkSpeed Value",
    Range = {7, 250},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 25,
    Flag = "WalkSpeedSlider",
    Callback = function(Value)
        _G.EvilHub.WalkSpeedValue = Value
    end,
})

MovementTab:CreateToggle({
    Name = "Anti Slow",
    CurrentValue = false,
    Flag = "AntiSlowToggle",
    Callback = function(Value)
        _G.EvilHub.AntiSlow = Value
    end,
})

MovementTab:CreateSection("Jumping")

MovementTab:CreateToggle({
    Name = "Force Jump",
    CurrentValue = false,
    Flag = "ForceJumpToggle",
    Callback = function(Value)
        _G.EvilHub.ForceJump = Value
        if Value then StartForceJump() else StopForceJump() end
    end,
})

MovementTab:CreateToggle({
    Name = "Double Jump",
    CurrentValue = false,
    Flag = "DoubleJumpToggle",
    Callback = function(Value)
        doubleJumpEnabled = Value
        _G.EvilHub.DoubleJump = Value
        if Value then StartJumpTracking() else StopJumpTracking() end
    end,
})

MovementTab:CreateToggle({
    Name = "Launch",
    CurrentValue = false,
    Flag = "LaunchToggle",
    Callback = function(Value)
        launchEnabled = Value
        _G.EvilHub.Launch = Value
        if Value then StartLaunch() else StopLaunch() end
    end,
})

MovementTab:CreateSection("Physics")

MovementTab:CreateToggle({
    Name = "Infinite Stamina",
    CurrentValue = false,
    Flag = "InfiniteStaminaToggle",
    Callback = function(Value)
        _G.EvilHub.InfiniteStamina = Value
        if Value then EnableInfiniteStamina() else DisableInfiniteStamina() end
    end,
})

MovementTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "NoclipToggle",
    Callback = function(Value)
        if Value then StartNoclip() else StopNoclip() end
    end,
})

MovementTab:CreateSection("Keybinds")

CreateKeybindDropdown(MovementTab, "Launch Key", _G.EvilHub.LaunchKey, function(k)
    _G.EvilHub.LaunchKey = k
    if launchEnabled then StartLaunch() end
end)

CreateKeybindDropdown(MovementTab, "Frontflip Key", _G.EvilHub.FrontflipKey, function(k)
    _G.EvilHub.FrontflipKey = k
end)

CreateKeybindDropdown(MovementTab, "Shake Key", _G.EvilHub.ShakeKey, function(k)
    _G.EvilHub.ShakeKey = k
end)

-- ====== TAB 2: COMBAT ======
local CombatTab = Window:CreateTab("⚔️ Combat", 2)
CombatTab:CreateSection("Hitbox")

CombatTab:CreateToggle({
    Name = "Hitbox Expander",
    CurrentValue = false,
    Flag = "HitboxExpanderToggle",
    Callback = function(Value)
        _G.EvilHub.HitboxExpander = Value
    end,
})

CombatTab:CreateToggle({
    Name = "Hitbox ESP",
    CurrentValue = false,
    Flag = "HitboxESPToggle",
    Callback = function(Value)
        _G.EvilHub.HitboxESP = Value
    end,
})

CombatTab:CreateSlider({
    Name = "Hitbox Size",
    Range = {1, 10},
    Increment = 0.5,
    Suffix = "x",
    CurrentValue = 3,
    Flag = "HitboxSizeSlider",
    Callback = function(Value)
        _G.EvilHub.HitboxSize = Value
    end,
})

CombatTab:CreateSection("Aim")

CombatTab:CreateToggle({
    Name = "Silent Aim (Killer)",
    CurrentValue = false,
    Flag = "SilentAimToggle",
    Callback = function(Value)
        if Value then StartSilentAim() else StopSilentAim() end
    end,
})

CombatTab:CreateSlider({
    Name = "Silent Aim FOV",
    Range = {50, 500},
    Increment = 10,
    Suffix = "px",
    CurrentValue = 150,
    Flag = "SilentAimFOV",
    Callback = function(Value)
        _G.EvilHub.SilentAimFOV = Value
    end,
})

-- ====== TAB 3: OBJECTIVE ======
local ObjectiveTab = Window:CreateTab("🎯 Objective", 3)
ObjectiveTab:CreateSection("Auto Objective")

ObjectiveTab:CreateButton({
    Name = "⚡ Complete via Values",
    Callback = function()
        local count = CompleteObjectivesViaValues()
        Rayfield:Notify({
            Title = "Auto Objective",
            Content = "Set " .. count .. " values to 100/true",
            Duration = 4
        })
    end,
})

ObjectiveTab:CreateButton({
    Name = "⚡ Fire All Objective Remotes",
    Callback = function()
        local count = FireAllObjectiveRemotes()
        Rayfield:Notify({
            Title = "Auto Objective",
            Content = "Fired " .. count .. " remotes",
            Duration = 4
        })
    end,
})

ObjectiveTab:CreateToggle({
    Name = "Auto Objective (Continuous)",
    CurrentValue = false,
    Flag = "AutoObjectiveToggle",
    Callback = function(Value)
        if Value then StartAutoObjective() else StopAutoObjective() end
    end,
})

ObjectiveTab:CreateToggle({
    Name = "Instant Interact",
    CurrentValue = false,
    Flag = "InstantInteractToggle",
    Callback = function(Value)
        _G.EvilHub.InstantInteract = Value
    end,
})

-- ====== TAB 4: VISUALS ======
local VisualsTab = Window:CreateTab("👁️ Visuals", 4)
VisualsTab:CreateSection("ESP")

VisualsTab:CreateToggle({
    Name = "Player ESP",
    CurrentValue = false,
    Flag = "PlayerESPToggle",
    Callback = function(Value)
        _G.EvilHub.ESP = Value
        if Value then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then pcall(CreateESP, player) end
            end
        else
            DisableESP()
        end
    end,
})

VisualsTab:CreateToggle({
    Name = "Show Stamina on ESP",
    CurrentValue = false,
    Flag = "StaminaOnESPToggle",
    Callback = function(Value)
        _G.EvilHub.StaminaESP = Value
    end,
})

VisualsTab:CreateToggle({
    Name = "Objectives ESP",
    CurrentValue = false,
    Flag = "ObjectivesESPToggle",
    Callback = function(Value)
        _G.EvilHub.ObjectivesESP = Value
    end,
})

VisualsTab:CreateToggle({
    Name = "Killer Health ESP",
    CurrentValue = false,
    Flag = "KillerHealthESPToggle",
    Callback = function(Value)
        _G.EvilHub.KillerHealthESP = Value
    end,
})

VisualsTab:CreateToggle({
    Name = "Low HP Alert",
    CurrentValue = false,
    Flag = "LowHPAlertToggle",
    Callback = function(Value)
        _G.EvilHub.LowHPAlert = Value
    end,
})

VisualsTab:CreateSection("Environment")

VisualsTab:CreateToggle({
    Name = "Full Bright",
    CurrentValue = false,
    Flag = "FullBrightToggle",
    Callback = function(Value)
        _G.EvilHub.FullBright = Value
        if not Value then
            Lighting.Brightness = 1
            Lighting.GlobalShadows = true
        end
    end,
})

VisualsTab:CreateToggle({
    Name = "No Fog",
    CurrentValue = false,
    Flag = "NoFogToggle",
    Callback = function(Value)
        _G.EvilHub.NoFog = Value
        if not Value then
            Lighting.FogEnd = 1000
        end
    end,
})

-- ====== TAB 5: INFO ======
local InfoTab = Window:CreateTab("📊 Info", 5)
InfoTab:CreateSection("Live Info")

InfoTab:CreateToggle({
    Name = "Killer Studs Display",
    CurrentValue = false,
    Flag = "KillerStudsToggle",
    Callback = function(Value)
        _G.EvilHub.KillerStuds = Value
    end,
})

InfoTab:CreateToggle({
    Name = "Map & Mode Display",
    CurrentValue = false,
    Flag = "MapDisplayToggle",
    Callback = function(Value)
        _G.EvilHub.MapDisplay = Value
    end,
})

InfoTab:CreateSection("Notifications")

InfoTab:CreateToggle({
    Name = "Kill Feed / Round Events",
    CurrentValue = false,
    Flag = "KillFeedToggle",
    Callback = function(Value)
        _G.EvilHub.KillFeed = Value
        if Value then
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then pcall(SetupKillFeed, player) end
            end
        end
    end,
})

InfoTab:CreateToggle({
    Name = "Remove Bad Effects",
    CurrentValue = false,
    Flag = "RemoveEffectsToggle",
    Callback = function(Value)
        _G.EvilHub.RemoveEffects = Value
    end,
})

-- ====== TAB 6: FUN ======
local FunTab = Window:CreateTab("🎮 Fun", 6)
FunTab:CreateSection("Fun Stuff")

FunTab:CreateButton({
    Name = "Frontflip",
    Callback = function() DoFrontflip() end,
})

FunTab:CreateButton({
    Name = "Screen Shake",
    Callback = function() ShakeScreen(10, 0.5) end,
})

-- ====== TAB 7: SETTINGS ======
local SettingsTab = Window:CreateTab("⚙️ Settings", 7)
SettingsTab:CreateSection("Maintenance")

SettingsTab:CreateButton({
    Name = "🔧 Run Full Repair",
    Callback = function()
        Repair.LastRepairTime = 0
        Repair.RunFullRepair()
        Rayfield:Notify({Title = "Repair", Content = "Hub repaired!", Duration = 3})
    end,
})

SettingsTab:CreateButton({
    Name = "🗑️ Clear All ESP",
    Callback = function()
        DisableESP()
        Rayfield:Notify({Title = "Cleanup", Content = "All ESP cleared", Duration = 3})
    end,
})

SettingsTab:CreateButton({
    Name = "🔄 Reset All Toggles",
    Callback = function()
        for key, val in pairs(_G.EvilHub) do
            if type(val) == "boolean" then
                _G.EvilHub[key] = false
            end
        end
        WalkspeedEnabled = false
        Rayfield:Notify({Title = "Reset", Content = "All toggles reset", Duration = 3})
    end,
})

SettingsTab:CreateSection("Danger Zone")

SettingsTab:CreateButton({
    Name = "💀 Unload Hub",
    Callback = function()
        Repair.Unloaded = true
        Repair.DisconnectAll()
        DisableESP()
        if ObjectivesFolder then ObjectivesFolder:ClearAllChildren() end
        if HitboxESPFolder then HitboxESPFolder:ClearAllChildren() end
        if killerHealthFolderRef then killerHealthFolderRef:ClearAllChildren() end
        for _, conns in pairs(killFeedConnections) do
            for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        end
        local infoGui = CoreGui:FindFirstChild("EvilHub_InfoDisplay")
        if infoGui then infoGui:Destroy() end
        if Window and Window.Destroy then pcall(function() Window:Destroy() end) end
        print("🛑 Ultimate Evil Hub unloaded")
    end,
})

-- ====== GLOBAL KEYBINDS ======
Repair.Connect(UserInputService.InputBegan, function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == _G.EvilHub.FrontflipKey then
        DoFrontflip()
    end
    if input.KeyCode == _G.EvilHub.ShakeKey then
        ShakeScreen(10, 0.5)
    end
end)

pcall(function()
    Rayfield:Notify({
        Title = "Ultimate Evil Hub",
        Content = "v17.8 loaded • Clean build",
        Duration = 5,
    })
end)

print("✅ Ultimate Evil Hub v17.8 loaded successfully!")
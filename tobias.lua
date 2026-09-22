getgenv().Configs = getgenv().Configs or {}
local Configs = getgenv().Configs

if Configs.Team == nil then Configs.Team = "Pirates" end -- Marines/Pirates
if Configs.Saber == nil then Configs.Saber = true end
if Configs.Pole == nil then Configs.Pole = true end
if Configs.SkipFarmLevel == nil then Configs.SkipFarmLevel = true end
if Configs.AutoRandomFruit == nil then Configs.AutoRandomFruit = true end
if Configs.MainLoopDelay == nil then Configs.MainLoopDelay = 0.05 end
if Configs.UtilityLoopDelay == nil then Configs.UtilityLoopDelay = 1 end
if Configs.RandomFruitInterval == nil then Configs.RandomFruitInterval = 60 end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Services
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local CommF_ = ReplicatedStorage.Remotes.CommF_

if not LocalPlayer.Team then
    repeat
        task.wait(0.25)
        pcall(function()
            CommF_:InvokeServer("SetTeam", Configs.Team)
        end)
    until LocalPlayer.Team
end

if not LocalPlayer.Character then
    LocalPlayer.CharacterAdded:Wait()
end

local v106 = tostring(LocalPlayer.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15)
local placeid = game.PlaceId
local AttackRotation = 0
local LastRotate = 0

-- Game state
local MaxLevel = game:GetAttribute("LEVEL_CAP") or 2800
local IsSaber = false
local IsPoleV1 = false
local IsPoleV2 = false
local Entrance = {}

-- Helpers
local function GetCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function GetHRP()
    local character = GetCharacter()
    return character:FindFirstChild("HumanoidRootPart")
end

local function TeleportServer(cursor)
    cursor = cursor or ""
    local placeId = game.PlaceId
    local visitedCursors = {}

    for _ = 1, 20 do
        if visitedCursors[cursor] then
            return false, "cursor_loop"
        end
        visitedCursors[cursor] = true

        local ok, data = pcall(function()
            local url = string.format(
                "https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100&cursor=%s",
                tostring(placeId),
                tostring(cursor)
            )
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
            return false, "server_list_failed"
        end

        for _, server in ipairs(data.data) do
            if server.id ~= game.JobId and server.playing < server.maxPlayers then
                local teleportOk, result = pcall(function()
                    return ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", server.id)
                end)
                return teleportOk, result
            end
        end

        cursor = data.nextPageCursor
        if not cursor or cursor == "" then
            break
        end
    end

    return false, "no_server_found"
end

local IsTweening = false
local function Tween(target, speed)
    speed = math.max(tonumber(speed) or 350, 1)
    local hrp = GetHRP()
    if not hrp or not target then return nil end

    local closestEntrance
    local minEntranceDist = math.huge
    for _, entrancePos in ipairs(Entrance) do
        local dist = (entrancePos - target.Position).Magnitude
        if dist < minEntranceDist then
            minEntranceDist = dist
            closestEntrance = entrancePos
        end
    end

    if not hrp:FindFirstChild("fixvelo") then
        local fixvelo = Instance.new("BodyVelocity")
        fixvelo.Name = "fixvelo"
        fixvelo.MaxForce = Vector3.new(0, 100000, 0)
        fixvelo.Velocity = Vector3.zero
        fixvelo.Parent = hrp
    end

    if closestEntrance and minEntranceDist < (hrp.Position - target.Position).Magnitude then
        IsTweening = true
        pcall(function()
            CommF_:InvokeServer("requestEntrance", closestEntrance)
        end)
        task.wait(0.35)
        hrp = GetHRP()
        if not hrp then
            IsTweening = false
            return nil
        end
    end

    local distance = (hrp.Position - target.Position).Magnitude
    local tween = TweenService:Create(
        hrp,
        TweenInfo.new(distance / speed, Enum.EasingStyle.Linear),
        {CFrame = target}
    )

    IsTweening = true
    tween:Play()
    task.spawn(function()
        tween.Completed:Wait()
        IsTweening = false
    end)

    return tween
end

local CombatRemote
local CombatRemotePathNames = {"Util", "Remotes", "Assets", "Common", "FX"}

local function FindCombatRemote()
    if CombatRemote and CombatRemote.Parent then
        return CombatRemote
    end

    for _, pathName in ipairs(CombatRemotePathNames) do
        local path = ReplicatedStorage:FindFirstChild(pathName)
        if path then
            for _, candidate in ipairs(path:GetChildren()) do
                if candidate:IsA("RemoteEvent") and candidate:GetAttribute("Id") then
                    CombatRemote = candidate
                    return CombatRemote
                end
            end
        end
    end

    return nil
end

task.spawn(function()
    while not FindCombatRemote() do
        task.wait(0.5)
    end
end)

local seed = ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2
local LastAttackTime = 0

local function IsOwn(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        local backpackTool = backpack:FindFirstChild(name)
        if backpackTool then
            return backpackTool
        end
    end

    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    return character:FindFirstChild(name)
end

local function IsAliveMob(mob)
    return mob
        and mob.Parent
        and mob:FindFirstChild("Humanoid")
        and mob:FindFirstChild("HumanoidRootPart")
        and mob.Humanoid.Health > 0
end

local function TryUseMeleeV()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local main = playerGui and playerGui:FindFirstChild("Main")
    local skills = main and main:FindFirstChild("Skills")
    if not skills then return end

    local styles = {
        {Name = "Death Step", Mastery = 400},
        {Name = "Black Leg", Mastery = 150}
    }

    for _, info in ipairs(styles) do
        local skill = skills:FindFirstChild(info.Name)
        local tool = IsOwn(info.Name)
        local level = tool and tool:FindFirstChild("Level")
        local vSkill = skill and skill:FindFirstChild("V")
        local cooldown = vSkill and vSkill:FindFirstChild("Cooldown")

        if skill and level and tonumber(level.Value) >= info.Mastery and cooldown and cooldown.AbsoluteSize.X <= 0.1 then
            VirtualInputManager:SendKeyEvent(true, "V", false, game)
            VirtualInputManager:SendKeyEvent(false, "V", false, game)
            return
        end
    end
end

local function Attack(target)
    if os.clock() - LastAttackTime < 0.2 then
        return false
    end

    local remote = FindCombatRemote()
    if not remote then
        return false
    end

    local character = LocalPlayer.Character
    if not character then
        return false
    end

    local targets = {}
    if type(target) == "table" then
        for _, mob in ipairs(target) do
            if IsAliveMob(mob) then
                table.insert(targets, mob)
            end
        end
    elseif IsAliveMob(target) then
        table.insert(targets, target)
    end

    if #targets == 0 then
        return false
    end

    LastAttackTime = os.clock()

    if not character:FindFirstChild("HasBuso") then
        pcall(function()
            CommF_:InvokeServer("Buso")
        end)
    end

    TryUseMeleeV()

    local h = "RE/RegisterHit"
    local key = math.floor(workspace:GetServerTimeNow() / 10 % 10)
    local encodedParts = table.create(#h)
    for i = 1, #h do
        encodedParts[i] = string.char(bit32.bxor(string.byte(h, i), key + 1))
    end
    local encoded = table.concat(encodedParts)

    local first = targets[1]
    local firstHead = first:FindFirstChild("Head")
    if not firstHead then
        return false
    end

    ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer(0)

    if #targets >= 2 then
        local second = targets[2]
        local secondHead = second:FindFirstChild("Head")
        if not secondHead then
            targets[2] = nil
        else
            local hitData = {
                {first, firstHead},
                first,
                {second, secondHead},
                second
            }

            remote:FireServer(
                encoded,
                bit32.bxor((remote:GetAttribute("Id") or 0) + 909090, seed),
                firstHead,
                hitData,
                nil,
                v106
            )
            ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(firstHead, hitData, nil, v106)
            return true
        end
    end

    local hitData = {first, firstHead}
    remote:FireServer(
        encoded,
        bit32.bxor((remote:GetAttribute("Id") or 0) + 909090, seed),
        firstHead,
        hitData,
        v106
    )
    ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(firstHead, hitData, v106)
    return true
end

local function DieWait()
    local character = GetCharacter()
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")

    if humanoid.Health <= 0 or not character:FindFirstChild("Head") then
        repeat
            task.wait(0.25)
            character = LocalPlayer.Character
            humanoid = character and character:FindFirstChildOfClass("Humanoid")
        until character and humanoid and humanoid.Health > 0 and character:FindFirstChild("Head")
    end

    if not character:FindFirstChild("HasBuso") then
        pcall(function()
            CommF_:InvokeServer("Buso")
        end)
    end
end

local function EquipWeapon(toolType)
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not character or not backpack then return nil end

    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == toolType then
            return tool
        end
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == toolType then
            humanoid:EquipTool(tool)
            return tool
        end
    end

    return nil
end

local function EquipName(toolName)
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not character or not backpack then return nil end

    local tool = character:FindFirstChild(toolName) or backpack:FindFirstChild(toolName)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not tool or not humanoid then return nil end

    if tool.Parent == backpack then
        humanoid:EquipTool(tool)
    end
    return tool
end

local InventoryCache = {}
local InventoryCacheAt = 0
local InventoryCacheTTL = 0.5

local function GetInventory(forceRefresh)
    if not forceRefresh and os.clock() - InventoryCacheAt <= InventoryCacheTTL then
        return InventoryCache
    end

    local ok, result = pcall(function()
        return CommF_:InvokeServer("getInventory")
    end)

    if ok and type(result) == "table" then
        InventoryCache = result
        InventoryCacheAt = os.clock()
    end

    return InventoryCache
end

local function InvalidateInventoryCache()
    InventoryCacheAt = 0
end

local function CheckInv(inv)
    inv = inv or GetInventory(false)
    IsSaber = false
    IsPoleV1 = false
    IsPoleV2 = false

    for _, item in pairs(inv) do
        if type(item) == "table" then
            if item.Name == "Saber" then
                IsSaber = true
            elseif item.Name == "Pole (1st Form)" then
                IsPoleV1 = true
            elseif item.Name == "Pole (2nd Form)" then
                IsPoleV2 = true
            end
        end
    end
end

local function BringMob(a)
    pcall(sethiddenproperty,LocalPlayer,"SimulationRadius",math.huge)
    local aname = a.Name
    local acf = a.HumanoidRootPart.CFrame
    local targets = {}
    table.insert(targets, {a, a:FindFirstChild("Head")})
    for _, v in ipairs(workspace.Enemies:GetChildren()) do
        if string.find(v.Name:lower(), aname:lower(), 1, true) and not v:FindFirstChild("BringCheck") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and (acf.Position - v.HumanoidRootPart.Position).Magnitude <= 350 then
            local bv = v.HumanoidRootPart:FindFirstChild("BringVelocity")
            if not bv then
                bv = Instance.new("BodyVelocity")
                bv.Name = "BringVelocity"
                bv.MaxForce = Vector3.new(10000, 10000, 10000)
                bv.Parent = v.HumanoidRootPart
            end
            bv.Velocity = Vector3.zero
            v.HumanoidRootPart.CFrame = acf
            table.insert(targets, {v, v:FindFirstChild("Head")})
            break
        end
    end
    return targets
end
--UI
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game.CoreGui
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 500, 0, 75)
frame.Position = UDim2.new(0.5, -250, 0, 30)
frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
frame.BackgroundTransparency = 0.2
frame.Parent = ScreenGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame
local edge = Instance.new("UIStroke")
edge.Color = Color3.fromRGB(0, 0, 0)
edge.Thickness = 3.5
edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
edge.Parent = frame
local layout = Instance.new("UIListLayout")
layout.Parent = frame
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 5)
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 40)
title.BackgroundTransparency = 1
title.Text = "Idling"
title.Font = Enum.Font.GothamBold
title.TextScaled = false
title.TextSize = 22
title.TextColor3 = Color3.fromRGB(200, 200, 200)
title.LayoutOrder = 1
title.Parent = frame
local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -20, 0, 30)
subtitle.BackgroundTransparency = 1
subtitle.Text = "No Subtask"
subtitle.Font = Enum.Font.GothamSemibold
subtitle.TextScaled = false
subtitle.TextSize = 20
subtitle.TextColor3 = Color3.fromRGB(200, 200, 200)
subtitle.LayoutOrder = 2
subtitle.Parent = frame
local TimeL = Instance.new("TextLabel")
TimeL.Size = UDim2.new(0, 500, 0, 30)
TimeL.Position = UDim2.new(0.5, -250, 0, 0)
TimeL.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
TimeL.BackgroundTransparency = 0.2
TimeL.Text = ""
TimeL.Font = Enum.Font.GothamBold
TimeL.TextScaled = false
TimeL.TextSize = 20
TimeL.TextColor3 = Color3.fromRGB(200, 200, 200)
TimeL.Parent = ScreenGui
local TimeC = Instance.new("UICorner")
TimeC.CornerRadius = UDim.new(0, 10)
TimeC.Parent = TimeL
local TimeS = Instance.new("UIStroke")
TimeS.Color = Color3.fromRGB(0, 0, 0)
TimeS.Thickness = 3.5
TimeS.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
TimeS.Parent = TimeL
task.spawn(function()
    while task.wait(1) do
		local t = os.date("*t")
        TimeL.Text = string.format("%02d:%02d:%02d  |  %s, %s %d, %d",t.hour,t.min,t.sec,os.date("%A"),os.date("%B"),t.day,t.year)
    end
end)
local LevelQuest
local Monster
local NameQuest
local NameCheckQuest
local CFrameQ
local CFrameMon
if not identifyexecutor or identifyexecutor() ~= "Solara" then
    pcall(function()
        require(ReplicatedStorage.Util.CameraShaker):Stop()
    end)
end
local World1 = false
local World2 = false
local World3 = false
if placeid == 2753915549 then
    World1 = true
	Entrance = {
		Vector3.new(61163.8515625, 11.6796875, 1819.7841796875),
		Vector3.new(3864.8515625, 6.6796875, -1926.7841796875),
		Vector3.new(-4607.8227539063, 872.54248046875, -1667.5568847656),
		Vector3.new(-7894.6176757813, 5547.1416015625, -380.29119873047),
	}
elseif placeid == 79091703265657 then
    World2 = true
	Entrance = {
		Vector3.new(923.21252441406, 126.9760055542, 32852.83203125),
		Vector3.new(-6508.5581054688, 89.034996032715, -132.83953857422),
		Vector3.new(2284,15,905),
		Vector3.new(-286.98907470703125, 306.1379089355469, 597.8827514648438),
	}
elseif placeid == 7449423635 then
    World3 = true
end
local function GetWorld()
    if World1 then
        return 1
    elseif World2 then
        return 2
    elseif World3 then
        return 3
    else
        return 0
    end
end
local function CheckQuest()
    local Level = LocalPlayer.Data.Level.Value
    if World1 then
		if Level == 1 or Level <= 9 then -- Bandit
			Monster = "Bandit"
			NameQuest = "BanditQuest1"
            LevelQuest = 1
			NameCheckQuest = "Bandit"
			CFrameQ = CFrame.new(1060, 17, 1547)
			CFrameMon = CFrame.new(1145, 17, 1634)
        elseif Level == 10 or Level <= 14 then -- Monkey
			Monster = "Monkey"
			NameQuest = "JungleQuest"
            LevelQuest = 1
			NameCheckQuest = "Monkey"
			CFrameQ = CFrame.new(-1602, 37, 152)
			CFrameMon = CFrame.new(-1496, 39, 35)
		elseif Level == 15 or Level <= 29 then -- Gorilla
			Monster = "Gorilla"
			NameQuest = "JungleQuest"
			LevelQuest = 2
			NameCheckQuest = "Gorilla"
			CFrameQ = CFrame.new(-1602, 37, 152)
			CFrameMon = CFrame.new(-1237, 6, -486)
		elseif Level == 30 or Level <= 39 then -- Pirate
			Monster = "Pirate"
			NameQuest = "BuggyQuest1"
			LevelQuest = 1
			NameCheckQuest = "Pirate"
			CFrameQ = CFrame.new(-1140, 5, 3828)
			CFrameMon = CFrame.new(-1115, 14, 3938)
		elseif Level == 40 or Level <= 59 then -- Brute
			Monster = "Brute"
			NameQuest = "BuggyQuest1"
			LevelQuest = 2
			NameCheckQuest = "Brute"
			CFrameQ = CFrame.new(-1140, 5, 3828)
			CFrameMon = CFrame.new(-1145, 15, 4350)
		elseif Level == 60 or Level <= 74 then -- Desert Bandit
			Monster = "Desert Bandit"
			NameQuest = "DesertQuest"
			LevelQuest = 1
			NameCheckQuest = "Desert Bandit"
			CFrameQ = CFrame.new(897, 7, 4388)
			CFrameMon = CFrame.new(932, 7, 4484)
		elseif Level == 75 or Level <= 89 then -- Desert Officer
			Monster = "Desert Officer"
			NameQuest = "DesertQuest"
			LevelQuest = 2
			NameCheckQuest = "Desert Officers"
			CFrameQ = CFrame.new(897, 7, 4388)
			CFrameMon = CFrame.new(1572, 10, 4373)
		elseif Level == 90 or Level <= 99 then -- Snow Bandit
			Monster = "Snow Bandit"
			NameQuest = "SnowQuest"
			LevelQuest = 1
			NameCheckQuest = "Snow Bandits"
			CFrameQ = CFrame.new(1386, 87, -1297)
			CFrameMon = CFrame.new(1289, 150, -1442)
		elseif Level == 100 or Level <= 119 then -- Snowman
			Monster = "Snowman"
			NameQuest = "SnowQuest"
			LevelQuest = 2
			NameCheckQuest = "Snowman"
			CFrameMon = CFrame.new(1289, 150, -1442)
			CFrameQ = CFrame.new(1386, 87, -1297)
		elseif Level == 120 or Level <= 149 then -- Chief Petty Officer
			Monster = "Chief Petty Officer"
			NameQuest = "MarineQuest2"
			LevelQuest = 1
			NameCheckQuest = "Chief Petty Officer"
			CFrameMon = CFrame.new(-4855, 23, 4308)
			CFrameQ = CFrame.new(-5036, 29, 4325)
		elseif Level == 150 or Level <= 174 then -- Sky Bandit
			Monster = "Sky Bandit"
			NameQuest = "SkyQuest"
			LevelQuest = 1
			NameCheckQuest = "Sky Bandit"
			CFrameMon = CFrame.new(-4981, 278, -2830)
			CFrameQ = CFrame.new(-4842, 718, -2623)
		elseif Level == 175 or Level <= 189 then -- Dark Master
			Monster = "Dark Master"
			NameQuest = "SkyQuest"
			LevelQuest = 2
			NameCheckQuest = "Dark Master"
			CFrameMon = CFrame.new(-5250, 389, -2272)
			CFrameQ = CFrame.new(-4842, 718, -2623)
		elseif Level == 190 or Level <= 209 then -- Dark Master
			Monster = "Prisoner"
			NameQuest = "PrisonerQuest"
			LevelQuest = 1
			NameCheckQuest = "Prisoners"
			CFrameMon = CFrame.new(5411, 96, 690)
			CFrameQ = CFrame.new(5308, 2, 474)
		elseif Level == 210 or Level <= 249 then -- Dark Master
			Monster = "Dangerous Prisoner"
			NameQuest = "PrisonerQuest"
			LevelQuest = 2
			NameCheckQuest = "Dangerous Prisoner"
			CFrameMon = CFrame.new(5411, 96, 690)
			CFrameQ = CFrame.new(5308, 2, 474)
		elseif Level == 250 or Level <= 299 then -- Toga Warrior
			Monster = "Toga Warrior"
			NameQuest = "ColosseumQuest"
			LevelQuest = 1
			NameCheckQuest = "Toga Warrior"
			CFrameMon = CFrame.new(-1641.4344482421875, 7.415142059326172, -2864.462646484375)
			CFrameQ = CFrame.new(-1576, 8, -2985)
		-- elseif Level == 275 or Level <= 299 then -- Gladiator
		-- 	Monster = "Gladiator"
		-- 	NameQuest = "ColosseumQuest"
		-- 	LevelQuest = 2
		-- 	NameCheckQuest = "Gladiator"
		-- 	CFrameMon = CFrame.new(-1385.5233154296875, 7.468349456787109, -3163.066650390625)
		-- 	CFrameQ = CFrame.new(-1576, 8, -2985)
		elseif Level == 300 or Level <= 329 then -- Military Soldier
			Monster = "Military Soldier"
			NameQuest = "MagmaQuest"
			LevelQuest = 1
			NameCheckQuest = "Military Soldier"
			CFrameMon = CFrame.new(-5408, 11, 8447)
			CFrameQ = CFrame.new(-5316, 12, 8517)
		elseif Level == 330 or Level <= 374 then -- Military Spy
			Monster = "Military Spy"
			NameQuest = "MagmaQuest"
			LevelQuest = 2
			NameCheckQuest = "Military Spy"
			CFrameMon = CFrame.new(-5815, 84, 8820)
			CFrameQ = CFrame.new(-5316, 12, 8517)
		elseif Level == 375 or Level <= 399 then -- Fishman Warrior
			Monster = "Fishman Warrior"
			NameQuest = "FishmanQuest"
			LevelQuest = 1
			NameCheckQuest = "Fishman Warrior"
			CFrameMon = CFrame.new(60859, 19, 1501)
			CFrameQ = CFrame.new(61123, 19, 1569)
		elseif Level == 400 or Level <= 449 then -- Fishman Commando
			Monster = "Fishman Commando"
			NameQuest = "FishmanQuest"
			LevelQuest = 2
			NameCheckQuest = "Fishman Commando"
			CFrameMon = CFrame.new(61891, 19, 1470)
			CFrameQ = CFrame.new(61123, 19, 1569)
		elseif Level == 450 or Level <= 474 then -- God's Guards
			Monster = "God's Guard"
			NameQuest = "SkyExp1Quest"
			LevelQuest = 1
			NameCheckQuest = "God's Guards"
			CFrameMon = CFrame.new(-4698, 845, -1912)
			CFrameQ = CFrame.new(-4722, 845, -1954)
		elseif Level == 475 or Level <= 524 then -- Shandas
			Monster = "Shanda"
			NameQuest = "SkyExp1Quest"
			LevelQuest = 2
			NameCheckQuest = "Shandas"
			CFrameMon = CFrame.new(-7685, 5567, -502)
			CFrameQ = CFrame.new(-7862, 5546, -380)
		elseif Level == 525 or Level <= 549 then -- Royal Squad
			Monster = "Royal Squad"
			NameQuest = "SkyExp2Quest"
			LevelQuest = 1
			NameCheckQuest = "Royal Squad"
			CFrameMon = CFrame.new(-7670, 5607, -1460)
			CFrameQ = CFrame.new(-7904, 5636, -1412)
		elseif Level == 550 or Level <= 624 then -- Royal Soldier
			Monster = "Royal Soldier"
			NameQuest = "SkyExp2Quest"
			LevelQuest = 2
			NameCheckQuest = "Royal Soldier"
			CFrameMon = CFrame.new(-7828, 5607, -1744)
			CFrameQ = CFrame.new(-7904, 5636, -1412)
		elseif Level == 625 or Level <= 649 then -- Galley Pirate
			Monster = "Galley Pirate"
			NameQuest = "FountainQuest"
			LevelQuest = 1
			NameCheckQuest = "Galley Pirate"
			CFrameMon = CFrame.new(5589, 45, 3996)
			CFrameQ = CFrame.new(5256, 39, 4050)
		elseif Level >= 650 then -- Galley Captain
			Monster = "Galley Captain"
			NameQuest = "FountainQuest"
			LevelQuest = 2
			NameCheckQuest = "Galley Captain"
			CFrameMon = CFrame.new(5649, 39, 4936)
			CFrameQ = CFrame.new(5256, 39, 4050)
        end
	end
    if World2 then
		if Level == 700 or Level <= 724 then -- Raider [Lv. 700]
			Monster = "Raider"
			NameQuest = "Area1Quest"
			LevelQuest = 1
			NameCheckQuest = "Raider"
			CFrameQ = CFrame.new(-425, 73, 1837)
			CFrameMon = CFrame.new(-746, 39, 2390)
		elseif Level == 725 or Level <= 774 then -- Mercenary [Lv. 725]
			Monster = "Mercenary"
			NameQuest = "Area1Quest"
			LevelQuest = 2
			NameCheckQuest = "Mercenary"
			CFrameQ = CFrame.new(-425, 73, 1837)
			CFrameMon = CFrame.new(-874, 141, 1312)
		elseif Level == 775 or Level <= 799 then -- Swan Pirate [Lv. 775]
			Monster = "Swan Pirate"
			NameQuest = "Area2Quest"
			LevelQuest = 1
			NameCheckQuest = "Swan Pirate"
			CFrameQ = CFrame.new(634, 73, 918)
			CFrameMon = CFrame.new(878, 122, 1235)
		elseif Level == 800 or Level <= 874 then -- Factory Staff [Lv. 800]
			Monster = "Factory Staff"
			NameQuest = "Area2Quest"
			LevelQuest = 2
			NameCheckQuest = "Factory Staff"
			CFrameQ = CFrame.new(634, 73, 918)
			CFrameMon = CFrame.new(295, 73, -56)
		elseif Level == 875 or Level <= 899 then -- Marine Lieutenant [Lv. 875]
			Monster = "Marine Lieutenant"
			NameQuest = "MarineQuest3"
			LevelQuest = 1
			NameCheckQuest = "Marine Lieutenant"
			CFrameMon = CFrame.new(-2806, 73, -3038)
			CFrameQ = CFrame.new(-2443, 73, -3219)
		elseif Level == 900 or Level <= 949 then -- Marine Captain [Lv. 900]
			Monster = "Marine Captain"
			NameQuest = "MarineQuest3"
			LevelQuest = 2
			NameCheckQuest = "Marine Captain"
			CFrameMon = CFrame.new(-1869, 73, -3320)
			CFrameQ = CFrame.new(-2443, 73, -3219)
		elseif Level == 950 or Level <= 974 then -- Zombie [Lv. 950]
			Monster = "Zombie"
			NameQuest = "ZombieQuest"
			LevelQuest = 1
			NameCheckQuest = "Zombie"
			CFrameMon = CFrame.new(-5736, 126, -728)
			CFrameQ = CFrame.new(-5494, 49, -795)
		elseif Level == 975 or Level <= 999 then -- Vampire [Lv. 975]
			Monster = "Vampire"
			NameQuest = "ZombieQuest"
			LevelQuest = 2
			NameCheckQuest = "Vampire"
			CFrameMon = CFrame.new(-6033, 7, -1317)
			CFrameQ = CFrame.new(-5494, 49, -795)
		elseif Level == 1000 or Level <= 1049 then -- Snow Trooper [Lv. 1000] **
			Monster = "Snow Trooper"
			NameQuest = "SnowMountainQuest"
			LevelQuest = 1
			NameCheckQuest = "Snow Trooper"
			CFrameMon = CFrame.new(478, 402, -5362)
			CFrameQ = CFrame.new(605, 402, -5371)
		elseif Level == 1050 or Level <= 1099 then -- Winter Warrior [Lv. 1050]
			Monster = "Winter Warrior"
			NameQuest = "SnowMountainQuest"
			LevelQuest = 2
			NameCheckQuest = "Winter Warrior"
			CFrameMon = CFrame.new(1157, 430, -5188)
			CFrameQ = CFrame.new(605, 402, -5371)
		elseif Level == 1100 or Level <= 1124 then -- Lab Subordinate [Lv. 1100]
			Monster = "Lab Subordinate"
			NameQuest = "IceSideQuest"
			LevelQuest = 1
			NameCheckQuest = "Lab Subordinate"
			CFrameMon = CFrame.new(-5782, 42, -4484)
			CFrameQ = CFrame.new(-6060, 16, -4905)
		elseif Level == 1125 or Level <= 1174 then -- Horned Warrior [Lv. 1125]
			Monster = "Horned Warrior"
			NameQuest = "IceSideQuest"
			LevelQuest = 2
			NameCheckQuest = "Horned Warrior"
			CFrameMon = CFrame.new(-6406, 24, -5805)
			CFrameQ = CFrame.new(-6060, 16, -4905)
		elseif Level == 1175 or Level <= 1199 then -- Magma Ninja [Lv. 1175]
			Monster = "Magma Ninja"
			NameQuest = "FireSideQuest"
			LevelQuest = 1
			NameCheckQuest = "Magma Ninja"
			CFrameMon = CFrame.new(-5428, 78, -5959)
			CFrameQ = CFrame.new(-5430, 16, -5295)
		elseif Level == 1200 or Level <= 1249 then -- Lava Pirate [Lv. 1200]
			Monster = "Lava Pirate"
			NameQuest = "FireSideQuest"
			LevelQuest = 2
			NameCheckQuest = "Lava Pirate"
			CFrameMon = CFrame.new(-5270, 42, -4800)
			CFrameQ = CFrame.new(-5430, 16, -5295)
		elseif Level == 1250 or Level <= 1274 then -- Ship Deckhand [Lv. 1250]
			Monster = "Ship Deckhand"
			NameQuest = "ShipQuest1"
			LevelQuest = 1
			NameCheckQuest = "Ship Deckhand"
			CFrameMon = CFrame.new(1198, 126, 33031)
			CFrameQ = CFrame.new(1038, 125, 32913)
		elseif Level == 1275 or Level <= 1299 then -- Ship Engineer [Lv. 1275]
			Monster = "Ship Engineer"
			NameQuest = "ShipQuest1"
			LevelQuest = 2
			NameCheckQuest = "Ship Engineer"
			CFrameMon = CFrame.new(918, 44, 32787)
			CFrameQ = CFrame.new(1038, 125, 32913)
		elseif Level == 1300 or Level <= 1324 then -- Ship Steward [Lv. 1300]
			Monster = "Ship Steward"
			NameQuest = "ShipQuest2"
			LevelQuest = 1
			NameCheckQuest = "Ship Steward"
			CFrameMon = CFrame.new(915, 130, 33419)
			CFrameQ = CFrame.new(969, 125, 33245)
		elseif Level == 1325 or Level <= 1349 then -- Ship Officer [Lv. 1325]
			Monster = "Ship Officer"
			NameQuest = "ShipQuest2"
			LevelQuest = 2
			NameCheckQuest = "Ship Officer"
			CFrameMon = CFrame.new(916, 181, 33335)
			CFrameQ = CFrame.new(969, 125, 33245)
		elseif Level == 1350 or Level <= 1374 then -- Arctic Warrior [Lv. 1350]
			Monster = "Arctic Warrior"
			NameQuest = "FrostQuest"
			LevelQuest = 1
			NameCheckQuest = "Arctic Warrior"
			CFrameMon = CFrame.new(6038, 29, -6231)
			CFrameQ = CFrame.new(5669, 28, -6482)
		elseif Level == 1375 or Level <= 1424 then -- Snow Lurker [Lv. 1375]
			Monster = "Snow Lurker"
			NameQuest = "FrostQuest"
			LevelQuest = 2
			NameCheckQuest = "Snow Lurker"
			CFrameMon = CFrame.new(5560, 42, -6826)
			CFrameQ = CFrame.new(5669, 28, -6482)
		elseif Level == 1425 or Level <= 1449 then -- Sea Soldier [Lv. 1425]
			Monster = "Sea Soldier"
			NameQuest = "ForgottenQuest"
			LevelQuest = 1
			NameCheckQuest = "Sea Soldier"
			CFrameMon = CFrame.new(-3022, 16, -9722)
			CFrameQ = CFrame.new(-3054, 237, -10148)
		elseif Level >= 1450 then -- Water Fighter [Lv. 1450]
			Monster = "Water Fighter"
			NameQuest = "ForgottenQuest"
			LevelQuest = 2
			NameCheckQuest = "Water Fighter"
			CFrameMon = CFrame.new(-3385, 239, -10542)
			CFrameQ = CFrame.new(-3054, 237, -10148)
		end
	end

    if World3 then

    end
end
task.spawn(function()
	local codes = {"BANEXPLOIT", "NOMOREHACKS", "WildDares", "BossBuild", "GetPranked", "EARN_FRUITS", "Sub2UncleKizaru", "FIGHT4FRUIT", "kittgaming", "TRIPLEABUSE", "Sub2CaptainMaui", "Sub2Fer999", "Enyu_is_Pro", "Magicbus", "JCWK", "Starcodeheo", "Bluxxy", "SUB2GAMERROBOT_EXP1", "Sub2NoobMaster123", "Sub2Daigrock", "Axiore", "TantaiGaming", "StrawHatMaine", "Sub2OfficialNoobie", "TheGreatAce", "SEATROLLIN", "24NOADMIN", "ADMIN_TROLL", "NEWTROLL", "SECRET_ADMIN", "staffbattle", "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts"}
	for _, v in ipairs(codes) do
		ReplicatedStorage.Remotes.Redeem:InvokeServer(v)
	end
end)
local function GetNearestMob(originMob, maxDistance)
    if not originMob or not originMob:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    local nearest
    local nearestDistance = math.huge
    for _, mob in ipairs(workspace.Enemies:GetChildren()) do
        if mob ~= originMob
        and mob.Name == originMob.Name
        and mob.Parent
        and mob:FindFirstChild("Humanoid")
        and mob:FindFirstChild("HumanoidRootPart")
        and mob.Humanoid.Health > 0 then
            local dist = (mob.HumanoidRootPart.Position - originMob.HumanoidRootPart.Position).Magnitude
            if dist <= maxDistance and dist < nearestDistance then
                nearest = mob
                nearestDistance = dist
            end
        end
    end

    return nearest
end

local function SmartMoveAndAttack(mainMob, QuestTitle, Quest, IsCheckQuest, CustomName)
    if IsCheckQuest == nil then IsCheckQuest = true end
    CustomName = CustomName or NameCheckQuest

    pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge)
    if not IsAliveMob(mainMob) then
        return false
    end

    local humanoid = mainMob.Humanoid
    local hrp = mainMob.HumanoidRootPart
    humanoid.JumpPower = 0
    humanoid.WalkSpeed = 0
    hrp.CanCollide = false

    local mainVelocity = hrp:FindFirstChild("BringVelocity")
    if not mainVelocity then
        mainVelocity = Instance.new("BodyVelocity")
        mainVelocity.Name = "BringVelocity"
        mainVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
        mainVelocity.Parent = hrp
    end
    mainVelocity.Velocity = Vector3.zero

    local secondMob
    local tween

    repeat
        task.wait(0.03)
        if not IsAliveMob(mainMob) then
            break
        end

        title.Text = "Auto Farming Level | Kill " .. mainMob.Name

        if not IsAliveMob(secondMob) then
            secondMob = GetNearestMob(mainMob, 350)
        end

        if IsAliveMob(secondMob) then
            local secondHRP = secondMob.HumanoidRootPart
            secondHRP.CFrame = hrp.CFrame
            secondMob.Humanoid.JumpPower = 0
            secondMob.Humanoid.WalkSpeed = 0
            secondHRP.CanCollide = false

            local secondVelocity = secondHRP:FindFirstChild("BringVelocity")
            if not secondVelocity then
                secondVelocity = Instance.new("BodyVelocity")
                secondVelocity.Name = "BringVelocity"
                secondVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
                secondVelocity.Parent = secondHRP
            end
            secondVelocity.Velocity = Vector3.zero
        else
            secondMob = nil
        end

        local myHRP = GetHRP()
        if not myHRP then
            break
        end

        local distance = (myHRP.Position - hrp.Position).Magnitude
        if distance > 150 then
            if not tween or tween.PlaybackState ~= Enum.PlaybackState.Playing then
                tween = Tween(hrp.CFrame * CFrame.new(0, 30, 0), 350)
            end
        else
            if tween then
                tween:Cancel()
                tween = nil
            end

            EquipWeapon("Melee")

            if os.clock() - LastRotate >= 0.25 then
                AttackRotation = (AttackRotation + 180) % 360
                LastRotate = os.clock()
            end

            myHRP.CFrame = hrp.CFrame
                * CFrame.new(0, 30, 0)
                * CFrame.Angles(0, math.rad(AttackRotation), 0)

            if secondMob then
                Attack({mainMob, secondMob})
            else
                Attack(mainMob)
            end
        end

        local questMismatch = false
        if IsCheckQuest then
            local questText = QuestTitle and QuestTitle.Text or ""
            questMismatch = not string.find(questText, CustomName, 1, true)
        end

        if questMismatch or (IsCheckQuest and Quest and not Quest.Visible) then
            break
        end
    until humanoid.Health <= 0

    if tween then
        tween:Cancel()
    end

    return humanoid.Health <= 0
end

local function KaitunWorld1(Quest,QuestTitle,Level)
	CheckInv()
	if Level >= 700 then
		title.Text = "Doing Second Sea Puzzle"
		local canTravel = CommF_:InvokeServer("DressrosaQuestProgress", "Dressrosa")
		local dressrosaProgress = CommF_:InvokeServer("DressrosaQuestProgress")
		if not canTravel then
			if type(dressrosaProgress) == "table" and dressrosaProgress.TalkedDetective and dressrosaProgress.UsedKey then
				if workspace.Enemies:FindFirstChild("Ice Admiral") then
					for _, v in workspace.Enemies:GetChildren() do
						if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and v.Name == "Ice Admiral" then
                            SmartMoveAndAttack(v, QuestTitle, Quest, false)
							title.Text = "Travel To Second Sea"
							CommF_:InvokeServer("TravelDressrosa")
						end
					end
				else
					local t0 = Tween(CFrame.new(1382.562255859375, 26.999441146850586, -1458.77783203125),350)
					t0.Completed:Wait()
				end
			elseif IsOwn("Key") then
				CommF_:InvokeServer("DressrosaQuestProgress","UseKey")
			elseif not IsOwn("Key") then
				CommF_:InvokeServer("DressrosaQuestProgress","Detective")
			end
		else
			title.Text = "Travel To Second Sea"
			CommF_:InvokeServer("TravelDressrosa")
		end
	elseif Level >= 200 and getgenv().Configs.Saber and workspace.Map.Jungle.Final.Part.CanCollide and not IsSaber then
		title.Text = "Saber Quest | Solve Puzzle"
		if not workspace.Map.Jungle.QuestPlates.Door.CanCollide then
			local proProgress = CommF_:InvokeServer("ProQuestProgress")
			if type(proProgress) == "table" and proProgress.UsedTorch then
				if CommF_:InvokeServer("ProQuestProgress","SickMan") == 0 then
					if CommF_:InvokeServer("ProQuestProgress","RichSon") == 0 then
						if workspace.Enemies:FindFirstChild("Mob Leader") then
							for _, v in workspace.Enemies:GetChildren() do
								if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and v.Name == "Mob Leader" then
                                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
								end
							end
						else
							if (CFrame.new(-2848, 8, 5342).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
								t0 = Tween(CFrame.new(-2848, 8, 5342),350)
							elseif (CFrame.new(-2848, 8, 5342).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
								if t0 then
									t0:Cancel()
								end
								LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-2848, 8, 5342)
							end
						end
					elseif CommF_:InvokeServer("ProQuestProgress","RichSon") == 1 then
						CommF_:InvokeServer("ProQuestProgress","PlaceRelic")
					else
						CommF_:InvokeServer("ProQuestProgress","RichSon")
					end
				else
					CommF_:InvokeServer("ProQuestProgress","GetCup")
					task.wait(0.2)
					EquipName("Cup")
					task.wait(0.2)
					local cup = IsOwn("Cup")
					CommF_:InvokeServer("ProQuestProgress","FillCup",cup)
					CommF_:InvokeServer("ProQuestProgress","SickMan")
				end
			elseif IsOwn("Torch") then
				CommF_:InvokeServer("ProQuestProgress","DestroyTorch")
			elseif not IsOwn("Torch") then
				CommF_:InvokeServer("ProQuestProgress","GetTorch")
			end
		else
			for i, v in workspace.Map.Jungle.QuestPlates:GetChildren() do
				if v:IsA("Model") then
					if v.Button.BrickColor ~= BrickColor.new("Camo") then
                        title.Text = "Doing Saber Quest | Touching Plates " .. i .. "/5"
                        local tbar = Tween(v.Button.CFrame,350)
                        tbar.Completed:Wait()
						task.wait(0.5)
                        -- if firetouchinterest or identifyexecutor() ~= "Solara" then
                        --     firetouchinterest(LocalPlayer.Character.HumanoidRootPart,v.Button,0)
                        --     task.wait(0.1)
                        --     firetouchinterest(LocalPlayer.Character.HumanoidRootPart,v.Button,1) 
                        --     task.wait(0.1)
                        -- end
					end
				end
			end
		end
	elseif Level >= 200 and getgenv().Configs.Saber and not IsSaber and (ReplicatedStorage:FindFirstChild("Saber Expert") or workspace.Enemies:FindFirstChild("Saber Expert")) then
		title.Text = "Saber Quest | Kill Saber Expert"
		if workspace.Enemies:FindFirstChild("Saber Expert") then
			for _, v in workspace.Enemies:GetChildren() do
				if v.Name == "Saber Expert" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
				end
			end
		elseif ReplicatedStorage:FindFirstChild("Saber Expert") then
			if (CFrame.new(-1458.89502, 29.8870335, -50.633564).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
				t920 = Tween(CFrame.new(-1458.89502, 29.8870335, -50.633564),350)
			elseif (CFrame.new(-1458.89502, 29.8870335, -50.633564).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t920 then
					t920:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1458.89502, 29.8870335, -50.633564)
			end
			CommF_:InvokeServer("SetSpawnPoint")
		end
	elseif Level >= 200 and getgenv().Configs.Pole and not IsPoleV1 and (ReplicatedStorage:FindFirstChild("Thunder God") or workspace.Enemies:FindFirstChild("Thunder God")) then
		title.Text = "Get Pole | Kill Thunder God"
		if workspace.Enemies:FindFirstChild("Thunder God") then
			for _, v in workspace.Enemies:GetChildren() do
				if v.Name == "Thunder God" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
				end
			end
		elseif ReplicatedStorage:FindFirstChild("Thunder God") then
			if (CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
				t920 = Tween(CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125),350)
			elseif (CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t920 then
					t920:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-7795.9287109375, 5605.951171875, -2231.444580078125)
			end
			CommF_:InvokeServer("SetSpawnPoint")
		end
	elseif getgenv().Configs.SkipFarmLevel and (Level >= 0 and Level <= 24) then
		if workspace.Enemies:FindFirstChild("Dark Master") then
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if LocalPlayer.Data.Level.Value >= 25 then
					break
				end
				if v.Name == "Dark Master" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
				end
			end
		else
			title.Text = "Skip Farming Level | Waiting"
			local t0 = Tween(CFrame.new(-5250, 389, -2272),350)
			if (CFrame.new(-5250, 389, -2272).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t0 then
					t0:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-5250, 389, -2272)
			end 
		end
	elseif getgenv().Configs.SkipFarmLevel and (Level >= 25 and Level <= 59) then
		if workspace.Enemies:FindFirstChild("Royal Squad") then
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if LocalPlayer.Data.Level.Value >= 60 then
					break
				end
				if v.Name == "Royal Squad" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
				end
			end
		else
			title.Text = "Skip Farming Level | Waiting"
			local t0 = Tween(CFrame.new(-7670, 5607, -1460),350)
			if (CFrame.new(-7670, 5607, -1460).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t0 then
					t0:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-7670, 5607, -1460)
			end 
		end
    elseif not Quest.Visible then
		title.Text = "Auto Farming Level | Get Quest"
		if (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
			t2 = Tween(CFrameQ,350)
		elseif (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
			if t2 then
				t2:Cancel()
			end
			LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameQ
			CommF_:InvokeServer("StartQuest",NameQuest,LevelQuest)
			CommF_:InvokeServer("SetSpawnPoint")
		end
	elseif Quest.Visible then
		if workspace.Enemies:FindFirstChild(Monster) then
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if v.Name == Monster and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
					if string.find(QuestTitle.Text, NameCheckQuest) then
                        SmartMoveAndAttack(v, QuestTitle, Quest)
					else
						CommF_:InvokeServer("AbandonQuest")
					end
				end
			end
		else
			title.Text = "Auto Farming Level | Wait For " .. Monster
			if (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
				t0 = Tween(CFrameMon,350)
			elseif (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t0 then
					t0:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameMon
			end
		end
	end
end
local function KaitunWorld2(Quest,QuestTitle,Level)
	CheckInv()
	local bartiloProgress
	if Level >= 850 then
		bartiloProgress = CommF_:InvokeServer("BartiloQuestProgress", "Bartilo")
	end
	if workspace.Enemies:FindFirstChild("Core") or ReplicatedStorage:FindFirstChild("Core") then
		if workspace.Enemies:FindFirstChild("Core") then
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if v.Name == "Core" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") then
                    SmartMoveAndAttack(v, QuestTitle, Quest, false)
				end
			end
		elseif ReplicatedStorage:FindFirstChild("Core") then
			Tween(CFrame.new(448.46756, 199.356781, -441.389252),350)
		end
	elseif Level >= 850 and (bartiloProgress == 0 or bartiloProgress == 2 or (bartiloProgress == 1 and (workspace.Enemies:FindFirstChild("Jeremy") or ReplicatedStorage:FindFirstChild("Jeremy")))) then
        if bartiloProgress == 0 then
            if LocalPlayer.PlayerGui.Main.Quest.Visible then 
                if string.find(LocalPlayer.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text, "50 Swan Pirates") then
                    if workspace.Enemies:FindFirstChild("Swan Pirate") then
                        for _, v in pairs(workspace.Enemies:GetChildren()) do
                            if v.Name == "Swan Pirate" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                                SmartMoveAndAttack(v, QuestTitle, Quest, false, "Swan Pirate")
                            end
                        end
                    else
                        title.Text = "Doing Bartilo Quest | Wait For Swan Pirates"
                        if (CFrame.new(878, 122, 1235).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
                            t0 = Tween(CFrame.new(878, 122, 1235),350)
                        elseif (CFrame.new(878, 122, 1235).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
                            if t0 then
                                t0:Cancel()
                            end
                            LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(878, 122, 1235)
                        end
                    end
                else
                    CommF_:InvokeServer("AbandonQuest")
                end
            else
                CommF_:InvokeServer("StartQuest","BartiloQuest",1)
            end
        elseif bartiloProgress == 1 and (workspace.Enemies:FindFirstChild("Jeremy") or ReplicatedStorage:FindFirstChild("Jeremy")) then
            if workspace.Enemies:FindFirstChild("Jeremy") then
                for _,v in pairs(workspace.Enemies:GetChildren()) do
                    if v.Name == "Jeremy" and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                        SmartMoveAndAttack(v, QuestTitle, Quest, false)
                    end
                end
            elseif ReplicatedStorage:FindFirstChild("Jeremy") then
                if (CFrame.new(2099.88159, 448.931, 648.997375).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
                    t920 = Tween(CFrame.new(2099.88159, 448.931, 648.997375),350)
                elseif (CFrame.new(2099.88159, 448.931, 648.997375).Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
                    if t920 then
                        t920:Cancel()
                    end
                    LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(2099.88159, 448.931, 648.997375)
                end
                CommF_:InvokeServer("SetSpawnPoint")
            end
        elseif bartiloProgress == 2 then
            local plates = {}
            for _, v in ipairs(workspace.Map.Dressrosa.BartiloPlates:GetChildren()) do
                local num = tonumber(string.match(v.Name, "%d+$"))
                if num then
                    table.insert(plates, {num = num, plate = v})
                end
            end
            table.sort(plates, function(a, b)
                return a.num < b.num
            end)
            -- for _, v in ipairs(plates) do
            --     if v.plate.BrickColor ~= BrickColor.new("Olivine") then
			-- 		title.Text = "Doing Bartilo Quest | Touching Plates " .. v.num .. "/8"
			-- 		-- repeat task.wait()
			-- 		-- 	local tbar = Tween(v.plate.CFrame,350)
			-- 		-- 	tbar.Completed:Wait()
			-- 		-- until v.plate.BrickColor == BrickColor.new("Olivine")
			-- 		-- -- firetouchinterest(LocalPlayer.Character.HumanoidRootPart,v.plate,0)
			-- 		-- -- task.wait(0.1)
			-- 		-- -- firetouchinterest(LocalPlayer.Character.HumanoidRootPart,v.plate,1)
			-- 		-- -- task.wait(0.1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1837.46155, 44.2921753, 1656.1987, 0.999881566, -1.03885048e-22, -0.0153914848, 1.07805858e-22, 1, 2.53909284e-22, 0.0153914848, -2.55538502e-22, 0.999881566)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1836.0, 11, 1714)
					task.wait(.5)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1850.49329, 13.1789551, 1750.89685)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1858.87305, 19.3777466, 1712.01807)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1803.94324, 16.5789185, 1750.89685)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1858.55835, 16.8604317, 1724.79541)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1869.54224, 15.987854, 1681.00659)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1800.0979, 16.4978027, 1684.52368)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1819.26343, 14.795166, 1717.90625)
					task.wait(1)
					LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-1813.51843, 14.8604736, 1724.79541)
            --     end
            -- end
        end
    elseif not Quest.Visible then
		title.Text = "Auto Farming Level | Get Quest"
		if (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
			t2 = Tween(CFrameQ,350)
		elseif (CFrameQ.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
			if t2 then
				t2:Cancel()
			end
			LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameQ
			CommF_:InvokeServer("StartQuest",NameQuest,LevelQuest)
			CommF_:InvokeServer("SetSpawnPoint")
		end
	elseif Quest.Visible then
		if workspace.Enemies:FindFirstChild(Monster) then
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if v.Name == Monster and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
					if string.find(QuestTitle.Text, NameCheckQuest) then
                        SmartMoveAndAttack(v, QuestTitle, Quest)
					else
						CommF_:InvokeServer("AbandonQuest")
					end
				end
			end
		else
			title.Text = "Auto Farming Level | Wait For " .. Monster
			if (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude > 150 then
				t0 = Tween(CFrameMon,350)
			elseif (CFrameMon.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude <= 150 then
				if t0 then
					t0:Cancel()
				end
				LocalPlayer.Character.HumanoidRootPart.CFrame = CFrameMon
			end
		end
	end
end
local Melees = {
    ["Black Leg"] = {
        NPC = "Dark Step Teacher",
        Price = {
            Beli = 150000,
            Fragments = 0
        },
        BuyID = "BuyBlackLeg",
        RequiredMastery = 400,
        IsCompleted = false,
		World = 1
    },
    ["Electro"] = {
        NPC = "Mad Scientist",
        Price = {
            Beli = 500000,
            Fragments = 0
        },
        BuyID = "BuyElectro",
        RequiredMastery = 400,
        IsCompleted = false,
		World = 1
    },
    ["Fishman Karate"] = {
        NPC = "Water Kung-fu Teacher",
        Price = {
            Beli = 750000,
            Fragments = 0
        },
        BuyID = "BuyFishmanKarate",
        RequiredMastery = 400,
        IsCompleted = false,
		World = 1
    },
    ["Dragon Claw"] = {
        NPC = "Sabi",
        Price = {
            Beli = 0,
            Fragments = 1500
        },
        BuyID = "BuyDragonClaw",
        RequiredMastery = 400,
        IsCompleted = false,
		World = 2
    },
    ["Superhuman"] = {
        NPC = "Martial Arts Master",
        Price = {
            Beli = 3000000,
            Fragments = 0
        },
        BuyID = "BuySuperhuman",
        RequiredMastery = 400,
        IsCompleted = false,
		World = 2
    },
    ["Death Step"] = {
        NPC = "Phoeyu, the Reformed",
        Price = {
            Beli = 2500000,
            Fragments = 5000
        },
        BuyID = "BuyDeathStep",
        RequiredMastery = 400, -- must master Dark Step first
        IsCompleted = false,
		World = 2
    },
    ["Sharkman Karate"] = {
        NPC = "Sharkman Teacher",
        Price = {
            Beli = 2500000,
            Fragments = 5000
        },
        BuyID = "BuySharkmanKarate",
        RequiredMastery = 400, -- must master Water Kung Fu + deliver Water Key
        IsCompleted = false,
		World = 2
    },
    ["Electric Claw"] = {
        NPC = "Previous Hero",
        Price = {
            Beli = 3000000,
            Fragments = 5000
        },
        BuyID = "BuyElectricClaw",
        RequiredMastery = 400, -- must master Electro + complete Hero quest
        IsCompleted = false,
		World = 3
    },
    ["Dragon Talon"] = {
        NPC = "Uzoth",
        Price = {
            Beli = 3000000,
            Fragments = 5000
        },
        BuyID = "BuyDragonTalon",
        RequiredMastery = 400, -- must master Dragon Claw + give Fire Essence
        IsCompleted = false,
		World = 3
    },
    ["Godhuman"] = {
        NPC = "Ancient Monk",
        Price = {
            Beli = 5000000,
            Fragments = 5000
        },
        BuyID = "BuyGodhuman",
        RequiredMastery = 400, -- must master Superhuman, Death Step, Electric Claw, Sharkman Karate, Dragon Talon
        IsCompleted = false,
		World = 3
    }
}
local Prerequisites = {
    ["Superhuman"] = {"Black Leg", "Electro", "Fishman Karate", "Dragon Claw"},
    ["Death Step"] = {"Black Leg"},
    ["Sharkman Karate"] = {"Fishman Karate"},
    ["Electric Claw"] = {"Electro"},
    ["Dragon Talon"] = {"Dragon Claw"},
    ["Godhuman"] = {"Superhuman", "Death Step", "Sharkman Karate", "Electric Claw", "Dragon Talon"}
}

local MeleeOrder = {
    "Black Leg",
    "Electro",
    "Fishman Karate",
    "Dragon Claw",
    "Superhuman",
    "Death Step",
    "Sharkman Karate",
    "Electric Claw",
    "Dragon Talon",
    "Godhuman"
}

local function MarkPrerequisitesComplete(styleName, visited)
    visited = visited or {}
    if visited[styleName] then return end
    visited[styleName] = true

    local requirements = Prerequisites[styleName]
    if not requirements then return end

    for _, requiredStyle in ipairs(requirements) do
        if Melees[requiredStyle] then
            Melees[requiredStyle].IsCompleted = true
            MarkPrerequisitesComplete(requiredStyle, visited)
        end
    end
end

for _, styleName in ipairs(MeleeOrder) do
    local data = Melees[styleName]
    local ok, status = pcall(function()
        return CommF_:InvokeServer(data.BuyID, true)
    end)
    if ok and status == 1 then
        MarkPrerequisitesComplete(styleName)
    end
end

local function BuildInventoryNameSet(inv)
    local names = {}
    for _, item in ipairs(inv or {}) do
        if type(item) == "table" and item.Name then
            names[item.Name] = true
        end
    end
    return names
end

local function StoreFruitTool(tool, inventoryNames)
    if not tool or not tool.Parent or not tool:IsA("Tool") then
        return false
    end

    local originalName = tool:GetAttribute("OriginalName")
    if not originalName or inventoryNames[originalName] then
        return false
    end

    if tool.Parent == LocalPlayer.Backpack then
        EquipName(tool.Name)
        task.wait(0.05)
    end

    local ok = pcall(function()
        CommF_:InvokeServer("StoreFruit", originalName, tool)
    end)

    if ok then
        inventoryNames[originalName] = true
        InvalidateInventoryCache()
    end

    return ok
end

local function HandleFruits()
    local inv = GetInventory(false)
    local inventoryNames = BuildInventoryNameSet(inv)
    local hrp = GetHRP()
    if not hrp then return end

    for _, fruit in ipairs(workspace:GetChildren()) do
        if fruit:IsA("Model") and string.find(fruit.Name:lower(), "fruit", 1, true) then
            local handle = fruit:FindFirstChild("Handle")
            local originalName = fruit:GetAttribute("OriginalName")

            if handle and originalName and not inventoryNames[originalName] then
                title.Text = "Get " .. fruit.Name
                local distance = (handle.Position - hrp.Position).Magnitude

                if distance > 150 then
                    local tween = Tween(handle.CFrame, 350)
                    if tween then
                        tween.Completed:Wait()
                        task.wait(0.15)
                    end
                else
                    hrp.CFrame = handle.CFrame
                    task.wait(0.1)
                end

                hrp = GetHRP()
                if not hrp then return end
            end
        end
    end

    local character = LocalPlayer.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") and string.find(tool.Name:lower(), "fruit", 1, true) then
                StoreFruitTool(tool, inventoryNames)
            end
        end
    end

    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and string.find(tool.Name:lower(), "fruit", 1, true) then
            StoreFruitTool(tool, inventoryNames)
        end
    end
end

local function GetCurrentMelee()
    local character = LocalPlayer.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") and tool.ToolTip == "Melee" then
                return tool.Name, tool
            end
        end
    end

    for _, tool in ipairs(LocalPlayer.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == "Melee" then
            return tool.Name, tool
        end
    end

    return nil, nil
end

local function GetMeleeMastery(styleName)
    local tool = IsOwn(styleName)
    local level = tool and tool:FindFirstChild("Level")
    return level and tonumber(level.Value) or 0
end

local function MoveToMeleeNPC(data)
    local workspaceNPCs = workspace:FindFirstChild("NPCs")
    local replicatedNPCs = ReplicatedStorage:FindFirstChild("NPCs")
    local npc = (workspaceNPCs and workspaceNPCs:FindFirstChild(data.NPC))
        or (replicatedNPCs and replicatedNPCs:FindFirstChild(data.NPC))
    local root = npc and npc:FindFirstChild("HumanoidRootPart")
    if not root then
        return false
    end

    local tween = Tween(root.CFrame, 350)
    if tween then
        tween.Completed:Wait()
    end
    return true
end

local function HasResourcesForMelee(data)
    local beli = LocalPlayer.Data.Beli.Value
    if beli < data.Price.Beli then
        return false
    end

    if data.Price.Fragments > 0 then
        local fragments = LocalPlayer.Data:FindFirstChild("Fragments")
        if not fragments or fragments.Value < data.Price.Fragments then
            return false
        end
    end

    return true
end

local function ProgressMelee()
    local currentName = GetCurrentMelee()

    if currentName and currentName ~= "Combat" and Melees[currentName] then
        MarkPrerequisitesComplete(currentName)
        local currentData = Melees[currentName]
        local mastery = GetMeleeMastery(currentName)

        if mastery < currentData.RequiredMastery then
            subtitle.Text = "Farming Until " .. currentName .. " Reaches " .. currentData.RequiredMastery .. " Mastery"
            return
        end

        currentData.IsCompleted = true
    end

    for _, styleName in ipairs(MeleeOrder) do
        local data = Melees[styleName]

        if data.IsCompleted then
            continue
        end

        if GetWorld() < data.World then
            continue
        end

        local mastery = GetMeleeMastery(styleName)
        if mastery >= data.RequiredMastery then
            data.IsCompleted = true
            MarkPrerequisitesComplete(styleName)
            continue
        end

        if currentName == styleName then
            subtitle.Text = "Farming Until " .. styleName .. " Reaches " .. data.RequiredMastery .. " Mastery"
            return
        end

        local ok, status = pcall(function()
            return CommF_:InvokeServer(data.BuyID, true)
        end)

        if (ok and status == 1) or HasResourcesForMelee(data) then
            title.Text = "Get " .. styleName
            MoveToMeleeNPC(data)

            pcall(function()
                CommF_:InvokeServer(data.BuyID)
            end)

            task.wait(0.1)
            local equipped = IsOwn(styleName)
            if equipped then
                subtitle.Text = "Farming Until " .. styleName .. " Reaches " .. data.RequiredMastery .. " Mastery"
            else
                subtitle.Text = "Waiting requirements for " .. styleName
            end
        else
            subtitle.Text = "Farming Until Has Enough Resources For " .. styleName
        end
        return
    end
end

local function RunMainCycle()
    DieWait()
    HandleFruits()

    CheckQuest()

    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("Main")
    local Quest = mainGui and mainGui:FindFirstChild("Quest")
    local container = Quest and Quest:FindFirstChild("Container")
    local questTitleContainer = container and container:FindFirstChild("QuestTitle")
    local QuestTitle = questTitleContainer and questTitleContainer:FindFirstChild("Title")
    if not Quest or not QuestTitle then
        return
    end

    local CurLevel = LocalPlayer.Data.Level.Value
    ProgressMelee()

    if World1 then
        KaitunWorld1(Quest, QuestTitle, CurLevel)
    elseif World2 then
        KaitunWorld2(Quest, QuestTitle, CurLevel)
    elseif World3 then
        title.Text = "Third Sea detected"
        subtitle.Text = "World 3 farming is not implemented in this script yet"
    end
end

task.spawn(function()
    while task.wait(Configs.MainLoopDelay) do
        local ok, err = pcall(RunMainCycle)
        if not ok then
            subtitle.Text = "Recovering from runtime error"
            warn("[Kaitun/Main] " .. tostring(err))
            task.wait(0.5)
        end
    end
end)

local LastRandomFruitAttempt = 0

local function SpendStatPoints()
    local data = LocalPlayer.Data
    local pointsValue = data.Points.Value
    if pointsValue <= 0 then return end

    local level = data.Level.Value
    local melee = data.Stats.Melee.Level.Value
    local defense = data.Stats.Defense.Level.Value
    local sword = data.Stats.Sword.Level.Value

    local targetMelee = math.min(MaxLevel, level * 2)
    local targetDefense = math.min(MaxLevel, level)

    local addMelee = math.max(0, math.min(pointsValue, targetMelee - melee))
    if addMelee > 0 then
        CommF_:InvokeServer("AddPoint", "Melee", addMelee)
        pointsValue -= addMelee
    end

    local addDefense = math.max(0, math.min(pointsValue, targetDefense - defense))
    if addDefense > 0 then
        CommF_:InvokeServer("AddPoint", "Defense", addDefense)
        pointsValue -= addDefense
    end

    if pointsValue > 0 and melee >= MaxLevel and defense >= MaxLevel then
        local targetSword = math.max(0, math.min(MaxLevel, level * 3 - MaxLevel * 2))
        local addSword = math.max(0, math.min(pointsValue, targetSword - sword))
        if addSword > 0 then
            CommF_:InvokeServer("AddPoint", "Sword", addSword)
        end
    end
end

local function RunUtilityCycle()
    local character = LocalPlayer.Character
    if not character then return end

    SpendStatPoints()

    if not CollectionService:HasTag(character, "Buso") and LocalPlayer.Data.Beli.Value >= 25000 then
        CommF_:InvokeServer("BuyHaki", "Buso")
    end
    if not CollectionService:HasTag(character, "Geppo") and LocalPlayer.Data.Beli.Value >= 10000 then
        CommF_:InvokeServer("BuyHaki", "Geppo")
    end
    if not CollectionService:HasTag(character, "Soru") and LocalPlayer.Data.Beli.Value >= 100000 then
        CommF_:InvokeServer("BuyHaki", "Soru")
    end
    if not CollectionService:HasTag(character, "Ken") and World1 and LocalPlayer.Data.Beli.Value >= 750000 then
        CommF_:InvokeServer("KenTalk", "Buy")
    end

    if Configs.AutoRandomFruit and os.clock() - LastRandomFruitAttempt >= Configs.RandomFruitInterval then
        LastRandomFruitAttempt = os.clock()
        CommF_:InvokeServer("Cousin", "Buy")
    end
end

task.spawn(function()
    while task.wait(Configs.UtilityLoopDelay) do
        local ok, err = pcall(RunUtilityCycle)
        if not ok then
            warn("[Kaitun/Utility] " .. tostring(err))
        end
    end
end)

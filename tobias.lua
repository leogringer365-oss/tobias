-- Tobias Hub v2.5 BLACKBOX DEBUG
-- Menu: RightShift | Configs salvas quando o executor suporta writefile/readfile

getgenv().Configs = getgenv().Configs or {}
local Configs = getgenv().Configs
local ConfigHttpService = game:GetService("HttpService")
local CONFIG_FILE = "tobias_hub_config.json"

-- Load saved settings when the executor supports file APIs.
do
    local ok, saved = pcall(function()
        if isfile and readfile and isfile(CONFIG_FILE) then
            return ConfigHttpService:JSONDecode(readfile(CONFIG_FILE))
        end
    end)
    if ok and type(saved) == "table" then
        for key, value in pairs(saved) do
            Configs[key] = value
        end
    end
end

local Defaults = {
    Team = "Pirates",
    AutoFarmLevel = true,
    Saber = true,
    Pole = true,
    SkipFarmLevel = true,
    AutoWorldProgress = true,
    AutoFactory = true,
    AutoBartilo = true,
    AutoFruitPickup = true,
    AutoStoreFruit = true,
    AutoRandomFruit = true,
    AutoRedeemCodes = true,
    DisableCameraShake = true,
    AutoMelee = true,
    AutoStats = true,
    AutoHaki = true,
    AutoBuso = true,
    AutoMeleeSkill = true,
    BringMobs = true,
    CombatMoveMode = "Hybrid",
    CombatSnapDistance = 300,
    TweenSpeed = 350,
    FarmHeight = 30,
    BringDistance = 350,
    AttackDelay = 0.20,
    MainLoopDelay = 0.05,
    UtilityLoopDelay = 1,
    RandomFruitInterval = 60,
    DebugEnabled = true,
    VerboseDebug = false,
    DebugMaxLogs = 500,
    DebugTraceEnabled = true,
    QuestStartCooldown = 0.75,
    QuestConfirmTimeout = 1.50,
    InventoryCacheTTL = 1.00
}

for key, value in pairs(Defaults) do
    if Configs[key] == nil then
        Configs[key] = value
    end
end

local function SaveConfigs()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, ConfigHttpService:JSONEncode(Configs))
        end
    end)
end

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
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local CommF_ = ReplicatedStorage.Remotes.CommF_

-- =========================================================
-- TOBIAS DEBUG / DIAGNOSTICS
-- =========================================================
local DebugState = {
    StartedAt = os.clock(),
    CurrentFunction = "Boot",
    PreviousFunction = "-",
    LastFunctionAt = os.clock(),
    LastError = "NONE",
    LastErrorAt = 0,
    ErrorCount = 0,
    LastRemote = "NONE",
    LastRemoteArgs = "-",
    LastRemoteResult = "-",
    RemoteCount = 0,
    LastTarget = "NONE",
    LastTargetHP = "-",
    LastQuest = "NONE",
    LastTween = "NONE",
    LastTweenDistance = 0,
    LastMoveMode = "NONE",
    LastMoveDistance = 0,
    CurrentState = "BOOTING",
    FunctionCalls = {},
    FunctionLastDuration = {},
    RemoteCalls = {},
    RemoteLastResult = {},
    Logs = {},
    ActiveTests = {},
    ActionSeq = 0,
    ActionCount = 0,
    ActionCounts = {},
    ActionHistory = {},
    CurrentAction = "BOOT",
    LastAction = "BOOT",
    LastActionDetails = "-",
    LastActionAt = 0,
    LastActionTimes = {},
    LastQuestSelection = "",
    LastQuestGuiVisible = nil,
    LastQuestGuiText = "",
    AttackAttempts = 0,
    AttackSuccess = 0,
    RegisterAttackCount = 0,
    RegisterHitCount = 0,
    CombatEntries = 0,
    CombatExits = 0,
    MovementActions = 0,
    EquipAttempts = 0,
    EquipSuccess = 0,
    QuestRequests = 0,
    QuestConfirmed = 0,
    TargetHpEvents = 0,
}

local function DebugSerialize(value, depth)
    depth = depth or 0
    if depth > 2 then return "..." end
    local kind = typeof(value)
    if kind == "Instance" then
        return value:GetFullName()
    elseif kind == "CFrame" then
        local p = value.Position
        return string.format("CFrame(%.0f, %.0f, %.0f)", p.X, p.Y, p.Z)
    elseif kind == "Vector3" then
        return string.format("Vector3(%.0f, %.0f, %.0f)", value.X, value.Y, value.Z)
    elseif type(value) == "table" then
        local out = {}
        local count = 0
        for k, v in pairs(value) do
            count += 1
            if count > 5 then
                table.insert(out, "...")
                break
            end
            table.insert(out, tostring(k) .. "=" .. DebugSerialize(v, depth + 1))
        end
        return "{" .. table.concat(out, ", ") .. "}"
    end
    local text = tostring(value)
    if #text > 140 then text = text:sub(1, 137) .. "..." end
    return text
end

local function DebugLog(category, message, force)
    if not Configs.DebugEnabled and not force then return end
    local entry = string.format("[%s][%s] %s", os.date("%H:%M:%S"), tostring(category), tostring(message))
    table.insert(DebugState.Logs, 1, entry)
    local maxLogs = math.clamp(tonumber(Configs.DebugMaxLogs) or 500, 50, 1000)
    while #DebugState.Logs > maxLogs do
        table.remove(DebugState.Logs)
    end
    if Configs.VerboseDebug or category == "ERROR" then
        warn("[TobiasDebug] " .. entry)
    end
end

local function DebugAction(action, details, minInterval, force)
    if not Configs.DebugTraceEnabled and not force then return end
    action = tostring(action or "UNKNOWN")
    details = details ~= nil and tostring(details) or "-"
    local now = os.clock()
    local key = action .. "|" .. details
    local interval = tonumber(minInterval) or 0
    local last = DebugState.LastActionTimes[key] or 0
    if interval > 0 and (now - last) < interval then
        return
    end
    DebugState.LastActionTimes[key] = now
    DebugState.ActionSeq += 1
    DebugState.ActionCount += 1
    DebugState.ActionCounts[action] = (DebugState.ActionCounts[action] or 0) + 1
    DebugState.CurrentAction = action
    DebugState.LastAction = action
    DebugState.LastActionDetails = details
    DebugState.LastActionAt = now
    local entry = string.format("#%05d +%.3fs %-22s | %s", DebugState.ActionSeq, now - DebugState.StartedAt, action, details)
    table.insert(DebugState.ActionHistory, 1, entry)
    local maxActions = math.clamp(tonumber(Configs.DebugMaxLogs) or 500, 50, 1000)
    while #DebugState.ActionHistory > maxActions do
        table.remove(DebugState.ActionHistory)
    end
    DebugLog("ACTION", entry, force)
end

local function DebugTopActions(limit)
    local list = {}
    for name, count in pairs(DebugState.ActionCounts) do
        table.insert(list, {name = name, count = count})
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    local out = {}
    for i = 1, math.min(limit or 12, #list) do
        local item = list[i]
        table.insert(out, string.format("%s: %d", item.name, item.count))
    end
    return table.concat(out, "\n")
end

local function DebugFunction(name, details)
    DebugState.PreviousFunction = DebugState.CurrentFunction
    DebugState.CurrentFunction = tostring(name)
    DebugState.LastFunctionAt = os.clock()
    DebugState.FunctionCalls[name] = (DebugState.FunctionCalls[name] or 0) + 1
    if details then
        DebugLog("FUNC", name .. " | " .. tostring(details))
    end
    return os.clock()
end

local function DebugFunctionEnd(name, startedAt)
    if startedAt then
        DebugState.FunctionLastDuration[name] = os.clock() - startedAt
    end
end

local function DebugError(where, err)
    DebugState.ErrorCount += 1
    DebugState.LastErrorAt = os.clock()
    DebugState.LastError = tostring(where) .. ": " .. tostring(err)
    DebugLog("ERROR", DebugState.LastError, true)
end

local function DebugSetState(state)
    if DebugState.CurrentState ~= state then
        DebugState.CurrentState = tostring(state)
        DebugLog("STATE", DebugState.CurrentState)
    end
end

local function DebugInvoke(...)
    local args = {...}
    local command = tostring(args[1] or "<no-command>")
    DebugState.LastRemote = command
    DebugState.RemoteCount += 1
    DebugState.RemoteCalls[command] = (DebugState.RemoteCalls[command] or 0) + 1

    local argText = {}
    for i = 1, math.min(#args, 6) do
        argText[i] = DebugSerialize(args[i])
    end
    DebugState.LastRemoteArgs = table.concat(argText, " | ")
    DebugLog("REMOTE", DebugState.LastRemoteArgs)
    DebugAction("REMOTE_CALL", DebugState.LastRemoteArgs)

    local packed = table.pack(pcall(function()
        return CommF_:InvokeServer(table.unpack(args, 1, #args))
    end))
    local ok = packed[1]
    if not ok then
        DebugState.LastRemoteResult = "ERROR: " .. tostring(packed[2])
        DebugError("Remote/" .. command, packed[2])
        return nil
    end

    DebugState.LastRemoteResult = DebugSerialize(packed[2])
    DebugState.RemoteLastResult[command] = DebugState.LastRemoteResult
    DebugAction("REMOTE_RETURN", command .. " => " .. DebugState.LastRemoteResult)
    return table.unpack(packed, 2, packed.n)
end

local function DebugTopFunctions(limit)
    local list = {}
    for name, count in pairs(DebugState.FunctionCalls) do
        table.insert(list, {name = name, count = count})
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    local out = {}
    for i = 1, math.min(limit or 8, #list) do
        local item = list[i]
        local duration = DebugState.FunctionLastDuration[item.name]
        table.insert(out, string.format("%s: %d%s", item.name, item.count,
            duration and string.format(" (%.3fms)", duration * 1000) or ""))
    end
    return table.concat(out, "\n")
end

local function DebugTopRemotes(limit)
    local list = {}
    for name, count in pairs(DebugState.RemoteCalls) do
        table.insert(list, {name = name, count = count})
    end
    table.sort(list, function(a, b) return a.count > b.count end)
    local out = {}
    for i = 1, math.min(limit or 8, #list) do
        table.insert(out, string.format("%s: %d", list[i].name, list[i].count))
    end
    return table.concat(out, "\n")
end

if not LocalPlayer.Team then
    repeat
        task.wait(0.25)
        pcall(function()
            DebugInvoke("SetTeam", Configs.Team)
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
local LastRandomFruitAttempt = 0

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
    local __dbgStart = DebugFunction("TeleportServer","cursor=" .. tostring(cursor))
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
local ActiveTween = nil
local ActiveTweenTarget = nil
local ActiveTweenSpeed = nil
local ActiveTweenGeneration = 0

local function SameTweenTarget(a, b)
    if not a or not b then return false end
    return (a.Position - b.Position).Magnitude <= 1
end

local function CancelActiveTween(reason)
    if ActiveTween and ActiveTween.PlaybackState == Enum.PlaybackState.Playing then
        DebugAction("TWEEN_CANCEL", tostring(reason or "movement changed"), 0.10)
        pcall(function() ActiveTween:Cancel() end)
    end
    ActiveTween = nil
    ActiveTweenTarget = nil
    ActiveTweenSpeed = nil
    ActiveTweenGeneration += 1
    IsTweening = false
end

local function Tween(target, speed)
    local __dbgStart = DebugFunction("Tween",DebugSerialize(target))
    speed = math.max(tonumber(Configs.TweenSpeed) or tonumber(speed) or 350, 1)
    local hrp = GetHRP()
    if not hrp or not target then
        DebugAction("TWEEN_ABORT", "hrp=" .. tostring(hrp ~= nil) .. " target=" .. tostring(target ~= nil), 0.30)
        return nil
    end

    -- IMPORTANT: the main farm loop runs many times per second. Reusing the
    -- same tween prevents TweenService from cancelling the previous tween on
    -- every cycle when the destination has not changed.
    if ActiveTween
        and ActiveTween.PlaybackState == Enum.PlaybackState.Playing
        and SameTweenTarget(ActiveTweenTarget, target)
        and math.abs((ActiveTweenSpeed or speed) - speed) < 0.01 then
        IsTweening = true
        DebugSetState("TWEENING")
        DebugState.LastTween = DebugSerialize(target)
        DebugState.LastTweenDistance = (hrp.Position - target.Position).Magnitude
        DebugAction("TWEEN_REUSE", string.format("dist=%.1f target=%s", DebugState.LastTweenDistance, DebugSerialize(target)), 0.50)
        return ActiveTween
    end

    if ActiveTween and ActiveTween.PlaybackState == Enum.PlaybackState.Playing then
        DebugAction("TWEEN_REPLACE", "old=" .. DebugSerialize(ActiveTweenTarget) .. " new=" .. DebugSerialize(target), 0.10)
        pcall(function() ActiveTween:Cancel() end)
    end

    DebugSetState("TWEENING")
    DebugState.LastTween = DebugSerialize(target)

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
            DebugInvoke("requestEntrance", closestEntrance)
        end)
        task.wait(0.35)
        hrp = GetHRP()
        if not hrp then
            IsTweening = false
            return nil
        end
    end

    local distance = (hrp.Position - target.Position).Magnitude
    DebugState.LastTweenDistance = distance
    DebugState.MovementActions += 1
    DebugAction("TWEEN_START", string.format("dist=%.1f speed=%.1f target=%s", distance, speed, DebugSerialize(target)))

    local tween = TweenService:Create(
        hrp,
        TweenInfo.new(distance / speed, Enum.EasingStyle.Linear),
        {CFrame = target}
    )

    ActiveTweenGeneration += 1
    local myGeneration = ActiveTweenGeneration
    ActiveTween = tween
    ActiveTweenTarget = target
    ActiveTweenSpeed = speed
    IsTweening = true
    tween:Play()

    task.spawn(function()
        local playback = tween.Completed:Wait()
        -- An old/cancelled tween must not clear the state of a newer tween.
        if ActiveTween == tween and ActiveTweenGeneration == myGeneration then
            ActiveTween = nil
            ActiveTweenTarget = nil
            ActiveTweenSpeed = nil
            IsTweening = false
        end
        DebugAction("TWEEN_END", "state=" .. tostring(playback) .. " target=" .. DebugSerialize(target))
    end)

    return tween
end

local CombatRemote
local CombatRemotePathNames = {"Util", "Remotes", "Assets", "Common", "FX"}

local function FindCombatRemote()
    local __dbgStart = DebugFunction("FindCombatRemote")
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
    local __dbgStart = DebugFunction("IsOwn",tostring(name))
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
    local __dbgStart = DebugFunction("TryUseMeleeV")
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
            DebugAction("SKILL_CAST", info.Name .. " | V | mastery=" .. tostring(level.Value))
            VirtualInputManager:SendKeyEvent(true, "V", false, game)
            VirtualInputManager:SendKeyEvent(false, "V", false, game)
            return
        end
    end
end

local function Attack(target)
    local __dbgStart = DebugFunction("Attack",DebugSerialize(target))
    DebugSetState("ATTACKING")
    DebugState.AttackAttempts += 1
    DebugAction("ATTACK_ATTEMPT", DebugSerialize(target))
    if os.clock() - LastAttackTime < math.max(tonumber(Configs.AttackDelay) or 0.2, 0.03) then
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
        DebugAction("ATTACK_ABORT", "no valid targets")
        return false
    end

    LastAttackTime = os.clock()

    if Configs.AutoBuso and not character:FindFirstChild("HasBuso") then
        pcall(function()
            DebugInvoke("Buso")
        end)
    end

    if Configs.AutoMeleeSkill then
        TryUseMeleeV()
    end

    local h = "RE/RegisterHit"
    local key = math.floor(workspace:GetServerTimeNow() / 10 % 10)
    local encodedParts = table.create(#h)
    for i = 1, #h do
        encodedParts[i] = string.char(bit32.bxor(string.byte(h, i), key + 1))
    end
    local encoded = table.concat(encodedParts)

    local first = targets[1]
    DebugState.LastTarget = first and first.Name or "NONE"
    DebugState.LastTargetHP = first and first:FindFirstChild("Humanoid") and string.format("%.0f/%.0f", first.Humanoid.Health, first.Humanoid.MaxHealth) or "-"
    local firstHead = first:FindFirstChild("Head")
    if not firstHead then
        return false
    end

    DebugState.RegisterAttackCount += 1
    DebugAction("REGISTER_ATTACK", "targets=" .. tostring(#targets))
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
            DebugAction("COMBAT_REMOTE_FIRE", "multi target | " .. first.Name .. " + " .. second.Name)
            ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(firstHead, hitData, nil, v106)
            DebugState.RegisterHitCount += 1
            DebugState.AttackSuccess += 1
            DebugAction("REGISTER_HIT", "multi target | " .. first.Name .. " + " .. second.Name)
            DebugAction("ATTACK_SENT", "success=true")
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
    DebugAction("COMBAT_REMOTE_FIRE", "single target | " .. first.Name)
    ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(firstHead, hitData, v106)
    DebugState.RegisterHitCount += 1
    DebugState.AttackSuccess += 1
    DebugAction("REGISTER_HIT", "single target | " .. first.Name)
    DebugAction("ATTACK_SENT", "success=true")
    return true
end

local function DieWait()
    local __dbgStart = DebugFunction("DieWait")
    local character = GetCharacter()
    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")

    if humanoid.Health <= 0 or not character:FindFirstChild("Head") then
        DebugAction("PLAYER_DEAD_WAIT", "waiting respawn", 0, true)
        repeat
            task.wait(0.25)
            character = LocalPlayer.Character
            humanoid = character and character:FindFirstChildOfClass("Humanoid")
        until character and humanoid and humanoid.Health > 0 and character:FindFirstChild("Head")
        DebugAction("PLAYER_RESPAWNED", "hp=" .. tostring(humanoid.Health), 0, true)
    end

    if not character:FindFirstChild("HasBuso") then
        pcall(function()
            DebugInvoke("Buso")
        end)
    end
end

local function EquipWeapon(toolType)
    local __dbgStart = DebugFunction("EquipWeapon",tostring(toolType))
    DebugState.EquipAttempts += 1
    DebugAction("EQUIP_ATTEMPT", tostring(toolType), 0.10)
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not character or not backpack then
        DebugAction("EQUIP_FAIL", "character/backpack missing")
        return nil
    end

    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == toolType then
            DebugAction("EQUIP_ALREADY", tool.Name, 0.25)
            return tool
        end
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        DebugAction("EQUIP_FAIL", "humanoid missing")
        return nil
    end

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == toolType then
            humanoid:EquipTool(tool)
            DebugState.EquipSuccess += 1
            DebugAction("EQUIP_SUCCESS", tool.Name .. " type=" .. tostring(toolType))
            return tool
        end
    end

    DebugAction("EQUIP_FAIL", "no tool for type=" .. tostring(toolType), 0.50)
    return nil
end

local function EquipName(toolName)
    local __dbgStart = DebugFunction("EquipName",tostring(toolName))
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
local InventoryLastAttemptAt = 0

local function GetInventory(forceRefresh)
    local __dbgStart = DebugFunction("GetInventory","force=" .. tostring(forceRefresh))
    local now = os.clock()
    local ttl = math.max(tonumber(Configs.InventoryCacheTTL) or 1.0, 0.25)

    if not forceRefresh and InventoryCacheAt > 0 and (now - InventoryCacheAt) <= ttl then
        return InventoryCache
    end

    -- If the server temporarily returns nil/non-table, don't hammer getInventory every frame.
    if not forceRefresh and InventoryLastAttemptAt > 0 and (now - InventoryLastAttemptAt) <= ttl then
        return InventoryCache
    end

    InventoryLastAttemptAt = now
    local ok, result = pcall(function()
        return DebugInvoke("getInventory")
    end)

    if ok and type(result) == "table" then
        InventoryCache = result
        InventoryCacheAt = now
    elseif ok then
        DebugLog("CACHE", "getInventory retornou " .. typeof(result) .. "; mantendo cache anterior")
    end

    return InventoryCache
end

local function InvalidateInventoryCache()
    InventoryCacheAt = 0
    InventoryLastAttemptAt = 0
end

local function CheckInv(inv)
    local __dbgStart = DebugFunction("CheckInv")
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
    local __dbgStart = DebugFunction("BringMob",a and a.Name or "nil")
    pcall(sethiddenproperty,LocalPlayer,"SimulationRadius",math.huge)
    local aname = a.Name
    local acf = a.HumanoidRootPart.CFrame
    local targets = {}
    table.insert(targets, {a, a:FindFirstChild("Head")})
    for _, v in ipairs(workspace.Enemies:GetChildren()) do
        if string.find(v.Name:lower(), aname:lower(), 1, true) and not v:FindFirstChild("BringCheck") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and (acf.Position - v.HumanoidRootPart.Position).Magnitude <= (tonumber(Configs.BringDistance) or 350) then
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
-- UI / Tobias Hub
local oldGui = game.CoreGui:FindFirstChild("TobiasHub")
if oldGui then
    oldGui:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TobiasHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = game.CoreGui

local Theme = {
    Background = Color3.fromRGB(17, 18, 24),
    Surface = Color3.fromRGB(26, 28, 36),
    Surface2 = Color3.fromRGB(35, 38, 49),
    Accent = Color3.fromRGB(121, 82, 255),
    Accent2 = Color3.fromRGB(86, 183, 255),
    Text = Color3.fromRGB(240, 241, 246),
    Muted = Color3.fromRGB(151, 155, 173),
    Good = Color3.fromRGB(77, 214, 139),
    Bad = Color3.fromRGB(245, 91, 112)
}

local function New(className, props)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        if key ~= "Parent" then
            object[key] = value
        end
    end
    if props and props.Parent then
        object.Parent = props.Parent
    end
    return object
end

local MainWindow = New("Frame", {
    Name = "MainWindow",
    Size = UDim2.fromOffset(650, 470),
    Position = UDim2.new(0.5, -325, 0.5, -235),
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    Parent = ScreenGui
})
New("UICorner", {CornerRadius = UDim.new(0, 12), Parent = MainWindow})
New("UIStroke", {Color = Color3.fromRGB(57, 61, 78), Thickness = 1, Transparency = 0.15, Parent = MainWindow})

local TopBar = New("Frame", {
    Size = UDim2.new(1, 0, 0, 54),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Parent = MainWindow
})
New("UICorner", {CornerRadius = UDim.new(0, 12), Parent = TopBar})
New("Frame", {
    Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = TopBar
})

New("TextLabel", {
    Size = UDim2.new(0, 230, 1, 0), Position = UDim2.fromOffset(18, 0),
    BackgroundTransparency = 1, Text = "TOBIAS HUB",
    Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = Theme.Text,
    TextXAlignment = Enum.TextXAlignment.Left, Parent = TopBar
})

local HotkeyHint = New("TextLabel", {
    Size = UDim2.new(0, 180, 1, 0), Position = UDim2.new(1, -220, 0, 0),
    BackgroundTransparency = 1, Text = "RightShift  •  mostrar/ocultar",
    Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.Muted,
    TextXAlignment = Enum.TextXAlignment.Right, Parent = TopBar
})

local CloseButton = New("TextButton", {
    Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -42, 0.5, -16),
    BackgroundColor3 = Theme.Surface2, Text = "×", AutoButtonColor = false,
    Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = Theme.Text, Parent = TopBar
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = CloseButton})
CloseButton.MouseButton1Click:Connect(function()
    MainWindow.Visible = false
end)

-- Dragging
local dragging = false
local dragStart
local startPosition
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = MainWindow.Position
    end
end)
TopBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        MainWindow.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end
end)

local Sidebar = New("Frame", {
    Size = UDim2.new(0, 150, 1, -54), Position = UDim2.fromOffset(0, 54),
    BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = MainWindow
})
local SidebarLayout = New("UIListLayout", {
    Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = Sidebar
})
New("UIPadding", {PaddingTop = UDim.new(0, 12), Parent = Sidebar})

local Content = New("Frame", {
    Size = UDim2.new(1, -150, 1, -54), Position = UDim2.fromOffset(150, 54),
    BackgroundTransparency = 1, Parent = MainWindow
})

local StatusBar = New("Frame", {
    Size = UDim2.new(1, -24, 0, 58), Position = UDim2.new(0, 12, 1, -70),
    BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = Content
})
New("UICorner", {CornerRadius = UDim.new(0, 9), Parent = StatusBar})

local title = New("TextLabel", {
    Size = UDim2.new(1, -20, 0, 27), Position = UDim2.fromOffset(10, 5),
    BackgroundTransparency = 1, Text = "Idling", Font = Enum.Font.GothamBold,
    TextSize = 14, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = StatusBar
})
local subtitle = New("TextLabel", {
    Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 29),
    BackgroundTransparency = 1, Text = "No Subtask", Font = Enum.Font.Gotham,
    TextSize = 12, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Parent = StatusBar
})

local DebugCheckQuestRunner
local Pages = {}
local TabButtons = {}
local CurrentTab

local function CreatePage(name)
    local page = New("ScrollingFrame", {
        Name = name,
        Size = UDim2.new(1, -24, 1, -88), Position = UDim2.fromOffset(12, 10),
        BackgroundTransparency = 1, BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Accent,
        Visible = false, Parent = Content
    })
    New("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page})
    New("UIPadding", {PaddingBottom = UDim.new(0, 10), Parent = page})
    Pages[name] = page
    return page
end

local function SelectTab(name)
    CurrentTab = name
    for tabName, page in pairs(Pages) do
        page.Visible = tabName == name
    end
    for tabName, button in pairs(TabButtons) do
        button.BackgroundColor3 = tabName == name and Theme.Accent or Theme.Surface2
        button.TextColor3 = tabName == name and Color3.new(1,1,1) or Theme.Muted
    end
end

local function AddTab(name, order)
    local button = New("TextButton", {
        Size = UDim2.new(1, -16, 0, 38), BackgroundColor3 = Theme.Surface2,
        Text = name, AutoButtonColor = false, LayoutOrder = order,
        Font = Enum.Font.GothamSemibold, TextSize = 13, TextColor3 = Theme.Muted,
        Parent = Sidebar
    })
    New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = button})
    button.MouseButton1Click:Connect(function() SelectTab(name) end)
    TabButtons[name] = button
    return CreatePage(name)
end

local function AddSection(page, text)
    return New("TextLabel", {
        Size = UDim2.new(1, -4, 0, 26), BackgroundTransparency = 1,
        Text = text, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = Theme.Accent2, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = page
    })
end

local ToggleRenderers = {}

local function AddToggle(page, label, key, description, callback)
    local row = New("Frame", {
        Size = UDim2.new(1, -4, 0, description and 58 or 46),
        BackgroundColor3 = Theme.Surface, BorderSizePixel = 0, Parent = page
    })
    New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = row})
    New("TextLabel", {
        Size = UDim2.new(1, -72, 0, 24), Position = UDim2.fromOffset(12, 6),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.GothamSemibold,
        TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row
    })
    if description then
        New("TextLabel", {
            Size = UDim2.new(1, -84, 0, 18), Position = UDim2.fromOffset(12, 30),
            BackgroundTransparency = 1, Text = description, Font = Enum.Font.Gotham,
            TextSize = 10, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left,
            TextWrapped = true, Parent = row
        })
    end

    local switch = New("TextButton", {
        Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -58, 0.5, -12),
        BackgroundColor3 = Theme.Surface2, Text = "", AutoButtonColor = false, Parent = row
    })
    New("UICorner", {CornerRadius = UDim.new(1, 0), Parent = switch})
    local knob = New("Frame", {
        Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3),
        BackgroundColor3 = Theme.Text, BorderSizePixel = 0, Parent = switch
    })
    New("UICorner", {CornerRadius = UDim.new(1, 0), Parent = knob})

    local function Render()
        local enabled = Configs[key] == true
        switch.BackgroundColor3 = enabled and Theme.Accent or Theme.Surface2
        knob.Position = enabled and UDim2.new(1, -21, 0, 3) or UDim2.fromOffset(3, 3)
    end
    ToggleRenderers[key] = Render
    switch.MouseButton1Click:Connect(function()
        Configs[key] = not Configs[key]
        DebugAction("CONFIG_TOGGLE", tostring(key) .. "=" .. tostring(Configs[key]), 0, true)
        Render()
        SaveConfigs()
        if callback then pcall(callback, Configs[key]) end
    end)
    Render()
    return row
end

local function RoundToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

local function AddSlider(page, label, key, minValue, maxValue, step, formatter)
    local row = New("Frame", {
        Size = UDim2.new(1, -4, 0, 66), BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0, Parent = page
    })
    New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = row})
    New("TextLabel", {
        Size = UDim2.new(0.7, 0, 0, 22), Position = UDim2.fromOffset(12, 7),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.GothamSemibold,
        TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row
    })
    local valueLabel = New("TextLabel", {
        Size = UDim2.new(0.3, -20, 0, 22), Position = UDim2.new(0.7, 8, 0, 7),
        BackgroundTransparency = 1, Text = "", Font = Enum.Font.GothamBold,
        TextSize = 12, TextColor3 = Theme.Accent2, TextXAlignment = Enum.TextXAlignment.Right,
        Parent = row
    })
    local bar = New("Frame", {
        Size = UDim2.new(1, -24, 0, 8), Position = UDim2.fromOffset(12, 43),
        BackgroundColor3 = Theme.Surface2, BorderSizePixel = 0, Parent = row
    })
    New("UICorner", {CornerRadius = UDim.new(1, 0), Parent = bar})
    local fill = New("Frame", {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0, Parent = bar
    })
    New("UICorner", {CornerRadius = UDim.new(1, 0), Parent = fill})
    local knob = New("Frame", {
        Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0, Parent = bar
    })
    New("UICorner", {CornerRadius = UDim.new(1, 0), Parent = knob})

    local sliding = false
    local function SetFromX(x)
        local alpha = math.clamp((x - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local value = minValue + (maxValue - minValue) * alpha
        value = RoundToStep(value, step)
        value = math.clamp(value, minValue, maxValue)
        Configs[key] = value
        fill.Size = UDim2.new((value - minValue) / (maxValue - minValue), 0, 1, 0)
        knob.Position = UDim2.new((value - minValue) / (maxValue - minValue), 0, 0.5, 0)
        valueLabel.Text = formatter and formatter(value) or tostring(value)
    end
    local function Render()
        local value = math.clamp(tonumber(Configs[key]) or minValue, minValue, maxValue)
        local alpha = (value - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = formatter and formatter(value) or tostring(value)
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = true
            SetFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            SetFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and sliding then
            sliding = false
            DebugAction("CONFIG_SLIDER", tostring(key) .. "=" .. tostring(Configs[key]), 0, true)
            SaveConfigs()
        end
    end)
    Render()
    return row
end

local function AddDropdown(page, label, key, options, callback)
    local row = New("Frame", {
        Size = UDim2.new(1, -4, 0, 50), BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0, ClipsDescendants = false, Parent = page
    })
    New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = row})
    New("TextLabel", {
        Size = UDim2.new(0.48, 0, 1, 0), Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1, Text = label, Font = Enum.Font.GothamSemibold,
        TextSize = 13, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
        Parent = row
    })
    local button = New("TextButton", {
        Size = UDim2.new(0.45, -12, 0, 32), Position = UDim2.new(0.55, 0, 0.5, -16),
        BackgroundColor3 = Theme.Surface2, Text = tostring(Configs[key]), AutoButtonColor = false,
        Font = Enum.Font.GothamSemibold, TextSize = 12, TextColor3 = Theme.Text, Parent = row
    })
    New("UICorner", {CornerRadius = UDim.new(0, 7), Parent = button})
    local index = table.find(options, Configs[key]) or 1
    button.MouseButton1Click:Connect(function()
        index = index % #options + 1
        Configs[key] = options[index]
        DebugAction("CONFIG_DROPDOWN", tostring(key) .. "=" .. tostring(Configs[key]), 0, true)
        button.Text = tostring(Configs[key])
        SaveConfigs()
        if callback then pcall(callback, Configs[key]) end
    end)
    return row
end

local function AddButton(page, label, callback, danger)
    local button = New("TextButton", {
        Size = UDim2.new(1, -4, 0, 40), BackgroundColor3 = danger and Theme.Bad or Theme.Surface2,
        Text = label, AutoButtonColor = false, Font = Enum.Font.GothamBold,
        TextSize = 13, TextColor3 = Theme.Text, Parent = page
    })
    New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = button})
    button.MouseButton1Click:Connect(function()
        DebugAction("UI_BUTTON", tostring(label), 0, true)
        task.spawn(function()
            local ok, err = pcall(callback)
            if not ok then
                warn("[Tobias/UI] " .. tostring(err))
            end
        end)
    end)
    return button
end

local MainPage = AddTab("Principal", 1)
local CombatPage = AddTab("Combate", 2)
local ItemsPage = AddTab("Itens", 3)
local ProgressPage = AddTab("Progressão", 4)
local SettingsPage = AddTab("Config", 5)
local DebugPage = AddTab("Debug", 6)

AddSection(MainPage, "FARM")
AddToggle(MainPage, "Auto Farm Level", "AutoFarmLevel", "Faz quests e elimina os mobs do nível atual.")
AddToggle(MainPage, "Skip Farm Level", "SkipFarmLevel", "Usa os atalhos de level já existentes no script.")
AddToggle(MainPage, "Auto World Progress", "AutoWorldProgress", "Executa progressão de Sea quando os requisitos forem alcançados.")
AddToggle(MainPage, "Auto Factory", "AutoFactory", "Prioriza o Core/Factory quando estiver disponível no Second Sea.")
AddToggle(MainPage, "Auto Bartilo", "AutoBartilo", "Executa automaticamente a quest do Bartilo.")
AddDropdown(MainPage, "Time", "Team", {"Pirates", "Marines"}, function(value)
    pcall(function() DebugInvoke("SetTeam", value) end)
end)

AddSection(CombatPage, "COMBATE")
AddToggle(CombatPage, "Bring Mobs", "BringMobs", "Agrupa um segundo inimigo próximo no alvo principal.")
AddToggle(CombatPage, "Auto Buso", "AutoBuso", "Ativa Buso automaticamente durante ataques.")
AddToggle(CombatPage, "Usar skill V", "AutoMeleeSkill", "Usa automaticamente V de estilos suportados quando disponível.")
AddDropdown(CombatPage, "Movimento de combate", "CombatMoveMode", {"Hybrid", "Tween", "Teleport"})
AddSlider(CombatPage, "Distância para TP no Hybrid", "CombatSnapDistance", 50, 800, 25, function(v) return string.format("%d studs", v) end)
AddSlider(CombatPage, "Velocidade do Tween", "TweenSpeed", 100, 1000, 25, function(v) return string.format("%d", v) end)
AddSlider(CombatPage, "Altura do Farm", "FarmHeight", 5, 60, 1, function(v) return string.format("%d studs", v) end)
AddSlider(CombatPage, "Distância do Bring", "BringDistance", 50, 600, 10, function(v) return string.format("%d", v) end)
AddSlider(CombatPage, "Intervalo de Ataque", "AttackDelay", 0.05, 0.50, 0.01, function(v) return string.format("%.2fs", v) end)

AddSection(ItemsPage, "FRUTAS / ITENS")
AddToggle(ItemsPage, "Pegar frutas do chão", "AutoFruitPickup", "Procura frutas no Workspace e vai até elas.")
AddToggle(ItemsPage, "Guardar frutas", "AutoStoreFruit", "Guarda automaticamente frutas encontradas quando possível.")
AddToggle(ItemsPage, "Comprar fruta aleatória", "AutoRandomFruit", "Compra uma fruta aleatória respeitando o intervalo abaixo.")
AddSlider(ItemsPage, "Intervalo fruta aleatória", "RandomFruitInterval", 10, 600, 5, function(v) return string.format("%ds", v) end)
AddToggle(ItemsPage, "Auto Saber", "Saber", "Executa a cadeia existente para obter Saber.")
AddToggle(ItemsPage, "Auto Pole", "Pole", "Tenta obter Pole quando Thunder God estiver disponível.")

AddSection(ProgressPage, "PERSONAGEM")
AddToggle(ProgressPage, "Progressão de Melee", "AutoMelee", "Compra/evolui estilos de luta suportados pelo script.")
AddToggle(ProgressPage, "Auto Stats", "AutoStats", "Distribui pontos automaticamente conforme a lógica do script.")
AddToggle(ProgressPage, "Auto Haki / habilidades", "AutoHaki", "Compra Buso, Geppo, Soru e Ken quando possível.")

AddSection(SettingsPage, "GERAL")
AddToggle(SettingsPage, "Resgatar códigos ao iniciar", "AutoRedeemCodes", "Executa a lista de códigos automaticamente ao carregar o script.")
AddToggle(SettingsPage, "Desativar Camera Shake", "DisableCameraShake", "Remove o tremor de câmera quando suportado. Reexecute para reaplicar.")

AddSection(SettingsPage, "DESEMPENHO")
AddSlider(SettingsPage, "Delay loop principal", "MainLoopDelay", 0.02, 0.50, 0.01, function(v) return string.format("%.2fs", v) end)
AddSlider(SettingsPage, "Delay utilidades", "UtilityLoopDelay", 0.10, 5.00, 0.10, function(v) return string.format("%.1fs", v) end)
AddSlider(SettingsPage, "Cooldown para iniciar quest", "QuestStartCooldown", 0.25, 3.00, 0.05, function(v) return string.format("%.2fs", v) end)
AddSlider(SettingsPage, "Tempo para confirmar quest", "QuestConfirmTimeout", 0.50, 4.00, 0.10, function(v) return string.format("%.1fs", v) end)
AddSlider(SettingsPage, "Cache de inventário", "InventoryCacheTTL", 0.25, 5.00, 0.25, function(v) return string.format("%.2fs", v) end)
AddButton(SettingsPage, "Server Hop", function()
    title.Text = "Server Hop"
    subtitle.Text = "Procurando servidor..."
    TeleportServer()
end)
AddButton(SettingsPage, "Comprar fruta agora", function()
    pcall(function() DebugInvoke("Cousin", "Buy") end)
    LastRandomFruitAttempt = os.clock()
end)
AddButton(SettingsPage, "Salvar configurações", function()
    SaveConfigs()
    subtitle.Text = "Configurações salvas"
end)
AddButton(SettingsPage, "DESLIGAR TODAS AS AUTOMAÇÕES", function()
    local keys = {
        "AutoFarmLevel", "SkipFarmLevel", "AutoWorldProgress", "AutoFactory", "AutoBartilo",
        "AutoFruitPickup", "AutoStoreFruit", "AutoRandomFruit", "AutoRedeemCodes", "AutoMelee", "AutoStats",
        "AutoHaki", "AutoBuso", "AutoMeleeSkill", "BringMobs", "Saber", "Pole"
    }
    for _, key in ipairs(keys) do
        Configs[key] = false
        if ToggleRenderers[key] then ToggleRenderers[key]() end
    end
    SaveConfigs()
    title.Text = "Automações desligadas"
    subtitle.Text = "Todos os toggles automáticos foram desativados"
end, true)


-- ======================== DEBUG TAB ========================
AddSection(DebugPage, "Diagnóstico em tempo real")
AddToggle(DebugPage, "Debug ativo", "DebugEnabled", "Registra funções, estados, remotes e erros em tempo real.")
AddToggle(DebugPage, "Rastreamento TOTAL", "DebugTraceEnabled", "Registra cada ação importante: quest, alvo, movimento, equipamento, ataque, hit, HP e remotes.")
AddToggle(DebugPage, "Verbose no console", "VerboseDebug", "Também imprime eventos detalhados no console do executor.")

local DebugSummary = New("TextLabel", {
    Size = UDim2.new(1, -4, 0, 245), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Text = "Carregando diagnóstico...", Font = Enum.Font.Code, TextSize = 11,
    TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = false, Parent = DebugPage
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = DebugSummary})
New("UIPadding", {PaddingTop = UDim.new(0, 9), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = DebugSummary})

AddSection(DebugPage, "Linha do tempo de ações")
local DebugActions = New("TextLabel", {
    Size = UDim2.new(1, -4, 0, 330), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Text = "Nenhuma ação ainda", Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = DebugPage
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = DebugActions})
New("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = DebugActions})

AddSection(DebugPage, "Ações mais registradas")
local DebugActionStats = New("TextLabel", {
    Size = UDim2.new(1, -4, 0, 155), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Text = "Nenhuma ação ainda", Font = Enum.Font.Code, TextSize = 11,
    TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, Parent = DebugPage
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = DebugActionStats})
New("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), Parent = DebugActionStats})

AddSection(DebugPage, "Funções mais chamadas")
local DebugFunctions = New("TextLabel", {
    Size = UDim2.new(1, -4, 0, 130), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Text = "Nenhuma chamada ainda", Font = Enum.Font.Code, TextSize = 11,
    TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, Parent = DebugPage
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = DebugFunctions})
New("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), Parent = DebugFunctions})

AddSection(DebugPage, "Remotes CommF_ mais chamados")
local DebugRemotes = New("TextLabel", {
    Size = UDim2.new(1, -4, 0, 130), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Text = "Nenhum remote ainda", Font = Enum.Font.Code, TextSize = 11,
    TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, Parent = DebugPage
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = DebugRemotes})
New("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), Parent = DebugRemotes})

AddSection(DebugPage, "Últimos eventos")
local DebugLogs = New("TextLabel", {
    Size = UDim2.new(1, -4, 0, 220), BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Text = "Sem eventos", Font = Enum.Font.Code, TextSize = 10,
    TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = DebugPage
})
New("UICorner", {CornerRadius = UDim.new(0, 8), Parent = DebugLogs})
New("UIPadding", {PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = DebugLogs})

AddSection(DebugPage, "Testes")
AddButton(DebugPage, "TESTAR INVENTÁRIO", function()
    local ok, result = pcall(function() return GetInventory(true) end)
    if ok and type(result) == "table" then
        DebugLog("TEST", "Inventário OK | " .. tostring(#result) .. " entradas", true)
    else
        DebugError("TestInventory", result or "resultado inválido")
    end
end)
AddButton(DebugPage, "TESTAR CHECK QUEST", function()
    local ok, err = pcall(function()
        if not DebugCheckQuestRunner then error("CheckQuest ainda não inicializado") end
        return DebugCheckQuestRunner()
    end)
    if ok then DebugLog("TEST", "CheckQuest OK | " .. tostring(DebugState.LastQuest), true)
    else DebugError("TestCheckQuest", err) end
end)
AddButton(DebugPage, "TESTAR TWEEN CURTO", function()
    local hrp = GetHRP()
    if not hrp then return DebugError("TestTween", "HumanoidRootPart ausente") end
    local ok, err = pcall(function() Tween(hrp.CFrame * CFrame.new(0, 8, 0), math.min(tonumber(Configs.TweenSpeed) or 350, 350)) end)
    if ok then DebugLog("TEST", "Tween curto iniciado", true) else DebugError("TestTween", err) end
end)
AddButton(DebugPage, "LIMPAR LOG", function()
    table.clear(DebugState.Logs)
    table.clear(DebugState.ActionHistory)
    table.clear(DebugState.ActionCounts)
    DebugState.ActionSeq = 0
    DebugState.ActionCount = 0
    DebugState.LastError = "NONE"
    DebugState.ErrorCount = 0
    DebugLog("DEBUG", "Log limpo", true)
end)
AddButton(DebugPage, "COPIAR SÓ LINHA DO TEMPO", function()
    local timeline = table.concat({
        "=== TOBIAS ACTION TIMELINE ===",
        "State: " .. tostring(DebugState.CurrentState),
        "Config: AutoFarm=" .. tostring(Configs.AutoFarmLevel) .. " SkipFarm=" .. tostring(Configs.SkipFarmLevel) .. " Move=" .. tostring(Configs.CombatMoveMode),
        "",
        table.concat(DebugState.ActionHistory, "\n")
    }, "\n")
    if setclipboard then
        setclipboard(timeline)
        DebugLog("DEBUG", "Linha do tempo copiada", true)
    else
        warn(timeline)
    end
end)
AddButton(DebugPage, "COPIAR RELATÓRIO", function()
    local report = table.concat({
        "=== TOBIAS DEBUG REPORT ===",
        "State: " .. tostring(DebugState.CurrentState),
        "CurrentAction: #" .. tostring(DebugState.ActionSeq) .. " " .. tostring(DebugState.CurrentAction) .. " | " .. tostring(DebugState.LastActionDetails),
        "CurrentFunction: " .. tostring(DebugState.CurrentFunction),
        "LastError: " .. tostring(DebugState.LastError),
        "LastRemote: " .. tostring(DebugState.LastRemote),
        "RemoteArgs: " .. tostring(DebugState.LastRemoteArgs),
        "RemoteResult: " .. tostring(DebugState.LastRemoteResult),
        "StartQuestResult: " .. tostring(DebugState.RemoteLastResult.StartQuest or "-"),
        "GetInventoryResult: " .. tostring(DebugState.RemoteLastResult.getInventory or "-"),
        "Target: " .. tostring(DebugState.LastTarget) .. " " .. tostring(DebugState.LastTargetHP),
        "Quest: " .. tostring(DebugState.LastQuest),
        "Tween: " .. tostring(DebugState.LastTween),
        "Movement: " .. tostring(DebugState.LastMoveMode) .. " | Distance=" .. string.format("%.0f", DebugState.LastMoveDistance or 0),
        string.format("Config: AutoFarm=%s SkipFarm=%s MoveMode=%s Bring=%s TweenSpeed=%s SnapDist=%s FarmHeight=%s AttackDelay=%s", tostring(Configs.AutoFarmLevel), tostring(Configs.SkipFarmLevel), tostring(Configs.CombatMoveMode), tostring(Configs.BringMobs), tostring(Configs.TweenSpeed), tostring(Configs.CombatSnapDistance), tostring(Configs.FarmHeight), tostring(Configs.AttackDelay)),
        string.format("Counters: actions=%d attacks=%d/%d hits=%d combat=%d/%d moves=%d equips=%d/%d quests=%d/%d hpEvents=%d", DebugState.ActionCount, DebugState.AttackSuccess, DebugState.AttackAttempts, DebugState.RegisterHitCount, DebugState.CombatEntries, DebugState.CombatExits, DebugState.MovementActions, DebugState.EquipSuccess, DebugState.EquipAttempts, DebugState.QuestConfirmed, DebugState.QuestRequests, DebugState.TargetHpEvents),
        "\n-- TOP ACTIONS --\n" .. DebugTopActions(20),
        "\n-- ACTION TIMELINE (NEWEST FIRST) --\n" .. table.concat(DebugState.ActionHistory, "\n"),
        "\n-- TOP FUNCTIONS --\n" .. DebugTopFunctions(15),
        "\n-- TOP REMOTES --\n" .. DebugTopRemotes(15),
        "\n-- LOG --\n" .. table.concat(DebugState.Logs, "\n")
    }, "\n")
    if setclipboard then
        setclipboard(report)
        DebugLog("DEBUG", "Relatório copiado para clipboard", true)
    else
        warn(report)
        DebugLog("DEBUG", "setclipboard indisponível; relatório enviado ao console", true)
    end
end)

-- Atualizador visual do painel de debug.
task.spawn(function()
    while ScreenGui.Parent do
        if Configs.DebugEnabled and CurrentTab == "Debug" then
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local hrp = character and character:FindFirstChild("HumanoidRootPart")
            local data = LocalPlayer:FindFirstChild("Data")
            local levelValue = data and data:FindFirstChild("Level")
            local questGui = LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("Main")
            questGui = questGui and questGui:FindFirstChild("Quest")

            DebugSummary.Text = table.concat({
                "STATE       : " .. tostring(DebugState.CurrentState),
                "ACTION      : #" .. tostring(DebugState.ActionSeq) .. " " .. tostring(DebugState.CurrentAction),
                "DETAIL      : " .. tostring(DebugState.LastActionDetails),
                "FUNCTION    : " .. tostring(DebugState.CurrentFunction),
                "ERRORS      : " .. tostring(DebugState.ErrorCount) .. " | " .. tostring(DebugState.LastError),
                "WORLD/LEVEL : " .. tostring(placeid == 2753915549 and 1 or placeid == 79091703265657 and 2 or placeid == 7449423635 and 3 or 0) .. " / " .. tostring(levelValue and levelValue.Value or "?"),
                "CHARACTER   : Humanoid=" .. (humanoid and "OK" or "NIL") .. " HRP=" .. (hrp and "OK" or "NIL"),
                "QUEST GUI   : " .. tostring(questGui and questGui.Visible or false),
                "QUEST       : " .. tostring(DebugState.LastQuest),
                "TARGET      : " .. tostring(DebugState.LastTarget) .. " | HP " .. tostring(DebugState.LastTargetHP),
                "TWEEN       : " .. tostring(IsTweening) .. " | Dist " .. string.format("%.0f", DebugState.LastTweenDistance or 0),
                "MOVEMENT    : " .. tostring(DebugState.LastMoveMode) .. " | TargetDist " .. string.format("%.0f", DebugState.LastMoveDistance or 0),
                "CONFIG      : AutoFarm=" .. tostring(Configs.AutoFarmLevel) .. " Skip=" .. tostring(Configs.SkipFarmLevel) .. " Move=" .. tostring(Configs.CombatMoveMode),
                "REMOTE      : " .. tostring(DebugState.LastRemote) .. " | Total " .. tostring(DebugState.RemoteCount),
                "ARGS        : " .. tostring(DebugState.LastRemoteArgs),
                "RETURN      : " .. tostring(DebugState.LastRemoteResult),
                "START QUEST : " .. tostring(DebugState.RemoteLastResult.StartQuest or "-"),
                "INV RESULT  : " .. tostring(DebugState.RemoteLastResult.getInventory or "-"),
                string.format("COUNTERS    : atk %d/%d | hit %d | combat %d/%d | move %d | equip %d/%d | quest %d/%d", DebugState.AttackSuccess, DebugState.AttackAttempts, DebugState.RegisterHitCount, DebugState.CombatEntries, DebugState.CombatExits, DebugState.MovementActions, DebugState.EquipSuccess, DebugState.EquipAttempts, DebugState.QuestConfirmed, DebugState.QuestRequests),
            }, "\n")
            local actionLines = {}
            for i = 1, math.min(18, #DebugState.ActionHistory) do actionLines[i] = DebugState.ActionHistory[i] end
            DebugActions.Text = #actionLines > 0 and table.concat(actionLines, "\n") or "Nenhuma ação ainda"
            DebugActionStats.Text = DebugTopActions(12)
            DebugFunctions.Text = DebugTopFunctions(9)
            DebugRemotes.Text = DebugTopRemotes(9)
            local visibleLogs = {}
            for i = 1, math.min(12, #DebugState.Logs) do visibleLogs[i] = DebugState.Logs[i] end
            DebugLogs.Text = #visibleLogs > 0 and table.concat(visibleLogs, "\n") or "Sem eventos"
        end
        task.wait(0.25)
    end
end)


-- BLACKBOX EVENT OBSERVERS: monitoram alterações reais do cliente, não apenas chamadas do Tobias.
task.spawn(function()
    local function bindCharacter(character)
        DebugAction("CHARACTER_ADDED", character:GetFullName(), 0, true)
        local humanoid = character:WaitForChild("Humanoid", 10)
        local hrp = character:WaitForChild("HumanoidRootPart", 10)
        if humanoid then
            DebugAction("HUMANOID_READY", string.format("hp=%.0f/%.0f", humanoid.Health, humanoid.MaxHealth), 0, true)
            humanoid.Died:Connect(function() DebugAction("PLAYER_DIED_EVENT", "Humanoid.Died", 0, true) end)
            local lastHp = humanoid.Health
            humanoid.HealthChanged:Connect(function(hp)
                if math.abs(hp - lastHp) >= 1 then
                    DebugAction("PLAYER_HP_CHANGED", string.format("%.0f -> %.0f", lastHp, hp), 0.10)
                    lastHp = hp
                end
            end)
        else
            DebugAction("HUMANOID_MISSING", "timeout", 0, true)
        end
        if hrp then DebugAction("HRP_READY", DebugSerialize(hrp.Position), 0, true) end
        character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then DebugAction("TOOL_EQUIPPED_EVENT", child.Name, 0, true) end
        end)
        character.ChildRemoved:Connect(function(child)
            if child:IsA("Tool") then DebugAction("TOOL_UNEQUIPPED_EVENT", child.Name, 0, true) end
        end)
    end
    if LocalPlayer.Character then task.spawn(bindCharacter, LocalPlayer.Character) end
    LocalPlayer.CharacterAdded:Connect(bindCharacter)
end)

task.spawn(function()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local main = playerGui:WaitForChild("Main", 20)
    local quest = main and main:WaitForChild("Quest", 20)
    if not quest then
        DebugAction("QUEST_GUI_MISSING", "Main.Quest not found", 0, true)
        return
    end
    local function getQuestText()
        local container = quest:FindFirstChild("Container")
        local qtc = container and container:FindFirstChild("QuestTitle")
        local titleObj = qtc and qtc:FindFirstChild("Title")
        return titleObj and titleObj.Text or "<no title>"
    end
    local function reportQuest(reason)
        local text = getQuestText()
        DebugState.LastQuestGuiVisible = quest.Visible
        DebugState.LastQuestGuiText = text
        DebugAction("QUEST_GUI_EVENT", reason .. " | visible=" .. tostring(quest.Visible) .. " | text=" .. text, 0, true)
    end
    reportQuest("BOUND")
    quest:GetPropertyChangedSignal("Visible"):Connect(function() reportQuest("VISIBLE_CHANGED") end)
    task.spawn(function()
        local container = quest:WaitForChild("Container", 20)
        local qtc = container and container:WaitForChild("QuestTitle", 20)
        local titleObj = qtc and qtc:WaitForChild("Title", 20)
        if titleObj then
            titleObj:GetPropertyChangedSignal("Text"):Connect(function() reportQuest("TEXT_CHANGED") end)
        end
    end)
end)


-- Observa spawn/despawn de inimigos e movimento real do personagem.
task.spawn(function()
    local enemies = workspace:WaitForChild("Enemies", 20)
    if enemies then
        enemies.ChildAdded:Connect(function(mob)
            task.defer(function()
                local hum = mob:FindFirstChild("Humanoid")
                local root = mob:FindFirstChild("HumanoidRootPart")
                DebugAction("ENEMY_SPAWN", tostring(mob.Name) .. " | hp=" .. tostring(hum and hum.Health or "?") .. " | pos=" .. tostring(root and DebugSerialize(root.Position) or "?"), 0, true)
            end)
        end)
        enemies.ChildRemoved:Connect(function(mob)
            DebugAction("ENEMY_DESPAWN", tostring(mob.Name), 0, true)
        end)
    else
        DebugAction("ENEMIES_FOLDER_MISSING", "workspace.Enemies timeout", 0, true)
    end
end)

task.spawn(function()
    local lastPos
    local lastSample = 0
    while ScreenGui.Parent do
        if Configs.DebugTraceEnabled then
            local hrp = GetHRP()
            if hrp then
                local pos = hrp.Position
                if lastPos then
                    local moved = (pos - lastPos).Magnitude
                    if moved >= 8 and (os.clock() - lastSample) >= 0.20 then
                        DebugAction("PLAYER_MOVED", string.format("delta=%.1f pos=%s", moved, DebugSerialize(pos)), 0.15)
                        lastSample = os.clock()
                        lastPos = pos
                    elseif moved >= 2 then
                        lastPos = pos
                    end
                else
                    lastPos = pos
                    DebugAction("PLAYER_POSITION_INIT", DebugSerialize(pos), 0, true)
                end
            else
                lastPos = nil
            end
        end
        task.wait(0.10)
    end
end)

SelectTab("Principal")

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        MainWindow.Visible = not MainWindow.Visible
        DebugAction("MENU_VISIBILITY", tostring(MainWindow.Visible), 0, true)
    end
end)

local TimeL = New("TextLabel", {
    Size = UDim2.new(1, -16, 0, 24), LayoutOrder = 99,
    BackgroundTransparency = 1, Text = "", Font = Enum.Font.Gotham,
    TextSize = 10, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Center,
    Parent = Sidebar
})
task.spawn(function()
    while ScreenGui.Parent do
        local t = os.date("*t")
        TimeL.Text = string.format("%02d:%02d:%02d  |  Lv. %s", t.hour, t.min, t.sec,
            tostring(LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Level") and LocalPlayer.Data.Level.Value or "?"))
        task.wait(1)
    end
end)

local LevelQuest
local Monster
local NameQuest
local NameCheckQuest
local CFrameQ
local CFrameMon
if Configs.DisableCameraShake and (not identifyexecutor or identifyexecutor() ~= "Solara") then
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
    local __dbgStart = DebugFunction("CheckQuest")
    DebugSetState("CHECKING_QUEST")
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
    DebugState.LastQuest = string.format("%s | LvQuest %s | Mob %s", tostring(NameQuest), tostring(LevelQuest), tostring(Monster))
    if DebugState.LastQuestSelection ~= DebugState.LastQuest then
        DebugState.LastQuestSelection = DebugState.LastQuest
        DebugAction("QUEST_SELECTED", DebugState.LastQuest)
    end
end
DebugCheckQuestRunner = CheckQuest
task.spawn(function()
    if not Configs.AutoRedeemCodes then return end
	local codes = {"BANEXPLOIT", "NOMOREHACKS", "WildDares", "BossBuild", "GetPranked", "EARN_FRUITS", "Sub2UncleKizaru", "FIGHT4FRUIT", "kittgaming", "TRIPLEABUSE", "Sub2CaptainMaui", "Sub2Fer999", "Enyu_is_Pro", "Magicbus", "JCWK", "Starcodeheo", "Bluxxy", "SUB2GAMERROBOT_EXP1", "Sub2NoobMaster123", "Sub2Daigrock", "Axiore", "TantaiGaming", "StrawHatMaine", "Sub2OfficialNoobie", "TheGreatAce", "SEATROLLIN", "24NOADMIN", "ADMIN_TROLL", "NEWTROLL", "SECRET_ADMIN", "staffbattle", "NOEXPLOIT", "NOOB2ADMIN", "CODESLIDE", "fruitconcepts"}
	for _, v in ipairs(codes) do
		ReplicatedStorage.Remotes.Redeem:InvokeServer(v)
	end
end)
local function GetNearestMob(originMob, maxDistance)
    local __dbgStart = DebugFunction("GetNearestMob",originMob and originMob.Name or "nil")
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

local function MoveToCombatTarget(myHRP, targetHRP, currentTween)
    if not myHRP or not targetHRP then
        DebugAction("MOVE_ABORT", "missing playerHRP/targetHRP")
        return currentTween, false
    end

    local farmHeight = tonumber(Configs.FarmHeight) or 30
    local desired = targetHRP.CFrame
        * CFrame.new(0, farmHeight, 0)
        * CFrame.Angles(0, math.rad(AttackRotation), 0)

    local distance = (myHRP.Position - targetHRP.Position).Magnitude
    local mode = tostring(Configs.CombatMoveMode or "Hybrid")
    local snapDistance = math.max(tonumber(Configs.CombatSnapDistance) or 300, 25)

    DebugState.LastMoveMode = mode
    DebugState.LastMoveDistance = distance

    local shouldTeleport = mode == "Teleport" or (mode == "Hybrid" and distance <= snapDistance)

    if shouldTeleport then
        if currentTween then
            CancelActiveTween("combat teleport requested")
            currentTween = nil
        end
        DebugSetState("COMBAT_TELEPORT")
        DebugState.MovementActions += 1
        local before = myHRP.Position
        DebugAction("TELEPORT_ATTEMPT", string.format("mode=%s dist=%.1f from=%s to=%s", mode, distance, DebugSerialize(before), DebugSerialize(desired.Position)), 0.15)
        myHRP.CFrame = desired
        task.wait()
        local after = myHRP.Position
        local errorDist = (after - desired.Position).Magnitude
        DebugAction("TELEPORT_RESULT", string.format("after=%s error=%.1f", DebugSerialize(after), errorDist), 0.15)
        return nil, errorDist <= math.max(15, farmHeight + 10)
    end

    DebugSetState("COMBAT_TWEEN")
    if not currentTween or currentTween.PlaybackState ~= Enum.PlaybackState.Playing then
        DebugAction("COMBAT_MOVE_TWEEN", string.format("mode=%s dist=%.1f", mode, distance), 0.15)
        currentTween = Tween(desired, tonumber(Configs.TweenSpeed) or 350)
    else
        DebugAction("COMBAT_TWEEN_ACTIVE", string.format("dist=%.1f", distance), 0.50)
    end
    return currentTween, false
end

local function SmartMoveAndAttack(mainMob, QuestTitle, Quest, IsCheckQuest, CustomName)
    local __dbgStart = DebugFunction("SmartMoveAndAttack",mainMob and mainMob.Name or "nil")
    DebugSetState("SMART_COMBAT")
    DebugState.LastTarget = mainMob and mainMob.Name or "NONE"
    DebugState.CombatEntries += 1
    DebugAction("COMBAT_ENTER", (mainMob and mainMob.Name or "nil") .. " | questCheck=" .. tostring(IsCheckQuest))
    if IsCheckQuest == nil then IsCheckQuest = true end
    CustomName = CustomName or NameCheckQuest

    pcall(sethiddenproperty, LocalPlayer, "SimulationRadius", math.huge)
    if not IsAliveMob(mainMob) then
        DebugAction("COMBAT_ABORT", "target invalid/dead")
        DebugState.CombatExits += 1
        return false
    end

    local humanoid = mainMob.Humanoid
    local hrp = mainMob.HumanoidRootPart
    DebugAction("TARGET_LOCK", string.format("%s hp=%.0f/%.0f pos=%s", mainMob.Name, humanoid.Health, humanoid.MaxHealth, DebugSerialize(hrp.Position)))
    local lastTargetHp = humanoid.Health
    local hpConn = humanoid.HealthChanged:Connect(function(newHp)
        DebugState.TargetHpEvents += 1
        DebugState.LastTargetHP = string.format("%.0f/%.0f", newHp, humanoid.MaxHealth)
        DebugAction("TARGET_HP_CHANGED", string.format("%s %.0f -> %.0f", mainMob.Name, lastTargetHp, newHp))
        lastTargetHp = newHp
    end)
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
    local inAttackPosition = false

    repeat
        task.wait(0.03)
        if not Configs.AutoFarmLevel or not IsAliveMob(mainMob) then
            break
        end

        title.Text = "Auto Farming Level | Kill " .. mainMob.Name

        if Configs.BringMobs then
            if not IsAliveMob(secondMob) then
                secondMob = GetNearestMob(mainMob, tonumber(Configs.BringDistance) or 350)
                if secondMob then
                    DebugAction("SECOND_TARGET_FOUND", secondMob.Name)
                end
            end
        else
            secondMob = nil
        end

        if Configs.BringMobs and IsAliveMob(secondMob) then
            local secondHRP = secondMob.HumanoidRootPart
            secondHRP.CFrame = hrp.CFrame
            DebugAction("BRING_MOB", secondMob.Name .. " -> " .. mainMob.Name, 0.50)
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
            DebugAction("COMBAT_EXIT_REASON", "player HRP missing")
            break
        end

        local distance = (myHRP.Position - hrp.Position).Magnitude

        if os.clock() - LastRotate >= 0.25 then
            AttackRotation = (AttackRotation + 180) % 360
            LastRotate = os.clock()
        end

        tween, inAttackPosition = MoveToCombatTarget(myHRP, hrp, tween)

        -- Em modo Tween puro, só ataca quando chegar perto. Hybrid/Teleport atacam assim que o TP é aplicado.
        local attackRange = math.max(tonumber(Configs.CombatSnapDistance) or 300, 75)
        if inAttackPosition or distance <= math.min(attackRange, 175) then
            DebugAction("ATTACK_RANGE_ENTER", string.format("dist=%.1f inPosition=%s", distance, tostring(inAttackPosition)), 0.20)
            EquipWeapon("Melee")

            -- Mantém o personagem acompanhando o alvo durante o combate.
            if tostring(Configs.CombatMoveMode or "Hybrid") ~= "Tween" then
                myHRP.CFrame = hrp.CFrame
                    * CFrame.new(0, tonumber(Configs.FarmHeight) or 30, 0)
                    * CFrame.Angles(0, math.rad(AttackRotation), 0)
            end

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
            DebugAction("COMBAT_EXIT_REASON", questMismatch and "quest mismatch" or "quest GUI hidden")
            break
        end
    until humanoid.Health <= 0

    if tween then
        CancelActiveTween("combat ended")
        tween = nil
    end
    if hpConn then hpConn:Disconnect() end
    DebugState.CombatExits += 1
    DebugAction("COMBAT_EXIT", string.format("target=%s dead=%s hp=%.0f", mainMob.Name, tostring(humanoid.Health <= 0), humanoid.Health))

    return humanoid.Health <= 0
end

local QuestRequestState = {
    Key = "",
    LastRequestAt = 0,
    PendingUntil = 0,
    LastConfirmedKey = "",
}

local function ResetQuestRequestState()
    QuestRequestState.Key = ""
    QuestRequestState.LastRequestAt = 0
    QuestRequestState.PendingUntil = 0
end

local function EnsureQuestStarted(Quest, questName, questLevel)
    local key = tostring(questName) .. ":" .. tostring(questLevel)
    local now = os.clock()
    local cooldown = math.max(tonumber(Configs.QuestStartCooldown) or 0.75, 0.25)
    local confirmTimeout = math.max(tonumber(Configs.QuestConfirmTimeout) or 1.50, cooldown)

    if Quest and Quest.Visible then
        if QuestRequestState.LastConfirmedKey ~= key then
            QuestRequestState.LastConfirmedKey = key
            DebugLog("QUEST", "Quest confirmada: " .. key)
            DebugState.QuestConfirmed += 1
            DebugAction("QUEST_CONFIRMED", key .. " | guiVisible=true")
        end
        ResetQuestRequestState()
        return true
    end

    if QuestRequestState.Key ~= key then
        QuestRequestState.Key = key
        QuestRequestState.LastRequestAt = 0
        QuestRequestState.PendingUntil = 0
    end

    if QuestRequestState.PendingUntil > now then
        DebugSetState("QUEST_REQUEST_PENDING")
        DebugAction("QUEST_WAIT_CONFIRM", key .. string.format(" | %.2fs left", QuestRequestState.PendingUntil - now), 0.50)
        return false
    end

    if QuestRequestState.LastRequestAt > 0 and (now - QuestRequestState.LastRequestAt) < cooldown then
        DebugSetState("QUEST_REQUEST_COOLDOWN")
        return false
    end

    DebugSetState("REQUESTING_QUEST")
    DebugState.QuestRequests += 1
    DebugAction("QUEST_REQUEST", key)
    QuestRequestState.LastRequestAt = now
    QuestRequestState.PendingUntil = now + confirmTimeout
    local result = DebugInvoke("StartQuest", questName, questLevel)
    DebugLog("QUEST", "StartQuest " .. key .. " => " .. DebugSerialize(result))
    DebugAction("QUEST_REQUEST_RESULT", key .. " => " .. DebugSerialize(result))
    return false
end

local function KaitunWorld1(Quest,QuestTitle,Level)
    local __dbgStart = DebugFunction("KaitunWorld1","Level=" .. tostring(Level))
	CheckInv()
	if Level >= 700 and Configs.AutoWorldProgress then
		title.Text = "Doing Second Sea Puzzle"
		local canTravel = DebugInvoke("DressrosaQuestProgress", "Dressrosa")
		local dressrosaProgress = DebugInvoke("DressrosaQuestProgress")
		if not canTravel then
			if type(dressrosaProgress) == "table" and dressrosaProgress.TalkedDetective and dressrosaProgress.UsedKey then
				if workspace.Enemies:FindFirstChild("Ice Admiral") then
					for _, v in workspace.Enemies:GetChildren() do
						if v:IsA("Model") and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") and v.Humanoid.Health > 0 and v.Name == "Ice Admiral" then
                            SmartMoveAndAttack(v, QuestTitle, Quest, false)
							title.Text = "Travel To Second Sea"
							DebugInvoke("TravelDressrosa")
						end
					end
				else
					local t0 = Tween(CFrame.new(1382.562255859375, 26.999441146850586, -1458.77783203125),350)
					t0.Completed:Wait()
				end
			elseif IsOwn("Key") then
				DebugInvoke("DressrosaQuestProgress","UseKey")
			elseif not IsOwn("Key") then
				DebugInvoke("DressrosaQuestProgress","Detective")
			end
		else
			title.Text = "Travel To Second Sea"
			DebugInvoke("TravelDressrosa")
		end
	elseif Level >= 200 and getgenv().Configs.Saber and workspace.Map.Jungle.Final.Part.CanCollide and not IsSaber then
		title.Text = "Saber Quest | Solve Puzzle"
		if not workspace.Map.Jungle.QuestPlates.Door.CanCollide then
			local proProgress = DebugInvoke("ProQuestProgress")
			if type(proProgress) == "table" and proProgress.UsedTorch then
				if DebugInvoke("ProQuestProgress","SickMan") == 0 then
					if DebugInvoke("ProQuestProgress","RichSon") == 0 then
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
					elseif DebugInvoke("ProQuestProgress","RichSon") == 1 then
						DebugInvoke("ProQuestProgress","PlaceRelic")
					else
						DebugInvoke("ProQuestProgress","RichSon")
					end
				else
					DebugInvoke("ProQuestProgress","GetCup")
					task.wait(0.2)
					EquipName("Cup")
					task.wait(0.2)
					local cup = IsOwn("Cup")
					DebugInvoke("ProQuestProgress","FillCup",cup)
					DebugInvoke("ProQuestProgress","SickMan")
				end
			elseif IsOwn("Torch") then
				DebugInvoke("ProQuestProgress","DestroyTorch")
			elseif not IsOwn("Torch") then
				DebugInvoke("ProQuestProgress","GetTorch")
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
			DebugInvoke("SetSpawnPoint")
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
			DebugInvoke("SetSpawnPoint")
		end
	elseif getgenv().Configs.SkipFarmLevel and (Level >= 0 and Level <= 24) then
        DebugAction("BRANCH_SKIP_FARM", "Level 0-24 | Dark Master", 0.50)
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
        DebugAction("BRANCH_SKIP_FARM", "Level 25-59 | Royal Squad", 0.50)
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
        DebugAction("BRANCH_NORMAL_QUEST", "quest not visible | " .. tostring(NameQuest), 0.50)
		title.Text = "Auto Farming Level | Get Quest"
		local hrp = GetHRP()
		if not hrp then
            DebugAction("QUEST_FLOW_ABORT", "player HRP missing")
            return
        end
		local distanceToQuest = (CFrameQ.Position - hrp.Position).Magnitude
        DebugAction("QUEST_MOVE_PROGRESS", string.format("quest=%s remaining=%.1f", tostring(NameQuest), distanceToQuest), 0.50)
		if distanceToQuest > 150 then
			DebugSetState("MOVING_TO_QUEST")
            DebugAction("MOVE_TO_QUEST", string.format("quest=%s dist=%.1f target=%s", tostring(NameQuest), distanceToQuest, DebugSerialize(CFrameQ)), 0.40)
			t2 = Tween(CFrameQ, tonumber(Configs.TweenSpeed) or 350)
		else
			if t2 then
                CancelActiveTween("arrived at quest NPC")
				t2 = nil
			end
            DebugAction("QUEST_NPC_SNAP", "from=" .. DebugSerialize(hrp.Position) .. " to=" .. DebugSerialize(CFrameQ.Position))
			hrp.CFrame = CFrameQ
            task.wait()
            DebugAction("QUEST_NPC_SNAP_RESULT", "actual=" .. DebugSerialize(hrp.Position))
			EnsureQuestStarted(Quest, NameQuest, LevelQuest)
		end
	elseif Quest.Visible then
        DebugAction("BRANCH_QUEST_ACTIVE", "title=" .. tostring(QuestTitle.Text), 0.50)
		ResetQuestRequestState()
		if workspace.Enemies:FindFirstChild(Monster) then
            DebugAction("TARGET_CONTAINER_FOUND", tostring(Monster), 0.30)
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if v.Name == Monster and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    local playerHrp = GetHRP()
                    local targetDist = playerHrp and (playerHrp.Position - v.HumanoidRootPart.Position).Magnitude or -1
                    DebugAction("TARGET_FOUND", string.format("%s hp=%.0f dist=%.1f pos=%s", v.Name, v.Humanoid.Health, targetDist, DebugSerialize(v.HumanoidRootPart.Position)), 0.20)
					if string.find(QuestTitle.Text, NameCheckQuest, 1, true) then
                        DebugAction("QUEST_MATCH", "title=" .. tostring(QuestTitle.Text) .. " expected=" .. tostring(NameCheckQuest), 0.30)
                        SmartMoveAndAttack(v, QuestTitle, Quest)
					else
                        DebugAction("QUEST_MISMATCH", "title=" .. tostring(QuestTitle.Text) .. " expected=" .. tostring(NameCheckQuest))
						DebugInvoke("AbandonQuest")
					end
				end
			end
		else
			title.Text = "Auto Farming Level | Wait For " .. Monster
            DebugAction("TARGET_NOT_FOUND", tostring(Monster) .. " | spawn=" .. DebugSerialize(CFrameMon), 0.60)
            local playerHrp = GetHRP()
            if not playerHrp then
                DebugAction("TARGET_WAIT_ABORT", "player HRP missing")
                return
            end
            local spawnDist = (CFrameMon.Position - playerHrp.Position).Magnitude
            DebugAction("MOB_MOVE_PROGRESS", string.format("mob=%s remaining=%.1f", tostring(Monster), spawnDist), 0.50)
			if spawnDist > 150 then
                DebugAction("MOVE_TO_MOB_SPAWN", string.format("mob=%s dist=%.1f", tostring(Monster), spawnDist), 0.40)
				t0 = Tween(CFrameMon,350)
			else
				if t0 then
                    CancelActiveTween("arrived at mob spawn")
                    t0 = nil
				end
                DebugAction("MOB_SPAWN_SNAP", "to=" .. DebugSerialize(CFrameMon.Position), 0.50)
				playerHrp.CFrame = CFrameMon
			end
		end
	end
end
local function KaitunWorld2(Quest,QuestTitle,Level)
    local __dbgStart = DebugFunction("KaitunWorld2","Level=" .. tostring(Level))
	CheckInv()
	local bartiloProgress
	if Level >= 850 then
		bartiloProgress = DebugInvoke("BartiloQuestProgress", "Bartilo")
	end
	if Configs.AutoFactory and (workspace.Enemies:FindFirstChild("Core") or ReplicatedStorage:FindFirstChild("Core")) then
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
                    DebugInvoke("AbandonQuest")
                end
            else
                DebugInvoke("StartQuest","BartiloQuest",1)
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
                DebugInvoke("SetSpawnPoint")
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
        DebugAction("BRANCH_NORMAL_QUEST", "quest not visible | " .. tostring(NameQuest), 0.50)
		title.Text = "Auto Farming Level | Get Quest"
		local hrp = GetHRP()
		if not hrp then
            DebugAction("QUEST_FLOW_ABORT", "player HRP missing")
            return
        end
		local distanceToQuest = (CFrameQ.Position - hrp.Position).Magnitude
        DebugAction("QUEST_MOVE_PROGRESS", string.format("quest=%s remaining=%.1f", tostring(NameQuest), distanceToQuest), 0.50)
		if distanceToQuest > 150 then
			DebugSetState("MOVING_TO_QUEST")
            DebugAction("MOVE_TO_QUEST", string.format("quest=%s dist=%.1f target=%s", tostring(NameQuest), distanceToQuest, DebugSerialize(CFrameQ)), 0.40)
			t2 = Tween(CFrameQ, tonumber(Configs.TweenSpeed) or 350)
		else
			if t2 then
                CancelActiveTween("arrived at quest NPC")
				t2 = nil
			end
            DebugAction("QUEST_NPC_SNAP", "from=" .. DebugSerialize(hrp.Position) .. " to=" .. DebugSerialize(CFrameQ.Position))
			hrp.CFrame = CFrameQ
            task.wait()
            DebugAction("QUEST_NPC_SNAP_RESULT", "actual=" .. DebugSerialize(hrp.Position))
			EnsureQuestStarted(Quest, NameQuest, LevelQuest)
		end
	elseif Quest.Visible then
        DebugAction("BRANCH_QUEST_ACTIVE", "title=" .. tostring(QuestTitle.Text), 0.50)
		ResetQuestRequestState()
		if workspace.Enemies:FindFirstChild(Monster) then
            DebugAction("TARGET_CONTAINER_FOUND", tostring(Monster), 0.30)
			for _,v in pairs(workspace.Enemies:GetChildren()) do
				if v.Name == Monster and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    local playerHrp = GetHRP()
                    local targetDist = playerHrp and (playerHrp.Position - v.HumanoidRootPart.Position).Magnitude or -1
                    DebugAction("TARGET_FOUND", string.format("%s hp=%.0f dist=%.1f pos=%s", v.Name, v.Humanoid.Health, targetDist, DebugSerialize(v.HumanoidRootPart.Position)), 0.20)
					if string.find(QuestTitle.Text, NameCheckQuest, 1, true) then
                        DebugAction("QUEST_MATCH", "title=" .. tostring(QuestTitle.Text) .. " expected=" .. tostring(NameCheckQuest), 0.30)
                        SmartMoveAndAttack(v, QuestTitle, Quest)
					else
                        DebugAction("QUEST_MISMATCH", "title=" .. tostring(QuestTitle.Text) .. " expected=" .. tostring(NameCheckQuest))
						DebugInvoke("AbandonQuest")
					end
				end
			end
		else
			title.Text = "Auto Farming Level | Wait For " .. Monster
            DebugAction("TARGET_NOT_FOUND", tostring(Monster) .. " | spawn=" .. DebugSerialize(CFrameMon), 0.60)
            local playerHrp = GetHRP()
            if not playerHrp then
                DebugAction("TARGET_WAIT_ABORT", "player HRP missing")
                return
            end
            local spawnDist = (CFrameMon.Position - playerHrp.Position).Magnitude
            DebugAction("MOB_MOVE_PROGRESS", string.format("mob=%s remaining=%.1f", tostring(Monster), spawnDist), 0.50)
			if spawnDist > 150 then
                DebugAction("MOVE_TO_MOB_SPAWN", string.format("mob=%s dist=%.1f", tostring(Monster), spawnDist), 0.40)
				t0 = Tween(CFrameMon,350)
			else
				if t0 then
                    CancelActiveTween("arrived at mob spawn")
                    t0 = nil
				end
                DebugAction("MOB_SPAWN_SNAP", "to=" .. DebugSerialize(CFrameMon.Position), 0.50)
				playerHrp.CFrame = CFrameMon
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
        return DebugInvoke(data.BuyID, true)
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
        DebugInvoke("StoreFruit", originalName, tool)
    end)

    if ok then
        inventoryNames[originalName] = true
        InvalidateInventoryCache()
    end

    return ok
end

local function HandleFruits()
    local __dbgStart = DebugFunction("HandleFruits")
    local inv = GetInventory(false)
    local inventoryNames = BuildInventoryNameSet(inv)
    local hrp = GetHRP()
    if not hrp then return end

    if Configs.AutoFruitPickup then
        for _, fruit in ipairs(workspace:GetChildren()) do
            if fruit:IsA("Model") and string.find(fruit.Name:lower(), "fruit", 1, true) then
                local handle = fruit:FindFirstChild("Handle")
                local originalName = fruit:GetAttribute("OriginalName")

                if handle and originalName and not inventoryNames[originalName] then
                    title.Text = "Get " .. fruit.Name
                    local distance = (handle.Position - hrp.Position).Magnitude

                    if distance > 150 then
                        local tween = Tween(handle.CFrame, Configs.TweenSpeed)
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
    end

    if Configs.AutoStoreFruit then
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
end

local function GetCurrentMelee()
    local __dbgStart = DebugFunction("GetCurrentMelee")
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
    local __dbgStart = DebugFunction("GetMeleeMastery",tostring(styleName))
    local tool = IsOwn(styleName)
    local level = tool and tool:FindFirstChild("Level")
    return level and tonumber(level.Value) or 0
end

local function MoveToMeleeNPC(data)
    local __dbgStart = DebugFunction("MoveToMeleeNPC",data and data.Name or "nil")
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
    local __dbgStart = DebugFunction("HasResourcesForMelee",data and data.Name or "nil")
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
    local __dbgStart = DebugFunction("ProgressMelee")
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
            return DebugInvoke(data.BuyID, true)
        end)

        if (ok and status == 1) or HasResourcesForMelee(data) then
            title.Text = "Get " .. styleName
            MoveToMeleeNPC(data)

            pcall(function()
                DebugInvoke(data.BuyID)
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
    local __dbgStart = DebugFunction("RunMainCycle")
    DebugSetState("MAIN_CYCLE")
    DieWait()

    if Configs.AutoFruitPickup or Configs.AutoStoreFruit then
        HandleFruits()
    end

    if Configs.AutoMelee then
        ProgressMelee()
    end

    if not Configs.AutoFarmLevel then
        DebugAction("AUTO_FARM_DISABLED", "main cycle idle", 1.0)
        if not Configs.AutoMelee and not Configs.AutoFruitPickup and not Configs.AutoStoreFruit then
            title.Text = "Idling"
            subtitle.Text = "Ative uma automação no menu"
        end
        return
    end

    DebugAction("AUTO_FARM_CYCLE", "level=" .. tostring(LocalPlayer.Data.Level.Value), 0.50)
    CheckQuest()

    local mainGui = LocalPlayer.PlayerGui:FindFirstChild("Main")
    local Quest = mainGui and mainGui:FindFirstChild("Quest")
    local container = Quest and Quest:FindFirstChild("Container")
    local questTitleContainer = container and container:FindFirstChild("QuestTitle")
    local QuestTitle = questTitleContainer and questTitleContainer:FindFirstChild("Title")
    if not Quest or not QuestTitle then
        DebugAction("QUEST_GUI_NOT_READY", "Quest=" .. tostring(Quest ~= nil) .. " Title=" .. tostring(QuestTitle ~= nil), 0.50)
        return
    end

    local CurLevel = LocalPlayer.Data.Level.Value

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
    while task.wait(math.max(tonumber(Configs.MainLoopDelay) or 0.05, 0.02)) do
        local ok, err = pcall(RunMainCycle)
        if not ok then
            subtitle.Text = "Recovering from runtime error"
            DebugError("MainLoop", err)
            warn("[Kaitun/Main] " .. tostring(err))
            task.wait(0.5)
        end
    end
end)

LastRandomFruitAttempt = LastRandomFruitAttempt or 0

local function SpendStatPoints()
    local __dbgStart = DebugFunction("SpendStatPoints")
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
        DebugInvoke("AddPoint", "Melee", addMelee)
        pointsValue -= addMelee
    end

    local addDefense = math.max(0, math.min(pointsValue, targetDefense - defense))
    if addDefense > 0 then
        DebugInvoke("AddPoint", "Defense", addDefense)
        pointsValue -= addDefense
    end

    if pointsValue > 0 and melee >= MaxLevel and defense >= MaxLevel then
        local targetSword = math.max(0, math.min(MaxLevel, level * 3 - MaxLevel * 2))
        local addSword = math.max(0, math.min(pointsValue, targetSword - sword))
        if addSword > 0 then
            DebugInvoke("AddPoint", "Sword", addSword)
        end
    end
end

local function RunUtilityCycle()
    local __dbgStart = DebugFunction("RunUtilityCycle")
    local character = LocalPlayer.Character
    if not character then return end

    if Configs.AutoStats then
        SpendStatPoints()
    end

    if Configs.AutoHaki then
        if not CollectionService:HasTag(character, "Buso") and LocalPlayer.Data.Beli.Value >= 25000 then
            DebugInvoke("BuyHaki", "Buso")
        end
        if not CollectionService:HasTag(character, "Geppo") and LocalPlayer.Data.Beli.Value >= 10000 then
            DebugInvoke("BuyHaki", "Geppo")
        end
        if not CollectionService:HasTag(character, "Soru") and LocalPlayer.Data.Beli.Value >= 100000 then
            DebugInvoke("BuyHaki", "Soru")
        end
        if not CollectionService:HasTag(character, "Ken") and World1 and LocalPlayer.Data.Beli.Value >= 750000 then
            DebugInvoke("KenTalk", "Buy")
        end
    end

    if Configs.AutoRandomFruit and os.clock() - LastRandomFruitAttempt >= (tonumber(Configs.RandomFruitInterval) or 60) then
        LastRandomFruitAttempt = os.clock()
        DebugInvoke("Cousin", "Buy")
    end
end

task.spawn(function()
    while task.wait(math.max(tonumber(Configs.UtilityLoopDelay) or 1, 0.1)) do
        local ok, err = pcall(RunUtilityCycle)
        if not ok then
            DebugError("UtilityLoop", err)
            warn("[Kaitun/Utility] " .. tostring(err))
        end
    end
end)


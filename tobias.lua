--[[
    TOBIAS GAME SCANNER v1
    Objetivo: mapear tudo que o CLIENTE do Roblox consegue enxergar.
    Nao chama RemoteEvents/RemoteFunctions, nao executa ModuleScripts e nao altera o jogo.

    Saida:
      1) copia para clipboard se setclipboard existir
      2) salva em tobias_game_scan.txt se writefile existir
      3) imprime no console como fallback
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local CONFIG = {
    ScanFullWorkspaceTree = false, -- true = MUITO mais texto
    ScanReplicatedStorageTree = true,
    ScanReplicatedFirstTree = true,
    ScanPlayerGuiTree = true,
    ScanBackpackTree = true,
    ScanCharacterTree = true,

    IncludeAttributes = true,
    IncludeValueObjects = true,
    IncludeGuiText = true,

    MaxTreeDepth = 8,
    MaxChildrenPerNode = 250,
    MaxOutputChars = 1800000, -- protecao contra relatorios gigantes
}

local lines = {}
local truncated = false

local function safe(fn, fallback)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return fallback
end

local function add(text)
    if truncated then
        return
    end

    text = tostring(text or "")
    local current = 0
    for _, line in ipairs(lines) do
        current += #line + 1
    end

    if current + #text + 1 > CONFIG.MaxOutputChars then
        table.insert(lines, "[SCAN TRUNCATED] Limite de saida atingido.")
        truncated = true
        return
    end

    table.insert(lines, text)
end

local function fullPath(obj)
    return safe(function()
        return obj:GetFullName()
    end, tostring(obj))
end

local function formatVector3(v)
    return string.format("Vector3(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

local function formatCFrame(cf)
    local p = cf.Position
    return string.format("CFrame(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
end

local function formatValue(value)
    local t = typeof(value)

    if t == "string" then
        local s = value:gsub("\n", "\\n")
        if #s > 200 then
            s = s:sub(1, 200) .. "..."
        end
        return '"' .. s .. '"'
    elseif t == "Vector3" then
        return formatVector3(value)
    elseif t == "CFrame" then
        return formatCFrame(value)
    elseif t == "Color3" then
        return string.format("Color3(%.3f, %.3f, %.3f)", value.R, value.G, value.B)
    elseif t == "Instance" then
        return fullPath(value)
    else
        return tostring(value)
    end
end

local function getAttributesString(obj)
    if not CONFIG.IncludeAttributes then
        return ""
    end

    local attrs = safe(function()
        return obj:GetAttributes()
    end, {})

    local parts = {}
    for k, v in pairs(attrs) do
        table.insert(parts, tostring(k) .. "=" .. formatValue(v))
    end
    table.sort(parts)

    if #parts == 0 then
        return ""
    end

    return " attrs={" .. table.concat(parts, ", ") .. "}"
end

local VALUE_CLASSES = {
    BoolValue = true,
    IntValue = true,
    NumberValue = true,
    StringValue = true,
    ObjectValue = true,
    Vector3Value = true,
    CFrameValue = true,
    Color3Value = true,
}

local function getExtra(obj)
    local extras = {}

    if CONFIG.IncludeValueObjects and VALUE_CLASSES[obj.ClassName] then
        local value = safe(function()
            return obj.Value
        end, "<error>")
        table.insert(extras, "value=" .. formatValue(value))
    end

    if obj:IsA("BasePart") then
        table.insert(extras, "pos=" .. formatVector3(obj.Position))
        table.insert(extras, "size=" .. formatVector3(obj.Size))
    end

    if obj:IsA("Humanoid") then
        table.insert(extras, string.format(
            "hp=%.1f/%.1f walk=%.1f jump=%.1f",
            obj.Health,
            obj.MaxHealth,
            obj.WalkSpeed,
            obj.JumpPower
        ))
    end

    if obj:IsA("Tool") then
        table.insert(extras, "tooltip=" .. formatValue(obj.ToolTip))
    end

    if CONFIG.IncludeGuiText and (
        obj:IsA("TextLabel")
        or obj:IsA("TextButton")
        or obj:IsA("TextBox")
    ) then
        table.insert(extras, "text=" .. formatValue(obj.Text))
        table.insert(extras, "visible=" .. tostring(obj.Visible))
    end

    if obj:IsA("ScreenGui") then
        table.insert(extras, "enabled=" .. tostring(obj.Enabled))
    end

    if obj:IsA("GuiObject") then
        table.insert(extras, "visible=" .. tostring(obj.Visible))
    end

    if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
        table.insert(extras, "REMOTE")
    end

    if obj:IsA("ModuleScript") then
        table.insert(extras, "MODULE")
    end

    if obj:IsA("ProximityPrompt") then
        table.insert(extras, "action=" .. formatValue(obj.ActionText))
        table.insert(extras, "object=" .. formatValue(obj.ObjectText))
    end

    if #extras == 0 then
        return ""
    end

    return " [" .. table.concat(extras, " | ") .. "]"
end

local function scanTree(root, label)
    add("")
    add("============================================================")
    add("TREE: " .. label)
    add("ROOT: " .. fullPath(root))
    add("============================================================")

    local function visit(obj, depth)
        if depth > CONFIG.MaxTreeDepth then
            return
        end

        local indent = string.rep("  ", depth)
        add(
            indent
            .. "- "
            .. obj.Name
            .. " <"
            .. obj.ClassName
            .. ">"
            .. getExtra(obj)
            .. getAttributesString(obj)
        )

        local children = safe(function()
            return obj:GetChildren()
        end, {})

        if #children > CONFIG.MaxChildrenPerNode then
            add(indent .. "  [children truncated: " .. tostring(#children) .. "]")
        end

        local max = math.min(#children, CONFIG.MaxChildrenPerNode)
        for i = 1, max do
            visit(children[i], depth + 1)
        end
    end

    visit(root, 0)
end

local function collectByClass(classes, title)
    add("")
    add("============================================================")
    add(title)
    add("============================================================")

    local count = 0
    for _, obj in ipairs(game:GetDescendants()) do
        if classes[obj.ClassName] then
            count += 1
            add(
                string.format(
                    "%04d | %s <%s>%s%s",
                    count,
                    fullPath(obj),
                    obj.ClassName,
                    getExtra(obj),
                    getAttributesString(obj)
                )
            )
        end
    end

    add("TOTAL: " .. count)
end

local function scanPlayerData()
    add("")
    add("============================================================")
    add("LOCAL PLAYER")
    add("============================================================")

    add("Name: " .. tostring(LocalPlayer.Name))
    add("UserId: " .. tostring(LocalPlayer.UserId))
    add("Team: " .. tostring(LocalPlayer.Team))
    add("Neutral: " .. tostring(LocalPlayer.Neutral))

    local character = LocalPlayer.Character
    if character then
        add("Character: " .. fullPath(character))
        local hrp = character:FindFirstChild("HumanoidRootPart")
        local hum = character:FindFirstChildOfClass("Humanoid")

        if hrp then
            add("CharacterPosition: " .. formatVector3(hrp.Position))
        end

        if hum then
            add(string.format("Humanoid: %.1f/%.1f", hum.Health, hum.MaxHealth))
        end
    else
        add("Character: NONE")
    end

    add("")
    add("-- PLAYER CHILDREN / DATA CANDIDATES --")

    for _, obj in ipairs(LocalPlayer:GetDescendants()) do
        if VALUE_CLASSES[obj.ClassName] then
            add(fullPath(obj) .. " <" .. obj.ClassName .. "> = " .. formatValue(obj.Value))
        end
    end

    local attrs = safe(function()
        return LocalPlayer:GetAttributes()
    end, {})

    add("")
    add("-- PLAYER ATTRIBUTES --")
    for k, v in pairs(attrs) do
        add(tostring(k) .. " = " .. formatValue(v))
    end
end

local function scanEnemies()
    add("")
    add("============================================================")
    add("ENEMY / HUMANOID MODELS")
    add("============================================================")

    local count = 0

    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") then
            local hum = obj:FindFirstChildOfClass("Humanoid")
            local hrp = obj:FindFirstChild("HumanoidRootPart")

            if hum then
                count += 1
                local pos = hrp and formatVector3(hrp.Position) or "NO_HRP"
                add(string.format(
                    "%04d | %s | hp=%.1f/%.1f | pos=%s",
                    count,
                    fullPath(obj),
                    hum.Health,
                    hum.MaxHealth,
                    pos
                ))
            end
        end
    end

    add("TOTAL HUMANOID MODELS: " .. count)
end

local function scanQuestCandidates()
    add("")
    add("============================================================")
    add("QUEST CANDIDATES")
    add("============================================================")

    local keywords = {
        "quest",
        "mission",
        "task",
        "objective",
        "npc",
        "enemy",
        "monster",
        "level",
    }

    local seen = {}

    for _, obj in ipairs(game:GetDescendants()) do
        local nameLower = obj.Name:lower()
        local matched = false

        for _, keyword in ipairs(keywords) do
            if nameLower:find(keyword, 1, true) then
                matched = true
                break
            end
        end

        if not matched and (
            obj:IsA("TextLabel")
            or obj:IsA("TextButton")
            or obj:IsA("TextBox")
        ) then
            local textLower = safe(function()
                return obj.Text:lower()
            end, "")

            for _, keyword in ipairs(keywords) do
                if textLower:find(keyword, 1, true) then
                    matched = true
                    break
                end
            end
        end

        if matched then
            local path = fullPath(obj)
            if not seen[path] then
                seen[path] = true
                add(path .. " <" .. obj.ClassName .. ">" .. getExtra(obj) .. getAttributesString(obj))
            end
        end
    end
end

local function scanInterestingFunctionsSupport()
    add("")
    add("============================================================")
    add("EXECUTOR CAPABILITIES")
    add("============================================================")

    local candidates = {
        "setclipboard",
        "writefile",
        "readfile",
        "isfile",
        "getgenv",
        "gethui",
        "identifyexecutor",
        "getgc",
        "getreg",
        "getconnections",
        "getsenv",
        "getrenv",
        "decompile",
        "getscriptclosure",
        "hookfunction",
        "hookmetamethod",
        "getnamecallmethod",
        "sethiddenproperty",
        "firetouchinterest",
        "fireproximityprompt",
    }

    local env = (getgenv and getgenv()) or _G

    for _, name in ipairs(candidates) do
        local value = rawget(env, name)
        if value == nil then
            value = rawget(_G, name)
        end

        add(name .. " = " .. tostring(typeof(value) == "function"))
    end

    if identifyexecutor then
        local ok, result = pcall(identifyexecutor)
        if ok then
            add("Executor = " .. tostring(result))
        end
    end
end

local function scanGameMetadata()
    add("=== TOBIAS GAME SCAN ===")
    add("GeneratedAtUnix: " .. tostring(os.time()))
    add("PlaceId: " .. tostring(game.PlaceId))
    add("GameId: " .. tostring(game.GameId))
    add("JobId: " .. tostring(game.JobId))
    add("PlaceVersion: " .. tostring(game.PlaceVersion))
    add("Loaded: " .. tostring(game:IsLoaded()))
    add("")

    add("LEVEL_CAP attribute: " .. formatValue(game:GetAttribute("LEVEL_CAP")))
end

local REMOTE_CLASSES = {
    RemoteEvent = true,
    RemoteFunction = true,
    UnreliableRemoteEvent = true,
}

local SCRIPT_CLASSES = {
    ModuleScript = true,
    LocalScript = true,
}

local INTERACTION_CLASSES = {
    ProximityPrompt = true,
    ClickDetector = true,
    TouchTransmitter = true,
}

scanGameMetadata()
scanInterestingFunctionsSupport()
scanPlayerData()

collectByClass(REMOTE_CLASSES, "ALL CLIENT-VISIBLE REMOTES")
collectByClass(SCRIPT_CLASSES, "ALL CLIENT-VISIBLE MODULES / LOCAL SCRIPTS")
collectByClass(INTERACTION_CLASSES, "INTERACTIONS / PROMPTS / TOUCH")

scanQuestCandidates()
scanEnemies()

if CONFIG.ScanReplicatedStorageTree then
    scanTree(ReplicatedStorage, "ReplicatedStorage")
end

if CONFIG.ScanReplicatedFirstTree then
    scanTree(ReplicatedFirst, "ReplicatedFirst")
end

if CONFIG.ScanPlayerGuiTree then
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        scanTree(playerGui, "LocalPlayer.PlayerGui")
    else
        add("PlayerGui not found")
    end
end

if CONFIG.ScanBackpackTree then
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        scanTree(backpack, "LocalPlayer.Backpack")
    else
        add("Backpack not found")
    end
end

if CONFIG.ScanCharacterTree and LocalPlayer.Character then
    scanTree(LocalPlayer.Character, "LocalPlayer.Character")
end

if CONFIG.ScanFullWorkspaceTree then
    scanTree(Workspace, "Workspace")
end

add("")
add("============================================================")
add("END OF SCAN")
add("============================================================")
add("IMPORTANT: este relatorio contem somente objetos replicados/visiveis ao cliente.")
add("ServerScriptService/ServerStorage e codigo puramente servidor nao podem ser lidos normalmente pelo cliente.")

local report = table.concat(lines, "\n")

local copied = false
if setclipboard then
    local ok = pcall(function()
        setclipboard(report)
    end)
    copied = ok
end

local saved = false
if writefile then
    local ok = pcall(function()
        writefile("tobias_game_scan.txt", report)
    end)
    saved = ok
end

print(report)

print("")
print("=== TOBIAS GAME SCANNER FINISHED ===")
print("Clipboard: " .. tostring(copied))
print("File saved: " .. tostring(saved))
print("Characters: " .. tostring(#report))

if copied then
    print("Relatorio copiado. Cole no ChatGPT.")
elseif saved then
    print("Abra tobias_game_scan.txt e envie o arquivo.")
else
    print("Sem clipboard/writefile. Copie a saida do console.")
end

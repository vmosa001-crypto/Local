--========================================================--
-- IRON SOUL - UTILITY CORE V1  (Dungeon / Endless Tower / Pets)
--
-- Standalone logic module. It does NOT need the big farming script and it has
-- no GUI. The mobile panel lives in systems/utility_ui.lua and only talks to
-- the table returned here (also exposed as getgenv().IronSoulUtility).
--
--   Pets    : auto hatch eggs (claim + start), auto pet expedition
--             (dispatch best pet + claim, selectable slots)
--   Tower   : auto join Endless Tower, starting round, players (waits for the
--             other players before pressing Start), extra weapon, start button
--   Dungeon : pick world + difficulty from the live catalog, auto create a
--             room from the Lobby, "start now" button, preset repeat counter
--             (1 match per lobby visit), auto map + mode (normal / hell /
--             both / manual difficulty) and a follow-user join countdown
--
-- Everything is OFF by default. Settings persist in IronSoul_Utility_V1.json.
--========================================================--

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

do
    local existing = rawget(getgenv(), "IronSoulUtility")
    if type(existing) == "table" and existing.Alive then
        return existing
    end
end

local U = { Alive = true, VERSION = "V1" }
local SAVE_FILE = "IronSoul_Utility_V1.json"

--========================================================--
-- SETTINGS
--========================================================--
local DEFAULTS = {
    -- pets
    HATCH_AUTO = false,
    EXP_DISPATCH = false,
    EXP_CLAIM = false,
    EXP_SLOTS = { 2, 3, 4 },
    -- tower
    TOWER_AUTO = false,
    TOWER_START_ROUND = 0,      -- 0 = highest unlocked
    TOWER_PLAYERS = 1,
    TOWER_WAIT = 60,            -- seconds to wait for TOWER_PLAYERS before Start (0 = don't wait)
    TOWER_WEAPON = "",          -- "" = highest damage
    -- dungeon
    DUNGEON_AUTO = false,
    DUNGEON_WORLD = "World3",
    DUNGEON_DIFF = 10,
    DUNGEON_PLAYERS = 1,
    DUNGEON_DELAY = 10,
    DUNGEON_REPEAT = 0,         -- matches to run, 1 per lobby visit (0 = unlimited)
    DUNGEON_REPEAT_DONE = 0,    -- progress of the current repeat batch
    DUNGEON_SMART = false,      -- true = auto map + mode instead of the preset above
    DUNGEON_MAPS = {},          -- world ids used by the smart mode
    DUNGEON_MODE = "normal",    -- normal | hell | both | manual
    DUNGEON_SMART_DIFF = 1,     -- difficulty level used when DUNGEON_MODE = manual
    DUNGEON_CURSOR = 0,         -- round-robin position inside DUNGEON_MAPS
    -- follow user (join countdown)
    FOLLOW_ENABLE = false,
    FOLLOW_USER = "",
    FOLLOW_DELAY = 5,
    -- shared
    LOBBY_GRACE = 8,
}

local function copyValue(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for i, x in ipairs(v) do out[i] = x end
    return out
end

local S = {}
for k, v in pairs(DEFAULTS) do S[k] = copyValue(v) end

local function clampInt(v, lo, hi, default)
    v = tonumber(v)
    if not v then return default end
    return math.clamp(math.floor(v), lo, hi)
end

local function normalizeSlots(value, maxSlot)
    maxSlot = math.max(1, math.floor(tonumber(maxSlot) or 4))
    local out, seen = {}, {}
    for _, v in ipairs(type(value) == "table" and value or {}) do
        v = tonumber(v)
        if v and v == math.floor(v) and v >= 1 and v <= maxSlot and not seen[v] then
            seen[v] = true
            table.insert(out, v)
        end
    end
    table.sort(out)
    return out
end

local function normalizeStrList(value)
    local out, seen = {}, {}
    for _, v in ipairs(type(value) == "table" and value or {}) do
        if type(v) == "string" and v ~= "" and not seen[v] then
            seen[v] = true
            table.insert(out, v)
        end
    end
    return out
end

local DUNGEON_MODES = { normal = true, hell = true, both = true, manual = true }

local function normalize()
    S.TOWER_PLAYERS = clampInt(S.TOWER_PLAYERS, 1, 4, 1)
    S.TOWER_WAIT = clampInt(S.TOWER_WAIT, 0, 300, 60)
    S.DUNGEON_PLAYERS = clampInt(S.DUNGEON_PLAYERS, 1, 4, 1)
    S.DUNGEON_DIFF = clampInt(S.DUNGEON_DIFF, 1, 20, 10)
    S.DUNGEON_DELAY = clampInt(S.DUNGEON_DELAY, 3, 120, 10)
    S.DUNGEON_REPEAT = clampInt(S.DUNGEON_REPEAT, 0, 999, 0)
    S.DUNGEON_REPEAT_DONE = clampInt(S.DUNGEON_REPEAT_DONE, 0, 999, 0)
    S.DUNGEON_SMART_DIFF = clampInt(S.DUNGEON_SMART_DIFF, 1, 20, 1)
    S.DUNGEON_CURSOR = clampInt(S.DUNGEON_CURSOR, 0, 999, 0)
    S.DUNGEON_MAPS = normalizeStrList(S.DUNGEON_MAPS)
    if not DUNGEON_MODES[S.DUNGEON_MODE] then S.DUNGEON_MODE = "normal" end
    S.FOLLOW_DELAY = clampInt(S.FOLLOW_DELAY, 0, 300, 5)
    if type(S.FOLLOW_USER) ~= "string" then S.FOLLOW_USER = "" end
    S.FOLLOW_USER = (string.gsub(S.FOLLOW_USER, "^%s*(.-)%s*$", "%1"))
    S.LOBBY_GRACE = clampInt(S.LOBBY_GRACE, 0, 60, 8)
    local round = clampInt(S.TOWER_START_ROUND, 0, 196, 0)
    if round > 0 then round = math.floor((round - 1) / 5) * 5 + 1 end
    S.TOWER_START_ROUND = round
    S.EXP_SLOTS = normalizeSlots(S.EXP_SLOTS, 99)
    if type(S.TOWER_WEAPON) ~= "string" then S.TOWER_WEAPON = "" end
    if type(S.DUNGEON_WORLD) ~= "string" or S.DUNGEON_WORLD == "" then S.DUNGEON_WORLD = "World3" end
end

do
    if type(readfile) == "function" then
        local okE, exists = true, true
        if type(isfile) == "function" then okE, exists = pcall(isfile, SAVE_FILE) end
        if okE and exists then
            local ok, text = pcall(readfile, SAVE_FILE)
            if ok and type(text) == "string" and text ~= "" then
                local okJ, data = pcall(function() return HttpService:JSONDecode(text) end)
                if okJ and type(data) == "table" then
                    for k, default in pairs(DEFAULTS) do
                        if data[k] ~= nil and type(data[k]) == type(default) then
                            S[k] = copyValue(data[k])
                        end
                    end
                end
            end
        end
    end
    normalize()
end

local saveQueued = false
local function save()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.4, function()
        saveQueued = false
        if type(writefile) ~= "function" then return end
        local ok, text = pcall(function() return HttpService:JSONEncode(S) end)
        if ok then pcall(writefile, SAVE_FILE, text) end
    end)
end

local changeListeners = {}
function U.OnChange(fn) table.insert(changeListeners, fn) end

function U.Get(key) return S[key] end
function U.Set(key, value)
    if DEFAULTS[key] == nil then return false end
    S[key] = copyValue(value)
    normalize()
    -- Tower and solo-Dungeon auto-create both use the Lobby portals: never both.
    if value == true and key == "TOWER_AUTO" then S.DUNGEON_AUTO = false end
    if value == true and key == "DUNGEON_AUTO" then S.TOWER_AUTO = false end
    -- turning Auto dungeon on (or changing the repeat target) starts a fresh batch
    if (key == "DUNGEON_AUTO" and value == true) or key == "DUNGEON_REPEAT" then
        S.DUNGEON_REPEAT_DONE = 0
    end
    save()
    for _, fn in ipairs(changeListeners) do pcall(fn, key) end
    return true
end
function U.Defaults() return DEFAULTS end

--========================================================--
-- STATUS
--========================================================--
local statuses = {}
local statusListeners = {}
function U.OnStatus(fn) table.insert(statusListeners, fn) end
function U.GetStatus(key) return statuses[key] or "OFF" end

local logLines = {}
local function setStatus(key, text)
    text = tostring(text)
    if statuses[key] == text then return end
    statuses[key] = text
    table.insert(logLines, os.date("%H:%M:%S") .. "  " .. key .. ": " .. text)
    if #logLines > 60 then table.remove(logLines, 1) end
    for _, fn in ipairs(statusListeners) do pcall(fn, key, text) end
end
function U.GetLog() return logLines end

--========================================================--
-- GAME ACCESS
--========================================================--
local FrameworkModule
local function framework()
    if not FrameworkModule then
        FrameworkModule = require(ReplicatedStorage:WaitForChild("Framework", 10))
    end
    return FrameworkModule
end
local function mods() return framework().Modules end

local function waitChain(root, names)
    local cur = root
    for _, n in ipairs(names) do
        cur = cur and cur:WaitForChild(n, 6)
    end
    if not cur then error("missing " .. table.concat(names, ".")) end
    return cur
end

local cached = {}
local function remote(key, root, names)
    if not cached[key] then cached[key] = waitChain(root, names) end
    return cached[key]
end
local function gameMatchRE() return remote("match", ReplicatedStorage, { "Remotes", "GameMatchRE" }) end
local function worldRE()
    return remote("world", ReplicatedStorage, { "Framework", "Gameplay", "WorldPlace", "WorldUtil", "RemoteEvent" })
end
local function gameEnum()
    if not cached.enum then
        cached.enum = require(waitChain(ReplicatedStorage, { "Enum", "GameEnum" }))
    end
    return cached.enum
end

local function isInLobby()
    return workspace:FindFirstChild("MatchRoom") ~= nil
        and workspace:FindFirstChild("WorldEnemys") == nil
        and workspace:FindFirstChild("DragonEgg") == nil
end
U.IsInLobby = isInLobby

local function inEndlessTower()
    local w = workspace:FindFirstChild("World")
    return w ~= nil and w:FindFirstChild("Start") ~= nil
end

local readySince
local function lobbyReady()
    if not isInLobby() then readySince = nil; return false end
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then readySince = nil; return false end
    readySince = readySince or os.clock()
    return os.clock() - readySince >= S.LOBBY_GRACE
end

local function guiVisible(obj)
    if not obj or not obj.Parent then return false end
    if obj:IsA("GuiObject") and not obj.Visible then return false end
    local p = obj.Parent
    while p and p ~= game do
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("LayerCollector") and not p.Enabled then return false end
        p = p.Parent
    end
    return true
end

local function clickButton(btn)
    if not btn or not btn:IsA("GuiObject") or not guiVisible(btn) then return false end
    -- 1) fire the first signal that has real connections (no double activation)
    if type(getconnections) == "function" then
        for _, sig in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Down" }) do
            local ok, conns = pcall(getconnections, btn[sig])
            if ok and type(conns) == "table" and #conns > 0 then
                local fired = false
                for _, c in ipairs(conns) do
                    local okF = pcall(function()
                        if type(c.Fire) == "function" then c:Fire() else c.Function() end
                    end)
                    fired = fired or okF
                end
                if fired then return true end
            end
        end
    end
    -- 2) fallback: synthetic click at the button centre
    local pos = btn.AbsolutePosition + (btn.AbsoluteSize / 2)
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
    return true
end

local function mainGui(name)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    local mg = pg and pg:FindFirstChild("MainGui")
    return mg and mg:FindFirstChild(name)
end

-- Match rooms: Room1..4 = normal dungeon, Room9..10 = Endless Tower.
local function roomIsFree(room)
    local count = tonumber(room:GetAttribute("PlayersCount")) or 0
    local state = room:GetAttribute("RoomState")
    local empty = gameEnum().RoomState.Empty
    return count == 0 and (state == nil or state == empty or tostring(state) == tostring(empty))
end

local function portalPart(room)
    local touch = room and room:FindFirstChild("Touch")
    if not touch then return nil end
    if touch:IsA("BasePart") then return touch end
    for _, o in ipairs(touch:GetDescendants()) do
        if o:IsA("BasePart") then return o end
    end
end

local function findFreePortal(first, last)
    local mr = workspace:FindFirstChild("MatchRoom")
    if not mr then return nil, nil end
    for i = first, last do
        local room = mr:FindFirstChild("Room" .. tostring(i))
        if room and roomIsFree(room) then
            local part = portalPart(room)
            if part then return room, part end
        end
    end
end

local function touchPortal(room, part)
    if type(firetouchinterest) ~= "function" then return false, "firetouchinterest unavailable" end
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local root = char:FindFirstChild("HumanoidRootPart") or char:WaitForChild("HumanoidRootPart", 3)
    if not root or not part then return false, "no character/portal" end
    local dir = part.Position - root.Position
    dir = dir.Magnitude < 0.1 and root.CFrame.LookVector or dir.Unit
    root.CFrame = CFrame.new(part.Position - dir * 2 + Vector3.new(0, 1, 0))
    root.AssemblyLinearVelocity = dir * 12
    task.wait(0.05)
    root.CFrame = CFrame.new(part.Position + dir * 2 + Vector3.new(0, 1, 0))
    firetouchinterest(root, part, 0)
    task.wait(0.2)
    firetouchinterest(root, part, 1)
    return true
end

local function waitVisible(getter, timeout)
    local t0 = os.clock()
    repeat
        local g = getter()
        if g and g.Visible then return g end
        task.wait(0.1)
    until os.clock() - t0 >= timeout
    return nil
end

--========================================================--
-- PETS : HATCH
--========================================================--
local Pets = { Hatch = {}, Expedition = {} }
U.Pets = Pets

local Hatch = Pets.Hatch
local hatchWake = false

local function hatchEggs(util)
    local eggs = {}
    for uuid, data in pairs(util:GetOwnedEggs(LocalPlayer) or {}) do
        local cfg = data and util:GetEggCfg(data.EggId)
        if cfg then
            table.insert(eggs, {
                UUID = uuid, EggId = data.EggId,
                Rarity = tonumber(cfg.Rarity) or 0, Sort = tonumber(cfg.Sort) or math.huge,
            })
        end
    end
    table.sort(eggs, function(a, b)
        if a.Rarity ~= b.Rarity then return a.Rarity > b.Rarity end
        if a.Sort ~= b.Sort then return a.Sort < b.Sort end
        return tostring(a.UUID) < tostring(b.UUID)
    end)
    return eggs
end

local function hatchSignature(util)
    local parts = {}
    for _, e in ipairs(hatchEggs(util)) do table.insert(parts, "E:" .. tostring(e.UUID)) end
    for i = 1, 3 do
        local s = util:GetSlotData(LocalPlayer, i)
        table.insert(parts, "S" .. i .. ":" .. tostring(s and s.EggId or "") .. ":" .. tostring(s and s.StartTime or ""))
    end
    return table.concat(parts, "|")
end

local function waitSignatureChange(util, before, timeout)
    local deadline = os.clock() + timeout
    while U.Alive and os.clock() < deadline do
        if hatchSignature(util) ~= before then return true end
        task.wait(0.2)
    end
    return false
end

function Hatch.GetInfo()
    local m = mods()
    local util, time = m.PetsHatchUtil, m.TimeUtil
    local info = { Eggs = #hatchEggs(util), Slots = {} }
    for i = 1, 3 do
        local s = util:GetSlotData(LocalPlayer, i)
        local row = { Index = i, State = "EMPTY" }
        if s and s.EggId then
            if util:IsCompleted(s) then
                row.State = "READY"
            else
                row.State = "HATCHING"
                local cfg = util:GetEggCfg(s.EggId)
                local dur, st = cfg and tonumber(cfg.HatchDuration), tonumber(s.StartTime)
                if dur and st then row.Remaining = math.max(0, dur - (time:GetNow() - st)) end
            end
        end
        info.Slots[i] = row
    end
    return info
end

function Hatch.Step()
    local util = mods().PetsHatchUtil
    local before = hatchSignature(util)

    for i = 1, 3 do
        local s = util:GetSlotData(LocalPlayer, i)
        if s and s.EggId and util:IsCompleted(s) then
            setStatus("Hatch", "CLAIMING SLOT " .. i)
            util:Claim(LocalPlayer, i)
            if not waitSignatureChange(util, before, 3) then setStatus("Hatch", "WAITING SERVER") end
            return
        end
    end

    local empty
    for i = 1, 3 do
        local s = util:GetSlotData(LocalPlayer, i)
        if not (s and s.EggId) then empty = i; break end
    end
    if not empty then setStatus("Hatch", "HATCHING"); return end

    local egg = hatchEggs(util)[1]
    if not egg then setStatus("Hatch", "NO EGGS"); return end

    setStatus("Hatch", "HATCHING SLOT " .. empty)
    util:StartHatch(LocalPlayer, empty, egg.UUID)
    if not waitSignatureChange(util, before, 3) then setStatus("Hatch", "WAITING SERVER") end
end

--========================================================--
-- PETS : EXPEDITION
--========================================================--
local Exp = Pets.Expedition

local function expModules()
    local m = mods()
    return m.PetsExpeditionUtil, m.PetsUtil, m.PetsAffinityUtil
end

function Exp.GetInfo()
    local ex = expModules()
    local used = ex:_GetEffectiveDailyCount(LocalPlayer)
    local limit = math.max(0, math.floor(tonumber(ex.Config.DailyLimit) or 0))
    local slotCount = math.max(1, math.floor(tonumber(ex.Config.SlotCount) or 4))
    local slots = {}
    for i = 1, slotCount do
        local s = ex:GetSlotData(LocalPlayer, i)
        local state = "EMPTY"
        if s and s.UID then state = ex:IsCompleted(s) and "READY" or "AWAY" end
        slots[i] = { Index = i, State = state }
    end
    return { Remaining = math.max(0, limit - used), Limit = limit, SlotCount = slotCount, Slots = slots }
end

local function expWaitSlot(ex, slot, expectedUID)
    local deadline = os.clock() + 5
    while U.Alive and os.clock() < deadline do
        local s = ex:GetSlotData(LocalPlayer, slot)
        if expectedUID == nil then
            if not (s and s.UID) then return true end
        elseif s and s.UID == expectedUID then
            return true
        end
        task.wait(0.2)
    end
    return false
end

local function expBestPet(ex, petsUtil, affinityUtil, slot)
    local list = {}
    for _, pet in ipairs(petsUtil:GetOwnedPets(LocalPlayer) or {}) do
        if pet.UID then
            local ok, can = pcall(ex.CanDispatch, ex, LocalPlayer, slot, pet.UID)
            if ok and can then
                local def = petsUtil:GetPetInfo(pet.Id) or {}
                table.insert(list, {
                    Pet = pet,
                    Affinity = affinityUtil:GetAffinityLevel(pet.Affinity or 0),
                    Rarity = tonumber(def.Rarity) or 0,
                    Sort = tonumber(def.Sort) or math.huge,
                })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Affinity ~= b.Affinity then return a.Affinity > b.Affinity end
        if a.Rarity ~= b.Rarity then return a.Rarity > b.Rarity end
        if a.Sort ~= b.Sort then return a.Sort < b.Sort end
        return (tonumber(a.Pet.UID) or 0) < (tonumber(b.Pet.UID) or 0)
    end)
    return list[1] and list[1].Pet or nil
end

function Exp.Step()
    local ex, petsUtil, affinityUtil = expModules()
    local re = ex.RemoteEvent
    if not re then setStatus("Expedition", "UNAVAILABLE"); return end
    local slotCount = math.max(1, math.floor(tonumber(ex.Config.SlotCount) or 4))

    if S.EXP_CLAIM then
        for i = 1, slotCount do
            local s = ex:GetSlotData(LocalPlayer, i)
            if s and s.UID and ex:IsCompleted(s) then
                setStatus("Expedition", "CLAIMING SLOT " .. i)
                re:FireServer("Claim", i)
                setStatus("Expedition", expWaitSlot(ex, i, nil) and ("CLAIMED SLOT " .. i) or "CLAIM TIMEOUT")
                return
            end
        end
    end

    if not S.EXP_DISPATCH then setStatus("Expedition", "CLAIM READY"); return end

    local used = ex:_GetEffectiveDailyCount(LocalPlayer)
    local limit = math.max(0, math.floor(tonumber(ex.Config.DailyLimit) or 0))
    if limit - used <= 0 then setStatus("Expedition", "DAILY LIMIT"); return end

    local order = normalizeSlots(S.EXP_SLOTS, slotCount)
    if #order == 0 then setStatus("Expedition", "NO SLOT SELECTED"); return end

    local slot
    for _, i in ipairs(order) do
        local s = ex:GetSlotData(LocalPlayer, i)
        if not (s and s.UID) then slot = i; break end
    end
    if not slot then setStatus("Expedition", "NO EMPTY SLOT"); return end

    local pet = expBestPet(ex, petsUtil, affinityUtil, slot)
    if not pet then setStatus("Expedition", "NO ELIGIBLE PET"); return end

    setStatus("Expedition", "DISPATCHING SLOT " .. slot)
    re:FireServer("Dispatch", slot, pet.UID)
    setStatus("Expedition", expWaitSlot(ex, slot, pet.UID)
        and ("SENT - " .. math.max(0, limit - used - 1) .. "/" .. limit .. " LEFT") or "DISPATCH TIMEOUT")
end

--========================================================--
-- DUNGEON
--========================================================--
local Dungeon = {}
U.Dungeon = Dungeon

local dungeonCache, diffCache = nil, {}
local catalogFailAt, catalogFailMsg

local function translate(key, fallback)
    local text
    pcall(function() text = mods().TranslationUtil:TranslateByKey(key) end)
    if type(text) == "string" and text ~= "" and text ~= key then return text end
    return tostring(fallback or key or "Unknown")
end

-- Locate the world config without blocking the UI for long.
local function findResWorld()
    local cfg = ReplicatedStorage:FindFirstChild("Configs")
    local node = cfg and cfg:FindFirstChild("World")
    local mod = node and node:FindFirstChild("ResWorld")
    if not mod then mod = ReplicatedStorage:FindFirstChild("ResWorld", true) end
    if not mod then
        local ok, found = pcall(waitChain, ReplicatedStorage, { "Configs", "World", "ResWorld" })
        mod = ok and found or nil
    end
    if not mod then error("ResWorld config not found") end
    return mod
end

local function catalogKeys(res)
    local keys = {}
    local idx = res.__index
    if type(idx) == "table" then
        for _, k in ipairs(idx) do table.insert(keys, k) end
    end
    if #keys == 0 then
        for k, v in pairs(res) do
            if type(v) == "table" and k ~= "__index" then table.insert(keys, k) end
        end
    end
    return keys
end

local function refreshLock(e)
    pcall(function() e.Unlocked = mods().WorldUtil:IsUnlockWorld(LocalPlayer, e.WorldId, 1) == true end)
end

function Dungeon.GetCatalog(force)
    if dungeonCache and not force then
        for _, e in ipairs(dungeonCache) do refreshLock(e) end
        return dungeonCache
    end
    -- a recent failure is re-thrown instantly so the 1 s UI refresh never stalls
    if not force and catalogFailAt and os.clock() - catalogFailAt < 30 then error(catalogFailMsg) end

    local ok, result = pcall(function()
        local res = require(findResWorld())
        local out = {}
        for _, key in ipairs(catalogKeys(res)) do
            pcall(function()
                local info = res[key]
                if type(info) == "table" and info.Mode ~= "Lobby" then
                    local id = tostring(info.Id or key)
                    local e = {
                        WorldId = id, Name = translate(info.Name, id),
                        Sort = tonumber(info.Sort) or math.huge, Unlocked = false,
                    }
                    refreshLock(e)
                    table.insert(out, e)
                end
            end)
        end
        if #out == 0 then error("no dungeon found in ResWorld") end
        table.sort(out, function(a, b)
            if a.Sort == b.Sort then return a.WorldId < b.WorldId end
            return a.Sort < b.Sort
        end)
        return out
    end)
    if not ok then
        catalogFailAt, catalogFailMsg = os.clock(), tostring(result)
        error(catalogFailMsg)
    end
    catalogFailAt = nil
    dungeonCache = result
    return result
end

-- Each entry: { Level, Name, Unlocked, Hell }
function Dungeon.GetDifficulties(worldId, force)
    local cachedList = diffCache[worldId]
    if cachedList and not force then
        pcall(function()
            local wu = mods().WorldUtil
            for _, e in ipairs(cachedList) do
                e.Unlocked = wu:IsUnlockWorld(LocalPlayer, worldId, e.Level) == true
            end
        end)
        return cachedList
    end
    local m = mods()
    local worldUtil, tiers = m.WorldUtil, m.RarityTiers
    local out, seen = {}, {}

    local hellLevels, hellList = {}, {}
    local okH, hell = pcall(function() return worldUtil:GetWorldStyleList(worldId, "Hell") end)
    if okH and type(hell) == "table" then
        for _, h in ipairs(hell) do
            local lv = tonumber(h.DiffLevel)
            if lv then hellLevels[lv] = true; table.insert(hellList, lv) end
        end
    end

    local function add(level)
        level = tonumber(level)
        if not level or seen[level] then return end
        local ok, info = pcall(function() return worldUtil:GetWorldDiffInfo(worldId, level) end)
        if not ok or type(info) ~= "table" then return end
        local okN, name = pcall(function() return tiers:GetDifficultyName(info.Difficulty) end)
        if not okN or type(name) ~= "string" or not string.find(name, "%S") or tonumber(name) then return end
        seen[level] = true
        local isHell = info.Style == "Hell" or hellLevels[level] == true
        if isHell then name = "Hell (" .. name .. ")" end
        local unlocked = false
        pcall(function() unlocked = worldUtil:IsUnlockWorld(LocalPlayer, worldId, level) == true end)
        table.insert(out, { Level = level, Name = "[" .. level .. "] " .. name, Unlocked = unlocked, Hell = isHell })
    end
    for lv = 1, 10 do add(lv) end
    for _, lv in ipairs(hellList) do add(lv) end
    table.sort(out, function(a, b) return a.Level < b.Level end)
    diffCache[worldId] = out
    return out
end

local function highestUnlockedDiff(worldId, force)
    local best
    for _, e in ipairs(Dungeon.GetDifficulties(worldId, force)) do
        if e.Unlocked and (not best or e.Level > best.Level) then best = e end
    end
    return best
end

function Dungeon.SelectWorld(worldId)
    for _, e in ipairs(Dungeon.GetCatalog(true)) do
        if e.WorldId == worldId and e.Unlocked then
            local d = highestUnlockedDiff(worldId, true)
            if not d then return false end
            U.Set("DUNGEON_WORLD", worldId)
            U.Set("DUNGEON_DIFF", d.Level)
            return true
        end
    end
    return false
end

function Dungeon.SelectDifficulty(level)
    for _, e in ipairs(Dungeon.GetDifficulties(S.DUNGEON_WORLD, true)) do
        if e.Level == level and e.Unlocked then
            U.Set("DUNGEON_DIFF", level)
            return true
        end
    end
    return false
end

-- Make sure the saved world/difficulty are unlocked, else fall back.
local function validateSelection()
    local world
    for _, e in ipairs(Dungeon.GetCatalog(true)) do
        if e.WorldId == S.DUNGEON_WORLD and e.Unlocked then world = e; break end
    end
    if not world then
        for _, e in ipairs(Dungeon.GetCatalog()) do
            if e.Unlocked then world = e; break end
        end
    end
    if not world then return false end
    local diff
    for _, e in ipairs(Dungeon.GetDifficulties(world.WorldId, true)) do
        if e.Level == S.DUNGEON_DIFF and e.Unlocked then diff = e; break end
    end
    diff = diff or highestUnlockedDiff(world.WorldId)
    if not diff then return false end
    if S.DUNGEON_WORLD ~= world.WorldId then U.Set("DUNGEON_WORLD", world.WorldId) end
    if S.DUNGEON_DIFF ~= diff.Level then U.Set("DUNGEON_DIFF", diff.Level) end
    return true
end

--------------------------------------------------------------------
-- Smart mode: selected maps (round-robin) + mode -> highest difficulty
--------------------------------------------------------------------
-- normal : highest unlocked normal level      hell : highest unlocked hell level
-- both   : highest unlocked level of either   manual : highest unlocked <= DUNGEON_SMART_DIFF
local function smartLevel(worldId, force)
    local best
    for _, e in ipairs(Dungeon.GetDifficulties(worldId, force)) do
        if e.Unlocked then
            local ok
            if S.DUNGEON_MODE == "normal" then ok = not e.Hell
            elseif S.DUNGEON_MODE == "hell" then ok = e.Hell
            elseif S.DUNGEON_MODE == "manual" then ok = e.Level <= S.DUNGEON_SMART_DIFF
            else ok = true end
            if ok and (not best or e.Level > best.Level) then best = e end
        end
    end
    return best
end

-- Returns worldId, level, label, mapIndex   or   nil, nil, reason
function Dungeon.ResolveSmart(force)
    local selected = {}
    for _, id in ipairs(S.DUNGEON_MAPS) do selected[id] = true end
    local maps = {}
    for _, e in ipairs(Dungeon.GetCatalog(force)) do
        if selected[e.WorldId] and e.Unlocked then table.insert(maps, e) end
    end
    if #maps == 0 then return nil, nil, "NO UNLOCKED MAP SELECTED" end
    for step = 0, #maps - 1 do
        local idx = (S.DUNGEON_CURSOR + step) % #maps + 1
        local e = maps[idx]
        local d = smartLevel(e.WorldId, force)
        if d then return e.WorldId, d.Level, e.Name .. " " .. d.Name, idx end
    end
    return nil, nil, "NO DIFFICULTY MATCHES MODE"
end

-- Text for the panel: the map/difficulty the smart mode will enter next.
function Dungeon.GetNextTarget()
    if not S.DUNGEON_SMART then return nil end
    local ok, world, _, label = pcall(Dungeon.ResolveSmart, false)
    if not ok then return "?" end
    return label
end

--------------------------------------------------------------------
-- Repeat batch + follow-user countdown
--------------------------------------------------------------------
function Dungeon.GetRepeatInfo()
    return { Done = S.DUNGEON_REPEAT_DONE, Total = S.DUNGEON_REPEAT }
end

local followSince

local function findFollowPlayer()
    local name = string.lower(S.FOLLOW_USER)
    if name == "" then return nil end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and (string.lower(p.Name) == name or string.lower(p.DisplayName) == name) then
            return p
        end
    end
    return nil
end

function Dungeon.GetFollowInfo()
    local info = { Enabled = S.FOLLOW_ENABLE, User = S.FOLLOW_USER, Present = false, Remaining = nil }
    if not S.FOLLOW_ENABLE then return info end
    info.Present = findFollowPlayer() ~= nil
    if info.Present and followSince then
        info.Remaining = math.max(0, S.FOLLOW_DELAY - (os.clock() - followSince))
    end
    return info
end

-- true once the target user is in this server and the countdown has finished
local function followGate()
    if not S.FOLLOW_ENABLE then followSince = nil; return true end
    if S.FOLLOW_USER == "" then setStatus("Dungeon", "FOLLOW: USERNAME EMPTY"); return false end
    if not findFollowPlayer() then
        followSince = nil
        setStatus("Dungeon", "WAITING " .. S.FOLLOW_USER .. " IN SERVER")
        return false
    end
    followSince = followSince or os.clock()
    if os.clock() - followSince < S.FOLLOW_DELAY then
        setStatus("Dungeon", "JOIN COUNTDOWN")   -- seconds left are shown in the panel
        return false
    end
    return true
end

--------------------------------------------------------------------
-- Start
--------------------------------------------------------------------
local lastDungeonAt = -math.huge
local requestedAt              -- when a counted room was requested in this lobby visit
local outOfLobbySince
local REQUEST_TIMEOUT = 25

function Dungeon.ResetSession()
    requestedAt, outOfLobbySince, followSince = nil, nil, nil
end

-- force = true -> ignore the AUTO switch, repeat delay, follow gate and the
-- repeat counter ("start now").
function Dungeon.TryStart(force)
    if not force then
        if not S.DUNGEON_AUTO then return false end
        if os.clock() - lastDungeonAt < S.DUNGEON_DELAY then return false end
    end
    if not isInLobby() then
        -- a few seconds outside the lobby = the requested match really started
        outOfLobbySince = outOfLobbySince or os.clock()
        if os.clock() - outOfLobbySince >= 3 then requestedAt, followSince = nil, nil end
        setStatus("Dungeon", "NOT IN LOBBY")
        return false
    end
    outOfLobbySince = nil
    if not lobbyReady() and not force then setStatus("Dungeon", "WAITING LOBBY"); return false end

    if not force then
        -- 1 match per lobby visit
        if requestedAt then
            if os.clock() - requestedAt < REQUEST_TIMEOUT then
                setStatus("Dungeon", "WAITING ROOM START")
                return false
            end
            -- the room never started: give the match back and try again
            requestedAt = nil
            if S.DUNGEON_REPEAT_DONE > 0 then U.Set("DUNGEON_REPEAT_DONE", S.DUNGEON_REPEAT_DONE - 1) end
            setStatus("Dungeon", "ROOM TIMEOUT - RETRY")
        end
        -- batch finished: stop auto
        if S.DUNGEON_REPEAT > 0 and S.DUNGEON_REPEAT_DONE >= S.DUNGEON_REPEAT then
            setStatus("Dungeon", "REPEAT DONE " .. S.DUNGEON_REPEAT_DONE .. "/" .. S.DUNGEON_REPEAT)
            U.Set("DUNGEON_AUTO", false)
            U.Set("DUNGEON_REPEAT_DONE", 0)
            return false
        end
        if not followGate() then return false end
    end

    local world, diff, label, mapIdx
    if S.DUNGEON_SMART then
        world, diff, label, mapIdx = Dungeon.ResolveSmart(true)
        if not world then setStatus("Dungeon", label); return false end
    else
        if not validateSelection() then setStatus("Dungeon", "NO UNLOCKED TARGET"); return false end
        world, diff = S.DUNGEON_WORLD, S.DUNGEON_DIFF
        label = world .. " DIFF " .. diff
    end

    local screen = mainGui("ScreenMatch")
    if not screen or not screen.Visible then
        local room, part = findFreePortal(1, 4)
        if not room then setStatus("Dungeon", "WAITING EMPTY ROOM 1-4"); return false end
        setStatus("Dungeon", "TOUCHING " .. room.Name)
        local ok, why = touchPortal(room, part)
        if not ok then setStatus("Dungeon", "ERROR " .. tostring(why)); return false end
        screen = waitVisible(function() return mainGui("ScreenMatch") end, 2.5)
        if not screen then setStatus("Dungeon", "WAITING SCREENMATCH"); return false end
    end
    if not isInLobby() then return false end

    setStatus("Dungeon", "CREATING " .. label)
    worldRE():FireServer("SelectWorld", world, diff)
    task.wait(0.35)
    gameMatchRE():FireServer("CreatRoom", world, diff, S.DUNGEON_PLAYERS)
    lastDungeonAt = os.clock()
    if force then
        setStatus("Dungeon", "ROOM REQUESTED")
    else
        requestedAt = os.clock()
        U.Set("DUNGEON_REPEAT_DONE", S.DUNGEON_REPEAT_DONE + 1)
        if mapIdx then U.Set("DUNGEON_CURSOR", mapIdx) end
        setStatus("Dungeon", "ROOM REQUESTED " .. S.DUNGEON_REPEAT_DONE .. "/"
            .. (S.DUNGEON_REPEAT > 0 and tostring(S.DUNGEON_REPEAT) or "inf"))
    end
    return true
end

function Dungeon.StartNow() return Dungeon.TryStart(true) end

--========================================================--
-- ENDLESS TOWER
--========================================================--
local Tower = { Weapon = { Attempt = 0, RequestedUUID = nil, RequestedAt = 0 } }
U.Tower = Tower
local lastJoinAt, lastStartClickAt = -math.huge, -math.huge

function Tower.GetHighest()
    local m = mods()
    local rec = m.WorldUtil:GetWorldRecords(LocalPlayer, "Endless1", 1, "MaxRound", m.SeasonUtil:GetCurrentSeason())
    rec = math.max(0, math.floor(tonumber(rec) or 0))
    return math.clamp(math.floor(rec / 5) * 5 + 1, 1, 196), rec
end

function Tower.ResolveStart()
    local highest, record = Tower.GetHighest()
    if S.TOWER_START_ROUND == 0 then return highest, record end
    return math.min(S.TOWER_START_ROUND, highest), record
end

local function weaponModules()
    local m = mods()
    local re = waitChain(ReplicatedStorage, { "Framework", "Gameplay", "EquipmentSystem", "EquipmentRE" })
    return m.DataUtil, m.EquipmentUtil, m.TimeLimitUtil, m.TranslationUtil, re
end

function Tower.GetWeaponOptions()
    local data, equip, timeLimit, translation = weaponModules()
    local owned = data:GetValue(LocalPlayer, { "Equipment", "Owned" }) or {}
    local slots = data:GetValue(LocalPlayer, { "Equipment", "EquipSlots" }) or {}
    local out = {}
    for uuid, item in pairs(owned) do
        if type(item) == "table" and item.Type == "Weapon" and uuid ~= slots.Weapon and uuid ~= slots.Weapon2
            and not timeLimit:IsTimeLimited(item) then
            local def = equip:GetDef(item.ID)
            if def then
                local dmg = tonumber(equip:GetDmgOrHpByInfo(LocalPlayer, item, def)) or 0
                local name = tostring(def.ID or item.ID or uuid)
                local ok, tr = pcall(translation.TranslateByKey, translation, "K_" .. string.upper(tostring(def.ID or item.ID or "")))
                if ok and type(tr) == "string" and tr ~= "" then name = tr end
                local fort = item.Fortify and item.Fortify - 1 or 0
                table.insert(out, {
                    UUID = uuid,
                    Label = name .. (fort > 0 and (" (+" .. fort .. ")") or "") .. " | DMG " .. dmg,
                    Damage = dmg,
                    Rarity = tonumber(equip:GetOreRarity(item.MaxOre)) or 0,
                    Sort = tonumber(def.Sort) or math.huge,
                })
            end
        end
    end
    table.sort(out, function(a, b)
        if a.Damage ~= b.Damage then return a.Damage > b.Damage end
        if a.Rarity ~= b.Rarity then return a.Rarity > b.Rarity end
        if a.Sort ~= b.Sort then return a.Sort < b.Sort end
        return tostring(a.UUID) < tostring(b.UUID)
    end)
    return out
end

local function resolveWeapon()
    local options = Tower.GetWeaponOptions()
    if S.TOWER_WEAPON ~= "" then
        for _, o in ipairs(options) do
            if o.UUID == S.TOWER_WEAPON then return o, false, options end
        end
    end
    return options[1], S.TOWER_WEAPON ~= "", options
end

local function resetWeaponRequest()
    local w = Tower.Weapon
    w.Attempt, w.RequestedUUID, w.RequestedAt = 0, nil, 0
end
Tower.ResetWeaponRequest = resetWeaponRequest

local function requestEquip(uuid)
    local _, _, _, _, re = weaponModules()
    re:FireServer("RequestSetExtraWeapon", uuid)
end

-- players currently inside the Endless room we created (Room9/10 attribute)
local function towerRoomCount()
    local room = Tower.Room
    if room and room.Parent then
        return tonumber(room:GetAttribute("PlayersCount")) or 0
    end
    local best = 0
    local mr = workspace:FindFirstChild("MatchRoom")
    if mr then
        for i = 9, 10 do
            local r = mr:FindFirstChild("Room" .. i)
            if r then best = math.max(best, tonumber(r:GetAttribute("PlayersCount")) or 0) end
        end
    end
    return best
end

function Tower.TryJoin()
    if not S.TOWER_AUTO then return false end
    if isInLobby() and LocalPlayer:GetAttribute("EnterRoomId") then setStatus("Tower", "ROOM ASSIGNED"); return false end
    if not lobbyReady() then
        setStatus("Tower", inEndlessTower() and "IN TOWER" or "WAITING LOBBY")
        return false
    end
    if os.clock() - lastJoinAt < 10 then return false end
    lastJoinAt = os.clock()

    local room, part = findFreePortal(9, 10)
    if not room then setStatus("Tower", "WAITING EMPTY ROOM 9/10"); return false end

    local screen = mainGui("ScreenMatch_Endless")
    if not screen or not screen.Visible then
        setStatus("Tower", "TOUCHING " .. room.Name)
        local ok, why = touchPortal(room, part)
        if not ok then setStatus("Tower", "ERROR " .. tostring(why)); return false end
        screen = waitVisible(function() return mainGui("ScreenMatch_Endless") end, 3)
        if not screen then setStatus("Tower", "WAITING SCREENMATCH_ENDLESS"); return false end
    end

    local startRound, record = Tower.ResolveStart()
    setStatus("Tower", "CREATING " .. room.Name .. " - ROUND " .. startRound .. " (BEST " .. record .. ")")
    gameMatchRE():FireServer("CreatRoom", "Endless1", 1, S.TOWER_PLAYERS, startRound)
    Tower.Room, Tower.WaitSince = room, nil
    -- diagnostics: room attributes go to the Log tab (shows the real max players)
    task.delay(2, function()
        local parts = {}
        pcall(function()
            for k, v in pairs(room:GetAttributes()) do table.insert(parts, k .. "=" .. tostring(v)) end
        end)
        table.sort(parts)
        if #parts > 0 then setStatus("Room", table.concat(parts, " ")) end
    end)
    return true
end

-- Handles the "Equip Extra Weapon" pop-up and presses Start. Returns true when
-- it handled (or is waiting on) that pop-up, so the caller skips TryJoin.
function Tower.TryStartRun()
    if not S.TOWER_AUTO then return false end
    local now = os.clock()
    if now - lastStartClickAt < 1 then return false end
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end

    local title
    for _, o in ipairs(pg:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and guiVisible(o)
            and string.find(string.lower(tostring(o.Text)), "equip extra weapon", 1, true) then
            title = o
            break
        end
    end
    if not title then resetWeaponRequest(); Tower.WaitSince = nil; return false end

    local startBtn
    local root = title.Parent
    while root and root ~= pg.Parent and not startBtn do
        for _, o in ipairs(root:GetDescendants()) do
            if o:IsA("GuiButton") and guiVisible(o) then
                local text = o:IsA("TextButton") and o.Text or ""
                if string.find(string.lower(o.Name .. " " .. tostring(text)), "start", 1, true) then
                    startBtn = o
                    break
                end
            elseif o:IsA("TextLabel") and guiVisible(o) and string.lower(tostring(o.Text)) == "start" then
                local btn = o:FindFirstAncestorWhichIsA("GuiButton")
                if btn and guiVisible(btn) then startBtn = btn; break end
            end
        end
        root = root.Parent
    end

    lastStartClickAt = now
    if not startBtn then setStatus("Tower", "WAITING START BUTTON"); return true end

    -- Multi-player: do not press Start while the room is still short of players,
    -- otherwise the run begins solo no matter what Max players is set to.
    if S.TOWER_PLAYERS > 1 and S.TOWER_WAIT > 0 then
        Tower.WaitSince = Tower.WaitSince or now
        local have = towerRoomCount()
        if have < S.TOWER_PLAYERS and now - Tower.WaitSince < S.TOWER_WAIT then
            setStatus("Tower", "WAITING PLAYERS " .. have .. "/" .. S.TOWER_PLAYERS)
            return true
        end
    end

    local function start(msg)
        setStatus("Tower", msg or "STARTING RUN")
        Tower.WaitSince = nil
        clickButton(startBtn)
    end

    local candidate, fellBack, options = resolveWeapon()
    if not candidate then
        setStatus("Weapon", "NO ELIGIBLE WEAPON")
        resetWeaponRequest()
        start()
        return true
    end

    local w = Tower.Weapon
    if w.Attempt == 0 then
        w.RequestedUUID, w.RequestedAt, w.Attempt = candidate.UUID, now, 1
        requestEquip(candidate.UUID)
        setStatus("Weapon", (fellBack and "FALLBACK: " or "EQUIPPING: ") .. candidate.Label)
        return true
    end
    if LocalPlayer:GetAttribute("ExtraWeaponUUID") == w.RequestedUUID then
        setStatus("Weapon", "EQUIPPED: " .. candidate.Label)
        resetWeaponRequest()
        start()
        return true
    end
    if now - w.RequestedAt < 2 then setStatus("Weapon", "WAITING EQUIP CONFIRM"); return true end
    if w.Attempt == 1 then
        local top = options[1] or candidate
        w.RequestedUUID, w.RequestedAt, w.Attempt = top.UUID, now, 2
        requestEquip(top.UUID)
        setStatus("Weapon", "RETRY HIGHEST: " .. top.Label)
        return true
    end
    setStatus("Weapon", "EQUIP TIMEOUT")
    resetWeaponRequest()
    start()
    return true
end

function Tower.GetInfo()
    local highest, record = Tower.GetHighest()
    local nextStart = Tower.ResolveStart()
    local okC, have = pcall(towerRoomCount)
    local waitLeft
    if Tower.WaitSince then waitLeft = math.max(0, S.TOWER_WAIT - (os.clock() - Tower.WaitSince)) end
    return {
        Highest = highest, Record = record, NextStart = nextStart,
        Players = S.TOWER_PLAYERS, Have = okC and have or 0, WaitLeft = waitLeft,
    }
end

--========================================================--
-- WORKERS
--========================================================--
local function loop(name, interval, fn)
    task.spawn(function()
        while U.Alive do
            task.wait(interval)
            local ok, err = pcall(fn)
            if not ok then
                setStatus(name, "ERROR " .. tostring(err))
                task.wait(2)
            end
        end
    end)
end

-- Pets
loop("Hatch", 1.5, function()
    if not S.HATCH_AUTO then setStatus("Hatch", "OFF"); return end
    Hatch.Step()
end)
loop("Expedition", 1, function()
    if not (S.EXP_DISPATCH or S.EXP_CLAIM) then setStatus("Expedition", "OFF"); return end
    Exp.Step()
end)

-- Hatch: react to data changes instead of waiting for the next poll.
task.spawn(function()
    local ok, err = pcall(function()
        local data = mods().DataUtil
        local function wake() hatchWake = true end
        data:ListenFor(LocalPlayer, { "PetHatch", "Egg" }, wake)
        data:ListenFor(LocalPlayer, { "PetHatch", "Slots" }, wake)
    end)
    if not ok then warn("[IronSoul Utility] hatch listener: " .. tostring(err)) end
end)
task.spawn(function()
    while U.Alive do
        if hatchWake then
            hatchWake = false
            if S.HATCH_AUTO then pcall(Hatch.Step) end
        end
        task.wait(0.25)
    end
end)

-- Tower
loop("Tower", 0.5, function()
    if not S.TOWER_AUTO then
        if statuses.Tower ~= nil and statuses.Tower ~= "OFF" then setStatus("Tower", "OFF") end
        return
    end
    if not Tower.TryStartRun() then Tower.TryJoin() end
end)

-- Dungeon
loop("Dungeon", 1, function()
    if not S.DUNGEON_AUTO then
        Dungeon.ResetSession()
        if statuses.Dungeon ~= nil and statuses.Dungeon ~= "OFF" then setStatus("Dungeon", "OFF") end
        return
    end
    Dungeon.TryStart(false)
end)

function U.Destroy()
    U.Alive = false
    if rawget(getgenv(), "IronSoulUtility") == U then getgenv().IronSoulUtility = nil end
end

getgenv().IronSoulUtility = U
return U

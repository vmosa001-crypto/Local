--------------------------------------------------------------------------------
--// ui/tab_trade.lua — Tab Trade: Stall Market (scan / deep scan / beli / jual di Market Place)
-- Dibuat dari "Iron Soul Dungeon | Stall Market v6.0". Logika scan, verifikasi dua langkah
-- (BUY -> baca ulang stall -> CONFIRM), teleport ke stall, dan SELL / LIST (Ore + Scroll) tidak diubah;
-- hanya UI yang dipindah ke halaman tab: filter + tombol (satu baris, geser samping) di atas,
-- status di bawahnya, lalu daftar listing. SELL / LIST menggantikan daftar pasar saat dibuka.
-- Inisialisasi berjalan di thread terpisah (WaitForChild booth system bisa menunggu sampai 10 dtk
-- per langkah) supaya loader tidak tertahan di place yang bukan Market.
--------------------------------------------------------------------------------
local H             = getgenv().Hub
local CreateTab     = H.CreateTab
local CreateSection = H.CreateSection

local Page = CreateTab("💱 Trade")

local function infoCard(text)
    local card = Instance.new("Frame", Page)
    card.BackgroundColor3 = Color3.fromRGB(22, 22, 35)
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BorderSizePixel = 0
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
    local pad = Instance.new("UIPadding", card)
    pad.PaddingTop = UDim.new(0, 8); pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)
    local lbl = Instance.new("TextLabel", card)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.TextWrapped = true
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(205, 205, 218)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Top
    lbl.Text = text
    return lbl
end

local Boot = infoCard("⏳ Stall Market: memuat modul booth...")

task.spawn(function()
    local ok, err = pcall(function()
        local Players = game:GetService("Players")
        local RS = game:GetService("ReplicatedStorage")
        local Workspace = game:GetService("Workspace")
        local HttpService = game:GetService("HttpService")
        local LocalPlayer = Players.LocalPlayer

        local function try(f) local ok, v = pcall(f) return ok and v or nil end
        local function wait10(o, ...)
            for _, n in ipairs({...}) do o = o and o:WaitForChild(n, 10) end
            return o
        end

        local BoothSys = wait10(RS, "Framework", "Features", "BoothSystem")
        local BoothRE = BoothSys and BoothSys:WaitForChild("BoothRE", 10)
        if not (BoothRE and BoothRE:IsA("RemoteEvent")) then
            error("BoothRE tidak tersedia di place ini (Stall Market hanya untuk Market/Booth place)", 0)
        end
        local Controller = try(function()
            local c = require(wait10(BoothSys, "Client", "BoothController"))
            return type(c) == "table" and c or nil
        end)
        local Config = require(BoothSys:WaitForChild("BoothConfig", 10))
        local marketCap = math.clamp(tonumber(Config.StallCount) or 40, 1, 100)
        local Registry = try(function() return require(wait10(RS, "Configs", "ResBoothTradeable")) end)
        local MarketUtil = try(function() return require(wait10(RS, "Utility", "GamePlaceUtil")) end)
        local ScrollDefinitions = try(function() return require(RS.Configs.ResScrolls) end)
        local fw = try(function() return require(RS.Framework) end)
        local function mod(n) return try(function() return fw.Modules[n] end) end
        local ScrollUtil, TranslateUtil, WindowUtil, dataUtil =
            mod("ScrollUtil"), mod("TranslationUtil"), mod("WindowUtil"), mod("DataUtil")

        local function marketPlace()
            if MarketUtil and type(MarketUtil.IsBooth) == "function" then
                local ok, v = pcall(function() return MarketUtil:IsBooth() end)
                return ok and v == true
            end
            return false
        end

        local env = (type(getgenv) == "function" and getgenv()) or shared
        if env.IronSoulMarketScanner and type(env.IronSoulMarketScanner.Stop) == "function" then
            pcall(env.IronSoulMarketScanner.Stop)
        end
        -- Bersihkan GUI versi standalone lama bila masih ada di PlayerGui.
        do
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            for _, n in ipairs({"IronSoulScrollMarketScannerV2", "IronSoulScrollMarketScannerV3",
                "IronSoulScrollMarketScannerV4", "IronSoulScrollMarketScannerV5", "IronSoulScrollMarketScannerV6"}) do
                local old = pg and pg:FindFirstChild(n)
                if old then old:Destroy() end
            end
        end

        local state = {
            Alive = true, Busy = false, Cancel = false, Dirty = true,
            Stalls = {}, Full = {}, FullAt = {}, Conn = {}, LastRefresh = -1e6,
            PendingPurchase = nil, PurchaseBusy = false, PurchasesSent = 0, Page = 1, PageSize = 15,
            LastRender = -100, MarkSlot = nil, TpLastDiagnostic = "", TpSource = {},
            ResponseSlot = nil, Probed = {}, ProbedCount = 0, ProbedSuccess = 0,
            AllScanCompleted = false, ExpectedProbes = 0, EmptyCount = 0,
            SnapshotReceived = false, Sort = "QUALITY", TypeFilter = "ALL", LastMessage = "", RefreshCount = 0,
        }
        env.IronSoulMarketScanner = state

        ---------------------------------------------------------------- helpers
        local function isNumber(n) return type(n) == "number" and n == n and math.abs(n) < 1e14 end
        local function pick(t, kind, ...)
            if type(t) ~= "table" then return nil end
            for i = 1, select("#", ...) do
                local v = t[(select(i, ...))]
                if kind == "n" then
                    if isNumber(v) then return v end
                elseif type(v) == "string" and v ~= "" then
                    return v
                end
            end
        end
        local function number(t, ...) return pick(t, "n", ...) end
        local function str(t, ...) return pick(t, "s", ...) end
        local function niceNumber(n)
            local r = math.floor(n + .5)
            return math.abs(n - r) < 1e-7 and string.format("%.0f", r) or string.format("%.2f", n)
        end
        local function fmt(n) return isNumber(n) and niceNumber(n) or "?" end
        local function slot(k)
            local n = tonumber(k)
            if n and n == math.floor(n) and n >= 1 and n <= marketCap then return n end
        end
        local function positiveUserId(s)
            local n = type(s) == "table" and tonumber(s.OwnerUserId)
            if n and n == math.floor(n) and n > 0 and n < 1e14 then return n end
        end
        local function intRange(v, lo, hi)
            local n = tonumber(v)
            if n and n == n and n % 1 == 0 and n >= lo and n <= hi then return n end
        end
        local function joinAttrs(t) return table.concat(t, "|") end

        local index = {}
        if type(Registry) == "table" then
            for _, key in ipairs(Registry.__index or {}) do
                local d = Registry[key]
                if type(d) == "table" and type(d.ItemType) == "string" and type(d.ItemID) == "string" then
                    index[d.ItemType .. "\0" .. d.ItemID] = d
                end
            end
        end

        ---------------------------------------------------------------- stat parsing
        -- Mythic (rarity 6) + exactly 4 rolled attributes + >=3 DISTINCT groups of ATK/CR/CD/SKILL/CDR.
        local STAT_GROUPS = {
            ATK = {"Attack Bonus", "atkbonus", "attackbonus", "attackbonusrate"},
            CR = {"Crit Rate", "chrate", "critrate", "criticrate", "criticalrate", "criticalchance", "critichance", "critchance"},
            CD = {"Crit Damage", "chdmgbonus", "critdmgbonus", "critdamage", "critdmg", "criticaldamage", "criticaldmg"},
            SKILL = {"Skill Damage", "skilldmgbonus", "skilldamage", "skilldmg", "skilldamagebonus"},
            CDR = {"Skill CDR", "skillcdreduce", "skillcdr", "skillcooldownreduction", "skillcooldownreduce", "skillcdreduction"},
        }
        local GROUP_ORDER = {"ATK", "CR", "CD", "SKILL", "CDR"}
        local GROUP_BY_KEY, NAME_BY_KEY = {}, {}
        for group, def in pairs(STAT_GROUPS) do
            for i = 2, #def do GROUP_BY_KEY[def[i]] = group; NAME_BY_KEY[def[i]] = def[1] end
        end
        for label, keys in pairs({
            ["Dash CDR"] = {"dashcdreduce", "dashcdreduction", "dashcooldownreduction", "dashcdr"},
            ["Move Speed"] = {"movespeedbonus", "movespeed", "movementspeed", "movementspeedbonus"},
            ["Health Bonus"] = {"healthbonus", "hpbonus"}, ["Skill Charge"] = {"skillchargebonus"},
            ["Ultimate Charge"] = {"ultimatecharge"}, ["Block Chance"] = {"blockchance"},
        }) do for _, k in ipairs(keys) do NAME_BY_KEY[k] = label end end
        local IGNORE = {}
        for w in ("id idx index rarity grade itemid skillid price quantity qty count level lv uuid weight sort type value amount val number stat key attribute attrtype stattype statvalue unit valuetype"):gmatch("%S+") do
            IGNORE[w] = true
        end
        local GOOD5 = {"Attack Bonus", "Crit Rate", "Crit Damage", "Skill Damage", "Skill CDR"}
        local PREMIUM4 = {"Attack Bonus", "Skill Damage", "Crit Rate", "Crit Damage"}
        local function hasLabel(text, list)
            for _, p in ipairs(list) do if text:find(p, 1, true) == 1 then return true end end
            return false
        end
        local function lowerKey(k) return (tostring(k):lower():gsub("[^a-z0-9]", "")) end

        local function formatStat(k, num, unit)
            local n = tonumber(num)
            if not isNumber(n) or math.abs(n) > 1e8 then return nil end
            local perc = not (unit == "flat" or unit == "count")
            if perc and n ~= 0 and math.abs(n) < 1 then n = n * 100 end
            local label = NAME_BY_KEY[lowerKey(k)] or (tostring(k):gsub("_", " "))
            return label .. " " .. (n >= 0 and "+" or "") .. niceNumber(n) .. (perc and "%" or "")
        end

        local function parseStats(raw)
            local source
            for _, n in ipairs({"Attrs", "Attributes", "BonusAttrs", "Stats", "StatData",
                "AttributeData", "ExtraAttrs", "Options", "Affixes", "ScrollData"}) do
                if type(raw[n]) == "table" then source = raw[n]; break end
            end
            if not source then return {}, {}, 0 end
            local entries, seen, kinds, visited = {}, {}, {}, {}
            local function add(key, value, unit)
                if type(key) ~= "string" and type(key) ~= "number" then return end
                local tag = lowerKey(key)
                if IGNORE[tag] or seen[tag] then return end
                local text = formatStat(key, value, unit)
                if not text then return end
                seen[tag] = true
                local group = GROUP_BY_KEY[tag]
                entries[#entries + 1] = {Key = tostring(key), Text = text, Group = group}
                if group then kinds[group] = true end
            end
            local function walk(t, depth)
                if type(t) ~= "table" or depth > 5 or visited[t] then return end
                visited[t] = true
                local key = t.Type or t.Stat or t.Key or t.Attribute or t.AttrType or t.StatType
                local value
                for _, f in ipairs({"Value", "Amount", "Val", "Number", "StatValue"}) do
                    if t[f] ~= nil then value = t[f]; break end
                end
                if key ~= nil and value ~= nil then add(key, value, t.Unit or t.ValueType) end
                for k, v in pairs(t) do
                    if type(v) == "number" and type(k) == "string" then add(k, v)
                    elseif type(v) == "table" then walk(v, depth + 1) end
                end
            end
            walk(source, 0)
            local function order(g) return g and table.find(GROUP_ORDER, g) or 99 end
            table.sort(entries, function(a, b)
                local wa, wb = order(a.Group), order(b.Group)
                if wa ~= wb then return wa < wb end
                return a.Key < b.Key
            end)
            local stats, match = {}, 0
            for _, e in ipairs(entries) do stats[#stats + 1] = e.Text end
            for _ in pairs(kinds) do match = match + 1 end
            return stats, kinds, match
        end

        local function parseRarity(v)
            for _, key in ipairs({"Rarity", "RarityID", "RarityId", "Grade", "Quality"}) do
                local x = v[key]
                if type(x) == "number" and x % 1 == 0 then return x end
                if type(x) == "string" then
                    if x:lower() == "mythic" then return 6 end
                    local n = tonumber(x)
                    if n and n % 1 == 0 then return n end
                end
            end
        end

        local function getListingId(v, itemId)
            local id = str(v, "ListingId", "ListingID", "ListingUUID", "ListingUid", "ListingUID",
                "ListId", "ListID", "ListUUID", "UUID", "Uid", "UID")
            if id and id ~= itemId then return id, "explicit" end
            local raw = str(v, "Id", "ID")
            if raw and raw ~= itemId and #raw >= 16 and #raw <= 128 then return raw, "strong-id" end
            return nil, "missing"
        end

        local function scrollName(id, listing)
            local direct = str(listing, "DisplayName", "ScrollName", "Title", "ItemTitle")
            if direct then return direct, nil end
            local def = type(ScrollDefinitions) == "table" and ScrollDefinitions[id] or nil
            if not def and type(ScrollUtil) == "table" and type(ScrollUtil.GetDef) == "function" then
                pcall(function() def = ScrollUtil:GetDef(id) end)
            end
            local isDef = type(def) == "table"
            local skill = str(listing, "SkillName", "SkillDisplayName", "NewSkill", "SkillId")
                or (isDef and str(def, "SkillName", "SkillId", "SkillID") or nil)
            local declared = isDef and str(def, "DisplayName", "Name", "Title") or nil
            local translation
            if type(TranslateUtil) == "table" and type(TranslateUtil.TranslateByKey) == "function" then
                pcall(function() translation = TranslateUtil:TranslateByKey("K_" .. id:upper()) end)
                if translation == "K_" .. id:upper() or translation == "" then translation = nil end
            end
            -- Replace untranslated K_* keys with weapon class + skill name.
            if declared and declared:match("^K_[A-Z0-9_]+$") then declared = nil end
            if translation and translation:match("^K_[A-Z0-9_]+$") then translation = nil end
            local class, level = id:match("^Scroll_([^_]+)_(%d+)$")
            local short = skill and skill:match("([^_]+)$")
            if short then short = short:gsub("(%l)(%u)", "%1 %2") end
            local natural = class and (class .. " Scroll") or (id:gsub("_", " "))
            local name = declared or translation
                or (natural .. (short and (": " .. short) or (level and (" #" .. level) or "")))
            return (tostring(name):gsub("<[^>]+>", "")), skill
        end

        local function normalizeListing(v, key, s, stall, detail)
            if type(v) ~= "table" then return nil end
            local itemType = str(v, "ItemType", "Type", "Category")
            if not itemType then return nil end
            local id = str(v, "ItemID", "ItemId", "ItemIDStr", "ItemName")
            if not id and itemType == "Scroll" and type(v.Id) == "string" and v.Id:sub(1, 7) == "Scroll_" then id = v.Id end
            if not id then return nil end
            local isScroll = itemType == "Scroll"
            local price = number(v, "TotalPrice", "ListingPrice", "Price", "SellPrice", "Gold")
            local info = index[itemType .. "\0" .. id]
            local listingId, idSource = getListingId(v, id)
            local name, skill
            if isScroll then
                name, skill = scrollName(id, v)
            else
                name = str(v, "DisplayName", "Name", "Title", "ItemTitle") or (type(info) == "table" and str(info, "DisplayName", "Name", "Title"))
                    or (id:gsub("_", " "))
                name = (tostring(name):gsub("<[^>]+>", ""))
            end
            local stats, groups, good = parseStats(v)
            local rarity = parseRarity(v)
            local reason = (not isScroll and "NOT_SCROLL") or (rarity ~= 6 and "NOT_MYTHIC") or (#stats ~= 4 and "NOT_4_ATTRS")
                or (good < 3 and "LESS_THAN_3_DPS_CATEGORIES") or "PASS"
            local distinct = {}
            for _, k in ipairs(GROUP_ORDER) do if groups[k] then distinct[#distinct + 1] = k end end
            return {
                Slot = s, Type = itemType, Qty = number(v, "Quantity", "Qty", "Count", "Amount"), Id = id, Name = name, Skill = skill, Stats = stats,
                StatCount = #stats, Rarity = rarity, Matched = good, MatchedList = table.concat(distinct, "+"),
                Pass = reason == "PASS", Reject = reason,
                Price = price, Ref = type(info) == "table" and number(info, "OfficialPrice") or nil,
                Owner = str(stall, "OwnerName", "Username", "UserName") or "?",
                OwnerUserId = positiveUserId(stall), ListingId = listingId, IdSource = idSource,
                Detail = detail == true, Raw = v, RawKey = tostring(key),
            }
        end

        local function extractItems(stall, s, detail)
            local rows, seen = {}, {}
            if type(stall) ~= "table" or type(stall.Items) ~= "table" then return rows end
            for key, v in pairs(stall.Items) do
                local row = normalizeListing(v, key, s, stall, detail)
                if row then
                    local unique = row.ListingId or (row.Id .. ":" .. tostring(key))
                    if not seen[unique] then seen[unique] = true; rows[#rows + 1] = row end
                end
            end
            return rows
        end

        ---------------------------------------------------------------- stall cache + events
        local function absorb(k, data, detail)
            local s = slot(k)
            if not s or type(data) ~= "table" then return false end
            state.Stalls[s] = data
            if detail then state.Full[s] = data; state.FullAt[s] = os.clock() end
            state.Dirty = true
            return true
        end
        local function occupiedStall(t)
            if type(t) ~= "table" or t.Empty == true or t.IsEmpty == true then return false end
            local uid = number(t, "OwnerUserId", "OwnerId", "UserId")
            local owner = str(t, "OwnerName", "Username", "UserName")
            if owner and (owner:lower():match("^%s*empty%s*$") or owner:lower():match("^%s*vacant%s*$")) then owner = nil end
            return (uid ~= nil and uid > 0) or owner ~= nil
        end
        local function countOccupied()
            local n = 0
            for _, st in pairs(state.Stalls) do if occupiedStall(st) then n = n + 1 end end
            return n
        end
        local function scanCurrentCache()
            if not Controller or type(Controller.GetAllStalls) ~= "function" then return 0 end
            local ok, cache = pcall(function() return Controller:GetAllStalls() end)
            if not ok or type(cache) ~= "table" then return 0 end
            local count = 0
            for key, data in pairs(cache) do
                if occupiedStall(data) and absorb(key, data, false) then count = count + 1 end
            end
            return count
        end
        local function updateEmpty()
            if state.SnapshotReceived then state.EmptyCount = math.max(0, marketCap - countOccupied()) end
        end

        local function handleEvent(action, payload)
            if not state.Alive or type(payload) ~= "table" then return end
            if action == "BoothShows" then
                -- Native client replaces the whole snapshot instead of merging.
                local copy = {}
                for k, d in pairs(payload) do
                    local s = slot(k)
                    if s and occupiedStall(d) then copy[s] = d end
                end
                state.Stalls = copy
                state.SnapshotReceived = true
                updateEmpty()
                for key, old in pairs(state.Full) do
                    local new = copy[key]
                    if not new or (old.OwnerUserId and new.OwnerUserId and old.OwnerUserId ~= new.OwnerUserId) then
                        state.Full[key] = nil; state.FullAt[key] = nil
                    end
                end
                state.RefreshCount = state.RefreshCount + 1
                state.Dirty = true
            elseif action == "BoothShowUpdate" then
                local s = slot(payload.SlotIndex)
                if s then
                    state.Stalls[s] = occupiedStall(payload.Stall) and payload.Stall or nil
                    updateEmpty()
                    state.Full[s] = nil; state.FullAt[s] = nil -- details may be stale now
                    state.PendingPurchase = nil
                    state.Dirty = true
                end
            elseif action == "StallView" then
                local s = slot(payload.SlotIndex)
                if s and type(payload.Stall) == "table" then
                    absorb(s, payload.Stall, true)
                    state.ResponseSlot = s
                    if state.Probed[s] then state.Probed[s].Status = "RESPONSE" end
                    -- Native UI opens after every StallView; close it ONLY while scanning.
                    if state.Busy and WindowUtil and type(WindowUtil.Close) == "function" then
                        task.defer(function()
                            if state.Alive and state.Busy then pcall(function() WindowUtil:Close("ScreenBoothRoot") end) end
                        end)
                    end
                end
            elseif action == "StallRefresh" then
                local uid = number(payload, "OwnerUserId")
                if uid then
                    for s, known in pairs(state.Stalls) do
                        if number(known, "OwnerUserId") == uid then absorb(s, payload, true); break end
                    end
                end
            end
        end
        state.Conn[#state.Conn + 1] = BoothRE.OnClientEvent:Connect(handleEvent)
        scanCurrentCache()

        ---------------------------------------------------------------- reversible performance options
        local perf = {HidePlayers = false, PlayerChanges = setmetatable({}, {__mode = "k"}), PlayerConns = {}, Seen = {}}
        local function change(bucket, obj, key, value)
            local ok, cur = pcall(function() return obj[key] end)
            if not ok or cur == value then return end
            local rec = bucket[obj]
            if not rec then rec = {}; bucket[obj] = rec end
            if rec[key] == nil then rec[key] = cur end
            pcall(function() obj[key] = value end)
        end
        local function restore(bucket)
            for obj, values in pairs(bucket) do
                for k, v in pairs(values) do pcall(function() if obj.Parent then obj[k] = v end end) end
                bucket[obj] = nil
            end
        end
        local function disconnect(list)
            for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
            table.clear(list)
        end
        local function hidePart(o)
            if perf.HidePlayers and o:IsA("BasePart") then change(perf.PlayerChanges, o, "LocalTransparencyModifier", 1) end
        end
        local function watchPlayer(p)
            if not perf.HidePlayers or p == LocalPlayer or perf.Seen[p] then return end
            perf.Seen[p] = true
            local function watch(char)
                if not char or not perf.HidePlayers then return end
                for _, o in ipairs(char:GetDescendants()) do hidePart(o) end
                perf.PlayerConns[#perf.PlayerConns + 1] = char.DescendantAdded:Connect(hidePart)
            end
            perf.PlayerConns[#perf.PlayerConns + 1] = p.CharacterAdded:Connect(function(c) task.defer(watch, c) end)
            if p.Character then task.defer(watch, p.Character) end
        end
        local function setHidePlayers(on)
            if perf.HidePlayers == on then return end
            perf.HidePlayers = on
            disconnect(perf.PlayerConns)
            perf.Seen = {}
            if not on then restore(perf.PlayerChanges) return end
            perf.PlayerConns[1] = Players.PlayerAdded:Connect(watchPlayer)
            for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
        end

        ---------------------------------------------------------------- status line (UI label bound later)
        local statusLabel
        local function say(msg)
            state.LastMessage = tostring(msg)
            if state.Alive and statusLabel and statusLabel.Parent then statusLabel.Text = state.LastMessage end
            print("[STALL_MARKET] " .. state.LastMessage)
        end

        ---------------------------------------------------------------- teleport (fails closed when ambiguous)
        local SLOT_ATTRS = {"SlotIndex", "StallIndex", "BoothIndex", "StallId", "BoothId", "SlotId", "StallSlot", "BoothSlot"}
        local NAME_PATTERNS = {"^stall[_%-]?(%d+)$", "^booth[_%-]?(%d+)$", "^stallslot[_%-]?(%d+)$",
            "^boothslot[_%-]?(%d+)$", "^marketstall[_%-]?(%d+)$", "^boothpoint[_%-]?(%d+)$", "^stallpoint[_%-]?(%d+)$"}
        local function directSlotId(inst)
            for _, f in ipairs(SLOT_ATTRS) do
                local ok, val = pcall(function() return inst:GetAttribute(f) end)
                if ok and val ~= nil and slot(val) then return slot(val), "attribute:" .. f, 150 end
            end
            local name = inst.Name:lower():gsub("%s+", "")
            for _, p in ipairs(NAME_PATTERNS) do
                local id = name:match(p)
                if id and slot(id) then return tonumber(id), "name:" .. inst.Name, 90 end
            end
        end
        local function getAnchor(o)
            if o:IsA("BasePart") then return o.CFrame, o end
            if not o:IsA("Model") then return nil end
            local part = o.PrimaryPart
            if not part then
                for _, n in ipairs({"StallBase", "BoothBase", "InteractPart", "Counter", "Floor", "Base", "Platform", "Stand", "Main"}) do
                    local f = o:FindFirstChild(n, true)
                    if f and f:IsA("BasePart") then part = f; break end
                end
            end
            if part then return part.CFrame, o end
            local ok, cf = pcall(function() return o:GetPivot() end)
            if ok then return cf, o end
        end
        local function findStallAnchor(slotId, owner)
            local candidates, trace, seen = {}, {}, {}
            local parts = Workspace:GetDescendants()
            for _, obj in ipairs(parts) do
                if obj:IsA("Model") or obj:IsA("BasePart") then
                    local id, why, score = directSlotId(obj)
                    if id == slotId then
                        local cf, parent = getAnchor(obj)
                        if cf and parent then
                            local key = tostring(cf.Position)
                            if not seen[key] then
                                seen[key] = true
                                candidates[#candidates + 1] = {CF = cf, Part = parent, Why = why,
                                    Score = score + (obj:IsA("Model") and 5 or 0)}
                            end
                        end
                    end
                end
                if #trace < 30 then
                    local nm = obj.Name:lower()
                    if nm:find("stall", 1, true) or nm:find("booth", 1, true) then trace[#trace + 1] = obj:GetFullName() end
                end
            end
            -- Fallback: seller text on a physical booth Surface/BillboardGui.
            if #candidates == 0 and type(owner) == "string" and owner ~= "?" then
                for _, obj in ipairs(parts) do
                    if obj:IsA("TextLabel") and obj.Text == owner then
                        local gui = obj.Parent
                        while gui and not gui:IsA("SurfaceGui") and not gui:IsA("BillboardGui") do gui = gui.Parent end
                        if gui then
                            local anchor = gui.Adornee
                            if not anchor then
                                anchor = gui.Parent
                                while anchor and not anchor:IsA("BasePart") do anchor = anchor.Parent end
                            end
                            local ctx, reasonable = gui, false
                            for _ = 1, 5 do
                                if not ctx then break end
                                local n = ctx.Name:lower()
                                if n:find("booth", 1, true) or n:find("stall", 1, true) then reasonable = true; break end
                                ctx = ctx.Parent
                            end
                            if reasonable and anchor and anchor:IsA("BasePart") then
                                candidates[#candidates + 1] = {CF = anchor.CFrame, Part = anchor, Why = "world-seller-label", Score = 45}
                            end
                        end
                    end
                end
            end
            table.sort(candidates, function(a, b) return a.Score > b.Score end)
            local first = candidates[1]
            state.TpLastDiagnostic = "slot=" .. slotId .. " candidate_count=" .. #candidates .. " paths=" .. table.concat(trace, " | ")
            if not first then return nil, "NOT_FOUND" end
            for i = 2, #candidates do
                local c = candidates[i]
                if c.Score >= first.Score and (c.CF.Position - first.CF.Position).Magnitude > 14 then
                    return nil, "AMBIGUOUS_LOCATIONS"
                end
            end
            return first
        end
        local function safeLanding(booth, character)
            local cf = booth.CF
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {character, booth.Part}
            for _, d in ipairs({-cf.LookVector * 6, cf.LookVector * 6, cf.RightVector * 6, -cf.RightVector * 6}) do
                local test = cf.Position + d
                local hit = Workspace:Raycast(test + Vector3.new(0, 13, 0), Vector3.new(0, -50, 0), params)
                if hit and hit.Normal.Y > .76 and math.abs(hit.Position.Y - cf.Position.Y) < 20 then
                    return Vector3.new(test.X, hit.Position.Y + 3.5, test.Z)
                end
            end
        end
        local function teleportToStall(r)
            if not state.Alive or not marketPlace() then say("TP only works in the Market Place."); return end
            state.MarkSlot = r.Slot
            local char = LocalPlayer.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 then say("No character available to teleport."); return end
            local pos, source, lookAt
            local booth, why = findStallAnchor(r.Slot, r.Owner)
            if not booth then
                say("Stall #" .. r.Slot .. " location unknown (" .. why .. "). Walk to it manually. COPY REPORT includes TP_DIAG.")
                return
            end
            pos = safeLanding(booth, char); source = booth.Why
            if not pos then
                say("Found Stall #" .. r.Slot .. " but no safe ground. Walk there manually.")
                return
            end
            lookAt = booth.CF.Position
            local target
            if lookAt and (Vector3.new(lookAt.X, pos.Y, lookAt.Z) - pos).Magnitude > .5 then
                target = CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z))
            else
                local d = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
                target = CFrame.lookAt(pos, pos + (d.Magnitude > .01 and d.Unit or Vector3.new(0, 0, -1)))
            end
            char:PivotTo(target)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            state.TpSource[r.Slot] = source
            say("Teleported to Stall #" .. r.Slot .. " (" .. r.Owner .. ") via " .. source .. ". Open the stall to check the price before buying.")
        end

        ---------------------------------------------------------------- rows / filtering / purchase identity
        local function allRows()
            local rows, slots = {}, {}
            for s in pairs(state.Stalls) do slots[s] = true end
            for s in pairs(state.Full) do slots[s] = true end
            for s in pairs(slots) do
                local byId = {}
                local summary, full = state.Stalls[s], state.Full[s]
                if summary and full and summary.OwnerUserId and full.OwnerUserId
                    and summary.OwnerUserId ~= full.OwnerUserId then full = nil end
                -- Merge summary + detail by listing id so neither erases the other.
                for _, pair in ipairs({{summary, false}, {full, true}}) do
                    if pair[1] then
                        for _, r in ipairs(extractItems(pair[1], s, pair[2])) do byId[r.ListingId or (r.Id .. ":" .. r.RawKey)] = r end
                    end
                end
                for _, r in pairs(byId) do rows[#rows + 1] = r end
            end
            return rows
        end
        -- Compare purchase identity (owner/slot/listing/item/price/rarity/stats), never a display fingerprint.
        local function samePurchaseTarget(a, b)
            if not a or not b or not a.Type or a.Type ~= b.Type then return false end
            if not a.OwnerUserId or a.OwnerUserId ~= b.OwnerUserId or a.Slot ~= b.Slot then return false end
            if not a.ListingId or b.ListingId ~= a.ListingId or a.Id ~= b.Id then return false end
            if not a.Price or a.Price <= 0 or b.Price ~= a.Price then return false end
            if a.Rarity ~= nil and b.Rarity ~= a.Rarity then return false end
            if a.StatCount > 0 and (b.StatCount ~= a.StatCount or joinAttrs(a.Stats) ~= joinAttrs(b.Stats)) then return false end
            return true
        end
        local function purchaseKey(r)
            return table.concat({r.Slot, r.OwnerUserId, r.Id, r.ListingId, r.Price}, "|")
        end
        local function matchingDetail(orig)
            local last = state.Full[orig.Slot]
            if type(last) ~= "table" or positiveUserId(last) ~= orig.OwnerUserId then return nil end
            for _, r in ipairs(extractItems(last, orig.Slot, true)) do
                if samePurchaseTarget(orig, r) then return r end
            end
        end

        ---------------------------------------------------------------- UI toolkit (touch-first)
        local C = {BG = Color3.fromRGB(17, 23, 35), Panel = Color3.fromRGB(29, 38, 55), Field = Color3.fromRGB(41, 53, 72),
            Green = Color3.fromRGB(28, 117, 87), Blue = Color3.fromRGB(51, 82, 127), Red = Color3.fromRGB(137, 63, 67),
            Text = Color3.fromRGB(235, 241, 251), Mute = Color3.fromRGB(174, 191, 217), Good = Color3.fromRGB(128, 225, 170)}
        local function new(class, parent, props)
            local o = Instance.new(class)
            for k, v in pairs(props or {}) do o[k] = v end
            o.Parent = parent
            return o
        end
        local function round(o, r) new("UICorner", o, {CornerRadius = UDim.new(0, r or 6)}) return o end
        local function label(parent, text, pos, size, ts, bold, wrap, color)
            return new("TextLabel", parent, {BackgroundTransparency = 1, Text = tostring(text or ""), TextColor3 = color or C.Text,
                TextSize = ts or 13, Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
                TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = wrap == true,
                TextTruncate = Enum.TextTruncate.AtEnd, Position = pos, Size = size})
        end
        local function button(parent, text, pos, size, cb, tint, ts)
            local b = new("TextButton", parent, {Text = text, Font = Enum.Font.GothamBold, TextSize = ts or 12,
                TextColor3 = C.Text, BackgroundColor3 = tint or C.Blue, TextWrapped = true, Position = pos, Size = size,
                AutoButtonColor = true})
            round(b)
            b.Activated:Connect(cb)
            return b
        end
        local function field(parent, placeholder, pos, size, default)
            return round(new("TextBox", parent, {ClearTextOnFocus = false, Text = default or "", PlaceholderText = placeholder,
                PlaceholderColor3 = C.Mute, Font = Enum.Font.Gotham, TextColor3 = C.Text, BackgroundColor3 = C.Field,
                TextSize = 14, Position = pos, Size = size}))
        end
        local function scroller(parent, pos, size)
            local s = new("ScrollingFrame", parent, {Position = pos, Size = size, BackgroundTransparency = 1, BorderSizePixel = 0,
                ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
                ScrollingDirection = Enum.ScrollingDirection.Y})
            new("UIListLayout", s, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
            return s
        end
        -- Frame kosong yang tingginya mengikuti isi (dipakai untuk daftar kartu di dalam halaman tab).
        local function stack(parent, order, visible)
            local f = new("Frame", parent, {BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order or 0, Visible = visible ~= false})
            new("UIListLayout", f, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
            return f
        end
        local function clearFrames(c) for _, o in ipairs(c:GetChildren()) do if o:IsA("Frame") then o:Destroy() end end end

        ---------------------------------------------------------------- tab layout (urutan = LayoutOrder)
        -- 1 filter | 2 tombol (satu baris landscape, geser samping) | 3-4 status | 5 menu warna stat | 6 pasar | 7 jual
        Boot.Parent:Destroy()
        CreateSection(Page, "Stall Market")
        local fieldRow = new("Frame", Page, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1})
        local search = field(fieldRow, "Search name/stat/seller", UDim2.new(0, 0, 0, 0), UDim2.new(.5, -3, 1, 0))
        local minPrice = field(fieldRow, "Min $", UDim2.new(.5, 3, 0, 0), UDim2.new(.25, -6, 1, 0))
        local maxPrice = field(fieldRow, "Max $", UDim2.new(.75, 3, 0, 0), UDim2.new(.25, -3, 1, 0))
        local btnRow = new("ScrollingFrame", Page, {Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2,
            BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollingDirection = Enum.ScrollingDirection.X})
        new("UIListLayout", btnRow, {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
            SortOrder = Enum.SortOrder.LayoutOrder})
        local sideOrder = 0
        local function sideBtn(text, cb, tint, w)
            sideOrder = sideOrder + 1
            local b = button(btnRow, text, UDim2.new(), UDim2.new(0, w or 100, 0, 34), cb, tint)
            b.LayoutOrder = sideOrder
            return b
        end

        local statsLabel = label(Page, "", UDim2.new(), UDim2.new(1, 0, 0, 20), 12, true, true)
        statsLabel.LayoutOrder = 3
        statusLabel = label(Page, "SCAN, then DEEP SCAN. Every listing is re-verified before purchase.",
            UDim2.new(), UDim2.new(1, 0, 0, 32), 12, false, true, C.Mute)
        statusLabel.LayoutOrder = 4

        -- daftar pasar + pager
        local marketView = stack(Page, 6)
        local list = stack(marketView, 1)
        local pager = new("Frame", marketView, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 2})
        button(pager, "◀", UDim2.new(0, 0, 0, 0), UDim2.new(.3, -4, 1, 0), function()
            state.Page = math.max(1, state.Page - 1); state.Dirty = true
        end, nil, 16)
        button(pager, "▶", UDim2.new(.7, 4, 0, 0), UDim2.new(.3, -4, 1, 0), function()
            state.Page = state.Page + 1; state.Dirty = true
        end, nil, 16)
        local pageLabel = label(pager, "PAGE 1/1", UDim2.new(.3, 0, 0, 0), UDim2.new(.4, 0, 1, 0), 13, true)
        pageLabel.TextXAlignment = Enum.TextXAlignment.Center

        -- Selectable green stats (listing cards only; the SELL panel pricing tiers keep their own fixed list).
        local STAT_FILE = "IronSoul_StatColors.json"
        local colorSet = {}
        for _, n in ipairs(GOOD5) do colorSet[n] = true end
        if type(readfile) == "function" then
            local ok, v = pcall(function() return HttpService:JSONDecode(readfile(STAT_FILE)) end)
            if ok and type(v) == "table" then
                colorSet = {}
                for _, n in ipairs(v) do if type(n) == "string" then colorSet[n] = true end end
            end
        end
        local function saveColors()
            if type(writefile) ~= "function" then return false end
            local list = {}
            for n, on in pairs(colorSet) do if on then list[#list + 1] = n end end
            table.sort(list)
            return pcall(function() writefile(STAT_FILE, HttpService:JSONEncode(list)) end)
        end
        local function statLabel(text)
            return text:match("^(.-) [%+%-][%d%.]+%%?$") or text
        end
        local function isColored(text) return colorSet[statLabel(text)] == true end
        local function knownStatLabels()
            local set = {}
            for _, n in ipairs(GOOD5) do set[n] = true end
            for _, label in pairs(NAME_BY_KEY) do set[label] = true end
            for n in pairs(colorSet) do set[n] = true end
            for _, r in ipairs(allRows()) do for _, t in ipairs(r.Stats) do set[statLabel(t)] = true end end
            local out = {}
            for n in pairs(set) do out[#out + 1] = n end
            table.sort(out)
            return out
        end

        local function knownTypes()
            local set, list = {Scroll = true}, {"ALL"}
            for _, r in ipairs(allRows()) do set[r.Type] = true end
            local names = {}
            for t in pairs(set) do names[#names + 1] = t end
            table.sort(names)
            for _, t in ipairs(names) do list[#list + 1] = t end
            return list
        end

        local function getFiltered()
            local all = allRows()
            local q, mn, mx = search.Text:lower(), tonumber(minPrice.Text), tonumber(maxPrice.Text)
            local result = {}
            for _, r in ipairs(all) do
                local joined = (r.Name .. " " .. r.Id .. " " .. r.Owner .. " " .. table.concat(r.Stats, " ")):lower()
                if (state.TypeFilter == "ALL" or r.Type == state.TypeFilter) and (q == "" or joined:find(q, 1, true)) and (not mn or (r.Price and r.Price >= mn))
                    and (not mx or (r.Price and r.Price <= mx)) then result[#result + 1] = r end
            end
            local function key(r)
                if state.Sort == "NAME" then return r.Name end
                if state.Sort == "REFERENCE" then return r.Ref and r.Ref > 0 and r.Price and r.Price / r.Ref or nil end
                return r.Price
            end
            table.sort(result, function(a, b)
                if state.Sort == "QUALITY" and a.Matched ~= b.Matched then return a.Matched > b.Matched end
                local va, vb = key(a), key(b)
                if va ~= nil and vb == nil then return true end
                if va == nil and vb ~= nil then return false end
                if va ~= vb then return va < vb end
                return a.Slot < b.Slot
            end)
            return all, result
        end

        ---------------------------------------------------------------- scan / deep scan
        local function requestShows()
            if not marketPlace() then say("Only works in the Market Place."); return false end
            if os.clock() - state.LastRefresh < 2 then say("SCAN needs at least 2s between requests."); return false end
            state.LastRefresh = os.clock()
            local ok, err = pcall(function() BoothRE:FireServer("RequestBoothShows") end)
            if not ok then say("RequestBoothShows error: " .. tostring(err)); return false end
            scanCurrentCache()
            say("Stall list requested. Waiting for BoothShows.")
            return true
        end
        local function waitUntil(cond, timeout)
            local t0 = os.clock()
            while state.Alive and not state.Cancel and not cond() and os.clock() - t0 < timeout do task.wait(.1) end
        end
        local function deepScan()
            if state.Busy or state.PurchaseBusy or state.PendingPurchase then say("A scan/purchase is running. STOP or finish it first."); return end
            if not marketPlace() then say("Only works in the Market Place."); return end
            state.Busy = true; state.Cancel = false
            state.Probed = {}; state.ProbedCount = 0; state.ProbedSuccess = 0
            state.AllScanCompleted = false; state.ExpectedProbes = 0
            task.spawn(function()
                -- Only OCCUPIED stalls are probed; empty slots have no owner/inventory.
                local previous = state.RefreshCount
                local sent = requestShows()
                if not sent then
                    waitUntil(function() return os.clock() - state.LastRefresh >= 2.05 end, 3)
                    if state.Alive and not state.Cancel then sent = requestShows() end
                end
                if sent then waitUntil(function() return state.RefreshCount ~= previous end, 3) end
                if state.Cancel or not state.Alive then state.Busy = false; return end
                if not state.SnapshotReceived then scanCurrentCache() end
                local ids = {}
                for id, stall in pairs(state.Stalls) do if occupiedStall(stall) then ids[#ids + 1] = id end end
                table.sort(ids)
                state.ExpectedProbes = #ids
                state.EmptyCount = state.SnapshotReceived and math.max(0, marketCap - #ids) or 0
                if #ids == 0 and not state.SnapshotReceived then
                    state.Busy = false
                    say("No BoothShows received yet: cannot conclude all stalls are empty. Tap SCAN again.")
                    return
                end
                local got = 0
                for i, id in ipairs(ids) do
                    if not state.Alive or state.Cancel then break end
                    if not occupiedStall(state.Stalls[id]) then
                        state.Probed[id] = {Status = "EMPTY_DURING_SCAN"}
                    else
                        state.ResponseSlot = nil
                        state.Probed[id] = {Status = "SENT", Known = true}
                        local ok, err = pcall(function() BoothRE:FireServer("InteractStall", id) end)
                        if not ok then
                            state.Probed[id].Status = "SEND_ERROR"
                            say("InteractStall #" .. id .. " error: " .. tostring(err))
                        else
                            waitUntil(function() return state.ResponseSlot == id end, 3)
                            if state.ResponseSlot == id then
                                got = got + 1; state.ProbedSuccess = state.ProbedSuccess + 1
                                state.Probed[id].Status = "RESPONSE"
                            else
                                state.Probed[id].Status = "NO_RESPONSE_NOT_EMPTY"
                            end
                        end
                        state.ProbedCount = state.ProbedCount + 1
                    end
                    state.Dirty = true
                    say("DEEP " .. i .. "/" .. #ids .. " | details " .. got .. " | Stall #" .. id .. " " .. state.Probed[id].Status)
                    if i < #ids and state.Alive and not state.Cancel then task.wait(.7) end
                end
                state.Busy = false
                state.AllScanCompleted = not state.Cancel and state.ProbedCount == #ids
                say("Checked " .. state.ProbedCount .. "/" .. #ids .. " occupied stalls | details " .. got .. " | empty "
                    .. (state.SnapshotReceived and tostring(state.EmptyCount) or "unknown") .. ". COPY REPORT shows timeouts.")
                state.Cancel = false; state.Dirty = true
            end)
        end

        ---------------------------------------------------------------- purchase (explicit two-step)
        local function purchaseClick(r)
            if not state.Alive then return end
            if not r or not r.Type then say("NOT BOUGHT: unknown item type."); return end
            if state.Busy or state.PurchaseBusy then say("Scanning/verifying in progress; wait."); return end
            if not marketPlace() then say("Buying only works in the Market Place."); return end
            if not r.ListingId then say("No verified ListingId. COPY REPORT and send the raw keys; never buy by ItemID."); return end
            if not r.Price or r.Price <= 0 or not r.OwnerUserId then say("Missing Price/OwnerUserId; cannot verify. Not bought."); return end
            local pending, now = state.PendingPurchase, os.clock()
            if pending and pending.Ready and pending.Expires > now and pending.Fingerprint == purchaseKey(r) then
                local live = matchingDetail(pending.Selected)
                if not live or not samePurchaseTarget(pending.Selected, r) or not samePurchaseTarget(r, live) then
                    state.PendingPurchase = nil; state.Dirty = true
                    say("Listing changed or sold; purchase cancelled. Scan again.")
                    return
                end
                state.PendingPurchase = nil; state.PurchaseBusy = true
                -- Verified remote signature: Purchase(ownerUserId, listingId)
                local ok, err = pcall(function() BoothRE:FireServer("Purchase", r.OwnerUserId, r.ListingId) end)
                if ok then
                    state.PurchasesSent = state.PurchasesSent + 1
                    say("Purchase request SENT for " .. r.Name .. " at stall #" .. r.Slot .. " for " .. fmt(r.Price) .. "$. Check the game for confirmation; no auto-retry.")
                    state.Full[r.Slot] = nil; state.FullAt[r.Slot] = nil
                else
                    say("Purchase FireServer error: " .. tostring(err) .. "; not retrying.")
                end
                state.Dirty = true
                task.delay(1.2, function() state.PurchaseBusy = false end)
                return
            end
            if pending then
                state.PendingPurchase = nil; state.Dirty = true
                say("Previous purchase request cancelled. Tap BUY again to verify the new listing.")
                return
            end
            local req = {Fingerprint = purchaseKey(r), Selected = r, Slot = r.Slot, Ready = false, Expires = now + 8}
            state.PendingPurchase = req; state.PurchaseBusy = true; state.Dirty = true
            say("Re-reading stall #" .. r.Slot .. " to verify price/ID before buying...")
            task.spawn(function()
                local mark = os.clock()
                local ok, err = pcall(function() BoothRE:FireServer("InteractStall", r.Slot) end)
                if not ok then
                    state.PendingPurchase = nil
                    say("Could not reopen the stall: " .. tostring(err))
                else
                    local verified
                    local deadline = os.clock() + 3
                    while state.Alive and state.PendingPurchase == req and os.clock() < deadline do
                        if (state.FullAt[r.Slot] or 0) >= mark then verified = matchingDetail(r); break end
                        task.wait(.08)
                    end
                    if state.PendingPurchase == req then
                        if verified and verified.Detail and samePurchaseTarget(r, verified) then
                            req.Ready = true; req.Expires = os.clock() + 8
                            say("VERIFIED: " .. r.Name .. " | " .. fmt(r.Price) .. "$ | " .. r.Owner .. ". Tap CONFIRM within 8 seconds to send Purchase.")
                        else
                            state.PendingPurchase = nil
                            say("Could not verify the exact Scroll/price/listing ID. Purchase NOT sent.")
                        end
                    end
                end
                state.PurchaseBusy = false; state.Dirty = true
            end)
        end

        ---------------------------------------------------------------- report
        local function report()
            local all = allRows()
            table.sort(all, function(a, b)
                if a.Slot ~= b.Slot then return a.Slot < b.Slot end
                if a.Id ~= b.Id then return a.Id < b.Id end
                return tostring(a.ListingId) < tostring(b.ListingId)
            end)
            local accepted, mythic, four, good3, occupied, slotsWith = 0, 0, 0, 0, {}, 0
            for _, r in ipairs(all) do
                if not occupied[r.Slot] then occupied[r.Slot] = true; slotsWith = slotsWith + 1 end
                if r.Rarity == 6 then mythic = mythic + 1 end
                if r.StatCount == 4 then four = four + 1 end
                if r.Matched >= 3 then good3 = good3 + 1 end
                if r.Pass then accepted = accepted + 1 end
            end
            local lines = {
                "SCROLL MARKET SCANNER v6.0 (MYTHIC 4 ATTRS; >=3 OF ATK,CR,CD,SKILL,CDR)",
                "PLACE=" .. tostring(game.PlaceId) .. " STALL_CAP=" .. marketCap .. " BOOTH_SHOWS=" .. countOccupied() .. " SLOTS_WITH_SCROLL=" .. slotsWith,
                "FOUND_SCROLLS=" .. #all .. " MYTHIC_R6=" .. mythic .. " FOUR_ATTRS=" .. four .. " THREE_GOOD=" .. good3
                    .. " QUALIFIED=" .. accepted .. " PURCHASE_REQUESTS_SENT=" .. state.PurchasesSent,
                "DEEP_OCCUPIED_PROBED=" .. state.ProbedCount .. "/" .. state.ExpectedProbes .. " DETAIL_RECEIVED=" .. state.ProbedSuccess
                    .. " SCAN_COMPLETE=" .. tostring(state.AllScanCompleted)
                    .. " EMPTY=" .. (state.SnapshotReceived and tostring(state.EmptyCount) or "UNVERIFIED")
                    .. " BOOTH_SHOWS_REPLIES=" .. state.RefreshCount,
                "Note: Empty = no owner in latest BoothShows; timeout is NOT Empty.",
                "TP_DIAG=" .. tostring(state.TpLastDiagnostic),
                "Slot | Type | Seller | ItemId | Rarity | Lines | Good/5 | Groups | Attrs | Price | ListingUUID | Filter | Detail",
            }
            local sampled = {}
            for _, r in ipairs(all) do
                lines[#lines + 1] = table.concat({r.Slot, r.Type, r.Owner, r.Id, tostring(r.Rarity or "UNKNOWN"), r.StatCount, r.Matched,
                    r.MatchedList ~= "" and r.MatchedList or "NONE",
                    #r.Stats > 0 and table.concat(r.Stats, " ; ") or "ATTRIBUTES_UNAVAILABLE",
                    fmt(r.Price), tostring(r.ListingId or "MISSING"), r.Reject, tostring(r.Detail)}, " | ")
                local sample = r.Type ~= "Scroll" and not sampled[r.Type]
                if sample then sampled[r.Type] = true end
                if sample or (r.Type == "Scroll" and (r.Rarity == nil or r.StatCount == 0)) then
                    local fields = {}
                    for k, v in pairs(r.Raw or {}) do fields[#fields + 1] = tostring(k) .. ":" .. type(v) end
                    table.sort(fields)
                    lines[#lines + 1] = "UNPARSED #" .. r.Slot .. " " .. r.Id .. " FIELDS=" .. table.concat(fields, ",")
                end
            end
            lines[#lines + 1] = "SLOT COVERAGE (known/summary_scrolls/deep_scrolls/probe):"
            for id = 1, marketCap do
                local summary, p = state.Stalls[id], state.Probed[id]
                local occ = occupiedStall(summary) and tostring(summary.OwnerName or "OCCUPIED")
                    or (state.SnapshotReceived and "EMPTY" or "UNKNOWN")
                lines[#lines + 1] = string.format("#%02d | %s | summary=%d | detail=%d | %s | TP=%s", id, occ,
                    #extractItems(summary, id, false), #extractItems(state.Full[id], id, true),
                    p and p.Status or "NOT_PROBED", tostring(state.TpSource[id] or "UNRESOLVED"))
            end
            return table.concat(lines, "\n")
        end

        ---------------------------------------------------------------- listing cards
        local function render()
            if not state.Alive or not Page.Parent then return end
            local all, filtered = getFiltered()
            local details = 0
            for _ in pairs(state.Full) do details = details + 1 end
            local pages = math.max(1, math.ceil(#filtered / state.PageSize))
            state.Page = math.clamp(state.Page, 1, pages)
            statsLabel.Text = string.format("OCCUPIED %d/%d | EMPTY %s | DETAIL %d | SCROLLS %d | SHOWN %d",
                countOccupied(), marketCap, state.SnapshotReceived and tostring(state.EmptyCount) or "?", details, #all, #filtered)
            pageLabel.Text = "PAGE " .. state.Page .. "/" .. pages
            clearFrames(list)
            local first = (state.Page - 1) * state.PageSize + 1
            for idx = first, math.min(#filtered, first + state.PageSize - 1) do
                local r = filtered[idx]
                local card = round(new("Frame", list, {Size = UDim2.new(1, 0, 0, 92), LayoutOrder = idx, BorderSizePixel = 0,
                    BackgroundColor3 = idx % 2 == 0 and C.Panel or C.Field}))
                local info = new("Frame", card, {BackgroundTransparency = 1, Size = UDim2.new(1, -138, 1, 0)})
                label(info, r.Name, UDim2.new(0, 8, 0, 4), UDim2.new(1, -8, 0, 20), 13, true)
                local sub = r.Type == "Scroll"
                    and ("#" .. r.Slot .. " · R" .. tostring(r.Rarity or "?") .. " · " .. r.Matched .. "/5 DPS · " .. r.Owner)
                    or ("#" .. r.Slot .. " · " .. r.Type .. (r.Qty and (" x" .. fmt(r.Qty)) or "") .. " · " .. r.Owner)
                label(info, sub, UDim2.new(0, 8, 0, 24), UDim2.new(1, -8, 0, 16), 11, false, false, C.Mute)
                for i = 1, 4 do
                    local text = r.Stats[i] or (r.Type == "Scroll" and "?" or "")
                    label(info, text, UDim2.new(((i - 1) % 2) * .5, 8, 0, 44 + math.floor((i - 1) / 2) * 22),
                        UDim2.new(.5, -10, 0, 20), 11, false, false, isColored(text) and C.Good or C.Mute)
                end
                label(card, fmt(r.Price) .. " $", UDim2.new(1, -132, 0, 4), UDim2.new(0, 126, 0, 24), 14, true)
                local p = state.PendingPurchase
                local isPending = p and p.Fingerprint == purchaseKey(r)
                local action = (not r.ListingId) and "ID?" or (isPending and (p.Ready and "CONFIRM" or "READING") or "BUY")
                button(card, action, UDim2.new(1, -132, 0, 32), UDim2.new(0, 62, 0, 54), function() purchaseClick(r) end,
                    isPending and C.Green or (r.ListingId and C.Blue or C.Red), 11)
                button(card, "TP #" .. r.Slot, UDim2.new(1, -64, 0, 32), UDim2.new(0, 58, 0, 54), function() teleportToStall(r) end, C.Green, 11)
            end
            state.LastRender = os.clock(); state.Dirty = false
        end

        ---------------------------------------------------------------- toolbar actions
        sideBtn("SCAN", requestShows, C.Green)
        sideBtn("DEEP SCAN", deepScan, nil, 104)
        sideBtn("STOP", function()
            state.Cancel = true; state.PendingPurchase = nil; state.Dirty = true
            say("Scan stopped / pending purchase confirmation cancelled.")
        end, C.Red)
        sideBtn("COPY REPORT", function()
            local value = report()
            local copy = (type(setclipboard) == "function" and setclipboard) or (type(toclipboard) == "function" and toclipboard)
            if copy then
                say(pcall(copy, value) and "Report (Scrolls + raw keys) copied." or "Clipboard error; see console.")
            else
                print(value); say("Clipboard unsupported by this executor; see console.")
            end
        end, nil, 116)
        local typeBtn
        typeBtn = sideBtn("TYPE: ALL", function()
            local types = knownTypes()
            local nextIdx = 1
            for i, t in ipairs(types) do if t == state.TypeFilter then nextIdx = i % #types + 1; break end end
            state.TypeFilter = types[nextIdx]; state.Page = 1; state.Dirty = true
            typeBtn.Text = "TYPE: " .. state.TypeFilter:upper()
            say("Showing type: " .. state.TypeFilter .. ". Tap TYPE again to cycle (types appear after SCAN / DEEP SCAN).")
        end, nil, 130)
        local sortBtn
        sortBtn = sideBtn("SORT: QUALITY", function()
            state.Sort = ({QUALITY = "PRICE", PRICE = "REFERENCE", REFERENCE = "NAME", NAME = "QUALITY"})[state.Sort] or "QUALITY"
            sortBtn.Text = "SORT: " .. state.Sort; state.Dirty = true
        end, nil, 140)
        -- STAT COLOR menu (inline di halaman): tap a stat to toggle green on/off (saved when the executor supports writefile)
        local dd = round(new("Frame", Page, {Name = "StatColorMenu", Visible = false, LayoutOrder = 5,
            BackgroundColor3 = C.BG, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 270)}))
        new("UIStroke", dd, {Color = C.Field, Thickness = 1})
        label(dd, "Green stats (tap to toggle)", UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 0, 26), 12, true)
        local ddList = scroller(dd, UDim2.new(0, 4, 0, 28), UDim2.new(1, -8, 1, -68))
        local function buildDropdown()
            for _, o in ipairs(ddList:GetChildren()) do if o:IsA("TextButton") then o:Destroy() end end
            for i, name in ipairs(knownStatLabels()) do
                local b
                local function paint() b.Text = (colorSet[name] and "✔ " or "☐ ") .. name; b.BackgroundColor3 = colorSet[name] and C.Green or C.Field end
                b = button(ddList, "", UDim2.new(), UDim2.new(1, -8, 0, 32), function()
                    colorSet[name] = not colorSet[name] or nil
                    paint(); saveColors(); state.Dirty = true
                end, nil, 12)
                b.LayoutOrder = i
                paint()
            end
        end
        button(dd, "RESET", UDim2.new(0, 4, 1, -38), UDim2.new(.5, -6, 0, 34), function()
            colorSet = {}
            for _, n in ipairs(GOOD5) do colorSet[n] = true end
            saveColors(); buildDropdown(); state.Dirty = true
        end, C.Red, 12)
        button(dd, "CLOSE", UDim2.new(.5, 2, 1, -38), UDim2.new(.5, -6, 0, 34), function() dd.Visible = false end, nil, 12)
        sideBtn("STAT COLOR", function()
            dd.Visible = not dd.Visible
            if dd.Visible then buildDropdown() end
        end, nil, 110)

        local hideBtn
        hideBtn = sideBtn("HIDE PLAYERS: OFF", function()
            setHidePlayers(not perf.HidePlayers)
            hideBtn.Text = "HIDE PLAYERS: " .. (perf.HidePlayers and "ON" or "OFF")
            say("HIDE PLAYERS " .. (perf.HidePlayers and "ON" or "OFF") .. "; booths are never hidden.")
        end, nil, 150)

        ---------------------------------------------------------------- SELL view (Ore ListStack + Scroll List)
        -- Menggantikan daftar pasar saat SELL / LIST dibuka (toolbar & filter tetap di atas).
        local saleView = stack(Page, 7, false)
        saleView.Name = "SalePanel"
        local saleBtnRow = new("Frame", saleView, {BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1})
        local saleStatus = label(saleView, "Tap SCAN ORE or SCAN SCROLLS. Scrolls need their own UUID.",
            UDim2.new(), UDim2.new(1, 0, 0, 36), 12, false, true, C.Mute)
        saleStatus.LayoutOrder = 2
        local bulkBar = new("Frame", saleView, {BackgroundTransparency = 1, Visible = false, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 3})
        local saleRows = stack(saleView, 4)
        local function saleMsg(m) saleStatus.Text = tostring(m):sub(1, 280); print("[STALL_SELL] " .. tostring(m)) end
        local function setSaleMode(scrollMode)
            bulkBar.Visible = scrollMode
            clearFrames(saleRows)
        end
        local function setSellView(on)
            saleView.Visible = on
            marketView.Visible = not on
            if not on then state.Dirty = true end
        end

        local saleBusy, saleStop, saleAttempted, bulkPending, bulkButtons, scrollCache = false, false, {}, nil, {}, {}

        -- Ore
        local function oreBag()
            if not dataUtil then return nil, "DataUtil not ready" end
            local ok, bag = pcall(function() return dataUtil:GetValue(LocalPlayer, {"Ores"}) end)
            if not ok or type(bag) ~= "table" then return nil, "Cannot read Ore Bag" end
            return bag
        end
        local function oreMin(id)
            local d = index["Ore\0" .. id]
            return type(d) == "table" and intRange(d.MinPrice, 1, 1000000000) or nil
        end
        local function numericControl(parent, default, x, w, limit, caption)
            label(parent, caption, UDim2.new(x, 0, 0, 22), UDim2.new(w, 0, 0, 14), 10, false, false, C.Mute)
            local box = new("Frame", parent, {BackgroundTransparency = 1, Position = UDim2.new(x, 0, 0, 38), Size = UDim2.new(w, 0, 0, 46)})
            local f = field(box, "", UDim2.new(.27, 0, 0, 0), UDim2.new(.46, 0, 1, 0), default)
            button(box, "−", UDim2.new(0, 0, 0, 0), UDim2.new(.25, 0, 1, 0), function() f.Text = tostring(math.max(1, (tonumber(f.Text) or 1) - 1)) end, nil, 16)
            button(box, "+", UDim2.new(.75, 0, 0, 0), UDim2.new(.25, 0, 1, 0), function() f.Text = tostring(math.min(limit, (tonumber(f.Text) or 1) + 1)) end, nil, 16)
            return f
        end
        local function sellOre(id, stacksF, qtyF, priceF, mode, btn)
            if saleBusy or not state.Alive then saleMsg("Previous order still sending."); return end
            local stacks, qty = intRange(stacksF.Text, 1, 30), intRange(qtyF.Text, 1, 1000000)
            local unit = mode.Value and oreMin(id) or intRange(priceF.Text, 1, 1000000000)
            if not stacks or not qty or not unit then saleMsg("Min price unverified or invalid input; nothing sent."); return end
            local total = qty * unit
            if total > 1000000000 then saleMsg("Stack total exceeds 1B; nothing sent."); return end
            local bag, err = oreBag()
            if not bag then saleMsg(err); return end
            if (tonumber(bag[id]) or 0) < stacks * qty then saleMsg("Not enough " .. id .. " to sell " .. stacks * qty .. "."); return end
            saleBusy = true; saleStop = false
            btn.Text = "0/" .. stacks
            task.spawn(function()
                local sent = 0
                for i = 1, stacks do
                    if not state.Alive or saleStop then break end
                    local live = oreBag()
                    if not live or (tonumber(live[id]) or 0) < qty then saleMsg("Stopped: not enough in bag or data unreadable."); break end
                    local ok, e = pcall(function() BoothRE:FireServer("ListStack", "Ore", id, qty, total) end)
                    if not ok then saleMsg("Send error: " .. tostring(e)); break end
                    sent = sent + 1; btn.Text = sent .. "/" .. stacks
                    saleMsg("Sent " .. sent .. "/" .. stacks .. " orders for " .. id .. "; server has not confirmed.")
                    if i < stacks then task.wait(.8) end
                end
                saleBusy = false; btn.Text = "SELL"
                if state.Alive then saleMsg("Finished sending " .. sent .. "/" .. stacks .. " orders. Check your stall to confirm.") end
            end)
        end
        local function refreshOre()
            if saleBusy then saleMsg("Sending; wait before rescanning."); return end
            bulkPending = nil
            setSaleMode(false)
            local bag, err = oreBag()
            if not bag then saleMsg(err); return end
            local ids = {}
            for id, count in pairs(bag) do if type(id) == "string" and (tonumber(count) or 0) > 0 then ids[#ids + 1] = id end end
            table.sort(ids)
            for n, id in ipairs(ids) do
                local card = round(new("Frame", saleRows, {BackgroundColor3 = C.Field, BorderSizePixel = 0, LayoutOrder = n, Size = UDim2.new(1, 0, 0, 92)}))
                local mn = oreMin(id)
                label(card, id .. " | Bag: " .. tostring(bag[id]) .. " | Min: " .. tostring(mn or "N/A"), UDim2.new(0, 8, 0, 2), UDim2.new(1, -16, 0, 20), 13, true)
                local mode = {Value = true}
                local stacks = numericControl(card, "1", .01, .21, 30, "Stacks")
                local qty = numericControl(card, tostring(math.min(tonumber(bag[id]) or 1, 10)), .24, .25, 1000000, "Qty / stack")
                label(card, "Price / each", UDim2.new(.52, 0, 0, 22), UDim2.new(.18, 0, 0, 14), 10, false, false, C.Mute)
                local price = field(card, "Price", UDim2.new(.52, 0, 0, 38), UDim2.new(.18, 0, 0, 46), mn and tostring(mn) or "")
                local toggle
                toggle = button(card, "MIN", UDim2.new(.72, 0, 0, 38), UDim2.new(.12, 0, 0, 46), function()
                    mode.Value = not mode.Value
                    toggle.Text = mode.Value and "MIN" or "MANUAL"
                    toggle.BackgroundColor3 = mode.Value and C.Green or C.Blue
                end, C.Green, 11)
                local sell
                sell = button(card, "SELL", UDim2.new(.86, 0, 0, 38), UDim2.new(.13, 0, 0, 46), function()
                    sellOre(id, stacks, qty, price, mode, sell)
                end, nil, 12)
            end
            saleMsg("Read " .. #ids .. " Ore types. Stacks × qty/stack × price/each.")
        end

        -- Scrolls
        local function validUUID(s)
            return type(s) == "string" and #s >= 16 and #s <= 128 and s:match("^[%w_%-]+$") ~= nil and s:lower():sub(1, 7) ~= "scroll_"
        end
        local function scrollResource(v)
            if type(v) ~= "table" then return nil end
            for _, k in ipairs({"ItemID", "ItemId", "ScrollId", "ScrollID", "ResourceId", "BaseId", "Id"}) do
                local id = v[k]
                if type(id) == "string" and id:lower():sub(1, 7) == "scroll_" then return id end
            end
        end
        local function scanOwnedScrolls()
            local items, seen, unresolved, diag, sources = {}, {}, 0, {}, {}
            local function source(name, ok, val)
                local found = ok and type(val) == "table"
                diag[#diag + 1] = name .. ":" .. (found and "OK" or "N/A")
                if found then sources[#sources + 1] = {Name = name, Value = val} end
            end
            if type(ScrollUtil) == "table" then
                for _, m in ipairs({"GetOwned", "GetOwnedScrolls", "GetInventory", "GetScrolls"}) do
                    if type(ScrollUtil[m]) == "function" then
                        local ok, v = pcall(ScrollUtil[m], ScrollUtil, LocalPlayer)
                        if not ok or type(v) ~= "table" then ok, v = pcall(ScrollUtil[m], ScrollUtil) end
                        source("ScrollUtil." .. m, ok, v)
                    end
                end
            else diag[#diag + 1] = "ScrollUtil:MISSING" end
            if dataUtil then
                local paths = {{"Scrolls", "Owned"}, {"Scroll", "Owned"}, {"OwnedScrolls"}, {"Scrolls"}, {"ScrollInventory"}}
                local keys = try(function()
                    local f = RS:FindFirstChild("Enum")
                    local m = f and f:FindFirstChild("KeyString")
                    return m and require(m).ScrollUtil
                end)
                if type(keys) == "table" then
                    local root, owned = keys.Scrolls or keys.Scroll or keys.Name, keys.Owned or keys.Inventory
                    if type(root) == "string" then
                        table.insert(paths, 1, {root})
                        if type(owned) == "string" then table.insert(paths, 1, {root, owned}) end
                    end
                end
                local already = {}
                for _, path in ipairs(paths) do
                    local name = table.concat(path, "/")
                    if not already[name] then
                        already[name] = true
                        local ok, v = pcall(function() return dataUtil:GetValue(LocalPlayer, path) end)
                        source("DataUtil." .. name, ok, v)
                    end
                end
            else diag[#diag + 1] = "DataUtil:MISSING" end
            local function register(raw, key, origin)
                if type(raw) ~= "table" then return false end
                local id = scrollResource(raw)
                if not id and raw.ItemType ~= "Scroll" and raw.Type ~= "Scroll" then return false end
                local uuid
                for _, f in ipairs({"UUID", "Uuid", "UID", "UniqueId", "Guid", "GUID", "InstanceId", "Id"}) do
                    if validUUID(raw[f]) then uuid = raw[f]; break end
                end
                if not uuid and validUUID(key) then uuid = key end
                if not uuid then unresolved = unresolved + 1; return true end
                if seen[uuid] then return true end
                seen[uuid] = true
                local attrs = parseStats(raw)
                local def = id and index["Scroll\0" .. id]
                local premium = 0
                for _, stat in ipairs(attrs) do if hasLabel(stat, PREMIUM4) then premium = premium + 1 end end
                items[#items + 1] = {UUID = uuid, Id = id, Name = id and scrollName(id, raw) or "Scroll (unknown type)", Attrs = attrs,
                    Min = type(def) == "table" and intRange(def.MinPrice, 1, 1000000000) or nil,
                    Max = type(def) == "table" and intRange(def.MaxPrice, 1, 1000000000) or nil,
                    Premium = (#attrs >= 1 and #attrs <= 4) and premium or nil, Source = origin,
                    Blocked = raw.Equipped == true or raw.IsEquipped == true or raw.Locked == true
                        or raw.IsLocked == true or raw.IsListed == true or raw.Listed == true}
                return true
            end
            for _, src in ipairs(sources) do
                local walked = {}
                local function walk(node, key, depth)
                    if depth > 6 or type(node) ~= "table" or walked[node] then return end
                    walked[node] = true
                    if register(node, key, src.Name) then return end
                    for k, v in pairs(node) do
                        if type(v) == "table" then walk(v, k, depth + 1)
                        elseif type(v) == "string" and v:lower():sub(1, 7) == "scroll_" and validUUID(k) then
                            register({ItemId = v, UUID = k}, k, src.Name)
                        end
                    end
                end
                walk(src.Value, nil, 0)
            end
            table.sort(items, function(a, b) if a.Name ~= b.Name then return a.Name < b.Name end return a.UUID < b.UUID end)
            return items, unresolved, table.concat(diag, " | ")
        end
        -- Pricing: 1 premium = Min; 2 = ceil(1.5 x Min); 3 = 4 x Min; 4 = Max. Official Max is a hard cap.
        local function qualityPrice(rec)
            local tier = rec.Premium
            if not tier or tier < 1 or tier > 4 then return nil, "NO_QUALITY_TIER" end
            if not rec.Min then return nil, "MIN_UNAVAILABLE" end
            if rec.Max and rec.Max < rec.Min then return nil, "INVALID_PRICE_RANGE" end
            local price
            if tier == 1 then price = rec.Min
            elseif tier == 2 then price = math.ceil(rec.Min * 1.5)
            elseif tier == 3 then price = rec.Min * 4
            else
                if not rec.Max then return nil, "MAX_UNAVAILABLE" end
                price = rec.Max
            end
            if rec.Max then price = math.min(price, rec.Max) end
            if price > 1000000000 or price < 1 then return nil, "INVALID_PRICE" end
            return price
        end
        local function liveOwnedScroll(rec)
            for _, b in ipairs((scanOwnedScrolls())) do
                if rec.UUID == b.UUID and rec.Id == b.Id and rec.Premium == b.Premium and joinAttrs(rec.Attrs) == joinAttrs(b.Attrs)
                    and rec.Min == b.Min and rec.Max == b.Max and not b.Blocked then return true end
            end
            return false
        end
        local function sendScrollList(rec, price)
            if saleAttempted[rec.UUID] then return false, "Already sent this session" end
            if rec.Blocked then return false, "Scroll locked/equipped/listed" end
            if not validUUID(rec.UUID) then return false, "Invalid UUID" end
            if not intRange(price, 1, 1000000000) then return false, "Invalid price" end
            if rec.Min and price < rec.Min then return false, "Below Min" end
            if rec.Max and price > rec.Max then return false, "Above Max" end
            if not liveOwnedScroll(rec) then return false, "Scroll changed or no longer in bag" end
            local ok, err = pcall(function() BoothRE:FireServer("List", rec.UUID, price) end)
            if not ok then return false, tostring(err) end
            saleAttempted[rec.UUID] = true
            return true
        end
        local updateBulkButtons, refreshScrolls
        local function sellTier(tier)
            if saleBusy or not state.Alive then saleMsg("Another sale is in progress."); return end
            local queue, skipped = {}, 0
            for _, rec in ipairs(scrollCache) do
                if rec.Premium == tier and not rec.Blocked and not saleAttempted[rec.UUID] then
                    local amount = qualityPrice(rec)
                    if amount then queue[#queue + 1] = {Record = rec, Price = amount} else skipped = skipped + 1 end
                end
            end
            if #queue == 0 then saleMsg("Tier " .. tier .. ": no Scrolls with valid Min/Max and UUID."); return end
            local now = os.clock()
            if not bulkPending or bulkPending.Tier ~= tier or bulkPending.Expires < now then
                bulkPending = {Tier = tier, Expires = now + 9}
                updateBulkButtons()
                saleMsg("Ready to list " .. #queue .. " Scrolls with " .. tier .. " premium stats (" .. skipped .. " missing price). TAP AGAIN within 9s to confirm.")
                task.delay(9, function()
                    if bulkPending and bulkPending.Tier == tier and bulkPending.Expires <= os.clock() then
                        bulkPending = nil; updateBulkButtons()
                    end
                end)
                return
            end
            bulkPending = nil; updateBulkButtons()
            saleBusy = true; saleStop = false
            task.spawn(function()
                local sent, failed = 0, 0
                for i, e in ipairs(queue) do
                    if not state.Alive or saleStop then break end
                    local ok, msg = sendScrollList(e.Record, e.Price)
                    if ok then sent = sent + 1 else failed = failed + 1 end
                    saleMsg("TIER " .. tier .. ": sent " .. sent .. "/" .. #queue .. ", skipped " .. failed .. ". " .. (msg or "No server ACK"))
                    if i < #queue and state.Alive and not saleStop then task.wait(.8) end
                end
                saleBusy = false
                if state.Alive then
                    refreshScrolls()
                    saleMsg("Tier " .. tier .. ": sent " .. sent .. "/" .. #queue .. "; skipped " .. failed .. ". Check your stall to confirm listings.")
                end
            end)
        end
        local BULK_TITLES = {"1 STAT = MIN", "2 STATS = 1.5×MIN", "3 STATS = 4×MIN", "4 STATS = MAX"}
        for tier = 1, 4 do
            bulkButtons[tier] = button(bulkBar, BULK_TITLES[tier], UDim2.new((tier - 1) * .25, 2, 0, 2), UDim2.new(.25, -4, 1, -4),
                function() sellTier(tier) end, nil, 11)
        end
        updateBulkButtons = function()
            local counts = {0, 0, 0, 0}
            for _, rec in ipairs(scrollCache) do
                local q = rec.Premium
                if q and q >= 1 and q <= 4 and not rec.Blocked and not saleAttempted[rec.UUID] and qualityPrice(rec) then counts[q] = counts[q] + 1 end
            end
            for tier = 1, 4 do
                local pending = bulkPending and bulkPending.Tier == tier and bulkPending.Expires > os.clock()
                bulkButtons[tier].Text = pending and ("CONFIRM " .. tier .. " STATS") or (BULK_TITLES[tier] .. " (" .. counts[tier] .. ")")
                bulkButtons[tier].BackgroundColor3 = pending and C.Red or C.Blue
            end
        end
        refreshScrolls = function()
            if saleBusy then saleMsg("Sending; wait before rescanning."); return end
            bulkPending = nil
            setSaleMode(true)
            local items, unresolved, diag = scanOwnedScrolls()
            scrollCache = items
            for n, rec in ipairs(items) do
                local card = round(new("Frame", saleRows, {BackgroundColor3 = C.Field, BorderSizePixel = 0, LayoutOrder = n, Size = UDim2.new(1, 0, 0, 96)}))
                local info = new("Frame", card, {BackgroundTransparency = 1, Size = UDim2.new(1, -138, 1, 0)})
                label(info, rec.Name .. "  [" .. tostring(rec.Premium or "?") .. " premium]", UDim2.new(0, 8, 0, 4), UDim2.new(1, -8, 0, 22), 13, true)
                for k = 1, 4 do
                    local stat = rec.Attrs[k] or ""
                    label(info, stat, UDim2.new(((k - 1) % 2) * .5, 8, 0, 30 + math.floor((k - 1) / 2) * 24), UDim2.new(.5, -10, 0, 22), 11,
                        false, false, hasLabel(stat, PREMIUM4) and C.Good or C.Mute)
                end
                local auto = qualityPrice(rec)
                local shown = auto or rec.Min
                local price = field(card, "Price", UDim2.new(1, -132, 0, 6), UDim2.new(0, 126, 0, 30), shown and tostring(shown) or "")
                label(card, rec.Min and ("Min " .. rec.Min .. (rec.Max and (" / Max " .. rec.Max) or "")) or "Min missing",
                    UDim2.new(1, -132, 0, 38), UDim2.new(0, 126, 0, 14), 10, false, false, C.Mute)
                local sell
                sell = button(card, rec.Blocked and "LOCKED" or (saleAttempted[rec.UUID] and "SENT" or "SELL"),
                    UDim2.new(1, -132, 0, 54), UDim2.new(0, 126, 0, 36), function()
                        if saleBusy then saleMsg("Another order is sending."); return end
                        if rec.Blocked or saleAttempted[rec.UUID] then saleMsg("Scroll is locked or already sent this session."); return end
                        local amount = intRange(price.Text, 1, 1000000000)
                        if not amount then saleMsg("Enter a whole price from 1 to 1B."); return end
                        saleBusy = true
                        local ok, err = sendScrollList(rec, amount)
                        saleBusy = false
                        if ok then
                            sell.Text = "SENT"; sell.BackgroundColor3 = C.Green
                            saleMsg("List sent for " .. rec.Name .. " at " .. amount .. ". Check your stall to confirm.")
                        else saleMsg("Not sent: " .. tostring(err)) end
                        updateBulkButtons()
                    end, (rec.Blocked or saleAttempted[rec.UUID]) and C.Red or C.Blue, 12)
            end
            updateBulkButtons()
            saleMsg("Scanned " .. #items .. " Scrolls; " .. unresolved .. " missing UUID. Premium stats: Attack, Skill Damage, Crit Rate, Crit Damage. " .. diag:sub(1, 80))
        end

        local function saleBtn(text, i, cb, tint)
            return button(saleBtnRow, text, UDim2.new(i * .25, 2, 0, 0), UDim2.new(.25, -4, 0, 36), cb, tint, 11)
        end
        saleBtn("SCAN ORE", 0, refreshOre)
        saleBtn("SCAN SCROLLS", 1, refreshScrolls)
        saleBtn("STOP SELLING", 2, function()
            saleStop = true; bulkPending = nil; updateBulkButtons()
            saleMsg("Stopping after the current order; group confirmation cancelled.")
        end, C.Red)
        saleBtn("CLOSE", 3, function() setSellView(false) end)
        sideBtn("SELL / LIST", function()
            setSellView(not saleView.Visible)
            if saleView.Visible and #saleRows:GetChildren() <= 1 then refreshOre() end
        end, C.Green, 110)

        ---------------------------------------------------------------- lifecycle
        for _, item in ipairs({search, minPrice, maxPrice}) do
            state.Conn[#state.Conn + 1] = item:GetPropertyChangedSignal("Text"):Connect(function() state.Page = 1; state.Dirty = true end)
        end
        function state.Stop()
            state.Alive = false; state.Cancel = true; state.PendingPurchase = nil
            saleStop = true
            setHidePlayers(false)
            for _, c in ipairs(state.Conn) do pcall(function() c:Disconnect() end) end
            if env.IronSoulMarketScanner == state then env.IronSoulMarketScanner = nil end
        end
        task.spawn(function()
            while state.Alive do
                task.wait(.35)
                if not Page.Parent then state.Stop(); break end   -- GUI hub ditutup / dimuat ulang
                local p = state.PendingPurchase
                if p and p.Ready and os.clock() > p.Expires then
                    state.PendingPurchase = nil; state.Dirty = true
                    say("Purchase confirmation expired. Tap BUY to re-verify the listing.")
                end
                -- render hanya saat tab Trade sedang terlihat (hemat performa)
                if state.Dirty and Page.Visible and os.clock() - state.LastRender >= .9 then
                    local ok, err = pcall(render)
                    if not ok then warn("[STALL_MARKET] UI error: " .. tostring(err)) end
                end
            end
        end)
        if marketPlace() then
            task.delay(.7, function() if state.Alive then requestShows() end end)
        else
            say("Enter the Market Place, then tap SCAN.")
        end

    end)
    if not ok then
        warn("[XiFil] Gagal membuat tab Trade: " .. tostring(err))
        local msg = "⚠️ Trade: " .. tostring(err)
        if Boot:IsDescendantOf(Page) then Boot.Text = msg else infoCard(msg) end
    end
end)

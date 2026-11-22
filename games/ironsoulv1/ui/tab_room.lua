--------------------------------------------------------------------------------
--// ui/tab_room.lua — S21 Tab 5: Room Hub
--------------------------------------------------------------------------------
local H                   = getgenv().Hub
local EngineConfig        = H.EngineConfig
local Services            = H.Services
local LocalPlayer         = H.LocalPlayer
local Workspace           = H.Workspace
local GameMatchRE         = H.GameMatchRE
local CombatEngine        = H.CombatEngine
local ROOM_WORLD_DISPLAY  = H.ROOM_WORLD_DISPLAY
local ROOM_WORLD_KEY      = H.ROOM_WORLD_KEY
local isCaveWorld         = H.isCaveWorld
local isEndlessTower      = H.isEndlessTower
local getModeLabel        = H.getModeLabel
local CustomNotify        = H.CustomNotify
local CreateTab           = H.CreateTab
local CreateSection       = H.CreateSection
local WorldPlaceRE        = H.WorldPlaceRE
local CreateCycleUI       = H.CreateCycleUI
local CreateDropdownUI    = H.CreateDropdownUI
local CreateButton        = H.CreateButton
local CreateInputUI       = H.CreateInputUI
local CreateToggleUI      = H.CreateToggleUI
local RegisterTranslation = H.RegisterTranslation

-- [S21] TAB 5 — ROOM HUB
--------------------------------------------------------------------------------
local RoomTabPage = CreateTab("🚪 Room", "tabRoom")

-- ── SUB TAB: Room (lama) | Dungeon | Tower ───────────────────────────────────
-- Semua kontrol Room lama tetap memakai nama `RoomPage`, kini menunjuk ke sub halaman "Room".
local SubBar = Instance.new("Frame", RoomTabPage)
SubBar.BackgroundTransparency = 1
SubBar.Size = UDim2.new(1, 0, 0, 30)
SubBar.LayoutOrder = 1

local function MakeSubPage(order)
    local f = Instance.new("Frame", RoomTabPage)
    f.BackgroundTransparency = 1
    f.Size = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y
    f.LayoutOrder = order
    f.Visible = false
    local l = Instance.new("UIListLayout", f)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    l.Padding = UDim.new(0, 6)
    return f
end

local SubRoomPage    = MakeSubPage(2)
local SubDungeonPage = MakeSubPage(3)
local SubTowerPage   = MakeSubPage(4)
local RoomPage       = SubRoomPage

local SubDefs = {
    { id = "room",    key = "subRoom",    text = "🚪 Room",    page = SubRoomPage },
    { id = "dungeon", key = "subDungeon", text = "🏰 Dungeon", page = SubDungeonPage },
    { id = "tower",   key = "subTower",   text = "🗼 Tower",   page = SubTowerPage },
}
local SubButtons, SubShowHooks = {}, {}
local ActiveSub = "room"
local GetThemeColor = H.GetThemeColor

local function PaintSubButtons()
    local primary = GetThemeColor and GetThemeColor("Primary") or Color3.fromRGB(80, 130, 255)
    for _, def in ipairs(SubDefs) do
        local btn = SubButtons[def.id]
        local active = def.id == ActiveSub
        btn.BackgroundColor3 = active and primary or Color3.fromRGB(22, 22, 35)
        btn.TextColor3       = active and Color3.fromRGB(10, 10, 15) or Color3.fromRGB(200, 200, 215)
    end
end

local function SelectSub(id)
    ActiveSub = id
    for _, def in ipairs(SubDefs) do
        def.page.Visible = def.id == id
    end
    PaintSubButtons()
    local hook = SubShowHooks[id]
    if hook then task.spawn(function() pcall(hook) end) end
end

for i, def in ipairs(SubDefs) do
    local btn = Instance.new("TextButton", SubBar)
    btn.Position = UDim2.new((i - 1) / 3, i == 1 and 0 or 2, 0, 0)
    btn.Size = UDim2.new(1 / 3, -4, 1, 0)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 11
    btn.Text = def.text
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    RegisterTranslation(def.key, btn, "Text")
    btn.MouseButton1Click:Connect(function() SelectSub(def.id) end)
    SubButtons[def.id] = btn
end
SelectSub("room")

CreateSection(RoomPage, "Matchmaking Control", "secMatchmake")

local sLblCon = Instance.new("Frame", RoomPage)
sLblCon.BackgroundColor3 = Color3.fromRGB(22,22,35)
sLblCon.Size = UDim2.new(1,0,0,32); sLblCon.BorderSizePixel = 0
Instance.new("UICorner",sLblCon).CornerRadius = UDim.new(0,8)
local statusLbl = Instance.new("TextLabel",sLblCon)
statusLbl.Size = UDim2.new(1,0,1,0)
statusLbl.BackgroundTransparency = 1; statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 11

-- RoomMapping: key → list of rooms
-- Endless1 hanya Room9 & Room10
local RoomMapping = {
    World1   = {"Room1","Room2","Room3","Room4"},
    World2   = {"Room1","Room2","Room3","Room4"},
    World3   = {"Room1","Room2","Room3","Room4"},
    World4   = {"Room1","Room2","Room3","Room4"},
    World5   = {"Room1","Room2","Room3","Room4"},   -- Sakura Village
    Cave1    = {"Room5","Room6","Room7","Room8"},
    Cave2    = {"Room5","Room6","Room7","Room8"},
    Cave3    = {"Room5","Room6","Room7","Room8"},
    Season1  = {"Room9","Room10","Room11","Room12"},
    Endless1 = {"Room9","Room10"},
}

-- buildModeList: Endless Tower → hanya mode 1; Cave → mode 1-5 (Normal); Hell → 6-10; Normal → 1-5
local function buildModeList(worldDisplay, modeType)
    local list = {}
    if isEndlessTower(worldDisplay) then
        table.insert(list, getModeLabel(1))
        return list
    end
    local isCave = isCaveWorld(worldDisplay)
    if isCave then
        for i=1,5 do table.insert(list, getModeLabel(i)) end
    elseif modeType == "Hell" then
        for i=6,10 do table.insert(list, getModeLabel(i)) end
    else
        for i=1,5 do table.insert(list, getModeLabel(i)) end
    end
    return list
end

local function getModeNumber(labelStr)
    local n = tonumber(labelStr:match("^(%d+)")); return n or 1
end

local RoomModeTypeDropdown = nil
local RoomModeDropdown     = nil
local RoomTargetDropdown   = nil

local function updateModeDropdown(worldDisplay, modeType)
    local list = buildModeList(worldDisplay, modeType)
    if RoomModeDropdown then RoomModeDropdown:SetValues(list) end
    EngineConfig.RoomMode = getModeNumber(list[1])
    -- Sync statusLbl setiap kali mode list berubah
    statusLbl.Text       = worldDisplay.." — Mode "..EngineConfig.RoomMode
    statusLbl.TextColor3 = EngineConfig.RoomMode<=5 and Color3.fromRGB(0,255,127) or Color3.fromRGB(255,64,64)
end

-- ── WORLD DROPDOWN ──
_G.RoomWorldDropdown = CreateDropdownUI(RoomPage, "World", ROOM_WORLD_DISPLAY, EngineConfig.RoomWorldDisplay, function(val)
    EngineConfig.RoomWorldDisplay = val
    local key     = ROOM_WORLD_KEY[val] or "World1"
    local endless = isEndlessTower(val)
    local cave    = isCaveWorld(val)
    -- Endless Tower & Cave dikunci ke Normal
    if (cave or endless) and RoomModeTypeDropdown then
        EngineConfig.RoomModeType = "Normal"
        RoomModeTypeDropdown:SetValue("Normal")
    end
    local modeType = (cave or endless) and "Normal" or EngineConfig.RoomModeType
    updateModeDropdown(val, modeType)
    -- Update room list
    local rooms = RoomMapping[key] or {"Room1"}
    if RoomTargetDropdown then RoomTargetDropdown:SetValues(rooms); EngineConfig.RoomTarget = rooms[1] end
    statusLbl.Text       = val.." — Mode "..EngineConfig.RoomMode
    statusLbl.TextColor3 = EngineConfig.RoomMode<=5 and Color3.fromRGB(0,255,127) or Color3.fromRGB(255,64,64)
    -- Endless Tower tidak perlu SelectWorld
    if not endless then
        task.spawn(function() pcall(function() WorldPlaceRE:FireServer("SelectWorld",key,EngineConfig.RoomMode) end) end)
    end
end, "lblRoomWorld")

-- ── MODE TYPE DROPDOWN ──
RoomModeTypeDropdown = CreateDropdownUI(RoomPage, "Mode Type", {"Normal","Hell"}, EngineConfig.RoomModeType, function(val)
    -- Endless Tower tidak menggunakan ModeType
    if isEndlessTower(EngineConfig.RoomWorldDisplay) then return end
    EngineConfig.RoomModeType = val
    updateModeDropdown(EngineConfig.RoomWorldDisplay, val)
end, "lblModeType")
_G.RoomModeTypeDropdown = RoomModeTypeDropdown

-- ── MODE DROPDOWN ──
local initModeList = buildModeList(EngineConfig.RoomWorldDisplay, EngineConfig.RoomModeType)
RoomModeDropdown = CreateDropdownUI(RoomPage, "Mode", initModeList, getModeLabel(EngineConfig.RoomMode), function(val)
    EngineConfig.RoomMode = getModeNumber(val)
    statusLbl.Text = EngineConfig.RoomWorldDisplay.." — Mode "..EngineConfig.RoomMode
    statusLbl.TextColor3 = EngineConfig.RoomMode<=5 and Color3.fromRGB(0,255,127) or Color3.fromRGB(255,64,64)
    task.spawn(function()
        local key = ROOM_WORLD_KEY[EngineConfig.RoomWorldDisplay] or "World1"
        pcall(function() WorldPlaceRE:FireServer("SelectWorld",key,EngineConfig.RoomMode) end)
    end, "lblMode")
end)
_G.RoomModeDropdown = RoomModeDropdown

-- ── PLAYER COUNT DROPDOWN ──
_G.RoomPlayersDropdown = CreateDropdownUI(RoomPage, "Jumlah Player", {1,2,3,4}, EngineConfig.RoomPlayers, function(val)
    EngineConfig.RoomPlayers = tonumber(val)
end, "lblPlayers")

-- ── TARGET ROOM DROPDOWN ──
local initRooms = RoomMapping[ROOM_WORLD_KEY[EngineConfig.RoomWorldDisplay] or "World1"] or {"Room1"}
RoomTargetDropdown = CreateDropdownUI(RoomPage, "Target Room", initRooms, EngineConfig.RoomTarget or initRooms[1], function(val)
    EngineConfig.RoomTarget = val
end, "lblTargetRoom")
_G.RoomTargetDropdown = RoomTargetDropdown

statusLbl.Text = EngineConfig.RoomWorldDisplay.." — Mode "..EngineConfig.RoomMode
statusLbl.TextColor3 = EngineConfig.RoomMode<=5 and Color3.fromRGB(0,255,127) or Color3.fromRGB(255,64,64)

-- ── ROOM SETTINGS: FRIEND ONLY ──
-- ON → panggil ChangeFriendOnly 1x; OFF → panggil ChangeFriendOnly 1x lagi
CreateSection(RoomPage, "Room Settings", "secRoomSettings")
-- _friendOnlyReady: cegah fire saat inisialisasi / SyncAllVisualUI.
-- Setelah ready, setiap perubahan manual user (ON atau OFF) fire 1x ChangeFriendOnly.
-- Load ON  → UI aktif; user tekan OFF → fire 1x  (poin 4 & 5)
-- Load OFF → UI nonaktif; tidak fire otomatis    (poin 6)
-- User tekan ON  → fire 1x                       (poin 2)
-- User tekan OFF → fire 1x                       (poin 3)
local _friendOnlyReady = false
_G.FriendOnlyToggle = CreateToggleUI(RoomPage, "🔒 Friend Only Room", EngineConfig.FriendOnlyRoom, function(v)
    EngineConfig.FriendOnlyRoom = v
    if not _friendOnlyReady then return end
    pcall(function() GameMatchRE:FireServer("ChangeFriendOnly") end)
    if v then CustomNotify("🔒 FRIEND ONLY","Aktif",2)
    else      CustomNotify("🔒 FRIEND ONLY","Nonaktif",2) end
end, "lblFriendOnly")
_friendOnlyReady = true

-- ── MATCH ACTIONS ──
CreateSection(RoomPage, "Match Actions", "secMatchActions")
CreateButton(RoomPage, "🛠️ Create Room", function()
    local key = ROOM_WORLD_KEY[EngineConfig.RoomWorldDisplay] or "World1"
    pcall(function()
        GameMatchRE:FireServer("CreatRoom", key, EngineConfig.RoomMode, EngineConfig.RoomPlayers)
        CustomNotify("MATCHMAKING","Room: "..EngineConfig.RoomWorldDisplay.." [M:"..EngineConfig.RoomMode.."]",3)
    end)
end, "btnCreateRoom")
CreateButton(RoomPage, "🚀 TP Room", function()
    local targetRoom = EngineConfig.RoomTarget or "Room1"
    local mrf = Workspace:FindFirstChild("MatchRoom"); local rf = mrf and mrf:FindFirstChild(targetRoom)
    local tm = rf and rf:FindFirstChild("Touch"); local tp = tm and tm:FindFirstChild("Part")
    if tp and tp:IsA("BasePart") then
        local char = LocalPlayer.Character; local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then CombatEngine.ResetPhysics(hrp); hrp.CFrame = tp.CFrame; CustomNotify("ROOM TP","Ke "..targetRoom,3) end
    else CustomNotify("ROOM ERROR","Room '"..targetRoom.."' tidak ditemukan!",4) end
end, "btnTPRoom")
CreateButton(RoomPage, "🚪 Leave Room", function()
    pcall(function() GameMatchRE:FireServer("LeaveRoom") end)
    CustomNotify("ROOM","Leave Room dikirim.",2)
end, "btnLeaveRoom")

-- ── AUTO JOIN ROOM ──
-- Jika ON: TP Room → Create Room → tunggu 30 detik → ulang
CreateSection(RoomPage, "Auto Room", "secAutoRoom")
_G.AutoJoinRoomToggle = CreateToggleUI(RoomPage, "🔁 Auto Join Room", EngineConfig.AutoJoinRoomActive, function(v)
    EngineConfig.AutoJoinRoomActive = v
    if v then CustomNotify("🔁 AUTO JOIN","TP + Buat Room setiap 30 detik",3)
    else      CustomNotify("🔁 AUTO JOIN","Nonaktif",2) end
end, "lblAutoJoinRoom")

--------------------------------------------------------------------------------
-- SUB TAB: DUNGEON & TOWER (dipindah dari "Iron Soul Dungeon Utility")
-- Semua pengaturan disimpan di EngineConfig (Dg* / Tw*) → ikut Save/Load profil.
-- Tiap sub tab dibungkus pcall supaya kegagalan satu bagian tidak merusak tab lain.
--------------------------------------------------------------------------------
local DS = H.DungeonSys
local T  = H.T

local function Fmt(Template, ...)
    local Args = table.pack(...)
    return (string.gsub(tostring(Template), "{(%d+)}", function(Index)
        return tostring(Args[tonumber(Index)] or "")
    end))
end

local function MakeInfoCard(parent)
    local card = Instance.new("Frame", parent)
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
    lbl.Text = ""
    return lbl
end

local DungeonSyncing = false           -- true saat UI di-set dari config (callback tidak boleh menulis balik)
local SyncFns, LangFns = {}, {}        -- sync dari config / bangun ulang daftar (ganti bahasa)
local UpdateDungeonInfo, UpdateTowerInfo

-- ── Sub tab DUNGEON ──────────────────────────────────────────────────────────
local okDg, errDg = pcall(function()
    if not DS then error("modul dungeon_sys tidak termuat") end
    local D = DS.Dungeon
    local page = SubDungeonPage
    local Ctl = {}
    local WorldMap, DiffMap = {}, {}
    local PlayerNames = { "Solo", "Duo", "Trio", "Quad" }
    local RefreshLists

    CreateSection(page, "Dungeon Status", "secDgStatus")
    local InfoLbl = MakeInfoCard(page)

    UpdateDungeonInfo = function()
        local wid, did = DS.GetWorldId(), DS.GetDifficulty()
        local worldLabel, diffLabel = wid, tostring(did)
        local okE, entry = pcall(DS.Catalog.FindDungeonEntry, wid)
        if okE and entry then worldLabel = tostring(entry.DisplayName) end
        local okD, diffs = pcall(DS.Catalog.GetDifficultyCatalog, wid)
        if okD and type(diffs) == "table" then
            for _, d in ipairs(diffs) do
                if d.Level == did then diffLabel = d.DisplayName; break end
            end
        end
        local rep = D.GetRepeatInfo()
        local lines = {
            Fmt(T("dgInfoStatus"), DS.FormatStatus(D.Status)),
            Fmt(T("dgInfoTarget"), worldLabel, diffLabel),
            Fmt(T("dgInfoPlayers"), tostring(EngineConfig.DgPlayerCount or 1), rep.Done,
                rep.Total > 0 and rep.Total or T("dgUnlimited")),
        }
        local fol = D.GetFollowInfo()
        if fol.Enabled then
            local state
            if not fol.Present then state = T("dgFollowAbsent")
            elseif fol.Remaining then state = Fmt(T("dgFollowCountdown"), math.ceil(fol.Remaining))
            else state = T("dgFollowPresent") end
            table.insert(lines, Fmt(T("dgInfoFollow"), fol.User ~= "" and fol.User or T("dgUserEmpty"), state))
        end
        InfoLbl.Text = table.concat(lines, "\n")
    end

    CreateSection(page, "Auto Start", "secDgAuto")
    Ctl.auto = CreateToggleUI(page, "🏰 Auto Start Dungeon", EngineConfig.DgAutoStart == true, function(v)
        if DungeonSyncing then return end
        EngineConfig.DgAutoStart = v
        D.OnToggle(v)
    end, "lblDgAutoStart")

    Ctl.repeatCount = CreateInputUI(page, "🔁 Repeat match (0 = tanpa batas)", tostring(EngineConfig.DgRepeatCount or 0), false, function(v)
        if DungeonSyncing then return end
        local n = tonumber(v)
        if not n or n ~= n then
            Ctl.repeatCount:SetValue(tostring(EngineConfig.DgRepeatCount or 0))
            return
        end
        n = math.clamp(math.floor(n), 0, 999)
        EngineConfig.DgRepeatCount = n
        Ctl.repeatCount:SetValue(tostring(n))
        D.ResetRepeat()
    end, "lblDgRepeat")
    CreateButton(page, "♻️ Reset Hitungan Repeat", function() D.ResetRepeat() end, "btnDgResetRepeat")

    CreateSection(page, "Target Dungeon", "secDgTarget")
    Ctl.world = CreateDropdownUI(page, "🗺️ Dungeon", { T("dgNoList") }, T("dgNoList"), function(label)
        if DungeonSyncing then return end
        local id = WorldMap[label]
        if id and DS.Catalog.SelectAutoStartWorld(id) then task.spawn(RefreshLists, false) end
    end, "lblDgWorld")
    Ctl.diff = CreateDropdownUI(page, "⚔️ Difficulty", { T("dgNoList") }, T("dgNoList"), function(label)
        if DungeonSyncing then return end
        local level = DiffMap[label]
        if level and DS.Catalog.SelectAutoStartDifficulty(level) then UpdateDungeonInfo() end
    end, "lblDgDiff")
    Ctl.players = CreateCycleUI(page, "👥 Jumlah Player", PlayerNames, PlayerNames[math.clamp(math.floor(tonumber(EngineConfig.DgPlayerCount) or 1), 1, 4)], function(v)
        if DungeonSyncing then return end
        for index, name in ipairs(PlayerNames) do
            if name == v then EngineConfig.DgPlayerCount = index; break end
        end
        UpdateDungeonInfo()
    end, "lblDgPlayers")
    CreateButton(page, "🔄 Refresh Daftar", function()
        task.spawn(RefreshLists, true)
        CustomNotify("🏰 DUNGEON", T("ntListsRefreshed"), 2)
    end, "btnDgRefresh")

    -- Dua mode otomatis, saling eksklusif:
    --   Auto Unlock Map & Difficulty → map terbaru, difficulty 1-5 saja (tanpa Hell)
    --   Auto Latest                  → map terbaru, difficulty tertinggi yang terbuka (Hell ikut)
    CreateSection(page, "Map Terbaru Otomatis", "secDgLatest")
    Ctl.unlock = CreateToggleUI(page, "🔓 Auto Unlock Map & Difficulty (tanpa Hell)", EngineConfig.DgAutoUnlock == true, function(v)
        if DungeonSyncing then return end
        EngineConfig.DgAutoUnlock = v
        if v then
            EngineConfig.DgAutoLatest = false
            DungeonSyncing = true; Ctl.latest:SetValue(false); DungeonSyncing = false
            task.spawn(function() pcall(DS.ApplyAutoSelection); RefreshLists(false) end)
        end
    end, "lblDgAutoUnlock")
    Ctl.latest = CreateToggleUI(page, "⭐ Auto Latest (Hell ikut)", EngineConfig.DgAutoLatest == true, function(v)
        if DungeonSyncing then return end
        EngineConfig.DgAutoLatest = v
        if v then
            EngineConfig.DgAutoUnlock = false
            DungeonSyncing = true; Ctl.unlock:SetValue(false); DungeonSyncing = false
            task.spawn(function() pcall(DS.ApplyAutoSelection); RefreshLists(false) end)
        end
    end, "lblDgAutoLatest")

    CreateSection(page, "Username (tunggu user di server)", "secDgFollow")
    Ctl.follow = CreateToggleUI(page, "👤 Mulai setelah user ada", EngineConfig.DgFollowEnabled == true, function(v)
        if DungeonSyncing then return end
        EngineConfig.DgFollowEnabled = v
        D.ResetFollow()
        UpdateDungeonInfo()
    end, "lblDgFollow")
    Ctl.followUser = CreateInputUI(page, "Username / Display Name", tostring(EngineConfig.DgFollowUser or ""), false, function(v)
        if DungeonSyncing then return end
        local name = string.gsub(tostring(v or ""), "^%s*(.-)%s*$", "%1")
        EngineConfig.DgFollowUser = name
        Ctl.followUser:SetValue(name)
        D.ResetFollow()
        UpdateDungeonInfo()
    end, "lblDgFollowUser")
    Ctl.followDelay = CreateInputUI(page, "⏱️ Delay join (detik)", tostring(EngineConfig.DgFollowDelay or 5), false, function(v)
        if DungeonSyncing then return end
        local n = tonumber(v)
        if not n or n ~= n then
            Ctl.followDelay:SetValue(tostring(EngineConfig.DgFollowDelay or 5))
            return
        end
        n = math.clamp(math.floor(n), 0, 300)
        EngineConfig.DgFollowDelay = n
        Ctl.followDelay:SetValue(tostring(n))
    end, "lblDgFollowDelay")

    CreateSection(page, "Manual", "secDgManual")
    CreateButton(page, "▶️ Start Dungeon Sekarang", function()
        CustomNotify("🏰 DUNGEON", T("ntDgStartNow"), 3)
        task.spawn(function()
            local ok, err = pcall(D.StartNow)
            if not ok then warn("[Dungeon] start: " .. tostring(err)) end
        end)
    end, "btnDgStartNow")

    -- Bangun ulang daftar dungeon/difficulty (hanya yang sudah terbuka)
    RefreshLists = function(force)
        local wid, did = DS.GetWorldId(), DS.GetDifficulty()
        local worldList, newWorldMap, curWorld = {}, {}, nil
        local okW, worlds = pcall(DS.Catalog.GetDungeonCatalog, force == true)
        if okW and type(worlds) == "table" then
            for _, e in ipairs(worlds) do
                if e.Unlocked then
                    local label = tostring(e.DisplayName) .. "  (" .. e.WorldId .. ")"
                    table.insert(worldList, label)
                    newWorldMap[label] = e.WorldId
                    if e.WorldId == wid then curWorld = label end
                end
            end
        end
        local diffList, newDiffMap, curDiff = {}, {}, nil
        local okD, diffs = pcall(DS.Catalog.GetDifficultyCatalog, wid, force == true)
        if okD and type(diffs) == "table" then
            for _, d in ipairs(diffs) do
                if d.Unlocked then
                    table.insert(diffList, d.DisplayName)
                    newDiffMap[d.DisplayName] = d.Level
                    if d.Level == did then curDiff = d.DisplayName end
                end
            end
        end
        if #worldList == 0 then worldList = { T("dgNoList") } end
        if #diffList == 0 then diffList = { T("dgNoList") } end
        -- blok di bawah tidak yield → atomik terhadap thread lain
        local was = DungeonSyncing
        DungeonSyncing = true
        WorldMap, DiffMap = newWorldMap, newDiffMap
        Ctl.world:SetValues(worldList)
        Ctl.world:SetValue(curWorld or wid)
        Ctl.diff:SetValues(diffList)
        Ctl.diff:SetValue(curDiff or tostring(did))
        DungeonSyncing = was
        UpdateDungeonInfo()
    end

    SubShowHooks.dungeon = function() RefreshLists(true) end
    table.insert(LangFns, function() RefreshLists(false) end)
    table.insert(SyncFns, function()
        Ctl.auto:SetValue(EngineConfig.DgAutoStart == true)
        Ctl.repeatCount:SetValue(tostring(EngineConfig.DgRepeatCount or 0))
        Ctl.players:SetValue(PlayerNames[math.clamp(math.floor(tonumber(EngineConfig.DgPlayerCount) or 1), 1, 4)])
        Ctl.unlock:SetValue(EngineConfig.DgAutoUnlock == true)
        Ctl.latest:SetValue(EngineConfig.DgAutoLatest == true)
        Ctl.follow:SetValue(EngineConfig.DgFollowEnabled == true)
        Ctl.followUser:SetValue(tostring(EngineConfig.DgFollowUser or ""))
        Ctl.followDelay:SetValue(tostring(EngineConfig.DgFollowDelay or 5))
    end)
    task.spawn(function() pcall(RefreshLists, false) end)
end)
if not okDg then
    warn("[XiFil] Gagal membuat sub tab Dungeon: " .. tostring(errDg))
    MakeInfoCard(SubDungeonPage).Text = "⚠️ Dungeon: " .. tostring(errDg)
end

-- ── Sub tab TOWER ────────────────────────────────────────────────────────────
local okTw, errTw = pcall(function()
    if not DS then error("modul dungeon_sys tidak termuat") end
    local Tw = DS.Tower
    local page = SubTowerPage
    local Ctl = {}
    local RoundMap, WeaponMap = {}, {}
    local RefreshTowerLists

    CreateSection(page, "Tower Status", "secTwStatus")
    local InfoLbl = MakeInfoCard(page)

    UpdateTowerInfo = function()
        local lines = { Fmt(T("twInfoStatus"), DS.FormatStatus(Tw.Status)) }
        local okI, info = pcall(Tw.GetInfo)
        if okI and type(info) == "table" then
            table.insert(lines, Fmt(T("twInfoRound"), info.Record, info.NextStart))
        end
        table.insert(lines, Fmt(T("twInfoWeapon"), DS.FormatStatus(Tw.WeaponStatus)))
        table.insert(lines, T("twInfoMode"))
        InfoLbl.Text = table.concat(lines, "\n")
    end

    CreateSection(page, "Auto", "secTwAuto")
    Ctl.auto = CreateToggleUI(page, "🗼 Auto Join Endless Tower", EngineConfig.TwAuto == true, function(v)
        if DungeonSyncing then return end
        EngineConfig.TwAuto = v
        Tw.OnToggle(v)
    end, "lblTwAuto")
    Ctl.round = CreateDropdownUI(page, "🔢 Starting Round", { T("twHighestUnlocked") }, T("twHighestUnlocked"), function(label)
        if DungeonSyncing then return end
        local round = RoundMap[label]
        if round ~= nil then
            EngineConfig.TwStartRound = round
            UpdateTowerInfo()
        end
    end, "lblTwRound")
    Ctl.weapon = CreateDropdownUI(page, "🗡️ Extra Weapon", { T("twWeaponAuto") }, T("twWeaponAuto"), function(label)
        if DungeonSyncing then return end
        local uuid = WeaponMap[label]
        if uuid ~= nil then
            EngineConfig.TwWeapon = uuid
            Tw.ResetWeaponRequest()
            UpdateTowerInfo()
        end
    end, "lblTwWeapon")
    CreateButton(page, "🔄 Refresh Senjata", function()
        task.spawn(RefreshTowerLists)
        CustomNotify("🗼 TOWER", T("ntListsRefreshed"), 2)
    end, "btnTwRefresh")

    RefreshTowerLists = function()
        -- Round
        local highestLabel = T("twHighestUnlocked")
        local roundList, newRoundMap = { highestLabel }, { [highestLabel] = 0 }
        local okH, highest = pcall(function() return (Tw.GetHighest()) end)
        if okH and type(highest) == "number" then
            for round = 1, 196, 5 do
                if round <= highest then
                    local label = Fmt(T("twRoundN"), round)
                    table.insert(roundList, label)
                    newRoundMap[label] = round
                end
            end
        end
        local cfgRound = DS.GetTowerStartRound()
        local curRound = cfgRound == 0 and highestLabel or Fmt(T("twRoundN"), cfgRound)

        -- Senjata
        local autoLabel = T("twWeaponAuto")
        local weaponList, newWeaponMap = { autoLabel }, { [autoLabel] = "" }
        local wanted = tostring(EngineConfig.TwWeapon or "")
        local curWeapon, found = autoLabel, wanted == ""
        local okW, options = pcall(Tw.GetWeaponOptions)
        if okW and type(options) == "table" then
            for _, option in ipairs(options) do
                local label = option.Label
                if newWeaponMap[label] ~= nil then label = label .. " #" .. tostring(#weaponList) end
                table.insert(weaponList, label)
                newWeaponMap[label] = option.UUID
                if option.UUID == wanted then curWeapon, found = label, true end
            end
        end
        if not found then curWeapon = T("twWeaponFallback") end

        local was = DungeonSyncing
        DungeonSyncing = true
        RoundMap, WeaponMap = newRoundMap, newWeaponMap
        Ctl.round:SetValues(roundList)
        Ctl.round:SetValue(curRound)
        Ctl.weapon:SetValues(weaponList)
        Ctl.weapon:SetValue(curWeapon)
        DungeonSyncing = was
        UpdateTowerInfo()
    end

    SubShowHooks.tower = function() RefreshTowerLists() end
    table.insert(LangFns, function() RefreshTowerLists() end)
    table.insert(SyncFns, function()
        Ctl.auto:SetValue(EngineConfig.TwAuto == true)
    end)
    task.spawn(function() pcall(RefreshTowerLists) end)
end)
if not okTw then
    warn("[XiFil] Gagal membuat sub tab Tower: " .. tostring(errTw))
    MakeInfoCard(SubTowerPage).Text = "⚠️ Tower: " .. tostring(errTw)
end

-- ── Sinkronisasi setelah load profil (dipanggil ui_sync) ─────────────────────
H.SyncDungeonUI = function()
    if DS then pcall(DS.SanitizeConfig) end
    DungeonSyncing = true
    for _, fn in ipairs(SyncFns) do pcall(fn) end
    DungeonSyncing = false
    if DS then
        pcall(DS.Dungeon.OnToggle, EngineConfig.DgAutoStart == true)
        pcall(DS.Tower.OnToggle, EngineConfig.TwAuto == true)
    end
    for _, fn in ipairs(LangFns) do
        task.spawn(function() pcall(fn) end)
    end
end

-- ── Refresh info: saat status berubah (digabung/ditunda) + tiap detik ────────
local function UpdateVisibleInfo()
    if not (RoomTabPage.Parent and RoomTabPage.Visible) then return end
    if ActiveSub == "dungeon" and UpdateDungeonInfo then pcall(UpdateDungeonInfo)
    elseif ActiveSub == "tower" and UpdateTowerInfo then pcall(UpdateTowerInfo) end
end

if DS then
    local Prev = DS.UIHook.Refresh
    local Pending = false
    DS.UIHook.Refresh = function()
        if Prev then Prev() end
        if Pending then return end
        Pending = true
        task.defer(function()
            Pending = false
            UpdateVisibleInfo()
        end)
    end
end

task.spawn(function()
    local LastLang = H.CurrentLang
    while RoomTabPage.Parent do
        task.wait(1)
        if RoomTabPage.Visible then
            PaintSubButtons()
            if H.CurrentLang ~= LastLang then       -- ganti bahasa: daftar dropdown dibangun ulang
                LastLang = H.CurrentLang
                for _, fn in ipairs(LangFns) do
                    task.spawn(function() pcall(fn) end)
                end
            end
            UpdateVisibleInfo()
        end
    end
end)


--------------------------------------------------------------------------------

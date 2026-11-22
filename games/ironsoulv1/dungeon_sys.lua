--------------------------------------------------------------------------------
--// dungeon_sys.lua — Auto Start Dungeon, Endless Tower (solo), Pets (hatch + expedition)
-- Dipindah dari "Iron Soul Dungeon Utility (standalone)"; logic sama, tetapi semua
-- pengaturan kini disimpan di EngineConfig (ikut Save/Load profil). Auto Potion TIDAK
-- ikut dipindah karena sudah punya tab Auto Potion sendiri. Dungeon Spy (hook remote)
-- juga tidak dipindah (hanya alat debug).
--
-- Status ditulis sebagai KUNCI terjemahan + argumen ({1}, {2}, ...) supaya UI bisa
-- menampilkannya dalam bahasa yang sedang dipilih (H.T).
--------------------------------------------------------------------------------
local H            = getgenv().Hub
local EngineConfig = H.EngineConfig
local Workspace    = game:GetService("Workspace")
local Players      = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer  = H.LocalPlayer or Players.LocalPlayer

-- Instance lama (bundle dijalankan ulang) otomatis berhenti: semua loop memeriksa token ini
local TOKEN = {}
getgenv().__XiFilDungeonSysToken = TOKEN
local function Alive()
    return getgenv().__XiFilDungeonSysToken == TOKEN
end

--------------------------------------------------------------------------------
-- CONFIG: pembaca yang toleran (isi config bisa rusak / hasil edit manual)
--------------------------------------------------------------------------------
local function CfgBool(Key)
    return EngineConfig[Key] == true
end

local function CfgInt(Key, Min, Max, Default)
    local Number = tonumber(EngineConfig[Key])
    if not Number or Number ~= Number then
        Number = Default
    end
    return math.clamp(math.floor(Number), Min, Max)
end

local function CfgStr(Key, Default)
    local Value = EngineConfig[Key]
    if type(Value) == "string" then
        return Value
    end
    return Default
end

local function Trim(Text)
    return (string.gsub(tostring(Text or ""), "^%s*(.-)%s*$", "%1"))
end

local function GetWorldId()
    local Value = Trim(CfgStr("DgWorldId", "World3"))
    return Value ~= "" and Value or "World3"
end
local function GetDifficulty() return CfgInt("DgDifficulty", 1, 999, 10) end
local function GetPlayers()    return CfgInt("DgPlayerCount", 1, 4, 1) end
local function GetRepeatTotal() return CfgInt("DgRepeatCount", 0, 999, 0) end
local function GetFollowUser() return Trim(CfgStr("DgFollowUser", "")) end
local function GetFollowDelay() return CfgInt("DgFollowDelay", 0, 300, 5) end

local function GetTowerStartRound()
    local Round = CfgInt("TwStartRound", 0, 196, 0)
    if Round > 0 then
        Round = math.floor((Round - 1) / 5) * 5 + 1
    end
    return Round
end

-- "2,3,4" (atau tabel angka) -> { 2, 3, 4 } terurut, unik, dalam 1..MaxSlot
local function ParseSlots(Value, MaxSlot)
    MaxSlot = math.max(1, math.floor(tonumber(MaxSlot) or 4))
    local Out, Seen = {}, {}
    local function Add(Raw)
        local Slot = tonumber(Raw)
        if Slot and Slot == math.floor(Slot) and Slot >= 1 and Slot <= MaxSlot and not Seen[Slot] then
            Seen[Slot] = true
            table.insert(Out, Slot)
        end
    end
    if type(Value) == "string" then
        for Token in string.gmatch(Value, "%d+") do
            Add(Token)
        end
    elseif type(Value) == "table" then
        for _, Raw in ipairs(Value) do
            Add(Raw)
        end
    end
    table.sort(Out)
    return Out
end

local function SlotsToString(List)
    return table.concat(List, ",")
end

-- Rapikan nilai di EngineConfig (dipanggil saat start & setelah load profil)
local function SanitizeConfig()
    EngineConfig.DgAutoStart   = CfgBool("DgAutoStart")
    EngineConfig.DgWorldId     = GetWorldId()
    EngineConfig.DgDifficulty  = GetDifficulty()
    EngineConfig.DgPlayerCount = GetPlayers()
    EngineConfig.DgAutoUnlock  = CfgBool("DgAutoUnlock")
    EngineConfig.DgAutoLatest  = CfgBool("DgAutoLatest")
    if EngineConfig.DgAutoUnlock and EngineConfig.DgAutoLatest then
        EngineConfig.DgAutoLatest = false      -- kedua mode saling eksklusif
    end
    EngineConfig.DgRepeatCount   = GetRepeatTotal()
    EngineConfig.DgFollowEnabled = CfgBool("DgFollowEnabled")
    EngineConfig.DgFollowUser    = GetFollowUser()
    EngineConfig.DgFollowDelay   = GetFollowDelay()
    EngineConfig.TwAuto          = CfgBool("TwAuto")
    EngineConfig.TwStartRound    = GetTowerStartRound()
    EngineConfig.TwWeapon        = CfgStr("TwWeapon", "")
    EngineConfig.PetHatchAuto    = CfgBool("PetHatchAuto")
    EngineConfig.PetExpDispatch  = CfgBool("PetExpDispatch")
    EngineConfig.PetExpClaim     = CfgBool("PetExpClaim")
    EngineConfig.PetExpSlots     = SlotsToString(ParseSlots(EngineConfig.PetExpSlots, 99))
end
SanitizeConfig()

--------------------------------------------------------------------------------
-- STATUS (kunci terjemahan + argumen)
--------------------------------------------------------------------------------
local UIHook = { Refresh = nil }
local function Changed()
    if UIHook.Refresh then
        pcall(UIHook.Refresh)
    end
end

local function MakeStatus(Key, ...)
    return { key = Key, args = table.pack(...) }
end

local function SameStatus(A, B)
    if not A or not B or A.key ~= B.key or A.args.n ~= B.args.n then
        return false
    end
    for Index = 1, A.args.n do
        if tostring(A.args[Index]) ~= tostring(B.args[Index]) then
            return false
        end
    end
    return true
end

local function FormatStatus(Status)
    if not Status then
        return ""
    end
    local Template = H.T(Status.key)
    return (string.gsub(Template, "{(%d+)}", function(Index)
        return tostring(Status.args[tonumber(Index)] or "")
    end))
end

--------------------------------------------------------------------------------
-- HELPER FRAMEWORK
--------------------------------------------------------------------------------
local function WaitChild(Parent, Name, Timeout)
    local Child = Parent:WaitForChild(Name, Timeout or 5)
    if not Child then
        error("tidak ditemukan: " .. tostring(Name))
    end
    return Child
end

local FrameworkModule = nil
local WorldRemoteEvent = nil
local GameMatchRemoteEvent = nil
local GameEnumModule = nil

local function GetFrameworkModule()
    if not FrameworkModule then
        FrameworkModule = require(WaitChild(ReplicatedStorage, "Framework", 10))
    end
    return FrameworkModule
end

local function GetWorldRemoteEvent()
    if not WorldRemoteEvent then
        WorldRemoteEvent = H.WorldPlaceRE
        if not WorldRemoteEvent then
            local Framework = WaitChild(ReplicatedStorage, "Framework", 10)
            WorldRemoteEvent = WaitChild(WaitChild(WaitChild(WaitChild(Framework, "Gameplay"), "WorldPlace"),
                "WorldUtil"), "RemoteEvent")
        end
    end
    return WorldRemoteEvent
end

local function GetGameMatchRemoteEvent()
    if not GameMatchRemoteEvent then
        GameMatchRemoteEvent = H.GameMatchRE or WaitChild(WaitChild(ReplicatedStorage, "Remotes", 10), "GameMatchRE")
    end
    return GameMatchRemoteEvent
end

local function GetGameEnum()
    if not GameEnumModule then
        GameEnumModule = require(WaitChild(WaitChild(ReplicatedStorage, "Enum", 10), "GameEnum"))
    end
    return GameEnumModule
end

local function IsInLobby()
    return Workspace:FindFirstChild("MatchRoom") ~= nil and Workspace:FindFirstChild("WorldEnemys") == nil and
               Workspace:FindFirstChild("DragonEgg") == nil
end

--------------------------------------------------------------------------------
-- DUNGEON CATALOG
--------------------------------------------------------------------------------
local Dungeon = {
    Status = MakeStatus("dgSt_off"),
    RepeatDone = 0,
    -- Auto Join Room (tab Room lama) dan Auto Start Dungeon sama-sama membuat room: jangan jalan bersamaan
    ExternalBlock = function()
        return EngineConfig.AutoJoinRoomActive == true
    end
}

local function SetTarget(WorldId, Difficulty)
    EngineConfig.DgWorldId = WorldId
    EngineConfig.DgDifficulty = Difficulty
    Changed()
end

local DungeonCatalog = (function()
    local Catalog = {}
    local CachedDungeons = nil
    local CachedDifficulties = {}

    local function GetWorldConfig()
        return require(WaitChild(WaitChild(WaitChild(ReplicatedStorage, "Configs", 10), "World"), "ResWorld"))
    end

    local function TranslateConfigName(NameKey, Fallback)
        local DisplayName = nil
        pcall(function()
            DisplayName = GetFrameworkModule().Modules.TranslationUtil:TranslateByKey(NameKey)
        end)
        if type(DisplayName) == "string" and DisplayName ~= "" and DisplayName ~= NameKey then
            return DisplayName
        end
        return tostring(Fallback or NameKey or "Unknown")
    end

    function Catalog.GetDungeonCatalog(ForceRefresh)
        if CachedDungeons and not ForceRefresh then
            return CachedDungeons
        end

        local ResWorld = GetWorldConfig()
        local WorldUtil = GetFrameworkModule().Modules.WorldUtil
        local Result = {}
        for _, WorldKey in ipairs(ResWorld.__index or {}) do
            local Info = ResWorld[WorldKey]
            if type(Info) == "table" and Info.Mode ~= "Lobby" then
                local WorldId = tostring(Info.Id or WorldKey)
                local Unlocked = false
                pcall(function()
                    Unlocked = WorldUtil:IsUnlockWorld(LocalPlayer, WorldId, 1) == true
                end)
                table.insert(Result, {
                    WorldId = WorldId,
                    DisplayName = TranslateConfigName(Info.Name, WorldId),
                    Sort = tonumber(Info.Sort) or math.huge,
                    Unlocked = Unlocked,
                    Info = Info
                })
            end
        end
        table.sort(Result, function(A, B)
            if A.Sort == B.Sort then
                return A.WorldId < B.WorldId
            end
            return A.Sort < B.Sort
        end)
        CachedDungeons = Result
        return Result
    end

    function Catalog.GetDifficultyCatalog(WorldId, ForceRefresh)
        if CachedDifficulties[WorldId] and not ForceRefresh then
            return CachedDifficulties[WorldId]
        end

        local Framework = GetFrameworkModule()
        local WorldUtil = Framework.Modules.WorldUtil
        local RarityTiers = Framework.Modules.RarityTiers
        local Result = {}
        local Seen = {}

        local function AddDifficulty(DiffLevel)
            DiffLevel = tonumber(DiffLevel)
            if not DiffLevel or Seen[DiffLevel] then
                return
            end
            local Success, DiffInfo = pcall(function()
                return WorldUtil:GetWorldDiffInfo(WorldId, DiffLevel)
            end)
            if not Success or type(DiffInfo) ~= "table" then
                return
            end
            Seen[DiffLevel] = true
            local NameSuccess, DifficultyName = pcall(function()
                return RarityTiers:GetDifficultyName(DiffInfo.Difficulty)
            end)
            if not NameSuccess or type(DifficultyName) ~= "string" or not string.find(DifficultyName, "%S") or
                tonumber(DifficultyName) then
                return
            end
            if DiffInfo.Style == "Hell" then
                DifficultyName = "Hell (" .. DifficultyName .. ")"
            end
            DifficultyName = "[" .. tostring(DiffLevel) .. "] " .. DifficultyName
            local Unlocked = false
            pcall(function()
                Unlocked = WorldUtil:IsUnlockWorld(LocalPlayer, WorldId, DiffLevel) == true
            end)
            table.insert(Result, {
                Level = DiffLevel,
                DisplayName = DifficultyName,
                Unlocked = Unlocked,
                Info = DiffInfo
            })
        end

        for DiffLevel = 1, 10 do
            AddDifficulty(DiffLevel)
        end
        local Success, HellList = pcall(function()
            return WorldUtil:GetWorldStyleList(WorldId, "Hell")
        end)
        if Success then
            for _, HellInfo in ipairs(HellList or {}) do
                AddDifficulty(HellInfo.DiffLevel)
            end
        end
        table.sort(Result, function(A, B)
            return A.Level < B.Level
        end)
        CachedDifficulties[WorldId] = Result
        return Result
    end

    function Catalog.FindDungeonEntry(WorldId, ForceRefresh)
        for _, Entry in ipairs(Catalog.GetDungeonCatalog(ForceRefresh)) do
            if Entry.WorldId == WorldId then
                return Entry
            end
        end
    end

    function Catalog.FindHighestUnlockedDifficulty(WorldId, ForceRefresh)
        local Selected = nil
        for _, Entry in ipairs(Catalog.GetDifficultyCatalog(WorldId, ForceRefresh)) do
            if Entry.Unlocked and (not Selected or Entry.Level > Selected.Level) then
                Selected = Entry
            end
        end
        return Selected
    end

    function Catalog.ValidateAutoStartSelection(PreferHighest)
        local DungeonEntry = Catalog.FindDungeonEntry(GetWorldId(), true)
        if not DungeonEntry or not DungeonEntry.Unlocked then
            DungeonEntry = nil
            for _, Entry in ipairs(Catalog.GetDungeonCatalog()) do
                if Entry.Unlocked then
                    DungeonEntry = Entry
                    break
                end
            end
        end
        if not DungeonEntry then
            return false
        end

        local CandidateWorldId = DungeonEntry.WorldId
        local CandidateDifficulty = nil
        if not PreferHighest then
            for _, Entry in ipairs(Catalog.GetDifficultyCatalog(CandidateWorldId, true)) do
                if Entry.Level == GetDifficulty() and Entry.Unlocked then
                    CandidateDifficulty = Entry
                    break
                end
            end
        end
        CandidateDifficulty = CandidateDifficulty or Catalog.FindHighestUnlockedDifficulty(CandidateWorldId)
        if not CandidateDifficulty then
            return false
        end

        if GetWorldId() ~= CandidateWorldId or GetDifficulty() ~= CandidateDifficulty.Level then
            SetTarget(CandidateWorldId, CandidateDifficulty.Level)
        end
        return true
    end

    function Catalog.SelectAutoStartWorld(WorldId)
        local Entry = Catalog.FindDungeonEntry(WorldId, true)
        if not Entry or not Entry.Unlocked then
            return false
        end
        local CandidateDifficulty = Catalog.FindHighestUnlockedDifficulty(Entry.WorldId, true)
        if not CandidateDifficulty then
            return false
        end
        SetTarget(Entry.WorldId, CandidateDifficulty.Level)
        return true
    end

    function Catalog.SelectAutoStartDifficulty(DiffLevel)
        for _, Entry in ipairs(Catalog.GetDifficultyCatalog(GetWorldId(), true)) do
            if Entry.Level == DiffLevel and Entry.Unlocked then
                SetTarget(GetWorldId(), Entry.Level)
                return true
            end
        end
        return false
    end

    return Catalog
end)()

--------------------------------------------------------------------------------
-- HELPER GUI (klik tombol, cek visibilitas)
--------------------------------------------------------------------------------
local function IsGuiVisible(Obj)
    if not Obj or not Obj.Parent then
        return false
    end
    if Obj:IsA("GuiObject") and not Obj.Visible then
        return false
    end
    local Parent = Obj.Parent
    while Parent and Parent ~= game do
        if Parent:IsA("GuiObject") and not Parent.Visible then
            return false
        end
        Parent = Parent.Parent
    end
    return true
end

local function TryFireGuiButtonSignals(Button)
    if not firesignal or not Button:IsA("GuiButton") then
        return false
    end
    local Fired = false
    for _, Signal in ipairs({
        Button.MouseButton1Down,
        Button.MouseButton1Click,
        Button.Activated
    }) do
        local Success = pcall(firesignal, Signal)
        Fired = Fired or Success
    end
    return Fired
end

local function ClickGuiButton(Button)
    if not Button or not Button:IsA("GuiObject") or not IsGuiVisible(Button) then
        return false
    end
    if TryFireGuiButtonSignals(Button) then
        return true
    end

    local VirtualInputManager = game:GetService("VirtualInputManager")
    local Position = Button.AbsolutePosition + (Button.AbsoluteSize / 2)
    VirtualInputManager:SendMouseButtonEvent(Position.X, Position.Y, 0, true, game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(Position.X, Position.Y, 0, false, game, 0)
    return true
end

local function GetMainGuiChild(Name)
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local MainGui = PlayerGui and PlayerGui:FindFirstChild("MainGui")
    return MainGui and MainGui:FindFirstChild(Name)
end

local function WaitForGui(Getter, Timeout)
    local StartedAt = os.clock()
    repeat
        local Gui = Getter()
        if Gui and Gui.Visible then
            return Gui
        end
        task.wait(0.1)
    until (os.clock() - StartedAt) >= Timeout
    return nil
end

local function FindDeep(Root, Name)
    return Root and (Root:FindFirstChild(Name) or Root:FindFirstChild(Name, true))
end

-- Counter "Max players" (Control.Match.MatchCount + Minus/Plus). Minus dulu (angka berputar);
-- Plus hanya dipakai kalau Minus tidak menggeser angka.
local function SetMatchCountTo(Screen, Want)
    local Control = Screen:FindFirstChild("Control")
    local Match = Control and Control:FindFirstChild("Match")
    local Count = (Match and Match:FindFirstChild("MatchCount")) or FindDeep(Screen, "MatchCount")
    local Minus = (Match and Match:FindFirstChild("MinusButton")) or FindDeep(Screen, "MinusButton")
    local Plus = (Match and Match:FindFirstChild("PlusButton")) or FindDeep(Screen, "PlusButton")
    if not Count or not (Minus or Plus) then
        return false, "MatchCount/MinusButton tidak ketemu"
    end
    local function Current()
        return tonumber(string.match(tostring(Count.Text), "%d+"))
    end
    local UseMinus = Minus ~= nil
    for _ = 1, 8 do
        local Cur = Current()
        if Cur == Want then
            return true
        end
        if not ClickGuiButton(UseMinus and Minus or Plus) then
            return false, "klik tombol gagal"
        end
        task.wait(0.15)
        if UseMinus and Plus and Current() == Cur then
            UseMinus = false
        end
    end
    return Current() == Want, "angka tertahan di " .. tostring(Current())
end

local function DescribeCountControls(Root)
    local Parts = {}
    pcall(function()
        for _, Obj in ipairs(Root:GetDescendants()) do
            local Name = string.lower(Obj.Name)
            if #Parts < 14 and (string.find(Name, "count", 1, true) or string.find(Name, "minus", 1, true) or
                string.find(Name, "plus", 1, true) or string.find(Name, "player", 1, true) or
                string.find(Name, "people", 1, true) or string.find(Name, "member", 1, true)) then
                table.insert(Parts, Obj.Name .. "(" .. Obj.ClassName .. ")")
            end
        end
    end)
    return #Parts > 0 and table.concat(Parts, ", ") or "none"
end

--------------------------------------------------------------------------------
-- AUTO START DUNGEON
--------------------------------------------------------------------------------
local LastAutoStartDungeonAt = 0
local LastAutoStartRetryAt = 0
local AutoStartDungeonDelay = 10.0
local AutoStartRetryDelay = 3.0
local AutoStartPending = false
-- menandai room sudah dibuat dan kita sedang menunggu masuk dungeon (cegah buat room berulang)
local AutoStartRoomWait = {Active = false, Since = 0, Timeout = 60}

-- Repeat: 1 match per masuk lobby. Manual = start-now tidak dihitung; Counted = request terakhir sudah dihitung.
local Repeat = {Manual = false, Counted = false}
-- Username: tunggu user ada di server yang sama, lalu hitung mundur FollowDelay detik.
local Follow = {Since = nil}

function Dungeon.IsEnabled()
    return CfgBool("DgAutoStart")
end

function Dungeon.IsBlocked()
    local Success, Result = pcall(Dungeon.ExternalBlock)
    return Success and Result == true
end

-- Start manual (tombol "Start Dungeon Now") boleh jalan walau Auto Start OFF, maksimal 60 detik
local function ManualActive()
    return Dungeon.ManualUntil ~= nil and os.clock() < Dungeon.ManualUntil
end

function Dungeon.GetRepeatInfo()
    return {Done = Dungeon.RepeatDone, Total = GetRepeatTotal()}
end

function Follow.Find()
    local Name = string.lower(GetFollowUser())
    if Name == "" then
        return nil
    end
    for _, Player in ipairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer and (string.lower(Player.Name) == Name or string.lower(Player.DisplayName) == Name) then
            return Player
        end
    end
    return nil
end

function Dungeon.GetFollowInfo()
    local Info = {Enabled = CfgBool("DgFollowEnabled"), User = GetFollowUser(), Present = false, Remaining = nil}
    if not Info.Enabled then
        return Info
    end
    Info.Present = Follow.Find() ~= nil
    if Info.Present and Follow.Since then
        Info.Remaining = math.max(0, GetFollowDelay() - (os.clock() - Follow.Since))
    end
    return Info
end

-- true bila user sudah ada di server dan hitung mundur selesai (atau fitur mati).
-- Bila belum: false, kunciStatus, argumen
function Follow.Gate()
    if not CfgBool("DgFollowEnabled") then
        Follow.Since = nil
        return true
    end
    if GetFollowUser() == "" then
        return false, "dgSt_followEmpty"
    end
    if not Follow.Find() then
        Follow.Since = nil
        return false, "dgSt_followWaiting", GetFollowUser()
    end
    Follow.Since = Follow.Since or os.clock()
    if os.clock() - Follow.Since < GetFollowDelay() then
        return false, "dgSt_followCountdown"
    end
    return true
end

local AutoLobbyStartGate = {
    GraceDelay = 8,
    ReadySince = nil
}

function AutoLobbyStartGate.IsReady()
    if not IsInLobby() then
        AutoLobbyStartGate.ReadySince = nil
        return false
    end

    local Character = LocalPlayer.Character
    if not Character or not Character:FindFirstChild("HumanoidRootPart") then
        AutoLobbyStartGate.ReadySince = nil
        return false
    end

    AutoLobbyStartGate.ReadySince = AutoLobbyStartGate.ReadySince or os.clock()
    return os.clock() - AutoLobbyStartGate.ReadySince >= AutoLobbyStartGate.GraceDelay
end

local IsSiegeWorld -- diisi di bawah (forward declaration)

-- Room Siege (21-24) bisa memakai layar match sendiri (seperti Endless yang memakai ScreenMatch_Endless),
-- jadi untuk world Siege cari layar "ScreenMatch*" apa pun yang sedang terlihat.
local function GetScreenMatch()
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local MainGui = PlayerGui and PlayerGui:FindFirstChild("MainGui")
    if not MainGui then
        return nil
    end
    local Default = MainGui:FindFirstChild("ScreenMatch")
    if Default and Default.Visible then
        return Default
    end
    if IsSiegeWorld and IsSiegeWorld(GetWorldId()) then
        for _, Child in ipairs(MainGui:GetChildren()) do
            if Child:IsA("GuiObject") and Child.Visible and
                string.find(string.lower(Child.Name), "screenmatch", 1, true) then
                return Child
            end
        end
    end
    return Default
end

local function DescribeMatchScreens()
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local MainGui = PlayerGui and PlayerGui:FindFirstChild("MainGui")
    local Parts = {}
    for _, Child in ipairs(MainGui and MainGui:GetChildren() or {}) do
        if string.find(string.lower(Child.Name), "match", 1, true) or
            string.find(string.lower(Child.Name), "siege", 1, true) then
            table.insert(Parts, Child.Name .. "=" .. tostring(Child:IsA("GuiObject") and Child.Visible))
        end
    end
    return #Parts > 0 and table.concat(Parts, ", ") or "tidak ada"
end

local function IsAutoStartFreeMatchRoom(Room)
    local PlayersCount = tonumber(Room:GetAttribute("PlayersCount")) or 0
    local RoomState = Room:GetAttribute("RoomState")
    local EmptyState = GetGameEnum().RoomState.Empty
    return PlayersCount == 0 and (RoomState == nil or RoomState == EmptyState or tostring(RoomState) == tostring(EmptyState))
end

local function FindAutoStartPortalPart(Room)
    local Touch = Room and Room:FindFirstChild("Touch")
    if not Touch then
        return nil
    end
    if Touch:IsA("BasePart") then
        return Touch
    end
    for _, Obj in ipairs(Touch:GetDescendants()) do
        if Obj:IsA("BasePart") then
            return Obj
        end
    end
end

-- Dungeon Siege (Siege Round I-V) memakai portal Room21-Room24, dungeon biasa Room1-Room4
local NormalRoomRange = {First = 1, Last = 4}
local SiegeRoomRange = {First = 21, Last = 24}

IsSiegeWorld = function(WorldId)
    local Parts = {tostring(WorldId)}
    local Entry = DungeonCatalog.FindDungeonEntry(WorldId)
    if Entry then
        table.insert(Parts, tostring(Entry.DisplayName))
        local Info = Entry.Info
        if type(Info) == "table" then
            table.insert(Parts, tostring(Info.Id))
            table.insert(Parts, tostring(Info.Name))
            table.insert(Parts, tostring(Info.Mode))
        end
    end
    return string.find(string.lower(table.concat(Parts, " ")), "siege", 1, true) ~= nil
end

-- Mode "Latest" hanya berlaku untuk map yang masuk lewat Room1-Room4 (dungeon biasa).
-- Map dari room lain (Siege Room21-24, Endless Tower Room9/10) dikecualikan.
local LatestExcludePatterns = {"siege", "endless", "tower", "valhalla arena", "abandoned"}
local LatestExcludePrefixes = {"cave"} -- nama dungeon yang diawali kata ini dikecualikan

local function IsRoom14World(Entry)
    local DisplayLower = string.lower(tostring(Entry.DisplayName))
    for _, Prefix in ipairs(LatestExcludePrefixes) do
        if string.sub(DisplayLower, 1, #Prefix) == Prefix then
            return false
        end
    end
    local Parts = {tostring(Entry.WorldId), tostring(Entry.DisplayName)}
    local Info = Entry.Info
    if type(Info) == "table" then
        table.insert(Parts, tostring(Info.Id))
        table.insert(Parts, tostring(Info.Name))
        table.insert(Parts, tostring(Info.Mode))
    end
    local Text = string.lower(table.concat(Parts, " "))
    for _, Pattern in ipairs(LatestExcludePatterns) do
        if string.find(Text, Pattern, 1, true) then
            return false
        end
    end
    return true
end

-- Pilih dungeon terbaru yang sudah unlock (Sort tertinggi, hanya map Room1-4)
-- beserta difficulty tertinggi yang sudah unlock. Return true bila pilihan berubah.
--   IncludeHell = false -> Auto Unlock Map & Difficulty (hanya difficulty 1-5)
--   IncludeHell = true  -> Auto Latest (difficulty tertinggi yang sudah unlock, Hell ikut)
local function ApplyLatestSelection(IncludeHell)
    local Latest = nil
    for _, Entry in ipairs(DungeonCatalog.GetDungeonCatalog(true)) do
        if Entry.Unlocked and IsRoom14World(Entry) then
            if not Latest or Entry.Sort > Latest.Sort or (Entry.Sort == Latest.Sort and Entry.WorldId > Latest.WorldId) then
                Latest = Entry
            end
        end
    end
    if not Latest then
        return false
    end
    local Difficulty = nil
    for _, DifficultyEntry in ipairs(DungeonCatalog.GetDifficultyCatalog(Latest.WorldId, true)) do
        local IsHell = type(DifficultyEntry.Info) == "table" and DifficultyEntry.Info.Style == "Hell"
        local Allowed = IncludeHell or (DifficultyEntry.Level <= 5 and not IsHell)
        if DifficultyEntry.Unlocked and Allowed then
            if not Difficulty or DifficultyEntry.Level > Difficulty.Level then
                Difficulty = DifficultyEntry
            end
        end
    end
    if not Difficulty then
        return false
    end
    local Changed = GetWorldId() ~= Latest.WorldId or GetDifficulty() ~= Difficulty.Level
    if Changed then
        SetTarget(Latest.WorldId, Difficulty.Level)
        print("[AutoStart] Latest -> " .. tostring(Latest.WorldId) .. " diff " .. tostring(Difficulty.Level))
    end
    return Changed
end

-- Terapkan mode otomatis yang sedang aktif (kalau ada). Return true bila pilihan berubah.
local function ApplyAutoSelection()
    if CfgBool("DgAutoLatest") then
        return ApplyLatestSelection(true)
    elseif CfgBool("DgAutoUnlock") then
        return ApplyLatestSelection(false)
    end
    return false
end

local function GetAutoStartRoomRange()
    if IsSiegeWorld(GetWorldId()) then
        return SiegeRoomRange, true
    end
    return NormalRoomRange, false
end

local function FindAutoStartFreePortal(RoomRange)
    RoomRange = RoomRange or NormalRoomRange
    local MatchRoom = Workspace:FindFirstChild("MatchRoom")
    if not MatchRoom then
        return nil, nil
    end
    for Index = RoomRange.First, RoomRange.Last do
        local Room = MatchRoom:FindFirstChild("Room" .. tostring(Index))
        if Room and IsAutoStartFreeMatchRoom(Room) then
            local PortalPart = FindAutoStartPortalPart(Room)
            if PortalPart then
                return Room, PortalPart
            end
        end
    end
end

function AutoLobbyStartGate.TouchRoomPortal(Room, PortalPart, LogPrefix)
    if not firetouchinterest then
        print(LogPrefix .. " firetouchinterest unavailable")
        return false
    end

    local Character = LocalPlayer.Character
    local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
    if not Room or not RootPart or not PortalPart then
        print(LogPrefix .. " Waiting free match room")
        return false
    end

    print(LogPrefix .. " Touching " .. Room.Name .. " portal")
    local Direction = PortalPart.Position - RootPart.Position
    if Direction.Magnitude < 0.1 then
        Direction = RootPart.CFrame.LookVector
    else
        Direction = Direction.Unit
    end
    RootPart.CFrame = CFrame.new(PortalPart.Position - (Direction * 2) + Vector3.new(0, 1, 0))
    RootPart.AssemblyLinearVelocity = Direction * 12
    task.wait(0.05)
    RootPart.CFrame = CFrame.new(PortalPart.Position + (Direction * 2) + Vector3.new(0, 1, 0))
    firetouchinterest(RootPart, PortalPart, 0)
    task.wait(0.2)
    firetouchinterest(RootPart, PortalPart, 1)
    return true
end

local function TouchAutoStartPortal()
    -- validasi dulu supaya world yang dipilih sudah final sebelum menentukan range room
    pcall(DungeonCatalog.ValidateAutoStartSelection, false)
    local RoomRange, IsSiege = GetAutoStartRoomRange()
    if IsSiege then
        print("[AutoStart] Siege dungeon -> mencari Room" .. tostring(RoomRange.First) .. "-Room" ..
                  tostring(RoomRange.Last))
    end
    local Room, PortalPart = FindAutoStartFreePortal(RoomRange)
    return AutoLobbyStartGate.TouchRoomPortal(Room, PortalPart, "[AutoStart]")
end

local function WaitForScreenMatchVisible(Timeout)
    local StartedAt = os.clock()
    repeat
        local ScreenMatch = GetScreenMatch()
        if ScreenMatch and ScreenMatch.Visible then
            return ScreenMatch
        end
        task.wait(0.1)
    until (os.clock() - StartedAt) >= Timeout
    return nil
end

local function TryAutoStartSoloDungeon()
    local Forced = ManualActive()
    if CfgBool("TwAuto") or Dungeon.IsBlocked() or not (Dungeon.IsEnabled() or Forced) then
        return false
    end

    if not AutoLobbyStartGate.IsReady() then
        return false
    end

    local CurrentTime = os.clock()
    if not Forced and (CurrentTime - LastAutoStartDungeonAt) < AutoStartDungeonDelay then
        return false
    end

    if CfgBool("DgAutoLatest") or CfgBool("DgAutoUnlock") then
        pcall(ApplyAutoSelection)
    end

    local ScreenMatch = GetScreenMatch()
    if not ScreenMatch or not ScreenMatch.Visible then
        Dungeon.SetStatus("dgSt_touchingPortal")
        if not TouchAutoStartPortal() then
            return false
        end
        ScreenMatch = WaitForScreenMatchVisible(2.5)
        if not ScreenMatch then
            print("[AutoStart] Waiting ScreenMatch after portal | layar match: " .. DescribeMatchScreens())
            Dungeon.SetStatus("dgSt_waitScreenMatch")
            return false
        end
    end

    if not IsInLobby() then
        return false
    end

    if not DungeonCatalog.ValidateAutoStartSelection(false) then
        print("[AutoStart] No unlocked dungeon target")
        Dungeon.SetStatus("dgSt_noDungeon")
        return false
    end

    local WorldId, Difficulty, Players_ = GetWorldId(), GetDifficulty(), GetPlayers()
    print("[AutoStart] Creating " .. tostring(Players_) .. "P " .. WorldId .. " diff " .. tostring(Difficulty) ..
              " | layar: " .. tostring(ScreenMatch and ScreenMatch.Name))
    Dungeon.SetStatus("dgSt_creating", WorldId)
    GetWorldRemoteEvent():FireServer("SelectWorld", WorldId, Difficulty)
    task.wait(0.35)
    GetGameMatchRemoteEvent():FireServer("CreatRoom", WorldId, Difficulty, Players_)
    LastAutoStartDungeonAt = os.clock()
    AutoStartPending = false
    Dungeon.ManualUntil = nil
    AutoStartRoomWait.Active = true
    AutoStartRoomWait.Since = os.clock()
    if Repeat.Manual then
        Repeat.Manual = false
        Repeat.Counted = false
    else
        Dungeon.RepeatDone = math.min(999, Dungeon.RepeatDone + 1)
        Repeat.Counted = true
    end
    Dungeon.SetStatus("dgSt_roomCreated")
    print("[AutoStart] Create room fired")
    return true
end

local function QueueAutoStartSoloDungeon()
    AutoStartPending = true
    LastAutoStartRetryAt = 0
    Dungeon.SetStatus("dgSt_queued")
    print("[AutoStart] Queued solo dungeon restart")
    TryAutoStartSoloDungeon()
end

local function SetStatusIfChanged(Key, ...)
    local New = MakeStatus(Key, ...)
    if not SameStatus(Dungeon.Status, New) then
        Dungeon.Status = New
        Changed()
    end
end

-- Dipanggil UI
function Dungeon.OnToggle(Value)
    Follow.Since = nil
    if Value then
        Dungeon.RepeatDone = 0 -- batch repeat baru
        Dungeon.SetStatus("dgSt_idle")
    else
        AutoStartPending = false
        Dungeon.SetStatus("dgSt_off")
    end
end

function Dungeon.ResetRepeat()
    Dungeon.RepeatDone = 0
    Changed()
end

function Dungeon.ResetFollow()
    Follow.Since = nil
end

function Dungeon.StartNow()
    Repeat.Manual = true -- start manual tidak dihitung repeat
    Dungeon.ManualUntil = os.clock() + 60
    QueueAutoStartSoloDungeon()
end

-- Loop utama Auto Start:
--  * ada antrean (AutoStartPending)  -> coba buat room (retry tiap AutoStartRetryDelay)
--  * tidak ada antrean + Auto Start ON + sudah di lobby -> antre otomatis, jadi tidak diam di IDLE
task.spawn(function()
    while Alive() do
        task.wait(0.5)
        local Enabled = Dungeon.IsEnabled()
        if Enabled or ManualActive() then
            local Ok, Err = pcall(function()
                if Dungeon.IsBlocked() then
                    SetStatusIfChanged("dgSt_blocked")
                    return
                end
                local CurrentTime = os.clock()
                if AutoStartPending then
                    if (CurrentTime - LastAutoStartRetryAt) >= AutoStartRetryDelay then
                        LastAutoStartRetryAt = CurrentTime
                        TryAutoStartSoloDungeon()
                    end
                elseif not Enabled then
                    return
                elseif not IsInLobby() then
                    AutoStartRoomWait.Active = false
                    Repeat.Counted = false
                    Follow.Since = nil
                    SetStatusIfChanged("dgSt_inDungeon")
                elseif CfgBool("TwAuto") then
                    SetStatusIfChanged("dgSt_endlessMode")
                elseif LocalPlayer:GetAttribute("EnterRoomId") then
                    SetStatusIfChanged("dgSt_inRoom")
                elseif AutoStartRoomWait.Active and (CurrentTime - AutoStartRoomWait.Since) < AutoStartRoomWait.Timeout then
                    SetStatusIfChanged("dgSt_waitingDungeon")
                elseif not AutoLobbyStartGate.IsReady() then
                    SetStatusIfChanged("dgSt_waitLobby")
                else
                    if AutoStartRoomWait.Active and Repeat.Counted and Dungeon.RepeatDone > 0 then
                        -- room tidak pernah mulai: kembalikan hitungan repeat
                        Dungeon.RepeatDone = Dungeon.RepeatDone - 1
                    end
                    Repeat.Counted = false
                    AutoStartRoomWait.Active = false
                    local Total = GetRepeatTotal()
                    if Total > 0 and Dungeon.RepeatDone >= Total then
                        -- batch repeat selesai: matikan Auto Start
                        Dungeon.RepeatDone = 0
                        EngineConfig.DgAutoStart = false
                        Dungeon.SetStatus("dgSt_repeatDone")
                    else
                        local Ready, Key, Arg = Follow.Gate()
                        if Ready then
                            QueueAutoStartSoloDungeon()
                        else
                            SetStatusIfChanged(Key, Arg)
                        end
                    end
                end
            end)
            if not Ok then
                warn("[Dungeon] loop: " .. tostring(Err))
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- TOWER (Endless Tower, SOLO 1 player)
--------------------------------------------------------------------------------
local Tower = {
    Status = MakeStatus("twSt_off"),
    WeaponStatus = MakeStatus("twWp_none"),
    Weapon = {Attempt = 0, RequestedUUID = nil, RequestedAt = 0},
    LastJoinAt = -math.huge,
    LastStartClickAt = -math.huge,
    CountFails = 0
}

function Tower.SetStatus(Key, ...)
    local New = MakeStatus(Key, ...)
    if not SameStatus(Tower.Status, New) then
        Tower.Status = New
        Changed()
    end
end

function Tower.SetWeaponStatus(Key, ...)
    local New = MakeStatus(Key, ...)
    if not SameStatus(Tower.WeaponStatus, New) then
        Tower.WeaponStatus = New
        Changed()
    end
end

function Tower.InEndless()
    local World = Workspace:FindFirstChild("World")
    return World ~= nil and World:FindFirstChild("Start") ~= nil
end

function Tower.GetHighest()
    local Modules = GetFrameworkModule().Modules
    local Record = Modules.WorldUtil:GetWorldRecords(LocalPlayer, "Endless1", 1, "MaxRound",
        Modules.SeasonUtil:GetCurrentSeason())
    Record = math.max(0, math.floor(tonumber(Record) or 0))
    return math.clamp(math.floor(Record / 5) * 5 + 1, 1, 196), Record
end

function Tower.ResolveStart()
    local Highest, Record = Tower.GetHighest()
    local Wanted = GetTowerStartRound()
    if Wanted == 0 then
        return Highest, Record
    end
    return math.min(Wanted, Highest), Record
end

function Tower.GetInfo()
    local Highest, Record = Tower.GetHighest()
    return {Highest = Highest, Record = Record, NextStart = (Tower.ResolveStart())}
end

function Tower.WeaponModules()
    local Modules = GetFrameworkModule().Modules
    local RemoteEvent = WaitChild(WaitChild(WaitChild(WaitChild(ReplicatedStorage, "Framework", 10), "Gameplay"),
        "EquipmentSystem"), "EquipmentRE")
    return Modules.DataUtil, Modules.EquipmentUtil, Modules.TimeLimitUtil, Modules.TranslationUtil, RemoteEvent
end

function Tower.GetWeaponOptions()
    local Data, Equip, TimeLimit, Translation = Tower.WeaponModules()
    local Owned = Data:GetValue(LocalPlayer, {"Equipment", "Owned"}) or {}
    local Slots = Data:GetValue(LocalPlayer, {"Equipment", "EquipSlots"}) or {}
    local Out = {}
    for UUID, Item in pairs(Owned) do
        if type(Item) == "table" and Item.Type == "Weapon" and UUID ~= Slots.Weapon and UUID ~= Slots.Weapon2 and
            not TimeLimit:IsTimeLimited(Item) then
            local Def = Equip:GetDef(Item.ID)
            if Def then
                local Damage = tonumber(Equip:GetDmgOrHpByInfo(LocalPlayer, Item, Def)) or 0
                local Name = tostring(Def.ID or Item.ID or UUID)
                local Success, Translated = pcall(Translation.TranslateByKey, Translation,
                    "K_" .. string.upper(tostring(Def.ID or Item.ID or "")))
                if Success and type(Translated) == "string" and Translated ~= "" then
                    Name = Translated
                end
                local Fortify = Item.Fortify and Item.Fortify - 1 or 0
                table.insert(Out, {
                    UUID = UUID,
                    Label = Name .. (Fortify > 0 and (" (+" .. Fortify .. ")") or "") .. " | DMG " .. Damage,
                    Damage = Damage,
                    Rarity = tonumber(Equip:GetOreRarity(Item.MaxOre)) or 0,
                    Sort = tonumber(Def.Sort) or math.huge
                })
            end
        end
    end
    table.sort(Out, function(A, B)
        if A.Damage ~= B.Damage then
            return A.Damage > B.Damage
        end
        if A.Rarity ~= B.Rarity then
            return A.Rarity > B.Rarity
        end
        if A.Sort ~= B.Sort then
            return A.Sort < B.Sort
        end
        return tostring(A.UUID) < tostring(B.UUID)
    end)
    return Out
end

function Tower.ResolveWeapon()
    local Options = Tower.GetWeaponOptions()
    local Wanted = CfgStr("TwWeapon", "")
    if Wanted ~= "" then
        for _, Option in ipairs(Options) do
            if Option.UUID == Wanted then
                return Option, false, Options
            end
        end
    end
    return Options[1], Wanted ~= "", Options
end

function Tower.ResetWeaponRequest()
    local Weapon = Tower.Weapon
    Weapon.Attempt, Weapon.RequestedUUID, Weapon.RequestedAt = 0, nil, 0
end

function Tower.RequestEquip(UUID)
    local _, _, _, _, RemoteEvent = Tower.WeaponModules()
    RemoteEvent:FireServer("RequestSetExtraWeapon", UUID)
end

function Tower.TryJoin()
    if not CfgBool("TwAuto") then
        return false
    end
    if IsInLobby() and LocalPlayer:GetAttribute("EnterRoomId") then
        Tower.SetStatus("twSt_roomAssigned")
        return false
    end
    if not AutoLobbyStartGate.IsReady() then
        Tower.SetStatus(Tower.InEndless() and "twSt_inTower" or "twSt_waitLobby")
        return false
    end
    if os.clock() - Tower.LastJoinAt < 10 then
        return false
    end
    Tower.LastJoinAt = os.clock()

    local Room, PortalPart = FindAutoStartFreePortal({First = 9, Last = 10})
    if not Room then
        Tower.SetStatus("twSt_waitRoom")
        return false
    end

    local Screen = GetMainGuiChild("ScreenMatch_Endless")
    if not Screen or not Screen.Visible then
        Tower.SetStatus("twSt_touching", Room.Name)
        if not AutoLobbyStartGate.TouchRoomPortal(Room, PortalPart, "[Tower]") then
            return false
        end
        Screen = WaitForGui(function()
            return GetMainGuiChild("ScreenMatch_Endless")
        end, 3)
        if not Screen then
            Tower.SetStatus("twSt_waitScreen")
            return false
        end
    end

    -- Tower selalu SOLO: pastikan counter di layar = 1 (counter layar yang dipakai server)
    local CountOk, CountWhy = SetMatchCountTo(Screen, 1)
    if CountOk then
        Tower.CountFails = 0
    else
        Tower.CountFails = Tower.CountFails + 1
        if Tower.CountFails < 4 then
            Tower.LastJoinAt = os.clock() - 7 -- coba lagi ~3 detik
            Tower.SetStatus("twSt_countFail", tostring(CountWhy))
            return false
        end
        print("[Tower] kontrol layar: " .. DescribeCountControls(Screen))
        Tower.SetStatus("twSt_countUiMissing")
    end

    local StartRound, Record = Tower.ResolveStart()
    Tower.SetStatus("twSt_creating", Room.Name, StartRound, Record)
    GetGameMatchRemoteEvent():FireServer("CreatRoom", "Endless1", 1, 1, StartRound)
    return true
end

-- Menangani pop-up "Equip Extra Weapon" lalu menekan Start. Return true bila sedang menangani pop-up itu.
function Tower.TryStartRun()
    if not CfgBool("TwAuto") then
        return false
    end
    local Now = os.clock()
    if Now - Tower.LastStartClickAt < 1 then
        return false
    end
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then
        return false
    end

    local Title
    for _, Obj in ipairs(PlayerGui:GetDescendants()) do
        if (Obj:IsA("TextLabel") or Obj:IsA("TextButton")) and IsGuiVisible(Obj) and
            string.find(string.lower(tostring(Obj.Text)), "equip extra weapon", 1, true) then
            Title = Obj
            break
        end
    end
    if not Title then
        Tower.ResetWeaponRequest()
        return false
    end

    local StartButton
    local Root = Title.Parent
    while Root and Root ~= PlayerGui.Parent and not StartButton do
        for _, Obj in ipairs(Root:GetDescendants()) do
            if Obj:IsA("GuiButton") and IsGuiVisible(Obj) then
                local Text = Obj:IsA("TextButton") and Obj.Text or ""
                if string.find(string.lower(Obj.Name .. " " .. tostring(Text)), "start", 1, true) then
                    StartButton = Obj
                    break
                end
            elseif Obj:IsA("TextLabel") and IsGuiVisible(Obj) and string.lower(tostring(Obj.Text)) == "start" then
                local Button = Obj:FindFirstAncestorWhichIsA("GuiButton")
                if Button and IsGuiVisible(Button) then
                    StartButton = Button
                    break
                end
            end
        end
        Root = Root.Parent
    end

    Tower.LastStartClickAt = Now
    if not StartButton then
        Tower.SetStatus("twSt_waitStart")
        return true
    end

    local function Start()
        Tower.SetStatus("twSt_starting")
        ClickGuiButton(StartButton)
    end

    local Candidate, FellBack, Options = Tower.ResolveWeapon()
    if not Candidate then
        Tower.SetWeaponStatus("twWp_noWeapon")
        Tower.ResetWeaponRequest()
        Start()
        return true
    end

    local Weapon = Tower.Weapon
    if Weapon.Attempt == 0 then
        Weapon.RequestedUUID, Weapon.RequestedAt, Weapon.Attempt = Candidate.UUID, Now, 1
        Tower.RequestEquip(Candidate.UUID)
        Tower.SetWeaponStatus(FellBack and "twWp_fallback" or "twWp_equipping", Candidate.Label)
        return true
    end
    if LocalPlayer:GetAttribute("ExtraWeaponUUID") == Weapon.RequestedUUID then
        Tower.SetWeaponStatus("twWp_equipped", Candidate.Label)
        Tower.ResetWeaponRequest()
        Start()
        return true
    end
    if Now - Weapon.RequestedAt < 2 then
        Tower.SetWeaponStatus("twWp_waitConfirm")
        return true
    end
    if Weapon.Attempt == 1 then
        local Top = Options[1] or Candidate
        Weapon.RequestedUUID, Weapon.RequestedAt, Weapon.Attempt = Top.UUID, Now, 2
        Tower.RequestEquip(Top.UUID)
        Tower.SetWeaponStatus("twWp_retryHighest", Top.Label)
        return true
    end
    Tower.SetWeaponStatus("twWp_timeout")
    Tower.ResetWeaponRequest()
    Start()
    return true
end

function Tower.OnToggle(Value)
    if Value then
        Tower.SetStatus("twSt_idle")
    else
        Tower.SetStatus("twSt_off")
        Tower.ResetWeaponRequest()
    end
end

task.spawn(function()
    while Alive() do
        task.wait(0.5)
        local Success, ErrorMessage = pcall(function()
            if not CfgBool("TwAuto") then
                if Tower.Status.key ~= "twSt_off" then
                    Tower.SetStatus("twSt_off")
                end
                return
            end
            if not Tower.TryStartRun() then
                if Dungeon.IsBlocked() then
                    Tower.SetStatus("twSt_blocked")
                else
                    Tower.TryJoin()
                end
            end
        end)
        if not Success then
            Tower.SetStatus("twSt_error", tostring(ErrorMessage))
            task.wait(2)
        end
    end
end)

--------------------------------------------------------------------------------
-- PETS (Auto Hatch + Expedition)
--------------------------------------------------------------------------------
local Pets = {HatchStatus = MakeStatus("ptSt_off"), ExpStatus = MakeStatus("ptSt_off"), HatchWake = false}

function Pets.Set(Field, Key, ...)
    local New = MakeStatus(Key, ...)
    local Name = Field .. "Status"
    if not SameStatus(Pets[Name], New) then
        Pets[Name] = New
        Changed()
    end
end

function Pets.HatchEggs(Util)
    local Eggs = {}
    for UUID, Data in pairs(Util:GetOwnedEggs(LocalPlayer) or {}) do
        local EggConfig = Data and Util:GetEggCfg(Data.EggId)
        if EggConfig then
            table.insert(Eggs, {
                UUID = UUID,
                EggId = Data.EggId,
                Rarity = tonumber(EggConfig.Rarity) or 0,
                Sort = tonumber(EggConfig.Sort) or math.huge
            })
        end
    end
    table.sort(Eggs, function(A, B)
        if A.Rarity ~= B.Rarity then
            return A.Rarity > B.Rarity
        end
        if A.Sort ~= B.Sort then
            return A.Sort < B.Sort
        end
        return tostring(A.UUID) < tostring(B.UUID)
    end)
    return Eggs
end

function Pets.HatchSignature(Util)
    local Parts = {}
    for _, Egg in ipairs(Pets.HatchEggs(Util)) do
        table.insert(Parts, "E:" .. tostring(Egg.UUID))
    end
    for Index = 1, 3 do
        local Slot = Util:GetSlotData(LocalPlayer, Index)
        table.insert(Parts, "S" .. Index .. ":" .. tostring(Slot and Slot.EggId or "") .. ":" ..
            tostring(Slot and Slot.StartTime or ""))
    end
    return table.concat(Parts, "|")
end

function Pets.WaitSignatureChange(Util, Before, Timeout)
    local Deadline = os.clock() + Timeout
    while Alive() and os.clock() < Deadline do
        if Pets.HatchSignature(Util) ~= Before then
            return true
        end
        task.wait(0.2)
    end
    return false
end

function Pets.GetHatchInfo()
    local Modules = GetFrameworkModule().Modules
    local Util, Time = Modules.PetsHatchUtil, Modules.TimeUtil
    local Info = {Eggs = #Pets.HatchEggs(Util), Slots = {}}
    for Index = 1, 3 do
        local Slot = Util:GetSlotData(LocalPlayer, Index)
        local Row = {Index = Index, State = "EMPTY"}
        if Slot and Slot.EggId then
            if Util:IsCompleted(Slot) then
                Row.State = "READY"
            else
                Row.State = "HATCHING"
                local EggConfig = Util:GetEggCfg(Slot.EggId)
                local Duration, StartTime = EggConfig and tonumber(EggConfig.HatchDuration), tonumber(Slot.StartTime)
                if Duration and StartTime then
                    Row.Remaining = math.max(0, Duration - (Time:GetNow() - StartTime))
                end
            end
        end
        Info.Slots[Index] = Row
    end
    return Info
end

function Pets.HatchStep()
    local Util = GetFrameworkModule().Modules.PetsHatchUtil
    local Before = Pets.HatchSignature(Util)

    for Index = 1, 3 do
        local Slot = Util:GetSlotData(LocalPlayer, Index)
        if Slot and Slot.EggId and Util:IsCompleted(Slot) then
            Pets.Set("Hatch", "ptHt_claiming", Index)
            Util:Claim(LocalPlayer, Index)
            if not Pets.WaitSignatureChange(Util, Before, 3) then
                Pets.Set("Hatch", "ptHt_waitServer")
            end
            return
        end
    end

    local Empty
    for Index = 1, 3 do
        local Slot = Util:GetSlotData(LocalPlayer, Index)
        if not (Slot and Slot.EggId) then
            Empty = Index
            break
        end
    end
    if not Empty then
        Pets.Set("Hatch", "ptHt_hatching")
        return
    end

    local Egg = Pets.HatchEggs(Util)[1]
    if not Egg then
        Pets.Set("Hatch", "ptHt_noEggs")
        return
    end

    Pets.Set("Hatch", "ptHt_hatchingSlot", Empty)
    Util:StartHatch(LocalPlayer, Empty, Egg.UUID)
    if not Pets.WaitSignatureChange(Util, Before, 3) then
        Pets.Set("Hatch", "ptHt_waitServer")
    end
end

function Pets.ExpModules()
    local Modules = GetFrameworkModule().Modules
    return Modules.PetsExpeditionUtil, Modules.PetsUtil, Modules.PetsAffinityUtil
end

function Pets.GetExpInfo()
    local Expedition = Pets.ExpModules()
    local Used = Expedition:_GetEffectiveDailyCount(LocalPlayer)
    local Limit = math.max(0, math.floor(tonumber(Expedition.Config.DailyLimit) or 0))
    local SlotCount = math.max(1, math.floor(tonumber(Expedition.Config.SlotCount) or 4))
    local Slots = {}
    for Index = 1, SlotCount do
        local Slot = Expedition:GetSlotData(LocalPlayer, Index)
        local State = "EMPTY"
        if Slot and Slot.UID then
            State = Expedition:IsCompleted(Slot) and "READY" or "AWAY"
        end
        Slots[Index] = {Index = Index, State = State}
    end
    return {Remaining = math.max(0, Limit - Used), Limit = Limit, SlotCount = SlotCount, Slots = Slots}
end

function Pets.ExpWaitSlot(Expedition, Slot, ExpectedUID)
    local Deadline = os.clock() + 5
    while Alive() and os.clock() < Deadline do
        local Data = Expedition:GetSlotData(LocalPlayer, Slot)
        if ExpectedUID == nil then
            if not (Data and Data.UID) then
                return true
            end
        elseif Data and Data.UID == ExpectedUID then
            return true
        end
        task.wait(0.2)
    end
    return false
end

function Pets.ExpBestPet(Expedition, PetsUtil, AffinityUtil, Slot)
    local List = {}
    for _, Pet in ipairs(PetsUtil:GetOwnedPets(LocalPlayer) or {}) do
        if Pet.UID then
            local Success, Can = pcall(Expedition.CanDispatch, Expedition, LocalPlayer, Slot, Pet.UID)
            if Success and Can then
                local Def = PetsUtil:GetPetInfo(Pet.Id) or {}
                table.insert(List, {
                    Pet = Pet,
                    Affinity = AffinityUtil:GetAffinityLevel(Pet.Affinity or 0),
                    Rarity = tonumber(Def.Rarity) or 0,
                    Sort = tonumber(Def.Sort) or math.huge
                })
            end
        end
    end
    table.sort(List, function(A, B)
        if A.Affinity ~= B.Affinity then
            return A.Affinity > B.Affinity
        end
        if A.Rarity ~= B.Rarity then
            return A.Rarity > B.Rarity
        end
        if A.Sort ~= B.Sort then
            return A.Sort < B.Sort
        end
        return (tonumber(A.Pet.UID) or 0) < (tonumber(B.Pet.UID) or 0)
    end)
    return List[1] and List[1].Pet or nil
end

function Pets.ExpStep()
    local Expedition, PetsUtil, AffinityUtil = Pets.ExpModules()
    local RemoteEvent = Expedition.RemoteEvent
    if not RemoteEvent then
        Pets.Set("Exp", "ptEx_unavailable")
        return
    end
    local SlotCount = math.max(1, math.floor(tonumber(Expedition.Config.SlotCount) or 4))

    if CfgBool("PetExpClaim") then
        for Index = 1, SlotCount do
            local Slot = Expedition:GetSlotData(LocalPlayer, Index)
            if Slot and Slot.UID and Expedition:IsCompleted(Slot) then
                Pets.Set("Exp", "ptEx_claiming", Index)
                RemoteEvent:FireServer("Claim", Index)
                if Pets.ExpWaitSlot(Expedition, Index, nil) then
                    Pets.Set("Exp", "ptEx_claimed", Index)
                else
                    Pets.Set("Exp", "ptEx_claimTimeout")
                end
                return
            end
        end
    end

    if not CfgBool("PetExpDispatch") then
        Pets.Set("Exp", "ptEx_claimReady")
        return
    end

    local Used = Expedition:_GetEffectiveDailyCount(LocalPlayer)
    local Limit = math.max(0, math.floor(tonumber(Expedition.Config.DailyLimit) or 0))
    if Limit - Used <= 0 then
        Pets.Set("Exp", "ptEx_dailyLimit")
        return
    end

    local Order = ParseSlots(EngineConfig.PetExpSlots, SlotCount)
    if #Order == 0 then
        Pets.Set("Exp", "ptEx_noSlot")
        return
    end

    local Target
    for _, Index in ipairs(Order) do
        local Slot = Expedition:GetSlotData(LocalPlayer, Index)
        if not (Slot and Slot.UID) then
            Target = Index
            break
        end
    end
    if not Target then
        Pets.Set("Exp", "ptEx_noEmpty")
        return
    end

    local Pet = Pets.ExpBestPet(Expedition, PetsUtil, AffinityUtil, Target)
    if not Pet then
        Pets.Set("Exp", "ptEx_noPet")
        return
    end

    Pets.Set("Exp", "ptEx_dispatching", Target)
    RemoteEvent:FireServer("Dispatch", Target, Pet.UID)
    if Pets.ExpWaitSlot(Expedition, Target, Pet.UID) then
        Pets.Set("Exp", "ptEx_sent", math.max(0, Limit - Used - 1), Limit)
    else
        Pets.Set("Exp", "ptEx_dispatchTimeout")
    end
end

function Pets.OnHatchToggle(Value)
    if not Value then
        Pets.Set("Hatch", "ptSt_off")
    end
end

local function PetsLoop(Field, Interval, Fn)
    task.spawn(function()
        while Alive() do
            task.wait(Interval)
            local Success, ErrorMessage = pcall(Fn)
            if not Success then
                Pets.Set(Field, "ptSt_error", tostring(ErrorMessage))
                task.wait(2)
            end
        end
    end)
end

PetsLoop("Hatch", 1.5, function()
    if not CfgBool("PetHatchAuto") then
        Pets.Set("Hatch", "ptSt_off")
        return
    end
    Pets.HatchStep()
end)
PetsLoop("Exp", 1, function()
    if not (CfgBool("PetExpDispatch") or CfgBool("PetExpClaim")) then
        Pets.Set("Exp", "ptSt_off")
        return
    end
    Pets.ExpStep()
end)

-- Hatch: bereaksi saat data berubah, tidak menunggu polling berikutnya
task.spawn(function()
    local Success, ErrorMessage = pcall(function()
        local Data = GetFrameworkModule().Modules.DataUtil
        local function Wake()
            Pets.HatchWake = true
        end
        Data:ListenFor(LocalPlayer, {"PetHatch", "Egg"}, Wake)
        Data:ListenFor(LocalPlayer, {"PetHatch", "Slots"}, Wake)
    end)
    if not Success then
        warn("[Pets] hatch listener: " .. tostring(ErrorMessage))
    end
end)
task.spawn(function()
    while Alive() do
        if Pets.HatchWake then
            Pets.HatchWake = false
            if CfgBool("PetHatchAuto") then
                pcall(Pets.HatchStep)
            end
        end
        task.wait(0.25)
    end
end)

--------------------------------------------------------------------------------
-- Export ke Hub
--------------------------------------------------------------------------------
H.DungeonSys = {
    Dungeon = Dungeon,
    Tower = Tower,
    Pets = Pets,
    Catalog = DungeonCatalog,
    UIHook = UIHook,                       -- UIHook.Refresh diisi tab UI
    SanitizeConfig = SanitizeConfig,       -- panggil setelah load profil
    ParseSlots = ParseSlots,
    SlotsToString = SlotsToString,
    FormatStatus = FormatStatus,
    ApplyAutoSelection = ApplyAutoSelection,
    GetWorldId = GetWorldId,
    GetDifficulty = GetDifficulty,
    GetTowerStartRound = GetTowerStartRound,
    ClickGuiButton = ClickGuiButton
}

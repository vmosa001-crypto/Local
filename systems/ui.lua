--========================================================--
-- IRON SOUL - CONTROL PANEL (MOBILE-FRIENDLY UI) V1
--
-- One panel to control every feature of the systems/ folder:
--   * Auto  : on/off switch for each automation stage (pipeline, tutorial, pets,
--             fortify, enchant, shop, skills, loadout, Cave, Hell, tickets mode)
--   * Farm  : Cave chase / World1 tween switches + movement and Cave/Hell tuning
--   * Upgrade: Fortify / Enchant / Shop limits and gold reserves
--   * System: FPS cap, headless, debug logs, reset, copy log, close UI
--   * Log   : live status feed (hooks getgenv().IronSoulStatus)
--
-- All values are written into getgenv().IronSoulConfig, which every manager
-- reads LIVE at the start of its Run(), and are persisted to
-- IronSoul_UIConfig_V1.json so they survive teleports / re-execution.
-- A missing key always means "default" (enabled), so this file is optional:
-- if it fails to load, the scripts behave exactly as before.
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Singleton: if already running, just bring the panel back.
do
    local existing = rawget(getgenv(), "IronSoulUI")
    if type(existing) == "table" and existing.Alive then
        pcall(existing.Show)
        return existing
    end
end

local UI = { Alive = true, VERSION = "V1" }
local SAVE_FILE = "IronSoul_UIConfig_V1.json"

local PLACES = {
    [117533937949084] = "Lobby",
    [91584731222940] = "Cave of Crystal",
    [119524374829397] = "Cave of Runes",
    [132445869992129] = "Abandoned Courtyard",
}

--========================================================--
-- SCHEMA
--========================================================--
-- t: toggle | step | cycle
local PAGES = {
    {
        id = "auto", tab = "Auto", title = "Automation",
        items = {
            { t = "section", name = "Pipeline" },
            { t = "toggle", key = "UPGRADE_AUTO", name = "Upgrade pipeline",
              desc = "Master: Pet > Fortify > Enchant > Shop > Cave > Hell. Off = langsung Story." },
            { t = "toggle", key = "TUTORIAL_AUTO", name = "Auto skip tutorial",
              desc = "Akun baru: pilih Sword lalu Skip Tutorial." },
            { t = "section", name = "Lobby managers" },
            { t = "toggle", key = "PET_AUTO", name = "Pets",
              desc = "Claim egg, start egg, equip pet terbaik." },
            { t = "toggle", key = "FORTIFY_AUTO", name = "Fortify / Blessing",
              desc = "Naikkan Fortify equipment sampai target aman." },
            { t = "toggle", key = "ENCHANT_AUTO", name = "Enchant",
              desc = "Pasang enchant stone otomatis (pintar)." },
            { t = "toggle", key = "SHOP_AUTO", name = "Gold Grocery",
              desc = "Beli bahan yang kurang untuk Fortify/Enchant." },
            { t = "toggle", key = "SKILL_AUTO", name = "Skill tree",
              desc = "Aktifkan cabang skill yang sudah terbuka." },
            { t = "toggle", key = "LOADOUT_AUTO", name = "Skill loadout",
              desc = "Samakan Skill1/Skill2/SkillU dengan weapon." },
            { t = "section", name = "Farming mode" },
            { t = "toggle", key = "CAVE_AUTO", name = "Smart Cave",
              desc = "Masuk Cave bila material dibutuhkan." },
            { t = "toggle", key = "HELL_AUTO", name = "Hell-first farm",
              desc = "Farm Hell stage, Normal hanya jadi jembatan unlock." },
            { t = "cycle", key = "TICKETS", name = "Ticket mode", default = "SMART",
              options = { "SMART", "MANUAL" },
              desc = "SMART = bot boleh pakai Ticket. MANUAL = tidak pernah." },
        },
    },
    {
        id = "farm", tab = "Farm", title = "Farm & Movement",
        items = {
            { t = "section", name = "Combat / movement" },
            { t = "toggle", key = "CAVE_CHASE_AUTO", name = "Cave chase",
              desc = "Dekati musuh jauh di Cave secara otomatis." },
            { t = "toggle", key = "WORLD1_TWEEN", name = "World1 smooth tween",
              desc = "Pindah portal pakai tween halus. Off = jalan bawaan lama." },
            { t = "step", key = "CHASE_ENGAGE_DISTANCE", name = "Chase trigger distance",
              default = 45, min = 10, max = 150, step = 5, unit = " studs",
              desc = "Musuh lebih jauh dari ini akan didekati." },
            { t = "step", key = "CHASE_SPEED", name = "Chase speed",
              default = 300, min = 100, max = 600, step = 25, unit = " st/s",
              desc = "Kecepatan tween saat mengejar musuh." },
            { t = "section", name = "Cave planner" },
            { t = "step", key = "CAVE_TICKET_RESERVE", name = "Ticket reserve",
              default = 5, min = 0, max = 50, step = 1,
              desc = "Sisa Ticket minimal yang tidak boleh dipakai." },
            { t = "step", key = "CAVE_COOLDOWN", name = "Cave cooldown",
              default = 360, min = 0, max = 3600, step = 30, unit = " s",
              desc = "Jeda minimal antar run Cave pintar." },
            { t = "step", key = "CAVE_POWER_PERCENT", name = "Cave power ready",
              default = 78, min = 30, max = 150, step = 2, unit = "%",
              desc = "Power minimal terhadap rekomendasi Cave." },
            { t = "section", name = "Hell planner" },
            { t = "step", key = "HELL_POWER_PERCENT", name = "Hell power ready",
              default = 78, min = 30, max = 150, step = 2, unit = "%",
              desc = "Power minimal terhadap rekomendasi stage Hell." },
        },
    },
    {
        id = "upgrade", tab = "Upgrade", title = "Upgrade limits",
        items = {
            { t = "section", name = "Fortify" },
            { t = "step", key = "FORTIFY_SAFE_TARGET", name = "Fortify target",
              default = 4, min = 1, max = 10, step = 1, desc = "Level Fortify tujuan." },
            { t = "step", key = "FORTIFY_MAX_ACTIONS", name = "Max actions / lobby",
              default = 6, min = 1, max = 30, step = 1, desc = "Batas aksi Fortify tiap kali di Lobby." },
            { t = "step", key = "FORTIFY_GOLD_RESERVE", name = "Gold reserve",
              default = 10000, min = 0, max = 10000000, step = 5000, desc = "Gold yang disisakan." },
            { t = "section", name = "Enchant" },
            { t = "step", key = "ENCHANT_MIN_FORTIFY", name = "Min Fortify to enchant",
              default = 4, min = 0, max = 10, step = 1, desc = "Hanya enchant gear dengan Fortify segini." },
            { t = "step", key = "ENCHANT_MAX_ACTIONS", name = "Max actions / lobby",
              default = 1, min = 1, max = 10, step = 1, desc = "Batas aksi Enchant tiap Lobby." },
            { t = "step", key = "ENCHANT_GOLD_RESERVE", name = "Gold reserve",
              default = 10000, min = 0, max = 10000000, step = 5000, desc = "Gold yang disisakan." },
            { t = "section", name = "Gold Grocery" },
            { t = "step", key = "SHOP_GOLD_RESERVE", name = "Gold reserve",
              default = 20000, min = 0, max = 10000000, step = 5000, desc = "Gold yang disisakan." },
            { t = "step", key = "SHOP_MAX_BUYS", name = "Max buys / pass",
              default = 3, min = 1, max = 10, step = 1, desc = "Pembelian maksimal sekali jalan." },
        },
    },
    {
        id = "system", tab = "System", title = "System",
        items = {
            { t = "section", name = "Performance" },
            { t = "step", key = "FPS_CAP", name = "FPS cap",
              default = 8, min = 1, max = 240, step = 1, unit = " fps",
              desc = "Batas FPS (hemat baterai/CPU). Langsung diterapkan.", apply = "fps" },
            { t = "toggle", key = "HEADLESS", name = "Headless",
              desc = "Dibaca bootstrap. Berlaku pada run / teleport berikutnya." },
            { t = "toggle", key = "DEBUG_LOGS", name = "Debug logs", default = false,
              desc = "Aktifkan log tambahan." },
        },
    },
}

--========================================================--
-- SETTINGS (config + persistence)
--========================================================--
getgenv().IronSoulConfig = getgenv().IronSoulConfig or {}

local saved = {}

local function cfg()
    local c = getgenv().IronSoulConfig
    if type(c) ~= "table" then
        c = {}
        getgenv().IronSoulConfig = c
        for k, v in pairs(saved) do c[k] = v end
    end
    return c
end

local function loadSaved()
    if type(readfile) ~= "function" then return end
    if type(isfile) == "function" then
        local okf, exists = pcall(isfile, SAVE_FILE)
        if not okf or not exists then return end
    end
    local ok, text = pcall(readfile, SAVE_FILE)
    if not ok or type(text) ~= "string" or text == "" then return end
    local okj, data = pcall(function() return HttpService:JSONDecode(text) end)
    if okj and type(data) == "table" then saved = data end
end

local saveQueued = false
local function persist()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.4, function()
        saveQueued = false
        if type(writefile) ~= "function" then return end
        local ok, text = pcall(function() return HttpService:JSONEncode(saved) end)
        if ok then pcall(writefile, SAVE_FILE, text) end
    end)
end

-- Index of every control definition by key.
local DEF = {}
for _, page in ipairs(PAGES) do
    for _, item in ipairs(page.items) do
        if item.key then
            if item.t == "toggle" and item.default == nil then item.default = true end
            DEF[item.key] = item
        end
    end
end

loadSaved()
for key, value in pairs(saved) do
    if DEF[key] ~= nil or key == "UI_OPEN" then
        cfg()[key] = value
    end
end

local function getValue(key)
    local v = cfg()[key]
    if v == nil then
        local d = DEF[key]
        return d and d.default
    end
    return v
end

local function applyHooks(key)
    local d = DEF[key]
    if d and d.apply == "fps" and type(setfpscap) == "function" then
        pcall(setfpscap, tonumber(cfg()[key]) or d.default)
    end
end

-- Apply persisted FPS cap right away (only when the user changed it before).
if saved.FPS_CAP ~= nil then applyHooks("FPS_CAP") end

--========================================================--
-- STATUS LOG
--========================================================--
local LOG_MAX = 80
local logLines = {}
local lastStatus = "Ready"
local logListeners = {}

local function pushLog(text)
    text = tostring(text or "")
    lastStatus = text
    local stamp = os.date("%H:%M:%S")
    table.insert(logLines, stamp .. "  " .. text)
    if #logLines > LOG_MAX then table.remove(logLines, 1) end
    for _, fn in ipairs(logListeners) do pcall(fn, stamp, text) end
end

do
    local previous = rawget(getgenv(), "IronSoulStatus")
    local wrapper
    wrapper = function(text)
        pushLog(text)
        if type(previous) == "function" and previous ~= wrapper then
            pcall(previous, text)
        end
    end
    getgenv().IronSoulStatus = wrapper
end

--========================================================--
-- GUI
--========================================================--
local C = {
    bg = Color3.fromRGB(14, 18, 28),
    panel = Color3.fromRGB(20, 26, 40),
    card = Color3.fromRGB(28, 36, 55),
    cardHi = Color3.fromRGB(36, 46, 70),
    text = Color3.fromRGB(235, 240, 250),
    sub = Color3.fromRGB(150, 162, 186),
    accent = Color3.fromRGB(79, 140, 255),
    on = Color3.fromRGB(52, 211, 153),
    off = Color3.fromRGB(70, 80, 104),
    danger = Color3.fromRGB(239, 90, 90),
}

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    if parent then obj.Parent = parent end
    return obj
end

local function corner(obj, r)
    new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, obj)
end

local function pad(obj, l, t, r, b)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
        PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
    }, obj)
end

local function guiParent()
    local okH, h = pcall(function() return type(gethui) == "function" and gethui() or nil end)
    if okH and h then return h end
    local okC, core = pcall(function() return game:GetService("CoreGui") end)
    if okC and core then
        local probe = Instance.new("ScreenGui")
        local okP = pcall(function() probe.Parent = core end)
        probe:Destroy()
        if okP then return core end
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local connections = {}
local function track(conn) table.insert(connections, conn); return conn end

local refreshers = {}   -- key -> { function() refresh visuals } (a key can appear twice)
local function addRefresher(key, fn)
    refreshers[key] = refreshers[key] or {}
    table.insert(refreshers[key], fn)
end
local featureKeys = {}  -- toggle keys controlled by "Enable/Disable all"
for _, page in ipairs(PAGES) do
    if page.id == "auto" or page.id == "farm" then
        for _, item in ipairs(page.items) do
            if item.t == "toggle" then table.insert(featureKeys, item.key) end
        end
    end
end

local function setValue(key, value)
    cfg()[key] = value
    saved[key] = value
    applyHooks(key)
    persist()
    for _, r in ipairs(refreshers[key] or {}) do pcall(r) end
end

local gui, panel, floatBtn, pageHolder, navBar, titleLabel
local pages, navButtons = {}, {}
local currentTab = "home"
local homeRefresh

local function build()
    gui = new("ScreenGui", {
        Name = "IronSoulControlPanel", ResetOnSpawn = false,
        IgnoreGuiInset = true, DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    gui.Parent = guiParent()

    ---------------------------------------------------------------- panel
    panel = new("Frame", {
        Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0.94, 0, 0.82, 0),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true,
        Visible = getValue("UI_OPEN") ~= false,
    }, gui)
    corner(panel, 16)
    new("UISizeConstraint", { MaxSize = Vector2.new(480, 700), MinSize = Vector2.new(260, 300) }, panel)
    new("UIStroke", { Color = C.cardHi, Thickness = 1 }, panel)

    -- header (drag handle)
    local header = new("Frame", {
        Name = "Header", Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
    }, panel)
    titleLabel = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 0),
        Size = UDim2.new(1, -80, 1, 0), Font = Enum.Font.GothamBold, TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.text,
        Text = "Iron Soul  Control",
    }, header)

    local hide = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.new(0, 44, 0, 36), BackgroundColor3 = C.card, AutoButtonColor = true,
        Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C.text, Text = "-",
    }, header)
    corner(hide, 10)

    -- dragging (mouse + touch)
    do
        local dragging, startInput, startPos, startMouse
        track(header.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                startInput = input
                startMouse = input.Position
                startPos = panel.Position
                track(input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end))
            end
        end))
        track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - startMouse
                panel.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end))
    end

    pageHolder = new("Frame", {
        Name = "Pages", Position = UDim2.new(0, 0, 0, 52),
        Size = UDim2.new(1, 0, 1, -52 - 56), BackgroundTransparency = 1,
    }, panel)

    navBar = new("Frame", {
        Name = "Nav", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = C.panel, BorderSizePixel = 0,
    }, panel)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4),
    }, navBar)

    ---------------------------------------------------------------- floating button
    floatBtn = new("TextButton", {
        Name = "Toggle", Size = UDim2.new(0, 48, 0, 48),
        Position = UDim2.new(0, 10, 0.4, 0), BackgroundColor3 = C.accent,
        Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1),
        Text = "IS", AutoButtonColor = true, ZIndex = 50,
        Visible = true,
    }, gui)
    corner(floatBtn, 24)
    new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.7, Thickness = 1 }, floatBtn)

    local function setOpen(open)
        panel.Visible = open
        setValue("UI_OPEN", open)
    end
    UI.Show = function() if panel then setOpen(true) end end
    UI.Hide = function() if panel then setOpen(false) end end

    track(hide.MouseButton1Click:Connect(function() setOpen(false) end))

    -- float button: drag or tap
    do
        local dragging, moved, startMouse, startPos
        track(floatBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging, moved = true, false
                startMouse = input.Position
                startPos = floatBtn.Position
                track(input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                        if not moved then setOpen(not panel.Visible) end
                    end
                end))
            end
        end))
        track(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - startMouse
                if d.Magnitude > 8 then moved = true end
                if moved then
                    floatBtn.Position = UDim2.new(
                        startPos.X.Scale, startPos.X.Offset + d.X,
                        startPos.Y.Scale, startPos.Y.Offset + d.Y)
                end
            end
        end))
    end
end

---------------------------------------------------------------- page helpers
local function newPage(id)
    local sf = new("ScrollingFrame", {
        Name = id, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = C.sub,
        CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
    }, pageHolder)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, sf)
    pad(sf, 12, 10, 12, 14)
    pages[id] = sf
    return sf
end

local order = 0
local function nextOrder() order += 1; return order end

local function sectionLabel(parent, text)
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.accent,
        TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(text),
        LayoutOrder = nextOrder(),
    }, parent)
end

local function rowBase(parent, def, rightWidth)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 62), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, parent)
    corner(row, 12)
    pad(row, 14, 10, 14, 10)

    local left = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, -(rightWidth + 10), 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, row)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, left)
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20),
        Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        Text = def.name, LayoutOrder = 1,
    }, left)
    if def.desc then
        new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
            Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.sub,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Text = def.desc, LayoutOrder = 2,
        }, left)
    end
    return row
end

local function makeToggle(parent, def)
    local row = rowBase(parent, def, 56)

    local track_ = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 56, 0, 30), BackgroundColor3 = C.off, BorderSizePixel = 0,
    }, row)
    corner(track_, 15)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, track_)
    corner(knob, 12)

    -- whole row is tappable (big touch target)
    local hit = new("TextButton", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 28, 1, 20),
        Position = UDim2.new(0, -14, 0, -10), Text = "", ZIndex = 5,
    }, row)

    local function refresh()
        local on = getValue(def.key) ~= false
        TweenService:Create(track_, TweenInfo.new(0.15), { BackgroundColor3 = on and C.on or C.off }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(0, 29, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        }):Play()
    end
    addRefresher(def.key, function() refresh(); if homeRefresh then homeRefresh() end end)
    refresh()

    track(hit.MouseButton1Click:Connect(function()
        setValue(def.key, not (getValue(def.key) ~= false))
    end))
end

local function makeStepper(parent, def)
    local row = rowBase(parent, def, 150)

    local box = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 150, 0, 40), BackgroundTransparency = 1,
    }, row)

    local function btn(text, x)
        local b = new("TextButton", {
            Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(0, 40, 1, 0),
            AnchorPoint = Vector2.new(x, 0),
            BackgroundColor3 = C.cardHi, Font = Enum.Font.GothamBold, TextSize = 20,
            TextColor3 = C.text, Text = text, AutoButtonColor = true,
        }, box)
        corner(b, 10)
        return b
    end
    local minus, plus = btn("-", 0), btn("+", 1)
    local valueLabel = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 42, 0, 0),
        Size = UDim2.new(1, -84, 1, 0), Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = C.text, TextWrapped = true,
    }, box)

    local function fmt(v)
        local n = tonumber(v) or def.default
        local s
        if n >= 10000 then
            s = string.format("%dk", math.floor(n / 1000))
            if n % 1000 ~= 0 then s = tostring(n) end
        else
            s = tostring(n)
        end
        return s .. (def.unit or "")
    end
    local function refresh() valueLabel.Text = fmt(getValue(def.key)) end
    addRefresher(def.key, refresh)
    refresh()

    local function bump(dir)
        local cur = tonumber(getValue(def.key)) or def.default
        local nv = math.clamp(cur + dir * def.step, def.min, def.max)
        if nv ~= cur then setValue(def.key, nv) end
    end

    -- tap = one step, hold = repeat (accelerating)
    local function hold(button, dir)
        local token = 0
        track(button.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                token += 1
                local my = token
                bump(dir)
                task.spawn(function()
                    task.wait(0.45)
                    local n = 0
                    while token == my and UI.Alive do
                        n += 1
                        for _ = 1, (n > 12 and 5 or 1) do bump(dir) end
                        task.wait(0.08)
                    end
                end)
                track(input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then token += 1 end
                end))
            end
        end))
    end
    hold(minus, -1)
    hold(plus, 1)
end

local function makeCycle(parent, def)
    local row = rowBase(parent, def, 110)
    local b = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 110, 0, 40), BackgroundColor3 = C.cardHi,
        Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text, AutoButtonColor = true,
    }, row)
    corner(b, 10)
    local function refresh() b.Text = tostring(getValue(def.key)) end
    addRefresher(def.key, refresh)
    refresh()
    track(b.MouseButton1Click:Connect(function()
        local cur = tostring(getValue(def.key))
        local idx = 1
        for i, o in ipairs(def.options) do if o == cur then idx = i end end
        setValue(def.key, def.options[(idx % #def.options) + 1])
    end))
end

local function makeButton(parent, text, color, onClick)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = color or C.cardHi,
        Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = C.text,
        Text = text, AutoButtonColor = true, LayoutOrder = nextOrder(),
    }, parent)
    corner(b, 12)
    track(b.MouseButton1Click:Connect(onClick))
    return b
end

---------------------------------------------------------------- tabs
local function selectTab(id)
    currentTab = id
    for pid, page in pairs(pages) do page.Visible = (pid == id) end
    for tid, b in pairs(navButtons) do
        local active = tid == id
        b.BackgroundColor3 = active and C.accent or C.panel
        b.TextColor3 = active and Color3.new(1, 1, 1) or C.sub
    end
end

local function addTab(id, label)
    local b = new("TextButton", {
        Size = UDim2.new(0.19, 0, 0, 44), BackgroundColor3 = C.panel,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.sub,
        Text = label, AutoButtonColor = true, LayoutOrder = #navBar:GetChildren(),
    }, navBar)
    corner(b, 10)
    b.TextScaled = true
    new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 8 }, b)
    navButtons[id] = b
    track(b.MouseButton1Click:Connect(function() selectTab(id) end))
end

local function buildPages()
    -- HOME ---------------------------------------------------------
    local home = newPage("home")

    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card, LayoutOrder = nextOrder(),
    }, home)
    corner(card, 12)
    pad(card, 14, 12, 14, 12)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, card)

    local function infoLabel(order_, size, color, font)
        return new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, size + 4),
            AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
            Font = font or Enum.Font.Gotham, TextSize = size, TextColor3 = color or C.text,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = order_,
        }, card)
    end
    local placeLbl = infoLabel(1, 18, C.text, Enum.Font.GothamBold)
    local statusLbl = infoLabel(2, 13, C.sub)
    local activeLbl = infoLabel(3, 13, C.on, Enum.Font.GothamMedium)
    local uptimeLbl = infoLabel(4, 12, C.sub)

    local startedAt = os.clock()
    local function fmtUptime(s)
        s = math.floor(s)
        return string.format("%02d:%02d:%02d", s // 3600, (s % 3600) // 60, s % 60)
    end

    homeRefresh = function()
        local on = 0
        for _, k in ipairs(featureKeys) do if getValue(k) ~= false then on += 1 end end
        activeLbl.Text = string.format("%d / %d fitur aktif", on, #featureKeys)
    end
    local function tick()
        placeLbl.Text = PLACES[game.PlaceId] or ("Story / World  (" .. tostring(game.PlaceId) .. ")")
        statusLbl.Text = lastStatus
        uptimeLbl.Text = "Uptime  " .. fmtUptime(os.clock() - startedAt)
        homeRefresh()
    end
    tick()
    task.spawn(function()
        while UI.Alive do
            task.wait(1)
            if panel and panel.Visible and currentTab == "home" then pcall(tick) end
        end
    end)

    sectionLabel(home, "Quick actions")
    makeButton(home, "Enable all features", C.on, function()
        for _, k in ipairs(featureKeys) do setValue(k, true) end
    end)
    makeButton(home, "Disable all automation", C.danger, function()
        for _, k in ipairs(featureKeys) do setValue(k, false) end
    end)

    sectionLabel(home, "Master")
    makeToggle(home, DEF.UPGRADE_AUTO)

    -- SCHEMA PAGES -------------------------------------------------
    for _, page in ipairs(PAGES) do
        local sf = newPage(page.id)
        for _, item in ipairs(page.items) do
            if item.t == "section" then sectionLabel(sf, item.name)
            elseif item.t == "toggle" then makeToggle(sf, item)
            elseif item.t == "step" then makeStepper(sf, item)
            elseif item.t == "cycle" then makeCycle(sf, item) end
        end

        if page.id == "system" then
            sectionLabel(sf, "Maintenance")
            makeButton(sf, "Reset all settings to default", C.cardHi, function()
                for key in pairs(DEF) do
                    cfg()[key] = nil
                    saved[key] = nil
                    for _, r in ipairs(refreshers[key] or {}) do pcall(r) end
                end
                if homeRefresh then homeRefresh() end
                persist()
                pushLog("Settings reset to default")
            end)
            makeButton(sf, "Copy log to clipboard", C.cardHi, function()
                if type(setclipboard) == "function" then
                    pcall(setclipboard, table.concat(logLines, "\n"))
                    pushLog("Log copied")
                else
                    pushLog("setclipboard unavailable")
                end
            end)
            makeButton(sf, "Close UI completely", C.danger, function()
                UI.Destroy()
            end)
        end
    end

    -- LOG ----------------------------------------------------------
    local log = newPage("log")
    local logBox = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card, LayoutOrder = nextOrder(),
    }, log)
    corner(logBox, 12)
    pad(logBox, 12, 10, 12, 10)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, logBox)

    local shown = 0
    local function addLogLabel(stamp, text)
        shown += 1
        new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
            Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.text,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Text = stamp .. "  " .. text, LayoutOrder = shown,
        }, logBox)
        local kids = {}
        for _, k in ipairs(logBox:GetChildren()) do
            if k:IsA("TextLabel") then table.insert(kids, k) end
        end
        if #kids > LOG_MAX then
            table.sort(kids, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
            kids[1]:Destroy()
        end
    end
    for _, line in ipairs(logLines) do
        local stamp, text = string.match(line, "^(%S+)%s%s(.*)$")
        addLogLabel(stamp or "", text or line)
    end
    table.insert(logListeners, function(stamp, text)
        if UI.Alive then addLogLabel(stamp, text) end
    end)

    -- tabs
    addTab("home", "Home")
    addTab("auto", "Auto")
    addTab("farm", "Farm")
    addTab("upgrade", "Upgrade")
    addTab("system", "System")
    addTab("log", "Log")
    -- six tabs: shrink widths to fit
    for _, b in pairs(navButtons) do b.Size = UDim2.new(0.158, 0, 0, 44) end

    selectTab("home")
end

function UI.Destroy()
    UI.Alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui then pcall(function() gui:Destroy() end) end
    if rawget(getgenv(), "IronSoulUI") == UI then getgenv().IronSoulUI = nil end
end

UI.Show = UI.Show or function() end
UI.Hide = UI.Hide or function() end

local okBuild, errBuild = pcall(function()
    build()
    buildPages()
end)

if not okBuild then
    -- Settings (Config) are already active; only the visuals failed.
    warn("[IronSoul UI] build failed: " .. tostring(errBuild))
    pcall(function() if gui then gui:Destroy() end end)
    UI.Alive = false
else
    getgenv().IronSoulUI = UI
    pushLog("Control panel ready")
end

return UI

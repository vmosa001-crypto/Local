--========================================================--
-- IRON SOUL - UTILITY PANEL (MOBILE UI) V1
--
-- Separate GUI for systems/utility.lua : Dungeon | Tower | Pets | Log.
-- Big touch targets, bottom tab bar, draggable header and a draggable
-- floating "UT" button. Everything on the panel is a live view of the core
-- module (getgenv().IronSoulUtility); closing the panel never stops the
-- automation - switch the toggles off for that.
--========================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

do
    local existing = rawget(getgenv(), "IronSoulUtilityUI")
    if type(existing) == "table" and existing.Alive then
        pcall(existing.Show)
        return existing
    end
end

--------------------------------------------------------------------
-- core
--------------------------------------------------------------------
local function loadCore()
    local core = rawget(getgenv(), "IronSoulUtility")
    if type(core) == "table" and core.Alive then return core end

    local loadRaw = rawget(getgenv(), "IronSoulLoadRaw")
    if type(loadRaw) == "function" then
        local ok, result = loadRaw("systems/utility.lua")
        if ok and type(result) == "table" then return result end
    end

    local base = rawget(getgenv(), "IronSoulBase")
        or "https://raw.githubusercontent.com/vmosa001-crypto/Local/main/"
    local src = game:HttpGet(base .. "systems/utility.lua?t=" .. tostring(os.time()))
    local fn, err = loadstring(src, "=systems/utility.lua")
    assert(fn, err)
    return fn()
end

local U = loadCore()
assert(type(U) == "table", "utility core unavailable")

local UI = { Alive = true, VERSION = "V1" }

--------------------------------------------------------------------
-- theme + helpers
--------------------------------------------------------------------
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
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 10) }, o) end
local function pad(o, l, t, r, b)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t),
        PaddingRight = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
    }, o)
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
local function track(c) table.insert(connections, c); return c end

local refreshers = {}   -- fn() list: re-read values from the core
local function addRefresher(fn) table.insert(refreshers, fn) end
local function refreshAll()
    for _, fn in ipairs(refreshers) do pcall(fn) end
end

--------------------------------------------------------------------
-- layout state
--------------------------------------------------------------------
local gui, panel, pageHolder, navBar, floatBtn
local pages, navButtons = {}, {}
local currentTab = "dungeon"
local order = 0
local function nextOrder() order += 1; return order end

local function newPage(id)
    local sf = new("ScrollingFrame", {
        Name = id, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.sub, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
    }, pageHolder)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, sf)
    pad(sf, 12, 10, 12, 14)
    pages[id] = sf
    return sf
end

local function section(parent, text)
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Font = Enum.Font.GothamBold,
        TextSize = 13, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Left,
        Text = string.upper(text), LayoutOrder = nextOrder(),
    }, parent)
end

-- live info card: lines() returns an array of strings
local function infoCard(parent, linesFn)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = C.card, LayoutOrder = nextOrder(),
    }, parent)
    corner(card, 12)
    pad(card, 14, 12, 14, 12)
    local label = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    }, card)
    addRefresher(function()
        local ok, lines = pcall(linesFn)
        label.Text = ok and table.concat(lines, "\n") or "unavailable"
    end)
end

local function rowBase(parent, name, desc, rightWidth)
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
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamMedium,
        TextSize = 15, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Text = name, LayoutOrder = 1,
    }, left)
    if desc then
        new("TextLabel", {
            BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            TextWrapped = true, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.sub,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
            Text = desc, LayoutOrder = 2,
        }, left)
    end
    return row
end

local function toggleRow(parent, key, name, desc)
    local row = rowBase(parent, name, desc, 56)
    local trackF = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 56, 0, 30), BackgroundColor3 = C.off, BorderSizePixel = 0,
    }, row)
    corner(trackF, 15)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.new(0, 24, 0, 24), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, trackF)
    corner(knob, 12)
    local hit = new("TextButton", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 28, 1, 20), Position = UDim2.new(0, -14, 0, -10),
        Text = "", ZIndex = 5,
    }, row)
    addRefresher(function()
        local on = U.Get(key) == true
        TweenService:Create(trackF, TweenInfo.new(0.15), { BackgroundColor3 = on and C.on or C.off }):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = on and UDim2.new(0, 29, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        }):Play()
    end)
    track(hit.MouseButton1Click:Connect(function()
        U.Set(key, not (U.Get(key) == true))
        refreshAll()
    end))
end

local function stepperRow(parent, key, name, desc, min, max, step, unit)
    local row = rowBase(parent, name, desc, 150)
    local box = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.new(0, 150, 0, 40), BackgroundTransparency = 1,
    }, row)
    local function btn(text, x)
        local b = new("TextButton", {
            AnchorPoint = Vector2.new(x, 0), Position = UDim2.new(x, 0, 0, 0), Size = UDim2.new(0, 40, 1, 0),
            BackgroundColor3 = C.cardHi, Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = C.text,
            Text = text, AutoButtonColor = true,
        }, box)
        corner(b, 10)
        return b
    end
    local minus, plus = btn("-", 0), btn("+", 1)
    local value = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 42, 0, 0), Size = UDim2.new(1, -84, 1, 0),
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text, TextWrapped = true,
    }, box)
    addRefresher(function()
        local v = tonumber(U.Get(key)) or 0
        value.Text = tostring(v) .. (unit or "")
    end)
    local function bump(dir)
        local cur = tonumber(U.Get(key)) or 0
        local nv = math.clamp(cur + dir * step, min, max)
        if nv ~= cur then U.Set(key, nv); refreshAll() end
    end
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

local function button(parent, text, color, onClick)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = color or C.cardHi, Font = Enum.Font.GothamBold,
        TextSize = 15, TextColor3 = C.text, Text = text, AutoButtonColor = true, LayoutOrder = nextOrder(),
    }, parent)
    corner(b, 12)
    track(b.MouseButton1Click:Connect(function() pcall(onClick, b) end))
    return b
end

--------------------------------------------------------------------
-- picker (modal list) : replaces dropdowns, thumb friendly
--------------------------------------------------------------------
local picker, pickerTitle, pickerList

local function closePicker() if picker then picker.Visible = false end end

-- options: array of { label=, enabled=, selected=, value= }
-- multi = true : tapping toggles `selected` and keeps the list open;
--                onPick(o, options) runs after every tap.
local function openPicker(title, options, onPick, multi)
    pickerTitle.Text = title
    for _, c in ipairs(pickerList:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    for i, o in ipairs(options) do
        local function text()
            return (multi and (o.selected and "  [x]  " or "  [ ]  ") or "  ")
                .. tostring(o.label) .. ((o.enabled == false) and "   (locked)" or "")
        end
        local b = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, AutoButtonColor = o.enabled ~= false,
            BackgroundColor3 = o.selected and C.accent or C.card, Font = Enum.Font.GothamMedium, TextSize = 14,
            TextColor3 = (o.enabled == false) and C.sub or C.text, TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd, Text = text(),
        }, pickerList)
        corner(b, 10)
        track(b.MouseButton1Click:Connect(function()
            if o.enabled == false and not (multi and o.selected) then return end
            if multi then
                o.selected = not o.selected
                b.BackgroundColor3 = o.selected and C.accent or C.card
                b.Text = text()
                pcall(onPick, o, options)
            else
                closePicker()
                pcall(onPick, o)
            end
        end))
    end
    picker.Visible = true
end

-- Shown instead of the list when building it failed, so the cause is visible.
local function openPickerError(title, err)
    pickerTitle.Text = title
    for _, c in ipairs(pickerList:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        TextWrapped = true, Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.danger,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 31,
        Text = "Gagal memuat daftar:\n" .. tostring(err) .. "\n\nTutup lalu coba lagi / buka tab Log.",
    }, pickerList)
    picker.Visible = true
end

local function pickerRow(parent, name, desc, currentFn, openFn)
    local row = rowBase(parent, name, desc, 150)
    local b = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 150, 0, 40),
        BackgroundColor3 = C.cardHi, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text,
        TextWrapped = true, AutoButtonColor = true,
    }, row)
    corner(b, 10)
    addRefresher(function()
        local ok, text = pcall(currentFn)
        b.Text = (ok and tostring(text) or "?") .. "  v"
    end)
    track(b.MouseButton1Click:Connect(function()
        -- own thread: building a list may yield, and a failure must not be silent
        task.spawn(function()
            local ok, err = pcall(openFn)
            if not ok then
                warn("[IronSoul UtilityUI] " .. tostring(name) .. ": " .. tostring(err))
                pcall(openPickerError, name, err)
            end
        end)
    end))
end

-- text input row (username etc.)
local function textRow(parent, key, name, desc, placeholder)
    local row = rowBase(parent, name, desc, 150)
    local box = new("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 150, 0, 40),
        BackgroundColor3 = C.cardHi, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.text,
        PlaceholderText = placeholder or "", PlaceholderColor3 = C.sub, ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.AtEnd, Text = "",
    }, row)
    corner(box, 10)
    addRefresher(function()
        if not box:IsFocused() then box.Text = tostring(U.Get(key) or "") end
    end)
    track(box.FocusLost:Connect(function()
        U.Set(key, box.Text)
        box.Text = tostring(U.Get(key) or "")
    end))
end

--------------------------------------------------------------------
-- formatting
--------------------------------------------------------------------
local function fmtTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    return string.format("%d:%02d", sec // 60, sec % 60)
end

local function worldLabel()
    local ok, list = pcall(U.Dungeon.GetCatalog)
    if ok then
        for _, e in ipairs(list) do
            if e.WorldId == U.Get("DUNGEON_WORLD") then return e.Name end
        end
    end
    return tostring(U.Get("DUNGEON_WORLD"))
end

local function diffLabel()
    local ok, list = pcall(U.Dungeon.GetDifficulties, U.Get("DUNGEON_WORLD"))
    if ok then
        for _, e in ipairs(list) do
            if e.Level == U.Get("DUNGEON_DIFF") then return e.Name end
        end
    end
    return "Level " .. tostring(U.Get("DUNGEON_DIFF"))
end

--------------------------------------------------------------------
-- pages
--------------------------------------------------------------------
local MODE_LABELS = {
    normal = "Normal", hell = "Hell", both = "Normal + Hell", manual = "Pilih difficulty",
}

local function mapsLabel()
    local ids = U.Get("DUNGEON_MAPS")
    if #ids == 0 then return "Belum dipilih" end
    if #ids == 1 then
        local ok, list = pcall(U.Dungeon.GetCatalog)
        if ok then
            for _, e in ipairs(list) do
                if e.WorldId == ids[1] then return e.Name end
            end
        end
    end
    return #ids .. " map"
end

local function smartDiffLabel()
    local lv = U.Get("DUNGEON_SMART_DIFF")
    local ref = U.Get("DUNGEON_MAPS")[1] or U.Get("DUNGEON_WORLD")
    local ok, list = pcall(U.Dungeon.GetDifficulties, ref)
    if ok then
        for _, e in ipairs(list) do
            if e.Level == lv then return e.Name end
        end
    end
    return "Level " .. tostring(lv)
end

local function buildDungeon()
    local p = newPage("dungeon")
    infoCard(p, function()
        local rep, follow = U.Dungeon.GetRepeatInfo(), U.Dungeon.GetFollowInfo()
        local lines = { "STATUS  " .. U.GetStatus("Dungeon") }
        if U.Get("DUNGEON_SMART") then
            table.insert(lines, "NEXT  " .. tostring(U.Dungeon.GetNextTarget() or "-"))
            table.insert(lines, "MODE  " .. (MODE_LABELS[U.Get("DUNGEON_MODE")] or "?")
                .. "   MAPS  " .. #U.Get("DUNGEON_MAPS"))
        else
            table.insert(lines, "TARGET  " .. worldLabel() .. "  /  " .. diffLabel())
        end
        table.insert(lines, "REPEAT  " .. rep.Done .. " / " .. (rep.Total > 0 and tostring(rep.Total) or "tanpa batas"))
        table.insert(lines, "PLAYERS  " .. tostring(U.Get("DUNGEON_PLAYERS")))
        if follow.Enabled then
            local t = "FOLLOW  " .. (follow.User ~= "" and follow.User or "(username kosong)") .. "  -  "
            if not follow.Present then
                t = t .. "belum ada di server"
            elseif follow.Remaining then
                t = t .. "join dalam " .. math.ceil(follow.Remaining) .. " s"
            else
                t = t .. "ada di server"
            end
            table.insert(lines, t)
        end
        return lines
    end)

    section(p, "Auto")
    toggleRow(p, "DUNGEON_AUTO", "Auto dungeon",
        "Dari Lobby: sentuh portal kosong lalu buat room, 1 match tiap masuk lobby. Mematikan Tower.")
    stepperRow(p, "DUNGEON_REPEAT", "Repeat match",
        "Jumlah match (1 per masuk lobby). 0 = tanpa batas. Auto mati sendiri setelah selesai.", 0, 999, 1, "x")
    button(p, "Reset hitungan repeat", C.cardHi, function()
        U.Set("DUNGEON_REPEAT_DONE", 0)
        refreshAll()
    end)

    section(p, "Preset (1 map + difficulty)")
    pickerRow(p, "Dungeon", "Pilih dunia (yang terkunci tidak bisa).", worldLabel, function()
        local opts = {}
        for _, e in ipairs(U.Dungeon.GetCatalog(true)) do
            table.insert(opts, {
                label = e.Name .. "  (" .. e.WorldId .. ")", enabled = e.Unlocked,
                selected = e.WorldId == U.Get("DUNGEON_WORLD"), value = e.WorldId,
            })
        end
        openPicker("Pilih Dungeon", opts, function(o)
            U.Dungeon.SelectWorld(o.value)
            refreshAll()
        end)
    end)
    pickerRow(p, "Difficulty", "Level kesulitan yang sudah terbuka.", diffLabel, function()
        local opts = {}
        for _, e in ipairs(U.Dungeon.GetDifficulties(U.Get("DUNGEON_WORLD"), true)) do
            table.insert(opts, {
                label = e.Name, enabled = e.Unlocked, selected = e.Level == U.Get("DUNGEON_DIFF"), value = e.Level,
            })
        end
        openPicker("Pilih Difficulty", opts, function(o)
            U.Dungeon.SelectDifficulty(o.value)
            refreshAll()
        end)
    end)

    section(p, "Auto map & difficulty tertinggi")
    toggleRow(p, "DUNGEON_SMART", "Pakai auto map",
        "Masuk map dari daftar di bawah (bergantian) ke difficulty tertinggi sesuai mode. Menggantikan preset.")
    pickerRow(p, "Pilih map", "Boleh lebih dari satu.", mapsLabel, function()
        local chosen, opts = {}, {}
        for _, id in ipairs(U.Get("DUNGEON_MAPS")) do chosen[id] = true end
        for _, e in ipairs(U.Dungeon.GetCatalog(true)) do
            table.insert(opts, {
                label = e.Name .. "  (" .. e.WorldId .. ")", enabled = e.Unlocked,
                selected = chosen[e.WorldId] == true, value = e.WorldId,
            })
        end
        openPicker("Pilih map (bisa banyak)", opts, function(_, all)
            local list = {}
            for _, o in ipairs(all) do
                if o.selected then table.insert(list, o.value) end
            end
            U.Set("DUNGEON_MAPS", list)
            refreshAll()
        end, true)
    end)
    pickerRow(p, "Mode", "Normal / Hell / gabungan, atau pilih difficulty sendiri.", function()
        return MODE_LABELS[U.Get("DUNGEON_MODE")] or "?"
    end, function()
        local opts = {}
        for _, id in ipairs({ "normal", "hell", "both", "manual" }) do
            table.insert(opts, { label = MODE_LABELS[id], value = id, selected = U.Get("DUNGEON_MODE") == id })
        end
        openPicker("Pilih mode", opts, function(o)
            U.Set("DUNGEON_MODE", o.value)
            refreshAll()
        end)
    end)
    pickerRow(p, "Difficulty (mode manual)",
        "Dipakai jika mode = Pilih difficulty. Jika terkunci, dipakai yang tertinggi di bawahnya.", smartDiffLabel,
        function()
            local ref = U.Get("DUNGEON_MAPS")[1] or U.Get("DUNGEON_WORLD")
            local opts = {}
            for _, e in ipairs(U.Dungeon.GetDifficulties(ref, true)) do
                table.insert(opts, {
                    label = e.Name, selected = e.Level == U.Get("DUNGEON_SMART_DIFF"), value = e.Level,
                })
            end
            openPicker("Pilih difficulty", opts, function(o)
                U.Set("DUNGEON_SMART_DIFF", o.value)
                refreshAll()
            end)
        end)

    section(p, "Join countdown")
    toggleRow(p, "FOLLOW_ENABLE", "Tunggu user di server",
        "Auto dungeon baru jalan setelah user di bawah ada di server yang sama, lalu hitung mundur.")
    textRow(p, "FOLLOW_USER", "Username", "Username atau display name.", "username")
    stepperRow(p, "FOLLOW_DELAY", "Delay join", "Hitung mundur sebelum masuk.", 0, 300, 1, " s")

    section(p, "Room")
    stepperRow(p, "DUNGEON_PLAYERS", "Max players", "Solo = 1.", 1, 4, 1, "")
    stepperRow(p, "DUNGEON_DELAY", "Retry delay", "Jeda antar percobaan membuat room.", 3, 120, 1, " s")

    section(p, "Manual")
    button(p, "Start dungeon now", C.on, function()
        task.spawn(function() pcall(U.Dungeon.StartNow); refreshAll() end)
    end)
    button(p, "Refresh dungeon list", C.cardHi, function()
        task.spawn(function() pcall(U.Dungeon.GetCatalog, true); refreshAll() end)
    end)
end

local function buildTower()
    local p = newPage("tower")
    infoCard(p, function()
        local info = U.Tower.GetInfo()
        local lines = {
            "STATUS  " .. U.GetStatus("Tower"),
            "BEST ROUND  " .. tostring(info.Record) .. "   NEXT START  " .. tostring(info.NextStart),
            "WEAPON  " .. U.GetStatus("Weapon"),
        }
        if info.Players > 1 then
            local t = "PLAYERS  " .. info.Have .. " / " .. info.Players
            if info.WaitLeft then t = t .. "   (tunggu " .. math.ceil(info.WaitLeft) .. " s)" end
            table.insert(lines, t)
        end
        return lines
    end)

    section(p, "Auto")
    toggleRow(p, "TOWER_AUTO", "Auto join Endless Tower",
        "Sentuh Room 9/10, buat room, equip extra weapon, tekan Start. Mematikan Auto dungeon.")
    pickerRow(p, "Starting round", "Highest = ronde tertinggi yang terbuka.", function()
        local r = U.Get("TOWER_START_ROUND")
        return r == 0 and "Highest" or ("Round " .. r)
    end, function()
        local highest = U.Tower.GetHighest()
        local opts = { { label = "Highest unlocked", value = 0, selected = U.Get("TOWER_START_ROUND") == 0 } }
        for r = 1, 196, 5 do
            table.insert(opts, {
                label = "Round " .. r, value = r, enabled = r <= highest, selected = U.Get("TOWER_START_ROUND") == r,
            })
        end
        openPicker("Starting round", opts, function(o)
            U.Set("TOWER_START_ROUND", o.value)
            refreshAll()
        end)
    end)
    stepperRow(p, "TOWER_PLAYERS", "Max players", "Solo = 1. Lebih dari 1: Start ditahan sampai pemain lengkap.", 1, 4, 1, "")
    stepperRow(p, "TOWER_WAIT", "Tunggu pemain",
        "Detik menunggu pemain lengkap sebelum Start. 0 = langsung Start. Habis waktu = Start tetap.", 0, 300, 5, " s")
    pickerRow(p, "Extra weapon", "Senjata ekstra saat Start.", function()
        local id = U.Get("TOWER_WEAPON")
        if id == "" then return "Highest DMG" end
        for _, o in ipairs(U.Tower.GetWeaponOptions()) do
            if o.UUID == id then return o.Label end
        end
        return "Highest DMG (fallback)"
    end, function()
        local opts = { { label = "Highest damage (auto)", value = "", selected = U.Get("TOWER_WEAPON") == "" } }
        for _, o in ipairs(U.Tower.GetWeaponOptions()) do
            table.insert(opts, { label = o.Label, value = o.UUID, selected = o.UUID == U.Get("TOWER_WEAPON") })
        end
        openPicker("Extra weapon", opts, function(o)
            U.Set("TOWER_WEAPON", o.value)
            U.Tower.ResetWeaponRequest()
            refreshAll()
        end)
    end)
end

local function buildPets()
    local p = newPage("pets")

    section(p, "Egg hatching")
    infoCard(p, function()
        local info = U.Pets.Hatch.GetInfo()
        local lines = { "STATUS  " .. U.GetStatus("Hatch"), "EGGS OWNED  " .. tostring(info.Eggs) }
        for _, s in ipairs(info.Slots) do
            local t = "SLOT " .. s.Index .. "  " .. s.State
            if s.Remaining then t = t .. "  " .. fmtTime(s.Remaining) end
            table.insert(lines, t)
        end
        return lines
    end)
    toggleRow(p, "HATCH_AUTO", "Auto hatch eggs", "Claim telur selesai dan mulai telur dengan rarity tertinggi.")

    section(p, "Pet expedition")
    infoCard(p, function()
        local info = U.Pets.Expedition.GetInfo()
        local lines = {
            "STATUS  " .. U.GetStatus("Expedition"),
            "DAILY CHANCES  " .. info.Remaining .. " / " .. info.Limit,
        }
        for _, s in ipairs(info.Slots) do
            table.insert(lines, "SLOT " .. s.Index .. "  " .. s.State)
        end
        return lines
    end)
    toggleRow(p, "EXP_DISPATCH", "Auto dispatch", "Kirim pet terbaik (affinity, rarity) ke slot kosong.")
    toggleRow(p, "EXP_CLAIM", "Auto claim", "Ambil hadiah expedition yang selesai.")

    -- slot chips
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card,
        LayoutOrder = nextOrder(),
    }, p)
    corner(card, 12)
    pad(card, 14, 10, 14, 12)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, card)
    new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20), Font = Enum.Font.GothamMedium, TextSize = 15,
        TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "Slot yang dipakai", LayoutOrder = 1,
    }, card)
    local grid = new("Frame", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 2,
    }, card)
    new("UIGridLayout", {
        CellSize = UDim2.new(0, 58, 0, 44), CellPadding = UDim2.new(0, 8, 0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, grid)

    local slotCount = 4
    pcall(function() slotCount = U.Pets.Expedition.GetInfo().SlotCount end)
    local chips = {}
    for i = 1, slotCount do
        local chip = new("TextButton", {
            LayoutOrder = i, BackgroundColor3 = C.off, Font = Enum.Font.GothamBold, TextSize = 16,
            TextColor3 = C.text, Text = tostring(i), AutoButtonColor = true,
        }, grid)
        corner(chip, 10)
        chips[i] = chip
        track(chip.MouseButton1Click:Connect(function()
            local set, found = {}, false
            for _, s in ipairs(U.Get("EXP_SLOTS")) do
                if s == i then found = true else table.insert(set, s) end
            end
            if not found then table.insert(set, i) end
            U.Set("EXP_SLOTS", set)
            refreshAll()
        end))
    end
    addRefresher(function()
        local active = {}
        for _, s in ipairs(U.Get("EXP_SLOTS")) do active[s] = true end
        for i, chip in pairs(chips) do chip.BackgroundColor3 = active[i] and C.on or C.off end
    end)
end

local function buildLog()
    local p = newPage("log")
    local box = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card,
        LayoutOrder = nextOrder(),
    }, p)
    corner(box, 12)
    pad(box, 12, 10, 12, 10)
    local text = new("TextLabel", {
        BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, Font = Enum.Font.Code, TextSize = 12, TextColor3 = C.text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
    }, box)
    addRefresher(function()
        local lines = U.GetLog()
        local from = math.max(1, #lines - 40)
        local out = {}
        for i = #lines, from, -1 do table.insert(out, lines[i]) end
        text.Text = #out > 0 and table.concat(out, "\n") or "(no events yet)"
    end)
    button(p, "Copy log", C.cardHi, function()
        if type(setclipboard) == "function" then pcall(setclipboard, table.concat(U.GetLog(), "\n")) end
    end)
    button(p, "Close panel (automation keeps running)", C.danger, function() UI.Destroy() end)
end

--------------------------------------------------------------------
-- frame, tabs, dragging
--------------------------------------------------------------------
local function selectTab(id)
    currentTab = id
    closePicker()
    for pid, page in pairs(pages) do page.Visible = pid == id end
    for tid, b in pairs(navButtons) do
        local active = tid == id
        b.BackgroundColor3 = active and C.accent or C.panel
        b.TextColor3 = active and Color3.new(1, 1, 1) or C.sub
    end
    refreshAll()
end

local function addTab(id, label)
    local b = new("TextButton", {
        Size = UDim2.new(0.235, 0, 0, 44), BackgroundColor3 = C.panel, Font = Enum.Font.GothamBold,
        TextSize = 13, TextColor3 = C.sub, Text = label, AutoButtonColor = true, LayoutOrder = #navBar:GetChildren(),
    }, navBar)
    corner(b, 10)
    navButtons[id] = b
    track(b.MouseButton1Click:Connect(function() selectTab(id) end))
end

local function makeDraggable(handle, target, onTap)
    local dragging, moved, startMouse, startPos
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved = true, false
            startMouse, startPos = input.Position, target.Position
            track(input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if onTap and not moved then onTap() end
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
                target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end))
end

local function build()
    gui = new("ScreenGui", {
        Name = "IronSoulUtilityPanel", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 998,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    gui.Parent = guiParent()

    panel = new("Frame", {
        Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0.94, 0, 0.82, 0), BackgroundColor3 = C.bg, BorderSizePixel = 0,
        ClipsDescendants = true, Visible = true,
    }, gui)
    corner(panel, 16)
    new("UISizeConstraint", { MaxSize = Vector2.new(480, 700), MinSize = Vector2.new(260, 300) }, panel)
    new("UIStroke", { Color = C.cardHi, Thickness = 1 }, panel)

    local header = new("Frame", {
        Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = C.panel, BorderSizePixel = 0,
    }, panel)
    new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(1, -80, 1, 0),
        Font = Enum.Font.GothamBold, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = C.text, Text = "Utility  Dungeon / Tower / Pets",
    }, header)
    local hide = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.new(0, 44, 0, 36),
        BackgroundColor3 = C.card, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = C.text, Text = "-",
    }, header)
    corner(hide, 10)
    makeDraggable(header, panel)

    pageHolder = new("Frame", {
        Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 1, -52 - 56), BackgroundTransparency = 1,
    }, panel)

    navBar = new("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 56),
        BackgroundColor3 = C.panel, BorderSizePixel = 0,
    }, panel)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    }, navBar)

    -- picker overlay (sits above pages, below nothing)
    picker = new("Frame", {
        Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 1, -52), BackgroundColor3 = C.bg,
        BorderSizePixel = 0, Visible = false, ZIndex = 30,
    }, panel)
    pickerTitle = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(1, -110, 0, 48),
        Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 31,
    }, picker)
    local pickerClose = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.new(0, 84, 0, 36),
        BackgroundColor3 = C.cardHi, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.text,
        Text = "Close", ZIndex = 31,
    }, picker)
    corner(pickerClose, 10)
    track(pickerClose.MouseButton1Click:Connect(closePicker))
    pickerList = new("ScrollingFrame", {
        Position = UDim2.new(0, 0, 0, 52), Size = UDim2.new(1, 0, 1, -52), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, ZIndex = 31,
    }, picker)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, pickerList)
    pad(pickerList, 12, 4, 12, 12)

    floatBtn = new("TextButton", {
        Name = "Toggle", Size = UDim2.new(0, 48, 0, 48), Position = UDim2.new(0, 10, 0.55, 0),
        BackgroundColor3 = C.on, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = Color3.new(1, 1, 1),
        Text = "UT", AutoButtonColor = true, ZIndex = 50,
    }, gui)
    corner(floatBtn, 24)
    new("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.7, Thickness = 1 }, floatBtn)

    local function setOpen(open)
        panel.Visible = open
        if open then refreshAll() end
    end
    UI.Show = function() if panel then setOpen(true) end end
    UI.Hide = function() if panel then setOpen(false) end end
    track(hide.MouseButton1Click:Connect(function() setOpen(false) end))
    makeDraggable(floatBtn, floatBtn, function() setOpen(not panel.Visible) end)
end

function UI.Destroy()
    UI.Alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui then pcall(function() gui:Destroy() end) end
    if rawget(getgenv(), "IronSoulUtilityUI") == UI then getgenv().IronSoulUtilityUI = nil end
end
UI.Show = UI.Show or function() end
UI.Hide = UI.Hide or function() end

local ok, err = pcall(function()
    build()
    buildDungeon()
    buildTower()
    buildPets()
    buildLog()
    addTab("dungeon", "Dungeon")
    addTab("tower", "Tower")
    addTab("pets", "Pets")
    addTab("log", "Log")
    selectTab("dungeon")

    U.OnStatus(function() if UI.Alive and panel and panel.Visible then refreshAll() end end)
    task.spawn(function()
        while UI.Alive do
            task.wait(1)
            if panel and panel.Visible and not picker.Visible then pcall(refreshAll) end
        end
    end)
end)

if not ok then
    warn("[IronSoul UtilityUI] build failed: " .. tostring(err))
    UI.Destroy()
else
    getgenv().IronSoulUtilityUI = UI
end

return UI

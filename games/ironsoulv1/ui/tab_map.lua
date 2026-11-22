--------------------------------------------------------------------------------
--// ui/tab_map.lua — Tab Map: tambah / hapus titik posisi (Vector3) tiap World
--// World yang dikelola = World di dropdown tab Farm (H.WORLD_NAMES).
--------------------------------------------------------------------------------
local H            = getgenv().Hub
local EngineConfig = H.EngineConfig
local LocalPlayer  = H.LocalPlayer
local CustomNotify = H.CustomNotify
local WORLD_NAMES  = H.WORLD_NAMES
local WORLD_INDEX  = H.WORLD_INDEX
local Waypoints    = H.Waypoints
local Maps         = H.Maps   -- bisa nil jika user_data gagal; fitur map baru dilewati

local CreateTab                     = H.CreateTab
local CreateSection                 = H.CreateSection
local CreateCycleUI                 = H.CreateCycleUI
local CreateInputUI                 = H.CreateInputUI
local CreateButton                  = H.CreateButton
local CreateScrollableMultiSelectUI = H.CreateScrollableMultiSelectUI

if not Waypoints then
    warn("[XiFil] tab_map dilewati: H.Waypoints tidak tersedia (user_data.lua gagal dimuat)")
    return
end

local MapPage = CreateTab("🗺️ Map")

local _world = EngineConfig.SelectedWorld
if not WORLD_INDEX[_world] then _world = WORLD_NAMES[1] end

local function currentIdx() return WORLD_INDEX[_world] end

local function fmt(n)
    if n == math.floor(n) then return tostring(math.floor(n)) end
    return string.format("%.1f", n)
end

local function buildItems()
    local list  = Waypoints.Get(currentIdx())
    local items = {}
    for i, p in ipairs(list) do
        items[i] = i .. ". (" .. fmt(p.x) .. ", " .. fmt(p.y) .. ", " .. fmt(p.z) .. ")"
    end
    return items
end

local function noopCallbacks(n)
    local t = {}
    for i = 1, n do t[i] = function() end end
    return t
end

local PointList
local refreshList

local function worldSummary()
    local n = #Waypoints.Get(currentIdx())
    local kind
    if Maps and Maps.IsCustom(_world) then kind = "map buatan"
    elseif Waypoints.IsCustom(currentIdx()) then kind = "custom"
    else kind = "default" end
    return _world .. " — " .. n .. " titik (" .. kind .. ")"
end

-- ── Pilih World ──────────────────────────────────────────────────────────────
CreateSection(MapPage, "Pilih Map")
local WorldCycle = CreateCycleUI(MapPage, "🌍 Map", WORLD_NAMES, _world, function(v)
    _world = v
    if refreshList then refreshList() end
    CustomNotify("🗺️ MAP", worldSummary(), 3)
end)

-- ── Daftar titik ─────────────────────────────────────────────────────────────
CreateSection(MapPage, "Titik Posisi")

local _items  = buildItems()
local _states = {}
for i = 1, #_items do _states[i] = false end
PointList = CreateScrollableMultiSelectUI(MapPage, "Daftar Titik", _items, _states, noopCallbacks(#_items))

refreshList = function()
    local items = buildItems()
    PointList:SetValues(items, noopCallbacks(#items))
    -- Rebuild mempertahankan centang berdasarkan nama; bersihkan supaya tidak
    -- ada titik yang tercentang tanpa disengaja setelah nomor berubah.
    for i = 1, #items do
        if PointList[i] then PointList[i]:SetValue(false) end
    end
end

local function selectedSet()
    local set, n = {}, 0
    for i = 1, #Waypoints.Get(currentIdx()) do
        if PointList[i] and PointList[i].state then set[i] = true; n = n + 1 end
    end
    return set, n
end

-- ── Tambah titik ─────────────────────────────────────────────────────────────
CreateSection(MapPage, "Tambah Titik")

local _coordText = ""
CreateInputUI(MapPage, "Koordinat (x,y,z)", "", false, function(v)
    _coordText = tostring(v or "")
end)

CreateButton(MapPage, "➕ Tambah dari Input (x,y,z / Vector3 / CFrame)", function()
    local x, y, z = Waypoints.Parse(_coordText)
    if not x then
        CustomNotify("⚠️ MAP", "Isi 3 angka: x,y,z — atau tempel Vector3.new(...) / CFrame.new(...)", 4)
        return
    end
    Waypoints.Add(currentIdx(), x, y, z)
    refreshList()
    CustomNotify("✅ MAP", "Titik ditambah. " .. worldSummary(), 3)
end)

CreateButton(MapPage, "📍 Tambah Posisi Saya Sekarang", function()
    local char = LocalPlayer and LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then CustomNotify("⚠️ MAP", "Karakter belum siap.", 3); return end
    local p = hrp.Position
    local function r1(n) return math.floor(n * 10 + 0.5) / 10 end
    Waypoints.Add(currentIdx(), r1(p.X), r1(p.Y), r1(p.Z))
    refreshList()
    CustomNotify("✅ MAP", "Posisi disimpan. " .. worldSummary(), 3)
end)

-- ── Kelola ───────────────────────────────────────────────────────────────────
CreateSection(MapPage, "Kelola")

CreateButton(MapPage, "🗑️ Hapus Titik Terpilih", function()
    local set, n = selectedSet()
    if n == 0 then CustomNotify("⚠️ MAP", "Centang minimal 1 titik.", 3); return end
    local removed, backToDefault = Waypoints.RemoveMany(currentIdx(), set)
    refreshList()
    if backToDefault then
        CustomNotify("🗑️ MAP",
            (Maps and Maps.IsCustom(_world)) and "Semua titik terhapus (map kosong)."
            or "Semua titik terhapus → kembali ke default.", 4)
    else
        CustomNotify("🗑️ MAP", removed .. " titik dihapus. " .. worldSummary(), 3)
    end
end)

CreateButton(MapPage, "🚀 Teleport ke Titik Terpilih (uji)", function()
    if EngineConfig.AutoFarmActive then
        CustomNotify("⚠️ MAP", "Matikan Auto Farm dulu.", 3)
        return
    end
    local set = selectedSet()
    local list = Waypoints.Get(currentIdx())
    local target
    for i = 1, #list do
        if set[i] then target = list[i]; break end
    end
    if not target then CustomNotify("⚠️ MAP", "Centang 1 titik dulu.", 3); return end
    local char = LocalPlayer and LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then CustomNotify("⚠️ MAP", "Karakter belum siap.", 3); return end
    hrp.CFrame = CFrame.new(target.x, target.y, target.z)
    CustomNotify("🚀 MAP", "Teleport ke (" .. fmt(target.x) .. ", " .. fmt(target.y) .. ", " .. fmt(target.z) .. ")", 3)
end)

CreateButton(MapPage, "📋 Salin Daftar (Vector3.new)", function()
    local lines = {}
    for _, p in ipairs(Waypoints.Get(currentIdx())) do
        table.insert(lines, string.format("Vector3.new(%s, %s, %s),", fmt(p.x), fmt(p.y), fmt(p.z)))
    end
    local ok = pcall(function() setclipboard(table.concat(lines, "\n")) end)
    CustomNotify(ok and "📋 MAP" or "⚠️ MAP",
        ok and (#lines .. " baris disalin.") or "Executor tidak mendukung clipboard.", 3)
end)

CreateButton(MapPage, "↩️ Reset Map Ini ke Default", function()
    Waypoints.Reset(currentIdx())
    refreshList()
    CustomNotify("↩️ MAP", ((Maps and Maps.IsCustom(_world)) and "Semua titik dikosongkan. " or "Kembali ke default. ") .. worldSummary(), 3)
end)

-- ── Map buatan sendiri ───────────────────────────────────────────────────────
-- Map baru langsung muncul di dropdown World tab Farm. Farm memakai pola
-- teleport berurutan antar titik (tanpa portal/room otomatis).
if Maps then
    CreateSection(MapPage, "Map Buatan Sendiri")

    local _newMapName = ""
    _G.MapNewNameInput = CreateInputUI(MapPage, "Nama Map Baru", "", false, function(v)
        _newMapName = tostring(v or "")
    end)

    CreateButton(MapPage, "➕ Tambah Map Baru", function()
        local ok, res = Maps.Add(_newMapName)
        if not ok then CustomNotify("⚠️ MAP", res, 3); return end
        _newMapName = ""
        pcall(function() _G.MapNewNameInput:SetValue("") end)
        _world = res
        WorldCycle:SetValue(res)   -- callback: refresh daftar + notifikasi ringkasan
        CustomNotify("✅ MAP", res .. " dibuat. Tambah titiknya, lalu pilih di tab Farm → World.", 5)
    end)

    CreateButton(MapPage, "🗑️ Hapus Map Ini (hanya map buatan)", function()
        if not Maps.IsCustom(_world) then
            CustomNotify("⚠️ MAP", "Map bawaan tidak bisa dihapus. Pilih map buatan.", 3)
            return
        end
        if EngineConfig.AutoFarmActive and EngineConfig.SelectedWorld == _world then
            CustomNotify("⚠️ MAP", "Matikan Auto Farm dulu.", 3)
            return
        end
        local removed  = _world
        local fallback = WORLD_NAMES[1]
        Maps.Remove(removed)
        _world = fallback
        if EngineConfig.SelectedWorld == removed then
            EngineConfig.SelectedWorld = fallback
            if _G.WorldDropdown then pcall(function() _G.WorldDropdown:SetValue(fallback) end) end
        end
        WorldCycle:SetValue(fallback)
        CustomNotify("🗑️ MAP", removed .. " dihapus.", 3)
    end)
end

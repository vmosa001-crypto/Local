--------------------------------------------------------------------------------
--// user_data.lua — Data buatan pengguna: Waypoint Map & Kode Redeem
--//   H.Waypoints : titik posisi (Vector3) per World di tab Farm
--//   H.Codes     : daftar kode redeem
--// Disimpan di folder XiFilHub_Data (terpisah dari profil config supaya tidak
--// muncul di daftar profil). Default dari kode dipakai jika belum diubah.
--------------------------------------------------------------------------------
local H           = getgenv().Hub
local Services    = H.Services
local HttpService = Services.HttpService

local FOLDER    = "XiFilHub_Data"
local WP_FILE   = FOLDER .. "/waypoints.json"
local CODE_FILE = FOLDER .. "/codes.json"

local function ensureFolder()
    pcall(function()
        if not isfolder(FOLDER) then makefolder(FOLDER) end
    end)
end

local function readJson(path)
    local ok, data = pcall(function()
        if isfile(path) then
            return HttpService:JSONDecode(readfile(path))
        end
        return nil
    end)
    if ok and type(data) == "table" then return data end
    return nil
end

local function writeJson(path, tbl)
    ensureFolder()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, tbl)
    if not ok then return false end
    local wok = pcall(writefile, path, encoded)
    return wok
end

--------------------------------------------------------------------------------
-- WAYPOINTS — indeks World sama dengan WORLD_INDEX (1..5)
--------------------------------------------------------------------------------
-- Default = titik bawaan dari navigation.lua (SearchWorld1..5).
local WP_DEFAULTS = {
    [1] = {
        { x = -660, y = 5, z = -10 },
        { x = -461, y = 6, z = 3 },
        { x = -430, y = 5, z = 190 },
        { x = 1117, y = 7, z = -23 },
        { x = -650, y = 5, z = -400 },
        { x = -470, y = 5, z = -380 },
        { x = -445, y = 5, z = -595 },
        { x = -2200, y = 41, z = -13200 },
        { x = 360, y = 7, z = 200 },
        { x = 380, y = 7, z = 25 },
        { x = -2420, y = 42, z = -10 },
    },
    [2] = {
        { x = -6165, y = 5, z = 641 },
        { x = -4348, y = 569, z = 1581 },
        { x = -4216, y = 560, z = 1583 },
        { x = -4040, y = 561, z = 1576 },
        { x = -6247, y = 3, z = -1432 },
        { x = -4100, y = 562, z = 2500 },
        { x = -4388, y = 564, z = 2515 },
        { x = -4188, y = 649, z = -1866 },
    },
    [3] = {
        { x = 687, y = 67, z = 600 },
        { x = 125, y = -8, z = 812 },
        { x = 236, y = 10, z = 287 },
        { x = 774, y = 64, z = -34 },
        { x = -756, y = 43, z = 255 },
        { x = -448, y = 49, z = 262 },
        { x = -1002, y = 22, z = 259 },
    },
    [4] = {
        { x = -8815, y = 205, z = -1833 },
        { x = -8891, y = 210, z = -1540 },
        { x = -8713, y = 204, z = -1294 },
        { x = -4111, y = 541, z = -1949 },
        { x = -4449, y = 531, z = -1963 },
        { x = 6136, y = -187, z = 592 },
        { x = -4069, y = 447, z = 1557 },
        { x = -4281, y = 452, z = 1586 },
        { x = -4268, y = 452, z = 3176 },
        { x = -4063, y = 452, z = 3148 },
        { x = -5970, y = -188, z = 593 },
        { x = -6020, y = -188, z = 594 },
        { x = -6089, y = -190, z = 586 },
    },
    [5] = {
        { x = 8560, y = 273, z = -3742 },
        { x = 8516, y = 268, z = -6333 },
        { x = 8549, y = 264, z = -9902 },
        { x = 8551, y = 274, z = -762 },
    },
}

local Waypoints = {}
local custom = {}   -- [worldIdx] = { {x=,y=,z=}, ... }  (hanya world yang diubah pengguna)

local function copyList(list)
    local out = {}
    for i, p in ipairs(list) do out[i] = { x = p.x, y = p.y, z = p.z } end
    return out
end

local function loadWaypoints()
    local data = readJson(WP_FILE)
    if not data then return end
    for k, list in pairs(data) do
        local idx = tonumber(k)
        if idx and WP_DEFAULTS[idx] and type(list) == "table" then
            local clean = {}
            for _, p in ipairs(list) do
                if type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) then
                    table.insert(clean, { x = tonumber(p.x), y = tonumber(p.y), z = tonumber(p.z) })
                end
            end
            if #clean > 0 then custom[idx] = clean end
        end
    end
end

local function saveWaypoints()
    local out = {}
    for idx, list in pairs(custom) do out[tostring(idx)] = list end
    return writeJson(WP_FILE, out)
end

-- Salinan daftar titik yang berlaku (custom jika ada, selain itu default)
function Waypoints.Get(idx)
    return copyList(custom[idx] or WP_DEFAULTS[idx] or {})
end

-- Dipakai navigation.lua. Tidak pernah kosong selama idx valid.
function Waypoints.GetVectors(idx)
    local list = custom[idx] or WP_DEFAULTS[idx] or {}
    local out = {}
    for i, p in ipairs(list) do out[i] = Vector3.new(p.x, p.y, p.z) end
    return out
end

function Waypoints.IsCustom(idx) return custom[idx] ~= nil end

function Waypoints.Add(idx, x, y, z)
    if not WP_DEFAULTS[idx] then return false end
    if not custom[idx] then custom[idx] = copyList(WP_DEFAULTS[idx]) end
    table.insert(custom[idx], { x = x, y = y, z = z })
    saveWaypoints()
    return true
end

-- indexSet: { [nomorTitik] = true }. Return: jumlah dihapus, kembali-ke-default?
function Waypoints.RemoveMany(idx, indexSet)
    local base = custom[idx] or WP_DEFAULTS[idx]
    if not base then return 0, false end
    local keep, removed = {}, 0
    for i, p in ipairs(base) do
        if indexSet[i] then
            removed = removed + 1
        else
            table.insert(keep, { x = p.x, y = p.y, z = p.z })
        end
    end
    if removed == 0 then return 0, false end
    if #keep == 0 then
        -- Daftar kosong membuat farm tidak punya titik → kembalikan ke default.
        custom[idx] = nil
        saveWaypoints()
        return removed, true
    end
    custom[idx] = keep
    saveWaypoints()
    return removed, false
end

function Waypoints.Reset(idx)
    custom[idx] = nil
    saveWaypoints()
end

-- Ambil 3 angka pertama dari teks apa pun: "1,2,3", "Vector3.new(1, 2, 3)",
-- "CFrame.new(1, 2, 3, 1,0,0,0,1,0,0,0,1)" → x, y, z
function Waypoints.Parse(text)
    local str = tostring(text or "")
    -- Ambil isi dalam kurung dulu supaya angka "3" pada "Vector3" tidak ikut terbaca
    str = str:match("%((.*)%)") or str
    local nums = {}
    for n in str:gmatch("-?%d+%.?%d*") do
        table.insert(nums, tonumber(n))
        if #nums == 3 then break end
    end
    if #nums == 3 and nums[1] and nums[2] and nums[3] then
        return nums[1], nums[2], nums[3]
    end
    return nil
end

--------------------------------------------------------------------------------
-- MAP BUATAN PENGGUNA — didaftarkan ke H.WORLD_NAMES / H.WORLD_INDEX dengan
-- indeks 6, 7, ... sehingga muncul di dropdown World tab Farm. Perilaku farm
-- = pola World 1 (teleport berurutan antar titik: Navigation.SearchCustom).
-- Harus dimuat SEBELUM loadWaypoints() agar titiknya ikut terbaca.
--------------------------------------------------------------------------------
local MAP_FILE     = FOLDER .. "/maps.json"
local FIRST_CUSTOM = 6
local Maps         = {}
local mapList      = {}              -- { {name=, idx=}, ... } urutan dibuat
local mapNext      = FIRST_CUSTOM    -- indeks berikutnya; tidak dipakai ulang

local function mapsSave()
    return writeJson(MAP_FILE, { next = mapNext, list = mapList })
end

local function nameTaken(name)
    local lower = name:lower()
    for _, n in ipairs(H.WORLD_NAMES) do
        if n:lower() == lower then return true end
    end
    return false
end

local function registerMap(name, idx)
    table.insert(H.WORLD_NAMES, name)
    H.WORLD_INDEX[name] = idx
    WP_DEFAULTS[idx] = {}            -- map buatan: default = kosong
end

-- MAP BAWAAN TAMBAHAN — map di luar World 1-5 yang sudah punya titik default.
-- Tampil di dropdown World tab Farm & tab Map; perilaku farm sama dengan map buatan
-- (Navigation.SearchCustom, indeks >= 6) tetapi TIDAK bisa dihapus, dan tombol "Reset"
-- di tab Map mengembalikan titiknya ke daftar di bawah. Indeks dicadangkan mulai 100
-- supaya tidak pernah bentrok dengan indeks map buatan pengguna (6, 7, ...) di maps.json.
local BUILTIN_MAPS = {
    {
        name = "Sakura Village", idx = 100,
        points = {
            { x = 1331.8, y = 15.3,  z = 3728.8 },
            { x = 1624.5, y = 15.9,  z = 3752.3 },
            { x = 3084.7, y = 127.8, z = 3419.2 },
            { x = 2432.9, y = 194.5, z = 5340.6 },
            { x = 128.6,  y = 194,   z = 4620   },
            { x = 3118.8, y = 150.5, z = 3681.5 },
        },
    },
}
for _, b in ipairs(BUILTIN_MAPS) do
    if not nameTaken(b.name) and not WP_DEFAULTS[b.idx] then
        table.insert(H.WORLD_NAMES, b.name)
        H.WORLD_INDEX[b.name] = b.idx
        WP_DEFAULTS[b.idx] = b.points
    end
end

do
    local renamedOnLoad = false
    local data = readJson(MAP_FILE)
    if data and type(data.list) == "table" then
        for _, m in ipairs(data.list) do
            local idx = type(m) == "table" and tonumber(m.idx)
            if idx and type(m.name) == "string" and m.name ~= "" then
                idx = math.floor(idx)
                if idx >= FIRST_CUSTOM and not WP_DEFAULTS[idx] then
                    -- Nama bentrok (mis. map buatan lama bernama sama dengan map bawaan):
                    -- beri akhiran supaya map & titiknya tetap tersimpan, tidak hilang diam-diam.
                    local nm, n = m.name, 1
                    while nameTaken(nm) do n = n + 1; nm = m.name .. " (" .. n .. ")" end
                    registerMap(nm, idx)
                    table.insert(mapList, { name = nm, idx = idx })
                    if idx >= mapNext then mapNext = idx + 1 end
                    if nm ~= m.name then renamedOnLoad = true end
                end
            end
        end
        local saved = tonumber(data.next)
        if saved and saved > mapNext then mapNext = math.floor(saved) end
    end
    if renamedOnLoad then mapsSave() end
end

function Maps.IsCustom(name)
    for _, m in ipairs(mapList) do
        if m.name == name then return true end
    end
    return false
end

-- Return: ok, namaBersih | pesanError
function Maps.Add(name)
    local s = tostring(name or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    s = s:gsub("%s+", " ")
    if s == "" then return false, "Nama map kosong." end
    if #s > 32 then return false, "Nama terlalu panjang (maks 32 karakter)." end
    if nameTaken(s) then return false, "Nama map sudah ada." end
    while WP_DEFAULTS[mapNext] do mapNext = mapNext + 1 end   -- lewati indeks milik map bawaan
    local idx = mapNext
    mapNext = mapNext + 1
    registerMap(s, idx)
    table.insert(mapList, { name = s, idx = idx })
    mapsSave()
    return true, s
end

-- Hanya map buatan. Titiknya ikut dihapus.
function Maps.Remove(name)
    for i, m in ipairs(mapList) do
        if m.name == name then
            table.remove(mapList, i)
            for j, n in ipairs(H.WORLD_NAMES) do
                if n == name then table.remove(H.WORLD_NAMES, j); break end
            end
            H.WORLD_INDEX[name] = nil
            WP_DEFAULTS[m.idx] = nil
            custom[m.idx] = nil
            saveWaypoints()
            mapsSave()
            return true
        end
    end
    return false
end

H.Maps = Maps

loadWaypoints()
H.Waypoints = Waypoints

--------------------------------------------------------------------------------
-- RESEP FORGE BUATAN PENGGUNA — tambah / hapus pilihan resep di tab Forge.
--   Tipe (Category)  : nilai yang dikirim ke server saat DropOres ("Weapon" / "Armor" / ...)
--   Nama (Label)     : teks tampilan
--   Persen (Chance)  : info peluang (tampilan)
--   Jumlah Ore       : jumlah ore yang wajib dipilih
--   RelicId          : relic opsional
-- Disimpan di forge_recipes.json (global, tidak ikut profil config):
--   { next = 3, custom = { {Id,Category,Label,OreCount,Chance,RelicId}, ... }, removed = { "WeaponStaff" } }
-- Resep bawaan yang "dihapus" hanya disembunyikan dari daftar (definisinya tetap ada untuk
-- engine); tombol Reset mengembalikannya. Semua isi file divalidasi saat dibaca.
--------------------------------------------------------------------------------
local RECIPE_FILE   = FOLDER .. "/forge_recipes.json"
local ForgeRecipes  = {}
local recipeCustom  = {}      -- urutan dibuat: { {Id=,Category=,Label=,OreCount=,Chance=,RelicId=}, ... }
local recipeRemoved = {}      -- [IdBawaan] = true
local recipeNext    = 1

local function cleanRecipeText(v, maxLen)
    local t = tostring(v == nil and "" or v)
    t = t:gsub("%c", " ")
    t = t:gsub("^%s+", "")
    t = t:gsub("%s+$", "")
    t = t:gsub("%s+", " ")
    if t == "" or #t > maxLen then return nil end
    return t
end

-- Validasi + rapikan satu resep. Return: resepBersih | nil, pesanError
local function cleanRecipe(raw)
    if type(raw) ~= "table" then return nil, "Data resep tidak valid." end
    local category = cleanRecipeText(raw.Category, 24)
    if not category then return nil, "Tipe kosong atau terlalu panjang (maks 24 karakter)." end
    local label = cleanRecipeText(raw.Label, 40)
    if not label then return nil, "Nama kosong atau terlalu panjang (maks 40 karakter)." end

    local oreCount = tonumber(raw.OreCount)
    if not oreCount or oreCount ~= oreCount then return nil, "Jumlah ore harus berupa angka." end
    oreCount = math.floor(oreCount)
    if oreCount < 1 or oreCount > 99 then return nil, "Jumlah ore harus 1 sampai 99." end

    local chanceRaw = raw.Chance
    if type(chanceRaw) == "string" then chanceRaw = chanceRaw:gsub("%%", "") end
    local chance = tonumber(chanceRaw)
    if not chance or chance ~= chance then return nil, "Persen harus berupa angka." end
    if chance < 0 or chance > 100 then return nil, "Persen harus 0 sampai 100." end
    chance = math.floor(chance * 10 + 0.5) / 10

    local relic = nil
    if raw.RelicId ~= nil and tostring(raw.RelicId) ~= "" then
        local r = tostring(raw.RelicId):gsub("%s+", "")
        if r ~= "" then
            if #r > 48 or not r:match("^[%w_%-]+$") then return nil, "Relic ID tidak valid." end
            relic = r
        end
    end
    return { Category = category, Label = label, OreCount = oreCount, Chance = chance, RelicId = relic }
end

local function recipesSave()
    local removedList = {}
    for id in pairs(recipeRemoved) do removedList[#removedList + 1] = id end
    table.sort(removedList)
    return writeJson(RECIPE_FILE, { next = recipeNext, custom = recipeCustom, removed = removedList })
end

do
    local data = readJson(RECIPE_FILE)
    if data then
        local used = {}
        if type(data.custom) == "table" then
            for _, raw in ipairs(data.custom) do
                local clean = cleanRecipe(raw)
                if clean then
                    local id = type(raw.Id) == "string" and raw.Id:match("^[%w_]+$") and #raw.Id <= 48 and raw.Id or nil
                    if id and not used[id] then
                        used[id] = true
                        clean.Id = id
                        table.insert(recipeCustom, clean)
                        local n = tonumber(id:match("^Custom(%d+)$"))
                        if n and n >= recipeNext then recipeNext = n + 1 end
                    end
                end
            end
        end
        if type(data.removed) == "table" then
            for _, id in ipairs(data.removed) do
                if type(id) == "string" and id ~= "" and #id <= 48 then recipeRemoved[id] = true end
            end
        end
        local saved = tonumber(data.next)
        if saved and saved > recipeNext then recipeNext = math.floor(saved) end
    end
end

-- Return: ok, resepBaru | pesanError
function ForgeRecipes.Add(category, label, chance, oreCount, relicId)
    local clean, err = cleanRecipe({ Category = category, Label = label, Chance = chance,
                                     OreCount = oreCount, RelicId = relicId })
    if not clean then return false, err end
    local id = "Custom" .. recipeNext
    local taken = true
    while taken do
        taken = false
        for _, r in ipairs(recipeCustom) do if r.Id == id then taken = true; break end end
        if taken then recipeNext = recipeNext + 1; id = "Custom" .. recipeNext end
    end
    recipeNext = recipeNext + 1
    clean.Id = id
    table.insert(recipeCustom, clean)
    recipesSave()
    return true, { Id = id, Category = clean.Category, Label = clean.Label, OreCount = clean.OreCount,
                   Chance = clean.Chance, RelicId = clean.RelicId }
end

function ForgeRecipes.Clean(raw) return cleanRecipe(raw) end

-- Salinan daftar resep buatan (aman dimodifikasi pemanggil)
function ForgeRecipes.GetCustom()
    local out = {}
    for i, r in ipairs(recipeCustom) do
        out[i] = { Id = r.Id, Category = r.Category, Label = r.Label, OreCount = r.OreCount,
                   Chance = r.Chance, RelicId = r.RelicId }
    end
    return out
end

function ForgeRecipes.IsRemoved(id) return recipeRemoved[id] == true end

function ForgeRecipes.RemoveCustom(id)
    for i, r in ipairs(recipeCustom) do
        if r.Id == id then
            table.remove(recipeCustom, i)
            recipesSave()
            return true
        end
    end
    return false
end

function ForgeRecipes.HideBuiltin(id)
    if type(id) ~= "string" or id == "" then return false end
    recipeRemoved[id] = true
    recipesSave()
    return true
end

-- Hapus semua resep buatan & tampilkan lagi semua resep bawaan
function ForgeRecipes.Reset()
    recipeCustom, recipeRemoved = {}, {}
    recipesSave()
end

H.ForgeRecipes = ForgeRecipes

--------------------------------------------------------------------------------
-- KODE REDEEM — Codes.List adalah tabel hidup (diubah di tempat) sehingga
-- semua modul yang memegang referensinya ikut melihat perubahan.
--------------------------------------------------------------------------------
local CODE_DEFAULTS = {
    "SCYTHEWEAPON", "IRONSOULWEEKEND18", "IRONSOULWEEKEND19",
    "SEASON2ENDING", "SEASON3EXPAND",
}

local Codes = { List = {} }

local function codesSave()
    return writeJson(CODE_FILE, { list = Codes.List })
end

local function codesLoadDefaults()
    for i = #Codes.List, 1, -1 do Codes.List[i] = nil end
    for _, c in ipairs(CODE_DEFAULTS) do table.insert(Codes.List, c) end
end

do
    local data = readJson(CODE_FILE)
    if data and type(data.list) == "table" then
        -- File ada → ikuti isinya (boleh kosong kalau pengguna menghapus semua)
        for _, c in ipairs(data.list) do
            if type(c) == "string" and c ~= "" then table.insert(Codes.List, c) end
        end
    else
        codesLoadDefaults()
    end
end

-- Return: ok, kodeBersih | pesanError
function Codes.Add(code)
    local s = tostring(code or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    if s == "" then return false, "Kode kosong." end
    if #s > 64 then return false, "Kode terlalu panjang (maks 64 karakter)." end
    if s:find("%s") then return false, "Kode tidak boleh mengandung spasi." end
    for _, c in ipairs(Codes.List) do
        if c == s then return false, "Kode sudah ada." end
    end
    table.insert(Codes.List, 1, s)   -- terbaru di atas
    codesSave()
    return true, s
end

-- nameSet: { [kode] = true }. Return: jumlah dihapus
function Codes.RemoveMany(nameSet)
    local removed = 0
    for i = #Codes.List, 1, -1 do
        if nameSet[Codes.List[i]] then
            table.remove(Codes.List, i)
            removed = removed + 1
        end
    end
    if removed > 0 then codesSave() end
    return removed
end

function Codes.Reset()
    codesLoadDefaults()
    codesSave()
end

H.Codes = Codes

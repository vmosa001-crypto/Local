--------------------------------------------------------------------------------
--// ui/tab_util.lua — Tab Utilitas: Redeem Code, Lottery, Reward, Race Reroll
--------------------------------------------------------------------------------
local H            = getgenv().Hub
local EngineConfig = H.EngineConfig
local Services     = H.Services
local LocalPlayer  = H.LocalPlayer
local CustomNotify = H.CustomNotify
local CreateTab                     = H.CreateTab
local CreateSection                 = H.CreateSection
local CreateToggleUI                = H.CreateToggleUI
local CreateInputUI                 = H.CreateInputUI
local CreateButton                  = H.CreateButton
local CreateScrollableMultiSelectUI = H.CreateScrollableMultiSelectUI
local CreateDropdownUI              = H.CreateDropdownUI
local RegisterTranslation           = H.RegisterTranslation

-- [UTIL] REMOTE EVENTS — lazy, di-cache setelah berhasil
--------------------------------------------------------------------------------
local _codeRE, _lotteryRE, _raceRE, _rewardRE = nil, nil, nil, nil

local function getCodeRE()
    if _codeRE then return _codeRE end
    local ok, re = pcall(function()
        return Services.ReplicatedStorage
            :WaitForChild("Framework",3):WaitForChild("Systems",3)
            :WaitForChild("CodesSystem",3):WaitForChild("CodeRE",3)
    end)
    if ok and re then _codeRE = re end
    return _codeRE
end

local function getLotteryRE()
    if _lotteryRE then return _lotteryRE end
    local ok, re = pcall(function()
        return Services.ReplicatedStorage
            :WaitForChild("Framework",3):WaitForChild("Features",3)
            :WaitForChild("SeasonSystem",3):WaitForChild("SeasonUtil",3)
            :WaitForChild("RemoteEvent",3)
    end)
    if ok and re then _lotteryRE = re end
    return _lotteryRE
end

local function getRaceRE()
    if _raceRE then return _raceRE end
    local ok, re = pcall(function()
        return Services.ReplicatedStorage
            :WaitForChild("Framework",3):WaitForChild("Gameplay",3)
            :WaitForChild("RaceSystem",3):WaitForChild("RaceRE",3)
    end)
    if ok and re then _raceRE = re end
    return _raceRE
end

local function getRewardRE()
    if _rewardRE then return _rewardRE end
    local ok, re = pcall(function()
        return Services.ReplicatedStorage
            :WaitForChild("Framework",3):WaitForChild("Features",3)
            :WaitForChild("UpdateLogSystem",3):WaitForChild("RemoteEvent",3)
    end)
    if ok and re then _rewardRE = re end
    return _rewardRE
end

-- [UTIL] DATA LISTS — tambah item baru di sini saja, tidak perlu ubah kode lain
--------------------------------------------------------------------------------

-- Kode redeem (terbaru di atas)
-- Sumber utama: H.Codes.List (tabel hidup, bisa tambah/hapus dari UI); literal = cadangan
local CODE_LIST = (H.Codes and H.Codes.List) or {
    
    "SCYTHEWEAPON","IRONSOULWEEKEND18", "IRONSOULWEEKEND19","SEASON2ENDING", "SEASON3EXPAND",
}

-- Versi reward update (tambah versi baru di sini)
local REWARD_VERSIONS = {
    "V10.1", "V10.2", "V10.3", "V10.4", "V10.5", "V10.6", "V11.0",
}

-- [UTIL] RACE LIST — dibangun dari ResRace (ReplicatedStorage.Configs.ResRace)
-- Otomatis sinkron saat game tambah race baru; tidak perlu edit manual.
-- Sort besar = langka = tampil di atas daftar.
--------------------------------------------------------------------------------
local RARITY_NAMES = {
    [1]="Common", [2]="Uncommon", [3]="Rare",
    [4]="Epic",   [5]="Legendary",[6]="Mythical", [7]="Secret",
}

local RACE_LIST, RACE_DISPLAY, RACE_RARITY = (function()
    local ok, res = pcall(function()
        return require(Services.ReplicatedStorage
            :WaitForChild("Configs", 10)
            :WaitForChild("ResRace",  10))
    end)

    if not ok or type(res) ~= "table" then
        warn("[XiFil] ResRace gagal dimuat — pakai fallback statis")
        return
            { "Lucifer","Archdruid","Elf","Demon","Angel","DragonKnight",
              "Fairy","Curse","Dragonborn","Undead","Goblin","Orc","Human" },
            { "Lucifer (Mythical)","Archdruid (Secret)","Elf (Mythical)",
              "Demon (Mythical)","Angel (Mythical)","DragonKnight (Secret)",
              "Fairy (Legendary)","Curse (Legendary)","Dragonborn (Epic)",
              "Undead (Rare)","Goblin (Uncommon)","Orc (Uncommon)","Human (Common)" },
            { Lucifer=6,Archdruid=7,Elf=6,Demon=6,Angel=6,DragonKnight=7,
              Fairy=5,Curse=5,Dragonborn=4,Undead=3,Goblin=2,Orc=2,Human=1 }
    end

    -- Kumpulkan entry valid: harus punya Id (string) dan Sort (number)
    local entries = {}
    for _, data in pairs(res) do
        if type(data) == "table"
            and type(data.Id)   == "string"
            and type(data.Sort) == "number" then
            table.insert(entries, data)
        end
    end
    -- Sort descending: nilai Sort besar = race langka = tampil di atas
    table.sort(entries, function(a, b) return a.Sort > b.Sort end)

    local ids, display, rarityMap = {}, {}, {}
    for _, data in ipairs(entries) do
        local rName = RARITY_NAMES[data.Rarity] or ("R"..tostring(data.Rarity or "?"))
        table.insert(ids,     data.Id)
        table.insert(display, data.Id .. " (" .. rName .. ")")
        rarityMap[data.Id] = data.Rarity
    end
    return ids, display, rarityMap
end)()

-- Export lists ke Hub agar ui_sync bisa sync tanpa duplikat konstanta
H.UtilCodeList = CODE_LIST
H.UtilRaceList = RACE_LIST

-- [UTIL] HELPER: baca race karakter — BEBAS BAHASA
--------------------------------------------------------------------------------
-- Masalah lama: race dibaca dari teks billboard (PlayerTitleGUI.Root.Title.Race) yang ikut
-- diterjemahkan sesuai bahasa Roblox/game, lalu dicocokkan dengan Id race berbahasa Inggris
-- (RACE_LIST). Di bahasa lain target TIDAK terdeteksi → roll terus lewat → target terskip.
-- Sekarang teks billboard dicocokkan ke ALIAS tiap race: Id + semua string pendek di entry
-- config ResRace + terjemahannya (LocalizationService / LocalizationTable semua bahasa),
-- setelah dinormalisasi (tanpa tag rich-text, spasi, tanda baca, huruf besar/kecil).
-- Alias yang dipakai >1 race dibuang (ambigu); Id race selalu menang.
-- Kalau race TIDAK bisa dikenali sama sekali, auto reroll BERHENTI + memberi tahu teks yang
-- terbaca (tidak menggulung buta), jadi target tidak mungkin terlewat diam-diam.

-- Normalisasi untuk perbandingan. Huruf non-ASCII (bahasa lain) dibiarkan utuh.
local function normText(s)
    if type(s) ~= "string" then return "" end
    s = s:gsub("<[^>]*>", "")      -- tag rich-text
    s = s:lower()
    s = s:gsub("[%s%p]+", "")      -- spasi & tanda baca ASCII
    return s
end

local _raceAliasMap      = nil     -- teks ternormalisasi → Id race | false (ambigu)
local _raceAliasBuilding = false

local function addRaceAlias(map, alias, id)
    if type(alias) ~= "string" or #alias > 40 then return end
    if alias:find("://", 1, true) or alias:lower():find("rbxasset", 1, true) then return end
    local key = normText(alias)
    if #key < 2 then return end                  -- terlalu pendek = rawan salah cocok
    local cur = map[key]
    if cur == nil then map[key] = id
    elseif cur ~= id then map[key] = false end   -- dipakai lebih dari satu race → abaikan
end

-- Kumpulkan string pendek dari sebuah entry config (termasuk tabel bersarang per bahasa).
local function collectRaceStrings(value, out, depth)
    if depth > 3 or #out >= 200 then return end
    if type(value) == "string" then
        out[#out + 1] = value
    elseif type(value) == "table" then
        for _, v in pairs(value) do collectRaceStrings(v, out, depth + 1) end
    end
end

local function buildRaceAliasMap()
    local map = {}

    -- 1. String dari entry ResRace (nama / key lokalisasi / tabel per bahasa)
    local stringsById = {}
    pcall(function()
        local cfg = Services.ReplicatedStorage:FindFirstChild("Configs")
        local mod = cfg and cfg:FindFirstChild("ResRace")
        local res = mod and require(mod)
        if type(res) == "table" then
            for _, data in pairs(res) do
                if type(data) == "table" and type(data.Id) == "string" then
                    local strs = {}
                    collectRaceStrings(data, strs, 0)
                    stringsById[data.Id] = strs
                end
            end
        end
    end)
    for id, strs in pairs(stringsById) do
        for _, str in ipairs(strs) do addRaceAlias(map, str, id) end
    end

    -- 2. Terjemahan bahasa pemain saat ini: coba tiap string sebagai KEY lokalisasi
    local translator = nil
    do
        local done = false
        task.spawn(function()
            pcall(function()
                translator = game:GetService("LocalizationService"):GetTranslatorForPlayerAsync(LocalPlayer)
            end)
            done = true
        end)
        local t0 = os.clock()
        while not done and os.clock() - t0 < 3 do task.wait(0.05) end
    end
    if translator then
        for id, strs in pairs(stringsById) do
            for _, str in ipairs(strs) do
                pcall(function()
                    local tr = translator:FormatByKey(str)
                    if type(tr) == "string" and tr ~= str then addRaceAlias(map, tr, id) end
                end)
            end
        end
    end

    -- 3. LocalizationTable milik game (semua bahasa sekaligus): entry yang salah satu teksnya
    --    sudah dikenali sebagai alias sebuah race → semua teks entry itu ikut jadi alias race tsb.
    pcall(function()
        local tables, scanned = {}, 0
        for _, root in ipairs({ game:GetService("LocalizationService"), Services.ReplicatedStorage }) do
            for _, d in ipairs(root:GetDescendants()) do
                scanned = scanned + 1
                if scanned > 30000 or #tables >= 20 then break end
                if d:IsA("LocalizationTable") then tables[#tables + 1] = d end
            end
        end
        for _, lt in ipairs(tables) do
            local okE, entries = pcall(lt.GetEntries, lt)
            if okE and type(entries) == "table" then
                for _, e in ipairs(entries) do
                    local texts = {}
                    if type(e.Source) == "string" then texts[#texts + 1] = e.Source end
                    if type(e.Key)    == "string" then texts[#texts + 1] = e.Key end
                    if type(e.Values) == "table" then
                        for _, v in pairs(e.Values) do
                            if type(v) == "string" then texts[#texts + 1] = v end
                        end
                    end
                    local owner = nil
                    for _, t in ipairs(texts) do
                        local hit = map[normText(t)]
                        if hit then owner = hit; break end
                    end
                    if owner then
                        for _, t in ipairs(texts) do addRaceAlias(map, t, owner) end
                    end
                end
            end
        end
    end)

    -- 4. Id race SELALU menang atas alias lain (menimpa status ambigu / alias race lain)
    for _, id in ipairs(RACE_LIST) do
        local key = normText(id)
        if key ~= "" then map[key] = id end
    end
    return map
end

local function getRaceAliasMap()
    while _raceAliasBuilding do task.wait(0.05) end      -- thread lain sedang membangun
    if _raceAliasMap then return _raceAliasMap end
    _raceAliasBuilding = true
    local ok, res = pcall(buildRaceAliasMap)
    _raceAliasBuilding = false
    if ok and type(res) == "table" then
        _raceAliasMap = res
    else
        warn("[XiFil] Gagal membangun alias race: " .. tostring(res))
        _raceAliasMap = {}
        for _, id in ipairs(RACE_LIST) do _raceAliasMap[normText(id)] = id end
    end
    return _raceAliasMap
end
-- Bangun di latar belakang agar reroll pertama tidak menunggu
task.spawn(function() pcall(getRaceAliasMap) end)

-- Teks → Id race (atau nil bila tidak dikenali / ambigu).
local function identifyRaceFromText(text)
    local norm = normText(text)
    if norm == "" then return nil end
    local map = getRaceAliasMap()
    local exact = map[norm]
    if exact then return exact end
    if exact == false then return nil end
    -- Teks memuat alias (mis. "Elf (Mythical)", "[Mythical] Elf"): pakai alias TERPANJANG
    local bestId, bestLen, tie = nil, 0, false
    for alias, id in pairs(map) do
        if id and #alias >= 3 and #alias <= #norm and norm:find(alias, 1, true) then
            if #alias > bestLen then
                bestId, bestLen, tie = id, #alias, false
            elseif #alias == bestLen and id ~= bestId then
                tie = true
            end
        end
    end
    if bestId and not tie then return bestId end
    return nil
end

-- Snapshot kondisi race saat ini.
--   text    : teks label billboard (apa adanya, bisa bahasa lain)
--   noGui   : label billboard belum ada (respawn / loading)
--   known   : race berhasil dikenali (textId / attrId)
--   isTarget/targetId : race termasuk target yang dipilih
--   sig     : tanda tangan untuk mendeteksi perubahan hasil roll (bebas bahasa)
local function readRaceState()
    local char  = LocalPlayer.Character
    local hrp   = char and char:FindFirstChild("HumanoidRootPart")
    local gui   = hrp and hrp:FindFirstChild("PlayerTitleGUI")
    local root  = gui and gui:FindFirstChild("Root")
    local title = root and root:FindFirstChild("Title")
    local lbl   = title and title:FindFirstChild("Race")

    local text, noGui = "", true
    if lbl and (lbl:IsA("TextLabel") or lbl:IsA("TextBox")) then
        text, noGui = lbl.Text, false
    end

    -- Id langsung dari atribut bernama "*race*" pada rantai billboard (bila game menyimpannya).
    -- Sengaja TIDAK memindai atribut Player/Character: bisa berisi race slot lain.
    local attrId = nil
    local map = getRaceAliasMap()
    for _, inst in ipairs({ gui, root, title, lbl }) do
        local okA, attrs = pcall(inst.GetAttributes, inst)
        if okA and type(attrs) == "table" then
            for name, value in pairs(attrs) do
                if type(value) == "string" and string.find(string.lower(name), "race", 1, true) then
                    local hit = map[normText(value)]
                    if hit then attrId = hit; break end
                end
            end
        end
        if attrId then break end
    end

    local textId = (not noGui) and identifyRaceFromText(text) or nil
    local targets = EngineConfig.UtilTargetRaces or {}
    local targetId = nil
    if attrId and targets[attrId] then targetId = attrId
    elseif textId and targets[textId] then targetId = textId end

    return {
        text = text, noGui = noGui,
        attrId = attrId, textId = textId,
        known = (attrId ~= nil) or (textId ~= nil),
        isTarget = targetId ~= nil, targetId = targetId,
        sig = tostring(attrId) .. "|" .. text,
    }
end

-- Tunggu sampai race terbaca jelas (label bisa sesaat berisi teks transisi saat roll).
local function readRaceSettled(timeout)
    local deadline = os.clock() + timeout
    local st = readRaceState()
    while not st.known and not st.noGui and os.clock() < deadline do
        task.wait(0.1)
        st = readRaceState()
    end
    return st
end

-- Tunggu hasil roll: label berubah dari tanda tangan sebelumnya (tidak peduli bahasa).
local function waitForRaceChange(prevSig, timeout)
    local deadline = os.clock() + timeout
    repeat
        local st = readRaceState()
        if not st.noGui and st.text ~= "" and st.sig ~= prevSig then return st end
        task.wait(0.1)
    until os.clock() >= deadline
    return readRaceState()
end

local function stopAutoReroll(title, message)
    EngineConfig.UtilAutoRerollActive = false
    if _G.UtilAutoRerollToggle then _G.UtilAutoRerollToggle:SetValue(false) end
    CustomNotify(title, message, 8)
end

-- Verifikasi ulang sesaat setelah target terlihat (hindari membaca teks transisi), lalu berhenti.
local function stopOnTargetRace()
    task.wait(0.35)
    local st = readRaceState()
    if not st.isTarget then return false end
    EngineConfig.UtilAutoRerollActive = false
    if _G.UtilAutoRerollToggle then _G.UtilAutoRerollToggle:SetValue(false) end
    local rNum   = RACE_RARITY and RACE_RARITY[st.targetId]
    local rLabel = rNum and RARITY_NAMES[rNum] or ""
    local detail = rLabel ~= "" and (" ("..rLabel..")") or ""
    CustomNotify("🎉 RACE DIDAPAT!", st.targetId..detail.." — target tercapai!", 10)
    return true
end

-- [UTIL] TAB
--------------------------------------------------------------------------------
local UtilPage = CreateTab("🔧 Utilitas", "tabUtil")

-- ════════════════════════════════════════════════════════════════════════════
-- [SEKSI 1] REDEEM CODE
-- ════════════════════════════════════════════════════════════════════════════
CreateSection(UtilPage, "Redeem Code", "secUtilCode")

local _codeInitVals, _codeCbs = {}, {}
for _, code in ipairs(CODE_LIST) do
    table.insert(_codeInitVals, EngineConfig.UtilSelectedCodes[code] == true)
    local _code = code
    table.insert(_codeCbs, function(v)
        EngineConfig.UtilSelectedCodes[_code] = (v == true)
    end)
end
_G.UtilCodeChecks = CreateScrollableMultiSelectUI(
    UtilPage, "Pilih Kode Redeem", CODE_LIST, _codeInitVals, _codeCbs
)

-- ── Kelola daftar kode: tambah / hapus (tersimpan permanen) ─────────────────
if H.Codes then
    local _newCode = ""
    _G.UtilNewCodeInput = CreateInputUI(UtilPage, "Kode Baru", "", false, function(v)
        _newCode = tostring(v or "")
    end)

    local function _codeCallbacks()
        local cbs = {}
        for _, code in ipairs(CODE_LIST) do
            local c = code
            table.insert(cbs, function(v) EngineConfig.UtilSelectedCodes[c] = (v == true) end)
        end
        return cbs
    end

    local function _refreshCodeList()
        local ui = _G.UtilCodeChecks
        if not (ui and ui.SetValues) then return end
        -- Salin: UI menyimpan referensi daftar yang diberikan, jangan beri tabel hidup
        local copy = {}
        for i, code in ipairs(CODE_LIST) do copy[i] = code end
        ui:SetValues(copy, _codeCallbacks())
        for i, code in ipairs(CODE_LIST) do
            if ui[i] then ui[i]:SetValue(EngineConfig.UtilSelectedCodes[code] == true) end
        end
    end

    CreateButton(UtilPage, "➕ Tambah Kode", function()
        local ok, res = H.Codes.Add(_newCode)
        if not ok then CustomNotify("⚠️ KODE", res, 3); return end
        EngineConfig.UtilSelectedCodes[res] = true
        _newCode = ""
        pcall(function() _G.UtilNewCodeInput:SetValue("") end)
        _refreshCodeList()
        CustomNotify("✅ KODE", res .. " ditambahkan (" .. #CODE_LIST .. " kode).", 3)
    end)

    CreateButton(UtilPage, "🗑️ Hapus Kode Terpilih", function()
        local set, n = {}, 0
        for _, code in ipairs(CODE_LIST) do
            if EngineConfig.UtilSelectedCodes[code] then set[code] = true; n = n + 1 end
        end
        if n == 0 then CustomNotify("⚠️ KODE", "Centang kode yang ingin dihapus.", 3); return end
        local removed = H.Codes.RemoveMany(set)
        for code in pairs(set) do EngineConfig.UtilSelectedCodes[code] = nil end
        _refreshCodeList()
        CustomNotify("🗑️ KODE", removed .. " kode dihapus (" .. #CODE_LIST .. " tersisa).", 3)
    end)

    CreateButton(UtilPage, "↩️ Reset Kode ke Default", function()
        H.Codes.Reset()
        EngineConfig.UtilSelectedCodes = {}
        _refreshCodeList()
        CustomNotify("↩️ KODE", "Daftar kode dikembalikan ke default.", 3)
    end)
end

-- Tombol "Semua": pilih semua kode sekaligus lalu langsung redeem
CreateButton(UtilPage, "✅ Semua — Pilih & Redeem", function()
    -- Centang semua
    for i, code in ipairs(CODE_LIST) do
        EngineConfig.UtilSelectedCodes[code] = true
        if _G.UtilCodeChecks and _G.UtilCodeChecks[i] then
            _G.UtilCodeChecks[i]:SetValue(true)
        end
    end
    -- Langsung trigger redeem
    local re = getCodeRE()
    if not re then CustomNotify("⚠️ UTIL","CodeRE tidak ditemukan!",3); return end
    task.spawn(function()
        CustomNotify("🎁 REDEEM SEMUA","Memulai "..#CODE_LIST.." kode (15d jeda)...",4)
        for i, code in ipairs(CODE_LIST) do
            pcall(function() re:FireServer({event="usecode", code=code}) end)
            if i < #CODE_LIST then
                for cd = 15, 1, -1 do
                    CustomNotify("🎁 REDEEM","["..i.."/"..#CODE_LIST.."] "..code.." | Berikutnya: "..cd.."d",1)
                    task.wait(1)
                end
            end
        end
        CustomNotify("🎁 REDEEM SEMUA","Selesai! "..#CODE_LIST.." kode di-redeem.",4)
    end)
end, "btnUtilRedeemAll")

local _redeemBusy = false
CreateButton(UtilPage, "🎁 Redeem Kode Terpilih", function()
    if _redeemBusy then return end
    local re = getCodeRE()
    if not re then CustomNotify("⚠️ UTIL","CodeRE tidak ditemukan!",3); return end
    local selected = {}
    for _, code in ipairs(CODE_LIST) do
        if EngineConfig.UtilSelectedCodes[code] then
            table.insert(selected, code)
        end
    end
    if #selected == 0 then CustomNotify("⚠️ UTIL","Pilih minimal 1 kode!",3); return end
    _redeemBusy = true
    task.spawn(function()
        CustomNotify("🎁 REDEEM","Memulai "..#selected.." kode (15d jeda)...",4)
        for i, code in ipairs(selected) do
            pcall(function() re:FireServer({event="usecode", code=code}) end)
            if i < #selected then
                -- Hitung mundur agar terlihat
                for cd = 15, 1, -1 do
                    CustomNotify("🎁 REDEEM","["..i.."/"..#selected.."] "..code.." | Berikutnya: "..cd.."d",1)
                    task.wait(1)
                end
            end
        end
        CustomNotify("🎁 REDEEM","Selesai! "..#selected.." kode di-redeem.",4)
        _redeemBusy = false
    end)
end, "btnUtilRedeem")

-- ════════════════════════════════════════════════════════════════════════════
-- [SEKSI 2] AUTO REROLL LOTTERY
-- ════════════════════════════════════════════════════════════════════════════
CreateSection(UtilPage, "Auto Reroll Lottery", "secUtilLottery")

_G.UtilLotteryCountInput = CreateInputUI(
    UtilPage, "Jumlah Reroll Sekaligus", tostring(EngineConfig.UtilLotteryCount), true,
    function(v)
        local n = tonumber(v)
        if n and n >= 1 then EngineConfig.UtilLotteryCount = math.floor(n) end
    end
)

local _lotteryBusy = false
CreateButton(UtilPage, "🎰 Reroll Lottery Sekarang", function()
    if _lotteryBusy then return end
    local re = getLotteryRE()
    if not re then CustomNotify("⚠️ UTIL","LootRE tidak ditemukan!",3); return end
    local count = math.max(math.floor(EngineConfig.UtilLotteryCount or 15), 1)
    _lotteryBusy = true
    task.spawn(function()
        for i = 1, count do
            pcall(function() re:FireServer("TrySeasonLottery", 1) end)
            task.wait(0.05)
        end
        CustomNotify("🎰 LOTTERY","Selesai "..count.." reroll!",3)
        _lotteryBusy = false
    end)
end, "btnUtilLottery")

-- ════════════════════════════════════════════════════════════════════════════
-- [SEKSI 3] CLAIM REWARD UPDATE
-- ════════════════════════════════════════════════════════════════════════════
CreateSection(UtilPage, "Claim Reward Update", "secUtilReward")

local _rewardBusy = false
CreateButton(UtilPage, "🏆 Claim Semua Reward Update", function()
    if _rewardBusy then return end
    local re = getRewardRE()
    if not re then CustomNotify("⚠️ UTIL","RewardRE tidak ditemukan!",3); return end
    _rewardBusy = true
    task.spawn(function()
        for _, ver in ipairs(REWARD_VERSIONS) do
            CustomNotify("🏆 REWARD","Mengklaim: "..ver,1)
            pcall(function() re:FireServer("ClaimReward", ver) end)
            task.wait(0.5)
        end
        CustomNotify("🏆 REWARD","Semua reward berhasil diklaim!",4)
        _rewardBusy = false
    end)
end, "btnUtilClaimReward")

-- ════════════════════════════════════════════════════════════════════════════
-- [SEKSI 4] AUTO REROLL RACE
-- ════════════════════════════════════════════════════════════════════════════
CreateSection(UtilPage, "Auto Reroll Race", "secUtilRace")

-- Dropdown pilih slot — tidak disimpan ke profil (lokal per sesi)
-- Slot 2-4 tersedia jika player sudah unlock via ResRollingAscend; server akan menolak jika belum.
local SLOT_LIST    = {"Free 1", "Slot 1", "Slot 2", "Slot 3", "Slot 4"}
local SLOT_KEY_MAP = {
    ["Free 1"]="Free_1", ["Slot 1"]="1",
    ["Slot 2"]="2",      ["Slot 3"]="3", ["Slot 4"]="4",
}
-- State lokal slot — selalu mulai dari Free_1 setiap sesi, tidak ikut save/load profil
local _raceSlot = "Free_1"
-- Guard: cegah FireServer saat dropdown baru dibuat
local _raceSlotReady = false
_G.UtilRaceSlotDropdown = CreateDropdownUI(
    UtilPage, "🎰 Race Slot", SLOT_LIST,
    "Free 1",
    function(val)
        local sk = SLOT_KEY_MAP[val] or "Free_1"
        _raceSlot = sk
        -- Fire SelectSlot hanya saat user memilih manual (bukan inisialisasi)
        if not _raceSlotReady then return end
        local re = getRaceRE()
        if re then pcall(function() re:FireServer("SelectSlot", sk) end) end
    end, "lblUtilRaceSlot"
)
_raceSlotReady = true

-- Dropdown multi-select (scrollable) — tampilkan RACE_DISPLAY (ada %)
-- tapi simpan state lewat RACE_LIST (nama asli)
local _raceInitVals, _raceCbs = {}, {}
for _, race in ipairs(RACE_LIST) do
    table.insert(_raceInitVals, EngineConfig.UtilTargetRaces[race] == true)
    local _race = race
    table.insert(_raceCbs, function(v)
        EngineConfig.UtilTargetRaces[_race] = (v == true)
    end)
end
_G.UtilRaceChecks = CreateScrollableMultiSelectUI(
    UtilPage, "Target Race", RACE_DISPLAY, _raceInitVals, _raceCbs
)

_G.UtilAutoRerollToggle = CreateToggleUI(
    UtilPage, "🎲 Auto Reroll Race", EngineConfig.UtilAutoRerollActive,
    function(v)
        EngineConfig.UtilAutoRerollActive = v
        if v then CustomNotify("🎲 AUTO REROLL","Aktif — roll sampai target!",3)
        else      CustomNotify("🎲 AUTO REROLL","Nonaktif",2) end
    end, "lblUtilAutoReroll"
)

-- Loop auto reroll race (background)
task.spawn(function()
    local noGuiCount = 0
    while true do
        task.wait(1)
        if not EngineConfig.UtilAutoRerollActive then noGuiCount = 0; continue end

        local re = getRaceRE()
        if not re then task.wait(3); continue end

        -- Cek setidaknya 1 target race dipilih
        local anyTarget = false
        for _, race in ipairs(RACE_LIST) do
            if EngineConfig.UtilTargetRaces[race] then anyTarget = true; break end
        end
        if not anyTarget then
            stopAutoReroll("⚠️ AUTO REROLL", "Pilih target race dulu!")
            continue
        end

        -- 1) Baca race sekarang. JANGAN roll bila race belum bisa dipastikan.
        local cur = readRaceSettled(2.5)
        if cur.noGui then
            -- billboard belum ada (respawn / loading): tunggu, jangan menggulung buta
            noGuiCount = noGuiCount + 1
            if noGuiCount >= 15 then
                stopAutoReroll("⚠️ AUTO REROLL", "Billboard race tidak ditemukan — auto reroll dihentikan.")
            end
            continue
        end
        noGuiCount = 0
        if not cur.known then
            stopAutoReroll("⚠️ AUTO REROLL",
                "Race tidak dikenali: \"" .. tostring(cur.text) .. "\" (kemungkinan beda bahasa). "
                .. "Dihentikan supaya target tidak terlewat.")
            continue
        end
        if cur.isTarget then
            if stopOnTargetRace() then continue end
        end

        -- 2) Roll. Selalu konfirmasi slot tepat sebelum roll (server bisa masih memakai slot lama).
        local selectedOk = pcall(function()
            re:FireServer("SelectSlot", _raceSlot)
        end)
        local rollingOk = selectedOk and pcall(function()
            re:FireServer("Rolling", _raceSlot)
        end)

        -- 3) Tunggu billboard berubah setelah tiap roll (delay tetap bisa membaca race lama lalu
        --    roll lagi dan melewatkan target), lalu pastikan hasilnya terbaca jelas.
        if rollingOk then
            waitForRaceChange(cur.sig, 5)
            local after = readRaceSettled(2.5)
            if after.known and after.isTarget then
                stopOnTargetRace()
            elseif not after.known and not after.noGui then
                stopAutoReroll("⚠️ AUTO REROLL",
                    "Race tidak dikenali: \"" .. tostring(after.text) .. "\" (kemungkinan beda bahasa). "
                    .. "Dihentikan supaya target tidak terlewat.")
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Export ke Hub
--------------------------------------------------------------------------------
H.UtilCodeList = CODE_LIST
H.UtilRaceList = RACE_LIST

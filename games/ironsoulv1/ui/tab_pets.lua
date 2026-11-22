--------------------------------------------------------------------------------
--// ui/tab_pets.lua — Tab Pets: Auto Hatch telur + Ekspedisi pet
-- Dipindah dari "Iron Soul Dungeon Utility". Pengaturan disimpan di EngineConfig
-- (PetHatchAuto / PetExpDispatch / PetExpClaim / PetExpSlots) → ikut Save/Load profil.
--------------------------------------------------------------------------------
local H              = getgenv().Hub
local EngineConfig   = H.EngineConfig
local CreateTab      = H.CreateTab
local CreateSection  = H.CreateSection
local CreateToggleUI = H.CreateToggleUI
local GetThemeColor  = H.GetThemeColor
local T              = H.T
local DS             = H.DungeonSys

local PetsPage = CreateTab("🐾 Pets", "tabPets")

local function Fmt(Template, ...)
    local Args = table.pack(...)
    return (string.gsub(tostring(Template), "{(%d+)}", function(Index)
        return tostring(Args[tonumber(Index)] or "")
    end))
end

local function FmtTime(Seconds)
    Seconds = math.max(0, math.floor(tonumber(Seconds) or 0))
    return string.format("%d:%02d", Seconds // 60, Seconds % 60)
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

local PetsSyncing = false           -- true saat UI di-set dari config (callback tidak boleh menulis balik)
local SyncPets = nil
local okP, errP = pcall(function()
    if not DS then error("modul dungeon_sys tidak termuat") end
    local Pets = DS.Pets
    local Chips, ChipFrame = {}, nil
    local HatchToggle, DispatchToggle, ClaimToggle

    -- ── Telur ──
    CreateSection(PetsPage, "Egg Hatching", "secPtHatch")
    local HatchInfo = MakeInfoCard(PetsPage)
    HatchToggle = CreateToggleUI(PetsPage, "🥚 Auto Hatch Telur", EngineConfig.PetHatchAuto == true, function(v)
        if PetsSyncing then return end
        EngineConfig.PetHatchAuto = v
        Pets.OnHatchToggle(v)
    end, "lblPtHatch")

    -- ── Ekspedisi ──
    CreateSection(PetsPage, "Pet Expedition", "secPtExp")
    local ExpInfo = MakeInfoCard(PetsPage)
    DispatchToggle = CreateToggleUI(PetsPage, "🧭 Auto Dispatch", EngineConfig.PetExpDispatch == true, function(v)
        if PetsSyncing then return end
        EngineConfig.PetExpDispatch = v
    end, "lblPtDispatch")
    ClaimToggle = CreateToggleUI(PetsPage, "🎁 Auto Claim", EngineConfig.PetExpClaim == true, function(v)
        if PetsSyncing then return end
        EngineConfig.PetExpClaim = v
    end, "lblPtClaim")

    CreateSection(PetsPage, "Slot yang Dipakai", "secPtSlots")
    ChipFrame = Instance.new("Frame", PetsPage)
    ChipFrame.BackgroundTransparency = 1
    ChipFrame.Size = UDim2.new(1, 0, 0, 0)
    ChipFrame.AutomaticSize = Enum.AutomaticSize.Y
    local grid = Instance.new("UIGridLayout", ChipFrame)
    grid.CellSize = UDim2.fromOffset(46, 32)
    grid.CellPadding = UDim2.fromOffset(8, 8)
    grid.SortOrder = Enum.SortOrder.LayoutOrder

    local function PaintChips()
        local active = {}
        for _, slot in ipairs(DS.ParseSlots(EngineConfig.PetExpSlots, 99)) do active[slot] = true end
        local primary = GetThemeColor and GetThemeColor("Primary") or Color3.fromRGB(80, 130, 255)
        for index, chip in pairs(Chips) do
            chip.BackgroundColor3 = active[index] and primary or Color3.fromRGB(35, 35, 50)
            chip.TextColor3 = active[index] and Color3.fromRGB(10, 10, 15) or Color3.fromRGB(200, 200, 215)
        end
    end

    -- Buat chip slot 1..Count (yang sudah ada tidak dibuat ulang; jumlah slot bisa baru diketahui belakangan)
    local function EnsureChips(Count)
        for index = 1, Count do
            if not Chips[index] then
                local chip = Instance.new("TextButton", ChipFrame)
                chip.LayoutOrder = index
                chip.Text = tostring(index)
                chip.Font = Enum.Font.GothamBold
                chip.TextSize = 13
                chip.BorderSizePixel = 0
                chip.AutoButtonColor = false
                Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 8)
                chip.MouseButton1Click:Connect(function()
                    local list = DS.ParseSlots(EngineConfig.PetExpSlots, 99)
                    local found, new = false, {}
                    for _, slot in ipairs(list) do
                        if slot == index then found = true else table.insert(new, slot) end
                    end
                    if not found then table.insert(new, index) end
                    EngineConfig.PetExpSlots = DS.SlotsToString(DS.ParseSlots(new, 99))
                    PaintChips()
                end)
                Chips[index] = chip
            end
        end
        PaintChips()
    end
    EnsureChips(4)

    local function UpdateInfo()
        -- telur
        local lines = { Fmt(T("ptInfoStatus"), DS.FormatStatus(Pets.HatchStatus)) }
        local okH, hatch = pcall(Pets.GetHatchInfo)
        if okH and type(hatch) == "table" then
            table.insert(lines, Fmt(T("ptInfoEggs"), hatch.Eggs))
            for _, slot in ipairs(hatch.Slots) do
                local text = Fmt(T("ptInfoSlot"), slot.Index, T("ptSlot_" .. slot.State))
                if slot.Remaining then text = text .. "  " .. FmtTime(slot.Remaining) end
                table.insert(lines, text)
            end
        end
        HatchInfo.Text = table.concat(lines, "\n")

        -- ekspedisi
        lines = { Fmt(T("ptInfoStatus"), DS.FormatStatus(Pets.ExpStatus)) }
        local okE, exp = pcall(Pets.GetExpInfo)
        if okE and type(exp) == "table" then
            table.insert(lines, Fmt(T("ptInfoDaily"), exp.Remaining, exp.Limit))
            for _, slot in ipairs(exp.Slots) do
                table.insert(lines, Fmt(T("ptInfoSlot"), slot.Index, T("ptSlot_" .. slot.State)))
            end
            if exp.SlotCount > 4 then EnsureChips(exp.SlotCount) end
        end
        ExpInfo.Text = table.concat(lines, "\n")
    end

    SyncPets = function()
        PetsSyncing = true
        HatchToggle:SetValue(EngineConfig.PetHatchAuto == true)
        DispatchToggle:SetValue(EngineConfig.PetExpDispatch == true)
        ClaimToggle:SetValue(EngineConfig.PetExpClaim == true)
        PetsSyncing = false
        PaintChips()
        pcall(Pets.OnHatchToggle, EngineConfig.PetHatchAuto == true)
        task.spawn(function() pcall(UpdateInfo) end)
    end

    -- Refresh saat status berubah (digabung/ditunda supaya tidak membebani thread logic)
    local Prev = DS.UIHook.Refresh
    local Pending = false
    DS.UIHook.Refresh = function()
        if Prev then Prev() end
        if Pending then return end
        Pending = true
        task.defer(function()
            Pending = false
            if PetsPage.Parent and PetsPage.Visible then pcall(UpdateInfo) end
        end)
    end

    task.spawn(function()
        while PetsPage.Parent do
            task.wait(1)
            if PetsPage.Visible then
                PaintChips()
                pcall(UpdateInfo)
            end
        end
    end)
    task.spawn(function() pcall(UpdateInfo) end)
end)
if not okP then
    warn("[XiFil] Gagal membuat tab Pets: " .. tostring(errP))
    MakeInfoCard(PetsPage).Text = "⚠️ Pets: " .. tostring(errP)
end

-- dipanggil ui_sync setelah load profil
H.SyncPetsUI = function()
    if DS then pcall(DS.SanitizeConfig) end
    if SyncPets then pcall(SyncPets) end
end

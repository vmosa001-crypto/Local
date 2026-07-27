_G.SelectedBuffs = _G.SelectedBuffs or {}
local urutanToggle = 0
local isAutoOn = false
local isSedangMemilih = false

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

local RemoteEvent = ReplicatedStorage:WaitForChild("Framework")
    :WaitForChild("Gameplay")
    :WaitForChild("WorldPlace")
    :WaitForChild("WorldBonusCardUtil")
    :WaitForChild("RemoteEvent")

local buffList = {
    "Skill Cooldown", "Dash Cooldown", "Critical Damage", "Critical Chance", 
    "Healing", "Frost", "Normal Attack", "Dash Speed", "Attack", 
    "Coroside", "Methysis", "Movement Speed", "Max Health"
}

-- ==========================================
-- PEMBUATAN UI (GUI)
-- ==========================================
-- Hapus GUI lama jika script dijalankan ulang
if CoreGui:FindFirstChild("AutoBuffGUI") then
    CoreGui.AutoBuffGUI:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoBuffGUI"
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 250, 0, 110)
MainFrame.Position = UDim2.new(0.5, -125, 0.2, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true -- Membuat UI bisa digeser
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.Text = "Auto Buff Card"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = MainFrame

-- Master Toggle (ON/OFF)
local ToggleMain = Instance.new("TextButton")
ToggleMain.Size = UDim2.new(0.9, 0, 0, 30)
ToggleMain.Position = UDim2.new(0.05, 0, 0, 35)
ToggleMain.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleMain.Text = "AUTO FARM: OFF"
ToggleMain.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleMain.Font = Enum.Font.GothamBold
ToggleMain.TextSize = 12
ToggleMain.Parent = MainFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleMain

-- Dropdown Button
local DropdownBtn = Instance.new("TextButton")
DropdownBtn.Size = UDim2.new(0.9, 0, 0, 30)
DropdownBtn.Position = UDim2.new(0.05, 0, 0, 70)
DropdownBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
DropdownBtn.Text = "Pilih Buff (▼)"
DropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DropdownBtn.Font = Enum.Font.GothamSemibold
DropdownBtn.TextSize = 12
DropdownBtn.Parent = MainFrame

local DropdownCorner = Instance.new("UICorner")
DropdownCorner.CornerRadius = UDim.new(0, 6)
DropdownCorner.Parent = DropdownBtn

-- Scrolling Frame untuk List Buff
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size = UDim2.new(0.9, 0, 0, 200)
ScrollFrame.Position = UDim2.new(0.05, 0, 0, 105)
ScrollFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 5
ScrollFrame.Visible = false 
ScrollFrame.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 5)
UIListLayout.Parent = ScrollFrame

local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 6)
ScrollCorner.Parent = ScrollFrame

-- Logika Interaksi UI
ToggleMain.MouseButton1Click:Connect(function()
    isAutoOn = not isAutoOn
    if isAutoOn then
        ToggleMain.Text = "AUTO FARM: ON"
        ToggleMain.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    else
        ToggleMain.Text = "AUTO FARM: OFF"
        ToggleMain.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    end
end)

DropdownBtn.MouseButton1Click:Connect(function()
    ScrollFrame.Visible = not ScrollFrame.Visible
    if ScrollFrame.Visible then
        MainFrame.Size = UDim2.new(0, 250, 0, 315)
        DropdownBtn.Text = "Tutup Buff (▲)"
    else
        MainFrame.Size = UDim2.new(0, 250, 0, 110)
        DropdownBtn.Text = "Pilih Buff (▼)"
    end
end)

-- Membuat Item di dalam Dropdown
for i, buffName in ipairs(buffList) do
    local BuffBtn = Instance.new("TextButton")
    BuffBtn.Size = UDim2.new(1, -10, 0, 25)
    BuffBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
    BuffBtn.Text = buffName
    BuffBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
    BuffBtn.Font = Enum.Font.Gotham
    BuffBtn.TextSize = 11
    BuffBtn.Parent = ScrollFrame

    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 4)
    BtnCorner.Parent = BuffBtn
    
    -- Sesuaikan warna jika script di-execute ulang
    if _G.SelectedBuffs[buffName] then
        BuffBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 200)
        BuffBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end

    BuffBtn.MouseButton1Click:Connect(function()
        if _G.SelectedBuffs[buffName] then
            _G.SelectedBuffs[buffName] = nil
            BuffBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
            BuffBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
        else
            urutanToggle = urutanToggle + 1
            _G.SelectedBuffs[buffName] = urutanToggle
            BuffBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 200)
            BuffBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end)
end

ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, UIListLayout.AbsoluteContentSize.Y + 10)

-- ==========================================
-- LOGIKA AUTO SELECT & PRIORITAS
-- ==========================================
local function romawiKeAngka(str)
    local map = {I = 1, V = 5, X = 10, L = 50, C = 100}
    local total, prev = 0, 0
    for i = #str, 1, -1 do
        local char = string.sub(str, i, i)
        local curr = map[char] or 0
        if curr < prev then total = total - curr else total = total + curr end
        prev = curr
    end
    return total
end

local function parseTeksKartu(teks)
    -- Bersihkan spasi berlebih bawaan dari game
    teks = string.gsub(teks, "%s+", " ")
    teks = string.match(teks, "^%s*(.-)%s*$") or teks 
    
    local namaDasar, romawi = string.match(teks, "^(.+)%s+([IVXLCDM]+)$")
    if namaDasar and romawi then
        return namaDasar, romawiKeAngka(romawi)
    end
    return teks, 0
end

local function AutoSelectKalkulasi()
    if not isAutoOn or isSedangMemilih then return end
    isSedangMemilih = true
    
    task.wait(0.2) -- Jeda memastikan semua 4 kartu muncul di UI
    
    local success, cardsContainer = pcall(function()
        return gui.MainGuiIgnoreGuiInset.PlayerBonusCard.Cards
    end)
    
    if not success or not cardsContainer then 
        isSedangMemilih = false 
        return 
    end

    local daftarKartu = {}
    
    for i = 1, 4 do
        local item = cardsContainer:FindFirstChild("Item" .. i)
        if item then
            local btn = item:FindFirstChild("BTN")
            local stat = btn and btn:FindFirstChild("Stat")
            local textLabel = stat and stat:FindFirstChild("Name")
            
            if textLabel and textLabel:IsA("TextLabel") and textLabel.Text ~= "" and textLabel.Text ~= "Name" then
                local namaDasar, level = parseTeksKartu(textLabel.Text)
                
                if _G.SelectedBuffs and _G.SelectedBuffs[namaDasar] then
                    table.insert(daftarKartu, {
                        index = i,
                        namaDasar = namaDasar,
                        level = level,
                        urutanOn = _G.SelectedBuffs[namaDasar]
                    })
                end
            end
        end
    end

    if #daftarKartu > 0 then
        table.sort(daftarKartu, function(a, b)
            if a.namaDasar == b.namaDasar then
                if a.index == 4 then return true end
                if b.index == 4 then return false end
                return a.level > b.level 
            end
            
            if a.level ~= b.level then
                return a.level > b.level 
            end
            
            return a.urutanOn < b.urutanOn
        end)

        local target = daftarKartu[1]
        print("[AUTO-BUFF] Menembak:", target.namaDasar, "| Level:", target.level, "| Index:", target.index)
        
        if target.index == 4 then
            RemoteEvent:FireServer("Unlock", 4)
        else
            RemoteEvent:FireServer("Select", target.index)
        end
    end

    task.wait(1) -- Jeda anti-spam
    isSedangMemilih = false
end

-- ==========================================
-- SISTEM TRIGGER / PEMANTAUAN ELEMEN (DIPERBAIKI)
-- ==========================================
local function pantauElemen(instance)
    if instance.Name == "Name" and instance:IsA("TextLabel") then
        
        -- 1. Pengecekan instan saat kartu baru dirender di layar
        if isAutoOn and instance.Text ~= "" and instance.Text ~= "Name" then
            task.spawn(AutoSelectKalkulasi)
        end

        -- 2. Pengecekan jika teksnya berubah (update)
        instance:GetPropertyChangedSignal("Text"):Connect(function()
            if isAutoOn and instance.Text ~= "" and instance.Text ~= "Name" then
                AutoSelectKalkulasi()
            end
        end)
    end
end

local function scanAwal(instance)
    if not instance then return end
    pantauElemen(instance)
    for _, child in ipairs(instance:GetChildren()) do
        scanAwal(child)
    end
end

local success, cardsContainer = pcall(function()
    return gui.MainGuiIgnoreGuiInset.PlayerBonusCard.Cards
end)

if success and cardsContainer then
    print("=== SCRIPT AUTO BUFF SIAP ===")
    scanAwal(cardsContainer)
    
    cardsContainer.DescendantAdded:Connect(function(descendant)
        task.wait(0.3) -- Sedikit delay agar elemen selesai di-load sebelum diperiksa
        pantauElemen(descendant)
    end)
else
    warn("Gagal menemukan path Cards! Pastikan sudah di dalam game.")
end

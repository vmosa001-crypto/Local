--------------------------------------------------------------------------------
--// ui/tab_npc.lua — Tab Npc: pindai NPC di map, teleport, buka dialog (shop)
--// Tata letak: tombol-tombol di atas (satu baris / landscape), hasil scan di bawah:
--//   Area 1 -> daftar NPC, tepat di bawahnya Area 2 -> daftar NPC (+ "Lainnya" bila ada).
--// Logika scan/teleport berasal dari "NPC Teleport Panel" (standalone).
--------------------------------------------------------------------------------
local H            = getgenv().Hub
local LocalPlayer  = H.LocalPlayer
local Workspace    = H.Workspace or game:GetService("Workspace")
local Players      = game:GetService("Players")

local CreateTab     = H.CreateTab
local CreateSection = H.CreateSection
local CreateButton  = H.CreateButton
local GetThemeColor = H.GetThemeColor

local NpcPage = CreateTab("👤 Npc")

--------------------------------------------------------------------
-- konfigurasi area
--------------------------------------------------------------------
local EXCLUDE = { "EnemyNpc", "WorldEnemys", "Enemys", "Monsters", "Breakables" }

-- NPC dengan jarak <= AREA_RADIUS (studs) ke titik pusat masuk area itu.
local AREA_RADIUS = 300
local AREAS = {
    { name = "Area 1", pos = Vector3.new(-36, 34, 4) },
    { name = "Area 2", pos = Vector3.new(9975, 14, -8) },
}
local OTHER_AREA  = "Lainnya"
local GROUP_ORDER = { "Area 1", "Area 2", OTHER_AREA }

local function areaOf(position)
    local best, bestDist = OTHER_AREA, AREA_RADIUS
    for _, a in ipairs(AREAS) do
        local d = (position - a.pos).Magnitude
        if d <= bestDist then best, bestDist = a.name, d end
    end
    return best
end

--------------------------------------------------------------------
-- scan NPC
--------------------------------------------------------------------
local function excluded(inst)
    local cur = inst
    while cur and cur ~= Workspace do
        if table.find(EXCLUDE, cur.Name) then return true end
        if Players:GetPlayerFromCharacter(cur) then return true end
        cur = cur.Parent
    end
    return false
end

local function anchorOf(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        return inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart")
            or inst:FindFirstChildWhichIsA("BasePart", true)
    end
end

local function myRoot()
    local char = LocalPlayer and LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function scan()
    local found, seen = {}, {}
    local function add(owner, prompt)
        if not owner or seen[owner] or excluded(owner) then return end
        local part = anchorOf(owner)
        if not part then return end
        seen[owner] = true
        local label = owner.Name
        if prompt and prompt.ObjectText ~= "" and prompt.ObjectText ~= owner.Name then
            label = label .. " (" .. prompt.ObjectText .. ")"
        elseif prompt and prompt.ActionText ~= "" then
            label = label .. " [" .. prompt.ActionText .. "]"
        end
        table.insert(found, { name = label, part = part, prompt = prompt, area = areaOf(part.Position) })
    end
    for _, d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            add(d:FindFirstAncestorOfClass("Model") or d.Parent, d)
        elseif d:IsA("Humanoid") then
            local model = d.Parent
            if model and model:IsA("Model") and not seen[model] then
                add(model, model:FindFirstChildWhichIsA("ProximityPrompt", true))
            end
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    local count = {}
    for _, n in ipairs(found) do
        count[n.name] = (count[n.name] or 0) + 1
        if count[n.name] > 1 then n.name = n.name .. " #" .. count[n.name] end
    end
    return found
end

--------------------------------------------------------------------
-- state
--------------------------------------------------------------------
local npcs        = {}
local selected    = nil
local filterText  = ""
local autoRescan  = false
local rows        = {}      -- { btn = TextButton, dist = TextLabel, npc = npc }
local StatusLabel, ResultFrame, AutoBtn

local function setStatus(text)
    if StatusLabel then StatusLabel.Text = text end
end

local function distanceTo(npc)
    local root = myRoot()
    if not root or not npc.part or not npc.part.Parent then return nil end
    return math.floor((npc.part.Position - root.Position).Magnitude)
end

local function distText(d) return d and (tostring(d) .. "m") or "-" end

--------------------------------------------------------------------
-- tata letak: tombol di atas (landscape) -> status -> cari -> hasil
--------------------------------------------------------------------
CreateSection(NpcPage, "NPC Teleport")

local Toolbar = Instance.new("Frame", NpcPage)
Toolbar.BackgroundTransparency = 1
Toolbar.Size = UDim2.new(1, 0, 0, 40)
Toolbar.BorderSizePixel = 0
local grid = Instance.new("UIGridLayout", Toolbar)
grid.CellSize = UDim2.new(0.2, -5, 1, 0)
grid.CellPadding = UDim2.new(0, 6, 0, 0)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.FillDirection = Enum.FillDirection.Horizontal

local function toolButton(order, text, callback)
    local b = CreateButton(Toolbar, text, function() task.spawn(callback) end)
    b.LayoutOrder = order
    b.TextWrapped = true
    return b
end

StatusLabel = Instance.new("TextLabel", NpcPage)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Size = UDim2.new(1, 0, 0, 0)
StatusLabel.AutomaticSize = Enum.AutomaticSize.Y
StatusLabel.TextWrapped = true
StatusLabel.Font = Enum.Font.GothamMedium
StatusLabel.TextSize = 11
StatusLabel.TextColor3 = Color3.fromRGB(150, 162, 186)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = "Tekan Rescan untuk memindai NPC"

local SearchBG = Instance.new("Frame", NpcPage)
SearchBG.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
SearchBG.BackgroundTransparency = 0.2
SearchBG.Size = UDim2.new(1, 0, 0, 34)
SearchBG.BorderSizePixel = 0
Instance.new("UICorner", SearchBG).CornerRadius = UDim.new(0, 8)
local SearchStroke = Instance.new("UIStroke", SearchBG)
SearchStroke.Color = Color3.fromRGB(50, 50, 60); SearchStroke.Thickness = 1
local SearchBox = Instance.new("TextBox", SearchBG)
SearchBox.BackgroundTransparency = 1
SearchBox.Size = UDim2.new(1, -24, 1, 0); SearchBox.Position = UDim2.new(0, 12, 0, 0)
SearchBox.Font = Enum.Font.GothamMedium; SearchBox.TextSize = 12
SearchBox.TextColor3 = Color3.fromRGB(235, 240, 250)
SearchBox.PlaceholderText = "🔍 Cari NPC..."
SearchBox.PlaceholderColor3 = Color3.fromRGB(150, 162, 186)
SearchBox.Text = ""; SearchBox.ClearTextOnFocus = false
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Focused:Connect(function() SearchStroke.Color = GetThemeColor("Primary") end)
SearchBox.FocusLost:Connect(function() SearchStroke.Color = Color3.fromRGB(50, 50, 60) end)

ResultFrame = Instance.new("Frame", NpcPage)
ResultFrame.BackgroundTransparency = 1
ResultFrame.Size = UDim2.new(1, 0, 0, 0)
ResultFrame.AutomaticSize = Enum.AutomaticSize.Y
ResultFrame.BorderSizePixel = 0
local resultLayout = Instance.new("UIListLayout", ResultFrame)
resultLayout.SortOrder = Enum.SortOrder.LayoutOrder
resultLayout.Padding = UDim.new(0, 4)

--------------------------------------------------------------------
-- daftar hasil: Area 1 -> NPC, lalu Area 2 -> NPC (+ Lainnya bila ada)
--------------------------------------------------------------------
local ROW_BG = Color3.fromRGB(28, 36, 55)

local function paintSelection()
    local primary = GetThemeColor("Primary")
    for _, r in ipairs(rows) do
        pcall(function()
            r.btn.BackgroundColor3 = (selected == r.npc) and primary or ROW_BG
        end)
    end
end

local function makeHeader(order, title, count)
    local hdr = Instance.new("Frame", ResultFrame)
    hdr.LayoutOrder = order
    hdr.BackgroundColor3 = Color3.fromRGB(15, 15, 22)
    hdr.Size = UDim2.new(1, 0, 0, 26)
    hdr.BorderSizePixel = 0
    Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 6)
    local dot = Instance.new("Frame", hdr)
    dot.BackgroundColor3 = GetThemeColor("Primary")
    dot.Size = UDim2.new(0, 5, 0, 5); dot.AnchorPoint = Vector2.new(0, 0.5)
    dot.Position = UDim2.new(0, 8, 0.5, 0); dot.BorderSizePixel = 0
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
    local lbl = Instance.new("TextLabel", hdr)
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 20, 0, 0); lbl.Size = UDim2.new(1, -28, 1, 0)
    lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 12
    lbl.TextColor3 = Color3.fromRGB(235, 240, 250)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = string.format("%s  (%d NPC)", title, count)
end

local function makeEmpty(order)
    local lbl = Instance.new("TextLabel", ResultFrame)
    lbl.LayoutOrder = order
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, 0, 0, 22)
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 11
    lbl.TextColor3 = Color3.fromRGB(110, 120, 145)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = "   — tidak ada NPC —"
end

local function makeRow(order, npc, dist)
    local b = Instance.new("TextButton", ResultFrame)
    b.LayoutOrder = order
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = ROW_BG
    b.AutoButtonColor = true
    b.Text = ""
    b.BorderSizePixel = 0
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
    local name = Instance.new("TextLabel", b)
    name.BackgroundTransparency = 1
    name.Position = UDim2.new(0, 12, 0, 0); name.Size = UDim2.new(1, -82, 1, 0)
    name.Font = Enum.Font.GothamMedium; name.TextSize = 12
    name.TextColor3 = Color3.fromRGB(235, 240, 250)
    name.TextXAlignment = Enum.TextXAlignment.Left
    name.TextTruncate = Enum.TextTruncate.AtEnd
    name.Text = npc.name
    local d = Instance.new("TextLabel", b)
    d.AnchorPoint = Vector2.new(1, 0)
    d.BackgroundTransparency = 1
    d.Position = UDim2.new(1, -10, 0, 0); d.Size = UDim2.new(0, 64, 1, 0)
    d.Font = Enum.Font.GothamBold; d.TextSize = 11
    d.TextColor3 = Color3.fromRGB(190, 200, 222)
    d.TextXAlignment = Enum.TextXAlignment.Right
    d.Text = distText(dist)
    b.MouseButton1Click:Connect(function()
        selected = npc
        setStatus("Dipilih: " .. npc.name)
        paintSelection()
    end)
    table.insert(rows, { btn = b, dist = d, npc = npc })
end

local function rebuildList()
    for _, c in ipairs(ResultFrame:GetChildren()) do
        if not c:IsA("UIListLayout") then c:Destroy() end
    end
    rows = {}

    local q = string.lower(filterText)
    local groups = {}
    for _, key in ipairs(GROUP_ORDER) do groups[key] = {} end
    for _, n in ipairs(npcs) do
        if q == "" or string.find(string.lower(n.name), q, 1, true) then
            table.insert(groups[n.area] or groups[OTHER_AREA], { npc = n, dist = distanceTo(n) })
        end
    end

    local order = 0
    local function nextOrder() order = order + 1; return order end

    for _, key in ipairs(GROUP_ORDER) do
        local list = groups[key]
        -- "Lainnya" hanya ditampilkan kalau memang ada isinya
        if key ~= OTHER_AREA or #list > 0 then
            table.sort(list, function(a, b) return (a.dist or math.huge) < (b.dist or math.huge) end)
            makeHeader(nextOrder(), key, #list)
            if #list == 0 then
                makeEmpty(nextOrder())
            else
                for _, e in ipairs(list) do makeRow(nextOrder(), e.npc, e.dist) end
            end
        end
    end
    paintSelection()
end

local function refreshDistances()
    for _, r in ipairs(rows) do
        pcall(function() r.dist.Text = distText(distanceTo(r.npc)) end)
    end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    filterText = SearchBox.Text
    rebuildList()
end)

--------------------------------------------------------------------
-- aksi
--------------------------------------------------------------------
local function doScan()
    local ok, result = pcall(scan)
    if not ok then setStatus("Gagal memindai: " .. tostring(result)); return end
    npcs = result
    if selected then
        local keep
        for _, n in ipairs(npcs) do if n.name == selected.name then keep = n end end
        selected = keep
    end
    setStatus(#npcs == 0 and "Tidak ada NPC ditemukan di map ini" or ("Ditemukan " .. #npcs .. " NPC"))
    rebuildList()
end

-- Rescan otomatis saat PLAYER pindah area (tombol teleport / jalan manual).
-- NPC area baru baru ter-stream sebentar kemudian: scan 1.5 dtk lalu 2.5 dtk berikutnya.
local lastPlayerArea
local areaToken = 0

local function checkAreaChange()
    local root = myRoot()
    if not root then return end
    local now = areaOf(root.Position)
    if lastPlayerArea == nil then lastPlayerArea = now; return end
    if now == lastPlayerArea then return end

    local from = lastPlayerArea
    lastPlayerArea = now
    areaToken = areaToken + 1
    local mine = areaToken
    setStatus(from .. " -> " .. now .. " | rescan otomatis...")
    task.spawn(function()
        task.wait(1.5)
        if mine ~= areaToken or not NpcPage.Parent then return end
        doScan()
        task.wait(2.5)
        if mine ~= areaToken or not NpcPage.Parent then return end
        doScan()
        setStatus(from .. " -> " .. now .. " | " .. #npcs .. " NPC")
    end)
end

local function gotoSelected()
    if not selected then setStatus("Pilih NPC dulu"); return false end
    local root = myRoot()
    if not root then setStatus("Karakter belum siap"); return false end
    if not selected.part or not selected.part.Parent then
        setStatus("NPC sudah hilang - tekan Rescan")
        return false
    end
    local p = selected.part.Position
    local stand = p + selected.part.CFrame.LookVector * 4 + Vector3.new(0, 2, 0)
    root.CFrame = CFrame.lookAt(stand, Vector3.new(p.X, stand.Y, p.Z))
    setStatus("Teleport ke " .. selected.name)
    task.wait(0.2)
    checkAreaChange()
    return true
end

local function interact()
    if not gotoSelected() then return end
    task.wait(0.35)
    if selected and selected.prompt and selected.prompt.Parent and type(fireproximityprompt) == "function" then
        pcall(fireproximityprompt, selected.prompt)
        setStatus("Interaksi dengan " .. selected.name)
    else
        setStatus("Sudah dekat NPC (tanpa prompt / fireproximityprompt tidak ada)")
    end
end

local function copyList()
    local lines = {}
    for _, n in ipairs(npcs) do
        local p = n.part.Position
        table.insert(lines, string.format("[%s] %s | Vector3.new(%.1f, %.1f, %.1f)", n.area, n.name, p.X, p.Y, p.Z))
    end
    if type(setclipboard) == "function" then
        pcall(setclipboard, table.concat(lines, "\n"))
        setStatus(#lines .. " baris disalin")
    else
        setStatus("setclipboard tidak tersedia")
    end
end

--------------------------------------------------------------------
-- tombol (satu baris di atas)
--------------------------------------------------------------------
toolButton(1, "Teleport", gotoSelected)
toolButton(2, "Teleport + Dialog", interact)
toolButton(3, "Rescan", doScan)
toolButton(4, "Copy list", copyList)
AutoBtn = toolButton(5, "Auto rescan: OFF", function()
    autoRescan = not autoRescan
    AutoBtn.Text = "Auto rescan: " .. (autoRescan and "ON" or "OFF")
    AutoBtn.TextColor3 = autoRescan and Color3.fromRGB(52, 211, 153) or Color3.fromRGB(220, 220, 220)
end)

--------------------------------------------------------------------
-- loop: jaga jarak tetap segar; rescan penuh tiap 5 dtk bila Auto ON
--------------------------------------------------------------------
task.spawn(function()
    local tick = 0
    while NpcPage.Parent do
        task.wait(1)
        tick = tick + 1
        pcall(checkAreaChange)
        if NpcPage.Visible then
            if autoRescan and tick % 5 == 0 then
                doScan()
            else
                pcall(refreshDistances)
            end
        end
    end
end)

rebuildList()                       -- tampilkan header Area 1 / Area 2 sejak awal
task.delay(2, function()            -- scan awal setelah GUI selesai dimuat
    if NpcPage.Parent then doScan() end
end)

-- XiFil Hub — IronSoul V1 | loader.lua
-- Memuat modul satu per satu. Daftar MODULES ini juga dipakai bundle.py
-- (jangan ubah format barisnya: tiap nama modul di dalam tanda kutip).

if not game:IsLoaded() then game.Loaded:Wait() end
repeat task.wait(0.5) until game.Players.LocalPlayer

if getgenv().XiFilHub_Executed then
    if getgenv().XiFil_CustomNotify then
        getgenv().XiFil_CustomNotify("⚠️ XIFIL HUB", "Script sudah berjalan!", 4)
    end
    return
end
getgenv().XiFilHub_Executed = true
getgenv().Hub = {}

local BASE = "https://raw.githubusercontent.com/iNFINITE-iKII/Infinitee/main/games/ironsoulv1/"

-- Urutan PENTING
local MODULES = {
    "core", "maid", "notify", "config_system",
    "user_data", "combat", "navigation", "farm",
    "auto_potion", "dungeon_sys", "auto_forge", "translate",
    "ui/ui_core", "ui/tab_farm", "ui/tab_vector", "ui/tab_autopotion",
    "ui/tab_forge", "ui/tab_profile", "ui/tab_util", "ui/tab_sell",
    "ui/tab_room", "ui/tab_pets", "ui/tab_autobuy", "ui/tab_visual",
    "ui/tab_map", "ui/tab_npc", "ui/tab_trade", "ui_sync", "init",
}

for _, m in ipairs(MODULES) do
    local ok, err = pcall(function()
        loadstring(game:HttpGet(BASE .. m .. ".lua", true))()
    end)
    if not ok then warn("[XiFil] Gagal load " .. m .. ": " .. tostring(err)) end
end

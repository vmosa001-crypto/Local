# Iron Soul Control Panel (systems/ui.lua)

Tombol bulat "IS" (bisa digeser) membuka/menutup panel. Panel bisa digeser lewat header.

Tab: Home (status + Enable/Disable all) | Auto | Farm | Upgrade | System | Log

Semua nilai disimpan di getgenv().IronSoulConfig dan file IronSoul_UIConfig_V1.json,
dibaca LIVE oleh tiap modul saat Run(). Key kosong = default (aktif), jadi aman bila ui.lua gagal dimuat.

Toggle  : UPGRADE_AUTO TUTORIAL_AUTO PET_AUTO FORTIFY_AUTO ENCHANT_AUTO SHOP_AUTO SKILL_AUTO
          LOADOUT_AUTO CAVE_AUTO HELL_AUTO CAVE_CHASE_AUTO WORLD1_TWEEN HEADLESS DEBUG_LOGS
Pilihan : TICKETS (SMART / MANUAL)
Angka   : CHASE_ENGAGE_DISTANCE CHASE_SPEED CAVE_TICKET_RESERVE CAVE_COOLDOWN CAVE_POWER_PERCENT
          HELL_POWER_PERCENT FORTIFY_SAFE_TARGET FORTIFY_MAX_ACTIONS FORTIFY_GOLD_RESERVE
          ENCHANT_MIN_FORTIFY ENCHANT_MAX_ACTIONS ENCHANT_GOLD_RESERVE SHOP_GOLD_RESERVE
          SHOP_MAX_BUYS FPS_CAP

File baru   : systems/ui.lua
File diubah : lobby.lua, combat.lua, tutorial.lua (memuat UI), cave.lua, pet_manager.lua,
              fortify_manager.lua, enchant_manager.lua, skill_manager.lua,
              skill_loadout_manager.lua, shop_manager.lua, cave_planner.lua, hell_planner.lua,
              upgrade_preflight.lua (gerbang toggle + tunables)

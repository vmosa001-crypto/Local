# READ_MAP — IronSoul V1

Peta modul untuk pencarian cepat. Urutan = urutan muat di `loader.lua`.
Baca peta ini dulu, lalu baca rentang baris yang tepat saja:
`sed -n 'AWAL,AKHIRp' games/ironsoulv1/<modul>.lua`
Dibuat otomatis oleh `tools/readmap.py` — jalankan ulang setelah mengubah kode.

| Modul | Baris | KB |
|---|---:|---:|
| `core` | 291 | 14 |
| `maid` | 29 | 1 |
| `notify` | 71 | 4 |
| `config_system` | 74 | 3 |
| `user_data` | 555 | 19 |
| `combat` | 271 | 11 |
| `navigation` | 474 | 19 |
| `farm` | 1958 | 91 |
| `auto_potion` | 591 | 24 |
| `dungeon_sys` | 1723 | 58 |
| `auto_forge` | 938 | 38 |
| `translate` | 775 | 33 |
| `ui/ui_core` | 1898 | 92 |
| `ui/tab_farm` | 416 | 18 |
| `ui/tab_vector` | 190 | 9 |
| `ui/tab_autopotion` | 271 | 12 |
| `ui/tab_forge` | 1272 | 58 |
| `ui/tab_profile` | 105 | 5 |
| `ui/tab_util` | 717 | 30 |
| `ui/tab_sell` | 502 | 24 |
| `ui/tab_room` | 683 | 30 |
| `ui/tab_pets` | 203 | 8 |
| `ui/tab_autobuy` | 332 | 16 |
| `ui/tab_visual` | 156 | 8 |
| `ui/tab_map` | 223 | 9 |
| `ui/tab_npc` | 432 | 16 |
| `ui/tab_trade` | 1501 | 86 |
| `ui_sync` | 202 | 13 |
| `init` | 335 | 16 |
| **Total** | **17188** | **765** |

## `core.lua` — 291 baris, 14 KB
- Ekspor: `H.EngineConfig`, `H.EquipmentRE`, `H.FARM_PRIORITY_KINDS`, `H.ForgeRF`, `H.GameLists`, `H.GameMatchRE`, `H.GameRoundRE`, `H.GetFarmPriority`, `H.LocalPlayer`, `H.MODE_NAMES`, `H.MaterialRE`, `H.NormalizeFarmPriority`, `H.POSITION_MODES`, `H.PlayerActionRE`, `H.ROOM_WORLD_DISPLAY`, `H.ROOM_WORLD_KEY`, `H.SeasonUtilRE`, `H.Services`, `H.SetFarmPriority`, `H.TweenService`, `H.WORLD_INDEX`, `H.WORLD_NAMES`, `H.Workspace`, `H.WorldBonusCardRE`, `H.WorldPlaceRE`, `H.getModeLabel`, `H.isCaveWorld`, `H.isEndlessTower`
- Bagian: L6 [S01] SERVICES & REMOTES; L54 [S02] ENGINE CONFIG & KONSTANTA
- Fungsi: waitChain:25, isCaveWorld:82, isEndlessTower:87, getModeLabel:95, NormalizeFarmPriority:222, GetFarmPriority:243, SetFarmPriority:253

## `maid.lua` — 29 baris, 1 KB
- Ekspor: `H.Maid`, `H.RuntimeMaid`
- Bagian: L6 [S03] MAID
- Fungsi: Maid.new:9, Maid:GiveTask:10, Maid:DoCleaning:11

## `notify.lua` — 71 baris, 4 KB
- Ekspor: `H.CustomNotify`, `H.NC`
- Bagian: L9 [S04] NOTIFICATION ENGINE
- Fungsi: CustomNotify:27

## `config_system.lua` — 74 baris, 3 KB
- Ekspor: `H.ConfigSystem`, `H.FOLDER_NAME`, `H.HttpService`
- Bagian: L9 [S05] CONFIG SYSTEM
- Fungsi: ConfigSystem.GetAutoLoadPointer:16, ConfigSystem.SaveAutoLoadPointer:21, ConfigSystem.GetConfigList:22, ConfigSystem.SaveNew:29, ConfigSystem.OverwriteExisting:35, ConfigSystem.Load:36, ConfigSystem.Delete:50, ConfigSystem.ExecuteAutoLoad:55

## `user_data.lua` — 555 baris, 19 KB
- Ekspor: `H.Codes`, `H.ForgeRecipes`, `H.Maps`, `H.Waypoints`
- Fungsi: ensureFolder:16, readJson:22, writeJson:33, copyList:104, loadWaypoints:110, saveWaypoints:127, Waypoints.Get:134, Waypoints.GetVectors:139, Waypoints.IsCustom:146, Waypoints.Add:148, Waypoints.RemoveMany:157, Waypoints.Reset:180, Waypoints.Parse:187, mapsSave:214, nameTaken:218, registerMap:226, Maps.IsCustom:284, Maps.Add:292, Maps.Remove:310, cleanRecipeText:351, cleanRecipe:362, recipesSave:392, ForgeRecipes.Add:429, ForgeRecipes.Clean:448, ForgeRecipes.GetCustom:451, ForgeRecipes.IsRemoved:460, ForgeRecipes.RemoveCustom:462, ForgeRecipes.HideBuiltin:473, ForgeRecipes.Reset:481, codesSave:499, codesLoadDefaults:503, Codes.Add:521, Codes.RemoveMany:537, Codes.Reset:549

## `combat.lua` — 271 baris, 11 KB
- Ekspor: `H.ApplyMovement`, `H.CombatEngine`, `H.DisableAutoFarm`, `H.FireBackLobby`, `H.FireReplayRemote`, `H.GetPositionCFrame`, `H.SetToggleControl`, `H.checkVictoryUi`
- Bagian: L15 [S06] COMBAT ENGINE & HELPER POSISI
- Fungsi: GetPositionCFrame:20, ApplyMovement:52, CombatEngine.ResetPhysics:69, CombatEngine.InterruptableStall:72, CombatEngine.GetLevelType:79, CombatEngine.GetNpcId:87, CombatEngine.GetValidChests:93, CombatEngine.GetValidMonsters:102, CombatEngine.TargetsExistGlobal:123, isVictoryText:128, checkVictoryUi:142, FireReplayRemote:150, FireBackLobby:159, HandleEndOfRound:176, DisableAutoFarm:202

## `navigation.lua` — 474 baris, 19 KB
- Ekspor: `H.Navigation`, `H.anyActiveTargetExists`
- Bagian: L14 [S07] NAVIGATION ENGINE (MODERN FRAMEWORK)
- Fungsi: Navigation.GetPortalRootCFrame:24, Navigation.GetSingleClosestPortal:45, Navigation.TryTriggerPortal:100, Navigation.GetClosestObject:135, anyActiveTargetExists:160, Navigation.SearchWorld1:184, Navigation.SearchWorld2:238, Navigation.SearchWorld3:287, Navigation.SearchWorld4:332, Navigation.SearchWorld5:384, Navigation.SearchCustom:430

## `farm.lua` — 1958 baris, 91 KB
- Ekspor: `H.FindGoldShopScrollingFrame`, `H.FindSeasonShopScrollingFrame`, `H.GetBondShopCatalog`, `H.GetGoldShopCatalog`, `H.GetItemDisplayName`, `H.GetSeasonShopCatalog`, `H.GetShopUtilRE`, `H.startFarmLoop`
- Bagian: L399 [S08] FARM LOOP; L1203 [S09] BACKGROUND LOOPS
- Fungsi: GetEggTier:47, IsEggName:54, IsEggInstance:58, RebuildEggIndex:78, StopEggTracking:87, StartEggTracking:96, ScanEggs:108, GetHighestTierEgg:148, GetActiveDragonEgg:165, GetEggPrompt:202, IsMobileDevice:209, MoveToEgg:217, IsEggGone:238, SnapshotAttrs:249, AttrsChanged:256, triggerEgg:275, TriggerEggIfNeeded:349, FireHeavyAttack:413, FireBowAttack:421, FireWeaponAttack:450, anyFarmToggleActive:496, PickFarmTarget:520, startFarmLoop:546, FindGoldShopRemote:1283, GetShopUtilModule:1301, GetShopUtil:1313, GetShopUtilRE:1318, GetFrameworkSafe:1329, GetItemDisplayName:1340, GetGoldShopCatalog:1361, GetSeasonShopCatalog:1421, GetBondShopCatalog:1461, FindSeasonShopScrollingFrame:1519, FindGoldShopScrollingFrame:1534, _destroyFlyObjects:1717, _restoreCollision:1726

## `auto_potion.lua` — 591 baris, 24 KB
- Ekspor: `H.AutoPotion`
- Fungsi: GetFramework:21, GetItemDisplayName:31, AutoPotion.ShouldCatalog:67, AutoPotion.GetBuffFields:72, AutoPotion.GetBuffAttributeIds:89, AutoPotion.AreBuffsActive:99, AutoPotion.ShouldQueueState:108, AutoPotion.RefreshState:118, AutoPotion.SetStatus:122, AutoPotion.BuildCatalog:129, AutoPotion.GetPlayerAttrEntry:214, AutoPotion.IsEndlessTower:218, AutoPotion.IsSettlementVisible:223, AutoPotion.ResetDungeonGrace:237, AutoPotion.CheckDungeonGrace:247, AutoPotion.IsDungeonEligible:274, AutoPotion.IsEntryActive:297, AutoPotion.GetEntryState:310, AutoPotion.Enqueue:323, AutoPotion.EvaluatePotion:335, AutoPotion.Scan:360, AutoPotion.UseOne:380, AutoPotion.RunQueue:445, AutoPotion.DisconnectSignals:460, AutoPotion.RebuildSignals:472, AutoPotion.StartScanner:531, AutoPotion.SetEnabled:549, AutoPotion.Shutdown:572

## `dungeon_sys.lua` — 1723 baris, 58 KB
- Ekspor: `H.DungeonSys`
- Fungsi: Alive:21, CfgBool:28, CfgInt:32, CfgStr:40, Trim:48, GetWorldId:52, GetDifficulty:56, GetPlayers:57, GetRepeatTotal:58, GetFollowUser:59, GetFollowDelay:60, GetTowerStartRound:62, ParseSlots:71, SlotsToString:94, SanitizeConfig:99, Changed:127, MakeStatus:133, SameStatus:137, FormatStatus:149, WaitChild:162, GetFrameworkModule:175, GetWorldRemoteEvent:182, GetGameMatchRemoteEvent:194, GetGameEnum:201, IsInLobby:208, SetTarget:225, IsGuiVisible:433, TryFireGuiButtonSignals:450, ClickGuiButton:466, GetMainGuiChild:482, WaitForGui:488, FindDeep:500, SetMatchCountTo:506, DescribeCountControls:535, Dungeon.IsEnabled:566, Dungeon.IsBlocked:570, ManualActive:576, Dungeon.GetRepeatInfo:580, Follow.Find:584, Dungeon.GetFollowInfo:597, Follow.Gate:611, AutoLobbyStartGate.IsReady:635, GetScreenMatch:655, DescribeMatchScreens:676, IsAutoStartFreeMatchRoom:689, FindAutoStartPortalPart:696, IsRoom14World:735, ApplyLatestSelection:762, ApplyAutoSelection:796, GetAutoStartRoomRange:805, FindAutoStartFreePortal:812, AutoLobbyStartGate.TouchRoomPortal:829, TouchAutoStartPortal:859, WaitForScreenMatchVisible:871, TryAutoStartSoloDungeon:883, QueueAutoStartSoloDungeon:950, SetStatusIfChanged:958, Dungeon.OnToggle:967, Dungeon.ResetRepeat:978, Dungeon.ResetFollow:983, Dungeon.StartNow:987, Tower.SetStatus:1069, Tower.SetWeaponStatus:1077, Tower.InEndless:1085, Tower.GetHighest:1090, Tower.ResolveStart:1098, Tower.GetInfo:1107, Tower.WeaponModules:1112, Tower.GetWeaponOptions:1119, Tower.ResolveWeapon:1162, Tower.ResetWeaponRequest:1175, Tower.RequestEquip:1180, Tower.TryJoin:1185, Tower.TryStartRun:1245, Tower.OnToggle:1341, Pets.Set:1380, Pets.HatchEggs:1389, Pets.HatchSignature:1414, Pets.WaitSignatureChange:1427, Pets.GetHatchInfo:1438, Pets.HatchStep:1462, Pets.ExpModules:1504, Pets.GetExpInfo:1509, Pets.ExpWaitSlot:1526, Pets.ExpBestPet:1542, Pets.ExpStep:1573, Pets.OnHatchToggle:1644, PetsLoop:1650

## `auto_forge.lua` — 938 baris, 38 KB
- Ekspor: `H.AutoForge`, `H.GetOreCatalog`, `H.GetOreRarityLevels`, `H.IsInLobby`
- Fungsi: CopyMap:18, ClampNumber:24, ReadInventoryCount:33, GetFrameworkModule:47, GetGameEnum:58, GetItemDisplayName:67, IsInLobby:73, GetOreCatalog:84, GetOreRarityLevels:130, AutoForge.ApplyRecipeEdits:217, NormRecipeText:252, AutoForge.AddRecipe:261, AutoForge.RemoveRecipe:292, AutoForge.ResetRecipes:306, AutoForge.SaveToEngineConfig:315, AutoForge.NormalizeStatId:328, AutoForge.NormalizeComposition:333, AutoForge.GetCompositionTotal:345, AutoForge.GetDefaultPoolStats:353, AutoForge.CreateDefaultProfile:357, AutoForge.BuildPoolLookup:370, AutoForge.NormalizeProfile:380, AutoForge.ValidateProfile:434, AutoForge.NormalizeProfiles:462, AutoForge.BuildStatCatalog:480, AutoForge.BuildResultSummary:518, AutoForge.BuildProfileSummary:537, AutoForge.MatchProfile:554, AutoForge.FindMatchingProfile:576, AutoForge.CopyResultData:585, AutoForge.CheckEquipmentStorage:593, AutoForge.GetKeyString:600, AutoForge.GetInventory:609, AutoForge.GetOwnedCount:620, AutoForge.GetCompositionIssue:625, AutoForge.CalculateLimit:656, AutoForge.RefreshState:681, AutoForge.SetStatus:685, AutoForge.WaitForData:690, AutoForge.WaitForQTEProgress:705, AutoForge.RunCraft:718, AutoForge.StartBatch:813

## `translate.lua` — 775 baris, 33 KB
- Ekspor: `H.ApplyTranslations`, `H.CurrentLang`, `H.LANGUAGES`, `H.RegisterTranslation`, `H.RegisterTranslationFn`, `H.SetLanguage`, `H.T`
- Bagian: L6 [S10] TRANSLATE SYSTEM
- Fungsi: T:728, RegisterTranslation:733, RegisterTranslationFn:738, ApplyTranslations:743, SetLanguage:758

## `ui/ui_core.lua` — 1898 baris, 92 KB
- Ekspor: `H.ANIM_MAP`, `H.ANIM_STYLES`, `H.ApplyAllVisuals`, `H.ApplyBgColorTheme`, `H.ApplyBgEffect`, `H.ApplyButtonShape`, `H.ApplyFont`, `H.ApplyTabMode`, `H.ApplyTheme`, `H.ApplyToggleShape`, `H.ApplyTransparency`, `H.BG_EFFECTS`, `H.BG_THEME_NAMES`, `H.BUTTON_RADIUS_MAP`, `H.BUTTON_SHAPES`, `H.BtnClose`, `H.ClearBgEffect`, `H.CreateButton`, `H.CreateCycleUI`, `H.CreateDropdownUI`, `H.CreateInputUI`, `H.CreateMultiCheckUI`, `H.CreateScrollableMultiSelectUI`, `H.CreateSection`, `H.CreateSliderUI`, `H.CreateTab`, `H.CreateToggleUI`, `H.CustomNotify`, `H.FONT_LIST`, `H.FONT_MAP`, `H.GUI_BACKGROUNDS`, `H.GUI_THEMES`, `H.GetRgbHue`, `H.GetThemeColor`, `H.GuiPanels`, `H.GuiRoot`, `H.MainWindow`, `H.MakeDraggable`, `H.MakeResizable`, `H.RegisterPanel`, `H.RegisterThemeElement`, `H.SafeParent`, `H.SetRgbHue`, `H.SwitchTab`, `H.THEME_NAMES`, `H.TOGGLE_RADIUS_MAP`, `H.TOGGLE_SHAPES`, `H.ThemeRegistry`, `H.UpdateFontSize`, `H.UserInputService`, `H.VisualConfig`, `H.rgbHue`
- Bagian: L25 [S11] VISUAL CONFIG & THEMES; L252 [S12] DRAGGABLE & RESIZE; L298 [S13] UI COMPONENT BUILDER; L1184 [S14] MAIN WINDOW & WINDOW CONTROLS; L1345 [S15] TAB SYSTEM; L1568 [S16] BACKGROUND EFFECTS; L1723 [S16b] CONFIG SYSTEM PATCH — VISUAL SETTINGS SAV
- Fungsi: GetThemeColor:109, RegisterThemeElement:129, Color3ToHex:132, RebuildTitleText:140, ApplyTheme:149, ApplyFont:193, ApplyToggleShape:210, ApplyButtonShape:217, ApplyTransparency:223, RegisterPanel:227, ClearBgEffect:231, UpdateFontSize:240, MakeDraggable:257, MakeResizable:275, GetSafeParent:302, CreateSection:318, CreateToggleUI:360, CreateDropdownUI:458, CreateCycleUI:631, CreateInputUI:679, CreateButton:729, CreateScrollableMultiSelectUI:779, CreateMultiCheckUI:1024, CreateSliderUI:1077, CreateMacBtn:1271, CreateTab:1420, ApplyTabMode:1494, ApplyBgEffect:1570, ApplyBgColorTheme:1710, ApplyAllVisuals:1774

## `ui/tab_farm.lua` — 416 baris, 18 KB
- Bagian: L24 [S17] TAB 1 — MAIN FARM
- UI: L26 TAB 🏠 Farm; L28 World; L33 Farm Engine Control; L118 Metode & Posisi Gerakan; L122 Skill Config; L149 Weapon Switcher; L154 Terbang (Fly); L172 Utilities; L263 📡 Discord Webhook
- Fungsi: _getQueueOnTeleport:200, _writeAutoExecFile:219, _removeAutoExecFile:228

## `ui/tab_vector.lua` — 190 baris, 9 KB
- Bagian: L15 [S18] TAB 2 — VECTOR CONFIG
- UI: L17 TAB ⚙️ Vector; L20 Prioritas Monster; L83 🔒 Lock Position; L105 🐉 Dodge Dragon; L166 Dodge Boss; L171 Reset Lock; L179 Kinematic System Parameters
- Fungsi: _formatName:22, _makeStatesCallbacks:56

## `ui/tab_autopotion.lua` — 271 baris, 12 KB
- Ekspor: `H.RebuildPotionUI`
- UI: L18 TAB 🧪 Auto Potion; L19 Auto Potion Control; L102 Buff Potions
- Fungsi: UpdateStatusUI:51

## `ui/tab_forge.lua` — 1272 baris, 58 KB
- Ekspor: `H.RebuildForgeOreUI`, `H.RefreshForgeProfileList`
- UI: L49 TAB ⚒️ Forge; L54 Forge Control; L143 Recipe & Craft; L338 Kelola Resep; L408 Ore Composition; L722 Target Mode
- Fungsi: CopyMap:22, ClampNumber:28, CopyProfile:34, UpdateStatusUI:86, GetRecipeLabel:147, SelectRecipeById:182, BuildRecipeOptions:197, RefreshSummary:319, FilterOreRows:461, ApplyOreSelection:472, MakeEditorInput:850, RefreshEditorRulesUI:967, RefreshEditorPoolUI:1039

## `ui/tab_profile.lua` — 105 baris, 5 KB
- Bagian: L19 [S19] TAB 3 — PROFILE
- UI: L21 TAB 💾 Profil; L22 Data Profiles; L69 System Guard
- Fungsi: RefreshConfigDropdown:28

## `ui/tab_util.lua` — 717 baris, 30 KB
- Ekspor: `H.UtilCodeList`, `H.UtilRaceList`
- UI: L408 TAB 🔧 Utilitas; L413 Redeem Code; L545 Auto Reroll Lottery; L575 Claim Reward Update; L597 Auto Reroll Race
- Fungsi: getCodeRE:22, getLotteryRE:33, getRaceRE:45, getRewardRE:56, normText:150, addRaceAlias:161, collectRaceStrings:172, buildRaceAliasMap:181, getRaceAliasMap:272, identifyRaceFromText:291, readRaceState:319, readRaceSettled:365, waitForRaceChange:376, stopAutoReroll:386, stopOnTargetRace:393

## `ui/tab_sell.lua` — 502 baris, 24 KB
- Bagian: L24 [S20] TAB 4 — SELL
- UI: L26 TAB 💰 Jual; L152 Auto Sell by Rarity (Live); L284 Inventory Management; L482 Merchant System
- Fungsi: _getFw:38, _getTaskRE:43, _getOreCatalog:53, _getDisplayName:89, _shouldSell:100, doSellByRarity:111, RefreshOreList:175, _scanActiveBg:295, sellSpesifikNamaItem:307, runInventoryScanner:314, doSellByScan:404

## `ui/tab_room.lua` — 683 baris, 30 KB
- Ekspor: `H.SyncDungeonUI`
- Bagian: L27 [S21] TAB 5 — ROOM HUB
- UI: L29 TAB 🚪 Room; L101 Matchmaking Control; L224 Room Settings; L242 Match Actions; L266 Auto Room; L326 Dungeon Status; L358 Auto Start; L379 Target Dungeon; L405 Map Terbaru Otomatis; L425 Username (tunggu user di server); L452 Manual; L529 Tower Status; L543 Auto
- Fungsi: MakeSubPage:38, PaintSubButtons:65, SelectSub:75, buildModeList:127, getModeNumber:144, updateModeDropdown:152, Fmt:281, MakeInfoCard:288, UpdateVisibleInfo:644

## `ui/tab_pets.lua` — 203 baris, 8 KB
- Ekspor: `H.SyncPetsUI`
- UI: L15 TAB 🐾 Pets; L62 Egg Hatching; L71 Pet Expedition; L82 Slot yang Dipakai
- Fungsi: Fmt:17, FmtTime:24, MakeInfoCard:29

## `ui/tab_autobuy.lua` — 332 baris, 16 KB
- Bagian: L24 [S22] TAB 6 — AUTO BUY
- UI: L26 TAB 🛒 Auto Buy; L27 Gold Shop Auto-Buyer
- Fungsi: makeCatBtn:42, AddBuyButton:79

## `ui/tab_visual.lua` — 156 baris, 8 KB
- Bagian: L38 [S24] TAB 8 — TAMPILAN; L98 [S25] TAB 9 — FONT & BENTUK; L132 [S26] TAB 10 — EFEK & ANIMASI
- UI: L40 TAB 🎨 Tampilan; L42 Notifikasi; L48 Warna Latar GUI; L53 Tema Warna GUI; L59 Transparansi; L70 Gesture & Open Button; L75 Perilaku Awal GUI; L85 Mode Tab; L91 Bahasa / Translate; L100 TAB 🔤 Font; L102 Font GUI; L107 Pengaturan Ukuran Font; L119 Bentuk Sakelar (Toggle); L125 Bentuk Button Dropdown; L134 TAB ✨ Efek; L136 Gaya Animasi Buka/Tutup; L141 Efek Latar & Partikel; L147 Info

## `ui/tab_map.lua` — 223 baris, 9 KB
- UI: L26 TAB 🗺️ Map; L66 Pilih Map; L74 Titik Posisi; L100 Tambah Titik; L130 Kelola; L185 Map Buatan Sendiri
- Fungsi: currentIdx:31, fmt:33, buildItems:38, noopCallbacks:47, worldSummary:56, selectedSet:91

## `ui/tab_npc.lua` — 432 baris, 16 KB
- UI: L17 TAB 👤 Npc; L127 NPC Teleport
- Fungsi: areaOf:33, excluded:45, anchorOf:55, myRoot:63, scan:68, setStatus:112, distanceTo:116, distText:122, toolButton:139, paintSelection:191, makeHeader:200, makeEmpty:221, makeRow:232, rebuildList:265, refreshDistances:299, doScan:313, checkAreaChange:331, gotoSelected:354, interact:371, copyList:382

## `ui/tab_trade.lua` — 1501 baris, 86 KB
- UI: L14 TAB 💱 Trade; L704 Stall Market
- Fungsi: infoCard:16

## `ui_sync.lua` — 202 baris, 13 KB
- Ekspor: `H.SyncAllVisualUI`
- Bagian: L30 [S27] SYNC ALL VISUAL UI
- Fungsi: _clampRoomMode:23, SyncAllVisualUI:32

## `init.lua` — 335 baris, 16 KB
- Ekspor: `H.PlayIntroAnimation`, `H.ToggleGUI`
- Bagian: L35 [S28] FLOATING TOGGLE BUTTON (Premium); L197 [S29] INTRO ANIMATION; L260 [S30] RGB RAINBOW LOOP; L271 [S31] INISIALISASI; L276 [S31] INISIALISASI (Bagian Akhir Script)
- Fungsi: getRgbHue:32, setRgbHue:33, ToggleGUI:49, PlayIntroAnimation:199

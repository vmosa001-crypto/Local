-- IRON SOUL - STABLE TUTORIAL ENTRY
-- Keep bootstrap routing stable while tutorial logic is versioned separately.

-- UI hook: control panel (toggles / settings). Safe no-op if unavailable.
pcall(function()
    local __lr = getgenv().IronSoulLoadRaw
    if type(__lr) == "function" then __lr("systems/ui.lua") end
end)

local loadRaw = getgenv().IronSoulLoadRaw

do
    local cfg = getgenv().IronSoulConfig or {}
    if cfg.TUTORIAL_AUTO == false then return nil end
end

if type(loadRaw) == "function" then
    local ok, result =
        loadRaw("systems/tutorial_v61_10.lua")

    if ok then
        return result
    end
end

local source = game:HttpGet(
    "https://raw.githubusercontent.com/"
        .. "MUshihara/ironsoulkaitun/main/systems/tutorial_v61_10.lua?t="
        .. tostring(os.time())
)

local fn, err = loadstring(source)
assert(fn, err)
return fn()

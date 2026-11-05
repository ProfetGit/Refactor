--- @integration GearRefactor
--- Purpose: ask Gear Refactor how a looted item compares, what it replaces, and to equip it, through its
---     public API only.
--- Requires: none
--- Events: none
--- Hot: no
local _, R = ...

R.Integrations = R.Integrations or {}
local Gear = {}
R.Integrations.gear = Gear

-- With both addons on, the loot feed carries Gear Refactor's upgrade badge, the upgrade prompt
-- offers to equip it, and Gear Refactor's own popup stands down (its PRD 5.3). GearRefactor.API is
-- another addon's global, resolved by name on every call and never declared as client API.
-- Version 1 gained some of these functions after it shipped, so each is looked for on its own.
local function api(name)
    local fn = R.Capabilities:Resolve("GearRefactor.API." .. name)
    return type(fn) == "function" and fn or nil
end

function Gear:Available()
    return api("GetUpgradeBadge") ~= nil
end

-- { state, text, r, g, b } in Gear Refactor's own colours, or nil when it has nothing to say
-- about the item: not equipment, not usable, or not loaded yet.
function Gear:Badge(link)
    local fn = api("GetUpgradeBadge")
    if not fn or type(link) ~= "string" then
        return nil
    end
    local ok, badge = pcall(fn, link)
    if ok and type(badge) == "table" and type(badge.text) == "string" and type(badge.state) == "string" then
        return badge
    end
    return nil
end

-- The name of the equipped item Gear Refactor compared against, for the upgrade prompt, or
-- nil when the slot is empty or Gear Refactor does not say. Its API hands over that item's
-- link as `replaces` (Gear Refactor PRD 5.2), so the name is read out of the link.
function Gear:ReplacedName(link)
    local fn = api("EvaluateItem")
    if not fn or type(link) ~= "string" then
        return nil
    end
    local ok, verdict = pcall(fn, link)
    local replaces = ok and type(verdict) == "table" and verdict.replaces
    local name = type(replaces) == "string" and replaces:match("|h%[(.-)%]|h")
    return name ~= "" and name or nil
end

-- False in combat: Gear Refactor never equips then, and never queues it for later.
function Gear:CanEquip()
    local fn = api("IsEquipAvailable")
    if not fn then
        return false
    end
    local ok, available = pcall(fn)
    return ok and available == true
end

-- Equips into the slot Gear Refactor compared the item against. The bind confirmation, if
-- the client asks for one, stays the player's.
function Gear:Equip(link)
    local fn = api("EquipItem")
    if not fn or type(link) ~= "string" then
        return false
    end
    local ok, equipped = pcall(fn, link)
    return ok and equipped == true
end

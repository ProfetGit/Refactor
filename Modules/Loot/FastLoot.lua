--- @module loot.fastLoot
--- Purpose: collect loot only while the player's auto-loot preference is active.
--- Requires: InCombatLockdown, C_CVar.GetCVarBool, C_CVar.SetCVar, C_CVar.GetCVarDefault,
---     IsModifiedClick, GetNumLootItems, GetLootSlotInfo, LootSlot
--- Events: LOOT_READY, LOOT_OPENED
--- Hot: no
local _, R = ...
local FastLoot = R:RegisterModule({
    id = "loot.fastLoot", category = "Loot", nameKey = "FAST_LOOT_NAME",
    descriptionKey = "FAST_LOOT_DESC", detailKey = "FAST_LOOT_DETAIL",
    requires = { "InCombatLockdown", "C_CVar.GetCVarBool", "C_CVar.SetCVar", "C_CVar.GetCVarDefault",
        "IsModifiedClick", "GetNumLootItems", "GetLootSlotInfo", "LootSlot" },
    risk = "safe", defaultEnabled = true,
})

-- The engine ticks its own auto-loot every autoLootRate milliseconds, 150 by default.
-- That tick, not the Lua loop below, is what makes a multi-item corpse feel slow.
local RATE = "autoLootRate"

-- LOOT_READY carries the client's own auto-loot answer and is synchronous, so it lands
-- before LOOT_OPENED. LOOT_OPENED stays subscribed as the fallback: looting an already
-- emptied slot is a no-op, so the double call costs nothing.
function FastLoot:OnLoot(_, autoloot)
    if InCombatLockdown() or R:Paused() then
        return
    end
    if type(autoloot) == "boolean" then
        if not autoloot then
            return
        end
    elseif C_CVar.GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then
        return
    end
    for slot = GetNumLootItems(), 1, -1 do
        local _, _, _, _, _, locked = GetLootSlotInfo(slot)
        if not locked then
            LootSlot(slot)
        end
    end
end

function FastLoot:OnEnable()
    C_CVar.SetCVar(RATE, "0")
    R.Broker:Subscribe("LOOT_READY", self.OnLoot, self)
    R.Broker:Subscribe("LOOT_OPENED", self.OnLoot, self)
end

function FastLoot:OnDisable()
    C_CVar.SetCVar(RATE, C_CVar.GetCVarDefault(RATE) or "150")
    R.Broker:UnsubscribeAll(self)
end

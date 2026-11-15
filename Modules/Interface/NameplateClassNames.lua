--- @module interface.nameplateClassNames
--- Purpose: colour friendly players' nameplate names by class, through Blizzard's own setting.
--- Requires: C_CVar.SetCVar, C_CVar.GetCVarDefault
--- Events: none
--- Hot: no
local _, R = ...
local ClassNames = R:RegisterModule({
    id = "interface.nameplateClassNames", category = "Interface", nameKey = "NAMEPLATE_CLASS_NAMES_NAME",
    descriptionKey = "NAMEPLATE_CLASS_NAMES_DESC", detailKey = "NAMEPLATE_CLASS_NAMES_DETAIL",
    requires = { "C_CVar.SetCVar", "C_CVar.GetCVarDefault" },
    risk = "visible", defaultEnabled = false,
})

-- Blizzard's "Use Class Color for Name" checkbox writes the same CVar, and its plates
-- listen for the change, so names recolour without a reload.
local CVAR, FALLBACK = "nameplateUseClassColorForFriendlyPlayerUnitNames", "0"

function ClassNames:OnEnable()
    C_CVar.SetCVar(CVAR, "1")
end

function ClassNames:OnDisable()
    C_CVar.SetCVar(CVAR, C_CVar.GetCVarDefault(CVAR) or FALLBACK)
end

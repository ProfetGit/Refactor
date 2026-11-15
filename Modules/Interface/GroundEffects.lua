--- @module interface.groundEffects
--- Purpose: set grass density, draw distance and fade distance to the player's sliders, restore defaults when off.
--- Requires: C_CVar.SetCVar, C_CVar.GetCVarDefault
--- Events: REFACTOR_SETTINGS_CHANGED, PLAYER_ENTERING_WORLD
--- Hot: no
local _, R = ...
local GroundEffects = R:RegisterModule({
    id = "interface.groundEffects", category = "Camera", nameKey = "GROUND_EFFECTS_NAME",
    descriptionKey = "GROUND_EFFECTS_DESC", detailKey = "GROUND_EFFECTS_DETAIL",
    requires = { "C_CVar.SetCVar", "C_CVar.GetCVarDefault" },
    risk = "visible", defaultEnabled = false,
})

-- The option and the CVar share a name, so the table is the whole mapping. The fallback is
-- the game's own default, used only if the client cannot say what it is.
local CVARS = {
    { name = "groundEffectDensity", fallback = "16" },
    { name = "groundEffectDist", fallback = "70" },
    { name = "groundEffectFade", fallback = "70" },
}

function GroundEffects:Apply(only)
    for _, cvar in ipairs(CVARS) do
        if only == nil or only == cvar.name then
            local value = R.Settings:GetOption(cvar.name)
            if type(value) == "number" then
                C_CVar.SetCVar(cvar.name, string.format("%d", value))
            end
        end
    end
end

-- Every other setting's change lands here too, some of them once per step of a slider drag;
-- only the CVar whose slider moved is written.
function GroundEffects:OnSettingsChanged(_, key)
    if key == nil then
        self:Apply()
        return
    end
    for _, cvar in ipairs(CVARS) do
        if key == cvar.name then
            self:Apply(key)
            return
        end
    end
end

-- The client's graphics quality setting writes these three CVars, so a login or a loading
-- screen is where a value picked here may have been overwritten.
function GroundEffects:OnEnteringWorld()
    self:Apply()
end

function GroundEffects:OnEnable()
    self:Apply()
    R.Broker:Subscribe("REFACTOR_SETTINGS_CHANGED", self.OnSettingsChanged, self)
    R.Broker:Subscribe("PLAYER_ENTERING_WORLD", self.OnEnteringWorld, self)
end

function GroundEffects:OnDisable()
    R.Broker:UnsubscribeAll(self)
    for _, cvar in ipairs(CVARS) do
        C_CVar.SetCVar(cvar.name, C_CVar.GetCVarDefault(cvar.name) or cvar.fallback)
    end
end

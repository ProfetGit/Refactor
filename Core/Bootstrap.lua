--- @core bootstrap
--- Purpose: wire saved variables, modules, window and slash commands to the login sequence.
--- Requires: UnitGUID, DEFAULT_CHAT_FRAME
--- Events: PLAYER_LOGIN
--- Hot: no
local _, R = ...
local bootstrap = {}

function R:Print(message)
    local chat = self.Capabilities:Resolve("DEFAULT_CHAT_FRAME")
    if chat then
        chat:AddMessage(self.L.CHAT_PREFIX .. tostring(message))
    end
end

local function handleSlash(input)
    local lines = R.Commands:Dispatch(input)
    for _, line in ipairs(lines or {}) do
        R:Print(line)
    end
end

-- PLAYER_LOGIN is the first point where saved variables and the player unit both exist.
function bootstrap:OnLogin()
    R.Broker:Unsubscribe("PLAYER_LOGIN", self)
    local guid = R.Capabilities:Resolve("UnitGUID")
    R:InitSavedVariables(guid and guid("player") or nil)
    -- Reconciling on every settings change is what makes the three-state toggle live.
    -- An option is a value inside a feature, never whether one is on, and a slider writes
    -- its option on every step of a drag.
    function R.Settings:OnChanged(id)
        if id == nil or self.optionDefaults[id] == nil then
            R.Registry:ReconcileAll()
        end
        if R.Integrations and R.Integrations.ApplyPriceOptions then
            R.Integrations:ApplyPriceOptions()
        end
    end
    R.UI:Initialize()
    if R.Integrations and R.Integrations.RegisterPriceProviders then
        R.Integrations:RegisterPriceProviders()
    end
    R.Registry:ReconcileAll()
    R:RegisterSlash(handleSlash)
    -- One line, once per account: there is no first-run screen, so a new install has to say
    -- where it lives or it looks like nothing happened.
    if R.Settings.fresh then
        R:Print(R.L.CMD_WELCOME)
    end
end

R.Broker:Subscribe("PLAYER_LOGIN", bootstrap.OnLogin, bootstrap)

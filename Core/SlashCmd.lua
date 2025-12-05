-- Refactor Addon - Slash Commands

local addonName, addon = ...
local L = addon.L

----------------------------------------------
-- Slash Command Handler
----------------------------------------------
local function HandleSlashCommand(msg)
    msg = msg:lower():trim()
    
    if msg == "" or msg == "help" then
        -- Open settings panel
        if addon.SettingsPanel then
            addon.SettingsPanel:Toggle()
        else
            addon.Print(L.SLASH_HELP)
            addon.Print(L.SLASH_HELP_ENABLE)
            addon.Print(L.SLASH_HELP_DISABLE)
            addon.Print(L.SLASH_HELP_STATUS)
        end
        return
    end
    
    local command, argument = msg:match("^(%S+)%s*(.*)$")
    
    if command == "enable" or command == "on" then
        local moduleKey = addon.ParseModuleKey(argument)
        if moduleKey then
            addon.SetDBValue(moduleKey, true, true)
            local info = addon.GetModuleInfo(moduleKey)
            addon.Print(L.SLASH_ENABLED:format(info and info.name or moduleKey))
        else
            addon.Print(L.SLASH_INVALID_MODULE:format(argument))
        end
        
    elseif command == "disable" or command == "off" then
        local moduleKey = addon.ParseModuleKey(argument)
        if moduleKey then
            addon.SetDBValue(moduleKey, false, true)
            local info = addon.GetModuleInfo(moduleKey)
            addon.Print(L.SLASH_DISABLED:format(info and info.name or moduleKey))
        else
            addon.Print(L.SLASH_INVALID_MODULE:format(argument))
        end
        
    elseif command == "status" then
        addon.Print("Module Status:")
        for _, info in ipairs(addon.ModuleInfo) do
            local status = addon.GetDBBool(info.key) and "|cff00ff00ON|r" or "|cffff0000OFF|r"
            print("  " .. info.name .. ": " .. status)
        end
        
    elseif command == "test" then
        -- Debug/test commands
        if argument == "sell" then
            if addon.Modules.AutoSellJunk then
                addon.Modules.AutoSellJunk:SellJunk()
            end
        elseif argument == "repair" then
            if addon.Modules.AutoRepair then
                addon.Modules.AutoRepair:Repair()
            end
        end
        
    else
        addon.Print(L.SLASH_HELP)
    end
end

----------------------------------------------
-- Register Slash Commands
----------------------------------------------
SLASH_REFACTOR1 = "/refactor"
SLASH_REFACTOR2 = "/rf"
SlashCmdList["REFACTOR"] = HandleSlashCommand

-- Refactor Addon - Auto-Invite Module
-- Automatically accepts invites from trusted sources

local addonName, addon = ...
local L = addon.L

local Module = {}

----------------------------------------------
-- Module State
----------------------------------------------
local isEnabled = false

----------------------------------------------
-- Friend/Guild Check Helpers
----------------------------------------------
local function IsInGuild(name)
    if not IsInGuild() then return false end
    
    -- Strip realm from name for comparison
    local shortName = Ambiguate(name, "short")
    
    local numMembers = GetNumGuildMembers()
    for i = 1, numMembers do
        local guildName = GetGuildRosterInfo(i)
        if guildName then
            local guildShortName = Ambiguate(guildName, "short")
            if guildShortName == shortName then
                return true
            end
        end
    end
    return false
end

local function IsFriend(name)
    local shortName = Ambiguate(name, "short")
    
    -- Check regular friends
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
        if friendInfo and Ambiguate(friendInfo.name, "short") == shortName then
            return true
        end
    end
    
    return false
end

local function IsBNetFriend(name)
    local shortName = Ambiguate(name, "short")
    
    local numBNetFriends = BNGetNumFriends()
    for i = 1, numBNetFriends do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo then
            local characterName = accountInfo.gameAccountInfo.characterName
            if characterName and Ambiguate(characterName, "short") == shortName then
                return true
            end
        end
    end
    
    return false
end

----------------------------------------------
-- Should Accept Invite
----------------------------------------------
local function ShouldAcceptInvite(name)
    if not name then return false end
    
    -- Check friends
    if addon.GetDBBool("AutoInvite_Friends") and IsFriend(name) then
        return true
    end
    
    -- Check BNet friends
    if addon.GetDBBool("AutoInvite_BNetFriends") and IsBNetFriend(name) then
        return true
    end
    
    -- Check guild
    if addon.GetDBBool("AutoInvite_Guild") and IsInGuild(name) then
        return true
    end
    
    return false
end

----------------------------------------------
-- Party Invite Handler
----------------------------------------------
local function OnPartyInvite(name)
    if not isEnabled then return end
    
    if ShouldAcceptInvite(name) then
        C_Timer.After(0.2, function()
            AcceptGroup()
            StaticPopup_Hide("PARTY_INVITE")
        end)
    end
end

----------------------------------------------
-- Guild Invite Handler
----------------------------------------------
local function OnGuildInvite(inviter, guildName)
    if not isEnabled then return end
    if not addon.GetDBBool("AutoInvite_GuildInvites") then return end
    
    -- Only auto-accept guild invites from friends/bnet
    if IsFriend(inviter) or IsBNetFriend(inviter) then
        C_Timer.After(0.2, function()
            AcceptGuild()
            StaticPopup_Hide("GUILD_INVITE")
        end)
    end
end

----------------------------------------------
-- Event Frame
----------------------------------------------
local eventFrame = CreateFrame("Frame")

local function RegisterEvents()
    eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    eventFrame:RegisterEvent("GUILD_INVITE_REQUEST")
end

local function UnregisterEvents()
    eventFrame:UnregisterAllEvents()
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PARTY_INVITE_REQUEST" then
        local name = ...
        OnPartyInvite(name)
    elseif event == "GUILD_INVITE_REQUEST" then
        local inviter, guildName = ...
        OnGuildInvite(inviter, guildName)
    end
end)

----------------------------------------------
-- Enable/Disable
----------------------------------------------
function Module:Enable()
    isEnabled = true
    RegisterEvents()
end

function Module:Disable()
    isEnabled = false
    UnregisterEvents()
end

----------------------------------------------
-- Initialization
----------------------------------------------
function Module:OnInitialize()
    if addon.GetDBBool("AutoInvite") then
        self:Enable()
    end
    
    addon.CallbackRegistry:Register("SettingChanged.AutoInvite", function(value)
        if value then
            Module:Enable()
        else
            Module:Disable()
        end
    end)
end

-- Register the module
addon.RegisterModule("AutoInvite", Module)

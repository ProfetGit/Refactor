--- @module chat.urls
--- Purpose: turn web addresses in chat into links that open a copy box.
--- Requires: ChatFrameUtil.AddMessageEventFilter, ChatFrameUtil.RemoveMessageEventFilter, hooksecurefunc,
---     SetItemRef
--- Events: none, chat message filters and a secure post-hook
--- Hot: no, filters run per chat line
local _, R = ...
local Urls = R:RegisterModule({
    id = "chat.urls", category = "Chat", nameKey = "CHAT_URLS_NAME",
    descriptionKey = "CHAT_URLS_DESC", detailKey = "CHAT_URLS_DETAIL",
    requires = { "ChatFrameUtil.AddMessageEventFilter", "ChatFrameUtil.RemoveMessageEventFilter",
        "hooksecurefunc", "SetItemRef" },
    risk = "visible", defaultEnabled = true,
})

local EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_SYSTEM",
}
local PATTERNS = { "%a[%w+.-]*://[^%s|]+", "www%.[%w_-]+%.[^%s|]+" }
local RING_SIZE = 200

-- Addresses are kept in a ring and referenced by index, so a link payload never carries
-- characters that would break the hyperlink markup.
function Urls:Remember(url)
    self.next = (self.next or 0) % RING_SIZE + 1
    self.ring[self.next] = url
    return self.next
end

function Urls:Wrap(text)
    if type(text) ~= "string" or self.state ~= "enabled" then
        return text
    end
    local color = R.Theme:Hex("TEXT_ACTIVE")
    for _, pattern in ipairs(PATTERNS) do
        text = text:gsub(pattern, function(url)
            return "|c" .. color .. "|Hrefactorurl:" .. self:Remember(url) .. "|h[" .. url .. "]|h|r"
        end)
    end
    return text
end

function Urls:Filter(_, _, text, ...)
    local ok, wrapped = pcall(self.Wrap, self, text)
    if ok and wrapped ~= text then
        return false, wrapped, ...
    end
    return false
end

function Urls:OnItemRef(link)
    local index = self.state == "enabled" and type(link) == "string" and link:match("^refactorurl:(%d+)$")
    local url = index and self.ring[tonumber(index)]
    if url then
        R.UI:ShowUrl(url)
    end
end

function Urls:OnEnable()
    self.ring = self.ring or {}
    if not self.filter then
        self.filter = function(...) return self:Filter(...) end
    end
    for _, event in ipairs(EVENTS) do
        ChatFrameUtil.AddMessageEventFilter(event, self.filter)
    end
    if not self.installed then
        self.installed = true
        hooksecurefunc("SetItemRef", function(link)
            R:SafeCall(self, self.OnItemRef, "itemref", link)
        end)
    end
end

function Urls:OnDisable()
    for _, event in ipairs(EVENTS) do
        ChatFrameUtil.RemoveMessageEventFilter(event, self.filter)
    end
    R.Broker:UnsubscribeAll(self)
end

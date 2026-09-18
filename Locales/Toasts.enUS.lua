local _, R = ...
R.L = R.L or {}
local L = R.L
L.UI_Toasts = "Toasts"
L.TOAST_LOOT_NAME = "Loot toasts"
L.TOAST_LOOT_DESC = "Show what you just looted: icon, name, count, and its price."
L.TOAST_LOOT_DETAIL = "Your own loot only. Repeated drops of the same item bump the count on one toast. Gold "
    .. "and currency toasts, the minimum quality and the price line are under Display options. Prices come "
    .. "from your vendor sell price unless you opted into an auction provider, and the toast names the source."
L.TOAST_COUNT = "%s x%d"
L.TOAST_PRICE = "%s (%s)"
L.TOAST_SOURCE_vendor = "vendor"
L.TOAST_SOURCE_tsm = "TSM"
L.TOAST_SOURCE_auctionator = "Auctionator"
L.TOAST_GOLD = "Gold"
L.TOAST_GOLD_DETAIL = "+%s"
L.TOAST_CURRENCY_DETAIL = "+%d"

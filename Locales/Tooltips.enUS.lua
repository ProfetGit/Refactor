local _, R = ...
R.L = R.L or {}
local L = R.L
L.UI_Tooltips = "Tooltips"
L.TOOLTIP_BORDER_NAME = "Rarity-coloured tooltip border"
L.TOOLTIP_BORDER_DESC = "Tint the tooltip border with the item's quality colour."
L.TOOLTIP_BORDER_DETAIL = "Applies to the main, linked and comparison tooltips. The border returns to normal as "
    .. "soon as the tooltip clears, so a recycled tooltip never keeps the previous item's colour."
L.TOOLTIP_HEALTHBAR_NAME = "Hide the tooltip health bar"
L.TOOLTIP_HEALTHBAR_DESC = "Remove the green health bar the game draws under a unit tooltip."
L.TOOLTIP_HEALTHBAR_DETAIL = "The bar is the only part of a tooltip that updates every frame, so hiding it also "
    .. "stops that work. Unit names, level and health text are untouched."
L.TOOLTIP_ANCHOR_NAME = "Tooltip anchor"
L.TOOLTIP_ANCHOR_DESC = "Move the default tooltip to the cursor or a screen corner."
L.TOOLTIP_ANCHOR_DETAIL = "Only tooltips that ask for the default anchor move: the world, unit frames and most "
    .. "of Blizzard's own UI. Bag slots, action buttons and other addons keep their own placement. Pick the "
    .. "mode under Display options."

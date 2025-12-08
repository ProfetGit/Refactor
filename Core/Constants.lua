-- Refactor Addon - Shared Constants
-- Reusable dropdown options and UI constants

local addonName, addon = ...
local L = addon.L

----------------------------------------------
-- Shared Constants Table
----------------------------------------------
addon.Constants = {}
local C = addon.Constants

----------------------------------------------
-- Dropdown Options (used in Settings UI)
----------------------------------------------

-- Modifier key options (SHIFT, CTRL, ALT, NONE)
C.MODIFIER_OPTIONS = {
    { value = "SHIFT", label = L.MODIFIER_SHIFT },
    { value = "CTRL", label = L.MODIFIER_CTRL },
    { value = "ALT", label = L.MODIFIER_ALT },
    { value = "NONE", label = L.MODIFIER_NONE },
}

-- Screen corner options
C.CORNER_OPTIONS = {
    { value = "TOPLEFT", label = L.ANCHOR_TOPLEFT },
    { value = "TOPRIGHT", label = L.ANCHOR_TOPRIGHT },
    { value = "BOTTOMLEFT", label = L.ANCHOR_BOTTOMLEFT },
    { value = "BOTTOMRIGHT", label = L.ANCHOR_BOTTOMRIGHT },
}

-- Tooltip anchor options (includes MOUSE and DEFAULT)
C.TOOLTIP_ANCHOR_OPTIONS = {
    { value = "DEFAULT", label = L.ANCHOR_DEFAULT },
    { value = "MOUSE", label = L.ANCHOR_MOUSE },
    { value = "TOPLEFT", label = L.ANCHOR_TOPLEFT },
    { value = "TOPRIGHT", label = L.ANCHOR_TOPRIGHT },
    { value = "BOTTOMLEFT", label = L.ANCHOR_BOTTOMLEFT },
    { value = "BOTTOMRIGHT", label = L.ANCHOR_BOTTOMRIGHT },
}

-- Mouse side options (for tooltip positioning)
C.MOUSE_SIDE_OPTIONS = {
    { value = "RIGHT", label = L.SIDE_RIGHT },
    { value = "LEFT", label = L.SIDE_LEFT },
    { value = "TOP", label = L.SIDE_TOP },
}

-- ActionCam mode options
C.ACTIONCAM_MODE_OPTIONS = {
    { value = "basic", label = L.ACTIONCAM_BASIC },
    { value = "full", label = L.ACTIONCAM_FULL },
}

-- Auto-release mode options
C.RELEASE_MODE_OPTIONS = {
    { value = "ALWAYS", label = L.RELEASE_ALWAYS },
    { value = "PVP", label = L.RELEASE_PVP },
    { value = "PVE", label = L.RELEASE_PVE },
    { value = "OPENWORLD", label = L.RELEASE_OPENWORLD },
}

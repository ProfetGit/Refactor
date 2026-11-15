-- Where zone exit arrows go, placed by hand in game on 7 Nov 2026 by dragging each arrow to its
-- real crossing on the Forever 1.60.1.70862 world map. From map ID, then the map the arrow leads to, then
-- the spot as a share of the map. These win over the position worked out from the zone shapes and lose
-- to an arrow the player has moved. Only zones that have been checked are listed. Static data, never
-- invalidated.
local _, R = ...
R.ExitDefaults = {
    [1430] = { -- Deadwind Pass
        [1431] = { x = 0.3458, y = 0.3498 }, -- Duskwood
        [1435] = { x = 0.5907, y = 0.4192 }, -- Swamp of Sorrows
    },
    [1431] = { -- Duskwood
        [1430] = { x = 0.8480, y = 0.4052 }, -- Deadwind Pass
        [1433] = { x = 0.9298, y = 0.1236 }, -- Redridge Mountains
        [1434] = { x = 0.4455, y = 0.8880 }, -- Stranglethorn Vale
        [1436] = { x = 0.0931, y = 0.6369 }, -- Westfall
    },
    [1434] = { -- Stranglethorn Vale
        [1431] = { x = 0.4018, y = 0.0442 }, -- Duskwood
    },
    [1436] = { -- Westfall
        [1429] = { x = 0.6084, y = 0.1865 }, -- Elwynn Forest
        [1431] = { x = 0.6716, y = 0.6287 }, -- Duskwood
    },
    [1439] = { -- Darkshore
        [1440] = { x = 0.4346, y = 0.9401 }, -- Ashenvale
    },
    [1440] = { -- Ashenvale
        [1411] = { x = 0.9380, y = 0.7597 }, -- Durotar
        [1413] = { x = 0.6854, y = 0.8807 }, -- The Barrens
        [1439] = { x = 0.2837, y = 0.1258 }, -- Darkshore
        [1442] = { x = 0.4280, y = 0.7287 }, -- Stonetalon Mountains
        [1447] = { x = 0.9532, y = 0.4849 }, -- Azshara
        [1448] = { x = 0.5586, y = 0.2669 }, -- Felwood
    },
    [1442] = { -- Stonetalon Mountains
        [1412] = { x = 0.6545, y = 0.9311 }, -- Mulgore
        [1413] = { x = 0.8455, y = 0.9660 }, -- The Barrens
        [1440] = { x = 0.7888, y = 0.4196 }, -- Ashenvale
        [1443] = { x = 0.2860, y = 0.8164 }, -- Desolace
    },
    [1446] = { -- Tanaris
        [1441] = { x = 0.5166, y = 0.2096 }, -- Thousand Needles
        [1449] = { x = 0.2821, y = 0.5794 }, -- Un'Goro Crater
    },
}

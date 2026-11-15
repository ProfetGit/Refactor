-- Boat and zeppelin routes in WoW Forever, from Method.gg's "All Travel Routes in WoW Forever"
-- (Geekmandem, 14 Oct 2026), read 7 Nov 2026. Not checked in game. Static data, never
-- invalidated.
--
-- The guide gives routes, not coordinates. Each end is a key matched against the start of the
-- town part of a flight point's name ("Menethil Harbor, Wetlands"), so a pin sits at that
-- town's flight master, which is near the dock but not on it. An end with no flight point
-- on the open map draws no pin. Left out on purpose: the Deeprun Tram and the portals, whose
-- doors are nowhere near a flight master, and the Skyborne ships from Zephras Isle, which only
-- Skyborne characters can take.
--
-- faction is nil for a route either side may take. oneWay routes list only the direction they
-- run.
local _, R = ...
R.TravelRoutes = {
    { kind = "boat", faction = "Alliance",
        a = { key = "stormwind harbour", name = "Stormwind Harbour" }, b = { key = "auberdine", name = "Auberdine" } },
    { kind = "boat", faction = "Alliance", oneWay = true,
        a = { key = "auberdine", name = "Auberdine" }, b = { key = "menethil", name = "Menethil Harbor" } },
    { kind = "boat", faction = "Alliance", oneWay = true,
        a = { key = "menethil", name = "Menethil Harbor" }, b = { key = "southshore", name = "Southshore" } },
    { kind = "boat", faction = "Alliance", oneWay = true,
        a = { key = "southshore", name = "Southshore" }, b = { key = "auberdine", name = "Auberdine" } },
    { kind = "boat", faction = "Alliance",
        a = { key = "menethil", name = "Menethil Harbor" }, b = { key = "theramore", name = "Theramore" } },
    { kind = "boat", faction = "Alliance",
        a = { key = "rut'theran", name = "Rut'theran Village" }, b = { key = "auberdine", name = "Auberdine" } },
    { kind = "boat", faction = "Alliance",
        a = { key = "feathermoon", name = "Feathermoon Stronghold" },
        b = { key = "forgotten coast", name = "Forgotten Coast" } },
    { kind = "zeppelin", faction = "Horde",
        a = { key = "orgrimmar", name = "Orgrimmar" }, b = { key = "undercity", name = "Undercity" } },
    { kind = "zeppelin", faction = "Horde",
        a = { key = "undercity", name = "Undercity" }, b = { key = "grom'gol", name = "Grom'gol" } },
    { kind = "zeppelin", faction = "Horde",
        a = { key = "orgrimmar", name = "Orgrimmar" }, b = { key = "grom'gol", name = "Grom'gol" } },
    { kind = "boat",
        a = { key = "ratchet", name = "Ratchet" }, b = { key = "booty bay", name = "Booty Bay" } },
    { kind = "boat",
        a = { key = "steamwheedle port", name = "Steamwheedle Port" },
        b = { key = "powderfuse port", name = "Powderfuse Port" } },
}

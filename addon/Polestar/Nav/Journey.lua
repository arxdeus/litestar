-- Journeys: going anywhere on the map.
--
-- Adapted from Shortest Path Forever by Cillian Berragan (GPL-3.0-or-later,
-- used with permission): Journey/JourneyInput.lua (Shift- and Alt-click
-- planning), Core/API.lua (the public API), Core/TomTom.lua (the TomTom
-- stand-in) and Core/Way.lua (/way).
-- Portions Copyright (C) 2026 Cillian Berragan (Shortest Path Forever, GPL-3.0-or-later); adapted for Polestar, 2026-10-15.
--
--   * Plan to anywhere (nav.mapPlan): Shift-click empty space on the world
--     map or the minimap and the arrow points there, routed like any target
--     (Nav.SetTarget, labelled with the zone and its coordinates). Alt-click
--     does the same on the world map over its icons too, named after the
--     icon (a flight master, a dungeon entrance), except Polestar's own
--     clickable pins, which keep their clicks. Shift- or Alt-clicking the
--     planned spot again lets it go: the arrow returns to the guide.
--   Slim build: the public API for other addons, the TomTom stand-in, /way
--   and following TomTom's arrow are gone.
--
-- Journey.Estimate(from, to, budgeted) -> seconds | nil[, "busy"] and
-- Journey.PlanTo(map, x, y, label) are shared with Nav/Nearby.lua.

local ADDON, ns = ...
local Nav = ns.Nav
local L = ns.L

local type, pairs, ipairs, tonumber, next = type, pairs, ipairs, tonumber, next
local sqrt, floor, abs, huge = math.sqrt, math.floor, math.abs, math.huge
local format, lower = string.format, string.lower

local Journey = {}
Nav.journey = Journey

ns.RegisterDefaults("nav", {
	mapPlan = true,
})

local RUN_SPEED = 7     -- yd/s, the straight-line estimate without the planner
local CONTINENT = 2     -- Enum.UIMapType.Continent; lower is the world and the cosmos
local AGAIN = 0.015     -- of the clicked map's width: a click this close to the planned spot lets it go
local AGAIN_MINIMAP = 0.08 -- of the minimap's radius

---------------------------------------------------------------------------
-- Places
---------------------------------------------------------------------------

local function number(v)
	return type(v) == "number" and v == v and v > -huge and v < huge
end

local function world(map, x, y, f)
	local C = ns.Compat
	if not (C and C.MapToWorld) then return nil end
	return C.MapToWorld(map, x, y, f)
end

local function zoneName(map)
	local C = ns.Compat
	return C and C.GetMapName and C.GetMapName(map) or nil
end

-- "Elwynn Forest 42, 65": what a planned spot is called.
local function spotLabel(map, x, y)
	local name = zoneName(map)
	if not name then return nil end
	return format(L["%s %d, %d"], name, floor(x + 0.5), floor(y + 0.5))
end

-- The spot under (x, y) percent of a map, on the zone that holds it: map, x,
-- y. On a continent map that is the zone under the cursor; nil for open sea,
-- the world map, or a map the client cannot place.
function Journey.ZonePoint(map, x, y)
	local c, wx, wy = world(map, x, y)
	if not c then return nil end
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	if not (info and info.mapType and info.mapType <= CONTINENT) then return map, x, y end
	local child = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(map, x / 100, y / 100)
	if not (child and child.mapID and child.mapID ~= map and (child.mapType or CONTINENT + 1) > CONTINENT) then return nil end
	local zx, zy = ns.Compat.WorldToMap(c, wx, wy, child.mapID)
	if not (zx and zx >= 0 and zx <= 100 and zy >= 0 and zy <= 100) then return nil end
	return child.mapID, zx, zy
end

-- Seconds from `from` ({ map, x, y, f }; nil: the player, Hearthstone
-- included) to `to`: the route planner's estimate (Nav.EstimateTravel, cached
-- there), else running in a straight line on one continent. nil when either
-- end cannot be placed, or across continents without the planner. `budgeted`
-- (the public API only) may answer nil, "busy": the planner's frame budget is
-- spent, and no straight line stands in for it (second review P2).
function Journey.Estimate(from, to, budgeted)
	if Nav.EstimateTravel then
		local s, why = Nav.EstimateTravel(from, to, budgeted)
		if s then return s end
		if why == "busy" then return nil, "busy" end
	end
	local C = ns.Compat
	local fc, fx, fy
	if from then
		fc, fx, fy = world(from.map, from.x, from.y, from.f)
	elseif C and C.GetPlayerWorldPosition then
		fc, fx, fy = C.GetPlayerWorldPosition()
	end
	local tc, tx, ty = world(to.map, to.x, to.y, to.f)
	if not (fc and tc and fc == tc) then return nil end
	return sqrt((tx - fx) ^ 2 + (ty - fy) ^ 2) / RUN_SPEED
end

-- Point the arrow at (x, y) percent of map, moved onto the zone under it.
-- False (and a line in chat) when no route can go there.
function Journey.PlanTo(map, x, y, label, f)
	local zm, zx, zy = map, x, y
	if not f then zm, zx, zy = Journey.ZonePoint(map, x, y) end
	if not zm then
		ns.Print(L["No route can be planned to that spot."])
		return false
	end
	return Nav.SetTarget(zm, zx, zy, label or spotLabel(zm, zx, zy), f)
end

-- A planned target (any picked point) within `yards` of world (c, wx, wy)
-- lets go, and the arrow returns to the guide. True if it did.
local function releaseNear(c, wx, wy, yards)
	if not (Nav.IsOverride() and c) then return false end
	local tc, tx, ty = Nav.GetTargetWorld()
	if tc ~= c or (tx - wx) ^ 2 + (ty - wy) ^ 2 > yards * yards then return false end
	Nav.ReleaseTarget()
	return true
end

-- A Shift- or Alt-click at (x, y) percent of a world map `map`.
function Journey.OnMapClick(map, x, y, label)
	local c, wx, wy = world(map, x, y)
	local c1, top, left = world(map, 0, 0)
	local c2, bottom, right = world(map, 100, 100)
	if c and c1 and c1 == c2 then
		local span = abs(right - left)
		if abs(bottom - top) > span then span = abs(bottom - top) end
		if releaseNear(c, wx, wy, span * AGAIN) then return true end
	end
	return Journey.PlanTo(map, x, y, label)
end

-- A Shift-click on the minimap, at (dNorth, dWest) yards from the player.
function Journey.OnMinimapClick(dNorth, dWest, radius)
	local C = ns.Compat
	local pc, px, py = C.GetPlayerWorldPosition()
	local map = C.GetPlayerMapPosition()
	if not (pc and map and dNorth) then
		ns.Print(L["No route can be planned to that spot."])
		return false
	end
	local wx, wy = px + dNorth, py + dWest
	if releaseNear(pc, wx, wy, (radius or 0) * AGAIN_MINIMAP) then return true end
	local x, y = C.WorldToMap(pc, wx, wy, map)
	if not x then
		ns.Print(L["No route can be planned to that spot."])
		return false
	end
	return Journey.PlanTo(map, x, y)
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------

-- Shortest Path Forever plans map clicks itself while it guides (Nav/Handoff.lua).
local function planning()
	return ns.Get("nav.mapPlan") and not Nav.HandedOff() and true or false
end

-- With Shortest Path Forever installed, its own Shift- and Alt-click plan a journey of its own (its
-- Journey/JourneyInput.lua) whichever addon hears the click first: one click planned in both, and once its journey
-- ended Polestar's arrow stayed on the clicked spot instead of going back to the guide. So with it installed, `fn`
-- (Polestar's plan) waits a frame and is dropped when the click started a journey there (Nav/Handoff.lua
-- ClickTaken); with its journeys off it plans nothing, and Polestar's plan goes ahead. -> true when it waits.
local function leftToShortestPath(fn)
	local H = Nav.handoff
	if not (H and H.Available and H.Available()) then return false end
	ns.After(0, function()
		if not H.ClickTaken() then fn() end
	end)
	return true
end

-- Shift-click inserts links into an open chat box; that click stays Blizzard's.
local function chatOpen()
	local active = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow) or ChatEdit_GetActiveWindow
	return active ~= nil and active() ~= nil
end

local function foci()
	if GetMouseFoci then return GetMouseFoci() end
	return { GetMouseFocus and GetMouseFocus() }
end

-- The world map pin under the cursor: "own" for one of Polestar's clickable
-- pins (they keep their clicks), else its name (or nil) and position (0-1).
-- Polestar's are its own frames (Pins.WorldPinOf), Blizzard's the map's pins.
local function hoveredPin(map)
	local P = ns.Pins
	for _, f in ipairs(foci()) do
		local own = type(f) == "table" and P and P.WorldPinOf and P.WorldPinOf(f)
		if own then
			if own.pin.onClick then return "own" end
			return type(own.pin.tooltip) == "string" and own.pin.tooltip or nil, own.x / 100, own.y / 100
		end
		if type(f) == "table" and f.pinTemplate and f.GetMap and f:GetMap() == map then
			local info = f.poiInfo or f.taxiNodeData
			local name = info and type(info.name) == "string" and info.name or (type(f.name) == "string" and f.name) or nil
			local x, y
			if f.GetPosition then x, y = f:GetPosition() end
			return name, x, y
		end
	end
end

-- Canvas click handlers run before the map's own (zooming into a zone);
-- true takes the click. Clicks on pins never reach them.
local function onCanvasClick(canvas, button)
	if button ~= "LeftButton" or not planning() or not IsShiftKeyDown() or IsAltKeyDown()
		or IsControlKeyDown() or chatOpen() then
		return false
	end
	local mapID = canvas:GetMapID()
	local x, y = canvas:GetNormalizedCursorPosition()
	if not (mapID and x and y) then return false end
	-- Left to Shortest Path Forever, the click goes on to its handler (and the map's own).
	if leftToShortestPath(function() Journey.OnMapClick(mapID, x * 100, y * 100) end) then return false end
	Journey.OnMapClick(mapID, x * 100, y * 100)
	return true
end

-- Shift-click on the target's own pin (which takes the click) lets it go
-- (Pins.OnWorldClick: Polestar's pins are its own frames, not the map's).
local function onOwnPinClick(_, layer, button)
	if button ~= "LeftButton" or not (layer and layer.name == "nav.target") or not planning()
		or not IsShiftKeyDown() or IsAltKeyDown() or chatOpen() or not Nav.IsOverride() then
		return false
	end
	Nav.ReleaseTarget()
	return true
end

-- Alt-click anywhere on the world map, its icons included. Observed through
-- GLOBAL_MOUSE_DOWN, as icons swallow canvas clicks.
local added = {} -- MapCanvas.Add's maps: alt-click and shift-click work there as on the world map
local function onGlobalMouseDown(_, button)
	if button ~= "LeftButton" or not planning() or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
	local map
	for i = 0, #added do
		local m = i == 0 and WorldMapFrame or added[i]
		if m and m:IsShown() and m.ScrollContainer and m.ScrollContainer:IsMouseOver() then map = m; break end
	end
	if not map then return end
	local mapID = map:GetMapID()
	local name, x, y = hoveredPin(map)
	if name == "own" then return end
	if not x then x, y = map:GetNormalizedCursorPosition() end
	if not (mapID and x and y) then return end
	if leftToShortestPath(function() Journey.OnMapClick(mapID, x * 100, y * 100, name) end) then return end
	Journey.OnMapClick(mapID, x * 100, y * 100, name)
end

-- The stock handler still pings the spot, which shows your group too.
local function onMinimapUp(_, button)
	if button ~= "LeftButton" or not planning() or not IsShiftKeyDown() then return end
	local P = ns.Pins
	if not (P and P.MinimapCursor) then return end
	local dNorth, dWest = P.MinimapCursor()
	local radius = P.MinimapView()
	if leftToShortestPath(function() Journey.OnMinimapClick(dNorth, dWest, radius) end) then return end
	Journey.OnMinimapClick(dNorth, dWest, radius)
end

local worldHooked, minimapHooked = false, false

-- Not with the gamepad interface (ns.GamepadUI): the handler is a write
-- into the map's own table, and the gamepad clicks the map with A, never
-- the mouse this answers.
local function hookWorldMap()
	local map = WorldMapFrame
	if worldHooked or ns.GamepadUI() or not (map and map.AddCanvasClickHandler and map.GetNormalizedCursorPosition) then return worldHooked end
	map:AddCanvasClickHandler(onCanvasClick)
	worldHooked = true
	return true
end

local function hookMinimap()
	if minimapHooked or not (Minimap and Minimap.HookScript) then return end
	Minimap:HookScript("OnMouseUp", onMinimapUp)
	minimapHooked = true
end

ns.OnLogin(function()
	hookMinimap()
	ns.RegisterEvent("GLOBAL_MOUSE_DOWN", onGlobalMouseDown)
	if ns.Pins and ns.Pins.OnWorldClick then ns.Pins.OnWorldClick(onOwnPinClick) end
	ns.MapCanvas.OnAdd(function(map)
		added[#added + 1] = map
		-- Another addon's own map: its click handlers are no game table (the
		-- gamepad check stays as on the world map).
		if not ns.GamepadUI() and map.AddCanvasClickHandler and map.GetNormalizedCursorPosition then
			map:AddCanvasClickHandler(onCanvasClick)
		end
	end)
	if hookWorldMap() then return end
	local function onLoaded(_, name)
		if name == "Blizzard_WorldMap" and hookWorldMap() then ns.UnregisterEvent("ADDON_LOADED", onLoaded) end
	end
	ns.RegisterEvent("ADDON_LOADED", onLoaded)
end)

if ns.RegisterOptions then
	local ok, err = ns.RegisterOptions({
		page = L["Guide"], tab = L["Arrow & routes"], section = L["Routes"],
		controls = {
			Nav.HandoffOption({ kind = "toggle", key = "nav.mapPlan", label = L["Shift-click a map to go there"],
				help = L["Shift-click the world map or minimap and the arrow takes you there; Alt-click works over map icons. Click the spot again to clear it."] }),
			Nav.HandoffOption({ kind = "dropdown", key = "nav.routeStyle", label = L["Route style"],
				help = L["Fastest: the shortest walk, over hills and across fields. Balanced: roads that aren't much longer, and round hills. Roads: stays on roads even when they're longer; the safest way, not the quickest."],
				choices = { { value = "fastest", label = L["Fastest"] }, { value = "balanced", label = L["Balanced"] }, { value = "roads", label = L["Roads"] } } }),
		},
	})
	if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- The game's own user waypoint (nav.blizzardWaypoint, off by default):
-- C_Map.SetUserWaypoint plus C_SuperTrack, cleared only if we set it.
-- Slim build: TomTom and Waypoint UI mirroring are gone.

local ADDON, ns = ...
local Nav = ns.Nav

local Bridges = {}
Nav.bridges = Bridges

local blizzardSet = false
local wuiSet = false   -- a Waypoint UI pin of ours
local wuiLast         -- the pin last set: label, map, x, y (an unchanged target is not sent again)
local questSet         -- the quest we super-tracked

local FLAG = "Polestar"

-- Slim build: no Waypoint UI, no TomTom; only the game's own user waypoint.
local function waypointUI() return nil end

local function inLog(q)
	local C = ns.Compat
	if C and C.IsOnQuest then return C.IsOnQuest(q) end
	return C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(q) and true or false
end

local routeStop -- (below)
local function makePoint(map, x, y)
	if UiMapPoint and UiMapPoint.CreateFromCoordinates then
		return UiMapPoint.CreateFromCoordinates(map, x, y)
	end
	if CreateVector2D then return { uiMapID = map, position = CreateVector2D(x, y) } end
end

-- Clears what Polestar set through Waypoint UI or as a tracked quest, never the player's own.
local function clearWaypointUI(W)
	wuiLast = nil
	if wuiSet then
		wuiSet = false
		if W and W.IsUserNavigationFlagged(FLAG) then W.ClearUserNavigation() end
	end
	if questSet then
		local ST = C_SuperTrack
		if ST and ST.GetSuperTrackedQuestID and ST.SetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == questSet then
			ST.SetSuperTrackedQuestID(0)
		end
		questSet = nil
	end
end

-- A quest goal the game's own quest tracking points at: a turn-in, or an
-- objective at one spot. Not an accept (not in the log yet), nor an objective
-- over an area or among spawns (the game has no point to show inside it).
local function questTrackable(target)
	local q = tonumber(target.quest)
	if not q or target.kind == "accept" or not inLog(q) then return nil end
	if target.kind ~= "turnin" and (target.area or target.spots or target.search) then return nil end
	return q
end

-- A world point in live-frame map percent of `map`, when it lies on it.
local function onMap(map, c, wx, wy)
	local C = ns.Compat
	if not (map and C and C.WorldToMap) then return nil end
	local x, y = C.WorldToMap(c, wx, wy, map)
	if not (x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100) then return nil end
	return x, y
end

-- Where the arrow's current leg leads while a route is followed (a flight
-- master, a dock, a portal, a crossing: Travel.Stop), with the leg's label,
-- in live-frame map percent: on the point's own map, else the zone the
-- walking maps put it in, else the target's map. nil on the route's last
-- walk, with no route, or for a point on none of them.
function routeStop(target)
	local T = Nav.travel
	local p, label
	if T and T.Stop then p, label = T.Stop() end
	if not (p and p.c and p.wx and p.wy) then return nil end
	local x, y = onMap(p.map, p.c, p.wx, p.wy)
	if x then return label or "", p.map, x, y end
	local zone = T.ZoneOf and T.ZoneOf(p.map, p.c, p.wx, p.wy)
	x, y = onMap(zone, p.c, p.wx, p.wy)
	if x then return label or "", zone, x, y end
	x, y = onMap(target.map, p.c, p.wx, p.wy)
	if x then return label or "", target.map, x, y end
	return nil
end

-- With Waypoint UI: "quest" or "pin" when the target is shown through it.
-- On a route, the pin is the current leg's stop, so its beacon leads the way
-- the arrow does (the portal first, then the bank: #1741); the target itself
-- (its quest tracked, or its pin) once the last walk to it begins.
local function syncWaypointUI(W, target)
	local ST = C_SuperTrack
	local label, map, x, y = routeStop(target)
	local q = not label and questTrackable(target)
	if q and ST and ST.SetSuperTrackedQuestID then
		if wuiSet then
			wuiSet, wuiLast = false, nil
			if W.IsUserNavigationFlagged(FLAG) then W.ClearUserNavigation() end
		end
		-- Already the tracked quest: nothing to tell the game (or Waypoint UI) again.
		if not (questSet == q and ST.GetSuperTrackedQuestID and ST.GetSuperTrackedQuestID() == q) then
			ST.SetSuperTrackedQuestID(q)
		end
		questSet = q
		return "quest"
	end
	if not label then
		label = target.label
		map, x, y = Nav.LiveCoords(target)
	end
	if not map or (C_Map and C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map)) then return false end
	if questSet then clearWaypointUI(nil) end
	-- The same pin again (the target re-announced, an area's spot unchanged,
	-- the route planned again the same way): Waypoint UI is not asked to
	-- redraw it while it still holds ours.
	local L = wuiLast
	if wuiSet and L and L.label == label and L.map == map and math.abs(L.x - x) < 0.05 and math.abs(L.y - y) < 0.05
		and W.IsUserNavigationFlagged(FLAG) then
		return "pin"
	end
	W.NewUserNavigation({ name = label, mapID = map, x = x, y = y, flags = FLAG, suppressAudio = true })
	wuiSet, wuiLast = true, { label = label, map = map, x = x, y = y }
	return "pin"
end

local retrying = false

local function syncBlizzard(target)
	local on = ns.Get("nav.blizzardWaypoint") and target and not Nav.HandedOff() and not ns.ArrowHidden()
	local W = waypointUI()
	-- Waypoint UI loads after Polestar and fills its API late: look again once
	-- (the first target after login is set before it is ready).
	local C = ns.Compat
	local present = type(WaypointUIAPI) == "table" or (C and C.AddOnPresent and C.AddOnPresent("WaypointUI"))
	if on and not W and not retrying and present then
		retrying = true
		ns.After(2, function()
			retrying = false
			if waypointUI() then syncBlizzard(Nav.GetTarget()) end
		end)
	end
	-- Waypoint UI loaded: the tracked quest or a named pin, through it.
	local shown = on and W and syncWaypointUI(W, target)
	if shown then
		-- A named pin replaces a plain one of ours (Waypoint UI sets the game's
		-- pin itself); a tracked quest does not, so ours is cleared (a target
		-- set as a plain pin before Waypoint UI's API was ready).
		if blizzardSet and shown == "quest" and C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
		blizzardSet = false
		return
	end
	if wuiSet or questSet then clearWaypointUI(W) end
	-- Without Waypoint UI: the game's own pin, unnamed.
	if on and not W and C_Map and C_Map.SetUserWaypoint then
		local map, x, y = Nav.LiveCoords(target)
		if map and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(map)) then
			local point = makePoint(map, x / 100, y / 100)
			if point then
				C_Map.SetUserWaypoint(point)
				blizzardSet = true
				if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
					C_SuperTrack.SetSuperTrackedUserWaypoint(true)
				end
				return
			end
		end
	end
	if blizzardSet then
		blizzardSet = false
		if C_Map and C_Map.ClearUserWaypoint then C_Map.ClearUserWaypoint() end
	end
end

function Bridges:OnTarget(target)
	syncBlizzard(target)
end

-- Only the settings these bridges read trigger a resync, so dragging the
-- arrow or changing its scale never churns the waypoint.
local tracked = { worldPins = true, minimapPins = true, blizzardWaypoint = true }
local seen = {}

function Bridges:OnSettings()
	local changed = false
	for key in pairs(tracked) do
		local v = ns.Get("nav." .. key) and true or false
		if seen[key] ~= v then
			seen[key] = v
			changed = true
		end
	end
	if changed then self:OnTarget(Nav.GetTarget()) end
end

Nav.RegisterModule(Bridges)
ns.On("POLESTAR_HIDDEN", function() Bridges:OnTarget(Nav.GetTarget()) end)

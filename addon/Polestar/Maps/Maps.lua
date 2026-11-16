-- Polestar.Maps, slim build: the zone level ranges the travel planner reads
-- and the minimap button. No world map overlays.

local ADDON, ns = ...
local L = ns.L

local type, floor, format, pcall = type, math.floor, string.format, pcall

local Maps = {}
ns.Maps = Maps

ns.RegisterDefaults("maps", {
	-- A Polestar button on the minimap's edge: click hides or shows Polestar.
	minimapButton = true,
	minimapButtonAngle = 225, -- where on the edge, degrees (0 = east, counter-clockwise)
})

-- The 0.3.6 test builds saved the button off once for an account from
-- before (never with the gamepad interface), flagged by
-- PolestarDB.minimapButtonKept. 0.3.6 shows the button to everyone: an
-- account with that flag loses it and the off it saved, so the default, on,
-- applies again. Runs once; turning the button off later stores false again.
local function undoMinimapButtonKept()
	local db = ns.DB()
	if not db.minimapButtonKept then return end
	db.minimapButtonKept = nil
	if ns.GamepadUI() then return end
	local maps = type(db.settings) == "table" and db.settings.maps
	if type(maps) == "table" and maps.minimapButton == false then maps.minimapButton = nil end
end
ns.OnInit(undoMinimapButtonKept)

---------------------------------------------------------------------------
-- Zone level ranges (ZoneLevels.lua): the travel planner's danger weights
-- (Nav/Danger.lua) and the Engine read them.
---------------------------------------------------------------------------

local levels = {} -- uiMapID -> { min, max, labelX, labelY }

function Maps.RegisterZoneLevels(tbl)
	if type(tbl) ~= "table" then return end
	for id, v in pairs(tbl) do
		if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then levels[id] = v end
	end
end

-- min, max | nil
function Maps.GetZoneLevels(uiMapID)
	local v = uiMapID and levels[uiMapID]
	if not v then return nil end
	return v[1], v[2]
end

-- Every zone with a level range: for uiMapID, min, max in Maps.EachZoneLevels() do ... end
function Maps.EachZoneLevels()
	local id
	return function()
		local v
		id, v = next(levels, id)
		if id ~= nil then return id, v[1], v[2] end
	end
end

-- Palette name for a zone's range seen from `level`: red well under it,
-- amber just under, gold inside, green a little over, muted when trivial.
function Maps.LevelColor(min, max, level)
	if not (min and max and level) then return "textDim" end
	if level < min - 2 then return "danger" end
	if level < min then return "warning" end
	if level <= max then return "quest" end
	if level <= max + 5 then return "success" end
	return "textMuted"
end

-- "1-10" (en dash)
function Maps.FormatLevels(min, max)
	if min == max then return tostring(min) end
	return min .. "–" .. max
end

---------------------------------------------------------------------------
-- Options: the map features on the Map page (its sections are declared by
-- the options window, UI/Options.lua); the flight timer and the instance
-- tracker on the Quality of Life page (Travel and Trackers)
---------------------------------------------------------------------------

local MAP = L["Map"]

local function register(spec)
	if not ns.RegisterOptions then return end
	local ok, err = ns.RegisterOptions(spec)
	if not ok and err then ns.Debug(err) end
end

-- Coordinates and the minimap button, also on Quality of Life > Map: one
-- setting, a fresh control per page (the registry keeps per-control state).
local function minimapButton()
	return { kind = "toggle", key = "maps.minimapButton", label = L["Minimap button"], search = "minimap icon, minimap button, hide button, launcher",
		help = L["A Polestar button on the edge of the minimap. Click to hide or show Polestar, right-click for a menu, drag to move it."] }
end

register({ page = L["Quality of Life"], tab = L["Map"], section = L["Minimap"], controls = { minimapButton() } })

-- The options registry (slim build): the pages, tabs and sections of every
-- setting, declared here and filled by the modules (ns.RegisterOptions). The
-- game's own Settings panel draws them (UI/BlizzardSettings.lua); Polestar's
-- own options window is gone.
--
-- Built-in pages come first; other modules add theirs with
-- Polestar.RegisterOptions (docs/ARCHITECTURE.md, UI -> "Options
-- registry"), which may run before this file loads: the registry replays
-- every registration to us. A control whose settings key has no registered
-- default is left out rather than shown dead.
--
-- A Blizzard Settings category ("Polestar") opens this window.

local ADDON, ns = ...
local UI, Theme, W, Anim = ns.UI, ns.Theme, ns.Widgets, ns.Anim
local L = ns.L
local floor, max, min, ipairs, pairs, type = math.floor, math.max, math.min, ipairs, pairs, type


local O = {}
UI.Options = O

local pages, pageList = {}, {} -- name -> page; ordered list
local seq = 0

local function percent(v) return floor(v * 100 + 0.5) .. "%" end
-- "+20%" / "0%" / "-35%"
function O.Signed(v)
	local p = v < 0 and math.ceil(v * 100 - 0.5) or floor(v * 100 + 0.5)
	return (p > 0 and "+" or "") .. p .. "%"
end

-- The name of the colour scheme in use.
function O.SchemeLabel()
	local key = Theme.SchemeKey()
	for _, c in ipairs(Theme.SchemeChoices()) do
		if c.value == key then return c.text end
	end
	return key
end

-- A Hardcore character (C_GameRules): deathskips are off for good.
function O.Hardcore()
	local rules = C_GameRules
	return rules and rules.IsHardcoreActive and rules.IsHardcoreActive() and true or false
end

local function keyOf(name) return (name:lower():gsub("[^%w]+", "")) end

---------------------------------------------------------------------------
-- The page model: page -> tabs -> sections -> controls
---------------------------------------------------------------------------

-- Pages that close the list whatever registers after them: the author's
-- Recorder, then About.
local TAIL = { [L["Recorder"]] = 1, [L["About"]] = 2 }

-- key: the page's stable key (`/polestar options <key>`, O.Select), the
-- spec's own or else made from the name. Built-in pages give theirs, so a
-- translated title does not move them.
local function pageOf(name, icon, order, builtin, key)
	local p = pages[name]
	if not p then
		seq = seq + 1
		p = { name = name, key = keyOf(key or name), icon = icon or "gear", order = order or 100, builtin = builtin, seq = seq, tabs = {} }
		pages[name] = p
		pageList[#pageList + 1] = p
		-- By order (built-in pages first on a tie), Recorder and About last.
		table.sort(pageList, function(a, b)
			local ta, tb = TAIL[a.name] or 0, TAIL[b.name] or 0
			if ta ~= tb then return ta < tb end
			if a.order ~= b.order then return a.order < b.order end
			if (a.builtin and true or false) ~= (b.builtin and true or false) then return a.builtin and true or false end
			return a.seq < b.seq
		end)
	else
		if icon and not p.builtin then p.icon = icon end
	end
	return p
end

local function tabOf(p, name)
	name = name or ""
	for _, t in ipairs(p.tabs) do if t.name == name then return t end end
	local t = { name = name, sections = {} }
	p.tabs[#p.tabs + 1] = t
	return t
end

local function sectionOf(t, name)
	name = name or ""
	for _, s in ipairs(t.sections) do if s.name == name then return s end end
	local s = { name = name, controls = {} }
	t.sections[#t.sections + 1] = s
	return s
end

-- Slim build: a short options screen. Settings that only fine-tune a
-- feature, and the copies of settings that sat on two pages, stay at their
-- saved value (or default) and are not shown. Whole pages: Quality of Life
-- (it only repeated other pages' settings), Discovery's Characters and
-- Group quests tabs. Control keys here, or "label:<English label>" for
-- controls without a settings key.
local HIDDEN = {}
for _, k in ipairs({
	-- Guide window
	"ui.notesOpen", "ui.upcomingOpen", "ui.newInForever", "ui.lockHud", "ui.barsBottom",
	-- Dynamic Questing: the switch stays, its tuning goes
	"behavior.whileHereRadius", "behavior.whileHereTurnins", "behavior.whileHereTurninSeconds",
	"behavior.whileHereFlights", "behavior.whileHereSound", "behavior.whileHereStepKey",
	-- Arrow and routes
	"nav.detourCaption", "nav.routeStyle", "nav.nearbyMenu", "nav.journeySteps", "nav.blizzardWaypoint",
	"nav.alertBanner", "nav.alertSound", "nav.alertFlash", "label:Show a sample alert",
	-- Guides
	"behavior.warnClosing", "behavior.groupQuests", "behavior.lostQuests", "behavior.autoSelectGuide",
	"behavior.routeChoice", "behavior.offerClassQuests",
	-- Appearance
	"ui.classCardSound", "ui.menuScale", "nav.minimapIconSize",
	-- Map
	"nav.upcomingPins", "nav.trailDots", "qol.questLevelWindow", "qol.lowLevelQuests", "qol.objectiveSpots",
	"qol.objectiveAreaAlpha", "qol.minimapObjectives", "qol.questMarkerSize", "qol.guideHighlight", "qol.guideDim",
	-- Questing
	"qol.questDB", "qol.questSellWarning", "qol.nameplateIconSide", "qol.questTimerAlerts",
	"gear.pickTooltip", "gear.minUpgrade", "gear.useBags", "label:Manage custom weights",
	-- Buttons
	"qol.targetPlate", "qol.targetAnnounce", "qol.guideNameTarget", "qol.markTarget", "qol.pingTarget",
	"qol.markMob", "qol.markNpc", "qol.stepInteract", "qol.buttonTextSide",
	-- Discovery
	"lookup.altClick", "lookup.mounts", "dungeons.headsUp",
}) do HIDDEN[k] = true end
local HIDDEN_PAGES = { [L["Quality of Life"]] = true, [L["Discovery"]] = true }
-- Whole sections moved to another page: { page, tab, section } -> where they go.
-- Appearance and Map fold into Guide, so it holds the window, the arrow and the map.
local function moveKey(page, tab, section) return page .. "\1" .. (tab or "") .. "\1" .. (section or "") end
local SECTION_MOVES = {
	[moveKey(L["Appearance"], L["Windows"], L["Guide window"])] = { L["Guide"], L["Window"], L["Look"] },
	[moveKey(L["Appearance"], L["Windows"], L["Type & motion"])] = { L["Guide"], L["Window"], L["Look"] },
	[moveKey(L["Appearance"], L["Arrow"], L["Arrow"])] = { L["Guide"], L["Arrow & routes"], L["Arrow"] },
	[moveKey(L["Map"], L["Guide & quests"], L["Guide"])] = { L["Guide"], L["Map"], L["Guide"] },
	[moveKey(L["Map"], L["Guide & quests"], L["Quest markers"])] = { L["Guide"], L["Map"], L["Quest markers"] },
	[moveKey(L["Guide"], L["Window"], L["Combat"])] = { L["Guide"], L["Window"], L["Show and hide"] },
	[moveKey(L["Guide"], L["Window"], L["Dungeons and battlegrounds"])] = { L["Guide"], L["Window"], L["Show and hide"] },
	[moveKey(L["Guide"], L["Window"], L["Dynamic Questing"])] = { L["Guide"], L["Window"], L["What it shows"] },
	[moveKey(L["Guide"], L["Automation"], L["Quests"])] = { L["Guide"], L["Automation"], L["Guides"] },
	[moveKey(L["Questing"], L["Rewards & gear"], L["Quest rewards"])] = { L["Questing"], L["Rewards & gear"], L["Gear advice"] },
}
local HIDDEN_TABS = { [L["Characters"]] = true, [L["Group quests"]] = true }
-- Kept from Quality of Life, moved to the page where they belong.
local MOVED = {
	["qol.levelUpSpells"] = { L["Guide"], L["Automation"], L["Guides"] },
	["qol.oldRanks"] = { L["Guide"], L["Automation"], L["Guides"] },
	["qol.ridingReminder"] = { L["Guide"], L["Automation"], L["Guides"] },
	["qol.deathHelper"] = { L["Guide"], L["Arrow & routes"], L["Arrow"] },
	["qol.xpTracker"] = { L["Guide"], L["Window"], L["What it shows"] },
	["qol.xpTargetMark"] = { L["Guide"], L["Window"], L["What it shows"] },
	["qol.questXPOverlay"] = { L["Guide"], L["Window"], L["What it shows"] },
	["qol.flightHighlight"] = { L["Guide"], L["Arrow & routes"], L["Routes"] },
}
local function hiddenControl(c)
	if c.key and HIDDEN[c.key] then return true end
	local label = type(c.label) == "string" and c.label or nil
	if label then
		for k in pairs(HIDDEN) do
			if k:sub(1, 6) == "label:" and L[k:sub(7)] == label then return true end
		end
	end
	return false
end

local add
local function addSlim(spec, builtin)
	local controls, moved = {}, {}
	for _, c in ipairs(spec.controls or {}) do
		local to = c.key and MOVED[c.key]
		if to then
			moved[#moved + 1] = { to, c }
		elseif not hiddenControl(c) then
			controls[#controls + 1] = c
		end
	end
	for _, m in ipairs(moved) do
		add({ page = m[1][1], tab = m[1][2], section = m[1][3], controls = { m[2] } }, builtin)
	end
	if HIDDEN_PAGES[spec.page] or HIDDEN_TABS[spec.tab] then return end
	local copy = {}
	for k, v in pairs(spec) do copy[k] = v end
	copy.controls = controls
	local to = SECTION_MOVES[moveKey(spec.page, spec.tab, spec.section)]
	if to then
		copy.page, copy.tab, copy.section = to[1], to[2], to[3]
		copy.key, copy.icon, copy.order, copy.subtitle, copy.preview = nil, nil, nil, nil, nil
		if #controls == 0 then return end
	end
	add(copy, builtin)
end

function add(spec, builtin)
	local p = pageOf(spec.page, spec.icon, spec.order, builtin, spec.key)
	if spec.subtitle then p.subtitle = spec.subtitle end
	if spec.custom then p.custom = spec.custom end
	if spec.dot then p.dot = spec.dot end
	if spec.empty then p.empty = spec.empty end
	local tab = tabOf(p, spec.tab)
	-- preview(view) -> frame with :Layout(width) -> height: drawn over the
	-- tab's sections (Appearance's live preview).
	if spec.preview then tab.preview = spec.preview end
	local s = sectionOf(tab, spec.section)
	for _, c in ipairs(spec.controls or {}) do
		c.page, c.tab, c.section = p, spec.tab, spec.section
		s.controls[#s.controls + 1] = c
	end
end

---------------------------------------------------------------------------
-- Built-in pages
--
-- The pages follow what the player came to do, not which module owns a
-- setting: follow the guide (Guide), make Polestar look their way
-- (Appearance), choose what the maps show (Map), quest (Questing), find
-- things (Discovery: Lookup, the dungeon journal, rares, your characters), small
-- conveniences (Quality of Life), other addons Polestar works with
-- (Integrations); the author's Recorder and About close the
-- list. Modules still register their own controls; the pages they fill are
-- declared here with their tabs and sections in order, and the modules
-- register into them by name (docs/ARCHITECTURE.md, "Options registry").
---------------------------------------------------------------------------

local GUIDE, LOOK, MAP, QUESTING, DISCOVERY, QOL, REC, ABOUT =
	L["Guide"], L["Appearance"], L["Map"], L["Questing"], L["Discovery"], L["Quality of Life"], L["Recorder"], L["About"]

local function resetPositions()
	ns.Set("ui.pos", nil)
	if ns.Nav and ns.Nav.ResetArrowPosition then ns.Nav.ResetArrowPosition() end
end
O.ResetPositions = resetPositions

local function px(v) return string.format(L["%d px"], floor(v + 0.5)) end
-- Guidance options with no effect while Shortest Path Forever guides (Nav/Handoff.lua).
local function H(c)
	local N = ns.Nav
	return N and N.HandoffOption and N.HandoffOption(c) or c
end

-- A page's tabs and sections in their order, for modules to fill.
local function declare(page, key, icon, order, subtitle, tabs)
	local out = {}
	for _, t in ipairs(tabs) do
		for _, section in ipairs(t[2]) do
			out[#out + 1] = { page = page, key = key, icon = icon, order = order, subtitle = subtitle, tab = t[1], section = section, controls = {} }
		end
	end
	return out
end

-- Guide > Automation's trainer reminders, also on Quality of Life > Vendors >
-- Trainers: one setting, a fresh control per page (the registry keeps
-- per-control state).
local function trainReminder()
	return { kind = "dropdown", key = "behavior.trainReminder", label = L["Trainer reminders"], help = L["A note in the guide window, with the nearest trainer of your class, when new skills are waiting."],
		search = "train, trainer, new spells, skills, abilities, level up, class trainer",
		choices = { { value = "2", label = L["Every 2 levels"] }, { value = "1", label = L["Every level"] }, { value = "off", label = L["Off"] } } }
end

local BUILTIN = {
	-- Following the guide: the window, the arrow and routes, automation.
	{ page = GUIDE, key = "guide", icon = "window", order = 10, tab = L["Window"], section = L["What it shows"],
		subtitle = L["The guide window, the arrow and its routes, and what Polestar does for you."], controls = {
		{ kind = "toggle", key = "ui.shown", label = L["Show the window"], help = L["Also /polestar, or the key binding."], search = "show guide, hide guide, toggle window, open window" },
		{ kind = "toggle", key = "ui.compact", label = L["Compact mode"], help = L["Only the header and the current step's goals."], search = "minimal, small, smaller window, simple" },
		{ kind = "toggle", key = "ui.wholeStep", label = L["Show the whole step"],
			help = L["Every goal of the step at once, finished ones kept, instead of one person at a time with the others on one line each."] },
		{ kind = "slider", key = "ui.maxHeight", label = L["Maximum height"], min = 0.3, max = 0.9, step = 0.05, format = percent,
			help = L["How tall the window may grow, as a share of the screen. A longer step scrolls."] },
		{ kind = "toggle", key = "ui.showNotes", label = L["Step tips"], help = L["The author's tip under the goals, one line until clicked."] },
		{ kind = "toggle", key = "ui.notesOpen", label = L["Expand step tips"], help = L["Start each step with its tip in full instead of one line."],
			child = true, disabled = function() return not ns.Get("ui.showNotes") end },
		{ kind = "slider", key = "ui.upcoming", label = L["Upcoming steps"], min = 0, max = 6, step = 1, format = "%d", help = L["How many steps the Up next list holds; 0 turns it off."] },
		{ kind = "toggle", key = "ui.upcomingOpen", label = L["Expand Up next"], help = L["Start with the upcoming steps listed instead of collapsed."] },
		{ kind = "toggle", key = "ui.newInForever", label = L["Mark quests new in Forever"],
			help = L["A small infinity mark beside the name of a quest Forever added, in the guide, While you're here, the Codex and quest tooltips."],
			search = "new in forever, infinity, new quest, forever quest, mark, badge" },
		{ kind = "toggle", key = "update.card", label = L["Tell me when a newer Polestar is out"],
			help = L["At login, a card on the guide window says a newer Polestar is out and how to update; Got it keeps it away for a day. A line in the guide window stays until you update. Two or more updates behind, both show even with this off (the card at most once a day)."],
			search = "update, new version, outdated, old version, release, curseforge, polestar client, upgrade" },
	} },
	-- Core/Engine.lua, Dynamic Questing (Own.hereBuild): quick objectives of later steps close by, in the guide
	-- window's "While you're here" panel. The setting keys keep their behavior.whileHere* names.
	{ page = GUIDE, tab = L["Window"], section = L["Dynamic Questing"], controls = {
		{ kind = "toggle", key = "behavior.whileHere", label = L["Dynamic Questing"],
			help = L["Suggests objectives from later steps when you are near them, from your quest log and what is around you. They show under the step in a \"While you're here\" panel: click one to point the arrow there; right-click to dismiss it around here (dismissed twice, it stays away for the zone)."],
			search = "while you're here, nearby objective, grab it now, on the way, later step, opportunistic, detour" },
		{ kind = "slider", key = "behavior.whileHereRadius", label = L["How close"], min = 60, max = 400, step = 10,
			format = function(v) return ns.FormatDistance(v) end,
			help = L["How near the middle of its spawn area you must be for a suggestion to show. It goes again a little further out."],
			child = true, disabled = function() return not ns.Get("behavior.whileHere") end },
		{ kind = "toggle", key = "behavior.whileHereTurnins", label = L["Include nearby hand-ins"],
			help = L["Also a quest ready to hand in whose NPC is a little out of your way, when the guide hands it in later."],
			child = true, disabled = function() return not ns.Get("behavior.whileHere") end },
		{ kind = "slider", key = "behavior.whileHereTurninSeconds", label = L["Hand-ins: how far out of your way"], min = 0, max = 60, step = 5,
			format = function(v) return L["%d s"]:format(v) end,
			help = L["The seconds of extra walking a hand-in may cost, to its NPC and back on your way. One in the town you are in always shows; 0 keeps to those."],
			search = "hand in, turn in, detour, out of the way, seconds, nearby hand-ins",
			child = true, disabled = function() return not (ns.Get("behavior.whileHere") and ns.Get("behavior.whileHereTurnins")) end },
		{ kind = "toggle", key = "behavior.whileHereFlights", label = L["Flight paths you pass"],
			help = L["Also a friendly flight master near you whose flight path you haven't learned yet. Learning it ticks the guide's later step for it too."],
			search = "flight path, flight master, taxi, learn, discover, getfp",
			child = true, disabled = function() return not ns.Get("behavior.whileHere") end },
		{ kind = "toggle", key = "behavior.whileHereSound", label = L["Sound for a new suggestion"],
			help = L["A soft chime for each new suggestion (once when several come together), at the game's sound effects volume."],
			search = "chime, sound, audio, ding, alert",
			child = true, disabled = function() return not ns.Get("behavior.whileHere") end },
		{ kind = "toggle", key = "behavior.whileHereStepKey", label = L["Step key targets their mobs"],
			help = L["The step key also targets the mobs of the suggestions, nearest first, after the current step's own. It changes only out of combat."],
			search = "step key, target, targetexact, keybind, binding",
			child = true, disabled = function() return not ns.Get("behavior.whileHere") end },
	} },
	{ page = GUIDE, tab = L["Window"], section = L["Combat"], controls = {
		{ kind = "dropdown", key = "ui.combat", label = L["In combat"], help = L["What the window does while you fight."], search = "hide in combat, fade in combat, fighting",
			choices = { { value = "show", label = L["Keep visible"] }, { value = "fade", label = L["Fade out"] }, { value = "hide", label = L["Hide"] } } },
	} },
	{ page = GUIDE, tab = L["Window"], section = L["Dungeons and battlegrounds"], controls = {
		{ kind = "dropdown", key = "ui.instance", label = L["In dungeons and battlegrounds"],
			help = L["What the window, its buttons and alerts do in dungeons, raids, battlegrounds and arenas. Guide window in the minimap button's menu, the key binding or /polestar opens it there until you leave."],
			search = "dungeon, raid, battleground, arena, instance, hide, pvp, healer",
			choices = { { value = "show", label = L["Keep visible"] }, { value = "hide", label = L["Hide"] } } },
	} },
	-- Ways to show and hide Polestar without typing: the minimap
	-- button (Maps/MinimapButton.lua; also on Map and Quality of Life), next to the rules above. Hiding
	-- Polestar (Core/Init.lua) is per character: so is whether it keeps the arrow.
	{ page = GUIDE, tab = L["Window"], section = L["Show and hide"], controls = {
		{ kind = "toggle", key = "maps.minimapButton", label = L["Minimap button"],
			help = L["A Polestar button on the edge of the minimap. Click to hide or show Polestar, right-click for a menu, drag to move it."],
			search = "minimap icon, minimap button, hide button, launcher" },
		{ kind = "toggle", label = L["Keep the arrow when hidden"],
			help = L["Hiding Polestar leaves the arrow, its travel button and its arrival sound. This character only."],
			search = "hide polestar, hidden, arrow only, keep arrow, minimap button, hide all",
			get = function() return ns.HideKeepsArrow() end, set = function(on) ns.SetHideKeepsArrow(on) end },
	} },
	{ page = GUIDE, tab = L["Window"], section = L["Position"], controls = {
		{ kind = "toggle", key = "ui.locked", label = L["Lock window"], help = L["Prevents moving and resizing."], search = "lock, move, drag, resize, unlock" },
		{ kind = "toggle", key = "ui.lockHud", label = L["Lock arrow and buttons"],
			help = L["Stops stray drags on the arrow, the action buttons and the flight and instance timers. Shift-drag still moves them."] },
		{ kind = "toggle", key = "ui.growUp", label = L["Grow upward"], help = L["Keep the bottom edge in place, so longer steps extend the window up."] },
		{ kind = "toggle", key = "ui.barsBottom", label = L["Bar at the bottom"], help = L["With Grow upward, put the tabs and the step bar at the bottom edge, next to where the window is pinned."],
			child = true, disabled = function() return not ns.Get("ui.growUp") end },
		{ kind = "button", icon = "reset", button = L["Reset"], label = L["Reset position"], help = L["Put the guide window back in its corner."], onClick = function() ns.Set("ui.pos", nil) end },
	} },
	{ page = GUIDE, tab = L["Arrow & routes"], section = L["Arrow"], controls = {
		H({ kind = "toggle", key = "nav.arrow", label = L["Show arrow"], help = L["Points to the current goal. Its look and colours are under Appearance, Arrow."],
			search = "arrow, waypoint, pointer, direction, compass, navigation, hud" }),
		H({ kind = "toggle", key = "nav.hideArrowWithGuide", label = L["Hide the arrow with the guide"], help = L["When the guide window is hidden, hide the arrow too."],
			child = true, disabled = function() return not ns.Get("nav.arrow") end }),
		H({ kind = "toggle", key = "nav.arrowEta", label = L["Arrival time"], help = L["Estimated time under the distance."], search = "eta, time left, travel time" }),
		{ kind = "dropdown", key = "nav.distanceUnit", label = L["Distances"], help = L["How the arrow, map tooltips, rares and the death helper show distances."], search = "units, yards, metres, metric, distance",
			choices = { { value = "yards", label = L["Yards (the game's unit)"] }, { value = "metres", label = L["Metres"] } } },
		H({ kind = "toggle", key = "nav.arrivalSound", label = L["Arrival sound"], help = L["A soft chime when you reach a waypoint."], search = "sound, chime, audio, ding" }),
		H({ kind = "button", icon = "reset", button = L["Reset"], label = L["Reset arrow position"], help = L["Back to the top of the screen. Drag the arrow to move it."],
			onClick = function() if ns.Nav and ns.Nav.ResetArrowPosition then ns.Nav.ResetArrowPosition() end end,
			needs = function() return ns.Nav and ns.Nav.ResetArrowPosition end }),
	} },
	{ page = GUIDE, tab = L["Arrow & routes"], section = L["Routes"], controls = {
		H({ kind = "toggle", key = "nav.travel", label = L["Plan travel routes"], help = L["Flights, boats and your hearthstone when they are faster. Off: the arrow points straight at the goal."],
			search = "flight, taxi, flight path, boat, zeppelin, hearth, hearthstone, route planning, fastest way, fps, frame rate, performance, lag, stutter, cpu, slow" }),
		H({ kind = "toggle", key = "nav.teleports", label = L["Class teleports"], help = L["Routes may start with a Teleport spell you know (a mage's city teleports, a druid's Moonglade) when it is faster. A city teleport needs a Rune of Teleportation in your bags."],
			search = "teleport, portal, mage, druid, moonglade",
			child = true, disabled = function() return not ns.Get("nav.travel") end }),
		H({ kind = "toggle", key = "nav.detourCaption", label = L["Detour captions"], help = L["Under a walk in the journey, say when it goes round a town of the other faction: \"Detour around Southshore\". It only says so: the route and the arrow stay as they are."],
			search = "detour, enemy town, hostile town, avoid, go round, journey",
			child = true, disabled = function() return not ns.Get("nav.travel") end }),
		H({ kind = "toggle", key = "nav.navRouting", label = L["Walk real paths"], help = L["The arrow follows paths on the ground around cliffs, water and walls, on Polestar's walking maps, with Shortest Path Forever's router by Cillian Berragan. Off: it points straight at each stop."],
			search = "pathfinding, pathing, router, walking, avoid cliffs, mountains, fps, frame rate, performance, lag, stutter, cpu, slow" }),
	} },
	{ page = GUIDE, tab = L["Arrow & routes"], section = L["Other waypoints"], controls = {
		H({ kind = "toggle", key = "nav.blizzardWaypoint", label = L["Blizzard waypoint"], help = L["Also set the game's own map pin and tracking."], search = "map pin, waypoint, user waypoint, supertrack" }),
	} },
	{ page = GUIDE, tab = L["Automation"], section = L["Quests"], controls = {
		{ kind = "toggle", key = "behavior.warnClosing", label = L["Warn about missable quests"], help = L["Before you take a quest that closes another for good, says which in chat and leaves the accept to you."],
			search = "missable, exclusive quests, breadcrumb, warning" },
		{ kind = "toggle", key = "behavior.skipGrey", label = L["Skip grey quests"], help = L["Leaves out grey quests and their turn-ins, unless a later quest needs them first."],
			search = "gray quests, low level quests, trivial, skip easy quests" },
		-- The answer at a group quest (`when group`) not answered one by one
		-- (Discovery > Group quests): ask at each, or do or skip them all.
		{ kind = "dropdown", key = "behavior.groupQuests", label = L["Group quests"],
			help = L["Elite and escort quests the guides mark for a group. Ask at each, or answer them all: with a group (a party levelling together) or skip them (solo). Discovery, Group quests changes one."],
			choices = { { value = "ask", label = L["Ask me at each"] }, { value = "do", label = L["Do them with a group"] }, { value = "skip", label = L["Skip them"] } },
			needs = function() local E = ns.Engine; return E and E.GroupQuests and #E.GroupQuests() > 0 end },
		-- A quest the route had passed that leaves the log (Engine Own.holdLost,
		-- #1365): the guide window asks, or the answer is always the same.
		{ kind = "dropdown", key = "behavior.lostQuests", label = L["When you abandon a guide quest"],
			help = L["Ask me: the guide stays on its step, leads you back to the quest giver, and the guide window asks. Or always go back for the quest, or always skip it and the quests that follow from it; chat says which."],
			choices = { { value = "ask", label = L["Ask me"] }, { value = "back", label = L["Always go back for it"] }, { value = "skip", label = L["Always skip it"] } },
			search = "abandon, abandoned quest, dropped quest, failed quest, quest log, go back, skip" },
	} },
	{ page = GUIDE, tab = L["Automation"], section = L["Guides"], controls = {
		{ kind = "toggle", key = "behavior.autoSelectGuide", label = L["Pick a guide for me"], help = L["Opens the suggested guide when no tab is open."], search = "auto guide, choose guide, suggested guide" },
		{ kind = "dropdown", key = "behavior.guideEnd", label = L["When a leveling guide ends"], help = L["Ask me: a window says the guide is done and offers the next one. Continue automatically: the next guide loads in the same tab."],
			choices = { { value = "ask", label = L["Ask me"] }, { value = "continue", label = L["Continue automatically"] } } },
		{ kind = "dropdown", key = "behavior.routeChoice", label = L["Where to level next"], help = L["Where a guide offers more than one zone to continue in (/polestar path)."],
			choices = { { value = "ask", label = L["Let me choose"] }, { value = "recommended", label = L["Take the recommended zone"] } } },
		-- `die` steps (Core/Engine.lua, Own.deathskips): the player's choice, never in Hardcore.
		{ kind = "toggle", key = "behavior.deathskips", label = L["Use deathskips"], search = "death skip, die on purpose, corpse run, spirit healer",
			help = L["Where dying on purpose and taking the Spirit Healer's resurrection gets you there sooner, the guide shows a step for it. It costs durability and, from level 11, resurrection sickness. Always off on Hardcore characters."],
			get = function() return ns.Get("behavior.deathskips") and not O.Hardcore() end,
			disabled = function() return O.Hardcore() end },
		trainReminder(),
		{ kind = "toggle", key = "behavior.offerClassQuests", label = L["Offer class quests"],
			help = L["When one of your class's Class guides opens (your level, its first quest), the guide window offers to open it in a tab."] },
		{ kind = "button", icon = "reset", button = L["Reset"], danger = true, label = L["Reset guide progress"], help = L["Manual check-offs and skips, current guide, from your last quest progress on."], confirm = true,
			confirmTitle = L["Reset guide progress?"], confirmAction = L["Reset progress"],
			confirmText = function()
				local g = ns.Engine and ns.Engine.GetGuide and ns.Engine.GetGuide()
				local name = g and (g.title or g.id)
				if name then return string.format(L["Your manual check-offs and skipped steps in %s are cleared from your last quest progress on. Quests you have done stay done, and the guide stays where they put you."], name) end
				return L["Your manual check-offs and skipped steps in the current guide are cleared from your last quest progress on. Quests you have done stay done, and the guide stays where they put you."]
			end,
			onClick = function() if ns.Engine and ns.Engine.ResetProgress then ns.Engine.ResetProgress() end end,
			needs = function() return ns.Engine and ns.Engine.ResetProgress end },
	} },

	-- How everything looks: colour and type, the windows' frames and the
	-- guide window's own look, the arrow. Every change repaints live, the
	-- preview over Colour & type with it. The accent's sources sit together
	-- in their own section.
	{ page = LOOK, key = "appearance", icon = "palette", order = 20, tab = L["Windows"], section = L["Type & motion"],
		subtitle = L["The windows and the arrow, in the game's own look. Right-click a setting to reset it."], controls = {
		{ kind = "toggle", key = "ui.reduceMotion", label = L["Reduce motion"], help = L["No sliding or popping; fades stay short."],
			search = "animations, motion sickness, fps, frame rate, performance, lag, stutter, cpu, slow" },
		{ kind = "toggle", key = "ui.classCardSound", label = L["Class quest chime"],
			disabled = function() return not (UI.ClassCard and UI.ClassCard.GameSoundOn()) end,
			help = L["A short chime the first time a class quest chain's card shows. Off while the game's sound effects are off."] },
	} },
	{ page = LOOK, tab = L["Windows"], section = L["Guide window"], controls = {
		{ kind = "dropdown", key = "ui.style", label = L["Style"], help = L["Transparent drops every background and border; text is outlined and the controls appear when you hover the window."],
			search = "transparent, transparency, see through, background, clear",
			choices = { { value = "standard", label = L["Standard"] }, { value = "transparent", label = L["Transparent"] } } },
		{ kind = "dropdown", key = "ui.backing", label = L["Backing"], child = true, disabled = function() return ns.Get("ui.style") ~= "transparent" end,
			help = L["With Transparent: Soft lays a light shade behind each line of text, Dark a dark backing behind the whole window. Off: the outlined text alone on the world."],
			search = "transparent, background, shade, dark, readable, contrast",
			choices = { { value = "soft", label = L["Soft"] }, { value = "dark", label = L["Dark"] }, { value = "none", label = L["Off"] } } },
		{ kind = "toggle", key = "ui.barShown", label = L["Keep the bar shown"], child = true, disabled = function() return ns.Get("ui.style") ~= "transparent" end,
			help = L["With Transparent, the tabs and the step bar stay on screen instead of only under the cursor."],
			search = "transparent, bar, header, readable, always, show" },
		{ kind = "slider", key = "ui.scale", label = L["Window scale"], min = 0.6, max = 1.6, step = 0.05, format = percent, search = "size, bigger, smaller, zoom" },
		{ kind = "slider", key = "ui.guideTextSize", label = L["Text size"], min = 0.8, max = 1.4, step = 0.05, format = percent,
			help = L["The size of the guide window's text, apart from its scale."],
			search = "text size, font size, bigger text, smaller text, readability, larger, guide text" },
		{ kind = "slider", key = "ui.width", label = L["Width"], min = 260, max = 560, step = 10, format = "%d", search = "wide, wider, size" },
		{ kind = "slider", key = "ui.opacity", label = L["Window opacity"], min = 0.3, max = 1, step = 0.05, format = percent, search = "transparency, alpha, see through",
			help = L["The whole guide window, text included."] },
	} },
	{ page = LOOK, tab = L["Windows"], section = L["Menus"], controls = {
		{ kind = "slider", key = "ui.menuScale", label = L["Menu scale"], min = 0.7, max = 1.4, step = 0.05, format = percent, release = true,
			help = L["The guide menu and this window; applies when you let go. Right-click to reset."] },
	} },
	{ page = LOOK, tab = L["Arrow"], section = L["Arrow"], controls = {
		H({ kind = "slider", key = "nav.arrowScale", label = L["Arrow scale"], min = 0.5, max = 2, step = 0.05, format = percent, search = "arrow size, bigger arrow, smaller arrow" }),
		H({ kind = "slider", key = "nav.arrowAlpha", label = L["Arrow opacity"], min = 0.2, max = 1, step = 0.05, format = percent, search = "arrow transparency, alpha" }),
	} },
	{ page = LOOK, tab = L["Arrow"], section = L["Map icons"], controls = {
		{ kind = "slider", key = "nav.minimapIconSize", label = L["Minimap icon size"], min = 0.5, max = 1.5, step = 0.05, format = percent,
			help = L["Polestar's marks on the minimap; the world map keeps its own. A mark over your arrow fades so the arrow shows through it. Right-click to reset."] },
	} },

	-- Everything Polestar draws on the world map and the minimap, in one
	-- place. The sections are declared here, in this order; the Quests,
	-- Rares and Maps modules register their controls into them by name.
	{ page = MAP, key = "map", icon = "icon-explore", order = 30, tab = L["Guide & quests"], section = L["Guide"],
		subtitle = L["What Polestar draws on the world map and the minimap. Quest, rare and travel icons start off."], controls = {
		{ kind = "toggle", key = "nav.worldPins", label = L["Guide pins on the world map"], search = "map pins, icons, markers, waypoint, world map",
			help = L["The arrow's target, the stops of its travel route, the step's other goals, the areas their mobs and objects spawn in, and the route lines."] },
		{ kind = "toggle", key = "nav.minimapPins", label = L["Guide pin on the minimap"], help = L["The arrow's target, the areas it spawns in, and the route line."], search = "map pins, icons, markers, waypoint, minimap" },
		{ kind = "toggle", key = "nav.upcomingPins", label = L["Numbered pins for the steps ahead"],
			help = L["A small pin with its step number where each of the next steps takes you, fainter the further ahead. As many as Up next shows, else five."] },
		H({ kind = "toggle", key = "nav.trailDots", label = L["Trail dots along the travel route"],
			help = L["Moving dots from you to the target on the world map and the minimap, along the travel route, while route lines are off."] }),
	} },
	{ page = MAP, tab = L["Guide & quests"], section = L["Quest markers"], controls = {} },
}

-- Pages filled by modules alone: Quests, QoL, Gear and Talents on Questing; Lookup,
-- Dungeons, Rares and Characters on Discovery; QoL and Maps on Quality of Life.
for _, list in ipairs({
	declare(QUESTING, "questing", "icon-accept", 40, L["Quest information, rewards and gear advice, and the quest buttons."], {
		{ L["Quests"], { L["Quest database"], L["Tooltips and quest log"] } },
		{ L["Rewards & gear"], { L["Quest rewards"], L["Gear advice"], L["Comparison"] } },
		{ L["Buttons"], { L["Action buttons"] } },
	}),
	declare(DISCOVERY, "discovery", "search", 50, L["Lookup, the dungeon journal and rares: finding things in the world."], {
		{ L["Lookup"], { L["How to get anything"] } },
		{ L["Dungeons"], { ENCOUNTER_JOURNAL, L["Dungeons in leveling guides"] } },
	}),
}) do
	for _, spec in ipairs(list) do BUILTIN[#BUILTIN + 1] = spec end
end

for _, spec in ipairs(BUILTIN) do addSlim(spec, true) end

---------------------------------------------------------------------------
-- Reading the registry
---------------------------------------------------------------------------

local function available(c)
	if c.needs and not c.needs() then return false end
	if c.kind == "button" then return true end
	if c.kind == "binding" or c.kind == "color" then return false end
	-- A toggle or slider with get/set and no key holds state that is no setting (per character).
	if (c.kind == "toggle" or c.kind == "slider") and not c.key and c.get and c.set then return true end
	return ns.GetDefault and ns.GetDefault(c.key) ~= nil
end

local function tabHasControls(t)
	for _, s in ipairs(t.sections) do
		for _, c in ipairs(s.controls) do
			if available(c) then return true end
		end
	end
	return false
end

local function shownTabs(p)
	local out = {}
	for _, t in ipairs(p.tabs) do
		if tabHasControls(t) then out[#out + 1] = t end
	end
	return out
end

local function pageShown(p)
	for _, t in ipairs(p.tabs) do
		if tabHasControls(t) then return true end
	end
	return false
end

-- The sections in order with their control tables (only those available),
-- for the game's Settings panel (UI/BlizzardSettings.lua).
function O.Sections()
	local out = {}
	for _, p in ipairs(pageList) do
		if pageShown(p) then
			for _, t in ipairs(shownTabs(p)) do
				for _, sec in ipairs(t.sections) do
					local list = {}
					for _, c in ipairs(sec.controls) do
						if available(c) then list[#list + 1] = c end
					end
					if #list > 0 then out[#out + 1] = { page = p.key, pageName = p.name, tab = t.name, section = sec.name, controls = list } end
				end
			end
		end
	end
	return out
end

-- Every shown control, page > tab > section, for tests and tooling.
function O.Layout()
	local out = {}
	for _, s in ipairs(O.Sections()) do
		local keys = {}
		for _, c in ipairs(s.controls) do keys[#keys + 1] = c.key or (c.kind .. ":" .. tostring(c.label)) end
		out[#out + 1] = { page = s.page, tab = s.tab, section = s.section, keys = keys }
	end
	return out
end

-- The pages and tabs, in order.
function O.Pages()
	local out = {}
	for _, p in ipairs(pageList) do
		if pageShown(p) then
			local tabs = {}
			for j, t in ipairs(shownTabs(p)) do tabs[j] = t.name end
			out[#out + 1] = { name = p.name, key = p.key, builtin = p.builtin and true or false, tabs = tabs }
		end
	end
	return out
end

-- Every module's registrations, now and later.
W.OnOptionsRegistered(function(spec) addSlim(spec, false) end)

-- Settings open in the game's panel; with no panel (or before it is built),
-- a line in chat.
function UI.ShowOptions()
	local BS = UI.BlizzardSettings
	if BS and BS.Open and BS.Open() then return end
	ns.Print(L["Open Polestar settings"] .. ": Esc > " .. (SETTINGS or "Options") .. " > " .. (ADDONS or "AddOns"))
end

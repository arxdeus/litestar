-- Slim build: every window Polestar drew for itself is gone; what the player
-- still needs from them goes through the game's own UI:
--
--   * Choosing a guide (UI.ShowPicker, SHOW_PICKER, /polestar guides): the
--     game's context menu (MenuUtil) at the cursor: suggested guides first,
--     the open tabs, then every guide this character can follow grouped by
--     folder as submenus. A click loads it (Shift: in a new tab).
--   * Route choice (ROUTE_CHOICE, /polestar path): the same menu with the
--     zones the guide offers; the recommended one marked.
--   * A guide's end (GUIDE_END): the game's dialog (StaticPopup) with Start
--     next / Later.
--   * Text to copy (UI.ShowCopy, SHOW_COPY): the game's dialog with an edit
--     box, selected.
--   * The quests the route never hands in (SHOW_QUEST_ROOM): a chat list; the
--     game's quest log abandons them.
--   * Lookup and the dungeon journal (SHOW_LOOKUP, SHOW_DUNGEON): a line in
--     chat; their data still feeds the guides.

local ADDON, ns = ...
local UI = ns.UI
local L = ns.L
local W = ns.Widgets
local ipairs, pairs, type, format, concat = ipairs, pairs, type, string.format, table.concat

local function Engine() return ns.Engine end
local function inCombat() return InCombatLockdown and InCombatLockdown() or false end

local function guideLabel(g)
	return (UI.GuideLabel and UI.GuideLabel(g)) or g.title or g.id
end

---------------------------------------------------------------------------
-- Choosing a guide
---------------------------------------------------------------------------

local function load(id, newTab)
	local E = Engine()
	if not (E and id) then return end
	if newTab and E.OpenTab then
		if not E.OpenTab(id) then ns.Print(L["Six tabs is the limit. Close one to open another."]) return end
	elseif E.SetGuide then
		E.SetGuide(id)
	end
	ns.Set("ui.shown", true)
end

-- The guides this character can follow, by folder, in the guide menu's order.
local function folders()
	local G, C = ns.Guides, ns.Compat
	local player = C and C.GetPlayerInfo and C.GetPlayerInfo()
	local out, byName = {}, {}
	for _, g in ipairs(G and G.List and G.List() or {}) do
		local ok = not (player and G.GuideMatches) or G.GuideMatches(g, player)
		if ok then
			local cat = g.category or "Leveling"
			local name
			if type(g.folder) == "string" and g.folder ~= "" then
				name = g.folder
			elseif cat == "Leveling" then
				local lv = g.minLevel or 1
				local lo = lv < 30 and 1 or (math.floor(lv / 10) * 10)
				local hi = lv < 30 and 30 or lo + 10
				name = L["Leveling"] .. " " .. ((UI.LevelRange and UI.LevelRange(lo, hi)) or (lo .. "-" .. hi))
			else
				name = L[cat] or cat
			end
			local f = byName[name]
			if not f then
				f = { name = name, guides = {}, first = g.minLevel or 0, cat = cat }
				byName[name] = f
				out[#out + 1] = f
			end
			f.guides[#f.guides + 1] = g
		end
	end
	table.sort(out, function(a, b)
		if (a.cat == "Leveling") ~= (b.cat == "Leveling") then return a.cat == "Leveling" end
		if a.first ~= b.first then return a.first < b.first end
		return a.name < b.name
	end)
	for _, f in ipairs(out) do
		table.sort(f.guides, function(a, b)
			if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
			return (a.title or a.id) < (b.title or b.id)
		end)
	end
	return out
end

local function newTabWanted(opts)
	return (opts and opts.newTab) or (IsShiftKeyDown and IsShiftKeyDown()) or false
end

function UI.ShowPicker(opts)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns.Print(L["Choose a guide"] .. ": /polestar guides")
		return
	end
	local G, E = ns.Guides, Engine()
	local current = E and E.GetGuide and E.GetGuide()
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle(L["Choose guide"])
		local seen = {}
		local sugg = G and G.Suggestions and G.Suggestions() or {}
		if #sugg > 0 then
			root:CreateTitle(L["Suggested for you"])
			for i = 1, math.min(#sugg, 5) do
				local g = G.Get(sugg[i])
				if g then
					seen[g.id] = true
					root:CreateRadio(guideLabel(g), function() return current and current.id == g.id end, function() load(g.id, newTabWanted(opts)) end)
				end
			end
			root:CreateDivider()
		end
		for _, f in ipairs(folders()) do
			local sub = root:CreateButton(f.name .. " (" .. #f.guides .. ")")
			for _, g in ipairs(f.guides) do
				sub:CreateRadio(guideLabel(g), function() return current and current.id == g.id end, function() load(g.id, newTabWanted(opts)) end)
			end
		end
		root:CreateDivider()
		root:CreateButton(L["Options"], function() if UI.ShowOptions then UI.ShowOptions() end end)
	end)
end

---------------------------------------------------------------------------
-- Route choice
---------------------------------------------------------------------------

local RC = {}
UI.RouteChoice = RC
local waiting

function RC.Show(id)
	local E = Engine()
	local choice = id and E and E.GetRouteChoice and E.GetRouteChoice(id)
	if not choice or #choice.options < 2 then return false end
	if inCombat() or not (MenuUtil and MenuUtil.CreateContextMenu) then
		waiting = id
		return true
	end
	waiting = nil
	MenuUtil.CreateContextMenu(UIParent, function(_, root)
		root:CreateTitle(L["Where to level next"])
		for _, o in ipairs(choice.options) do
			local name = o.zoneName or o.title or o.id
			if o.recommended then name = name .. " (" .. L["Recommended"] .. ")" end
			if o.open then name = name .. " (" .. L["Keep this route"] .. ")" end
			root:CreateButton(name, function()
				if E.ChooseRoute then E.ChooseRoute(id, o.id) end
				ns.Set("ui.shown", true)
			end)
		end
	end)
	return true
end
function RC.Hide() waiting = nil end
function RC.IsShown() return false end
UI.ShowRouteChoice = function(id) return RC.Show(id) end

ns.On("ROUTE_CHOICE", function(id)
	if ns.IsLoggedIn() then RC.Show(id) else waiting = id end
end)

---------------------------------------------------------------------------
-- A guide's end
---------------------------------------------------------------------------

local GE = {}
UI.GuideEnd = GE
local endWaiting

function GE.Show(info)
	local G, E = ns.Guides, Engine()
	local g = info and info.guideId and G and G.Get(info.guideId)
	if not g then return false end
	if inCombat() or not ns.IsLoggedIn() then endWaiting = info return true end
	endWaiting = nil
	local choice = info.choose and E and E.GetRouteChoice and E.GetRouteChoice(g.id)
	local nextGuide = not (choice and #choice.options >= 2) and info.next and G.Get(info.next) or nil
	local text = format(L["You reached the end of %s."], guideLabel(g))
	local action
	if choice and #choice.options >= 2 then
		action = L["Where to level next"]
	elseif nextGuide then
		text = text .. "\n\n" .. L["Next"] .. ": " .. guideLabel(nextGuide)
		action = L["Start"]
	else
		action = L["Choose guide"]
	end
	W.Modal({ title = "", text = text, action = action, cancel = L["Later"], onAccept = function()
		if choice and #choice.options >= 2 then
			RC.Show(g.id)
		elseif nextGuide then
			if E and E.StartNext then E.StartNext(g.id) end
		else
			UI.ShowPicker()
		end
		ns.Set("ui.shown", true)
	end })
	return true
end
function GE.Hide() endWaiting = nil end
function GE.IsShown() return false end
function GE.Model(info)
	local G = ns.Guides
	local g = info and info.guideId and G and G.Get(info.guideId)
	return g and { id = g.id } or nil
end

ns.On("GUIDE_END", function(_, info) GE.Show(info) end)

ns.OnLogin(function()
	if waiting then RC.Show(waiting) end
	if endWaiting then GE.Show(endWaiting) end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if waiting then RC.Show(waiting) end
	if endWaiting then GE.Show(endWaiting) end
end)

---------------------------------------------------------------------------
-- Text to copy
---------------------------------------------------------------------------

local COPY = "LITESTAR_COPY"
function UI.ShowCopy(title, text)
	if not (StaticPopupDialogs and StaticPopup_Show) then
		ns.Print((title or "") .. ": " .. (text or ""))
		return
	end
	StaticPopupDialogs[COPY] = {
		text = (title and title ~= "" and (title .. "\n\n") or "") .. L["Selected for you: copy it with Ctrl+C (Cmd+C on a Mac), then press Escape."],
		button1 = CLOSE or L["Close"],
		hasEditBox = true, editBoxWidth = 320,
		OnShow = function(self)
			local box = self.editBox or self.EditBox
			if box then box:SetText(text or ""); box:HighlightText(); box:SetFocus() end
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopup_Show(COPY)
end
ns.On("SHOW_COPY", function(title, text) UI.ShowCopy(title, text) end)

---------------------------------------------------------------------------
-- Quests the route never hands in
---------------------------------------------------------------------------

function UI.ShowQuestRoom()
	local RP = ns.RoutePlan
	local list = RP and RP.Unneeded and RP.Unneeded()
	if list == nil then
		ns.Print(L["The route ahead isn't settled yet (a guide to choose or load), so it can't say which quests it leaves behind."])
	elseif #list == 0 then
		ns.Print(L["The route hands in every quest in your log."])
	else
		ns.Print(L["The route doesn't need these: it never hands them in, or they give no XP any more. Abandon asks in the game's own window first."])
		for _, u in ipairs(list) do ns.Print("  " .. (u.title or ("#" .. u.quest))) end
	end
end
function UI.LayoutQuestRoom() end
ns.On("SHOW_QUEST_ROOM", function() UI.ShowQuestRoom() end)

---------------------------------------------------------------------------
-- Lookup and the dungeon journal: their windows are gone
---------------------------------------------------------------------------

function UI.ShowLookup() ns.Print(L["Lookup"] .. ": " .. L["Off"]) end
ns.On("SHOW_LOOKUP", function() UI.ShowLookup() end)
ns.On("SHOW_DUNGEON", function() end)

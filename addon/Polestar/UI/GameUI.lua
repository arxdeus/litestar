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
--   * The quests the route never hands in (SHOW_QUEST_ROOM): the game's
--     context menu; a click abandons through the game's own confirmation.
--   * Importing a guide (SHOW_IMPORT, /polestar import): the game's dialog
--     with an edit box, then a preview dialog before anything is saved.
--   * Community guides (/polestar packs): the game's context menu: each
--     pack's switch, the imported guides with Delete, suggestions' source.
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

local function packTitle(r)
	if r.official then return L["Polestar"] end
	return r.title or r.id
end

-- The guide menu: the game's context menu, from the guide window's button
-- (opts.anchor) or at the cursor. Suggested guides, then the open tabs, then
-- every guide this character can follow by folder, then each community
-- pack's guides, then Import and Community guides.
function UI.ShowPicker(opts)
	opts = opts or {}
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		ns.Print(L["Choose a guide"] .. ": /polestar guides")
		return
	end
	local G, E = ns.Guides, Engine()
	local current = E and E.GetGuide and E.GetGuide()
	local function radio(parent, g)
		parent:CreateRadio(guideLabel(g), function() return current and current.id == g.id end, function() load(g.id, newTabWanted(opts)) end)
	end
	MenuUtil.CreateContextMenu(opts.anchor or UIParent, function(_, root)
		W.MenuTitle(root, newTabWanted(opts) and L["Open in new tab"] or L["Choose guide"])
		local sugg = G and G.Suggestions and G.Suggestions() or {}
		if #sugg > 0 then
			W.MenuTitle(root, L["Suggested for you"])
			for i = 1, math.min(#sugg, 5) do
				local g = G.Get(sugg[i])
				if g then radio(root, g) end
			end
			W.MenuDivider(root)
		end
		-- Polestar's own guides by folder; a community pack's under its title.
		local byPack = {}
		for _, f in ipairs(folders()) do
			for _, g in ipairs(f.guides) do
				local pack = g.pack or "guides"
				local list = byPack[pack]
				if not list then list = { folders = {}, index = {} }; byPack[pack] = list end
				local sub = list.index[f.name]
				if not sub then sub = { name = f.name, guides = {} }; list.index[f.name] = sub; list.folders[#list.folders + 1] = sub end
				sub.guides[#sub.guides + 1] = g
			end
		end
		local own = byPack.guides
		for _, f in ipairs(own and own.folders or {}) do
			local sub = root:CreateButton(f.name .. " (" .. #f.guides .. ")")
			for _, g in ipairs(f.guides) do radio(sub, g) end
		end
		local others = {}
		for pack, list in pairs(byPack) do if pack ~= "guides" then others[#others + 1] = pack end end
		table.sort(others)
		if #others > 0 then
			W.MenuDivider(root)
			for _, pack in ipairs(others) do
				local r = G.Pack and G.Pack(pack)
				local title = pack == "imported" and L["Imported guides"] or (r and packTitle(r)) or pack
				local sub = root:CreateButton(title)
				for _, f in ipairs(byPack[pack].folders) do
					if #byPack[pack].folders > 1 then
						local inner = sub:CreateButton(f.name .. " (" .. #f.guides .. ")")
						for _, g in ipairs(f.guides) do radio(inner, g) end
					else
						for _, g in ipairs(f.guides) do radio(sub, g) end
					end
				end
			end
		end
		W.MenuDivider(root)
		root:CreateButton(L["Import a guide"], function() UI.ShowImport() end)
		root:CreateButton(L["Community guides"], function() UI.ShowPacks() end)
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
		W.MenuTitle(root, L["Where to level next"])
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

-- The game's context menu: each quest the route does not need, a click
-- abandons it through the game's own confirmation (Compat.AskAbandonQuest).
local WHY = {}
function UI.ShowQuestRoom(anchor)
	local RP = ns.RoutePlan
	local list = RP and RP.Unneeded and RP.Unneeded()
	if list == nil then
		ns.Print(L["The route ahead isn't settled yet (a guide to choose or load), so it can't say which quests it leaves behind."])
		return
	elseif #list == 0 then
		ns.Print(L["The route hands in every quest in your log."])
		return
	end
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		for _, u in ipairs(list) do ns.Print("  " .. (u.title or ("#" .. u.quest))) end
		return
	end
	WHY.grey, WHY.never = L["Grey: no XP any more"], L["The route never hands it in"]
	MenuUtil.CreateContextMenu(anchor or UIParent, function(_, root)
		W.MenuTitle(root, L["Clean up quest log"])
		for _, u in ipairs(list) do
			local why = WHY[u.status]
			local b = root:CreateButton((u.title or ("#" .. u.quest)) .. (why and ("  |cff9d9d9d" .. why .. "|r") or ""), function()
				if not ns.Compat.AskAbandonQuest(u.quest) then ns.Print(L["Abandon it from your quest log."]) end
			end)
			if b and b.SetTooltip then
				b:SetTooltip(function(tip) GameTooltip_SetTitle(tip, L["Abandon"]); GameTooltip_AddNormalLine(tip, L["Abandon asks in the game's own window first."]) end)
			end
		end
	end)
end
function UI.LayoutQuestRoom() end
ns.On("SHOW_QUEST_ROOM", function() UI.ShowQuestRoom() end)

---------------------------------------------------------------------------
-- Importing a guide: the game's dialog with an edit box. What is pasted is
-- read (Import.Preview) and shown in a second dialog before anything is
-- saved; Import (or Update) saves it.
---------------------------------------------------------------------------

local IMPORT = "LITESTAR_IMPORT"

local function factionText(f)
	if f == nil then return L["Alliance and Horde"] end
	return (ns.FactionName and ns.FactionName(f)) or f
end

local function confirmImport(info)
	local I = ns.Import
	local parts = { info.title }
	if info.author then parts[#parts + 1] = format(L["by %s"], info.author) end
	parts[#parts + 1] = format(L["%d steps"], info.steps or 0)
	if info.minLevel then parts[#parts + 1] = (UI.LevelRange and UI.LevelRange(info.minLevel, info.maxLevel)) or tostring(info.minLevel) end
	parts[#parts + 1] = factionText(info.faction)
	if info.license then parts[#parts + 1] = info.license end
	local text = concat(parts, "  \194\183  ")
	if info.state == "same" then text = text .. "\n\n" .. L["You already have this version."] end
	if info.state == "older" then text = text .. "\n\n" .. L["You have a newer version of this guide."] end
	if info.authorChanged then text = text .. "\n\n" .. L["The author is different from the guide you have."] end
	if info.licenseChanged then text = text .. "\n\n" .. L["The licence is different from the guide you have."] end
	W.Modal({ title = L["Import a guide"], text = text, action = info.state == "update" and L["Update"] or L["Import"], onAccept = function()
		local ok, why = I.Save(info.entry)
		if ok then
			ns.Print(format(L["Imported %s."], info.title))
			load(info.id, false)
		else
			ns.Print(why or "?")
		end
	end })
end

function UI.ShowImport()
	local I = ns.Import
	if not (I and I.Preview) then return end
	if not (StaticPopupDialogs and StaticPopup_Show) then
		ns.Print(L["Import a guide"] .. ": /polestar import")
		return
	end
	StaticPopupDialogs[IMPORT] = {
		text = L["Import a guide"] .. "\n\n" .. L["Paste an import string (Ctrl+V, Cmd+V on a Mac)."],
		button1 = L["Next"], button2 = CANCEL or L["Cancel"],
		hasEditBox = true, editBoxWidth = 320, maxLetters = 0,
		OnAccept = function(self)
			local box = self.editBox or self.EditBox
			local text = box and box:GetText() or ""
			local info, why = I.Preview(text)
			if info then
				ns.After(0, function() confirmImport(info) end)
			else
				ns.Print(why or L["This import string holds no guide."])
			end
		end,
		EditBoxOnEnterPressed = function(self)
			local parent = self:GetParent()
			local b = parent and (parent.button1 or (parent.GetButton1 and parent:GetButton1()))
			if b then b:Click() end
		end,
		EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
	}
	StaticPopup_Show(IMPORT)
end
ns.On("SHOW_IMPORT", function() UI.ShowImport() end)

---------------------------------------------------------------------------
-- Community guides: every pack the core found, in the game's context menu
-- (a checkbox to show or hide its guides, or why it is not running), the
-- imported guides with Delete, and where suggestions come from.
---------------------------------------------------------------------------

local PACKS = {}
UI.Packs = PACKS

local function packs()
	local G = ns.Guides
	return G and G.Packs and G.Packs() or {}
end

function PACKS.HasProblems()
	local G = ns.Guides
	return G and G.ProblemCount and G.ProblemCount() > 0 or false
end
function PACKS.AnySwitchedOff()
	for _, r in ipairs(packs()) do if r.status == "off" then return true end end
	return false
end
function PACKS.OursSwitchedOff()
	for _, r in ipairs(packs()) do if r.official and r.status == "off" then return true end end
	return false
end

-- Polestar Guides installed but turned off in the game's AddOns list. The
-- list nests it under Polestar (the client groups addons by name and
-- dependency), and ticking Polestar there does not tick it: after "Disable
-- All" and ticking Polestar again, or one untick, Polestar opens with no
-- guides. The empty states and a question at login turn it back on.
local OWN = "Polestar_Guides"

-- Ours to turn on with it: its race and faction parts and the walking
-- packs (Polestar_Nav*), never the 0.2.x language folders a hand install
-- may have left (Polestar_Guides_deDE), nor the Recorder or community addons.
local function ownPart(name)
	if name == OWN or name:find("^Polestar_Nav") then return true end
	return name:find("^Polestar_Guides_") ~= nil and not name:find("_%l%l%u%u$")
end

-- The installed addons `want` picks that are off for this character:
-- GetAddOnInfo says DISABLED, or the enable state for its GUID is none.
local function offAddOns(want)
	local A = C_AddOns
	local out = {}
	if not (A and A.GetNumAddOns and A.GetAddOnInfo) then return out end
	local C = ns.Compat
	local guid = UnitGUID and UnitGUID("player")
	local player = C and C.Readable and C.Readable(guid) or nil
	for i = 1, A.GetNumAddOns() do
		local name, _, _, _, reason = A.GetAddOnInfo(i)
		if type(name) == "string" and want(name) then
			local off = reason == "DISABLED"
			if not off and A.GetAddOnEnableState then
				local ok, state = pcall(A.GetAddOnEnableState, name, player)
				off = ok and state == 0
			end
			if off then out[#out + 1] = name end
		end
	end
	return out
end

-- Is Polestar Guides installed and turned off in the AddOns list?
function PACKS.OwnGuidesOff()
	return #offAddOns(function(name) return name == OWN end) > 0
end

-- Turn Polestar Guides and its parts back on for every character (no
-- character given: all of them, as the AddOns list's "All"), then reload.
-- Returns the addons it turned on.
function PACKS.TurnOnOwnGuides()
	local A = C_AddOns
	if not (A and A.EnableAddOn) then return {} end
	local names = offAddOns(ownPart)
	for _, name in ipairs(names) do A.EnableAddOn(name) end
	if #names > 0 and ReloadUI then ReloadUI() end
	return names
end

-- At login, once: ask to turn it on, never in combat (then after it). The
-- answer is kept per account until the guides are on again, so a player who
-- keeps them off on purpose is asked once. Never with the gamepad interface
-- (its focus owns the game's dialogs): the guide window's button stays.
local POPUP = "POLESTAR_GUIDES_OFF"
local askPending = false

local function ask()
	if not askPending then return end
	if ns.Compat.InCombat() then return end
	askPending = false
	if ns.GamepadUI() or not (StaticPopupDialogs and StaticPopup_Show) or not PACKS.OwnGuidesOff() then return end
	ns.DB().guidesOffAsked = true
	StaticPopupDialogs[POPUP] = StaticPopupDialogs[POPUP] or {
		text = "%s",
		button1 = L["Turn on and reload"],
		button2 = L["Not now"],
		OnAccept = function() PACKS.TurnOnOwnGuides() end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		preferredIndex = 3,
	}
	StaticPopup_Show(POPUP, L["Polestar Guides is turned off in the AddOns list, so Polestar has no guides to show. Turn it on for all your characters and reload?"])
end

ns.OnLogin(function()
	local db = ns.DB()
	if not PACKS.OwnGuidesOff() then
		db.guidesOffAsked = nil
		return
	end
	if db.guidesOffAsked then return end
	askPending = true
	if C_Timer and C_Timer.After then ns.After(2, ask) else ask() end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() ask() end)

function PACKS.StatusText(r)
	local st = r.status
	if st == "disabled" then return L["turned off in the AddOns list"] end
	if st == "not-loaded" then return r.reason and (L["not loaded: %s"]):format(r.reason) or L["not loaded"] end
	if st == "too-new" then return r.needs and (L["needs Polestar %s or newer"]):format(r.needs) or L["needs a newer Polestar"] end
	if st == "broken" then return L["broken: registered no guides"] end
	if st == "refused" then return (L["refused: %s"]):format(r.reason or "?") end
	return nil
end

function UI.ShowPacks(anchor)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	local G = ns.Guides
	MenuUtil.CreateContextMenu(anchor or UIParent, function(_, root)
		W.MenuTitle(root, L["Community guides"])
		for _, r in ipairs(packs()) do
			local name = packTitle(r) .. (r.guideCount and ("  |cff9d9d9d" .. r.guideCount .. "|r") or "")
			if r.status == "on" or r.status == "off" then
				root:CreateCheckbox(name, function() return r.status == "on" end, function()
					G.SetPackShown(r.id, r.status ~= "on")
				end)
			else
				local b = root:CreateButton(name .. "  |cffff8040" .. (PACKS.StatusText(r) or "") .. "|r")
				if b and b.SetEnabled then b:SetEnabled(false) end
			end
		end
		local I = ns.Import
		local list = I and I.List and I.List() or {}
		W.MenuDivider(root)
		local imported = root:CreateButton(L["Imported guides"] .. " (" .. #list .. ")")
		for _, e in ipairs(list) do
			local sub = imported:CreateButton(e.title .. (e.author and ("  |cff9d9d9d" .. e.author .. "|r") or ""))
			sub:CreateButton(L["Open"], function() load(e.id, false) end)
			sub:CreateButton(L["Delete"], function()
				W.Modal({ title = L["Delete"], text = e.title, action = L["Delete"], danger = true, onAccept = function()
					if I.Delete(e.id) then ns.Print(format(L["Removed imported guide %s."], e.title)) end
				end })
			end)
		end
		imported:CreateButton(L["Import a guide"], function() UI.ShowImport() end)
		local sources = G and G.SuggestSources and G.SuggestSources() or {}
		if #sources > 1 then
			local from = G.SuggestSource()
			local sub = root:CreateButton(L["Suggestions from"])
			for _, id in ipairs(sources) do
				local r = G.Pack and G.Pack(id)
				sub:CreateRadio(id == "guides" and L["Polestar"] or (r and r.title) or id, function() return from == id end, function() ns.Set("behavior.suggestFrom", id) end)
			end
		end
	end)
end
ns.RegisterCommand("packs", function() UI.ShowPacks() end, L["Open the Community guides page"])

---------------------------------------------------------------------------
-- Lookup and the dungeon journal: their windows are gone
---------------------------------------------------------------------------

function UI.ShowLookup() ns.Print(L["Lookup"] .. ": " .. L["Off"]) end
ns.On("SHOW_LOOKUP", function() UI.ShowLookup() end)
ns.On("SHOW_DUNGEON", function() end)

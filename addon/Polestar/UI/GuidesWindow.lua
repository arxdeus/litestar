-- Slim build: the guides window, made only of the game's own templates
-- (Blizzard_SharedXML): ButtonFrameTemplate with its inset and close button,
-- PanelTabButtonTemplate tabs, SearchBoxTemplate, ScrollBox lists with a
-- MinimalScrollBar, UIPanelButtonTemplate, UICheckButtonTemplate and a
-- WowStyle1DropdownTemplate. Three pages:
--
--   * Guides: search, then Suggested for you, Open tabs and every guide this
--     character can follow by folder (community packs and imported guides
--     under their own titles), folders folded like the game's old quest log.
--     The right side shows the selected guide; Load guide, Open in new tab,
--     a double-click (Shift: new tab) or Enter in the search box loads it.
--   * Community guides: each pack's switch (or why it is not running), the
--     imported guides with Open and Delete, Import, and where suggestions
--     come from.
--   * Quest log: the quests the route never hands in (RoutePlan.Unneeded),
--     each with Abandon, which asks in the game's own dialog first.
--
--   UI.ShowGuides(page, opts)  page "guides" | "packs" | "quests"; shown on
--                              that page already: hides (a toggle)
--   UI.GuidesWindow            the frame once built
--
-- Not a UI panel (ShowUIPanel / HideUIPanel are protected in combat): plain
-- Show and Hide, Escape through ns.CloseOnEscape, the close button rewired.

local ADDON, ns = ...
local UI = ns.UI
local L = ns.L
local GU = UI.GameUI

local floor, ipairs, pairs, type, format = math.floor, ipairs, pairs, type, string.format
local concat = table.concat

local NAME = "PolestarGuidesWindow"
local WIN_W, WIN_H = 760, 520
local LIST_W = 330
local ROW_H, HEADER_H = 18, 22
local PAGES = { "guides", "packs", "quests" }

local win
local page = "guides"
local query = ""
local selected
local folds = {} -- this session's folders folded or open by the player: id -> bool
local factCache = {}

local function Engine() return ns.Engine end

-- The ruRU client font (the game's templates use it) has no middle dot and
-- no arrow: plain ASCII there.
local RU = GetLocale and GetLocale() == "ruRU"
local function clean(s)
	if type(s) ~= "string" then return s end
	if RU then s = s:gsub("\194\183", "-"):gsub("\226\134\146", "->") end
	return s
end

local function setFontString(parent, font, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "ARTWORK", font)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	return fs
end

-- Rows come from the game's ScrollBox pool: what goes on them is made with
-- no parent and set under them (ns.CreateFrameUnder), as everywhere a frame
-- of ours goes under one the game made.
local function button(parent, text, width, onClick)
	local b = ns.CreateFrameUnder("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 120, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

---------------------------------------------------------------------------
-- A ScrollBox list with its scroll bar: the game's own (Blizzard_SharedXML
-- ScrollBox, ScrollUtil); rows are plain buttons set up once, filled by
-- `fill(row, data)` each time the list hands one out.
---------------------------------------------------------------------------

local function scrollList(parent, extent, setup, fill)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, data) return extent(data) end)
	view:SetElementInitializer("Button", function(row, data)
		if not row.psReady then
			row.psReady = true
			setup(row)
		end
		row.data = data
		fill(row, data)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	box.ScrollBar = bar
	return box
end

local function setRows(box, rows, keep)
	local dp = CreateDataProvider(rows)
	local retain = keep and ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
	box:SetDataProvider(dp, retain)
end

---------------------------------------------------------------------------
-- Guides page: the model
---------------------------------------------------------------------------

local function playerInfo()
	local C = ns.Compat
	local ok, info = pcall(C.GetPlayerInfo)
	return ok and type(info) == "table" and info or nil
end

local function haystack(g)
	local parts = { g.title or "", g.zoneName or "", g.folder or "", g.id or "", UI.GuidePlace(g) or "", L[UI.Category(g)] or "" }
	if type(g.keywords) == "table" then
		for _, k in ipairs(g.keywords) do parts[#parts + 1] = k end
	end
	return concat(parts, " "):lower()
end

local function matches(g, q)
	if q == "" then return true end
	local hay = haystack(g)
	for word in q:gmatch("%S+") do
		if not hay:find(word, 1, true) then return false end
	end
	return true
end

local function tabsInfo()
	local E = Engine()
	if not (E and E.GetTabs) then return {}, nil end
	local ok, tabs, active = pcall(E.GetTabs)
	if not ok or type(tabs) ~= "table" then return {}, nil end
	return tabs, active
end

local function isOpen(id, default)
	local v = folds[id]
	if v == nil then return default end
	return v
end

-- The rows of the list: headers (folders) and guides, as the search leaves them.
local function guideRows()
	local G = ns.Guides
	local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
	local searching = q ~= ""
	local rows = {}
	local E = Engine()
	local current = E and E.GetGuide and E.GetGuide()
	local tabs = tabsInfo()
	local tabOf = {}
	for i, t in ipairs(tabs) do tabOf[t.guideId] = i end
	local function section(id, text, list, default)
		if #list == 0 then return end
		local open = searching or isOpen(id, default)
		rows[#rows + 1] = { kind = "header", id = id, text = text, count = #list, open = open }
		if open then
			for _, g in ipairs(list) do rows[#rows + 1] = { kind = "guide", g = g, tab = tabOf[g.id] } end
		end
	end
	if not searching then
		local sugg = {}
		for _, id in ipairs(G and G.Suggestions and G.Suggestions() or {}) do
			local h = G.Get(id)
			if h and #sugg < 5 then sugg[#sugg + 1] = h end
		end
		section("suggested", L["Suggested for you"], sugg, true)
		local open = {}
		for _, t in ipairs(tabs) do
			local h = G.Get(t.guideId)
			if h then open[#open + 1] = h end
		end
		section("tabs", L["Open tabs"], open, true)
	end
	-- Polestar's own guides by folder; then each community pack, then the imported ones.
	local byPack, packOrder = {}, {}
	for _, f in ipairs(GU.folders()) do
		for _, g in ipairs(f.guides) do
			if matches(g, q) then
				local pack = g.pack or "guides"
				local p = byPack[pack]
				if not p then
					p = { folders = {}, index = {} }
					byPack[pack] = p
					if pack ~= "guides" then packOrder[#packOrder + 1] = pack end
				end
				local sub = p.index[f.name]
				if not sub then
					sub = { name = f.name, guides = {} }
					p.index[f.name] = sub
					p.folders[#p.folders + 1] = sub
				end
				sub.guides[#sub.guides + 1] = g
			end
		end
	end
	local function holdsCurrent(list)
		if not current then return false end
		for _, g in ipairs(list) do if g.id == current.id then return true end end
		return false
	end
	for _, f in ipairs(byPack.guides and byPack.guides.folders or {}) do
		section("guides/" .. f.name, f.name, f.guides, holdsCurrent(f.guides))
	end
	table.sort(packOrder, function(a, b) return (a == "imported") ~= (b == "imported") and b == "imported" or a < b end)
	for _, pack in ipairs(packOrder) do
		local r = G.Pack and G.Pack(pack)
		local title = pack == "imported" and L["Imported guides"] or (r and GU.packTitle(r)) or pack
		local all = {}
		for _, f in ipairs(byPack[pack].folders) do
			for _, g in ipairs(f.guides) do all[#all + 1] = g end
		end
		section("pack/" .. pack, title, all, holdsCurrent(all))
	end
	if #rows == 0 then
		rows[1] = { kind = "empty", text = searching and L["No guides match your search."] or L["No guides for this character."] }
	end
	return rows
end

-- What a guide's steps hold for this character: the quests it accepts and
-- the zones it visits, in step order. Cached per guide.
local function guideFacts(g)
	local f = factCache[g.id]
	if f then return f end
	f = { quests = 0, zones = {} }
	local G = ns.Guides
	local full = G and G.Get and G.Get(g.id)
	local player = playerInfo()
	local function applies(only) return type(only) ~= "table" or not (G.Matches and player) or G.Matches(only, player) end
	local seen = {}
	local mapName = ns.Compat.MapName
	for _, step in ipairs(full and type(full.steps) == "table" and full.steps or {}) do
		if applies(step.only) and type(step.goals) == "table" then
			for _, goal in ipairs(step.goals) do
				if applies(goal.only) then
					if goal.t == "accept" then f.quests = f.quests + 1 end
					local name = goal.map and mapName(goal.map)
					if name and not seen[name] then
						seen[name] = true
						f.zones[#f.zones + 1] = name
					end
				end
			end
		end
	end
	if #f.zones == 0 then f.zones[1] = UI.GuidePlace(g) end
	factCache[g.id] = f
	return f
end
ns.On("GUIDES_REGISTERED", function() factCache = {} end)

local function nextText(g)
	local G, E = ns.Guides, Engine()
	local function offered(id) return not (E and E.RouteOffered) or E.RouteOffered(g.id, id) end
	local function named(id)
		local h = G.Get(id)
		return h and UI.GuideLabel(h) or nil
	end
	if type(g.nextChoices) == "table" then
		local names = {}
		for _, id in ipairs(g.nextChoices) do
			if offered(id) then names[#names + 1] = named(id) end
		end
		if #names > 0 then return concat(names, ", ") end
	end
	return g.next and named(g.next) or nil
end

---------------------------------------------------------------------------
-- Guides page: the frames
---------------------------------------------------------------------------

local Guides = {}

local function loadGuide(id, newTab)
	if not id then return end
	GU.load(id, newTab)
	if win then win:Hide() end
end

local function difficultyColor(g)
	local lv = g.minLevel
	if not (lv and GetQuestDifficultyColor) then return 1, 1, 1 end
	local ok, c = pcall(GetQuestDifficultyColor, lv)
	if ok and type(c) == "table" and c.r then return c.r, c.g, c.b end
	return 1, 1, 1
end

local function setupGuideRow(row)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.Sel = row:CreateTexture(nil, "BACKGROUND")
	row.Sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	row.Sel:SetBlendMode("ADD")
	row.Sel:SetAllPoints()
	row.Sel:Hide()
	row.Fold = row:CreateTexture(nil, "ARTWORK")
	row.Fold:SetSize(14, 14)
	row.Fold:SetPoint("LEFT", 4, 0)
	row.Check = row:CreateTexture(nil, "ARTWORK")
	row.Check:SetSize(12, 12)
	row.Check:SetPoint("LEFT", 6, 0)
	row.Check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	row.Text = setFontString(row, "GameFontNormal")
	row.Right = setFontString(row, "GameFontHighlightSmall", "RIGHT")
	row.Right:SetPoint("RIGHT", -6, 0)
	row.Text:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(self)
		local d = self.data
		if d.kind == "header" then
			folds[d.id] = not d.open
			Guides.Refresh(true)
		elseif d.kind == "guide" then
			Guides.Select(d.g.id)
		end
	end)
	row:SetScript("OnDoubleClick", function(self)
		local d = self.data
		if d.kind == "guide" then loadGuide(d.g.id, IsShiftKeyDown and IsShiftKeyDown()) end
	end)
end

local function fillGuideRow(row, d)
	row.Fold:Hide()
	row.Check:Hide()
	row.Sel:Hide()
	row.Text:ClearAllPoints()
	row.Text:SetPoint("RIGHT", row.Right, "LEFT", -6, 0)
	if d.kind == "header" then
		row.Fold:Show()
		row.Fold:SetTexture(d.open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
		row.Text:SetFontObject("GameFontNormal")
		row.Text:SetPoint("LEFT", row.Fold, "RIGHT", 4, 0)
		row.Text:SetText(clean(d.text))
		row.Text:SetTextColor(1, 0.82, 0)
		row.Right:SetText(d.count)
		row:Enable()
	elseif d.kind == "guide" then
		local g = d.g
		local E = Engine()
		local state = E and E.GetGuideState and E.GetGuideState(g.id)
		row.Check:SetShown(state == "done")
		row.Text:SetFontObject("GameFontHighlight")
		row.Text:SetPoint("LEFT", 24, 0)
		row.Text:SetText(clean(g.title or g.id))
		row.Text:SetTextColor(difficultyColor(g))
		local lv = UI.LevelRange(g.minLevel, g.maxLevel) or ""
		row.Right:SetText(d.tab and (format(L["Tab %d"], d.tab) .. "  " .. lv) or lv)
		row.Sel:SetShown(g.id == selected)
		row:Enable()
	else
		row.Text:SetFontObject("GameFontDisable")
		row.Text:SetPoint("LEFT", 8, 0)
		row.Text:SetText(d.text)
		row.Text:SetTextColor(0.6, 0.6, 0.6)
		row.Right:SetText("")
		row:Disable()
	end
end

local function line(label, value)
	if not value or value == "" then return nil end
	return "|cffffd100" .. label .. ":|r " .. clean(value)
end

function Guides.Details()
	local d = win.GuidesPage.Details
	local G = ns.Guides
	local g = selected and G.Get(selected)
	local E = Engine()
	d.Empty:SetShown(g == nil)
	d.Title:SetShown(g ~= nil)
	d.Body:SetShown(g ~= nil)
	d.Pitch:SetShown(g ~= nil)
	win.Load:SetEnabled(g ~= nil)
	win.NewTab:SetEnabled(g ~= nil and E and E.OpenTab ~= nil)
	if not g then return end
	d.Title:SetText(clean(g.title or g.id))
	local f = guideFacts(g)
	local state, done, total = nil, nil, nil
	if E and E.GetGuideState then state, done, total = E.GetGuideState(g.id) end
	local status
	if state == "done" then
		status = L["Finished"]
	elseif done and total and total > 0 then
		status = format(L["%d of %d steps"], done, total)
	elseif state == "started" then
		status = L["Started"]
	else
		status = L["Not started"]
	end
	local lines = {}
	local function add(s) if s then lines[#lines + 1] = s end end
	local cat = UI.Category(g)
	if cat ~= "Leveling" then add(line(L["Category"], L[cat] or cat)) end
	add(line(L["Levels"], UI.LevelRange(g.minLevel, g.maxLevel)))
	add(line(L["Zones"], concat(f.zones, ", ")))
	-- Steps as the player counts them (the guide window's "Step 12 of 70").
	local full = G.Get(g.id)
	local n = E and E.StepTotalOf and full and E.StepTotalOf(full)
	if not n or n == 0 then n = g.stepCount or (full and full.steps and #full.steps) end
	-- An open guide says "48 of 70 steps" under Progress, counted for this character.
	if n and not (done and total and total > 0) then add(line(L["Steps"], tostring(n))) end
	if f.quests > 0 then add(line(L["Quests"], tostring(f.quests))) end
	add(line(L["Next"], nextText(g)))
	if g.pack and g.pack ~= "guides" then
		local r = G.Pack and G.Pack(g.pack)
		add(line(L["Community guides"], g.pack == "imported" and L["Imported guides"] or (r and GU.packTitle(r)) or g.pack))
		if g.author then add(line(L["Author"], g.author)) end
	end
	add(line(L["Progress"], status))
	d.Body:SetText(concat(lines, "\n"))
	local pitch = type(g.pitch) == "string" and g.pitch or (type(g.why) == "string" and g.why) or ""
	d.Pitch:SetText(clean(pitch))
	-- An open guide: Continue in place of Load guide, and no second tab.
	local tabs = tabsInfo()
	local open = false
	for _, t in ipairs(tabs) do if t.guideId == g.id then open = true end end
	win.Load:SetText(open and L["Continue"] or L["Load guide"])
	win.NewTab:SetEnabled(not open and E and E.OpenTab ~= nil)
end

function Guides.Select(id)
	selected = id
	local box = win.GuidesPage.List
	box:ForEachFrame(function(row)
		local d = row.data
		row.Sel:SetShown(d and d.kind == "guide" and d.g.id == selected or false)
	end)
	Guides.Details()
end

function Guides.Refresh(keep)
	if not (win and win:IsShown() and page == "guides") then return end
	local rows = guideRows()
	-- Nothing selected, or the selection gone from the list: the open guide,
	-- else the first suggestion.
	local first, has
	for _, r in ipairs(rows) do
		if r.kind == "guide" then
			first = first or r.g.id
			if r.g.id == selected then has = true end
		end
	end
	if not has and not (selected and ns.Guides.Get(selected)) then
		local E = Engine()
		local cur = E and E.GetGuide and E.GetGuide()
		selected = cur and cur.id or first
	end
	setRows(win.GuidesPage.List, rows, keep)
	Guides.Details()
end

function Guides.Build(p)
	local list = scrollList(p, function(d)
		if d.kind == "header" then return HEADER_H end
		if d.kind == "empty" then return 40 end
		return ROW_H
	end, setupGuideRow, fillGuideRow)
	list:SetPoint("TOPLEFT", win.Inset, "TOPLEFT", 6, -6)
	list:SetPoint("BOTTOMLEFT", win.Inset, "BOTTOMLEFT", 6, 6)
	list:SetWidth(LIST_W)
	p.List = list

	local d = CreateFrame("Frame", nil, p)
	d:SetPoint("TOPLEFT", list, "TOPRIGHT", 26, -4)
	d:SetPoint("BOTTOMRIGHT", win.Inset, "BOTTOMRIGHT", -12, 8)
	p.Details = d
	d.Title = setFontString(d, "GameFontNormalLarge")
	d.Title:SetPoint("TOPLEFT")
	d.Title:SetPoint("RIGHT")
	d.Title:SetWordWrap(true)
	d.Body = setFontString(d, "GameFontHighlight")
	d.Body:SetPoint("TOPLEFT", d.Title, "BOTTOMLEFT", 0, -12)
	d.Body:SetPoint("RIGHT")
	d.Body:SetWordWrap(true)
	d.Body:SetSpacing(4)
	d.Pitch = setFontString(d, "GameFontHighlightSmall")
	d.Pitch:SetPoint("TOPLEFT", d.Body, "BOTTOMLEFT", 0, -14)
	d.Pitch:SetPoint("RIGHT")
	d.Pitch:SetWordWrap(true)
	d.Pitch:SetTextColor(0.8, 0.8, 0.8)
	d.Empty = setFontString(d, "GameFontDisable", "CENTER")
	d.Empty:SetPoint("CENTER")
	d.Empty:SetText(L["Choose a guide"])
end

---------------------------------------------------------------------------
-- Community guides page
---------------------------------------------------------------------------

local Packs = {}

local function setupPackRow(row)
	row.Check = ns.CreateFrameUnder("CheckButton", nil, row, "UICheckButtonTemplate")
	row.Check:SetSize(24, 24)
	row.Check:SetPoint("LEFT", 2, 0)
	row.Check:SetScript("OnClick", function(self)
		local d = self:GetParent().data
		if d and d.kind == "pack" then ns.Guides.SetPackShown(d.r.id, self:GetChecked() and true or false) end
	end)
	row.Text = setFontString(row, "GameFontHighlight")
	row.Sub = setFontString(row, "GameFontDisableSmall", "RIGHT")
	row.Delete = button(row, L["Delete"], 80, function(self)
		local e = self:GetParent().data.e
		ns.Widgets.Modal({ title = L["Delete"], text = e.title, action = L["Delete"], danger = true, onAccept = function()
			if ns.Import.Delete(e.id) then
				ns.Print(format(L["Removed imported guide %s."], e.title))
				Packs.Refresh()
			end
		end })
	end)
	row.Delete:SetPoint("RIGHT", -4, 0)
	row.Open = button(row, L["Open"], 80, function(self) loadGuide(self:GetParent().data.e.id, false) end)
	row.Open:SetPoint("RIGHT", row.Delete, "LEFT", -4, 0)
end

local function fillPackRow(row, d)
	row.Check:Hide()
	row.Open:Hide()
	row.Delete:Hide()
	row.Sub:ClearAllPoints()
	row.Sub:SetPoint("RIGHT", -8, 0)
	row.Text:ClearAllPoints()
	row.Text:SetPoint("RIGHT", row.Sub, "LEFT", -8, 0)
	row.Text:SetTextColor(1, 1, 1)
	row.Sub:SetText("")
	if d.kind == "header" then
		row.Text:SetFontObject("GameFontNormal")
		row.Text:SetTextColor(1, 0.82, 0)
		row.Text:SetPoint("LEFT", 6, 0)
		row.Text:SetText(d.text)
	elseif d.kind == "pack" then
		local r = d.r
		row.Text:SetFontObject("GameFontHighlight")
		row.Text:SetPoint("LEFT", 32, 0)
		row.Text:SetText(clean(GU.packTitle(r)))
		local why = UI.Packs.StatusText(r)
		if r.status == "on" or r.status == "off" then
			row.Check:Show()
			row.Check:SetChecked(r.status == "on")
			row.Sub:SetText(format(L["%d guides"], r.guideCount or 0))
		else
			row.Text:SetTextColor(0.6, 0.6, 0.6)
			row.Sub:SetText("|cffff8040" .. (why or "") .. "|r")
		end
	elseif d.kind == "imported" then
		local e = d.e
		row.Open:Show()
		row.Delete:Show()
		row.Sub:ClearAllPoints()
		row.Sub:SetPoint("RIGHT", row.Open, "LEFT", -8, 0)
		row.Text:SetFontObject("GameFontHighlight")
		row.Text:SetPoint("LEFT", 32, 0)
		row.Text:SetText(clean(e.title or e.id))
		row.Sub:SetText(e.author or "")
	else
		row.Text:SetFontObject("GameFontDisable")
		row.Text:SetPoint("LEFT", 32, 0)
		row.Text:SetText(d.text)
		row.Text:SetTextColor(0.6, 0.6, 0.6)
	end
end

function Packs.Refresh(keep)
	if not (win and win:IsShown() and page == "packs") then return end
	local rows = { { kind = "header", text = L["Guide packs"] } }
	for _, r in ipairs(UI.Packs.List()) do rows[#rows + 1] = { kind = "pack", r = r } end
	local list = ns.Import and ns.Import.List and ns.Import.List() or {}
	table.sort(list, function(a, b) return (a.title or a.id) < (b.title or b.id) end)
	rows[#rows + 1] = { kind = "header", text = L["Imported guides"] }
	for _, e in ipairs(list) do rows[#rows + 1] = { kind = "imported", e = e } end
	if #list == 0 then rows[#rows + 1] = { kind = "empty", text = L["No imported guides yet."] } end
	setRows(win.PacksPage.List, rows, keep)
	local G = ns.Guides
	local sources = G and G.SuggestSources and G.SuggestSources() or {}
	win.PacksPage.From:SetShown(#sources > 1)
	win.PacksPage.FromLabel:SetShown(#sources > 1)
	if #sources > 1 and win.PacksPage.From.GenerateMenu then win.PacksPage.From:GenerateMenu() end
end

function Packs.Build(p)
	local list = scrollList(p, function(d) return d.kind == "header" and HEADER_H + 4 or 28 end, setupPackRow, fillPackRow)
	list:SetPoint("TOPLEFT", win.Inset, "TOPLEFT", 6, -6)
	list:SetPoint("BOTTOMRIGHT", win.Inset, "BOTTOMRIGHT", -26, 40)
	p.List = list
	p.FromLabel = setFontString(p, "GameFontNormal")
	p.FromLabel:SetPoint("BOTTOMLEFT", win.Inset, "BOTTOMLEFT", 12, 14)
	p.FromLabel:SetText(L["Suggestions from"] .. ":")
	local from = CreateFrame("DropdownButton", nil, p, "WowStyle1DropdownTemplate")
	from:SetPoint("LEFT", p.FromLabel, "RIGHT", 10, 0)
	from:SetWidth(200)
	if from.SetupMenu then
		from:SetupMenu(function(_, root)
			local G = ns.Guides
			for _, id in ipairs(G.SuggestSources and G.SuggestSources() or {}) do
				local r = G.Pack and G.Pack(id)
				local text = id == "guides" and L["Polestar"] or (r and r.title) or id
				root:CreateRadio(text, function() return G.SuggestSource() == id end, function() ns.Set("behavior.suggestFrom", id) end)
			end
		end)
	end
	p.From = from
end

---------------------------------------------------------------------------
-- Quest log page
---------------------------------------------------------------------------

local Quests = {}
local WHY = {}

local function setupQuestRow(row)
	row.Text = setFontString(row, "GameFontHighlight")
	row.Text:SetPoint("LEFT", 8, 0)
	row.Sub = setFontString(row, "GameFontDisableSmall", "RIGHT")
	row.Abandon = button(row, L["Abandon"], 100, function(self)
		local u = self:GetParent().data.u
		if not ns.Compat.AskAbandonQuest(u.quest) then ns.Print(L["Abandon it from your quest log."]) end
	end)
	row.Abandon:SetPoint("RIGHT", -4, 0)
	row.Sub:SetPoint("RIGHT", row.Abandon, "LEFT", -10, 0)
	row.Text:SetPoint("RIGHT", row.Sub, "LEFT", -8, 0)
end

local function fillQuestRow(row, d)
	if d.kind == "quest" then
		row.Abandon:Show()
		row.Text:SetFontObject("GameFontHighlight")
		row.Text:SetText(d.u.title or ("#" .. d.u.quest))
		row.Sub:SetText(WHY[d.u.status] or "")
	else
		row.Abandon:Hide()
		row.Text:SetFontObject("GameFontDisable")
		row.Text:SetText(d.text)
		row.Sub:SetText("")
	end
end

function Quests.Refresh(keep)
	if not (win and win:IsShown() and page == "quests") then return end
	WHY.grey, WHY.missed, WHY.skipped, WHY.unplanned = L["Grey: no XP any more"], L["The route never hands it in"], L["The route never hands it in"], L["The route never hands it in"]
	local RP = ns.RoutePlan
	local list = RP and RP.Unneeded and RP.Unneeded()
	local rows = {}
	if list == nil then
		rows[1] = { kind = "empty", text = L["The route ahead isn't settled yet (a guide to choose or load), so it can't say which quests it leaves behind."] }
	elseif #list == 0 then
		rows[1] = { kind = "empty", text = L["The route hands in every quest in your log."] }
	else
		for _, u in ipairs(list) do rows[#rows + 1] = { kind = "quest", u = u } end
	end
	setRows(win.QuestsPage.List, rows, keep)
end

function Quests.Build(p)
	p.Desc = setFontString(p, "GameFontHighlightSmall")
	p.Desc:SetPoint("TOPLEFT", win.Inset, "TOPLEFT", 12, -10)
	p.Desc:SetPoint("RIGHT", win.Inset, "RIGHT", -12, 0)
	p.Desc:SetWordWrap(true)
	p.Desc:SetText(L["The route doesn't need these quests: it never hands them in, or they give no XP any more. Abandon asks in the game's own window first."])
	local list = scrollList(p, function(d) return d.kind == "quest" and 28 or 48 end, setupQuestRow, fillQuestRow)
	list:SetPoint("TOPLEFT", win.Inset, "TOPLEFT", 6, -44)
	list:SetPoint("BOTTOMRIGHT", win.Inset, "BOTTOMRIGHT", -26, 6)
	p.List = list
end

local pendingQuests = false
local function questsSoon()
	if pendingQuests or not (win and win:IsShown() and page == "quests") then return end
	pendingQuests = true
	ns.After(0.3, function()
		pendingQuests = false
		Quests.Refresh(true)
	end)
end
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_REMOVED", "QUEST_ACCEPTED" }) do ns.RegisterEvent(ev, questsSoon) end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local TAB_TEXT

local function refresh(keep)
	if not win then return end
	if page == "guides" then Guides.Refresh(keep)
	elseif page == "packs" then Packs.Refresh(keep)
	else Quests.Refresh(keep) end
end

local function showPage(name)
	page = name
	for i, id in ipairs(PAGES) do
		if id == name then PanelTemplates_SetTab(win, i) end
	end
	win.GuidesPage:SetShown(name == "guides")
	win.PacksPage:SetShown(name == "packs")
	win.QuestsPage:SetShown(name == "quests")
	win.Search:SetShown(name == "guides")
	win.Load:SetShown(name == "guides")
	win.NewTab:SetShown(name == "guides")
	win.Import:SetShown(name ~= "quests")
	win:SetTitle(L["Polestar"] .. " - " .. TAB_TEXT[name])
	refresh(false)
end

local function build()
	TAB_TEXT = { guides = L["Guides"], packs = L["Community guides"], quests = L["Quest log"] }
	win = CreateFrame("Frame", NAME, ns.UIParent, "ButtonFrameTemplate")
	UI.GuidesWindow = win
	win:SetSize(WIN_W, WIN_H)
	win:SetPoint("CENTER")
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	if win.SetPortraitToAsset then win:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Book_09") end
	-- Not a UI panel: the template's close button would go through
	-- HideUIPanel, which the game refuses from an addon's frame in combat.
	if win.CloseButton then win.CloseButton:SetScript("OnClick", function() win:Hide() end) end
	win:Hide()
	ns.CloseOnEscape(NAME)

	local search = CreateFrame("EditBox", nil, win, "SearchBoxTemplate")
	search:SetSize(220, 20)
	search:SetPoint("TOPLEFT", win, "TOPLEFT", 70, -32)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		if text == query then return end
		query = text
		Guides.Refresh(false)
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if selected then loadGuide(selected, IsShiftKeyDown and IsShiftKeyDown()) end
	end)
	win.Search = search

	win.Import = button(win, L["Import a guide"], 150, function() UI.ShowImport() end)
	win.Import:SetPoint("TOPRIGHT", win, "TOPRIGHT", -12, -30)

	win.Load = button(win, L["Load guide"], 140, function() loadGuide(selected, false) end)
	win.Load:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -8, 4)
	win.NewTab = button(win, L["Open in new tab"], 160, function() loadGuide(selected, true) end)
	win.NewTab:SetPoint("RIGHT", win.Load, "LEFT", -4, 0)

	win.GuidesPage = CreateFrame("Frame", nil, win)
	win.GuidesPage:SetAllPoints()
	Guides.Build(win.GuidesPage)
	win.PacksPage = CreateFrame("Frame", nil, win)
	win.PacksPage:SetAllPoints()
	Packs.Build(win.PacksPage)
	win.QuestsPage = CreateFrame("Frame", nil, win)
	win.QuestsPage:SetAllPoints()
	Quests.Build(win.QuestsPage)

	-- PanelTabButtonTemplate adds each tab to win.Tabs (parentArray) as it is made.
	local tabs = rawget(win, "Tabs")
	if type(tabs) ~= "table" then
		tabs = {}
		win.Tabs = tabs
	end
	for i, id in ipairs(PAGES) do
		local tab = CreateFrame("Button", NAME .. "Tab" .. i, win, "PanelTabButtonTemplate")
		tabs[i] = tab
		tab:SetID(i)
		tab:SetText(TAB_TEXT[id])
		tab:SetScript("OnClick", function() showPage(id) end)
		if i == 1 then tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 12, 2) end
	end
	PanelTemplates_SetNumTabs(win, #PAGES)
	for _, tab in ipairs(tabs) do
		if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 0) end
	end
	win:SetScript("OnShow", function() refresh(true) end)
	return win
end

function UI.ShowGuides(name, opts)
	name = name or "guides"
	if not win then build() end
	if win:IsShown() and page == name and not (opts and opts.keepOpen) then
		win:Hide()
		return
	end
	if name == "guides" then
		local E = Engine()
		local cur = E and E.GetGuide and E.GetGuide()
		if cur and not selected then selected = cur.id end
	end
	win:Show()
	win:Raise()
	showPage(name)
end

-- While shown, what it lists follows the guides, the tabs and the packs.
local function onChange() if win and win:IsShown() then refresh(true) end end
for _, msg in ipairs({ "GUIDES_REGISTERED", "TABS_CHANGED", "GUIDE_CHANGED", "PACKS_CHANGED", "GUIDE_COMPLETED" }) do ns.On(msg, onChange) end
ns.On("SETTING_CHANGED", function(path) if path == "behavior.suggestFrom" then onChange() end end)

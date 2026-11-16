-- The options in the game's own Settings panel (Esc > Options > AddOns >
-- Polestar), drawn by Blizzard's vertical layout: its checkboxes, sliders,
-- dropdowns and buttons, section headers and search. Slim build: this replaces
-- Polestar's own options window as the place settings live.
--
-- The rows come from the same registry the options window reads (UI/Options.lua
-- filters it: O.Layout's pages, tabs and sections, the hidden and moved
-- controls already applied), so nothing is declared twice. Every row is a proxy
-- setting (Settings.RegisterProxySetting): it reads and writes ns.Get / ns.Set,
-- so the addon's own saved variables stay the only store, and a change made
-- elsewhere (the guide window's menu) shows the next time the panel draws.
--
-- One category, "Polestar", with a subcategory per page (Guide, Questing,
-- Discovery, ...); each tab of a page is a section header, its sections below
-- it as smaller headers when there are several. Pages drawn by hand (Community
-- guides, About) and colour or key-binding rows have no Blizzard control: they
-- stay in Polestar's window, which the last row of the main category opens.
--
-- Built once, after every module registered (PLAYER_LOGIN): Blizzard's layout
-- has no way to remove a row, so late registrations wait for the next /reload.
-- Taint: no search tags are added from our code, no parent initializers are
-- set (Hyperframe's InterfacePanelLib documents both); a dependent row is
-- greyed out through AddModifyPredicate instead.

local ADDON, ns = ...
local UI = ns.UI
local L = ns.L
local type, ipairs, pairs, tostring, tonumber, floor = type, ipairs, pairs, tostring, tonumber, math.floor

local BS = {}
UI.BlizzardSettings = BS

local function api()
	return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory
		and Settings.RegisterProxySetting and Settings.CreateCheckbox and Settings.CreateSlider and Settings.CreateDropdown
		and Settings.CreateSliderOptions and Settings.CreateControlTextContainer and Settings.RegisterAddOnCategory
		and Settings.VarType and true or false
end
BS.Available = api

local function text(v)
	if type(v) == "function" then v = v() end
	return type(v) == "string" and v or ""
end

local seq = 0
local function variable(c)
	seq = seq + 1
	return ADDON .. "_" .. (c.key and c.key:gsub("[^%w]", "_") or ("row" .. seq))
end

-- A value the slider shows at its right, as the options window formats it.
local function formatter(c)
	local f = c.format
	if type(f) == "function" then return function(v) return tostring(f(v)) end end
	if type(f) == "string" then return function(v) return f:format(v) end end
	return function(v)
		if v == floor(v) then return tostring(v) end
		return ("%.2f"):format(v)
	end
end

local function getter(c)
	if c.get then return c.get end
	return function() return ns.Get(c.key) end
end
local function setter(c)
	if c.set then return c.set end
	return function(v) ns.Set(c.key, v) end
end
local function default(c, fallback)
	if c.key then
		local d = ns.GetDefault(c.key)
		if d ~= nil then return d end
	end
	local ok, v = pcall(getter(c))
	if ok and v ~= nil then return v end
	return fallback
end

-- A row greyed out while c.disabled says so (a child of a switch that is off).
local function predicates(init, c)
	if not init then return end
	if c.disabled and init.AddModifyPredicate then
		init:AddModifyPredicate(function()
			local ok, off = pcall(c.disabled)
			return not (ok and off)
		end)
	end
	if c.child and init.Indent then init:Indent() end
end

local function checkbox(cat, c)
	local s = Settings.RegisterProxySetting(cat, variable(c), Settings.VarType.Boolean, text(c.label), default(c, false) and true or false,
		function() return getter(c)() and true or false end, setter(c))
	predicates(Settings.CreateCheckbox(cat, s, text(c.help)), c)
end

local function slider(cat, c)
	local lo, hi, step = c.min or 0, c.max or 1, c.step or 0.1
	local s = Settings.RegisterProxySetting(cat, variable(c), Settings.VarType.Number, text(c.label), tonumber(default(c, lo)) or lo,
		function() return tonumber(getter(c)()) or lo end, setter(c))
	local o = Settings.CreateSliderOptions(lo, hi, step)
	if o.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
		o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter(c))
	end
	predicates(Settings.CreateSlider(cat, s, o, text(c.help)), c)
end

-- Dropdown values are strings in Polestar's choices ("2", "off", "soft");
-- a numeric list is kept as numbers.
local function dropdown(cat, c)
	local function list()
		local l = c.choices
		if type(l) == "function" then l = l() end
		return l or {}
	end
	local first = list()[1]
	local numeric = first and type(first.value) == "number"
	local vt = numeric and Settings.VarType.Number or Settings.VarType.String
	local fallback = first and first.value or ""
	local s = Settings.RegisterProxySetting(cat, variable(c), vt, text(c.label), default(c, fallback),
		function() local v = getter(c)(); if v == nil then return fallback end return numeric and tonumber(v) or tostring(v) end, setter(c))
	local function options()
		local box = Settings.CreateControlTextContainer()
		for _, ch in ipairs(list()) do box:Add(ch.value, ch.label or ch.text or tostring(ch.value), ch.help) end
		return box:GetData()
	end
	predicates(Settings.CreateDropdown(cat, s, options, text(c.help)), c)
end

local function button(layout, c)
	if not (CreateSettingsButtonInitializer and layout) then return end
	local onClick = c.onClick
	if c.confirm and ns.Widgets and ns.Widgets.Modal then
		onClick = function()
			ns.Widgets.Modal({ title = text(c.confirmTitle) ~= "" and text(c.confirmTitle) or text(c.label), icon = c.icon, danger = c.danger,
				action = text(c.confirmAction) ~= "" and text(c.confirmAction) or text(c.button), text = text(c.confirmText),
				onAccept = c.onClick })
		end
	end
	-- addSearchTags false: tags written from addon code taint the panel's search.
	local init = CreateSettingsButtonInitializer(text(c.label), text(c.button) ~= "" and text(c.button) or text(c.label), onClick, text(c.help), false)
	layout:AddInitializer(init)
	predicates(init, c)
end

local function header(layout, name)
	if layout and CreateSettingsListSectionHeaderInitializer and name and name ~= "" then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
	end
end

local function row(cat, layout, c)
	local ok, err = pcall(function()
		if c.needs and not c.needs() then return end
		if c.kind == "toggle" then checkbox(cat, c)
		elseif c.kind == "slider" then slider(cat, c)
		elseif c.kind == "dropdown" then dropdown(cat, c)
		elseif c.kind == "button" then button(layout, c)
		end -- color and binding rows stay in Polestar's window
	end)
	if not ok then ns.Debug("Settings row " .. tostring(c.key or c.label) .. ": " .. tostring(err)) end
end

local built = false
function BS.Build()
	if built or not api() then return false end
	local O = UI.Options
	if not (O and O.Sections) then return false end
	built = true
	local main, mainLayout = Settings.RegisterVerticalLayoutCategory(ns.name or ADDON)
	BS.category = main
	local subs = {}
	local lastTab = {}
	for _, s in ipairs(O.Sections()) do
		local sub = subs[s.page]
		if not sub then
			local cat, layout = Settings.RegisterVerticalLayoutSubcategory(main, s.pageName)
			sub = { cat = cat, layout = layout }
			subs[s.page] = sub
		end
		if lastTab[s.page] ~= s.tab then
			lastTab[s.page] = s.tab
			header(sub.layout, s.tab ~= "" and s.tab or s.section)
		end
		for _, c in ipairs(s.controls) do row(sub.cat, sub.layout, c) end
	end
	-- The main category: what the addon is, and the window for the rest.
	header(mainLayout, L["Leveling guides for World of Warcraft: Forever."])
	if CreateSettingsButtonInitializer and mainLayout then
		mainLayout:AddInitializer(CreateSettingsButtonInitializer(L["Community guides"], L["Open"], function() BS.OpenWindow("guidepacks") end,
			L["Guides made by other players: switch them on or off, and choose where suggestions come from."], false))
		mainLayout:AddInitializer(CreateSettingsButtonInitializer(L["About"], L["Open"], function() BS.OpenWindow("about") end,
			L["Why Polestar exists, its commands and its credits."], false))
	end
	Settings.RegisterAddOnCategory(main)
	UI.settingsCategory = main
	return true
end

-- Polestar's own window, for the pages Blizzard's layout cannot draw. The
-- game's panel closes first (never in combat: protected), as the old entry
-- did.
function BS.OpenWindow(section)
	local panel = SettingsPanel
	if panel and panel.IsShown and panel:IsShown() and HideUIPanel and not (InCombatLockdown and InCombatLockdown()) then
		HideUIPanel(panel)
	end
	if UI.ShowOptionsWindow then UI.ShowOptionsWindow(section) end
end

-- Open the game's panel on Polestar (or a page of it). False when it cannot.
function BS.Open(section)
	if not (built and BS.category and Settings and Settings.OpenToCategory) then return false end
	if InCombatLockdown and InCombatLockdown() then
		ns.Print(L["Polestar's settings open after combat."])
		return true
	end
	local ok = pcall(Settings.OpenToCategory, BS.category:GetID())
	return ok
end

ns.OnLogin(function() BS.Build() end)

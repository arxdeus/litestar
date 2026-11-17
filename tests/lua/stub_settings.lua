-- The game's vertical Settings layout for tests (Settings.RegisterVerticalLayoutCategory and
-- friends, as Blizzard_Settings_Shared declares them on Forever 1.60.1): categories with a layout
-- of initializers, proxy settings with get/set, checkbox / slider / dropdown / button / header
-- initializers with modify predicates and indents. Load after wow_stub.lua.
--
--   stub.settings.categories   every vertical category: { name, parent, layout = { initializers } }
--   stub.settings.byVar[var]   a setting by its variable: setting:GetValue(), :SetValue(v)

stub.settings = { categories = {}, byVar = {} }

Settings.VarType = { Boolean = "boolean", Number = "number", String = "string" }

local function newLayout()
	local l = { initializers = {} }
	function l:AddInitializer(i) self.initializers[#self.initializers + 1] = i; i.layout = self end
	return l
end

local function newCategory(name, parent)
	local c = { name = name, parent = parent, layout = newLayout(), ID = name .. "#" .. (#stub.settings.categories + 1) }
	function c:GetID() return self.ID end
	function c:GetName() return self.name end
	stub.settings.categories[#stub.settings.categories + 1] = c
	return c, c.layout
end

function Settings.RegisterVerticalLayoutCategory(name) return newCategory(name, nil) end
function Settings.RegisterVerticalLayoutSubcategory(parent, name) return newCategory(name, parent) end

function Settings.RegisterProxySetting(category, variable, varType, name, default, get, set)
	assert(stub.settings.byVar[variable] == nil, "duplicate setting variable " .. tostring(variable))
	local v0 = get()
	assert(type(v0) == varType, ("setting %s: getter returned %s, declared %s"):format(variable, type(v0), varType))
	assert(type(default) == varType, ("setting %s: default is %s, declared %s"):format(variable, type(default), varType))
	local s = { category = category, variable = variable, varType = varType, name = name, default = default }
	function s:GetValue() return get() end
	function s:SetValue(v) assert(type(v) == varType, "SetValue type"); set(v) end
	function s:GetVariable() return variable end
	function s:GetName() return name end
	function s:GetDefaultValue() return default end
	stub.settings.byVar[variable] = s
	return s
end

local function initializer(kind, data)
	local i = { kind = kind, data = data, predicates = {}, indent = false }
	function i:AddModifyPredicate(fn) self.predicates[#self.predicates + 1] = fn end
	function i:AddShownPredicate(fn) self.shown = fn end
	function i:Indent() self.indent = true end
	function i:IsEnabled()
		for _, p in ipairs(self.predicates) do if not p() then return false end end
		return true
	end
	return i
end

function Settings.CreateCheckbox(category, setting, tooltip)
	assert(type(tooltip) == "string" or tooltip == nil)
	local i = initializer("checkbox", { setting = setting, tooltip = tooltip })
	category.layout:AddInitializer(i)
	return i
end

function Settings.CreateSliderOptions(min, max, step)
	assert(type(min) == "number" and type(max) == "number" and type(step) == "number" and min < max)
	local o = { min = min, max = max, step = step }
	function o:SetLabelFormatter(side, fn) self.formatter = fn end
	return o
end
MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2, Top = 3 } }

function Settings.CreateSlider(category, setting, options, tooltip)
	local i = initializer("slider", { setting = setting, options = options, tooltip = tooltip })
	category.layout:AddInitializer(i)
	return i
end

function Settings.CreateControlTextContainer()
	local c = { list = {} }
	function c:Add(value, label, tooltip) self.list[#self.list + 1] = { value = value, label = label, tooltip = tooltip } end
	function c:GetData() return self.list end
	return c
end

function Settings.CreateDropdown(category, setting, options, tooltip)
	assert(type(options) == "function", "CreateDropdown wants an options function")
	local i = initializer("dropdown", { setting = setting, options = options, tooltip = tooltip })
	category.layout:AddInitializer(i)
	return i
end

function CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)
	assert(addSearchTags == false, "search tags from addon code taint the panel")
	return initializer("button", { name = name, buttonText = buttonText, onClick = onClick, tooltip = tooltip })
end

function CreateSettingsListSectionHeaderInitializer(name)
	return initializer("header", { name = name })
end

local addOnCategories = {}
stub.settings.addOn = addOnCategories
local registerAddOn = Settings.RegisterAddOnCategory
function Settings.RegisterAddOnCategory(c)
	addOnCategories[#addOnCategories + 1] = c
	if registerAddOn then registerAddOn(c) end
end

SettingsPanel = CreateFrame("Frame", "SettingsPanel")
SettingsPanel:Hide()
local open = Settings.OpenToCategory
function Settings.OpenToCategory(id)
	SettingsPanel:Show()
	if open then open(id) end
end
function HideUIPanel(f) if f and f.Hide then f:Hide() end end

-- Blizzard_Menu's context menu (MenuUtil.CreateContextMenu) for tests: the
-- generator runs at once into a description tree; stub.menus[#stub.menus] is
-- the last one, its items { kind, text, children, fn, checked }.
stub.menus = {}
local function description(kind, text, fn, checked)
	local d = { kind = kind, text = text, fn = fn, checked = checked, children = {}, enabled = true }
	function d:CreateButton(t, f) local c = description("button", t, f); self.children[#self.children + 1] = c; return c end
	function d:CreateTitle(t) local c = description("title", t); self.children[#self.children + 1] = c; return c end
	function d:CreateDivider() local c = description("divider"); self.children[#self.children + 1] = c; return c end
	function d:CreateCheckbox(t, is, f) local c = description("checkbox", t, f, is); self.children[#self.children + 1] = c; return c end
	function d:CreateRadio(t, is, f) local c = description("radio", t, f, is); self.children[#self.children + 1] = c; return c end
	function d:SetEnabled(on) self.enabled = on and true or false end
	function d:SetTooltip(fn) self.tooltip = fn end
	return d
end
MenuUtil = {
	CreateContextMenu = function(owner, generator)
		local root = description("root")
		generator(owner, root)
		local m = { root = root, owner = owner, shown = true }
		function m:Close() self.shown = false end
		function m:IsShown() return self.shown end
		stub.menus[#stub.menus + 1] = m
		return m
	end,
}
-- Click the first item (depth-first) whose text contains `text`.
function stub.clickMenu(text)
	local m = stub.menus[#stub.menus]
	local function walk(d)
		for _, c in ipairs(d.children) do
			if c.text and tostring(c.text):find(text, 1, true) and c.fn then c.fn(); return true end
			if walk(c) then return true end
		end
	end
	return m and walk(m.root) or false
end
function stub.menuText()
	local m = stub.menus[#stub.menus]
	local out = {}
	local function walk(d, depth)
		for _, c in ipairs(d.children) do
			out[#out + 1] = string.rep("  ", depth) .. c.kind .. ":" .. tostring(c.text)
			walk(c, depth + 1)
		end
	end
	if m then walk(m.root, 0) end
	return out
end

-- The game's frame templates the guides window is made of (Blizzard_SharedXML):
-- ButtonFrameTemplate (Inset, CloseButton, SetTitle), WowScrollBoxList with a
-- linear view (every element gets a row at once: stub.rows(box)), the tab
-- helpers, DataProvider. Enough to drive UI/GuidesWindow.lua in tests.
local baseCreate = CreateFrame
function CreateFrame(kind, name, parent, template, ...)
	local f = baseCreate(kind, name, parent, template, ...)
	if template == "ButtonFrameTemplate" then
		f.Inset = baseCreate("Frame", nil, f)
		f.CloseButton = baseCreate("Button", nil, f)
		f.TitleText = f:CreateFontString()
		function f:SetTitle(t) self.TitleText:SetText(t) end
		function f:SetPortraitToAsset() end
	elseif template == "WowScrollBoxList" then
		f.frames = {}
		function f:SetDataProvider(dp)
			for _, row in ipairs(self.frames) do row:Hide() end
			local list = {}
			for i, data in ipairs(dp.list) do
				local row = self.frames[i] or baseCreate(self.view.kind, nil, self)
				self.frames[i] = row
				row:Show()
				self.view.init(row, data)
				list[i] = row
			end
			self.shownRows = list
		end
		function f:ForEachFrame(fn) for _, row in ipairs(self.shownRows or {}) do fn(row) end end
	elseif template == "UICheckButtonTemplate" then
		f.Text = f:CreateFontString()
	elseif template == "DropdownButton" or template == "WowStyle1DropdownTemplate" then
		function f:SetupMenu(gen) self.generator = gen end
		function f:GenerateMenu() end
	end
	return f
end
function CreateScrollBoxListLinearView()
	local v = { kind = "Button" }
	function v:SetElementExtentCalculator(fn) self.extent = fn end
	function v:SetElementInitializer(kind, fn) self.kind, self.init = kind, fn end
	return v
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end }
ScrollBoxConstants = { RetainScrollPosition = true }
function CreateDataProvider(t) return { list = t or {} } end
function PanelTemplates_SetTab(f, i) f.selectedTab = i end
function PanelTemplates_SetNumTabs(f, n) f.numTabs = n end
function PanelTemplates_TabResize() end
function stub.rows(box)
	local out = {}
	for _, row in ipairs(box.shownRows or {}) do out[#out + 1] = row end
	return out
end

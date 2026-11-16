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

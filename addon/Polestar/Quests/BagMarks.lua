-- A quest mark on bag items a quest still needs, so a Murloc Eye is not
-- deleted or sold before the hand-in: a quest in your log (Q.ObjectivesForItem,
-- the index the item tooltip reads) or one the running guide has ahead that you
-- have not accepted (Q.IsItemNeededAhead). It goes once the quest is handed in.
-- Abandoning a quest keeps it, as the quest is ahead in the guide again.
-- So does a guide that has gone past every step for a quest you never accepted:
-- nothing ahead needs the item, and the mark clears.
--
-- Three bag views (qol.questBagMarks, which hides only the marks: the sale,
-- delete and buyback guards ask Q.IsItemNeeded whatever it says), the way
-- Gear/Bags.lua draws its arrows: the client's bags, where each container
-- frame's UpdateItems is
-- post-hooked on the frame itself (ContainerFrameMixin's functions are copied
-- onto each frame as it is made) and the mark is a texture on the item
-- button, top-right, kept here by button, nothing written into the button's
-- table; Baganator, as a corner widget; and EllesmereUI Bags, as an item
-- overlay painter.

local ADDON, ns = ...

local Q = ns.QuestDB
local type, pairs, ipairs, pcall, tonumber = type, pairs, ipairs, pcall, tonumber

local ICON = "Interface/GossipFrame/ActiveQuestIcon"
local SIZE = 16

-- The marks only (none while Polestar is hidden); the guards below ask Q.IsItemNeeded.
local function isOn()
	return Q.IsRunning() and ns.Get("qol.questBagMarks") and not ns.Hidden() and true or false
end

-- Whether a quest in the log, or one ahead in the running guide, still asks
-- for item `itemID`. Needs only the quest database: the marks' setting does
-- not turn off the other guards that ask this.
function Q.IsItemNeeded(itemID)
	return Q.IsRunning() and (Q.ObjectivesForItem(itemID) ~= nil or Q.IsItemNeededAhead(itemID)) or false
end

local marks = setmetatable({}, { __mode = "k" }) -- item button -> texture

local function markFor(button)
	local t = marks[button]
	if t then return t end
	t = button:CreateTexture(nil, "OVERLAY", nil, 3)
	t:SetSize(SIZE, SIZE)
	t:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
	t:SetTexture(ICON)
	marks[button] = t
	return t
end

local function itemOf(button)
	local ok, bag = pcall(button.GetBagID, button)
	if not (ok and type(bag) == "number") then return nil end
	local C = C_Container
	if not C then return nil end
	local slot = button:GetID()
	if C.GetContainerItemID then return C.GetContainerItemID(bag, slot) end
	local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
	return type(info) == "table" and info.itemID or nil
end

local function updateFrame(frame)
	if type(frame.EnumerateValidItems) ~= "function" then return end
	local on = isOn()
	for _, button in frame:EnumerateValidItems() do
		local id = on and itemOf(button)
		if id and Q.IsItemNeeded(id) then
			markFor(button):Show()
		elseif marks[button] then
			marks[button]:Hide()
		end
	end
end

local function onUpdateItems(frame)
	ns.SafeCall(updateFrame, frame)
end

local function containerFrames()
	local out = {}
	local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	if type(list) == "table" then
		for _, f in ipairs(list) do out[#out + 1] = f end
	end
	if ContainerFrameCombinedBags then out[#out + 1] = ContainerFrameCombinedBags end
	return out
end

local hooked = setmetatable({}, { __mode = "k" })

local function hookBags()
	if not hooksecurefunc then return end
	for _, f in ipairs(containerFrames()) do
		if not hooked[f] and type(f.UpdateItems) == "function" then
			hooksecurefunc(f, "UpdateItems", onUpdateItems)
			hooked[f] = true
		end
	end
end

---------------------------------------------------------------------------
-- Baganator and EllesmereUI Bags (as Gear/Bags.lua draws its arrows there)
---------------------------------------------------------------------------

local function needed(link)
	local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
	return id and Q.IsItemNeeded(id) or false
end

-- Repaints the shown bags now.
function Q.RedrawBagMarks()
	hookBags()
	for _, f in ipairs(containerFrames()) do
		if hooked[f] and f:IsShown() then onUpdateItems(f) end
	end
end

hookBags()
ns.OnLogin(hookBags)
ns.On("QUESTDB_UPDATED", Q.RedrawBagMarks)
ns.On("QUESTDB_STARTED", Q.RedrawBagMarks)
ns.On("STEP_CHANGED", Q.RedrawBagMarks)
ns.On("GUIDE_CHANGED", Q.RedrawBagMarks)
ns.On("SETTING_CHANGED", function(path)
	if path == "qol.questBagMarks" or path == "qol.questDB" or path == "qol" or path == "" then Q.RedrawBagMarks() end
end)
ns.On("POLESTAR_HIDDEN", Q.RedrawBagMarks)

-- Zone art band, slim build: no world map paintings or overlay tables, only
-- the plain band the callers (guide menu, route choice, guide end, lookup,
-- dungeons) lay their text over.
--
--   ZoneArt.Create(parent, width, height[, ground]) -> art (art.Over for text)
--   ZoneArt.Paint(art, ...) -> false (nothing painted; art.psCanvas nil)

local ADDON, ns = ...
local UI, Theme, W = ns.UI, ns.Theme, ns.Widgets

local ZA = {}
UI.ZoneArt = ZA

function ZA.Create(parent, width, height, ground)
	local a = CreateFrame("Frame", nil, parent)
	a:SetSize(width, height)
	a.psW, a.psH = width, height
	a.Bg = a:CreateTexture(nil, "BACKGROUND")
	a.Bg:SetAllPoints(a)
	a.Bg:SetTexture(Theme.Media("white"))
	ground = ground or "panelAlt"
	W.Painter(a, function(self)
		local r, g, b = Theme.Color(ground)
		self.Bg:SetVertexColor(r, g, b, 1)
	end)
	a.Over = CreateFrame("Frame", nil, a)
	a.Over:SetAllPoints(a)
	a.Rule = W.Divider(a.Over)
	a.Rule:SetPoint("BOTTOMLEFT", a, "BOTTOMLEFT", 0, 0)
	a.Rule:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
	return a
end

function ZA.Paint(a)
	a.psCanvas = nil
	return false
end

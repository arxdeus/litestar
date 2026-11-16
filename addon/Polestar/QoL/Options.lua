-- The Quality of Life settings (docs/ARCHITECTURE.md, "Options registry"):
-- the questing helpers on the Questing page, the rest on Quality of Life, and
-- the conveniences among the questing helpers on both (C below). Both pages
-- and their tabs and sections are declared in UI/Options.lua.

local ADDON, ns = ...
local L = ns.L
local QoL = ns.QoL

if not ns.RegisterOptions then return end

local QUESTING, QOL = L["Questing"], L["Quality of Life"]

local function register(page, tab, section, controls)
	local ok, err = ns.RegisterOptions({ page = page, tab = tab, section = section, controls = controls })
	if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- Help for a toggle EllesmereUI may cover: says why it starts off.
local function help(key, text)
	local by = QoL.CoveredBy(key)
	if not by then return text end
	return text .. " " .. string.format(L["Off by default: %s does this too."], (by:gsub("^EllesmereUI", "EllesmereUI ")))
end

local function markOff() return not QoL.On("markTarget") end
local function targetOff() return not QoL.On("targetButton") end

-- The eight raid icons, by the client's names, then a new one each press.
local function markChoices()
	local list = {}
	for i = 1, 8 do
		list[i] = { value = tostring(i), label = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":0|t " .. (_G["RAID_TARGET_" .. i] or i) }
	end
	list[9] = { value = "cycle", label = L["A new one each press"] }
	return list
end

-- Controls shown on two pages: on their home page and on Quality of Life,
-- where players look for conveniences (Fitz, 2026-11-05). One setting, two
-- places: both read and write the same key. Each call makes fresh tables, as
-- the registry keeps per-control state (rows, caches).
local C = {}
function C.itemButton()
	return { kind = "toggle", key = "qol.itemButton", label = L["Quest item button"],
		help = L["A button for the current step's quest item, with count, cooldown and range. Bind it under Key Bindings > AddOns."],
		search = "use item, quest item, keybind, hotkey, item bar" }
end
local function itemButtonOff() return not QoL.On("itemButton") end
function C.questLoot()
	return { kind = "toggle", key = "qol.questLoot", label = L["Show quest-starting loot"], disabled = itemButtonOff, child = true,
		help = L["When you loot an item that starts a quest you can take, it goes on the quest item button with a glow until you click it or take the quest. The step's own item comes first; several wait their turn, oldest first."],
		search = "quest starter, starts a quest, loot, quest item, glow" }
end
function C.stepInteract()
	return { kind = "toggle", key = "qol.stepInteract", label = L["Step key talks and loots"],
		help = L["Once the step key has targeted the step's NPC, the next press talks to it; on the corpse of the step's mob, it loots; in the step's quest window, it accepts or completes. Only out of combat, and only on the step the guide is at."],
		search = "interact, interact key, talk, loot, one button, keybind, hotkey" }
end
function C.hearthButton()
	return { kind = "toggle", key = "qol.hearthButton", label = L["Hearthstone button"],
		help = L["Shows your Hearthstone while the guide says to hearth. Bindable."], search = "hearth, hearthstone, keybind, hotkey" }
end

register(QUESTING, L["Buttons"], L["Action buttons"], {
	C.itemButton(),
	C.questLoot(),
	{ kind = "toggle", key = "qol.bagGlow", label = L["Highlight the step's item in your bags"],
		help = L["The item the current step uses, or a quest item it collects, glows in your bags (and in Baganator). An item a later step needs gets a lock, so you don't sell it."],
		search = "bags, glow, quest item, inventory" },
	{ kind = "toggle", key = "qol.targetButton", label = L["Target button"],
		help = L["Targets the current step's mobs by name, or the NPCs it sends you to when it has no mob; each click moves to the next name. Bindable."], search = "target macro, find mob, keybind, hotkey" },
	{ kind = "toggle", key = "qol.targetPlate", label = L["Show who it targets"], disabled = targetOff, child = true,
		help = L["The target button's icon shows what you do next: talk, accept, turn in, kill or loot, a skull for an elite, rare or boss, or their face once you have seen them. Their name sits beside it, green for a friendly NPC, red for a mob, gold for an elite or rare, with small icons for the names after it."],
		search = "target icon, target name, portrait, npc name, elite, boss" },
	{ kind = "toggle", key = "qol.targetAnnounce", label = L["Name new targets in chat"], disabled = targetOff, child = true,
		help = L["When the target button's names change, one line in chat lists them (\"Targeting: ...\"). Only you see it."],
		search = "target chat, announce target, targeting" },
	{ kind = "toggle", key = "qol.guideNameTarget", label = L["Click objectives to target"],
		help = L["Clicking an objective row or NPC heading also targets its NPC outside combat, using the same marking settings as the Target button. This replaces your current target; a failed search clears it."] },
	{ kind = "toggle", key = "qol.rareButton", label = L["Rare button"],
		help = L["Shows a button that targets a rare Polestar spotted nearby, until it dies or is out of sight. Bindable."], search = "rare elite, target rare, keybind" },
	C.hearthButton(),
	{ kind = "toggle", key = "qol.markTarget", label = L["Mark what they target"],
		help = L["The target button and the step key put a raid icon on the mob and the NPC they target; out of combat, a press that finds neither clears your target. Pressing again never takes an icon off. In a party you don't lead, only a unit with no icon gets one; in a raid, only when you lead or assist."],
		search = "raid marker, raid icon, skull, star, mark target" },
	{ kind = "toggle", key = "qol.pingTarget", label = L["Ping what they target"],
		help = L["The target button and the step key ping the mob they target, so your group sees it behind rocks and buildings. Never in a raid unless you lead or assist. The rare buttons always ping."],
		search = "ping, ping target, group ping" },
	{ kind = "dropdown", key = "qol.markMob", label = L["Icon on mobs"], choices = markChoices, disabled = markOff,
		help = L["A new one each press skips the NPCs' icon and leaves a mob that has one as it is."], search = "raid marker, raid icon, skull" },
	{ kind = "dropdown", key = "qol.markNpc", label = L["Icon on NPCs"], choices = markChoices, disabled = markOff,
		help = L["A new one each press, so the last few NPCs keep theirs. Every press counts, even one that marks nothing."], search = "raid marker, raid icon, star" },
	C.stepInteract(),
	{ kind = "slider", key = "qol.buttonScale", label = L["Button size"], min = 0.6, max = 1.6, step = 0.05, format = function(v) return math.floor(v * 100 + 0.5) .. "%" end,
		help = L["Scale of the quest item, Hearthstone, target and rare buttons. Drag one to move them all."], search = "scale, bigger, smaller, button scale" },
	{ kind = "dropdown", key = "qol.buttonTextSide", label = L["Target name position"], help = L["Where the target's name shows around the target button: right, left, above or below."],
		choices = { { value = "right", label = L["Right"] }, { value = "left", label = L["Left"] }, { value = "above", label = L["Above"] }, { value = "below", label = L["Below"] } } },
	{ kind = "button", icon = "reset", button = L["Reset"], label = L["Reset button positions"], help = L["Put the buttons back in their default spot."],
		search = "move buttons, button position", onClick = function() if QoL.Buttons then QoL.Buttons.ResetPositions() end end },
})

register(QUESTING, L["Rewards & gear"], L["Quest rewards"], {
	{ kind = "toggle", key = "qol.rewardHighlight", label = L["Mark quest rewards"],
		help = L["On the reward choices, a green arrow marks each upgrade for your spec (with Gear advice on), a thin frame in your accent colour the one to take, and a coin the one that sells for most."],
		search = "highlight reward, best reward, vendor price, upgrade" },
})

register(QUESTING, L["Quests"], L["Tooltips and quest log"], {
	{ kind = "button", button = L["Show"], label = L["Clean up quest log"],
		help = L["Lists the quests in your log the route doesn't need: those it never hands in, and grey ones that give no XP any more. Each has an Abandon button that asks first. The guide window's menu has it too while there are any."],
		onClick = function() ns.Fire("SHOW_QUEST_ROOM") end },
})

register(QOL, L["Quests"], L["Action buttons"], { C.itemButton(), C.questLoot(), C.stepInteract() })

register(QOL, L["Travel"], L["Flight masters"], {
	{ kind = "toggle", key = "qol.flightHighlight", label = L["Mark the route's destination"],
		help = L["Marks where the travel route flies next on the flight map. You still choose the flight."], search = "flight, taxi, flight path, highlight destination" },
})

register(QOL, L["Travel"], L["Hearthstone"], {
	C.hearthButton(),
})

register(QOL, L["Travel"], L["Death"], {
	{ kind = "toggle", key = "qol.deathHelper", label = L["Corpse or Spirit Healer"],
		help = L["As a ghost, points the arrow at the faster way back: your corpse or the nearest Spirit Healer."], search = "death, die, dead, ghost, corpse run, graveyard, spirit healer" },
	{ kind = "toggle", key = "qol.breathWarning", label = L["Warn when out of breath"],
		help = L["Under water, a red edge round the screen, a sound and a taskbar flash with 10 seconds of breath left, and again at 4."], search = "breath, drowning, underwater, swim" },
})

register(QOL, L["Vendors"], L["Trainers"], {
	{ kind = "toggle", key = "qol.ridingReminder", label = L["Riding reminder"],
		help = L["At level 40 and 60, if you have not learned riding yet, says the cost in chat (with any Honored discount) and points the arrow at your race's riding trainer when you can afford it. Warlocks and Alliance Paladins are sent to their free-mount quest NPC instead. Once per tier per character."],
		search = "mount, riding, horse, epic mount, level 40, level 60" },
	{ kind = "toggle", key = "qol.levelUpSpells", label = L["New spells at level-up"],
		help = L["When you level up, a card on the guide window shows the class spells you can now train, what they cost together and the nearest class trainer, with a button for the arrow. Not in combat or instances, and not on levels with nothing new."],
		search = "level up, ding, new spells, trainer, train, ranks, abilities, cost" },
	{ kind = "toggle", key = "qol.oldRanks", label = L["Old ranks on your bars"],
		help = L["After training and at login, says which spells on your action bars are a lower rank than the one in your spellbook, with a button that puts the highest rank in the same buttons (out of combat). Macros and items are never touched. Right-click a spell on the card to keep it at its rank; a lower rank you put on a bar yourself is kept too."],
		search = "rank, old rank, downrank, action bar, upgrade spells, highest rank, buttons" },
	{ kind = "button", icon = "reset", button = L["Forget"], label = L["Forget kept ranks"],
		help = L["Lists the spells you kept at a lower rank again."], search = "rank, downrank, keep rank, action bar",
		disabled = function() return not QoL.On("oldRanks") end,
		onClick = function() if QoL.Spells then QoL.Spells.ForgetKept(); QoL.Spells.CheckRanks(true) end end },
})

register(QOL, L["Trackers"], L["Experience"], {
	{ kind = "toggle", key = "qol.xpTracker", label = L["XP tracker"],
		help = L["XP per hour, time, kills and quests to level, and level splits (/pole xp)."], search = "experience, xp per hour, exp, leveling speed, time to level" },
	{ kind = "toggle", key = "qol.xpTargetMark", label = L["Guide level on the XP bar"],
		help = L["A mark at the end of the game's XP bar with the level the guide wants you to reach before it moves on, and how many levels away that is when it is more than one."],
		search = "experience bar, exp bar, target level" },
	{ kind = "toggle", key = "qol.boostedRest", label = L["Boosted Rest status"],
		help = L["How long the campfire's Boosted Rest lasts and the Cozy Sleeping Bag's cooldown, under the guide window's XP line; your party's Boosted Rest in the party panel."],
		search = "boosted rest, campfire, sit, rested, sleeping bag, camp, cozy sleeping bag" },
	{ kind = "button", icon = "reset", button = L["Reset"], label = L["Reset session"], help = L["Start this session's XP per hour from zero."], search = "xp, experience",
		onClick = function() if QoL.XP then QoL.XP.ResetSession() end end },
})

-- The Deck Shelf: your collection, your saved decks and the deck editor. Client only.
-- The server (MatchServer + PlayerDecks) owns the collection and the saved decks: this screen
-- shows the snapshot it gets and sends "GetDecks", "SaveDeck" and "DeleteDeck" back, and the
-- card actions "FuseCard", "FuseAll", "FuseEverything" and "SellCard" (answered by "CardResult").
--
-- The collection has two tabs: My cards (what you own, with each card's best level as pips and a
-- FUSE tag when two copies can fuse) and All cards (everything, the ones still to find dark).
-- Tapping an owned card opens its copies: one row per level with Fuse 2 -> next level and Sell.
--
--   DeckBuilderUI.init(kit)          -- once, from DeckWarsClient (its make/label/button/... helpers)
--   DeckBuilderUI.request()          -- ask the server for a fresh snapshot
--   DeckBuilderUI.snapshot()         -- the latest { cards, decks = { { slot, deck, ok, problems } }, slots }
--   DeckBuilderUI.onDecks(fn)        -- fn(snapshot) whenever a new one arrives
--   DeckBuilderUI.showShelf(body)    -- the right-hand station panel + the big left panel
--   DeckBuilderUI.hide()             -- closes the big left panel (leaving the station)
--
-- Deck rules live in DeckRules (shared with the server): 20-30 cards, at most 2 themes, 3 copies
-- (1 of each Legendary and Secret), and you can only use cards you own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local DeckRules = require(here:WaitForChild("DeckRules"))
local CardLevels = require(here:WaitForChild("CardLevels"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit"))
local Enchants = require(here:WaitForChild("Enchants"))
local EnchantFx = require(here:WaitForChild("EnchantFx"))

local rgb = Juice.rgb

local DeckBuilderUI = {}

local GOLD = rgb(255, 220, 90)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(176, 170, 196)
local GOOD = rgb(90, 200, 120)
local BAD = rgb(235, 110, 110)
local IDLE = rgb(70, 64, 100)
local TILE = rgb(42, 36, 62)
local INK = rgb(18, 14, 28)
local WHITE = Color3.new(1, 1, 1)

local kit = nil
local state = {
	snap = nil,
	listeners = {},
	body = nil, -- the station panel body while the shelf is open
	left = nil, -- the big left panel
	editing = nil, -- { slot, deck } working copy while the editor is open
	saved = nil, -- text under the Save button ("Saved", problems...)
	note = nil, -- a short line about the last click ("Took out 4 Snack cards")
	gridKey = nil, -- rebuild the card grid only when the themes change
	view = nil, -- "backgrounds" while the match backgrounds fill the left panel (BackdropPicker)
	tab = "mine", -- the collection shows "mine" (cards you own) or "all"
	detail = nil, -- the card whose copies are open (fuse and sell)
	anim = nil, -- what to play once the next snapshot is drawn ({ kind = "fuse", level }, ...)
	busy = false, -- a fuse or sell is on its way to the server
}

local function make(className, props, parent)
	return kit.make(className, props, parent)
end

local function text(parent, str, props)
	local base = { Font = kit.BODY_FONT, TextScaled = false, TextSize = 15, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	return kit.label(parent, str, base)
end

local function famColor(f)
	if f == "Any" then
		return rgb(200, 190, 170)
	end
	return kit.familyColor(f)
end

local function copyDeck(d)
	return {
		name = d.name,
		hero = d.hero,
		themes = table.clone(d.themes or {}),
		lanes = table.clone(d.lanes or {}),
		cards = table.clone(d.cards or {}),
	}
end

local function owned()
	return state.snap and state.snap.cards or {}
end

local function ownedCount(id)
	return owned()[id] or 0
end

local function uniqueOwned()
	local n = 0
	for _, id in ipairs(CardData.List) do
		if DeckRules.collectible(id) and ownedCount(id) > 0 then
			n += 1
		end
	end
	return n
end

local function collectibleTotal()
	local n = 0
	for _, id in ipairs(CardData.List) do
		if DeckRules.collectible(id) then
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------
-- Talking to the server
---------------------------------------------------------------------------

function DeckBuilderUI.request()
	kit.MenuAction:FireServer("GetDecks")
end

function DeckBuilderUI.snapshot()
	return state.snap
end

function DeckBuilderUI.onDecks(fn)
	table.insert(state.listeners, fn)
end

local redraw -- set below: repaints whatever part of the shelf is open

---------------------------------------------------------------------------
-- Sorting
---------------------------------------------------------------------------

local function sortedIds(themes)
	local rank = {}
	for i, f in ipairs(themes or {}) do
		rank[f] = i
	end
	rank.Any = 50
	local list = {}
	for _, id in ipairs(CardData.List) do
		if DeckRules.collectible(id) then
			table.insert(list, id)
		end
	end
	local famIndex = {}
	for i, f in ipairs(CardData.Families) do
		famIndex[f] = 10 + i
	end
	famIndex.Any = 50
	table.sort(list, function(a, b)
		local da, db = CardData.Cards[a], CardData.Cards[b]
		local ra = rank[da.family] or (famIndex[da.family] or 99) + 100
		local rb = rank[db.family] or (famIndex[db.family] or 99) + 100
		if ra ~= rb then
			return ra < rb
		end
		if da.cost ~= db.cost then
			return da.cost < db.cost
		end
		return da.name < db.name
	end)
	return list
end

local function clearLeft()
	for _, c in ipairs(state.left:GetChildren()) do
		if not c:IsA("UICorner") and not c:IsA("UIStroke") and not c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	state.gridKey = nil
end

---------------------------------------------------------------------------
-- Copies and levels (from the snapshot; the rules are CardLevels, shared with the server)
---------------------------------------------------------------------------

local function levelsOf(id)
	local list = state.snap and state.snap.levels and state.snap.levels[id]
	if list then
		return CardLevels.fromList(list)
	end
	local n = ownedCount(id)
	return n > 0 and { [1] = n } or {}
end

local function reservedOf(id)
	return (state.snap and state.snap.reserved and state.snap.reserved[id]) or 0
end

local function bestLevel(id)
	return math.max(1, CardLevels.best(levelsOf(id)))
end

-- How many fuses "Fuse all" would do for one card (or for every card).
local function fusesFor(id)
	return (CardLevels.fuseAll(id, table.clone(levelsOf(id)), reservedOf(id)))
end

local function fusesEverywhere()
	local n = 0
	for id in pairs(owned()) do
		n += fusesFor(id)
	end
	return n
end

local function storage()
	local st = state.snap and state.snap.storage
	if st then
		return st.used or 0, st.limit or CardLevels.StorageLimit
	end
	local n = 0
	for _, c in pairs(owned()) do
		n += c
	end
	return n, CardLevels.StorageLimit
end

---------------------------------------------------------------------------
-- The collection (left panel when you're not editing)
---------------------------------------------------------------------------

local function cardCell(parent, id, order)
	local cell = make("Frame", { Name = "Cell_" .. id, Size = UDim2.fromOffset(104, 168), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local card = kit.makeCard(cell, id, UDim2.fromOffset(104, 146), nil, nil, bestLevel(id))
	if ownedCount(id) > 0 then
		EnchantFx.decorateCard(card, state.snap and state.snap.enchants and state.snap.enchants[id])
	end
	local dim = make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 1, ZIndex = 20 }, card)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, dim)
	local badge = text(cell, "", { Name = "Badge", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, Font = Enum.Font.FredokaOne })
	return cell, dim, badge
end

-- A two-way switch: [ My cards | All cards ].
local function tabs(parent, props)
	local bar = make("Frame", { Name = "Tabs", Size = UDim2.fromOffset(230, 34), BackgroundColor3 = INK, BackgroundTransparency = 0.25 }, parent)
	for k, v in pairs(props or {}) do
		bar[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, bar)
	make("UIStroke", { Thickness = 1, Color = rgb(150, 118, 80), Transparency = 0.5 }, bar)
	local knob = make("Frame", { Name = "Knob", Size = UDim2.new(0.5, -4, 1, -6), Position = UDim2.new(state.tab == "all" and 0.5 or 0, 2, 0, 3), BackgroundColor3 = GOLD }, bar)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)
	for i, t in ipairs({ { "mine", "My cards" }, { "all", "All cards" } }) do
		local on = state.tab == t[1]
		local b = make("TextButton", {
			Name = "Tab_" .. t[1],
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale((i - 1) * 0.5, 0),
			BackgroundTransparency = 1,
			Text = t[2],
			Font = Enum.Font.FredokaOne,
			TextSize = 16,
			TextColor3 = on and INK or TEXT,
			ZIndex = 3,
		}, bar)
		b.Activated:Connect(function()
			if state.tab ~= t[1] then
				state.tab = t[1]
				Juice.sound("tick", 1.15, 0.35)
				UIKit.tween(knob, 0.25, { Position = UDim2.new(t[1] == "all" and 0.5 or 0, 2, 0, 3) })
				task.delay(0.12, redraw)
			end
		end)
	end
	return bar
end

-- Storage: "42 / 60" with a thin bar that warms up as it fills.
local function storageMeter(parent, props)
	local used, limit = storage()
	local box = make("Frame", { Name = "Storage", Size = UDim2.fromOffset(150, 36), BackgroundColor3 = TILE }, parent)
	for k, v in pairs(props or {}) do
		box[k] = v
	end
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
	local share = math.clamp(used / math.max(1, limit), 0, 1)
	local color = share >= 1 and BAD or (share >= 0.9 and rgb(255, 160, 70) or GOLD)
	text(box, "Storage", { Size = UDim2.new(0.5, 0, 0, 16), Position = UDim2.fromOffset(10, 3), TextSize = 12, TextColor3 = DIM })
	text(box, used .. " / " .. limit, { Name = "Count", Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.new(0.4, -10, 0, 2), TextSize = 15, Font = Enum.Font.FredokaOne, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Right })
	local back = make("Frame", { Name = "Bar", Size = UDim2.new(1, -20, 0, 5), Position = UDim2.new(0, 10, 1, -10), BackgroundColor3 = INK }, box)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, back)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(share, 1), BackgroundColor3 = color }, back)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	return box
end

-- A small gold "FUSE" tag on a card that can fuse right now.
local function fuseTag(card)
	local tag = make("TextLabel", {
		Name = "FuseTag",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 4, 0, -4),
		Size = UDim2.fromOffset(40, 18),
		BackgroundColor3 = GOLD,
		Text = "FUSE",
		Font = Enum.Font.FredokaOne,
		TextSize = 12,
		TextColor3 = INK,
		ZIndex = 26,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, tag)
	make("UIStroke", { Thickness = 1.5, Color = INK, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tag)
	Juice.breathe(tag, 0.06, 2.2)
	return tag
end

local openDetail -- set below

-- Sends a fuse or sell; nothing else can be tapped until the answer comes (or 4 seconds pass).
local function cardAction(what, options)
	state.busy = true
	local token = {}
	state.busyToken = token
	kit.MenuAction:FireServer(what, options)
	task.delay(4, function()
		if state.busyToken == token then
			state.busy = false
		end
	end)
end

local function showGrid()
	local left = state.left
	local total = collectibleTotal()
	local mine = state.tab ~= "all"
	text(left, "Your cards", { Size = UDim2.fromOffset(170, 34), Position = UDim2.fromOffset(14, 8), Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = GOLD })
	tabs(left, { Position = UDim2.fromOffset(186, 10) })
	-- right: storage and "Fuse all"
	local fuses = fusesEverywhere()
	local armed = false
	local fuseAll
	fuseAll = kit.button(left, fuses > 0 and ("Fuse all  " .. fuses) or "Nothing to fuse", fuses > 0 and rgb(214, 150, 60) or IDLE, function()
		if fuses == 0 or state.busy then
			return
		end
		if not armed then
			-- tap twice: fusing can't be undone
			armed = true
			fuseAll.Text = "Sure? " .. fuses .. " fuses"
			task.delay(2.5, function()
				armed = false
				if fuseAll.Parent then
					fuseAll.Text = "Fuse all  " .. fuses
				end
			end)
			return
		end
		cardAction("FuseEverything")
	end, { Name = "FuseEverything", Size = UDim2.fromOffset(150, 36), Position = UDim2.new(1, -14, 0, 10), AnchorPoint = Vector2.new(1, 0) })
	fuseAll.TextScaled = false
	fuseAll.TextSize = 15
	fuseAll.Font = Enum.Font.FredokaOne
	fuseAll.TextColor3 = fuses > 0 and INK or DIM
	storageMeter(left, { Position = UDim2.new(1, -174, 0, 10), AnchorPoint = Vector2.new(1, 0) })
	local used, limit = storage()
	local sub
	if not state.snap then
		sub = "Loading your cards..."
	elseif mine then
		local kinds = 0
		for id, n in pairs(owned()) do
			if n > 0 and DeckRules.collectible(id) then
				kinds += 1
			end
		end
		sub = kinds .. " different cards · " .. used .. " copies · tap a card to fuse or sell copies"
		if used >= limit then
			sub = "Storage is full: fuse or sell copies to open more packs"
		end
	else
		sub = uniqueOwned() .. " of " .. total .. " cards found · open packs at Pack Party for more"
	end
	local note = state.note
	state.note = nil
	text(left, note and note[1] or sub, { Name = "Sub", Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(14, 50), TextColor3 = note and note[2] or (used >= limit and BAD or DIM) })
	local scroll = make("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.new(1, -24, 1, -84),
		Position = UDim2.fromOffset(12, 76),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, left)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(104, 172), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8) }, scroll)
	-- owned first (in My cards, only owned), then the ones still to find (dark)
	local ids = sortedIds(nil)
	local shown = 0
	for i, id in ipairs(ids) do
		local have = ownedCount(id)
		if have > 0 or not mine then
			shown += 1
			local secret = CardData.Cards[id].rarity == "Secret" and have == 0
			local cell = make("TextButton", { Name = "Cell_" .. id, Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(104, 172), BackgroundTransparency = 1, LayoutOrder = (have > 0 and 0 or 1000) + i }, scroll)
			local card = kit.makeCard(cell, id, UDim2.fromOffset(104, 146), secret and "hidden" or nil, nil, have > 0 and bestLevel(id) or nil)
			if have == 0 then
				local dim = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.35, ZIndex = 20 }, card)
				make("UICorner", { CornerRadius = UDim.new(0, 10) }, dim)
			elseif fusesFor(id) > 0 then
				fuseTag(card)
			end
			text(cell, have > 0 and ("×" .. have) or "not found yet", {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.new(0, 0, 1, -18),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextSize = have > 0 and 15 or 12,
				Font = have > 0 and Enum.Font.FredokaOne or kit.BODY_FONT,
				TextColor3 = have > 0 and GOLD or DIM,
			})
			if have > 0 then
				Juice.button(cell, { grow = 1.04 })
				cell.Activated:Connect(function()
					openDetail(id)
				end)
			end
		end
	end
	if shown == 0 and state.snap then
		text(scroll, "No cards yet. Open packs at Pack Party!", { Size = UDim2.fromOffset(320, 40), TextColor3 = DIM })
	end
end

---------------------------------------------------------------------------
-- One card's copies: fuse and sell (left panel)
---------------------------------------------------------------------------

local RARE_SELL = { Epic = true, Mythic = true, Legendary = true, Secret = true }

local function detailNote(msg, color)
	state.note = { msg, color }
	local root = state.left:FindFirstChild("Detail")
	local note = root and root:FindFirstChild("Note", true)
	if note then
		note.Text = msg
		note.TextColor3 = color
	end
end

local function showDetail()
	local id = state.detail
	local d = CardData.Cards[id]
	local left = state.left
	local lv = levelsOf(id)
	local reserved = reservedOf(id)
	local max = CardLevels.maxLevel(id)
	local best = math.max(1, CardLevels.best(lv))
	local root = make("Frame", { Name = "Detail", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, left)
	local back = kit.button(root, "‹  Back", TILE, function()
		state.detail = nil
		state.note = nil
		Juice.sound("tick", 0.9, 0.35)
		redraw()
	end, { Name = "Back", Size = UDim2.fromOffset(96, 34), Position = UDim2.fromOffset(14, 12) })
	back.TextScaled = false
	back.TextSize = 16
	back.Font = Enum.Font.GothamBold
	-- the big card
	local stage = make("Frame", { Name = "Stage", Size = UDim2.fromOffset(220, 308), Position = UDim2.fromOffset(24, 62), BackgroundTransparency = 1 }, root)
	local big = kit.makeCard(stage, id, UDim2.fromScale(1, 1), nil, nil, best)
	big.Name = "BigCard"
	local enchant = state.snap and state.snap.enchants and state.snap.enchants[id]
	EnchantFx.decorateCard(big, enchant, { gem = 28 })
	-- the right column
	local col = make("ScrollingFrame", {
		Name = "Info",
		Size = UDim2.new(1, -290, 1, -24),
		Position = UDim2.fromOffset(270, 12),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, root)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, col)
	text(col, d.name, { Size = UDim2.new(1, -8, 0, 32), Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = GOLD, LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd })
	local rc = CardData.RarityColors[d.rarity]
	text(col, d.rarity .. " · " .. d.type .. (d.family ~= "Any" and (" · " .. d.family) or ""), { Size = UDim2.new(1, -8, 0, 18), TextSize = 14, TextColor3 = rc and rgb(rc[1], rc[2], rc[3]) or DIM, Font = kit.BODY_FONT, LayoutOrder = 2 })
	-- what its level does
	local info = make("Frame", { Name = "Bonus", Size = UDim2.new(1, -8, 0, 74), BackgroundColor3 = TILE, LayoutOrder = 3 }, col)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, info)
	UIKit.levelPips(info, best, max, { Size = UDim2.fromOffset(0, 18), Position = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0, 0) })
	text(info, "Level " .. best .. " of " .. max .. (best >= max and "  ·  MAX" or ""), { Size = UDim2.new(1, -120, 0, 20), Position = UDim2.fromOffset(110, 10), Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = best >= max and GOLD or TEXT })
	local nextL, nextText = CardLevels.nextStep(id, best)
	local now = CardLevels.bonusText(id, best)
	local line = (now ~= "no bonus" and ("Now: " .. now) or "No bonus yet") .. (nextL and ("   ·   Lv " .. nextL .. ": " .. nextText) or "")
	text(info, line, { Name = "BonusLine", Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 34), TextSize = 14, TextColor3 = TEXT })
	text(info, CardLevels.InDuels and "Counts in every match." or "Counts against bots and in the Campaign. Duels with players use printed numbers.", { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 53), TextSize = 12, TextColor3 = DIM, TextTruncate = Enum.TextTruncate.AtEnd })
	-- its enchant (put on at the Enchanting Crystal in the Park)
	if Enchants.canEnchant(id) then
		local e = Enchants.get(enchant)
		local box = make("Frame", { Name = "Enchant", Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = TILE, LayoutOrder = 4 }, col)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
		if e then
			local c = EnchantFx.color(e.rarity)
			make("UIStroke", { Thickness = 2, Color = c, Transparency = 0.2 }, box)
			text(box, "◆ " .. e.name .. "  ·  " .. e.rarity, { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 4), Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = c })
			text(box, e.text, { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 24), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
		else
			text(box, "◆ No enchant", { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 4), Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = DIM })
			text(box, "Enchant it at the big crystal in the middle of the Park.", { Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 24), TextSize = 13, TextColor3 = DIM, TextTruncate = Enum.TextTruncate.AtEnd })
		end
	end
	-- one row per level
	text(col, "Copies  ·  " .. CardLevels.total(lv) .. (reserved > 0 and ("  ·  your decks use " .. reserved) or ""), { Size = UDim2.new(1, -8, 0, 22), Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = TEXT, LayoutOrder = 5 })
	for l = 1, max do
		local c = lv[l] or 0
		local row = make("Frame", { Name = "Level_" .. l, Size = UDim2.new(1, -8, 0, 44), BackgroundColor3 = c > 0 and TILE or INK, BackgroundTransparency = c > 0 and 0 or 0.5, LayoutOrder = 10 + l }, col)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, row)
		UIKit.levelPips(row, l, max, { Size = UDim2.fromOffset(0, 16), Position = UDim2.new(0, 12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
		text(row, "Lv " .. l, { Size = UDim2.fromOffset(46, 20), Position = UDim2.new(0, 104, 0.5, -10), Font = Enum.Font.FredokaOne, TextSize = 16, TextColor3 = c > 0 and TEXT or DIM })
		text(row, "×" .. c, { Name = "Count", Size = UDim2.fromOffset(46, 20), Position = UDim2.new(0, 150, 0.5, -10), Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = c > 0 and GOLD or DIM })
		-- Sell one (right) and Fuse two (left of it)
		local canSell, sellWhy = CardLevels.canSell(id, lv, l, reserved)
		if c > 0 then
			local value = CardLevels.sellValue(id, l)
			local armed = false
			local sell
			sell = kit.button(row, "", canSell and rgb(96, 70, 52) or IDLE, function()
				if state.busy then
					return
				end
				if not canSell then
					detailNote(sellWhy or "Can't sell that copy", BAD)
					return
				end
				if RARE_SELL[d.rarity] and not armed then
					armed = true
					UIKit.caption(sell, nil, "Sure?")
					task.delay(2.5, function()
						armed = false
						if sell.Parent then
							UIKit.caption(sell, "Coins", tostring(value))
						end
					end)
					return
				end
				cardAction("SellCard", { id = id, level = l })
			end, { Name = "Sell_" .. l, Size = UDim2.fromOffset(86, 32), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
			sell.TextScaled = false
			sell.TextSize = 15
			sell.Font = Enum.Font.FredokaOne
			sell.TextColor3 = canSell and TEXT or DIM
			UIKit.caption(sell, "Coins", tostring(value))
		end
		if l < max and c > 0 then
			local canFuse, fuseWhy = CardLevels.canFuse(id, lv, l, reserved)
			local fuse = kit.button(row, "Fuse 2 → Lv " .. (l + 1), canFuse and rgb(214, 150, 60) or IDLE, function()
				if state.busy then
					return
				end
				if not canFuse then
					detailNote(fuseWhy or "Can't fuse yet", c >= 2 and BAD or DIM)
					return
				end
				cardAction("FuseCard", { id = id, level = l })
			end, { Name = "Fuse_" .. l, Size = UDim2.fromOffset(120, 32), Position = UDim2.new(1, -102, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
			fuse.TextScaled = false
			fuse.TextSize = 14
			fuse.Font = Enum.Font.GothamBold
			fuse.TextColor3 = canFuse and INK or DIM
		elseif l >= max then
			text(row, c > 0 and "Max level" or "", { Size = UDim2.fromOffset(120, 20), Position = UDim2.new(1, -102, 0.5, -10), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.FredokaOne, TextSize = 14, TextColor3 = GOLD })
		end
	end
	-- Fuse everything of this card
	local n = fusesFor(id)
	local all = kit.button(col, n > 0 and ("Fuse all  ·  " .. n .. (n == 1 and " fuse" or " fuses")) or "Nothing to fuse", n > 0 and rgb(214, 150, 60) or IDLE, function()
		if n == 0 or state.busy then
			return
		end
		cardAction("FuseAll", { id = id })
	end, { Name = "FuseAllCard", Size = UDim2.new(1, -8, 0, 40), LayoutOrder = 30 })
	all.TextScaled = false
	all.TextSize = 17
	all.Font = Enum.Font.FredokaOne
	all.TextColor3 = n > 0 and INK or DIM
	local msg = state.note
	text(col, msg and msg[1] or (reserved > 0 and ("Your best " .. reserved .. " stay safe for your decks. Two copies of the same level fuse into one a level higher.") or "Two copies of the same level fuse into one a level higher."), {
		Name = "Note",
		Size = UDim2.new(1, -8, 0, 36),
		TextWrapped = true,
		TextSize = 13,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = msg and msg[2] or DIM,
		LayoutOrder = 31,
	})
end

function openDetail(id)
	state.detail = id
	state.note = nil
	Juice.sound("tick", 1.2, 0.4)
	redraw()
end

-- The fuse: two ghost copies slide into the card, a flash, the card pops a level up and the new
-- pip lights; at the max level, confetti.
local function playFuse(levelTo, many)
	local root = state.left:FindFirstChild("Detail")
	local stage = root and root:FindFirstChild("Stage")
	local big = stage and stage:FindFirstChild("BigCard")
	if not big then
		return
	end
	local id = state.detail
	local max = CardLevels.maxLevel(id)
	local from = math.max(1, levelTo - 1)
	local pips = big:FindFirstChild("LevelPips")
	if pips then
		UIKit.setPips(pips, from, max, false)
	end
	big.Visible = false
	local ghosts = {}
	for i, side in ipairs({ -1, 1 }) do
		local g = make("Frame", { Name = "Ghost" .. i, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(side * 70, 10), Rotation = side * 9, BackgroundTransparency = 1, ZIndex = 30 }, stage)
		kit.makeCard(g, id, UDim2.fromScale(1, 1), nil, true, from)
		table.insert(ghosts, g)
		UIKit.tween(g, 0.32, { Position = UDim2.fromOffset(0, 0), Rotation = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	end
	Juice.sound("whoosh", 1.25, 0.45)
	task.delay(0.32, function()
		for _, g in ipairs(ghosts) do
			g:Destroy()
		end
		if not big.Parent then
			return
		end
		big.Visible = true
		local flash = make("Frame", { Name = "FuseFlash", Size = UDim2.new(1, 16, 1, 16), Position = UDim2.fromOffset(-8, -8), BackgroundColor3 = rgb(255, 246, 214), BackgroundTransparency = 0, ZIndex = 40 }, stage)
		make("UICorner", { CornerRadius = UDim.new(0, 14) }, flash)
		UIKit.tween(flash, 0.45, { BackgroundTransparency = 1 }).Completed:Connect(function()
			flash:Destroy()
		end)
		local sc = Juice.scaleOf(big)
		sc.Scale = 1.18
		UIKit.tween(sc, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		if pips then
			UIKit.setPips(pips, levelTo, max, true)
		end
		Juice.sound("pop", 0.9 + levelTo * 0.08, 0.6)
		Juice.sound("charge", 1.2 + levelTo * 0.05, 0.3)
		Juice.stars(stage, 0.5, 0.5, 10, { text = "★", size = 20, color = GOLD, speed = 0.8, zIndex = 45 })
		if levelTo >= max then
			Juice.sound("choir", 1.05, 0.5)
			Juice.confetti(state.left, 0.2, 0.45, 40, { zIndex = 60 })
			local stamp = make("TextLabel", { Name = "MaxStamp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(160, 50), BackgroundTransparency = 1, Text = "MAX LEVEL", Font = Enum.Font.FredokaOne, TextSize = 34, TextColor3 = GOLD, Rotation = -8, ZIndex = 50 }, stage)
			make("UIStroke", { Thickness = 3, Color = INK }, stamp)
			Juice.popIn(stamp, 0, { twist = -20, sound = false })
			task.delay(1.6, function()
				if stamp.Parent then
					UIKit.tween(stamp, 0.4, { TextTransparency = 1 })
					task.delay(0.4, function()
						stamp:Destroy()
					end)
				end
			end)
		elseif many and many > 1 then
			local tag = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(160, 40), BackgroundTransparency = 1, Text = many .. " fuses!", Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = GOLD, ZIndex = 50 }, stage)
			make("UIStroke", { Thickness = 2.5, Color = INK }, tag)
			Juice.popIn(tag, 0, { sound = false })
			task.delay(1.2, function()
				tag:Destroy()
			end)
		end
	end)
end

-- Selling: the count ticks down and the Coins float up.
local function playSell(level, coins)
	local root = state.left:FindFirstChild("Detail")
	local row = root and root:FindFirstChild("Level_" .. level, true)
	local host = row or state.left
	local f = make("Frame", { Name = "SoldCoins", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -20, 0.5, 0), Size = UDim2.fromOffset(110, 26), BackgroundTransparency = 1, ZIndex = 40 }, host)
	local t = make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Font = Enum.Font.FredokaOne, TextSize = 20, TextColor3 = rgb(255, 214, 90), TextStrokeTransparency = 0.4, ZIndex = 40 }, f)
	UIKit.caption(t, "Coins", "+" .. tostring(coins))
	UIKit.tween(f, 0.9, { Position = UDim2.new(1, -20, 0.5, -34) })
	task.delay(0.6, function()
		for _, x in ipairs(f:GetDescendants()) do
			if x:IsA("TextLabel") then
				UIKit.tween(x, 0.3, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end
		end
		task.delay(0.35, function()
			f:Destroy()
		end)
	end)
	Juice.sound("pop", 1.5, 0.45)
	Juice.sound("tick", 1.6, 0.35)
	local count = row and row:FindFirstChild("Count")
	if count then
		Juice.pop(count, 1.35, 0.4)
	end
end

local function showCollection()
	clearLeft()
	if state.detail and ownedCount(state.detail) > 0 then
		showDetail()
	else
		state.detail = nil
		showGrid()
	end
	local anim = state.anim
	state.anim = nil
	if anim and state.detail then
		if anim.kind == "fuse" then
			playFuse(anim.level, anim.count)
		elseif anim.kind == "sell" then
			playSell(anim.level, anim.coins)
		end
	elseif anim and anim.kind == "fuseAll" then
		Juice.sound("charge", 1.3, 0.4)
		Juice.sound("pop", 1.2, 0.5)
		Juice.confetti(state.left, 0.5, 0.3, 30, { zIndex = 60 })
		local grid = state.left:FindFirstChild("Grid")
		if grid then
			for _, cell in ipairs(grid:GetChildren()) do
				if cell:IsA("GuiObject") and cell:FindFirstChild("Card") then
					Juice.pop(cell.Card, 1.08, 0.5)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- The deck editor (left panel)
---------------------------------------------------------------------------

local function editingDeck()
	return state.editing and state.editing.deck
end

local function deckCounts()
	return DeckRules.counts(editingDeck().cards)
end

-- Can one more copy of `id` go in? Returns ok, why-not.
local function canAdd(id)
	local deck = editingDeck()
	local d = CardData.Cards[id]
	local have = deckCounts()[id] or 0
	if #deck.cards >= DeckRules.MaxCards then
		return false, "The deck is full (" .. DeckRules.MaxCards .. " cards)"
	end
	if have >= ownedCount(id) then
		return false, ownedCount(id) == 0 and ("You don't own " .. d.name .. " yet") or ("You only own " .. ownedCount(id) .. " " .. d.name)
	end
	if have >= DeckRules.copyLimit(id) then
		return false, DeckRules.copyLimit(id) == 1 and (d.name .. " is one of a kind: 1 per deck") or ("3 copies of a card at most")
	end
	if not DeckRules.fits(id, deck.themes) then
		if #deck.themes >= DeckRules.MaxThemes then
			return false, d.family .. " isn't one of this deck's themes (take one out to swap)"
		end
		return true, nil, d.family -- adding it adds its theme
	end
	return true
end

local function setThemes(deck, themes)
	-- a new theme gets its share of the lanes (2 and 2); taking one out keeps the lanes that still fit
	local grew = #themes > #(deck.themes or {})
	deck.themes = themes
	deck.lanes = DeckRules.fixLanes(themes, (not grew) and deck.lanes or nil)
end

local function addCard(id)
	local deck = editingDeck()
	local ok, why, newTheme = canAdd(id)
	if not ok then
		state.note = { why, BAD }
		redraw()
		return
	end
	if newTheme then
		local t = table.clone(deck.themes)
		table.insert(t, newTheme)
		setThemes(deck, t)
		state.note = { "Added the " .. newTheme .. " theme (" .. (CardData.Terrains[newTheme] or newTheme) .. ")", GOOD }
	else
		state.note = nil
	end
	table.insert(deck.cards, id)
	state.saved = nil
	Juice.sound("tick", 1.1, 0.4)
	redraw()
end

local function removeCard(id)
	local deck = editingDeck()
	for i = #deck.cards, 1, -1 do
		if deck.cards[i] == id then
			table.remove(deck.cards, i)
			break
		end
	end
	state.saved = nil
	state.note = nil
	Juice.sound("tick", 0.85, 0.35)
	redraw()
end

local function toggleTheme(f)
	local deck = editingDeck()
	local themes = table.clone(deck.themes)
	local at = table.find(themes, f)
	if at then
		table.remove(themes, at)
		local kept, out = {}, 0
		for _, id in ipairs(deck.cards) do
			if CardData.Cards[id].family == f then
				out += 1
			else
				table.insert(kept, id)
			end
		end
		deck.cards = kept
		state.note = out > 0 and { "Took out " .. out .. " " .. f .. " card" .. (out == 1 and "" or "s"), DIM } or nil
	elseif #themes >= DeckRules.MaxThemes then
		state.note = { "A deck uses at most " .. DeckRules.MaxThemes .. " themes. Take one out first.", BAD }
		redraw()
		return
	else
		table.insert(themes, f)
		state.note = nil
	end
	setThemes(deck, themes)
	state.saved = nil
	redraw()
end

local function cycleLane(i)
	local deck = editingDeck()
	local n = #deck.themes
	if n < 2 then
		return
	end
	local at = table.find(deck.themes, deck.lanes[i]) or 0
	deck.lanes[i] = deck.themes[at % n + 1]
	state.saved = nil
	state.gridKey = nil -- repaint the lane chips
	redraw()
end

local function chip(parent, str, color, on, onClick, props)
	local b = kit.button(parent, str, on and color or color:Lerp(rgb(30, 25, 46), 0.7), onClick, props)
	b.TextScaled = false
	b.TextSize = 14
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = on and INK or TEXT
	return b
end

local function showEditor()
	local deck = editingDeck()
	local left = state.left
	local key = table.concat(deck.themes, "+")
	local counts = deckCounts()
	local ok, problems = DeckRules.validate(deck, owned())
	if state.gridKey ~= key or not left:FindFirstChild("Editor") then
		clearLeft()
		state.gridKey = key
		local root = make("Frame", { Name = "Editor", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, left)
		-- top bar: name, hero, buttons
		local nameBox = make("TextBox", {
			Name = "DeckName",
			Size = UDim2.new(0.34, 0, 0, 36),
			Position = UDim2.fromOffset(14, 10),
			BackgroundColor3 = TILE,
			Text = deck.name or "",
			PlaceholderText = "Deck name",
			ClearTextOnFocus = false,
			Font = Enum.Font.FredokaOne,
			TextSize = 22,
			TextColor3 = GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, root)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, nameBox)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10) }, nameBox)
		nameBox.FocusLost:Connect(function()
			local s = string.sub(nameBox.Text, 1, DeckRules.MaxNameLength)
			nameBox.Text = s
			if editingDeck() then
				editingDeck().name = s
				state.saved = nil
			end
		end)
		local heroRow = make("Frame", { Name = "Heroes", Size = UDim2.new(0.3, 0, 0, 36), Position = UDim2.new(0.34, 24, 0, 10), BackgroundTransparency = 1 }, root)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, heroRow)
		for _, h in ipairs(DeckRules.Heroes) do
			local hero = CardData.Heroes[h]
			chip(heroRow, hero and hero.name or h, GOLD, deck.hero == h, function()
				editingDeck().hero = h
				state.saved = nil
				state.gridKey = nil
				redraw()
			end, { Name = "Hero_" .. h, Size = UDim2.new(0.5, -3, 1, 0) })
		end
		-- (a drawn ✕: Roblox's fonts have none)
		UIKit.closeButton(root, function()
			state.editing = nil
			state.saved, state.note = nil, nil
			redraw()
		end, { Name = "CloseEditor", Size = UDim2.fromOffset(38, 38), Position = UDim2.new(1, -54, 0, 9) })
		-- themes and lanes
		text(root, "Themes (up to " .. DeckRules.MaxThemes .. ")", { Size = UDim2.new(0.5, 0, 0, 18), Position = UDim2.fromOffset(14, 52), TextColor3 = DIM, TextSize = 13 })
		local themeRow = make("Frame", { Name = "Themes", Size = UDim2.new(1, -28, 0, 30), Position = UDim2.fromOffset(14, 70), BackgroundTransparency = 1 }, root)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, themeRow)
		for _, f in ipairs(CardData.Families) do
			chip(themeRow, f, famColor(f), table.find(deck.themes, f) ~= nil, function()
				toggleTheme(f)
			end, { Name = "Theme_" .. f, Size = UDim2.new(1 / #CardData.Families, -5, 1, 0) })
		end
		text(root, "Lanes, left to right from your chair (your creatures get +1 attack on their own family's terrain)", { Size = UDim2.new(1, -28, 0, 18), Position = UDim2.fromOffset(14, 104), TextColor3 = DIM, TextSize = 13 })
		local laneRow = make("Frame", { Name = "Lanes", Size = UDim2.new(1, -28, 0, 30), Position = UDim2.fromOffset(14, 122), BackgroundTransparency = 1 }, root)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, laneRow)
		for i = 1, CardData.Cols do
			local f = deck.lanes[i]
			local label = f and (i .. ": " .. (CardData.Terrains[f] or f)) or (i .. ": pick a theme")
			chip(laneRow, label, f and famColor(f) or IDLE, f ~= nil, function()
				cycleLane(i)
			end, { Name = "Lane_" .. i, Size = UDim2.new(1 / CardData.Cols, -5, 1, 0) })
		end
		-- the card pool (left) and the deck list (right)
		local pool = make("ScrollingFrame", {
			Name = "Pool",
			Size = UDim2.new(0.64, -14, 1, -168),
			Position = UDim2.fromOffset(12, 160),
			BackgroundTransparency = 1,
			ScrollBarThickness = 8,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, root)
		make("UIGridLayout", { CellSize = UDim2.fromOffset(104, 168), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, pool)
		make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4) }, pool)
		local order = 0
		for _, id in ipairs(sortedIds(deck.themes)) do
			if ownedCount(id) > 0 and (#deck.themes < DeckRules.MaxThemes or DeckRules.fits(id, deck.themes)) then
				order += 1
				local cell = cardCell(pool, id, order)
				local hit = make("TextButton", { Name = "Add", Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 30 }, cell)
				hit.Activated:Connect(function()
					addCard(id)
				end)
			end
		end
		if order == 0 then
			text(pool, "No cards of these themes yet. Open packs at Pack Party!", { Size = UDim2.fromOffset(300, 40), TextColor3 = DIM, TextWrapped = true })
		end
		local side = make("Frame", { Name = "Side", Size = UDim2.new(0.36, -14, 1, -168), Position = UDim2.new(0.64, 2, 0, 160), BackgroundColor3 = TILE, BackgroundTransparency = 0.2 }, root)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, side)
		text(side, "", { Name = "Count", Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 6), Font = Enum.Font.FredokaOne, TextSize = 20 })
		local list = make("ScrollingFrame", {
			Name = "List",
			Size = UDim2.new(1, -8, 1, -196),
			Position = UDim2.fromOffset(4, 34),
			BackgroundTransparency = 1,
			ScrollBarThickness = 6,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, side)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		text(side, "", { Name = "Problems", Size = UDim2.new(1, -16, 0, 64), Position = UDim2.new(0, 8, 1, -158), TextWrapped = true, TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top })
		text(side, "", { Name = "Note", Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 1, -92), TextWrapped = true, TextSize = 12, TextColor3 = DIM, TextYAlignment = Enum.TextYAlignment.Top })
		local buttons = make("Frame", { Name = "Buttons", Size = UDim2.new(1, -16, 0, 52), Position = UDim2.new(0, 8, 1, -60), BackgroundTransparency = 1 }, side)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, buttons)
		local fill = kit.button(buttons, "Fill up", rgb(70, 110, 190), function()
			local d = editingDeck()
			if #d.themes == 0 then
				state.note = { "Pick a theme first", BAD }
			else
				local before = #d.cards
				d.cards = DeckRules.autoFill(d, owned(), DeckRules.MinCards)
				local added = #d.cards - before
				state.note = added > 0 and { "Added " .. added .. " card" .. (added == 1 and "" or "s"), GOOD } or { "Nothing more to add from your collection", DIM }
				state.saved = nil
			end
			redraw()
		end, { Name = "FillUp", Size = UDim2.new(0.5, -3, 1, 0) })
		fill.TextScaled = false
		fill.TextSize = 16
		local save = kit.button(buttons, "Save", rgb(60, 170, 90), function()
			local e = state.editing
			if not e then
				return
			end
			state.saved = { "Saving...", DIM }
			kit.MenuAction:FireServer("SaveDeck", { slot = e.slot, deck = e.deck })
			redraw()
		end, { Name = "SaveDeck", Size = UDim2.new(0.5, -3, 1, 0) })
		save.TextScaled = false
		save.TextSize = 18
	end
	-- the parts that change with every click
	local root = left:FindFirstChild("Editor")
	local pool = root:FindFirstChild("Pool")
	for _, cell in ipairs(pool:GetChildren()) do
		local id = cell:IsA("Frame") and string.match(cell.Name, "^Cell_(.+)$")
		if id then
			local inDeck = counts[id] or 0
			local can = canAdd(id)
			local badge = cell:FindFirstChild("Badge")
			badge.Text = inDeck .. " in deck · own " .. ownedCount(id)
			badge.TextColor3 = inDeck > 0 and GOLD or DIM
			local dim = cell:FindFirstChild("Card") and cell.Card:FindFirstChild("Dim")
			if dim then
				dim.BackgroundTransparency = can and 1 or 0.5
			end
		end
	end
	local side = root:FindFirstChild("Side")
	local n = #deck.cards
	local count = side:FindFirstChild("Count")
	count.Text = "Cards " .. n .. " / " .. DeckRules.MinCards .. "-" .. DeckRules.MaxCards
	count.TextColor3 = (n >= DeckRules.MinCards and n <= DeckRules.MaxCards) and GOOD or GOLD
	local list = side:FindFirstChild("List")
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local ids = {}
	for id in pairs(counts) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local da, db = CardData.Cards[a], CardData.Cards[b]
		if da.cost ~= db.cost then
			return da.cost < db.cost
		end
		return da.name < db.name
	end)
	for i, id in ipairs(ids) do
		local d = CardData.Cards[id]
		local row = make("TextButton", {
			Name = "Row_" .. id,
			Text = "",
			AutoButtonColor = true,
			Size = UDim2.new(1, -8, 0, 26),
			BackgroundColor3 = famColor(d.family):Lerp(rgb(30, 25, 46), 0.55),
			LayoutOrder = i,
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
		text(row, d.cost .. "  " .. d.name, { Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(8, 0), TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd })
		text(row, "×" .. counts[id], { Size = UDim2.new(0, 36, 1, 0), Position = UDim2.new(1, -40, 0, 0), TextSize = 14, Font = Enum.Font.FredokaOne, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right })
		row.Activated:Connect(function()
			removeCard(id)
		end)
	end
	if #ids == 0 then
		local hint = make("TextButton", { Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.new(1, -8, 0, 60) }, list)
		text(hint, "Tap cards on the left to add them. Tap a card here to take one out.", { TextWrapped = true, TextColor3 = DIM, TextSize = 13 })
	end
	local probs = side:FindFirstChild("Problems")
	if ok then
		probs.Text = "✓ Ready to play"
		probs.TextColor3 = GOOD
	else
		local shown = {}
		for i = 1, math.min(3, #problems) do
			table.insert(shown, "• " .. problems[i])
		end
		probs.Text = table.concat(shown, "\n")
		probs.TextColor3 = BAD
	end
	local note = side:FindFirstChild("Note")
	local msg = state.saved or state.note
	note.Text = msg and msg[1] or "Unfinished decks can be saved too, but only ready ones can be played."
	note.TextColor3 = msg and msg[2] or DIM
	-- hero chips repaint through a rebuild (rare), the rest stays put
end

---------------------------------------------------------------------------
-- The right-hand panel: your deck slots
---------------------------------------------------------------------------

local function themeLine(deck)
	local names = {}
	for _, f in ipairs(deck.themes or {}) do
		table.insert(names, f)
	end
	return #names > 0 and table.concat(names, " + ") or "no theme"
end

local function openEditor(slot, deck)
	state.view = nil
	state.editing = { slot = slot, deck = copyDeck(deck) }
	state.editing.deck.lanes = DeckRules.fixLanes(state.editing.deck.themes, state.editing.deck.lanes)
	state.saved, state.note, state.gridKey = nil, nil, nil
	redraw()
end

local function showSlots()
	local body = state.body
	if not body or not body.Parent then
		return
	end
	for _, c in ipairs(body:GetChildren()) do
		c:Destroy()
	end
	local scroll = make("ScrollingFrame", { Name = "DeckSlots", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollBarThickness = 6 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	local snap = state.snap
	if not snap then
		text(scroll, "Loading your decks...", { Size = UDim2.new(1, -8, 0, 30), TextColor3 = DIM })
		return
	end
	-- Match backgrounds: the world around the table in your matches (BackdropPicker fills the big
	-- panel while they're open).
	do
		local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
		local Backdrops = require(here:WaitForChild("Backdrops"))
		local Cosmetics = require(here:WaitForChild("Cosmetics"))
		local worn = ShopCatalog.CosmeticById[Cosmetics.equipped().backdrop or ""] or ShopCatalog.CosmeticById[ShopCatalog.DefaultEquipped.backdrop]
		local info = worn and Backdrops.ByKey[worn.backdrop]
		local open = state.view == "backgrounds"
		local bg = make("TextButton", { Name = "Backgrounds", Size = UDim2.new(1, -8, 0, 58), BackgroundColor3 = open and rgb(70, 58, 30) or TILE, AutoButtonColor = false, Text = "", LayoutOrder = -1 }, scroll)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, bg)
		make("UIStroke", { Thickness = open and 2 or 1, Color = open and GOLD or rgb(90, 80, 120), Transparency = open and 0 or 0.4 }, bg)
		local sw = make("Frame", { Size = UDim2.fromOffset(42, 42), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = WHITE }, bg)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, sw)
		if info then
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new(info.colors[1], info.colors[2]) }, sw)
			text(sw, info.emoji, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center })
		end
		text(bg, "🌄 Match background", { Size = UDim2.new(1, -70, 0, 22), Position = UDim2.fromOffset(60, 7), Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = GOLD })
		text(bg, (worn and worn.name or "Card Den") .. (open and "  ·  pick one on the left" or "  ·  tap to change"), { Size = UDim2.new(1, -70, 0, 18), Position = UDim2.fromOffset(60, 31), TextSize = 13, TextColor3 = DIM, TextTruncate = Enum.TextTruncate.AtEnd })
		bg.Activated:Connect(function()
			state.view = (state.view == "backgrounds") and nil or "backgrounds"
			if state.view then
				state.editing = nil
			end
			state.gridKey = nil
			redraw()
		end)
		Juice.button(bg, { grow = 1.02 })
	end
	text(scroll, "My decks", { Size = UDim2.new(1, -8, 0, 26), Font = Enum.Font.FredokaOne, TextSize = 22, TextColor3 = GOLD, LayoutOrder = 0 })
	local bySlot = {}
	for _, d in ipairs(snap.decks or {}) do
		bySlot[d.slot] = d
	end
	for slot = 1, snap.slots or DeckRules.DefaultDeckSlots do
		local d = bySlot[slot]
		local editingThis = state.editing and state.editing.slot == slot
		local card = make("Frame", { Name = "Slot_" .. slot, Size = UDim2.new(1, -8, 0, 84), BackgroundColor3 = editingThis and rgb(70, 60, 30) or TILE, LayoutOrder = slot }, scroll)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
		if d then
			local fam = d.deck.themes[1]
			local strip = make("Frame", { Size = UDim2.new(0, 6, 1, -16), Position = UDim2.fromOffset(6, 8), BackgroundColor3 = fam and famColor(fam) or IDLE }, card)
			make("UICorner", { CornerRadius = UDim.new(0, 3) }, strip)
			text(card, d.deck.name, { Size = UDim2.new(1, -150, 0, 24), Position = UDim2.fromOffset(20, 6), Font = Enum.Font.FredokaOne, TextSize = 19, TextColor3 = TEXT, TextTruncate = Enum.TextTruncate.AtEnd })
			local hero = CardData.Heroes[d.deck.hero]
			text(card, themeLine(d.deck) .. " · " .. #d.deck.cards .. " cards · " .. (hero and hero.name or "?"), { Size = UDim2.new(1, -150, 0, 18), Position = UDim2.fromOffset(20, 32), TextSize = 13, TextColor3 = DIM })
			text(card, d.ok and "✓ Ready to play" or ("⚠ " .. tostring(d.problems and d.problems[1] or "Not finished")), {
				Size = UDim2.new(1, -150, 0, 30),
				Position = UDim2.fromOffset(20, 50),
				TextSize = 12,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextColor3 = d.ok and GOOD or GOLD,
			})
			local edit = kit.button(card, "Edit", rgb(70, 110, 190), function()
				openEditor(slot, d.deck)
			end, { Name = "Edit_" .. slot, Size = UDim2.fromOffset(60, 34), Position = UDim2.new(1, -132, 0.5, -17) })
			edit.TextScaled = false
			edit.TextSize = 15
			local armed = false
			local del
			del = kit.button(card, "🗑", rgb(110, 60, 70), function()
				if not armed then
					-- tap twice: deleting a deck can't be undone
					armed = true
					del.Text = "Sure?"
					task.delay(2.5, function()
						armed = false
						if del.Parent then
							del.Text = "🗑"
						end
					end)
					return
				end
				if state.editing and state.editing.slot == slot then
					state.editing = nil
				end
				kit.MenuAction:FireServer("DeleteDeck", { slot = slot })
			end, { Name = "Delete_" .. slot, Size = UDim2.fromOffset(58, 34), Position = UDim2.new(1, -66, 0.5, -17) })
			del.TextScaled = false
			del.TextSize = 14
		else
			text(card, "Empty slot " .. slot, { Size = UDim2.new(1, -140, 0, 24), Position = UDim2.fromOffset(16, 14), Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = DIM })
			text(card, "Build a deck from the cards you own", { Size = UDim2.new(1, -140, 0, 20), Position = UDim2.fromOffset(16, 44), TextSize = 13, TextColor3 = DIM })
			local new = kit.button(card, "+ New", rgb(60, 170, 90), function()
				openEditor(slot, { name = "Deck " .. slot, hero = DeckRules.Heroes[1], themes = {}, lanes = {}, cards = {} })
			end, { Name = "New_" .. slot, Size = UDim2.fromOffset(96, 38), Position = UDim2.new(1, -108, 0.5, -19) })
			new.TextScaled = false
			new.TextSize = 16
		end
	end
	text(scroll, "A deck has " .. DeckRules.MinCards .. " to " .. DeckRules.MaxCards .. " cards from up to " .. DeckRules.MaxThemes .. " themes, plus any neutral cards. Up to 3 copies of a card, 1 of each Legendary and Secret. More deck slots are in the Shop.", {
		Size = UDim2.new(1, -8, 0, 70),
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = DIM,
		LayoutOrder = 100,
	})
end

function redraw()
	if not state.left or not state.left.Visible then
		return
	end
	if state.view == "backgrounds" then
		clearLeft()
		require(here:WaitForChild("BackdropPicker")).render(state.left)
	elseif state.editing then
		showEditor()
	else
		showCollection()
	end
	showSlots()
end

-- Opens the shelf straight on the match backgrounds (from the Shop's background tiles).
function DeckBuilderUI.showBackgrounds()
	state.view = "backgrounds"
	state.editing = nil
	redraw()
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function DeckBuilderUI.showShelf(body)
	state.body = body
	state.left.Visible = true
	state.gridKey = nil
	redraw()
	DeckBuilderUI.request()
end

function DeckBuilderUI.hide()
	state.view = nil
	state.detail = nil
	state.anim = nil
	state.note = nil
	if state.left then
		state.left.Visible = false
	end
	state.body = nil
end

function DeckBuilderUI.init(k)
	kit = k
	state.left = k.panel(k.menuUI, UDim2.new(0.62, 0, 0.74, 0), UDim2.new(0, 24, 0.5, -10), Vector2.new(0, 0.5))
	state.left.Name = "DeckBuilder"
	state.left.Visible = false
	-- the "Match background" button over your decks follows what you wear
	require(here:WaitForChild("Cosmetics")).onChanged(function()
		if state.body and state.body.Parent then
			showSlots()
		end
	end)
	k.MenuAction.OnClientEvent:Connect(function(what, data)
		if what == "Decks" and type(data) == "table" then
			state.snap = data
			-- the deck you're editing may have been deleted
			if state.editing then
				local still = state.editing.slot <= (data.slots or DeckRules.DefaultDeckSlots)
				if not still then
					state.editing = nil
				end
			end
			for _, fn in ipairs(state.listeners) do
				task.spawn(fn, data)
			end
			-- keep the card grid (it only changes with the themes), repaint the rest
			redraw()
		elseif what == "CardResult" and type(data) == "table" then
			state.busy = false
			state.busyToken = nil
			if not data.ok then
				state.note = { tostring(data.why or "That didn't work"), BAD }
				Juice.sound("thud", 1.2, 0.3)
				return -- (the snapshot that follows repaints with the note)
			end
			if data.what == "FuseCard" or data.what == "FuseAll" then
				local best = 0
				for _, l in ipairs(data.made or {}) do
					best = math.max(best, l)
				end
				local n = data.count or 1
				state.anim = { kind = "fuse", level = best, count = n }
				state.note = { (n > 1 and (n .. " fuses! ") or "Fused! ") .. "Now up to level " .. best .. ".", GOOD }
			elseif data.what == "FuseEverything" then
				state.anim = { kind = "fuseAll" }
				state.note = { "✓ " .. (data.count or 0) .. " fuses" .. ((data.best and data.best > 1) and (" · best new level " .. data.best) or ""), GOOD }
			elseif data.what == "SellCard" then
				state.anim = { kind = "sell", level = data.level, coins = data.coins or 0 }
				state.note = { "Sold for " .. tostring(data.coins or 0) .. " Coins.", GOOD }
			end
		elseif what == "DeckSaved" and type(data) == "table" then
			if data.ok then
				state.saved = { "✓ Saved. Ready to play at the Duel Table!", GOOD }
				Juice.sound("chime", 1.0, 0.5)
			else
				state.saved = { "Saved, but not ready to play yet", GOLD }
			end
			redraw()
		end
	end)
end

return DeckBuilderUI

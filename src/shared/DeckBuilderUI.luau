-- The Deck Shelf: your collection, your saved decks and the deck editor. Client only.
-- The server (MatchServer + PlayerDecks) owns the collection and the saved decks: this screen
-- shows the snapshot it gets and sends "GetDecks", "SaveDeck" and "DeleteDeck" back.
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
local Juice = require(here:WaitForChild("Juice"))

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
-- The collection (left panel when you're not editing)
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

local function cardCell(parent, id, order)
	local cell = make("Frame", { Name = "Cell_" .. id, Size = UDim2.fromOffset(104, 168), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local card = kit.makeCard(cell, id, UDim2.fromOffset(104, 146))
	local dim = make("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 1, ZIndex = 20 }, card)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, dim)
	local badge = text(cell, "", { Name = "Badge", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -20), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, Font = Enum.Font.FredokaOne })
	return cell, dim, badge
end

local function showCollection()
	clearLeft()
	local left = state.left
	local total = collectibleTotal()
	text(left, "Your collection", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(14, 8), Font = Enum.Font.FredokaOne, TextSize = 28, TextColor3 = GOLD })
	text(left, state.snap and (uniqueOwned() .. " of " .. total .. " cards found · open packs at Pack Party for more") or "Loading your cards...", {
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(14, 42),
		TextColor3 = DIM,
	})
	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -76),
		Position = UDim2.fromOffset(12, 68),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, left)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(104, 168), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8) }, scroll)
	-- owned cards first, then the ones still to find (dark)
	local ids = sortedIds(nil)
	local order = {}
	for i, id in ipairs(ids) do
		order[id] = (ownedCount(id) > 0 and 0 or 1000) + i
	end
	for _, id in ipairs(ids) do
		local have = ownedCount(id)
		local secret = CardData.Cards[id].rarity == "Secret" and have == 0
		local cell = make("Frame", { Size = UDim2.fromOffset(104, 168), BackgroundTransparency = 1, LayoutOrder = order[id] }, scroll)
		local card = kit.makeCard(cell, id, UDim2.fromOffset(104, 146), secret and "hidden" or nil)
		if have == 0 then
			local dim = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.35, ZIndex = 20 }, card)
			make("UICorner", { CornerRadius = UDim.new(0, 10) }, dim)
		end
		text(cell, have > 0 and ("×" .. have) or "not found yet", {
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.new(0, 0, 1, -20),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = have > 0 and 15 or 12,
			Font = have > 0 and Enum.Font.FredokaOne or kit.BODY_FONT,
			TextColor3 = have > 0 and GOLD or DIM,
		})
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
		local closeB = kit.button(root, "✕", rgb(110, 60, 70), function()
			state.editing = nil
			state.saved, state.note = nil, nil
			redraw()
		end, { Name = "CloseEditor", Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -54, 0, 10) })
		closeB.TextScaled = false
		closeB.TextSize = 18
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
		probs.Text = "✔ Ready to play"
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
			text(card, d.ok and "✔ Ready to play" or ("⚠ " .. tostring(d.problems and d.problems[1] or "Not finished")), {
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
	if state.editing then
		showEditor()
	else
		showCollection()
	end
	showSlots()
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
		elseif what == "DeckSaved" and type(data) == "table" then
			if data.ok then
				state.saved = { "✔ Saved. Ready to play at the Duel Table!", GOOD }
				Juice.sound("chime", 1.0, 0.5)
			else
				state.saved = { "Saved, but not ready to play yet", GOLD }
			end
			redraw()
		end
	end)
end

return DeckBuilderUI

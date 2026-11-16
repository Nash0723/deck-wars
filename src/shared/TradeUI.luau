-- TradeUI: trading cards at the Park's Trading Post, on your screen. Client only. ParkClient
-- starts it and passes it the "trade..." events from the server; the steps of a trade are in
-- ServerScriptService.TradeDesk and the rules in Trade.
--
--   TradeUI.init(ctx)      once (ctx: gui = the Park's ScreenGui, action = ParkAction, makeCard,
--                          toast, isInside)
--   TradeUI.openPicker()   the Trading Post's prompt: who is here to trade with
--   TradeUI.onEvent(e)     a ParkEvent payload; returns true when it was a trade one
--   TradeUI.close()        you left the park: every trade panel goes away
--   TradeUI.escape()       Escape: closes the picker (a trade is only left with Cancel)
--   TradeUI.isOpen()       is the trade window up?
--
-- The screens: the picker (players standing at the Trading Post, "Ask"), the request card
-- ("Ann wants to trade": Trade / No thanks), the trade window (what you give, what they give,
-- your cards to pick from, Lock in, then Confirm once both have locked in) and the result.

local Players = game:GetService("Players")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local Trade = require(here:WaitForChild("Trade"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit"))

local player = Players.LocalPlayer

local rgb, make = Juice.rgb, Juice.make
local INK = rgb(18, 14, 28)
local PANEL = rgb(30, 25, 46)
local TILE = rgb(42, 36, 62)
local GOLD = rgb(255, 214, 102)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(170, 164, 190)
local GOOD = rgb(70, 190, 110)
local WARN = rgb(255, 170, 110)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local TradeUI = {}

local S = {
	ctx = nil,
	picker = nil, -- the "who's here" panel
	invite = nil, -- the request card
	win = nil, -- the trade window
	T = nil, -- the open trade (see openWindow)
	result = nil, -- the "Trade done" card
}
TradeUI.S = S -- (for the tests)

local function corner(p, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

local function stroke(p, color, t)
	return make("UIStroke", { Color = color or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent, str, props)
	local t = make("TextLabel", { BackgroundTransparency = 1, Text = str, Font = BODY_FONT, TextSize = 14, TextColor3 = TEXT, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18) }, parent)
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	return t
end

local function button(parent, str, color, onClick, props)
	local b = make("TextButton", { AutoButtonColor = false, BackgroundColor3 = color, Text = str, Font = TITLE_FONT, TextSize = 17, TextColor3 = TEXT, Size = UDim2.fromOffset(120, 40) }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 10)
	stroke(b, INK, 2)
	Juice.button(b)
	b.Activated:Connect(onClick)
	return b
end

local function toast(msg)
	if S.ctx and S.ctx.toast then
		S.ctx.toast(msg)
	end
end

local function fire(what, options)
	S.ctx.action:FireServer(what, options or {})
end

-- A window that would be taller or wider than the screen is scaled down to fit.
local function fit(frame, width, height)
	local cam = workspace.CurrentCamera
	local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local scale = math.min(1, (view.X - 24) / width, (view.Y - 24) / height)
	if scale < 1 then
		make("UIScale", { Name = "Fit", Scale = math.max(0.4, scale) }, frame)
	end
end

-- A card face that lets clicks through to the button it sits on.
local function face(parent, id, level)
	if not (S.ctx and S.ctx.makeCard) then
		return nil
	end
	local card = S.ctx.makeCard(parent, id, UDim2.fromScale(1, 1), nil, "compact", level)
	if card then
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.Active = false
			end
		end
	end
	return card
end

local function copyOffer(offer)
	local out = {}
	for i, o in ipairs(offer or {}) do
		out[i] = { id = o.id, level = o.level }
	end
	return out
end

local function keyOf(o)
	return o.id .. ":" .. tostring(o.level)
end

---------------------------------------------------------------------------
-- Who's here: the Trading Post's prompt
---------------------------------------------------------------------------

local function deskPosition()
	local park = workspace:FindFirstChild("Park")
	local post = park and park:FindFirstChild("TradingPost")
	local desk = post and post:FindFirstChild("Desk")
	return desk and desk.Position or nil
end

local function atPost(p)
	local at = deskPosition()
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return at ~= nil and root ~= nil and p:GetAttribute("InPark") == true and (root.Position - at).Magnitude <= Trade.Radius
end

local function closePicker()
	if S.picker then
		S.picker:Destroy()
		S.picker = nil
	end
end

function TradeUI.openPicker()
	if S.win or not S.ctx then
		return
	end
	closePicker()
	local f = make("Frame", { Name = "TradePicker", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 10), Size = UDim2.fromOffset(400, 440), BackgroundColor3 = PANEL }, S.ctx.gui)
	S.picker = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	fit(f, 448, 480)
	text(f, "🤝 Trading Post", { Font = TITLE_FONT, TextSize = 24, Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(14, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	UIKit.closeButton(f, closePicker, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 8) })
	text(f, "Swap cards with another player. You both stand here, put in up to " .. Trade.MaxOffer .. " cards each, lock in, then confirm.", { Position = UDim2.fromOffset(14, 48), Size = UDim2.new(1, -28, 0, 52), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	text(f, "Cards your decks use stay with you. Level " .. Trade.MinLevel .. " and up, " .. Trade.MaxPerDay .. " trades a day.", { Position = UDim2.fromOffset(14, 102), Size = UDim2.new(1, -28, 0, 34), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local note = text(f, "", { Name = "Note", Position = UDim2.fromOffset(14, 140), Size = UDim2.new(1, -28, 0, 40), TextColor3 = WARN, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local list = make("ScrollingFrame", { Name = "Players", Position = UDim2.fromOffset(14, 184), Size = UDim2.new(1, -28, 1, -198), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, f)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local empty = text(list, "Nobody else is at the Trading Post right now. Ask a friend to meet you here.", { Name = "Empty", Size = UDim2.new(1, -8, 0, 44), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 999 })
	local rows = {} -- [player] = row
	local function refresh()
		local myLevel = tonumber(player:GetAttribute("Level")) or 1
		local canTrade = myLevel >= Trade.MinLevel
		if not canTrade then
			note.Text = "You need level " .. Trade.MinLevel .. " to trade (you're level " .. myLevel .. "). Play a few matches first."
		elseif not atPost(player) then
			note.Text = "Step up to the Trading Post to trade."
		elseif note.Text ~= S.pickerNote then
			note.Text = S.pickerNote or ""
		end
		local here = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and atPost(p) then
				here[p] = true
			end
		end
		for p, row in pairs(rows) do
			if not here[p] then
				row:Destroy()
				rows[p] = nil
			end
		end
		local n = 0
		for p in pairs(here) do
			n += 1
			local row = rows[p]
			if not row then
				row = make("Frame", { Name = "Row" .. p.UserId, Size = UDim2.new(1, -8, 0, 50), BackgroundColor3 = TILE }, list)
				corner(row, 10)
				text(row, p.DisplayName, { Name = "Who", Font = TITLE_FONT, TextSize = 17, Position = UDim2.fromOffset(12, 5), Size = UDim2.new(1, -124, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
				text(row, "", { Name = "Level", Position = UDim2.fromOffset(12, 27), Size = UDim2.new(1, -124, 0, 18), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
				button(row, "Ask", GOOD, function()
					fire("TradeInvite", { userId = p.UserId })
				end, { Name = "Ask", Size = UDim2.fromOffset(92, 36), Position = UDim2.new(1, -102, 0, 7) })
				rows[p] = row
			end
			local level = tonumber(p:GetAttribute("Level")) or 1
			row.Level.Text = level >= Trade.MinLevel and ("Level " .. level) or ("Level " .. level .. " · needs level " .. Trade.MinLevel)
			row.Ask.Visible = canTrade and level >= Trade.MinLevel
		end
		empty.Visible = n == 0
	end
	task.spawn(function()
		while S.picker == f and f.Parent do
			refresh()
			task.wait(1)
		end
	end)
end

---------------------------------------------------------------------------
-- A request to trade
---------------------------------------------------------------------------

local function hideInvite()
	if S.invite then
		S.invite:Destroy()
		S.invite = nil
	end
end

local function showInvite(e)
	hideInvite()
	if S.win then
		return -- (already trading; the server wouldn't have sent this)
	end
	local seconds = tonumber(e.seconds) or Trade.InviteSeconds
	local f = make("Frame", { Name = "TradeInvite", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 124), Size = UDim2.fromOffset(440, 100), BackgroundColor3 = PANEL, ZIndex = 20 }, S.ctx.gui)
	S.invite = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	fit(f, 464, 120)
	text(f, "🤝 " .. tostring(e.name) .. " wants to trade cards", { Name = "Ask", Font = TITLE_FONT, TextSize = 18, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 26), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 21 })
	button(f, "✓ Trade", GOOD, function()
		fire("TradeAnswer", { userId = e.from, accept = true })
		hideInvite()
	end, { Name = "Accept", Size = UDim2.new(0.5, -20, 0, 40), Position = UDim2.new(0, 14, 0, 42), ZIndex = 21 })
	button(f, "No thanks", TILE, function()
		fire("TradeAnswer", { userId = e.from, accept = false })
		hideInvite()
	end, { Name = "Decline", Size = UDim2.new(0.5, -20, 0, 40), Position = UDim2.new(0.5, 6, 0, 42), ZIndex = 21 })
	-- the time left to answer
	local bar = make("Frame", { Name = "Timer", Position = UDim2.new(0, 14, 1, -10), Size = UDim2.new(1, -28, 0, 4), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 21 }, f)
	corner(bar, 2)
	Juice.tween(bar, seconds, { Size = UDim2.new(0, 0, 0, 4) }, Enum.EasingStyle.Linear)
	Juice.sound("pop", 1.2, 0.4)
	task.delay(seconds, function()
		if S.invite == f then
			hideInvite()
		end
	end)
end

---------------------------------------------------------------------------
-- The trade window
---------------------------------------------------------------------------

local SLOT = Vector2.new(94, 124)

local function closeWindow()
	if S.win then
		S.win:Destroy()
	end
	S.win = nil
	S.T = nil
end

local function offered(T, key)
	local n = 0
	for _, o in ipairs(T.offer) do
		if keyOf(o) == key then
			n += 1
		end
	end
	return n
end

-- Fills a row of slots with an offer. onTap(index): tapping a card (your own row only).
local function drawRow(row, offer, onTap)
	for i, slot in ipairs(row) do
		local o = offer[i]
		local key = o and keyOf(o) or ""
		if slot:GetAttribute("Shows") ~= key then
			slot:SetAttribute("Shows", key)
			local old = slot:FindFirstChild("Cell")
			if old then
				old:Destroy()
			end
			if o then
				local cell = make("TextButton", { Name = "Cell", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = onTap ~= nil }, slot)
				face(cell, o.id, o.level)
				if onTap then
					cell.Activated:Connect(function()
						onTap(i)
					end)
				end
				Juice.pop(cell, 0.8, 0.18)
			end
		end
	end
end

local function render()
	local T = S.T
	if not T then
		return
	end
	local v = T.view
	local confirming = v.state == "confirm"
	drawRow(T.mineRow, T.offer, function(i)
		T.remove(i)
	end)
	drawRow(T.theirRow, v.theirs.offer)
	-- your cards: how many of each are left to add
	for key, cell in pairs(T.cells) do
		local left = cell:GetAttribute("Count") - offered(T, key)
		cell.Count.Text = "×" .. left
		cell.Count.Visible = left > 1
		cell.Shade.Visible = left <= 0
	end
	T.grid.Visible = not confirming
	if T.empty then
		T.empty.Visible = not confirming
	end
	T.gridTitle.Visible = not confirming
	T.summary.Visible = confirming
	T.mineStatus.Text = v.mine.confirmed and "✓ Confirmed" or (v.mine.locked and "🔒 Locked in" or "Choosing...")
	T.mineStatus.TextColor3 = (v.mine.locked or v.mine.confirmed) and GOOD or DIM
	T.theirStatus.Text = v.theirs.confirmed and "✓ Confirmed" or (v.theirs.locked and "🔒 Locked in" or "Choosing...")
	T.theirStatus.TextColor3 = (v.theirs.locked or v.theirs.confirmed) and GOOD or DIM
	local name = T.name
	if confirming then
		local get = #v.theirs.offer > 0 and Trade.describe(v.theirs.offer) or "nothing"
		local give = #T.offer > 0 and Trade.describe(T.offer) or "nothing"
		T.summaryText.Text = "You give:  " .. give .. "\nYou get:  " .. get
		T.warning.Visible = #v.theirs.offer == 0
		T.lock.Text = "Change cards"
		T.lock.BackgroundColor3 = TILE
		T.cancel.Position = UDim2.new(1, -446, 1, -58)
		T.lock.Position = UDim2.new(1, -334, 1, -58)
		T.confirm.Visible = true
		local left = math.max(0, math.ceil(T.confirmAt - time()))
		if v.mine.confirmed then
			T.confirm.Text = "Waiting for " .. name .. "..."
			T.confirm.BackgroundColor3 = TILE
			T.status.Text = "You've confirmed. The cards change hands when " .. name .. " confirms too."
		elseif left > 0 then
			T.confirm.Text = "Confirm in " .. left .. "..."
			T.confirm.BackgroundColor3 = TILE
			T.status.Text = "Both locked in. Check the cards before you confirm."
		else
			T.confirm.Text = "✓ Confirm trade"
			T.confirm.BackgroundColor3 = GOOD
			T.status.Text = v.theirs.confirmed and (name .. " has confirmed. Your turn.") or "Both locked in. Check the cards, then confirm."
		end
	else
		T.confirm.Visible = false
		T.cancel.Position = UDim2.new(1, -288, 1, -58)
		T.lock.Position = UDim2.new(1, -176, 1, -58)
		T.lock.Text = v.mine.locked and "Change cards" or "🔒 Lock in"
		T.lock.BackgroundColor3 = v.mine.locked and TILE or GOOD
		if v.mine.locked then
			T.status.Text = "Locked in. Waiting for " .. name .. " to lock in."
		elseif v.theirs.locked then
			T.status.Text = name .. " has locked in. Lock in when you're happy with the trade."
		else
			T.status.Text = "Tap your cards to put them in (up to " .. T.max .. "). Tap a card in your row to take it back."
		end
	end
end

local function openWindow(e)
	closePicker()
	hideInvite()
	closeWindow()
	if S.result then
		S.result:Destroy()
		S.result = nil
	end
	local name = tostring(type(e.with) == "table" and e.with.name or "them")
	local f = make("Frame", { Name = "TradeWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(800, 590), BackgroundColor3 = PANEL }, S.ctx.gui)
	S.win = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	fit(f, 824, 614)
	UIKit.Focus.watch(f, { dim = 0.35, blur = 6 })
	local T = {
		name = name,
		max = tonumber(e.max) or Trade.MaxOffer,
		offer = {}, -- what you've put in (your screen's copy; the server has the real one)
		n = 0, -- how many edits you've sent
		view = { state = "offering", mine = { offer = {}, locked = false, confirmed = false, version = 0, n = 0 }, theirs = { offer = {}, locked = false, confirmed = false, version = 0 } },
		confirmAt = 0,
		cells = {},
	}
	S.T = T
	text(f, "🤝 Trading with " .. name, { Name = "Title", Font = TITLE_FONT, TextSize = 24, Size = UDim2.new(1, -70, 0, 32), Position = UDim2.fromOffset(16, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	UIKit.closeButton(f, function()
		fire("TradeCancel")
	end, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 8) })
	-- the two offers
	local function offerRow(y, title, rowName)
		local holder = make("Frame", { Name = rowName, Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, SLOT.Y + 8), BackgroundColor3 = TILE, BackgroundTransparency = 0.45 }, f)
		corner(holder, 10)
		text(holder, title, { Name = "Title", Font = TITLE_FONT, TextSize = 17, Position = UDim2.fromOffset(10, 30), Size = UDim2.fromOffset(140, 44), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
		local status = text(holder, "Choosing...", { Name = "Status", Position = UDim2.fromOffset(10, 78), Size = UDim2.fromOffset(140, 20), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
		local slots = make("Frame", { Name = "Slots", Position = UDim2.new(1, -(6 * SLOT.X + 5 * 8 + 6), 0, 4), Size = UDim2.fromOffset(6 * SLOT.X + 5 * 8, SLOT.Y), BackgroundTransparency = 1 }, holder)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, slots)
		local row = {}
		for i = 1, T.max do
			local slot = make("Frame", { Name = "Slot" .. i, LayoutOrder = i, Size = UDim2.fromOffset(SLOT.X, SLOT.Y), BackgroundColor3 = INK, BackgroundTransparency = 0.55 }, slots)
			corner(slot, 10)
			make("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 7), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, slot)
			row[i] = slot
		end
		return row, status, holder
	end
	T.mineRow, T.mineStatus = offerRow(50, "You give", "Mine")
	T.theirRow, T.theirStatus, T.theirHolder = offerRow(190, name .. " gives", "Theirs")
	-- your cards
	local room = tonumber(e.room) or 0
	T.gridTitle = text(f, "Your cards" .. (room <= 0 and "  ·  your storage is full: you can't end up with more cards than you give" or ""), { Name = "GridTitle", Position = UDim2.fromOffset(18, 330), Size = UDim2.new(1, -36, 0, 20), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	T.grid = make("ScrollingFrame", { Name = "Cards", Position = UDim2.fromOffset(16, 354), Size = UDim2.new(1, -32, 0, 168), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, f)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(80, 112), CellPadding = UDim2.fromOffset(10, 12), SortOrder = Enum.SortOrder.LayoutOrder }, T.grid)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, T.grid)
	local function send(what)
		T.n += 1
		fire(what, { offer = copyOffer(T.offer), n = T.n, seen = T.view.theirs.version })
	end
	local function frozen()
		if T.view.state == "confirm" then
			toast("Tap Change cards first.")
			return true
		end
		return false
	end
	function T.remove(i)
		if frozen() or not T.offer[i] then
			return
		end
		table.remove(T.offer, i)
		T.view.mine.locked = false
		send("TradeOffer")
		render()
	end
	local shown = 0
	for _, c in ipairs(type(e.cards) == "table" and e.cards or {}) do
		if type(c) == "table" and CardData.Cards[c.id] and shown < 150 then
			shown += 1
			local key = keyOf(c)
			local cell = make("TextButton", { Name = key, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = shown }, T.grid)
			cell:SetAttribute("Count", tonumber(c.count) or 1)
			face(cell, c.id, c.level)
			local count = text(cell, "", { Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(34, 22), BackgroundColor3 = INK, BackgroundTransparency = 0, Font = TITLE_FONT, TextSize = 14, TextColor3 = GOLD, ZIndex = 10 })
			corner(count, 11)
			local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0.35, Visible = false, ZIndex = 9, Active = false }, cell)
			corner(shade, 10)
			T.cells[key] = cell
			cell.Activated:Connect(function()
				if frozen() then
					return
				end
				if #T.offer >= T.max then
					toast("That's the most cards for one trade (" .. T.max .. ").")
					return
				end
				if offered(T, key) >= cell:GetAttribute("Count") then
					return
				end
				table.insert(T.offer, { id = c.id, level = c.level })
				T.view.mine.locked = false
				send("TradeOffer")
				render()
			end)
		end
	end
	if shown == 0 then
		T.empty = text(f, "You have no spare cards to trade: every copy you own plays in one of your decks.", { Name = "NoCards", TextColor3 = DIM, Position = UDim2.fromOffset(22, 366), Size = UDim2.new(1, -44, 0, 40), TextXAlignment = Enum.TextXAlignment.Left })
	end
	-- the last look before confirming (shown in place of your cards)
	T.summary = make("Frame", { Name = "Summary", Position = UDim2.fromOffset(16, 334), Size = UDim2.new(1, -32, 0, 186), BackgroundColor3 = TILE, Visible = false }, f)
	corner(T.summary, 10)
	text(T.summary, "Last look", { Font = TITLE_FONT, TextSize = 20, TextColor3 = GOLD, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 26), TextXAlignment = Enum.TextXAlignment.Left })
	T.summaryText = text(T.summary, "", { Name = "Cards", TextSize = 16, Position = UDim2.fromOffset(14, 42), Size = UDim2.new(1, -28, 0, 96), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	T.warning = text(T.summary, "You get nothing back: this is a gift. A trade can't be undone.", { Name = "Warning", Font = TITLE_FONT, TextSize = 16, TextColor3 = WARN, Position = UDim2.new(0, 14, 1, -40), Size = UDim2.new(1, -28, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, Visible = false })
	-- the bottom row
	T.status = text(f, "", { Name = "Status", Position = UDim2.new(0, 18, 1, -58), Size = UDim2.new(1, -470, 0, 44), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = TEXT })
	T.cancel = button(f, "Cancel", rgb(150, 76, 76), function()
		fire("TradeCancel")
	end, { Name = "Cancel", Size = UDim2.fromOffset(104, 44), Position = UDim2.new(1, -288, 1, -58) })
	T.lock = button(f, "🔒 Lock in", GOOD, function()
		if T.view.state == "confirm" or T.view.mine.locked then
			fire("TradeUnlock")
		else
			send("TradeLock")
		end
	end, { Name = "Lock", Size = UDim2.fromOffset(160, 44), Position = UDim2.new(1, -176, 1, -58) })
	T.confirm = button(f, "✓ Confirm trade", GOOD, function()
		if T.view.state == "confirm" and not T.view.mine.confirmed and time() >= T.confirmAt then
			fire("TradeConfirm")
		end
	end, { Name = "Confirm", Size = UDim2.fromOffset(150, 44), Position = UDim2.new(1, -166, 1, -58), Visible = false })
	UIKit.animateIn(f)
	render()
	-- the countdown on the Confirm button
	task.spawn(function()
		while S.win == f and f.Parent do
			if T.view.state == "confirm" then
				render()
			end
			task.wait(0.25)
		end
	end)
end

-- The trade as the server has it.
local function update(e)
	local T = S.T
	if not T or type(e.mine) ~= "table" or type(e.theirs) ~= "table" then
		return
	end
	local before = T.view
	e.mine.offer = type(e.mine.offer) == "table" and e.mine.offer or {}
	e.theirs.offer = type(e.theirs.offer) == "table" and e.theirs.offer or {}
	T.view = e
	-- your own row follows the server once it has caught up with your last edit
	if (tonumber(e.mine.n) or 0) >= T.n then
		T.offer = copyOffer(e.mine.offer)
	end
	if e.state == "confirm" and before.state ~= "confirm" then
		T.confirmAt = time() + (tonumber(e.confirmIn) or Trade.ConfirmDelay)
		Juice.sound("pop", 0.9, 0.4)
	end
	if e.theirs.version ~= before.theirs.version and T.theirHolder then
		-- their cards changed: a quick glow so you look again
		T.theirHolder.BackgroundColor3 = GOLD
		Juice.tween(T.theirHolder, 0.6, { BackgroundColor3 = TILE })
	end
	render()
end

---------------------------------------------------------------------------
-- Done
---------------------------------------------------------------------------

local function showResult(e)
	if S.result then
		S.result:Destroy()
	end
	local got = type(e.got) == "table" and e.got or {}
	local gave = type(e.gave) == "table" and e.gave or {}
	local name = tostring(e.name or "them")
	local f = make("Frame", { Name = "TradeResult", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, #got > 0 and 300 or 170), BackgroundColor3 = PANEL }, S.ctx.gui)
	S.result = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	fit(f, 644, 324)
	local function close()
		if S.result == f then
			S.result = nil
		end
		f:Destroy()
	end
	text(f, "✓ Trade done!", { Font = TITLE_FONT, TextSize = 26, TextColor3 = GOLD, Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 32) })
	local line = #got > 0 and ("From " .. name .. ":") or ("Your gift went to " .. name .. ": " .. Trade.describe(gave) .. ".")
	text(f, line, { Name = "Line", Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 0, #got > 0 and 20 or 44), TextColor3 = TEXT })
	if #got > 0 then
		local row = make("Frame", { Name = "Got", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(#got * 88 + (#got - 1) * 8, 122), BackgroundTransparency = 1 }, f)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
		for i, o in ipairs(got) do
			if type(o) == "table" and CardData.Cards[o.id] then
				local cell = make("Frame", { Name = "Card" .. i, LayoutOrder = i, Size = UDim2.fromOffset(88, 122), BackgroundTransparency = 1 }, row)
				face(cell, o.id, o.level)
				Juice.popIn(cell, (i - 1) * 0.08)
			end
		end
		Juice.confetti(f, 0.5, 0.3, 26)
	end
	button(f, "Nice!", GOOD, close, { Name = "Ok", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(160, 44), Position = UDim2.new(0.5, 0, 1, -14) })
	UIKit.animateIn(f)
	Juice.sound("sting_Rare", 1, 0.4)
	task.delay(10, function()
		if S.result == f then
			close()
		end
	end)
end

---------------------------------------------------------------------------
-- From ParkClient
---------------------------------------------------------------------------

function TradeUI.onEvent(e)
	local kind = e.kind
	if kind == "tradeInvite" then
		showInvite(e)
	elseif kind == "tradeInviteGone" then
		hideInvite()
	elseif kind == "tradeAsked" then
		S.pickerNote = "Asked " .. tostring(e.name) .. ". Waiting for an answer..."
		local note = S.picker and S.picker:FindFirstChild("Note")
		if note then
			note.Text = S.pickerNote
		else
			toast(S.pickerNote)
		end
		local said = S.pickerNote
		task.delay(tonumber(e.seconds) or Trade.InviteSeconds, function()
			if S.pickerNote == said then
				S.pickerNote = nil
			end
		end)
	elseif kind == "tradeOpen" then
		S.pickerNote = nil
		openWindow(e)
	elseif kind == "trade" then
		update(e)
	elseif kind == "tradeDone" then
		closeWindow()
		showResult(e)
	elseif kind == "tradeClosed" then
		local was = S.win ~= nil
		closeWindow()
		if was and e.text then
			toast(tostring(e.text))
		end
	else
		return false
	end
	return true
end

function TradeUI.isOpen()
	return S.win ~= nil
end

function TradeUI.escape()
	closePicker()
end

function TradeUI.close()
	closePicker()
	hideInvite()
	closeWindow()
	if S.result then
		S.result:Destroy()
		S.result = nil
	end
	S.pickerNote = nil
end

function TradeUI.init(ctx)
	S.ctx = ctx
end

return TradeUI

-- The Shop screen, the Gems / Coins counters and the reward toasts. Client only.
-- The server (EconomyServer + EconomyManager) owns every number: this screen only shows the
-- snapshot it gets and sends requests ("Buy", "Equip", "BuyGems", "Emote") back.
--
--   ShopUI.init({ makeCard = fn(parent, cardId, size) })  -- once, from DeckWarsClient
--   ShopUI.hud(parent)                 -- Gems / Coins / level counters (top right of the menu)
--   ShopUI.stationPanel(body)          -- the right-hand panel at the Shop counter
--   ShopUI.open(tab) / ShopUI.close()  -- the big Shop window (tabs "daily", "cosmetics", "exchange")
--   ShopUI.mountEmotes(matchUI, myHero, theirHero)  -- the 💬 emote button in matches
--
-- Tabs:
--   🃏 Daily Cards       six single cards a day for Coins (same for everyone, new at UTC midnight)
--   🎨 Deck & Field      board themes, card backs, emotes and deck slots
--   💎 Exchange & Boosts Robux Gem bundles, Coins <-> Gems, Luck and XP boosters

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local here = script.Parent
local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
local Cosmetics = require(here:WaitForChild("Cosmetics"))
local CardData = require(here:WaitForChild("CardData"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit")) -- the drawn coin (Roblox can't draw 🪙) and the close ✕

local remotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local ShopAction = remotes:WaitForChild("ShopAction")
local EconomyEvent = remotes:WaitForChild("EconomyEvent")

local rgb, make, tween = Juice.rgb, Juice.make, Juice.tween

local ShopUI = {}

-- Look: the menu's dark plum panels, warm gold titles, gem blue and coin gold.
local INK = rgb(18, 14, 28)
local PANEL = rgb(30, 25, 46)
local TILE = rgb(42, 36, 62)
local TILE_HI = rgb(56, 48, 82)
local GOLD = rgb(255, 220, 90)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(176, 170, 196)
local GOOD = rgb(70, 190, 110)
local BAD = rgb(220, 80, 80)
local GEM = rgb(ShopCatalog.Color.Gems[1], ShopCatalog.Color.Gems[2], ShopCatalog.Color.Gems[3])
local COIN = rgb(ShopCatalog.Color.Coins[1], ShopCatalog.Color.Coins[2], ShopCatalog.Color.Coins[3])
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local BOLD_FONT = Enum.Font.FredokaOne

local state = {
	ready = false,
	snap = nil, -- the newest snapshot from the server
	snapAt = 0, -- time() when it came
	makeCard = nil,
	huds = {}, -- { set = fn(snap) }
	panels = {}, -- open station panels to refresh
	gui = nil,
	toastGui = nil,
	toastHolder = nil,
	window = nil,
	content = nil,
	tab = "daily",
	tabButtons = {},
	confirm = nil, -- { button, until } for "tap again to confirm" Gem purchases
	emoteFns = {}, -- listeners for server-approved emotes
	snapFns = {},
}

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function corner(obj, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 10) }, obj)
	return obj
end

local function stroke(obj, color, thick)
	return make("UIStroke", { Color = color or INK, Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, obj)
end

local function text(parent, str, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = str,
		Font = BODY_FONT,
		TextSize = 16,
		TextColor3 = TEXT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 20),
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, str, color, onClick, props)
	local b = make("TextButton", {
		Text = str,
		Font = TITLE_FONT,
		TextSize = 18,
		TextColor3 = INK,
		BackgroundColor3 = color or GOLD,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(140, 38),
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 10)
	stroke(b, INK, 2)
	Juice.button(b, { grow = 1.05 })
	if onClick then
		b.Activated:Connect(onClick)
	end
	return b
end

local function curColor(cur)
	return cur == "Gems" and GEM or COIN
end

local function balanceOf(cur)
	local s = state.snap
	if not s then
		return 0
	end
	return cur == "Gems" and s.gems or s.coins
end

local function duration(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	local s = seconds % 60
	return string.format("%dm %02ds", m, s)
end

-- Seconds left on a countdown from the snapshot, counted on from when it arrived.
local function since(seconds)
	return math.max(0, (seconds or 0) - (time() - state.snapAt))
end

---------------------------------------------------------------------------
-- Toasts (top of the screen)
---------------------------------------------------------------------------
local TOAST_COLORS = { good = GOOD, bad = BAD, info = GOLD, gem = GEM, coin = COIN }

function ShopUI.toast(message, kind, opts)
	if not state.toastHolder then
		return
	end
	opts = opts or {}
	local big = opts.big
	local t = make("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(big and 520 or 430, big and 86 or 50),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		LayoutOrder = math.floor(time() * 100) % 1e7,
	}, state.toastHolder)
	corner(t, 14)
	stroke(t, TOAST_COLORS[kind or "info"] or GOLD, 3)
	if opts.icon == "Coins" or opts.icon == "Gems" then
		local px = big and 40 or 26
		UIKit.icon(t, opts.icon, px, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 8 + (big and 31 or 20), 0.5, 0) })
	else
		text(t, opts.icon or (kind == "bad" and "✋" or kind == "good" and "✓" or "★"), {
			Size = UDim2.new(0, big and 62 or 40, 1, 0),
			Position = UDim2.fromOffset(8, 0),
			TextScaled = true,
			Font = BOLD_FONT,
			TextColor3 = TOAST_COLORS[kind or "info"] or GOLD,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	text(t, message, {
		Name = "Message",
		Size = UDim2.new(1, big and -84 or -60, 1, -10),
		Position = UDim2.fromOffset(big and 76 or 52, 5),
		Font = big and TITLE_FONT or BOLD_FONT,
		TextSize = big and 20 or 16,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	Juice.popIn(t, 0, { twist = 0, sound = false, time = 0.35 })
	if big then
		Juice.stars(t, 0.08, 0.5, 8, { zIndex = 5 })
		Juice.sound("twang", 1.1, 0.4)
	end
	task.delay(opts.time or (big and 5.5 or 3.2), function()
		if t.Parent then
			Juice.popOut(t, 0.25)
			task.wait(0.3)
			t:Destroy()
		end
	end)
	return t
end

---------------------------------------------------------------------------
-- The Gems / Coins / level counters
---------------------------------------------------------------------------
local counting = {} -- [TextLabel] = { shown, target, icon }
local countLoop = nil
local function countTo(label, target, icon)
	local c = counting[label]
	if not c then
		c = { shown = target, target = target, icon = icon }
		counting[label] = c
		label.Text = (icon and (icon .. " ") or "") .. ShopCatalog.format(target)
	end
	if c.target ~= target then
		if target > c.target then
			local p = label.Parent
			if p and p.Name == "Amount" and p.Parent then
				p = p.Parent
			end
			Juice.pop(p, 1.12, 0.4)
		end
		c.target = target
	end
	if not countLoop then
		countLoop = RunService.Heartbeat:Connect(function(dt)
			for l, s in pairs(counting) do
				if not l.Parent then
					counting[l] = nil
				elseif s.shown ~= s.target then
					local step = math.max(1, math.abs(s.target - s.shown) * math.min(1, dt * 8))
					if s.shown < s.target then
						s.shown = math.min(s.target, s.shown + step)
					else
						s.shown = math.max(s.target, s.shown - step)
					end
					s.shown = math.floor(s.shown + 0.5)
					l.Text = (s.icon and (s.icon .. " ") or "") .. ShopCatalog.format(s.shown)
				end
			end
		end)
	end
end

-- A rounded counter. With cur ("Gems" / "Coins") its icon is drawn next to the number.
local function pill(parent, color, order, cur)
	local p = make("Frame", { Size = UDim2.fromOffset(150, 40), BackgroundColor3 = rgb(20, 16, 32), BackgroundTransparency = 0.05, LayoutOrder = order }, parent)
	corner(p, 20)
	stroke(p, color, 2)
	if cur then
		local row, l = UIKit.currency(p, cur, "", { size = 20, color = color, align = Enum.HorizontalAlignment.Center })
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Position = UDim2.fromScale(0.5, 0.5)
		row.Name = "Amount"
		return p, l
	end
	local l = text(p, "", { Name = "Value", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), Font = TITLE_FONT, TextSize = 20, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center })
	return p, l
end

-- Counters for Gems, Coins and the level. parent is a full-screen frame (the menu UI).
function ShopUI.hud(parent, position)
	local bar = make("Frame", {
		Name = "CurrencyHud",
		AnchorPoint = Vector2.new(1, 0),
		Position = position or UDim2.new(1, -20, 0, 66),
		Size = UDim2.fromOffset(480, 40),
		BackgroundTransparency = 1,
	}, parent)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
	local lvl, lvlLabel = pill(bar, GOLD, 1)
	lvl.Size = UDim2.fromOffset(120, 40)
	local gems, gemLabel = pill(bar, GEM, 2, "Gems")
	local coins, coinLabel = pill(bar, COIN, 3, "Coins")
	gems.Name, coins.Name, lvl.Name = "Gems", "Coins", "Level"
	local h = {}
	function h.set(s)
		if not bar.Parent then
			return
		end
		countTo(gemLabel, s.gems, nil)
		countTo(coinLabel, s.coins, nil)
		lvlLabel.Text = "Lv " .. s.level .. (s.luckCharges > 0 and ("  🍀" .. s.luckCharges) or "")
	end
	table.insert(state.huds, h)
	if state.snap then
		h.set(state.snap)
	else
		gemLabel.Text, coinLabel.Text, lvlLabel.Text = "...", "...", "Lv ..."
	end
	return bar
end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------
local function send(what, kind, id)
	ShopAction:FireServer(what, kind, id)
end

-- A price button. Gem prices need a second tap within 3 seconds (no accidental Gem spending).
local function priceButton(parent, price, onBuy, props)
	local cur, amount = ShopCatalog.priceOf(price)
	local b = button(parent, "", curColor(cur), nil, props)
	b:SetAttribute("Currency", cur or "Free")
	local function show(prefix)
		-- the price as [icon] number (the coin is drawn: Roblox has no 🪙)
		if cur then
			UIKit.caption(b, cur, (prefix or "") .. ShopCatalog.format(amount))
		else
			UIKit.caption(b, nil, "Free")
		end
	end
	show()
	b:SetAttribute("Price", amount or 0)
	local function afford()
		return cur ~= nil and balanceOf(cur) >= amount
	end
	if not afford() then
		b.BackgroundColor3 = curColor(cur):Lerp(rgb(70, 66, 86), 0.65)
		b.TextColor3 = DIM
		show()
	end
	b.Activated:Connect(function()
		if not afford() then
			ShopUI.toast("Not enough " .. tostring(cur) .. ".", "bad")
			Juice.shake(b, 5, 0.25)
			return
		end
		if cur == "Gems" then
			local c = state.confirm
			if not (c and c.button == b and time() < c.untilT) then
				state.confirm = { button = b, untilT = time() + 3 }
				show("Tap again: ")
				task.delay(3, function()
					if b.Parent and state.confirm and state.confirm.button == b and time() >= state.confirm.untilT then
						show()
						state.confirm = nil
					end
				end)
				return
			end
			state.confirm = nil
		end
		UIKit.caption(b, nil, "...")
		onBuy()
	end)
	return b
end

local function statusButton(parent, str, color, props)
	local b = button(parent, str, color or rgb(70, 66, 86), nil, props)
	b.TextColor3 = TEXT
	b.Active = false
	return b
end

---------------------------------------------------------------------------
-- The Shop window
---------------------------------------------------------------------------
local function section(parent, title, sub, order)
	local holder = make("Frame", { Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
	text(holder, title, { Size = UDim2.new(1, 0, 0, 30), Font = TITLE_FONT, TextSize = 24, TextColor3 = GOLD, LayoutOrder = 1 })
	if sub then
		text(holder, sub, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 14, TextColor3 = DIM, LayoutOrder = 2 })
	end
	local grid = make("Frame", { Name = "Grid", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, holder)
	return holder, grid
end

local function gridLayout(grid, w, h)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(w, h), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
end

local function tile(grid, order, highlight)
	local t = make("Frame", { Name = "Tile", BackgroundColor3 = highlight and TILE_HI or TILE, LayoutOrder = order }, grid)
	corner(t, 12)
	stroke(t, highlight and GOLD or rgb(70, 62, 98), highlight and 2 or 1)
	return t
end

local builders = {}

-- 🃏 Daily Cards
function builders.daily(content, s)
	local _, grid = section(content, "Today's cards", "Six cards for Coins, the same for every player today. Each can be bought once a day. Legendary and Secret cards only come from packs.", 1)
	gridLayout(grid, 150, 270)
	local countdown = text(content, "", { Name = "Countdown", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), Font = BOLD_FONT, TextColor3 = DIM })
	Juice.onFrame(countdown, function()
		countdown.Text = "⏳ New cards in " .. duration(since(s.resetIn))
	end)
	for k, offer in ipairs(ShopCatalog.dailyCards(s.day)) do
		local def = CardData.get(offer.id)
		local t = tile(grid, k, offer.rarity == "Mythic")
		if state.makeCard then
			local card = state.makeCard(t, offer.id, UDim2.fromOffset(126, 176))
			card.Position = UDim2.fromOffset(12, 10)
		else
			text(t, def.name, { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 40) })
		end
		local owned = (s.dailyOwned and s.dailyOwned[offer.id]) or 0
		text(t, owned > 0 and ("You own " .. owned) or "New for you!", {
			Position = UDim2.fromOffset(10, 192),
			Size = UDim2.new(1, -20, 0, 20),
			TextSize = 14,
			Font = BOLD_FONT,
			TextColor3 = owned > 0 and DIM or GOOD,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local props = { Position = UDim2.fromOffset(10, 220), Size = UDim2.new(1, -20, 0, 40) }
		if s.bought["s" .. offer.slot] then
			statusButton(t, "Bought ✓", GOOD:Lerp(TILE, 0.4), props)
		else
			priceButton(t, { Coins = offer.price }, function()
				send("Buy", "card", offer.slot)
			end, props)
		end
	end
end

-- 🎨 Deck & Field
local function cosmeticTile(grid, c, s, order)
	local owned = s.owned[c.id] == true
	local isOn = (c.kind == "board" and s.equipped.board == c.id) or (c.kind == "cardback" and s.equipped.cardback == c.id) or (c.kind == "backdrop" and s.equipped.backdrop == c.id)
	local t = tile(grid, order, isOn)
	local preview = make("Frame", { Name = "Preview", Size = UDim2.new(1, -20, 0, 96), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = rgb(24, 20, 36) }, t)
	corner(preview, 10)
	if c.kind == "board" then
		local p = Cosmetics.previewBoard(preview, c.id, UDim2.fromOffset(120, 80))
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
	elseif c.kind == "cardback" then
		local p = Cosmetics.previewBack(preview, c.id, UDim2.fromOffset(60, 84))
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(0.5, 0.5)
	elseif c.kind == "backdrop" then
		-- the world's two colours with its emoji (the Deck Shelf can preview it for real)
		local info = require(here:WaitForChild("Backdrops")).ByKey[c.backdrop or ""]
		if info then
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new(info.colors[1], info.colors[2]) }, preview)
			preview.BackgroundColor3 = rgb(255, 255, 255)
			text(preview, info.emoji, { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = BOLD_FONT, TextXAlignment = Enum.TextXAlignment.Center })
		end
	else
		text(preview, c.icon or "💬", { Size = UDim2.fromScale(1, 1), TextScaled = true, Font = BOLD_FONT, TextXAlignment = Enum.TextXAlignment.Center })
	end
	text(t, c.name, { Position = UDim2.fromOffset(10, 112), Size = UDim2.new(1, -20, 0, 22), Font = TITLE_FONT, TextSize = 18 })
	text(t, c.blurb or (c.kind == "emote" and "Pops up over your hero in a match." or ""), { Position = UDim2.fromOffset(10, 136), Size = UDim2.new(1, -20, 0, 34), TextSize = 13, TextColor3 = DIM, TextYAlignment = Enum.TextYAlignment.Top })
	local props = { Position = UDim2.new(0, 10, 1, -48), Size = UDim2.new(1, -20, 0, 38) }
	if not owned and (c.road or not c.price) then
		statusButton(t, "🏆 Trophy Road reward", rgb(150, 105, 50), props)
	elseif not owned then
		priceButton(t, c.price, function()
			send("Buy", "cosmetic", c.id)
		end, props)
	elseif c.kind == "emote" then
		statusButton(t, "Owned ✓", GOOD:Lerp(TILE, 0.4), props)
	elseif isOn then
		statusButton(t, "Equipped ✓", GOOD:Lerp(TILE, 0.3), props)
	else
		button(t, "Equip", rgb(130, 190, 255), function()
			send("Equip", c.kind, c.id)
		end, props)
	end
end

function builders.cosmetics(content, s)
	local groups = {
		{ kind = "board", title = "Board themes", sub = "Repaints the duel table: felt, rim, frame and trim. You see it in the room and in every match." },
		{ kind = "cardback", title = "Card backs", sub = "The back of every face-down card: your draws and the bot's hand." },
		{ kind = "emote", title = "Emotes", sub = "Use them from the 💬 button in a match." },
		{ kind = "backdrop", title = "Match backgrounds", sub = "The world around the table in your matches. Try them on and pick one at the Deck Shelf; three more are on the Trophy Road." },
	}
	for gi, g in ipairs(groups) do
		local _, grid = section(content, g.title, g.sub, gi)
		gridLayout(grid, 176, 230)
		local n = 0
		for _, c in ipairs(ShopCatalog.Cosmetics) do
			if c.kind == g.kind then
				n += 1
				cosmeticTile(grid, c, s, n)
			end
		end
	end
	local S = ShopCatalog.DeckSlots
	local _, grid = section(content, "Deck slots", "Each slot keeps one saved deck.", 10)
	gridLayout(grid, 362, 110)
	local t = tile(grid, 1)
	text(t, "📚  " .. s.deckSlots .. " / " .. S.max .. " deck slots", { Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 30), Font = TITLE_FONT, TextSize = 22 })
	local props = { Position = UDim2.new(0, 14, 1, -50), Size = UDim2.new(1, -28, 0, 38) }
	if s.deckSlots >= S.max then
		statusButton(t, "All slots unlocked ✓", GOOD:Lerp(TILE, 0.4), props)
	else
		priceButton(t, S.price, function()
			send("Buy", "deckslot")
		end, props)
	end
end

-- 💎 Exchange & Boosts
function builders.exchange(content, s)
	local _, grid = section(content, "Gem bundles", "Gems open card packs at the Pack Party. Bought with Robux.", 1)
	gridLayout(grid, 176, 170)
	for k, b in ipairs(ShopCatalog.GemBundles) do
		local t = tile(grid, k, b.bonus > 0)
		text(t, "💎 " .. ShopCatalog.format(b.gems + b.bonus), { Position = UDim2.fromOffset(10, 12), Size = UDim2.new(1, -20, 0, 34), Font = TITLE_FONT, TextSize = 28, TextColor3 = GEM, TextXAlignment = Enum.TextXAlignment.Center })
		text(t, b.name, { Position = UDim2.fromOffset(10, 50), Size = UDim2.new(1, -20, 0, 20), Font = BOLD_FONT, TextXAlignment = Enum.TextXAlignment.Center })
		if b.bonus > 0 then
			local tag = text(t, "+" .. ShopCatalog.format(b.bonus) .. " bonus!", { Position = UDim2.fromOffset(30, 74), Size = UDim2.new(1, -60, 0, 22), Font = BOLD_FONT, TextSize = 14, TextColor3 = INK, BackgroundTransparency = 0, BackgroundColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center })
			corner(tag, 8)
		end
		local props = { Position = UDim2.new(0, 10, 1, -48), Size = UDim2.new(1, -20, 0, 38) }
		if b.productId == 0 then
			statusButton(t, "Not on sale yet", nil, props)
		elseif s.gemsRestricted then
			statusButton(t, "Not available", nil, props)
		else
			button(t, "R$ " .. b.robux, rgb(120, 230, 140), function()
				send("BuyGems", b.id)
			end, props)
		end
	end
	if s.gemsRestricted then
		text(content, "Gem bundles aren't available where you live, because Gems open random packs. You can still earn Gems by playing.", { LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = DIM, TextSize = 14 })
	end

	local _, grid2 = section(content, "Exchange", nil, 3)
	gridLayout(grid2, 240, 150)
	for k, e in ipairs(ShopCatalog.Exchanges) do
		local t = tile(grid2, k)
		local gc, gn = ShopCatalog.priceOf(e.give)
		local rc, rn = ShopCatalog.priceOf(e.get)
		do
			-- [icon] give  →  [icon] get, centered
			local trade = make("Frame", { Name = "Trade", Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 30), BackgroundTransparency = 1 }, t)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, trade)
			UIKit.currency(trade, gc, ShopCatalog.format(gn), { size = 22, color = TEXT }).LayoutOrder = 1
			text(trade, "→", { Size = UDim2.fromOffset(24, 30), Font = TITLE_FONT, TextSize = 22, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
			UIKit.currency(trade, rc, ShopCatalog.format(rn), { size = 22, color = TEXT }).LayoutOrder = 3
		end
		local used = s.exchanges[e.id] or 0
		local left = e.perDay and (e.perDay - used) or nil
		text(t, e.blurb .. (left and ("  (" .. left .. " left today)") or ""), { Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 0, 40), TextSize = 13, TextColor3 = DIM, TextYAlignment = Enum.TextYAlignment.Top })
		local props = { Position = UDim2.new(0, 12, 1, -48), Size = UDim2.new(1, -24, 0, 38) }
		if left and left <= 0 then
			statusButton(t, "Come back tomorrow", nil, props)
		else
			local b = priceButton(t, e.give, function()
				send("Buy", "exchange", e.id)
			end, props)
			UIKit.caption(b, gc, "Trade " .. ShopCatalog.format(gn))
		end
	end

	local luckLine = "🍀 Lucky pulls left: " .. s.luckCharges
	local xpLeft = since(s.xpBoostLeft)
	local xpLine = xpLeft > 0 and ("⚡ Double XP: " .. duration(xpLeft) .. " left") or "⚡ No XP boost on"
	local odds = nil
	pcall(function()
		local pr = ReplicatedStorage:FindFirstChild("PackBrawl") and ReplicatedStorage.PackBrawl:FindFirstChild("PullRates")
		if pr then
			local PullRates = require(pr)
			if PullRates.luckyOdds then
				local o = PullRates.luckyOdds(ShopCatalog.LuckMultiplier)
				odds = string.format("Lucky odds: Epic %g%%, Mythic %g%%, Legendary %g%%, Secret %g%% (Common %g%%).", o.Epic, o.Mythic, o.Legendary, o.Secret, o.Common)
			end
		end
	end)
	local _, grid3 = section(content, "Boosters", luckLine .. "     " .. xpLine .. "\nA lucky pull multiplies the chance of Epic and better by " .. ShopCatalog.LuckMultiplier .. " for one pack opening (a 10-pack counts as one). " .. (odds or ""), 4)
	gridLayout(grid3, 176, 170)
	for k, b in ipairs(ShopCatalog.Boosts) do
		local t = tile(grid3, k)
		text(t, (b.kind == "luck" and "🍀 " or "⚡ ") .. b.name, { Position = UDim2.fromOffset(10, 12), Size = UDim2.new(1, -20, 0, 26), Font = TITLE_FONT, TextSize = 19 })
		text(t, b.blurb, { Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -20, 0, 56), TextSize = 13, TextColor3 = DIM, TextYAlignment = Enum.TextYAlignment.Top })
		priceButton(t, b.price, function()
			send("Buy", "boost", b.id)
		end, { Position = UDim2.new(0, 10, 1, -48), Size = UDim2.new(1, -20, 0, 38) })
	end
end

local TABS = {
	{ key = "daily", name = "🃏 Daily Cards" },
	{ key = "cosmetics", name = "🎨 Deck & Field" },
	{ key = "exchange", name = "💎 Exchange & Boosts" },
}

local function rebuild(keepScroll)
	local content = state.content
	if not content or not state.window.Visible then
		return
	end
	local y = keepScroll and content.CanvasPosition.Y or 0
	for _, c in ipairs(content:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
	for key, b in pairs(state.tabButtons) do
		local on = key == state.tab
		b.BackgroundColor3 = on and GOLD or TILE
		b.TextColor3 = on and INK or TEXT
	end
	local s = state.snap
	if not s then
		text(content, "Loading your save...", { Size = UDim2.new(1, 0, 0, 30) })
		return
	end
	builders[state.tab](content, s)
	content.CanvasPosition = Vector2.new(0, y)
end

local function buildWindow()
	local w = make("Frame", {
		Name = "ShopWindow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 24, 0.5, 6),
		Size = UDim2.new(1, -450, 0.74, 0),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.04,
		Visible = false,
	}, state.gui)
	make("UISizeConstraint", { MaxSize = Vector2.new(1000, 720), MinSize = Vector2.new(420, 360) }, w)
	corner(w, 18)
	stroke(w, rgb(242, 230, 201), 3)
	text(w, "SHOP", { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(160, 40), Font = TITLE_FONT, TextSize = 34, TextColor3 = GOLD, TextWrapped = false })
	text(w, "Pickles' counter", { Position = UDim2.fromOffset(122, 22), Size = UDim2.fromOffset(200, 22), TextSize = 14, TextColor3 = DIM, TextWrapped = false })
	ShopUI.hud(w, UDim2.new(1, -62, 0, 12)).Name = "WindowHud"
	-- (a drawn ✕: Roblox's fonts have none, so the old one showed as an empty box)
	local close = UIKit.closeButton(w, function()
		ShopUI.close()
	end, { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(40, 40) })
	close.ZIndex = 3
	local tabs = make("Frame", { Name = "Tabs", Position = UDim2.fromOffset(16, 62), Size = UDim2.new(1, -32, 0, 44), BackgroundTransparency = 1 }, w)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, t in ipairs(TABS) do
		state.tabButtons[t.key] = button(tabs, t.name, TILE, function()
			if state.tab ~= t.key then
				state.tab = t.key
				Juice.sound("tick", 1.2, 0.4)
				rebuild(false)
			end
		end, { Name = "Tab_" .. t.key, Size = UDim2.new(1 / 3, -6, 1, 0), LayoutOrder = i, TextColor3 = TEXT })
	end
	local content = make("ScrollingFrame", {
		Name = "Content",
		Position = UDim2.fromOffset(16, 116),
		Size = UDim2.new(1, -24, 1, -128),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
	}, w)
	make("UIListLayout", { Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 16) }, content)
	state.window = w
	state.content = content
end

function ShopUI.open(tab)
	if not state.window then
		return
	end
	if tab and builders[tab] then
		state.tab = tab
	end
	UIKit.keepOpen(state.window)
	local was = state.window.Visible
	state.window.Visible = true -- (UIKit.Focus springs it in and clears the screen around it)
	if not was then
		Juice.sound("whoosh", 1.15, 0.25)
	end
	rebuild(false)
end

function ShopUI.close(instant)
	if state.window then
		if instant then
			state.window.Visible = false
		else
			UIKit.close(state.window)
		end
	end
end

function ShopUI.isOpen()
	return state.window ~= nil and state.window.Visible
end

---------------------------------------------------------------------------
-- The Shop counter's right-hand panel
---------------------------------------------------------------------------
function ShopUI.stationPanel(body)
	local list = make("Frame", { Name = "ShopSummary", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local lines = {}
	local function line(order, size)
		local l = text(list, "", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, size or 22), TextSize = 16 })
		table.insert(lines, l)
		return l
	end
	-- your wallet: [gem] 1,720   [coin] 300
	local money = make("Frame", { Name = "Wallet", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, list)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }, money)
	local _, gemsValue = UIKit.currency(money, "Gems", "", { size = 22 })
	local coinsRow, coinsValue = UIKit.currency(money, "Coins", "", { size = 22 })
	coinsRow.LayoutOrder = 2
	local level = line(2)
	local bar = make("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = TILE }, list)
	corner(bar, 6)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = GOLD }, bar)
	corner(fill, 6)
	local boosts = line(4, 44)
	local daily = line(5, 44)
	local tip = line(7, 70)
	tip.TextColor3 = DIM
	tip.TextSize = 14
	tip.Text = "Win bot matches for Coins and XP. The first win each day gives 💎 " .. ShopCatalog.Match.firstWinGems .. ". Level ups give 💎 " .. ShopCatalog.LevelUpGems .. ". Gems open packs at the Pack Party."
	button(list, "Open the Shop", GOLD, function()
		ShopUI.open()
	end, { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 48) })
	local p = {}
	function p.set(s)
		if not list.Parent then
			return
		end
		gemsValue.Text = ShopCatalog.format(s.gems)
		coinsValue.Text = ShopCatalog.format(s.coins)
		-- The same level as the profile card (the player's Level / XP / XPNeeded attributes), so the
		-- two never disagree; the shop's own numbers are only a fallback.
		local lp = Players.LocalPlayer
		local lv = lp and lp:GetAttribute("Level") or s.level
		local xp = lp and lp:GetAttribute("XP") or s.xp
		local need = lp and lp:GetAttribute("XPNeeded") or s.xpNeed
		level.Text = "Level " .. lv .. "  ·  " .. xp .. " / " .. need .. " XP"
		tween(fill, 0.4, { Size = UDim2.fromScale(math.clamp(xp / math.max(1, need), 0, 1), 1) })
		local xpLeft = since(s.xpBoostLeft)
		boosts.Text = "🍀 Lucky pulls: " .. s.luckCharges .. "\n⚡ " .. (xpLeft > 0 and ("Double XP for " .. duration(xpLeft)) or "No XP boost")
		daily.Text = "🔥 Login streak: " .. s.streak .. " day" .. (s.streak == 1 and "" or "s") .. "\n🎮 Paid matches left today: " .. s.paidMatchesLeft .. (s.firstWinLeft and "  (first win bonus ready!)" or "")
		if s.memoryOnly then
			tip.Text = "⚠ Saving is off in this Studio test. Turn on Game Settings > Security > Studio Access to API Services to keep Gems and cards."
			tip.TextColor3 = rgb(255, 170, 120)
		end
	end
	table.insert(state.panels, p)
	if state.snap then
		p.set(state.snap)
	end
	return list
end

---------------------------------------------------------------------------
-- Emotes in a match
---------------------------------------------------------------------------
local BOT_EMOTES = { "emote_hello", "emote_nice", "emote_haha", "emote_hmm", "emote_grr" }

-- myHero / theirHero: functions that return the part to show the bubble over.
function ShopUI.mountEmotes(matchUI, myHero, theirHero)
	-- It sits just above your bar (bottom left), clear of your hand.
	local holder = make("Frame", { Name = "Emotes", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -180), Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 1 }, matchUI)
	local menu = make("Frame", { Name = "EmoteMenu", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 0, -8), Size = UDim2.fromOffset(200, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL, Visible = false }, holder)
	corner(menu, 12)
	stroke(menu, GOLD, 2)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, menu)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, menu)
	local last = 0
	local function fill()
		for _, c in ipairs(menu:GetChildren()) do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local s = state.snap
		for i, c in ipairs(ShopCatalog.Cosmetics) do
			if c.kind == "emote" and (c.default or (s and s.owned[c.id])) then
				button(menu, c.icon .. "  " .. c.name, TILE, function()
					menu.Visible = false
					if time() - last < 3 then
						return
					end
					last = time()
					send("Emote", c.id)
				end, { Name = c.id, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = i, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextSize = 17 })
			end
		end
	end
	button(holder, "💬", rgb(70, 85, 125), function()
		menu.Visible = not menu.Visible
		if menu.Visible then
			fill()
		end
	end, { Name = "EmoteButton", Size = UDim2.fromScale(1, 1), TextScaled = false, TextSize = 24 })
	table.insert(state.emoteFns, function(payload)
		if not holder.Parent or not matchUI.Visible then
			return
		end
		local part = myHero and myHero()
		if part then
			Cosmetics.emote(part, payload.id)
		end
		-- Bot Bonkers sometimes answers
		if math.random() < 0.45 then
			task.delay(1.1 + math.random() * 0.8, function()
				local their = theirHero and theirHero()
				if their and matchUI.Visible then
					Cosmetics.emote(their, BOT_EMOTES[math.random(1, #BOT_EMOTES)], { color = rgb(226, 232, 255) })
				end
			end)
		end
	end)
	return holder
end

---------------------------------------------------------------------------
-- Server messages
---------------------------------------------------------------------------
local function onSnapshot(s)
	state.snap = s
	state.snapAt = time()
	Cosmetics.setEquipped(s.equipped)
	for _, h in ipairs(state.huds) do
		h.set(s)
	end
	for _, p in ipairs(state.panels) do
		p.set(s)
	end
	for _, fn in ipairs(state.snapFns) do
		task.spawn(fn, s)
	end
	if ShopUI.isOpen() then
		rebuild(true)
	end
end

local function onEvent(kind, payload)
	if kind == "snapshot" and type(payload) == "table" then
		onSnapshot(payload)
	elseif kind == "result" and type(payload) == "table" then
		if payload.ok then
			ShopUI.toast(payload.message, "good")
			Juice.sound("twang", 1.25, 0.4)
			if state.window and state.window.Visible then
				Juice.confetti(state.gui, 0.5, 0.25, 26)
			end
		else
			ShopUI.toast(payload.message or "That didn't work.", "bad")
			Juice.sound("thud", 1, 0.4)
			if ShopUI.isOpen() then
				rebuild(true) -- put the button's price back
			end
		end
	elseif kind == "daily" and type(payload) == "table" then
		local msg = string.format("Daily reward! Day %d streak: +%s Coins, +%s Gems", payload.streak, ShopCatalog.format(payload.coins), ShopCatalog.format(payload.gems))
		task.spawn(function()
			-- wait until the title screen is gone, so the reward isn't missed behind it
			local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
			local waited = 0
			while pg and pg:FindFirstChild("DeckWarsTitle") and waited < 120 do
				task.wait(0.5)
				waited += 0.5
			end
			task.wait(0.8)
			ShopUI.toast(msg, "info", { big = true, icon = "🎁" })
		end)
	elseif kind == "reward" and type(payload) == "table" then
		if payload.coins > 0 or payload.xp > 0 then
			local parts = { "+" .. payload.coins .. " Coins", "+" .. payload.xp .. " XP" .. (payload.boosted and " (x2)" or "") }
			if payload.gems > 0 then
				table.insert(parts, "+" .. payload.gems .. " Gems (first win today!)")
			end
			ShopUI.toast(table.concat(parts, "   "), "coin", { big = true, icon = "Coins" })
			if payload.levels and payload.levels > 0 then
				task.delay(1.2, function()
					ShopUI.toast(string.format("Level up! You're level %d: +%d Gems, +%d Coins", state.snap and state.snap.level or 0, payload.levelGems or 0, payload.levelCoins or 0), "gem", { big = true, icon = "⬆" })
				end)
			end
		elseif payload.note == "too short" then
			ShopUI.toast("That match was too short to pay out.", "info")
		elseif payload.note == "daily limit" then
			ShopUI.toast("You've had all your paid matches today. Coins are back tomorrow!", "info")
		end
	elseif kind == "notice" and type(payload) == "string" then
		ShopUI.toast(payload, "info", { time = 6 })
	elseif kind == "emote" and type(payload) == "table" then
		for _, fn in ipairs(state.emoteFns) do
			task.spawn(fn, payload)
		end
	end
end

function ShopUI.snapshot()
	return state.snap
end

function ShopUI.onSnapshot(fn)
	table.insert(state.snapFns, fn)
	if state.snap then
		task.spawn(fn, state.snap)
	end
end

function ShopUI.init(opts)
	if state.ready then
		return
	end
	state.ready = true
	opts = opts or {}
	state.makeCard = opts.makeCard
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	state.gui = make("ScreenGui", { Name = "DeckWarsShop", ResetOnSpawn = false, DisplayOrder = 6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	state.toastGui = make("ScreenGui", { Name = "DeckWarsToasts", ResetOnSpawn = false, DisplayOrder = 60, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	state.toastHolder = make("Frame", { Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16), Size = UDim2.fromOffset(540, 400), BackgroundTransparency = 1 }, state.toastGui)
	make("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, state.toastHolder)
	buildWindow()
	EconomyEvent.OnClientEvent:Connect(onEvent)
	ShopAction:FireServer("Snapshot")
	-- keep countdowns honest while the window is open
	task.spawn(function()
		while true do
			task.wait(30)
			if ShopUI.isOpen() then
				ShopAction:FireServer("Snapshot")
			end
		end
	end)
end

return ShopUI

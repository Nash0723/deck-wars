-- QuestHallUI: the Quest Hall's window in the Park, your quests on the hall's boards, and the
-- Quest Hall card on the Trophy Wall in your room. Client only.
--
-- Quests are finished anywhere (a match, the Campaign, the Pack Party, the crystal...) and
-- claimed at Quill's counter in the Quest Hall on the north lawn of the Park: ParkClient opens
-- this window from the counter's "Quests" prompt. What the quests are and what they pay is in
-- Quests; the save and the rules are on the server (QuestBook, through QuestServer and
-- ReplicatedStorage.QuestRemotes).
--
--   QuestHallUI.init(ctx)        once, from ParkClient. ctx: gui, makeCard, toast, inPark(),
--                                keeper(kind) (Quill hops ("hop") or nods ("nod")), desk() (the
--                                counter's Desk part: walk away from it and the window closes)
--   QuestHallUI.open(tab) / QuestHallUI.close() / QuestHallUI.isOpen()
--   QuestHallUI.escape()         Escape: puts the chest scene away first (true if it did)
--   QuestHallUI.request()        asks the server for a fresh copy of your quests
--   QuestHallUI.book()           the latest copy (QuestBook.snapshot), or nil
--   QuestHallUI.onBook(fn)       fn(book) whenever a fresh copy arrives; returns a disconnect fn
--   QuestHallUI.drawBoards(hall) your quests on the hall's boards (everyone sees their own)
--   QuestHallUI.summary(parent, order, opts)  the Trophy Wall's card (opts.walk: "Walk there")
--
-- The window: Daily, Weekly and Journey tabs, a card for each quest (its progress, what it pays
-- and Claim or Swap), a word from Quill, and the week's Renown track with its four Quest Chests
-- along the bottom. Claiming slams a wax seal onto the card, the rewards fly up into your Gems,
-- Shards and level badge, Renown runs along the track and a chest it reaches starts to glow.
-- Opening a chest plays its own scene: it drops in, shakes, bursts open and its prizes rise out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local here = script.Parent
local Quests = require(here:WaitForChild("Quests"))
local Campaign = require(here:WaitForChild("Campaign"))
local Backdrops = require(here:WaitForChild("Backdrops"))
local CardData = require(here:WaitForChild("CardData"))
local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
local Juice = require(here:WaitForChild("Juice"))
local UIKit = require(here:WaitForChild("UIKit"))
local MenuBriefs = require(here:WaitForChild("MenuBriefs"))

local player = Players.LocalPlayer

local rgb, make = Juice.rgb, Juice.make
local INK = rgb(18, 14, 28)
local PANEL = rgb(30, 25, 46)
local TILE = rgb(42, 36, 62)
local TILE_DONE = rgb(33, 28, 48)
local GOLD = rgb(255, 214, 102)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(170, 164, 190)
local FAINT = rgb(118, 112, 140)
local GOOD = rgb(70, 190, 110)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local BOLD_FONT = Enum.Font.GothamBold

local function c3(t)
	return rgb(t[1], t[2], t[3])
end
local function darken(c, k)
	return c:Lerp(BLACK, k)
end
local function lighten(c, k)
	return c:Lerp(WHITE, k)
end

local KIND = { daily = c3(Quests.Colors.daily), weekly = c3(Quests.Colors.weekly), journey = c3(Quests.Colors.journey) }
local RENOWN = c3(Quests.Colors.renown)
local XP_COLOR = rgb(130, 200, 255)
local SWAP_COLOR = rgb(64, 56, 100)
local TABS = { "daily", "weekly", "journey" }
local TAB_NAME = { daily = "Daily", weekly = "Weekly", journey = "Journey" }
local TAB_ICON = { daily = "☀️", weekly = "🌙", journey = "🗺" }
local GROUP_NAME = { core = "Core", battle = "Battle", campaign = "Campaign", collection = "Collection" }
local STEP_NAME = { act3 = "Acts 1-3", boss = "Boss", stars = "Stars", hard = "Hard mode" }
local ROMAN = { "I", "II", "III" }
-- the boards on the hall's walls: dark brown ink on parchment, the headings in the kinds' colours
local INK_BROWN = rgb(66, 44, 30)
local BOARD_COLOR = { daily = rgb(38, 110, 70), weekly = rgb(38, 82, 158), journey = rgb(106, 60, 158) }

local W, H = 900, 620 -- the window's size (it shrinks to fit a small screen)
local RIGHT = 252 -- the quest cards' column for the rewards and the button

-- What Quill says at the top of the list (one each time you open the window).
local TIPS = {
	"Hoo! Quests count everywhere: the Duel Table, the Campaign, packs and the crystal. You claim them here.",
	"Every quest you claim adds Renown. Fill the track for this week's four Quest Chests.",
	"Stuck on one? Swap it. One free swap a day, and one a week for the weekly quests.",
	"Finished quests wait for you, even after the day ends. Come by whenever you like.",
	"The Journey follows your Campaign. Clear a world, then come and see me.",
	"The Crystal Chest at the end of the track holds an Epic card and a Luck Potion.",
}

local QuestHallUI = {}

local S = {
	ctx = nil,
	listening = false,
	action = nil, -- QuestRemotes.QuestAction
	wantState = false, -- (a fresh copy was asked for before the remotes were found)
	book = nil, -- the latest QuestBook.snapshot
	bookAt = 0, -- os.clock() when it arrived (the reset countdowns count from then)
	nextFire = 0,
	lastAsk = -10,
	lastStale = -10,
	revPending = false,
	listeners = {},
	tab = nil,
	tip = math.random(1, #TIPS),
	root = nil, -- the window's outer frame (it fits the screen); S.ui.panel is the window itself
	ui = nil,
	busy = nil, -- { what, token } while a claim, a swap or a chest is on its way
	armed = nil, -- the quest whose Swap was tapped once ("Sure?")
	just = nil, -- { claimed = key } or { swapped = key }: the next render plays that card's moment
	claimFrom = nil, -- where the claimed quest's rewards were on the screen
	walletFrom = nil, -- what the wallet shows until the rewards land
	renownFrom = nil, -- where the Renown track starts until the Renown lands
	hold = 0, -- until then the wallet waits for flying rewards
	reveal = nil, -- the chest scene while it's up
	summary = nil, -- the Trophy Wall's card while it's up
	boards = nil, -- the boards' countdown lines
}
QuestHallUI.S = S -- (for the tests)

local render -- (below)

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function corner(p, r)
	return make("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, p)
end

local function stroke(p, color, t, transparency)
	return make("UIStroke", { Color = color or INK, Thickness = t or 2, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function gradient(p, top, bottom, rotation)
	return make("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(top, bottom) }, p)
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

local function hlist(parent, gap, halign, valign)
	return make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, gap or 6),
		HorizontalAlignment = halign or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
end

local function fmt(n)
	return ShopCatalog.format(math.floor(tonumber(n) or 0))
end

local function toast(msg)
	if S.ctx and S.ctx.toast then
		S.ctx.toast(msg)
	end
end

local function keeper(kind)
	if S.ctx and S.ctx.keeper then
		pcall(S.ctx.keeper, kind)
	end
end

local function rarityColor(rarity)
	local c = CardData.RarityColors and CardData.RarityColors[rarity]
	return c and rgb(c[1], c[2], c[3]) or TEXT
end

-- (for RichText)
local function escape(s)
	return (string.gsub(tostring(s), "[<>&]", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;" }))
end

local function plural(n, one, many)
	return n == 1 and one or many
end

local function centerOf(obj)
	return obj.AbsolutePosition + obj.AbsoluteSize / 2
end

-- A point on the screen (pixels) in the window's own coordinates (it may be scaled to fit).
local function toPanel(abs)
	local panel = S.ui.panel
	local k = panel.AbsoluteSize.X / W
	if k <= 0 then
		k = 1
	end
	return (abs - panel.AbsolutePosition) / k
end

-- A point on the screen as 0..1 of the Park's ScreenGui (for Juice's confetti and stars).
local function onScreen(abs)
	local gui = S.ctx and S.ctx.gui
	if not gui then
		return 0.5, 0.5
	end
	local size = gui.AbsoluteSize
	return (abs.X - gui.AbsolutePosition.X) / math.max(1, size.X), (abs.Y - gui.AbsolutePosition.Y) / math.max(1, size.Y)
end

-- A label counting from one number to another.
local function countUp(label, from, to, time, format)
	if not label or not label.Parent then
		return
	end
	format = format or fmt
	local nv = Instance.new("NumberValue")
	nv.Value = from
	label.Text = format(from)
	nv.Changed:Connect(function(v)
		if label.Parent then
			label.Text = format(v)
		end
	end)
	local tw = Juice.tween(nv, time or 0.6, { Value = to }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tw.Completed:Connect(function()
		if label.Parent then
			label.Text = format(to)
		end
		nv:Destroy()
	end)
end

local function fit(frame, width, height)
	local cam = workspace.CurrentCamera
	local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local scale = math.min(1, (view.X - 24) / width, (view.Y - 24) / height)
	if scale < 1 then
		make("UIScale", { Name = "Fit", Scale = math.max(0.4, scale) }, frame)
	end
end

---------------------------------------------------------------------------
-- Drawn marks: Renown's seal, the XP tag, the wax seal and the Quest Chests
---------------------------------------------------------------------------

-- Renown's mark: a gold seal (a diamond in a darker rim, with a bright heart).
local function renownIcon(parent, px, props)
	px = px or 18
	local c = make("Frame", { Name = "RenownIcon", Size = UDim2.fromOffset(px, px), BackgroundTransparency = 1 }, parent)
	local rim = make("Frame", { Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.72, 0.72), Rotation = 45, BackgroundColor3 = rgb(128, 72, 24), BorderSizePixel = 0 }, c)
	corner(rim, math.max(1, math.floor(px * 0.1)))
	local edge = math.max(2, math.floor(px * 0.16 + 0.5))
	local face = make("Frame", { Name = "Face", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -edge, 1, -edge), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, rim)
	corner(face, math.max(1, math.floor(px * 0.08)))
	gradient(face, rgb(255, 238, 160), rgb(236, 150, 44), 45)
	local heart = make("Frame", { Name = "Heart", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.36, 0.36), BackgroundColor3 = rgb(255, 252, 230), BorderSizePixel = 0 }, face)
	corner(heart, 2)
	for k, v in pairs(props or {}) do
		c[k] = v
	end
	return c
end

-- XP: a small blue tag.
local function xpIcon(parent, px, props)
	px = px or 18
	local c = make("TextLabel", {
		Name = "XPIcon",
		Size = UDim2.fromOffset(math.floor(px * 1.5), px),
		BackgroundColor3 = XP_COLOR,
		Text = "XP",
		Font = TITLE_FONT,
		TextSize = math.max(9, math.floor(px * 0.6)),
		TextColor3 = rgb(16, 34, 60),
	}, parent)
	corner(c, math.floor(px / 2))
	stroke(c, rgb(16, 34, 60), 1.5, 0.3)
	for k, v in pairs(props or {}) do
		c[k] = v
	end
	return c
end

local function rewardIcon(parent, kind, px, props)
	if kind == "Gems" or kind == "Shards" or kind == "Coins" then
		return UIKit.icon(parent, kind, px, props)
	elseif kind == "XP" then
		return xpIcon(parent, px, props)
	end
	return renownIcon(parent, px, props)
end

-- One reward as [icon] amount (Gems, Shards, Coins, XP or Renown). Returns its row.
local function rewardItem(parent, kind, amount, size, order)
	size = size or 15
	if kind == "Gems" or kind == "Shards" or kind == "Coins" then
		local row = UIKit.currency(parent, kind, fmt(amount), { size = size, height = size + 8 })
		row.LayoutOrder = order or 0
		return row
	end
	local row = make("Frame", { Name = kind, Size = UDim2.fromOffset(0, size + 8), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = order or 0 }, parent)
	hlist(row, math.floor(size * 0.3))
	rewardIcon(row, kind, kind == "XP" and size + 1 or size + 4, { LayoutOrder = 1 })
	text(row, fmt(amount), {
		Name = "Value",
		Font = TITLE_FONT,
		TextSize = size,
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		TextColor3 = kind == "XP" and XP_COLOR or RENOWN,
		LayoutOrder = 2,
	})
	return row
end

-- A red wax seal with a tick, the wax run out round its edge in a few drops.
local function waxSeal(parent, px, props)
	local seal = make("Frame", { Name = "Seal", Size = UDim2.fromOffset(px, px), BackgroundTransparency = 1, Rotation = -12 }, parent)
	for k = 0, 7 do
		local a = math.rad(k * 45 + 12)
		local r = px * 0.39
		local d = px * (k % 2 == 0 and 0.34 or 0.25)
		local drop = make("Frame", { Name = "Drop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r), Size = UDim2.fromOffset(d, d), BackgroundColor3 = rgb(150, 28, 40), BorderSizePixel = 0 }, seal)
		corner(drop)
	end
	local disc = make("Frame", { Name = "Disc", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.86), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, seal)
	corner(disc)
	gradient(disc, rgb(222, 74, 80), rgb(128, 20, 32))
	local ring = make("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.68, 0.68), BackgroundTransparency = 1 }, disc)
	corner(ring)
	stroke(ring, rgb(255, 176, 166), math.max(1.5, px * 0.045), 0.3)
	text(disc, "✓", { Name = "Mark", Size = UDim2.fromScale(1, 1), Font = TITLE_FONT, TextSize = math.floor(px * 0.44), TextColor3 = rgb(255, 228, 220) })
	for k, v in pairs(props or {}) do
		seal[k] = v
	end
	return seal
end

-- A Quest Chest px wide: a body and a domed lid in the chest's colour with iron bands and a gold
-- lock. opened: the lid stands open and the inside glows. Returns the art, its lid and its lock.
local function chestArt(parent, color, px, opened, props)
	local art = make("Frame", { Name = "Art", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(px, math.floor(px * 0.84)), BackgroundTransparency = 1, ZIndex = 2 }, parent)
	local band = darken(color, 0.55)
	local line = math.max(1.5, px * 0.035)
	local body = make("Frame", { Name = "Body", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.58), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 1 }, art)
	corner(body, math.max(2, math.floor(px * 0.08)))
	gradient(body, color, darken(color, 0.42))
	stroke(body, INK, line)
	local lid = make("Frame", { Name = "Lid", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromScale(1.04, 0.42), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, art)
	corner(lid, math.max(3, math.floor(px * 0.2)))
	gradient(lid, lighten(color, 0.3), darken(color, 0.1))
	stroke(lid, INK, line)
	for _, x in ipairs({ 0.2, 0.8 }) do
		for _, piece in ipairs({ body, lid }) do
			make("Frame", { Name = "Band", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(x, 0), Size = UDim2.new(0, math.max(2, math.floor(px * 0.08)), 1, 0), BackgroundColor3 = band, BorderSizePixel = 0 }, piece)
		end
	end
	local lock = make("Frame", { Name = "Lock", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.46), Size = UDim2.fromOffset(math.max(5, math.floor(px * 0.18)), math.max(6, math.floor(px * 0.22))), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = 4 }, art)
	corner(lock, math.max(1, math.floor(px * 0.04)))
	gradient(lock, rgb(255, 238, 150), rgb(212, 146, 36))
	stroke(lock, INK, math.max(1, px * 0.025))
	if opened then
		lid.Rotation = -16
		lid.Position = UDim2.fromScale(0.4, 0.3)
		lock.Visible = false
		local glow = make("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.84, 0.13), BackgroundColor3 = rgb(255, 238, 176), BorderSizePixel = 0, ZIndex = 2 }, art)
		corner(glow, math.max(2, math.floor(px * 0.05)))
	end
	for k, v in pairs(props or {}) do
		art[k] = v
	end
	return art, lid, lock
end

---------------------------------------------------------------------------
-- The quest book (QuestBook.snapshot) and talking to the server
---------------------------------------------------------------------------

local function readyEntry(e)
	return e ~= nil and not e.claimed and e.open ~= false and (tonumber(e.progress) or 0) >= (tonumber(e.target) or 1)
end

-- How many quests in a tab are ready to claim (the waiting ones count in their own tab).
local function readyIn(book, tab)
	if not book then
		return 0
	end
	local n = 0
	if tab == "journey" then
		for _, e in ipairs(book.journey or {}) do
			if readyEntry(e) then
				n += 1
			end
		end
		return n
	end
	for _, e in ipairs(book[tab] or {}) do
		if readyEntry(e) then
			n += 1
		end
	end
	for _, e in ipairs(book.waiting or {}) do
		if e.from == tab then
			n += 1
		end
	end
	return n
end

local function bestTab(book)
	for _, t in ipairs(TABS) do
		if readyIn(book, t) > 0 then
			return t
		end
	end
	return "daily"
end

local function claimedOf(list)
	local n = 0
	for _, e in ipairs(list or {}) do
		if e.claimed then
			n += 1
		end
	end
	return n
end

local function worldOf(key)
	for _, w in ipairs(Campaign.Worlds) do
		if w.key == key then
			return w
		end
	end
	return nil
end

local function worldColors(w)
	local b = w and Backdrops.ByKey and Backdrops.ByKey[w.backdrop]
	if b and b.colors then
		return b.colors[1], b.colors[2]
	end
	return KIND.journey, darken(KIND.journey, 0.5)
end

local function since()
	return os.clock() - S.bookAt
end
local function dailyLeft()
	return S.book and math.max(0, (tonumber(S.book.resetDaily) or 0) - since()) or 0
end
local function weeklyLeft()
	return S.book and math.max(0, (tonumber(S.book.resetWeekly) or 0) - since()) or 0
end

-- Sends a request (at least 0.3 s after the one before: the server ignores them closer together).
local function fire(what, options)
	local action = S.action
	if not action then
		return false
	end
	local now = os.clock()
	local at = math.max(now, S.nextFire)
	S.nextFire = at + 0.3
	if at > now + 0.01 then
		task.delay(at - now, function()
			action:FireServer(what, options or {})
		end)
	else
		action:FireServer(what, options or {})
	end
	return true
end

function QuestHallUI.request()
	if os.clock() - S.lastAsk < 0.5 then
		return
	end
	S.lastAsk = os.clock()
	if not fire("State") then
		S.wantState = true
	end
end

function QuestHallUI.book()
	return S.book
end

function QuestHallUI.onBook(fn)
	table.insert(S.listeners, fn)
	return function()
		local i = table.find(S.listeners, fn)
		if i then
			table.remove(S.listeners, i)
		end
	end
end

local function notify()
	for i = #S.listeners, 1, -1 do
		local fn = S.listeners[i]
		if fn then
			local ok, err = pcall(fn, S.book)
			if not ok then
				warn("QuestHallUI: " .. tostring(err))
			end
		end
	end
end

-- Does anything on the screen show the quests right now (so a change is worth asking for)?
local function wanted()
	if QuestHallUI.isOpen() or (S.summary ~= nil and S.summary.Parent ~= nil) then
		return true
	end
	return S.ctx ~= nil and S.ctx.inPark ~= nil and S.ctx.inPark() == true
end

---------------------------------------------------------------------------
-- The window: header, tabs, list and the Renown track
---------------------------------------------------------------------------

function QuestHallUI.isOpen()
	return S.root ~= nil and S.root.Parent ~= nil and S.ui ~= nil
end

local function busyFor(seconds)
	local token = {}
	S.busy = { token = token }
	task.delay(seconds or 6, function()
		if S.busy and S.busy.token == token then
			S.busy = nil
			render() -- (no answer came: the buttons work again)
		end
	end)
end

local function fail(why, obj)
	if why then
		toast("📜 " .. tostring(why))
	end
	if obj and obj.Parent then
		Juice.shake(obj, 6, 0.3)
	end
	Juice.sound("thud", 0.8, 0.3)
end

-- The wallet in the window's corner (from: numbers to show instead of yours, while rewards fly).
local function walletShow(from)
	local ui = S.ui
	if not ui then
		return
	end
	local function v(name)
		return (from and from[name]) or player:GetAttribute(name) or 0
	end
	ui.gemValue.Text = fmt(v("Gems"))
	ui.shardValue.Text = fmt(v("Shards"))
	ui.coinValue.Text = fmt(v("Coins"))
	UIKit.setLevel(ui.level, (from and from.Level) or player:GetAttribute("Level") or 1)
end

local function clockLine()
	local book = S.book
	if not book then
		return ""
	end
	if S.tab == "daily" then
		local swaps = tonumber(book.dailySwaps) or 0
		return "☀️ New daily quests in " .. Quests.timeText(dailyLeft()) .. (swaps > 0 and ("  ·  " .. swaps .. plural(swaps, " free swap left", " free swaps left")) or "")
	elseif S.tab == "weekly" then
		local swaps = tonumber(book.weeklySwaps) or 0
		return "🌙 New weekly quests in " .. Quests.timeText(weeklyLeft()) .. (swaps > 0 and ("  ·  " .. swaps .. plural(swaps, " free swap left", " free swaps left")) or "")
	end
	return "🗺 Journey quests never reset"
end

local function renownLine()
	return "Claim quests to earn Renown  ·  new chests in " .. Quests.timeText(weeklyLeft())
end

local function selectTab(key)
	if S.tab == key or not S.ui then
		return
	end
	S.tab = key
	S.armed = nil
	render()
	if S.ui and S.ui.list then
		S.ui.list.CanvasPosition = Vector2.zero
	end
	Juice.sound("tick", 1.25, 0.25)
end

local function buildHeader(panel)
	local ui = S.ui
	local crest = make("Frame", { Name = "Crest", Position = UDim2.fromOffset(18, 12), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = WHITE }, panel)
	corner(crest)
	gradient(crest, rgb(134, 88, 194), rgb(52, 38, 100))
	stroke(crest, GOLD, 2.5)
	local ring = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1 }, crest)
	corner(ring)
	stroke(ring, WHITE, 1, 0.7)
	text(crest, "📜", { Size = UDim2.fromScale(1, 1), TextSize = 30, Font = TITLE_FONT })
	Juice.wobble(crest, 4, 1.3)
	local title = text(panel, "Quest Hall", { Name = "Title", Font = TITLE_FONT, TextSize = 31, TextColor3 = GOLD, Position = UDim2.fromOffset(86, 10), Size = UDim2.fromOffset(300, 36), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
	make("UIStroke", { Thickness = 1.5, Color = INK, Transparency = 0.3 }, title)
	text(panel, "Finish quests anywhere. Claim them here.", { Name = "Subtitle", TextColor3 = DIM, TextSize = 14, Position = UDim2.fromOffset(86, 46), Size = UDim2.fromOffset(300, 18), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false })
	-- your level, Coins, Shards and Gems (the rewards fly into them)
	local wallet = make("Frame", { Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -104, 0, 17), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, panel)
	hlist(wallet, 8, Enum.HorizontalAlignment.Right)
	ui.level = UIKit.levelBadge(wallet, 34, { LayoutOrder = 1 })
	local function pill(cur, order)
		local p = make("Frame", { Name = cur .. "Pill", Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, BackgroundTransparency = 0.25, LayoutOrder = order }, wallet)
		corner(p, 17)
		make("UIStroke", { Color = UIKit.currencyColor(cur), Thickness = 1.5, Transparency = 0.45 }, p)
		make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }, p)
		local _, value = UIKit.currency(p, cur, "0", { size = 17, height = 34 })
		return p, value
	end
	ui.coinPill, ui.coinValue = pill("Coins", 2)
	ui.shardPill, ui.shardValue = pill("Shards", 3)
	ui.gemPill, ui.gemValue = pill("Gems", 4)
	UIKit.closeButton(panel, QuestHallUI.close, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -48, 0, 16) })
	MenuBriefs.helpButton(panel, "QuestHall", { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -92, 0, 16) }, "center")
	-- developers: a new day or week of quests, or all of them finished (QuestServer checks too)
	if player:GetAttribute("QuestDev") == true then
		local dev = make("Frame", { Name = "Dev", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 56), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, panel)
		hlist(dev, 6, Enum.HorizontalAlignment.Right)
		for i, d in ipairs({ { "DevNewDay", "Dev: new day" }, { "DevNewWeek", "new week" }, { "DevFinish", "finish all" } }) do
			button(dev, d[2], rgb(96, 64, 140), function()
				fire(d[1])
			end, { Name = d[1], Size = UDim2.fromOffset(i == 1 and 96 or 76, 20), TextSize = 12, LayoutOrder = i })
		end
	end
end

local function buildTabs(panel)
	local ui = S.ui
	local row = make("Frame", { Name = "Tabs", Position = UDim2.fromOffset(18, 80), Size = UDim2.new(1, -36, 0, 44), BackgroundTransparency = 1 }, panel)
	ui.tabs = {}
	for i, key in ipairs(TABS) do
		local b = make("TextButton", { Name = TAB_NAME[key] .. "Tab", AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(166, 40), Position = UDim2.fromOffset((i - 1) * 176, 2), BackgroundColor3 = TILE }, row)
		corner(b, 12)
		local st = stroke(b, INK, 2)
		local label = text(b, TAB_ICON[key] .. "  " .. TAB_NAME[key], { Name = "Label", Font = TITLE_FONT, TextSize = 19, Size = UDim2.fromScale(1, 1), TextColor3 = DIM, TextWrapped = false })
		local badge = text(b, "", { Name = "Badge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -8), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 0, BackgroundColor3 = rgb(230, 70, 80), Font = TITLE_FONT, TextSize = 14, TextColor3 = WHITE, Visible = false, ZIndex = 3 })
		corner(badge)
		stroke(badge, INK, 2)
		Juice.button(b, { grow = 1.04, sound = false })
		b.Activated:Connect(function()
			selectTab(key)
		end)
		ui.tabs[key] = { button = b, stroke = st, label = label, badge = badge }
	end
	ui.clock = text(row, "", { Name = "Clock", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(320, 20), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = DIM, TextSize = 13, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
end

local function buildList(panel)
	local list = make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(16, 132),
		Size = UDim2.new(1, -32, 1, -132 - 148),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = DIM,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	corner(list, 12)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }, list)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	S.ui.list = list
end

-- The chest's look on the track: "locked" (not reached yet), "ready" (glowing: open it!) or
-- "opened" (this week's is done).
local function drawChest(i, state, force)
	local slot = S.ui and S.ui.chests and S.ui.chests[i]
	if not slot or (slot.state == state and not force) then
		return
	end
	slot.state = state
	for _, c in ipairs(slot.button:GetChildren()) do
		if c.Name == "Art" or c.Name == "Sunburst" then
			c:Destroy()
		end
	end
	local def = Quests.Chests[i]
	local color = c3(def.color)
	local shown = state == "locked" and darken(color, 0.42):Lerp(rgb(84, 80, 100), 0.45) or color
	local art = chestArt(slot.button, shown, 44, state == "opened")
	local tag = slot.tag
	if state == "ready" then
		Juice.sunburst(slot.button, lighten(color, 0.25), { length = 46, width = 14, count = 10, transparency = 0.45, speed = 40, zIndex = 1, position = UDim2.new(0.5, 0, 1, -18) })
		Juice.bob(art, 3, 4)
		tag.Text = "OPEN!"
		tag.TextColor3 = INK
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = GOLD
	elseif state == "opened" then
		tag.Text = "✓"
		tag.TextColor3 = GOOD
		tag.BackgroundTransparency = 1
	else
		tag.Text = tostring(def.at)
		tag.TextColor3 = FAINT
		tag.BackgroundTransparency = 1
	end
end

local openChest -- (below)

local function buildFooter(panel)
	local ui = S.ui
	local f = make("Frame", { Name = "Renown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -12), Size = UDim2.new(1, -32, 0, 130), BackgroundColor3 = WHITE, ZIndex = 2 }, panel)
	corner(f, 12)
	gradient(f, rgb(44, 36, 62), rgb(32, 26, 46))
	stroke(f, INK, 2, 0.2)
	local head = make("Frame", { Name = "Head", Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(330, 24), BackgroundTransparency = 1 }, f)
	hlist(head, 7)
	renownIcon(head, 22, { LayoutOrder = 1 })
	text(head, "WEEKLY RENOWN", { Font = TITLE_FONT, TextSize = 17, TextColor3 = RENOWN, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextWrapped = false, LayoutOrder = 2 })
	ui.renownValue = text(head, "0 / " .. Quests.RenownMax, { Name = "Value", Font = TITLE_FONT, TextSize = 17, TextColor3 = TEXT, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextWrapped = false, LayoutOrder = 3 })
	ui.renownHint = text(f, "", { Name = "Hint", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 11), Size = UDim2.fromOffset(440, 18), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 13, TextColor3 = DIM, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	-- the track, with the chests standing on it where their Renown is
	local track = make("Frame", { Name = "Track", Position = UDim2.fromOffset(26, 88), Size = UDim2.new(1, -82, 0, 14), BackgroundColor3 = rgb(16, 12, 26) }, f)
	corner(track, 7)
	stroke(track, INK, 2)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
	corner(fill, 7)
	make("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, rgb(236, 128, 40)), ColorSequenceKeypoint.new(0.6, RENOWN), ColorSequenceKeypoint.new(1, rgb(255, 238, 160)) }) }, fill)
	local shine = make("Frame", { Name = "Shine", Position = UDim2.fromOffset(4, 2), Size = UDim2.new(1, -8, 0, 3), BackgroundColor3 = WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0 }, fill)
	corner(shine, 2)
	ui.renownTip = make("Frame", { Name = "Tip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(8, 8), BackgroundTransparency = 1 }, fill)
	ui.renownFill = fill
	ui.chests = {}
	for i, def in ipairs(Quests.Chests) do
		local x = def.at / Quests.RenownMax
		make("Frame", { Name = "Notch", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), Size = UDim2.fromOffset(3, 10), BackgroundColor3 = INK, BackgroundTransparency = 0.3, BorderSizePixel = 0 }, track)
		local b = make("TextButton", { Name = "Chest" .. i, Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 0, -3), Size = UDim2.fromOffset(56, 46), BackgroundTransparency = 1, ZIndex = 2 }, track)
		local tag = text(track, tostring(def.at), { Name = "Tag" .. i, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(x, 0, 1, 5), Size = UDim2.fromOffset(50, 17), Font = TITLE_FONT, TextSize = 13, TextColor3 = FAINT, TextWrapped = false })
		corner(tag, 8)
		Juice.button(b, { grow = 1.12, sound = false })
		b.Activated:Connect(function()
			openChest(i)
		end)
		-- what's inside, while you point at it
		local tipBox = text(f, "", { Name = "ChestTip" .. i, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0, 26, 0, 40), Size = UDim2.fromOffset(250, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 0.05, BackgroundColor3 = rgb(16, 12, 26), TextSize = 13, Visible = false, ZIndex = 8, RichText = true })
		corner(tipBox, 8)
		stroke(tipBox, c3(def.color), 1.5, 0.2)
		make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tipBox)
		local bits = {}
		if def.gems then
			table.insert(bits, fmt(def.gems) .. " Gems")
		end
		if def.coins then
			table.insert(bits, fmt(def.coins) .. " Coins")
		end
		if def.shards then
			table.insert(bits, fmt(def.shards) .. " Shards")
		end
		if def.card then
			table.insert(bits, "a random " .. def.card .. " card")
		end
		if def.potion then
			local p = ShopCatalog.PotionById and ShopCatalog.PotionById[def.potion]
			table.insert(bits, p and p.name or "a Luck Potion")
		end
		tipBox.Text = "<b>" .. escape(def.name) .. "</b>  ·  " .. def.at .. " Renown\n" .. escape(table.concat(bits, ", "))
		b.MouseEnter:Connect(function()
			-- (above the chest, kept inside the footer: the track starts 26 in and is 82 shorter)
			tipBox.Position = UDim2.new(0, math.clamp(26 + x * (W - 32 - 82), 130, W - 32 - 130), 0, 40)
			tipBox.Visible = true
		end)
		b.MouseLeave:Connect(function()
			tipBox.Visible = false
		end)
		ui.chests[i] = { button = b, tag = tag, state = nil }
	end
end

---------------------------------------------------------------------------
-- The quest cards
---------------------------------------------------------------------------

local function medal(card, q, e, locked)
	local m = make("Frame", { Name = "Medal", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(46, 46), BackgroundColor3 = WHITE }, card)
	corner(m)
	local top, bottom, glyph, glyphColor, glyphSize = nil, nil, "", TEXT, 24
	if locked then
		top, bottom, glyph = rgb(96, 92, 110), rgb(52, 48, 64), "🔒"
	elseif q.type == "daily" then
		local c = c3(Quests.Tiers[q.tier].color)
		top, bottom, glyph, glyphColor, glyphSize = lighten(c, 0.3), darken(c, 0.32), ROMAN[q.tier] or "I", darken(c, 0.72), 21
	elseif q.type == "weekly" then
		top, bottom, glyph = lighten(KIND.weekly, 0.2), darken(KIND.weekly, 0.5), "🌙"
	else
		local w = worldOf(q.world)
		top, bottom = worldColors(w)
		glyph = w and w.emoji or "🗺"
	end
	gradient(m, top, bottom)
	stroke(m, e.claimed and darken(GOLD, 0.45) or GOLD, 2, e.claimed and 0.3 or 0)
	text(m, glyph, { Name = "Glyph", Size = UDim2.fromScale(1, 1), Font = TITLE_FONT, TextSize = glyphSize, TextColor3 = glyphColor, TextWrapped = false })
	if e.claimed then
		local shade = make("Frame", { Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BLACK, BackgroundTransparency = 0.55, ZIndex = 2 }, m)
		corner(shade)
	end
	return m
end

local function chip(parent, label, color, order)
	local c = text(parent, string.upper(label), {
		Name = "Chip",
		Font = TITLE_FONT,
		TextSize = 11,
		Size = UDim2.fromOffset(0, 18),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = darken(color, 0.6),
		TextColor3 = lighten(color, 0.25),
		TextWrapped = false,
		LayoutOrder = order or 0,
	})
	corner(c, 9)
	make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, c)
	stroke(c, color, 1, 0.45)
	return c
end

local function chipFor(q, waiting)
	if waiting then
		return q.type == "daily" and "From an earlier day" or "From last week", GOLD
	elseif q.type == "daily" then
		local tier = Quests.Tiers[q.tier]
		return tier and tier.key or "Daily", tier and c3(tier.color) or KIND.daily
	elseif q.type == "weekly" then
		return GROUP_NAME[q.group] or "Weekly", KIND.weekly
	end
	return STEP_NAME[q.step] or "Journey", KIND.journey
end

-- The seal lands: big and turned at first, then down onto the card with a thump.
local function slam(seal, card)
	local s = Juice.scaleOf(seal)
	s.Scale = 2.6
	seal.Rotation = -40
	seal.Visible = false
	local flash = make("Frame", { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 5 }, card)
	corner(flash, 12)
	task.delay(0.08, function()
		if not seal.Parent then
			return
		end
		seal.Visible = true
		Juice.tween(s, 0.16, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Juice.tween(seal, 0.16, { Rotation = -12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
	task.delay(0.25, function()
		if not card.Parent then
			return
		end
		Juice.shake(card, 6, 0.24)
		Juice.sound("thud", 1.15, 0.5)
		flash.BackgroundTransparency = 0.45
		Juice.tween(flash, 0.45, { BackgroundTransparency = 1 })
		local sx, sy = onScreen(centerOf(seal))
		Juice.stars(S.ctx.gui, sx, sy, 9, { color = rgb(255, 196, 150), size = 18, speed = 0.55, zIndex = 70 })
		task.delay(0.5, function()
			if flash.Parent then
				flash:Destroy()
			end
		end)
	end)
end

local claim, swap -- (below)

-- One quest's card. opts.waiting: finished before the reset and still waiting.
local function questCard(list, order, e, opts)
	opts = opts or {}
	local q = Quests.ById[e.id]
	if not q then
		return nil
	end
	local color = KIND[q.type] or GOLD
	local locked = e.open == false
	local ready = readyEntry(e)
	local small = q.type == "journey"
	local h = small and 80 or 90
	local holder = make("Frame", { Name = "Quest_" .. tostring(e.key), Size = UDim2.new(1, -4, 0, h), BackgroundTransparency = 1, LayoutOrder = order }, list)
	local card = make("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = e.claimed and TILE_DONE or TILE }, holder)
	corner(card, 12)
	local st = stroke(card, ready and color or INK, ready and 2.5 or 1.5, ready and 0 or 0.25)
	gradient(card, WHITE, rgb(206, 200, 222))
	local refs = { holder = holder, card = card, rewards = {} }
	-- the kind's colour down the left edge
	local stripe = make("Frame", { Name = "Stripe", Position = UDim2.fromOffset(8, 10), Size = UDim2.new(0, 5, 1, -20), BackgroundColor3 = (e.claimed or locked) and darken(color, 0.45) or color, BorderSizePixel = 0 }, card)
	corner(stripe, 3)
	medal(card, q, e, locked)
	local x0 = 82
	local rightW = RIGHT + 16
	local y1, y2, y3 = small and 9 or 11, small and 33 or 37, small and 57 or 64
	text(card, q.text, {
		Name = "Title",
		Font = BOLD_FONT,
		TextSize = small and 15 or 17,
		Position = UDim2.fromOffset(x0, y1),
		Size = UDim2.new(1, -(x0 + rightW), 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = (e.claimed or locked) and DIM or TEXT,
	})
	-- its tier (or group, or Journey step) and where to do it
	local line = make("Frame", { Name = "Line", Position = UDim2.fromOffset(x0, y2), Size = UDim2.new(1, -(x0 + rightW), 0, 18), BackgroundTransparency = 1, ClipsDescendants = true }, card)
	hlist(line, 8)
	local label, chipColor = chipFor(q, opts.waiting)
	chip(line, label, chipColor, 1)
	local hint = q.hint or ""
	if locked then
		local w = worldOf(q.world)
		hint = "Reach " .. (w and w.name or "this world") .. " in the Campaign first."
	elseif type(e.themes) == "table" and #e.themes > 0 then
		hint = "Won with " .. table.concat(e.themes, ", ") .. " so far."
	end
	if hint ~= "" then
		text(line, hint, { Name = "Hint", TextSize = 13, TextColor3 = DIM, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), TextWrapped = false, LayoutOrder = 2 })
	end
	-- progress
	local progress, target = math.min(tonumber(e.progress) or 0, tonumber(e.target) or 1), math.max(1, tonumber(e.target) or 1)
	local back = make("Frame", { Name = "Bar", Position = UDim2.fromOffset(x0, y3), Size = UDim2.new(1, -(x0 + rightW + 76), 0, 12), BackgroundColor3 = rgb(18, 14, 30) }, card)
	corner(back, 6)
	stroke(back, INK, 1.5, 0.3)
	local fillColor = e.claimed and darken(color, 0.4) or (locked and FAINT or color)
	local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(math.clamp(progress / target, 0, 1), 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, back)
	corner(fill, 6)
	gradient(fill, lighten(fillColor, 0.35), fillColor)
	if progress <= 0 then
		fill.Visible = false
	end
	text(card, e.claimed and "Done" or (fmt(progress) .. " / " .. fmt(target)), {
		Name = "Count",
		Font = TITLE_FONT,
		TextSize = 15,
		Position = UDim2.new(1, -(rightW + 68), 0, y3 - 4),
		Size = UDim2.fromOffset(64, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		TextColor3 = ready and GOLD or (e.claimed and FAINT or DIM),
	})
	-- what it pays, and Claim, Swap or the seal
	local right = make("Frame", { Name = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0, RIGHT, 1, 0), BackgroundTransparency = 1 }, card)
	local rewards = make("Frame", { Name = "Rewards", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, small and 6 or 8), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, right)
	hlist(rewards, 10, Enum.HorizontalAlignment.Right)
	for i, r in ipairs(Quests.rewardList(q)) do
		local item = rewardItem(rewards, r[1], r[2], 14, i)
		refs.rewards[r[1]] = item
		if e.claimed then
			for _, d in ipairs(item:GetDescendants()) do
				if d:IsA("TextLabel") then
					d.TextTransparency = 0.45
				end
			end
		end
	end
	local busy = S.busy ~= nil
	if e.claimed then
		local seal = waxSeal(right, small and 40 or 46, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -4, 1, -3) })
		text(right, "Claimed", { Name = "Claimed", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, small and -52 or -58, 1, small and -12 or -15), Size = UDim2.fromOffset(80, 18), Font = BOLD_FONT, TextSize = 13, TextColor3 = FAINT, TextXAlignment = Enum.TextXAlignment.Right })
		if S.just and S.just.claimed == e.key then
			slam(seal, card)
		end
	elseif locked then
		text(right, "🔒 Locked", { Name = "Locked", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -12), Size = UDim2.fromOffset(110, 20), Font = TITLE_FONT, TextSize = 14, TextColor3 = FAINT, TextXAlignment = Enum.TextXAlignment.Right })
	elseif ready then
		local b
		b = button(right, (busy and S.busy.key == e.key) and "..." or "Claim", WHITE, function()
			claim(e, refs)
		end, { Name = "Claim", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, small and -7 or -9), Size = UDim2.fromOffset(132, small and 34 or 38), TextSize = 20, TextColor3 = WHITE, TextStrokeTransparency = 0.55, TextStrokeColor3 = rgb(10, 60, 30) })
		gradient(b, rgb(124, 226, 146), rgb(34, 138, 72))
		Juice.shine(b, 2.3, UDim.new(0, 10))
		refs.button = b
		-- the card's edge glows while it waits
		Juice.onFrame(st, function(t)
			st.Transparency = 0.35 * (0.5 + 0.5 * math.sin(t * 3.2))
		end)
	elseif not opts.waiting and (q.type == "daily" or q.type == "weekly") then
		local left = S.book and tonumber(q.type == "daily" and S.book.dailySwaps or S.book.weeklySwaps) or 0
		if left > 0 then
			local armed = S.armed == e.key
			local b = button(right, armed and "Sure?" or "Swap", armed and rgb(150, 96, 40) or SWAP_COLOR, function() end, { Name = "Swap", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -11), Size = UDim2.fromOffset(92, 30), TextSize = 15, TextColor3 = armed and TEXT or DIM })
			b.Activated:Connect(function()
				swap(e, b)
			end)
			refs.swap = b
		end
	end
	S.ui.cards[e.key] = holder
	-- a swapped quest unfolds into place
	if S.just and S.just.swapped == e.key then
		card.ClipsDescendants = true
		card.Size = UDim2.fromScale(0, 1)
		local tw = Juice.tween(card, 0.26, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
		tw.Completed:Connect(function()
			card.ClipsDescendants = false
		end)
		task.delay(0.05, function()
			if card.Parent then
				local sx, sy = onScreen(centerOf(holder))
				Juice.stars(S.ctx.gui, sx, sy, 8, { color = color, size = 16, speed = 0.6, zIndex = 70 })
			end
		end)
	end
	return holder, refs
end

local function section(list, order, title, color, sub)
	order += 1
	local f = make("Frame", { Name = "Section", Size = UDim2.new(1, -4, 0, sub and 40 or 24), BackgroundTransparency = 1, LayoutOrder = order }, list)
	text(f, title, { Name = "Title", Font = TITLE_FONT, TextSize = 17, TextColor3 = color or GOLD, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if sub then
		text(f, sub, { Name = "Sub", TextSize = 12, TextColor3 = DIM, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	end
	return order
end

-- A word from Quill at the top of the list.
local function quillSays(list, order, line)
	local f = make("Frame", { Name = "Quill", Size = UDim2.new(1, -4, 0, 46), BackgroundTransparency = 1, LayoutOrder = order }, list)
	local m = make("Frame", { Name = "Face", Position = UDim2.fromOffset(2, 3), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = WHITE }, f)
	corner(m)
	gradient(m, rgb(200, 150, 104), rgb(108, 72, 46))
	stroke(m, GOLD, 2)
	text(m, "🦉", { Size = UDim2.fromScale(1, 1), TextSize = 22, Font = TITLE_FONT })
	local bubble = make("Frame", { Name = "Bubble", Position = UDim2.fromOffset(54, 2), Size = UDim2.new(1, -58, 0, 42), BackgroundColor3 = rgb(244, 234, 206) }, f)
	corner(bubble, 12)
	stroke(bubble, INK, 1.5, 0.35)
	make("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(12, 12), Rotation = 45, BackgroundColor3 = rgb(244, 234, 206), BorderSizePixel = 0 }, bubble)
	text(bubble, "<b>Quill:</b> " .. escape(line), { RichText = true, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -22, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 13, TextColor3 = rgb(72, 50, 34), TextWrapped = true })
	return f
end

-- A Campaign world's heading on the Journey tab (its colours, how many of its quests you've claimed).
local function worldHeader(list, order, w, entries)
	order += 1
	local open = entries[1] and entries[1].open ~= false
	local claimed, ready = claimedOf(entries), 0
	for _, e in ipairs(entries) do
		if readyEntry(e) then
			ready += 1
		end
	end
	local c1, c2 = worldColors(w)
	local f = make("Frame", { Name = "World_" .. w.key, Size = UDim2.new(1, -4, 0, 40), BackgroundColor3 = WHITE, BackgroundTransparency = open and 0.15 or 0.55, LayoutOrder = order }, list)
	corner(f, 10)
	make("UIGradient", { Rotation = 0, Color = ColorSequence.new(darken(c1, 0.35), darken(c2, 0.55)) }, f)
	stroke(f, open and c1 or INK, 1.5, open and 0.35 or 0.2)
	text(f, (open and w.emoji or "🔒") .. "  " .. w.name, { Font = TITLE_FONT, TextSize = 18, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -220, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = open and TEXT or DIM })
	local right
	if not open then
		right = "Reach it in the Campaign"
	elseif claimed >= #entries then
		right = "✓ All " .. #entries .. " claimed"
	elseif ready > 0 then
		right = ready .. " ready  ·  " .. claimed .. " / " .. #entries
	else
		right = claimed .. " / " .. #entries .. " claimed"
	end
	text(f, right, { Font = TITLE_FONT, TextSize = 15, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.fromOffset(220, 40), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false, TextColor3 = ready > 0 and GOLD or (open and lighten(c1, 0.3) or FAINT) })
	return order, open, claimed >= #entries
end

local function renderList(book)
	local ui = S.ui
	local list = ui.list
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	ui.cards = {}
	if not book then
		text(list, "Quill is looking for your quests...", { Name = "Waiting", TextSize = 16, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 60), LayoutOrder = 1 })
		return
	end
	local order = 1
	quillSays(list, order, TIPS[S.tip] or TIPS[1])
	if S.tab == "daily" or S.tab == "weekly" then
		local tab = S.tab
		local waiting = {}
		for _, e in ipairs(book.waiting or {}) do
			if e.from == tab then
				table.insert(waiting, e)
			end
		end
		if #waiting > 0 then
			order = section(list, order, "📬  Waiting from " .. (tab == "daily" and "earlier days" or "last week"), GOLD, "Finished before the quests changed. They keep until you claim them.")
			for _, e in ipairs(waiting) do
				order += 1
				questCard(list, order, e, { waiting = true })
			end
		end
		local entries = book[tab] or {}
		local claimed = claimedOf(entries)
		if tab == "daily" then
			order = section(list, order, "☀️  Today's quests  ·  " .. claimed .. " / " .. #entries .. " claimed", KIND.daily, "An Easy one, a Medium one and a Hard one, new every day.")
		else
			order = section(list, order, "🌙  This week's quests  ·  " .. claimed .. " / " .. #entries .. " claimed", KIND.weekly, "Bigger goals with bigger rewards, new every Monday.")
		end
		for _, e in ipairs(entries) do
			order += 1
			questCard(list, order, e)
		end
		if #entries > 0 and claimed >= #entries then
			order += 1
			text(list, tab == "daily" and ("✨  All done for today! New quests in " .. Quests.timeText(dailyLeft()) .. ". The Journey has quests that never reset.") or "🏆  Your week is complete! Quill is impressed.", { Name = "AllDone", Font = TITLE_FONT, TextSize = 15, TextColor3 = GOLD, Size = UDim2.new(1, -4, 0, 40), LayoutOrder = order })
		end
	else
		local total, claimed = #(book.journey or {}), claimedOf(book.journey)
		order = section(list, order, "🗺  Journey  ·  " .. claimed .. " / " .. total .. " claimed", KIND.journey, "Four quests in every Campaign world. They never reset, and worlds you've cleared before count.")
		for _, w in ipairs(Campaign.Worlds) do
			local entries = {}
			for _, e in ipairs(book.journey or {}) do
				local q = Quests.ById[e.id]
				if q and q.world == w.key then
					table.insert(entries, e)
				end
			end
			if #entries > 0 then
				local open, done
				order, open, done = worldHeader(list, order, w, entries)
				if open and not done then
					for _, e in ipairs(entries) do
						order += 1
						questCard(list, order, e)
					end
				end
			end
		end
	end
end

local function renderTabs(book)
	for _, key in ipairs(TABS) do
		local t = S.ui.tabs[key]
		local on = key == S.tab
		local color = KIND[key]
		t.button.BackgroundColor3 = on and darken(color, 0.62) or TILE
		t.stroke.Color = on and color or INK
		t.stroke.Thickness = on and 2.5 or 2
		t.label.TextColor3 = on and lighten(color, 0.35) or DIM
		local n = readyIn(book, key)
		t.badge.Visible = n > 0
		t.badge.Text = tostring(n)
	end
end

local function renderRenown(book)
	local ui = S.ui
	local renown = book and tonumber(book.renown) or 0
	local shown = S.renownFrom or renown
	S.renownFrom = nil
	ui.renownFill.Size = UDim2.fromScale(math.clamp(shown / Quests.RenownMax, 0, 1), 1)
	ui.renownValue.Text = fmt(math.min(shown, Quests.RenownMax)) .. " / " .. Quests.RenownMax
	for i, def in ipairs(Quests.Chests) do
		local c = book and book.chests and book.chests[i]
		local state = "locked"
		if c and c.opened then
			state = "opened"
		elseif c and c.ready and shown >= def.at then
			state = "ready"
		end
		drawChest(i, state)
	end
	ui.renownHint.Text = renownLine()
end

render = function()
	if not QuestHallUI.isOpen() then
		return
	end
	local book = S.book
	if os.clock() >= S.hold then
		walletShow(S.walletFrom)
	end
	S.walletFrom = nil
	renderTabs(book)
	renderList(book)
	renderRenown(book)
	S.ui.clock.Text = clockLine()
	S.just = nil
end

---------------------------------------------------------------------------
-- Rewards flying into the wallet
---------------------------------------------------------------------------

-- One icon flying from a to b (points in the window) along an arc; done() when it lands.
local function flyOne(kind, a, b, delay, time, done)
	local fx = S.ui and S.ui.fx
	if not fx or not fx.Parent then
		return
	end
	local icon = rewardIcon(fx, kind, 26)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromOffset(a.X, a.Y)
	icon.Visible = false
	local mid = (a + b) / 2 + Vector2.new((math.random() - 0.5) * 90, -(70 + math.random() * 60))
	local nv = Instance.new("NumberValue")
	nv.Changed:Connect(function(t)
		local p = a * ((1 - t) ^ 2) + mid * (2 * (1 - t) * t) + b * (t ^ 2)
		icon.Position = UDim2.fromOffset(p.X, p.Y)
	end)
	task.delay(delay, function()
		if not icon.Parent then
			nv:Destroy()
			return
		end
		icon.Visible = true
		Juice.popIn(icon, 0, { twist = 0, time = 0.18, sound = false })
		local tw = Juice.tween(nv, time, { Value = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tw.Completed:Connect(function()
			nv:Destroy()
			if icon.Parent then
				icon:Destroy()
			end
			if done then
				done()
			end
		end)
	end)
end

-- The rewards fly from where they were shown (screen points by kind; `fallback` for the rest) to
-- the wallet, the level badge and the Renown track. land[kind]() runs when that kind's first
-- icon arrives.
local function flyRewards(from, amounts, fallback, land)
	local ui = S.ui
	if not ui then
		return
	end
	local targets = { Gems = ui.gemPill, Shards = ui.shardPill, Coins = ui.coinPill, XP = ui.level, Renown = ui.renownTip }
	S.hold = os.clock() + 2.6
	local wave = 0
	for _, kind in ipairs({ "Gems", "Shards", "Coins", "XP", "Renown" }) do
		local amount = tonumber(amounts[kind]) or 0
		local target = targets[kind]
		if amount > 0 and target and target.Parent then
			wave += 1
			local start = toPanel(from[kind] or fallback)
			local finish = toPanel(centerOf(target))
			local n = math.clamp(math.ceil(amount / 25), 3, 6)
			local landed = false
			for i = 1, n do
				local jitter = Vector2.new((math.random() - 0.5) * 28, (math.random() - 0.5) * 14)
				flyOne(kind, start + jitter, finish, (wave - 1) * 0.13 + (i - 1) * 0.07, 0.48 + math.random() * 0.16, function()
					if target.Parent and kind ~= "Renown" then
						Juice.pop(target, 1.16, 0.3)
					end
					Juice.sound("tick", 1 + wave * 0.05 + i * 0.06, 0.22)
					if not landed then
						landed = true
						if land and land[kind] then
							land[kind]()
						end
					end
				end)
			end
		end
	end
	-- and afterwards the wallet shows your real numbers again
	task.delay(2.8, function()
		if QuestHallUI.isOpen() and os.clock() >= S.hold then
			walletShow()
		end
	end)
end

local function levelBanner(ups)
	local ui = S.ui
	if not ui or #ups == 0 then
		return
	end
	local last, gems = ups[#ups], 0
	for _, u in ipairs(ups) do
		gems += tonumber(u.gems) or 0
	end
	local b = make("Frame", { Name = "LevelUp", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(340, 60), BackgroundColor3 = WHITE, ZIndex = 55 }, ui.panel)
	corner(b, 16)
	gradient(b, rgb(255, 228, 124), rgb(228, 140, 40))
	stroke(b, INK, 2.5)
	text(b, "⭐ Level " .. tostring(last.level) .. "!", { Font = TITLE_FONT, TextSize = 27, TextColor3 = rgb(72, 36, 8), Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 5) })
	text(b, "+" .. fmt(gems) .. " Gems for the level up", { Font = BOLD_FONT, TextSize = 13, TextColor3 = rgb(92, 50, 14), Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 37) })
	Juice.popIn(b, 0, { twist = -6 })
	Juice.sound("choir", 1.1, 0.35)
	local sx, sy = onScreen(centerOf(ui.panel))
	Juice.confetti(S.ctx.gui, sx, sy - 0.18, 40)
	task.delay(2.4, function()
		if b.Parent then
			Juice.popOut(b, 0.25)
			task.delay(0.3, function()
				if b.Parent then
					b:Destroy()
				end
			end)
		end
	end)
end

-- Renown runs along the track from `from` to `to`; then every chest it reached pops open-ready.
local function fillRenown(from, to, reached)
	local ui = S.ui
	if not ui then
		return
	end
	local max = Quests.RenownMax
	ui.renownFill.Size = UDim2.fromScale(math.clamp(from / max, 0, 1), 1)
	local tw = Juice.tween(ui.renownFill, 0.75, { Size = UDim2.fromScale(math.clamp(to / max, 0, 1), 1) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	countUp(ui.renownValue, math.min(from, max), math.min(to, max), 0.75, function(v)
		return fmt(v) .. " / " .. max
	end)
	Juice.sound("charge", 1.3, 0.2)
	tw.Completed:Connect(function()
		for _, i in ipairs(reached or {}) do
			local slot = S.ui and S.ui.chests[i]
			if slot then
				drawChest(i, "ready", true)
				Juice.pop(slot.button, 1.5, 0.7)
				Juice.sound("chime", 0.95 + i * 0.08, 0.5)
				local sx, sy = onScreen(centerOf(slot.button))
				Juice.stars(S.ctx.gui, sx, sy, 10, { color = lighten(c3(Quests.Chests[i].color), 0.3), size = 20, speed = 0.7, zIndex = 70 })
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Claim, swap and the chests
---------------------------------------------------------------------------

claim = function(e, refs)
	if S.busy then
		return
	end
	busyFor(6)
	S.busy.key = e.key
	S.armed = nil
	if refs.button then
		refs.button.Text = "..."
	end
	-- where its rewards are on the screen (they fly from there once Quill says yes)
	local from = {}
	for kind, item in pairs(refs.rewards) do
		if item.Parent then
			from[kind] = centerOf(item)
		end
	end
	S.claimFrom = { key = e.key, from = from, center = centerOf(refs.card) }
	fire("Claim", { key = e.key })
end

local function onClaimed(e)
	S.busy = nil
	local cf = S.claimFrom
	S.claimFrom = nil
	if not e.ok then
		local holder = S.ui and S.ui.cards[e.key]
		fail(e.why, holder and holder:FindFirstChild("Card"))
		task.delay(0.35, render)
		return
	end
	local r = type(e.reward) == "table" and e.reward or {}
	local ups = type(r.levelUps) == "table" and r.levelUps or {}
	local q = Quests.ById[tostring(r.id)]
	keeper("hop")
	if not QuestHallUI.isOpen() then
		toast("📜 " .. (q and q.text or "Quest") .. ": +" .. fmt(r.gems) .. " Gems, +" .. fmt(r.shards) .. " Shards")
		return
	end
	local book = S.book or {}
	local gems = (tonumber(r.gems) or 0) + (tonumber(r.levelGems) or 0)
	local shards, coins = tonumber(r.shards) or 0, tonumber(r.coins) or 0
	local to = { Gems = tonumber(book.gems) or player:GetAttribute("Gems") or 0, Shards = tonumber(book.shards) or player:GetAttribute("Shards") or 0, Coins = tonumber(book.coins) or player:GetAttribute("Coins") or 0 }
	local fromWallet = { Gems = math.max(0, to.Gems - gems), Shards = math.max(0, to.Shards - shards), Coins = math.max(0, to.Coins - coins) }
	if #ups > 0 then
		fromWallet.Level = math.max(1, (tonumber(ups[1].level) or 2) - 1)
	end
	S.just = { claimed = e.key }
	S.walletFrom = fromWallet
	S.renownFrom = tonumber(r.renownBefore)
	S.hold = 0
	render()
	S.hold = os.clock() + 2.6
	Juice.sound("pop", 1.2, 0.4)
	local ui = S.ui
	local land = {
		Gems = function()
			countUp(ui.gemValue, fromWallet.Gems, to.Gems, 0.6)
		end,
		Shards = function()
			countUp(ui.shardValue, fromWallet.Shards, to.Shards, 0.6)
		end,
		Coins = function()
			countUp(ui.coinValue, fromWallet.Coins, to.Coins, 0.6)
		end,
		XP = function()
			if #ups > 0 then
				UIKit.setLevel(ui.level, ups[#ups].level)
				Juice.pop(ui.level, 1.6, 0.7)
				levelBanner(ups)
			end
		end,
		Renown = function()
			fillRenown(tonumber(r.renownBefore) or 0, tonumber(r.renownAfter) or (tonumber(book.renown) or 0), r.chestsReady)
		end,
	}
	local fallback = (cf and cf.center) or centerOf(ui.panel)
	local from = (cf and cf.key == e.key and cf.from) or {}
	-- (they leave as the seal lands)
	task.delay(0.28, function()
		if QuestHallUI.isOpen() then
			flyRewards(from, { Gems = r.gems, Shards = shards, Coins = coins, XP = r.xp, Renown = r.renown }, fallback, land)
		end
	end)
end

swap = function(e, b)
	if S.busy then
		return
	end
	if S.armed ~= e.key then
		-- swaps are few: the first tap asks
		S.armed = e.key
		b.Text = "Sure?"
		b.BackgroundColor3 = rgb(150, 96, 40)
		b.TextColor3 = TEXT
		local key = e.key
		task.delay(3, function()
			if S.armed == key then
				S.armed = nil
				local holder = S.ui and S.ui.cards[key]
				local now = (holder and holder:FindFirstChild("Swap", true)) or (b.Parent and b) or nil
				if now then
					now.Text = "Swap"
					now.BackgroundColor3 = SWAP_COLOR
					now.TextColor3 = DIM
				end
			end
		end)
		return
	end
	S.armed = nil
	busyFor(6)
	S.busy.key = e.key
	b.Text = "..."
	fire("Swap", { key = e.key })
end

local function onSwapped(e)
	S.busy = nil
	if not e.ok then
		local holder = S.ui and S.ui.cards[e.key]
		fail(e.why, holder and holder:FindFirstChild("Card"))
		task.delay(0.35, render)
		return
	end
	keeper("nod")
	local holder = S.ui and S.ui.cards[e.key]
	local card = holder and holder:FindFirstChild("Card")
	local function after()
		S.just = { swapped = e.key }
		render()
		Juice.sound("whoosh", 1.25, 0.35)
	end
	if card then
		-- the old quest folds away...
		card.ClipsDescendants = true
		Juice.tween(card, 0.14, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.15, after)
	else
		after()
	end
end

-- The prizes in an opened chest, in the order they come out.
local function prizeList(r)
	local out = {}
	if (tonumber(r.gems) or 0) > 0 then
		table.insert(out, { kind = "Gems", amount = r.gems })
	end
	if (tonumber(r.coins) or 0) > 0 then
		table.insert(out, { kind = "Coins", amount = r.coins })
	end
	if (tonumber(r.shards) or 0) > 0 then
		table.insert(out, { kind = "Shards", amount = r.shards })
	end
	if r.card then
		table.insert(out, { kind = "Card", card = r.card, rarity = r.rarity, isNew = r.isNew })
	end
	if r.potion then
		table.insert(out, { kind = "Potion", name = r.potion, charges = r.charges })
	end
	return out
end

local function prizeTile(parent, p, order, color)
	local isCard = p.kind == "Card"
	local tile = make("Frame", { Name = "Prize_" .. p.kind, Size = UDim2.fromOffset(isCard and 132 or 116, isCard and 180 or 136), BackgroundColor3 = TILE, LayoutOrder = order }, parent)
	corner(tile, 14)
	stroke(tile, color, 2, 0.15)
	gradient(tile, WHITE, rgb(196, 190, 212))
	if p.kind == "Gems" or p.kind == "Coins" or p.kind == "Shards" then
		UIKit.icon(tile, p.kind, 50, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 16) })
		text(tile, "+" .. fmt(p.amount), { Font = TITLE_FONT, TextSize = 26, TextColor3 = UIKit.currencyColor(p.kind), Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 30), TextWrapped = false })
		text(tile, p.kind, { TextColor3 = DIM, TextSize = 13, Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 18) })
	elseif isCard then
		local def = CardData.Cards[p.card]
		local holder = make("Frame", { Name = "Face", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(88, 122), BackgroundTransparency = 1 }, tile)
		if def and S.ctx and S.ctx.makeCard then
			pcall(S.ctx.makeCard, holder, p.card, UDim2.fromScale(1, 1), nil, "compact")
		end
		text(tile, def and def.name or "A new card", { Font = BOLD_FONT, TextSize = 13, Position = UDim2.fromOffset(4, 136), Size = UDim2.new(1, -8, 0, 18), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		text(tile, tostring(p.rarity or (def and def.rarity) or ""), { Font = TITLE_FONT, TextSize = 14, TextColor3 = rarityColor(p.rarity or (def and def.rarity)), Position = UDim2.fromOffset(4, 155), Size = UDim2.new(1, -8, 0, 18) })
		if p.isNew then
			local new = text(tile, "NEW!", { Name = "New", Font = TITLE_FONT, TextSize = 13, TextColor3 = INK, BackgroundTransparency = 0, BackgroundColor3 = GOLD, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(46, 20), Rotation = 8, ZIndex = 3 })
			corner(new, 10)
			stroke(new, INK, 1.5)
		end
	else
		text(tile, "🍀", { TextSize = 46, Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromOffset(0, 8), Font = TITLE_FONT })
		text(tile, "+" .. tostring(p.charges or 0) .. " lucky pulls", { Font = TITLE_FONT, TextSize = 17, TextColor3 = rgb(140, 230, 150), Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, 24) })
		text(tile, tostring(p.name or "Luck Potion"), { TextColor3 = DIM, TextSize = 12, Position = UDim2.fromOffset(6, 98), Size = UDim2.new(1, -12, 0, 30) })
	end
	return tile
end

-- Puts the chest scene away (instant: at once, nothing flies).
local function closeReveal(instant)
	local rv = S.reveal
	if not rv then
		return
	end
	S.reveal = nil
	local f = rv.frame
	if instant or not QuestHallUI.isOpen() then
		S.hold = 0
		if f.Parent then
			f:Destroy()
		end
		walletShow()
		return
	end
	-- the coins, gems and shards fly out of their tiles into the wallet
	local r, ui, book = rv.reward, S.ui, S.book or {}
	local from, to, start = {}, {}, {}
	for kind, tile in pairs(rv.tiles) do
		if tile.Parent then
			from[kind] = centerOf(tile)
		end
	end
	for _, kind in ipairs({ "Gems", "Shards", "Coins" }) do
		to[kind] = tonumber(book[string.lower(kind)]) or player:GetAttribute(kind) or 0
		start[kind] = math.max(0, to[kind] - (tonumber(r[string.lower(kind)]) or 0))
	end
	local land = {
		Gems = function()
			countUp(ui.gemValue, start.Gems, to.Gems, 0.6)
		end,
		Shards = function()
			countUp(ui.shardValue, start.Shards, to.Shards, 0.6)
		end,
		Coins = function()
			countUp(ui.coinValue, start.Coins, to.Coins, 0.6)
		end,
	}
	flyRewards(from, { Gems = r.gems, Shards = r.shards, Coins = r.coins }, centerOf(ui.panel), land)
	Juice.tween(f, 0.22, { BackgroundTransparency = 1 })
	for _, d in ipairs(f:GetChildren()) do
		if d:IsA("GuiObject") then
			Juice.popOut(d, 0.2)
		end
	end
	task.delay(0.25, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

-- The chest scene: it drops in, shakes three times (harder each time), bursts open in its own
-- colour, and its prizes rise out one by one. "Collect" sends them to your wallet.
local function reveal(r)
	closeReveal(true)
	local ui = S.ui
	local def = Quests.Chests[tonumber(r.index) or 0]
	if not ui or not def then
		return
	end
	local color = c3(def.color)
	local ov = make("TextButton", { Name = "ChestScene", Text = "", AutoButtonColor = false, Selectable = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(8, 6, 14), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 40 }, ui.panel)
	corner(ov, 16)
	local rv = { frame = ov, reward = r, tiles = {} }
	S.reveal = rv
	S.hold = os.clock() + 120 -- (the wallet waits until you collect)
	local function alive()
		return S.reveal == rv and ov.Parent ~= nil
	end
	Juice.tween(ov, 0.25, { BackgroundTransparency = 0.1 })
	local title = text(ov, def.name, { Name = "Title", Font = TITLE_FONT, TextSize = 38, TextColor3 = lighten(color, 0.15), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.fromOffset(560, 46), TextTransparency = 1, TextWrapped = false, ZIndex = 3 })
	make("UIStroke", { Thickness = 2.5, Color = INK, Transparency = 0.2 }, title)
	local sub = text(ov, "This week's Quest Chest", { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(560, 20), TextColor3 = DIM, TextTransparency = 1, ZIndex = 3 })
	Juice.tween(title, 0.3, { TextTransparency = 0 })
	Juice.tween(sub, 0.3, { TextTransparency = 0 })
	local stage = make("Frame", { Name = "Stage", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 236), Size = UDim2.fromOffset(220, 190), BackgroundTransparency = 1 }, ov)
	local art, lid, lock = chestArt(stage, color, 190)
	art.Position = UDim2.new(0.5, 0, 1, -280)
	Juice.tween(art, 0.5, { Position = UDim2.fromScale(0.5, 1) }, Enum.EasingStyle.Bounce)
	Juice.sound("whoosh", 0.85, 0.3)
	task.delay(0.42, function()
		if alive() then
			Juice.sound("thud", 0.9, 0.5)
		end
	end)
	for k, t in ipairs({ 0.8, 1.1, 1.38 }) do
		task.delay(t, function()
			if alive() then
				Juice.shake(stage, 3 + k * 4, 0.2)
				Juice.sound("tick", 0.85 + k * 0.17, 0.45)
			end
		end)
	end
	task.delay(1.7, function()
		if not alive() then
			return
		end
		-- it bursts open
		local rays = Juice.sunburst(ov, color, { length = 520, width = 80, count = 12, transparency = 0.8, speed = 12, zIndex = 1, position = UDim2.new(0.5, 0, 0, 226) })
		Juice.popIn(rays, 0, { twist = 0, time = 0.45, sound = false })
		stage.ZIndex = 2
		Juice.tween(lid, 0.4, { Position = UDim2.fromScale(0.26, -0.2), Rotation = -36 }, Enum.EasingStyle.Back)
		lock.Visible = false
		local glow = make("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.84, 0.13), BackgroundColor3 = lighten(color, 0.6), BorderSizePixel = 0, ZIndex = 2 }, art)
		corner(glow, 8)
		Juice.flash(ov, lighten(color, 0.5), 0.5, 0.2)
		local sx, sy = onScreen(centerOf(stage))
		Juice.confetti(S.ctx.gui, sx, sy, 60, { colors = { color, lighten(color, 0.45), GOLD, WHITE } })
		Juice.sound(tonumber(r.index) == #Quests.Chests and "choir" or "chime", 1, 0.55)
		keeper("hop")
		-- the prizes rise out one by one
		local row = make("Frame", { Name = "Prizes", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 352), Size = UDim2.fromOffset(0, 184), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 3 }, ov)
		hlist(row, 14, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)
		local prizes = prizeList(r)
		for i, p in ipairs(prizes) do
			local tile = prizeTile(row, p, i, color)
			if p.kind == "Gems" or p.kind == "Coins" or p.kind == "Shards" then
				rv.tiles[p.kind] = tile
			end
			Juice.popIn(tile, 0.3 + i * 0.24, { pitch = 1 + i * 0.1 })
		end
		task.delay(0.55 + #prizes * 0.24, function()
			if not alive() then
				return
			end
			local b = button(ov, "Collect", GOLD, function()
				closeReveal(false)
			end, { Name = "Collect", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(200, 50), TextSize = 25, TextColor3 = INK, ZIndex = 4 })
			Juice.popIn(b, 0)
			Juice.shine(b, 2.4, UDim.new(0, 10))
		end)
	end)
end

openChest = function(i)
	local book = S.book
	local c = book and book.chests and book.chests[i]
	local def = Quests.Chests[i]
	local slot = S.ui and S.ui.chests[i]
	if not c or not def then
		return
	end
	if c.opened then
		toast("📜 You've opened the " .. def.name .. " this week. New chests on Monday.")
		return
	end
	if not c.ready then
		toast("📜 Earn " .. math.max(0, def.at - (tonumber(book.renown) or 0)) .. " more Renown to open the " .. def.name .. ".")
		if slot then
			Juice.pop(slot.button, 0.85, 0.35)
		end
		Juice.sound("thud", 0.75, 0.25)
		return
	end
	if S.busy or S.reveal then
		return
	end
	busyFor(6)
	fire("Chest", { index = i })
end

local function onChest(e)
	S.busy = nil
	if not e.ok then
		fail(e.why)
		render()
		return
	end
	if not QuestHallUI.isOpen() then
		return
	end
	local r = type(e.reward) == "table" and e.reward or { index = e.index }
	r.index = r.index or e.index
	-- (the wallet keeps the old numbers until the prizes are collected)
	local book = S.book or {}
	S.walletFrom = {
		Gems = math.max(0, (tonumber(book.gems) or 0) - (tonumber(r.gems) or 0)),
		Shards = math.max(0, (tonumber(book.shards) or 0) - (tonumber(r.shards) or 0)),
		Coins = math.max(0, (tonumber(book.coins) or 0) - (tonumber(r.coins) or 0)),
	}
	S.hold = 0
	render()
	reveal(r)
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function QuestHallUI.close()
	closeReveal(true)
	local root, ui = S.root, S.ui
	if not root then
		return
	end
	S.root, S.ui = nil, nil
	S.armed = nil
	S.just = nil
	if ui and ui.panel and ui.panel.Parent then
		UIKit.close(ui.panel, function()
			root:Destroy()
		end)
	else
		root:Destroy()
	end
end

function QuestHallUI.escape()
	if S.reveal then
		closeReveal(false)
		return true
	end
	return false
end

local tickClocks -- (below)

function QuestHallUI.open(tab)
	if not S.ctx or not S.ctx.gui then
		return
	end
	if QuestHallUI.isOpen() then
		if tab then
			selectTab(tab)
		end
		return
	end
	S.tab = tab or bestTab(S.book)
	S.tip = (S.tip % #TIPS) + 1
	S.armed = nil
	local root = make("Frame", { Name = "QuestHallWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(W, H), BackgroundTransparency = 1 }, S.ctx.gui)
	fit(root, W + 40, H + 40)
	local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, Active = true }, root)
	corner(panel, 16)
	gradient(panel, rgb(40, 33, 60), PANEL)
	stroke(panel, GOLD, 2)
	S.root = root
	S.ui = { panel = panel, cards = {} }
	buildHeader(panel)
	buildTabs(panel)
	buildList(panel)
	buildFooter(panel)
	S.ui.fx = make("Frame", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 60 }, panel)
	UIKit.animateIn(panel)
	if UIKit.Focus and UIKit.Focus.watch then
		pcall(UIKit.Focus.watch, panel, { dim = 0.3, blur = 8 })
	end
	S.hold = 0
	render()
	QuestHallUI.request()
	Juice.sound("whoosh", 1.15, 0.28)
	MenuBriefs.maybe("QuestHall", { place = "center", still = function()
		return S.ui ~= nil and S.ui.panel == panel and panel.Parent ~= nil
	end })
	-- the window closes when you walk away from the counter
	local acc = 0
	Juice.onFrame(panel, function(_, dt)
		acc += dt or 0
		if acc < 0.5 then
			return
		end
		acc = 0
		if S.ui and S.ui.panel == panel then
			local desk = S.ctx.desk and S.ctx.desk()
			local body = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if desk and body and not S.reveal and (body.Position - desk.Position).Magnitude > Quests.ClaimDistance + 4 then
				QuestHallUI.close()
			end
		end
	end)
end

---------------------------------------------------------------------------
-- The boards in the hall (and the notice board out front): your own quests, in ink
---------------------------------------------------------------------------

local function boardGui(part, pps)
	local old = part:FindFirstChild("QuestBoardGui")
	if old then
		old:Destroy()
	end
	local sg = make("SurfaceGui", { Name = "QuestBoardGui", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = pps or 40, LightInfluence = 0.3, Brightness = 1.3, ClipsDescendants = true }, part)
	local f = make("Frame", { Name = "Page", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, sg)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }, f)
	return f
end

local function boardTitle(f, str, color, size)
	text(f, str, { Name = "Heading", Font = TITLE_FONT, TextSize = size, TextColor3 = color, Size = UDim2.new(1, 0, 0, size + 6), TextWrapped = false, LayoutOrder = 1 })
	make("Frame", { Name = "Rule", Size = UDim2.new(0.84, 0, 0, 2), BackgroundColor3 = color, BackgroundTransparency = 0.4, BorderSizePixel = 0, LayoutOrder = 2 }, f)
end

-- A short version of a quest for the small Journey board.
local function shortText(q)
	if q.type ~= "journey" then
		return q.text
	end
	local w = worldOf(q.world)
	if q.step == "act3" then
		return "Clear acts 1-3"
	elseif q.step == "boss" then
		return "Beat " .. (w and w.boss and w.boss.name or "the boss")
	elseif q.step == "stars" then
		return "Earn " .. tostring(q.target) .. " ★"
	end
	return "Boss on Hard"
end

local function boardRow(f, e, size, order)
	local q = Quests.ById[e.id]
	if not q then
		return
	end
	local row = make("Frame", { Name = "Row", Size = UDim2.new(1, 0, 0, size + 9), BackgroundTransparency = 1, LayoutOrder = order }, f)
	local mark, markColor = "•", INK_BROWN
	local ready = readyEntry(e)
	if e.claimed then
		mark, markColor = "✓", rgb(36, 118, 66)
	elseif e.open == false then
		mark, markColor = "×", rgb(140, 120, 100)
	elseif ready then
		mark, markColor = "★", rgb(200, 112, 16)
	end
	text(row, mark, { Size = UDim2.new(0, size + 4, 1, 0), Font = TITLE_FONT, TextSize = size + 2, TextColor3 = markColor, TextWrapped = false })
	local countW = math.floor(size * 3.4)
	local label = text(row, escape(shortText(q)), {
		RichText = true,
		Position = UDim2.fromOffset(size + 6, 0),
		Size = UDim2.new(1, -(size + 6 + countW), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = size,
		Font = BODY_FONT,
		TextColor3 = INK_BROWN,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	if e.claimed then
		label.Text = "<s>" .. escape(shortText(q)) .. "</s>"
		label.TextTransparency = 0.45
	end
	local right = e.claimed and "done" or (ready and "claim!" or (e.open == false and "" or (fmt(math.min(e.progress, e.target)) .. "/" .. fmt(e.target))))
	text(row, right, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, countW, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = TITLE_FONT,
		TextSize = size,
		TextWrapped = false,
		TextColor3 = ready and rgb(200, 112, 16) or (e.claimed and rgb(36, 118, 66) or INK_BROWN),
		TextTransparency = e.claimed and 0.3 or 0,
	})
end

local function boardFoot(f, size, order)
	return text(f, "", { Name = "Foot", Font = BODY_FONT, TextSize = size, TextColor3 = INK_BROWN, TextTransparency = 0.25, Size = UDim2.new(1, 0, 0, size + 6), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = order })
end

-- The Journey board shows the first world you've opened that still has quests for you.
local function journeyWorld(book)
	local best = nil
	for _, w in ipairs(Campaign.Worlds) do
		local entries = {}
		for _, e in ipairs(book.journey or {}) do
			local q = Quests.ById[e.id]
			if q and q.world == w.key then
				table.insert(entries, e)
			end
		end
		if #entries > 0 and entries[1].open ~= false then
			best = { world = w, entries = entries }
			if claimedOf(entries) < #entries then
				return best
			end
		end
	end
	return best
end

function QuestHallUI.drawBoards(hall)
	if not hall then
		return
	end
	local book = S.book
	S.boards = {}
	local daily = hall:FindFirstChild("DailyBoard")
	if daily then
		local f = boardGui(daily, 40)
		boardTitle(f, "Daily Quests", BOARD_COLOR.daily, 30)
		if book then
			for i, e in ipairs(book.daily or {}) do
				boardRow(f, e, 16, 2 + i)
			end
			S.boards.daily = boardFoot(f, 13, 10)
		else
			text(f, "Ask Quill at the counter.", { TextColor3 = INK_BROWN, TextSize = 16, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3 })
		end
	end
	local weekly = hall:FindFirstChild("WeeklyBoard")
	if weekly then
		local f = boardGui(weekly, 40)
		boardTitle(f, "Weekly Quests", BOARD_COLOR.weekly, 26)
		if book then
			for i, e in ipairs(book.weekly or {}) do
				boardRow(f, e, 13, 2 + i)
			end
			S.boards.weekly = boardFoot(f, 12, 10)
		else
			text(f, "Ask Quill at the counter.", { TextColor3 = INK_BROWN, TextSize = 16, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3 })
		end
	end
	local journey = hall:FindFirstChild("JourneyBoard")
	if journey then
		local f = boardGui(journey, 40)
		boardTitle(f, "Journey", BOARD_COLOR.journey, 22)
		local pick = book and journeyWorld(book)
		if pick then
			text(f, pick.world.emoji .. " " .. pick.world.name, { Font = TITLE_FONT, TextSize = 13, TextColor3 = BOARD_COLOR.journey, Size = UDim2.new(1, 0, 0, 18), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 3 })
			for i, e in ipairs(pick.entries) do
				boardRow(f, e, 11, 3 + i)
			end
			local foot = boardFoot(f, 11, 10)
			foot.Text = claimedOf(book.journey) .. " / " .. #(book.journey or {}) .. " claimed"
		else
			text(f, "Play the Campaign: every world has quests.", { TextColor3 = INK_BROWN, TextSize = 12, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 3 })
		end
	end
	local notice = hall:FindFirstChild("NoticeBoard")
	if notice then
		local f = boardGui(notice, 40)
		text(f, "QUEST HALL", { Font = TITLE_FONT, TextSize = 17, TextColor3 = rgb(38, 58, 100), Size = UDim2.new(1, 0, 0, 22), TextWrapped = false, LayoutOrder = 1 })
		local ready = player:GetAttribute("QuestsReady") or 0
		text(f, ready > 0 and (ready .. plural(ready, " reward to claim!", " rewards to claim!")) or "Quill keeps your quests", {
			Font = TITLE_FONT,
			TextSize = ready > 0 and 18 or 14,
			TextColor3 = ready > 0 and rgb(170, 36, 46) or INK_BROWN,
			Size = UDim2.new(1, 0, 0, 26),
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 2,
		})
		S.boards.notice = text(f, "", { Font = BODY_FONT, TextSize = 12, TextColor3 = INK_BROWN, TextTransparency = 0.2, Size = UDim2.new(1, 0, 0, 16), TextWrapped = false, LayoutOrder = 3 })
		text(f, "Finish them anywhere. Claim them inside.", { Font = BODY_FONT, TextSize = 10, TextColor3 = INK_BROWN, TextTransparency = 0.35, Size = UDim2.new(1, 0, 0, 14), TextWrapped = false, LayoutOrder = 4 })
	end
	tickClocks()
end

---------------------------------------------------------------------------
-- The Trophy Wall's card in your room
---------------------------------------------------------------------------

local function miniRow(parent, e, order)
	local q = Quests.ById[e.id]
	if not q then
		return
	end
	local ready = readyEntry(e)
	local row = make("Frame", { Name = "Quest" .. order, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local tier = Quests.Tiers[q.tier]
	text(row, (e.claimed and "✓  " or "") .. q.text, { Font = BOLD_FONT, TextSize = 14, Size = UDim2.new(1, -96, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = e.claimed and DIM or TEXT })
	text(row, e.claimed and "Claimed" or (ready and "Ready!" or (fmt(math.min(e.progress, e.target)) .. " / " .. fmt(e.target))), {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(90, 18),
		Font = TITLE_FONT,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = ready and GOLD or (e.claimed and FAINT or DIM),
	})
	local back = make("Frame", { Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = rgb(24, 20, 36), BorderSizePixel = 0 }, row)
	corner(back, 3)
	local fill = make("Frame", { Size = UDim2.fromScale(math.clamp((tonumber(e.progress) or 0) / math.max(1, tonumber(e.target) or 1), 0, 1), 1), BackgroundColor3 = tier and c3(tier.color) or KIND.daily, BorderSizePixel = 0 }, back)
	corner(fill, 3)
	if e.claimed then
		fill.BackgroundTransparency = 0.5
	end
end

function QuestHallUI.summary(parent, order, opts)
	opts = opts or {}
	local box = make("Frame", { Name = "QuestHallCard", Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = rgb(44, 38, 64), LayoutOrder = order or 0 }, parent)
	corner(box, 10)
	stroke(box, INK, 2, 0.2)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, box)
	local head = make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = 1 }, box)
	local m = make("Frame", { Name = "Quill", Size = UDim2.fromOffset(46, 46), BackgroundColor3 = WHITE }, head)
	corner(m)
	gradient(m, rgb(134, 88, 194), rgb(52, 38, 100))
	stroke(m, GOLD, 2)
	text(m, "🦉", { Size = UDim2.fromScale(1, 1), TextSize = 26, Font = TITLE_FONT })
	local title = text(head, "", { Name = "Title", Font = TITLE_FONT, TextSize = 17, TextColor3 = GOLD, Position = UDim2.fromOffset(56, 2), Size = UDim2.new(1, -56, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	text(head, "Out in the Park, on the north lawn. Quill keeps them.", { TextSize = 13, TextColor3 = DIM, Position = UDim2.fromOffset(56, 26), Size = UDim2.new(1, -56, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local rows = make("Frame", { Name = "Today", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, box)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, rows)
	local week = text(box, "", { Name = "Week", TextSize = 12, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 })
	local go = button(box, "🌳  Walk to the Quest Hall", GOOD, function()
		if opts.walk then
			opts.walk()
		end
	end, { Name = "WalkToQuestHall", Size = UDim2.new(1, 0, 0, 42), TextSize = 18, LayoutOrder = 4 })
	local function draw(book)
		if not box.Parent then
			return
		end
		local ready = player:GetAttribute("QuestsReady") or 0
		title.Text = ready > 0 and ("📜 " .. ready .. plural(ready, " reward waits", " rewards wait") .. " at the Quest Hall") or "📜 Your quests live at the Quest Hall"
		title.TextColor3 = ready > 0 and GOLD or TEXT
		go.Text = ready > 0 and "🌳  Walk out and claim them" or "🌳  Walk to the Quest Hall"
		for _, c in ipairs(rows:GetChildren()) do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not book then
			text(rows, "Asking Quill...", { TextColor3 = DIM, TextSize = 13, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1 })
			week.Text = ""
			return
		end
		for i, e in ipairs(book.daily or {}) do
			miniRow(rows, e, i)
		end
		week.Text = "This week: " .. claimedOf(book.weekly) .. " / " .. #(book.weekly or {}) .. " weekly quests claimed  ·  Renown " .. fmt(math.min(tonumber(book.renown) or 0, Quests.RenownMax)) .. " / " .. Quests.RenownMax .. "\nNew daily quests in " .. Quests.timeText(dailyLeft())
	end
	S.summary = box
	S.summaryDraw = draw
	local off = QuestHallUI.onBook(draw)
	local readyConn = player:GetAttributeChangedSignal("QuestsReady"):Connect(function()
		draw(S.book)
	end)
	box.AncestryChanged:Connect(function()
		if not box.Parent then
			off()
			readyConn:Disconnect()
			if S.summary == box then
				S.summary = nil
				S.summaryDraw = nil
			end
		end
	end)
	draw(S.book)
	QuestHallUI.request()
	return box
end

---------------------------------------------------------------------------
-- Answers from the server, the clocks, and init
---------------------------------------------------------------------------

local function onEvent(e)
	if type(e) ~= "table" then
		return
	end
	if type(e.book) == "table" then
		S.book = e.book
		S.bookAt = os.clock()
	end
	if e.kind == "state" then
		if e.note then
			toast("📜 " .. tostring(e.note))
		end
		render()
	elseif e.kind == "claimed" then
		onClaimed(e)
	elseif e.kind == "swapped" then
		onSwapped(e)
	elseif e.kind == "chest" then
		onChest(e)
	end
	notify()
end

tickClocks = function()
	if QuestHallUI.isOpen() and S.ui.clock then
		S.ui.clock.Text = clockLine()
		S.ui.renownHint.Text = renownLine()
	end
	local b = S.boards
	if b and S.book then
		if b.daily and b.daily.Parent then
			b.daily.Text = "New quests in " .. Quests.timeText(dailyLeft())
		end
		if b.weekly and b.weekly.Parent then
			b.weekly.Text = "Renown " .. fmt(math.min(tonumber(S.book.renown) or 0, Quests.RenownMax)) .. " / " .. Quests.RenownMax .. "  ·  new week in " .. Quests.timeText(weeklyLeft())
		end
		if b.notice and b.notice.Parent then
			b.notice.Text = "New daily quests in " .. Quests.timeText(dailyLeft())
		end
	end
	-- a new day (or week) has begun while you were looking: ask for the new quests
	if S.book and (dailyLeft() <= 0 or weeklyLeft() <= 0) and os.clock() - S.lastStale > 15 and wanted() then
		S.lastStale = os.clock()
		QuestHallUI.request()
	end
end

-- Your quests changed on the server (a match, a pack, an enchant): fetch them if they're on show.
local function onRev()
	local rev = player:GetAttribute("QuestRev")
	if (S.book and S.book.rev == rev) or S.revPending or not wanted() then
		return
	end
	S.revPending = true
	task.delay(0.6, function()
		S.revPending = false
		if not (S.book and S.book.rev == player:GetAttribute("QuestRev")) and wanted() then
			QuestHallUI.request()
		end
	end)
end

local function listen()
	if S.listening then
		return
	end
	S.listening = true
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("QuestRemotes", 60)
		if not folder then
			warn("QuestHallUI: ReplicatedStorage.QuestRemotes is missing")
			return
		end
		local action = folder:WaitForChild("QuestAction", 10)
		local event = folder:WaitForChild("QuestEvent", 10)
		if event then
			event.OnClientEvent:Connect(onEvent)
		end
		S.action = action
		if action and S.wantState then
			S.wantState = false
			S.lastAsk = -10
			QuestHallUI.request()
		end
	end)
	player:GetAttributeChangedSignal("QuestRev"):Connect(onRev)
	-- the wallet in the window follows your numbers (unless rewards are flying into it)
	for _, name in ipairs({ "Gems", "Shards", "Coins", "Level" }) do
		player:GetAttributeChangedSignal(name):Connect(function()
			if QuestHallUI.isOpen() and os.clock() >= S.hold then
				walletShow()
			end
		end)
	end
	local acc, ticks = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			ticks += 1
			tickClocks()
			-- (the Trophy Wall's card: its countdown, every half minute)
			if ticks % 30 == 0 and S.summary and S.summary.Parent and S.summaryDraw then
				S.summaryDraw(S.book)
			end
		end
	end)
end

function QuestHallUI.init(ctx)
	S.ctx = ctx
	listen()
end

-- The room's Trophy Wall uses the card without the Park's init: listening starts on first use.
local summary = QuestHallUI.summary
QuestHallUI.summary = function(parent, order, opts)
	listen()
	return summary(parent, order, opts)
end

return QuestHallUI

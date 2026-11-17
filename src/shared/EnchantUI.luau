-- EnchantUI: the Enchanting Crystal's window in the Park. Client only. ParkClient opens it from
-- the crystal's "Enchant" prompt. The rules are in Enchants, the save and the dice on the server
-- (EconomyManager.enchantCard / chooseEnchant through MenuServer's "Enchant" and
-- "EnchantChoose", answered by "CardResult" and a fresh "Decks" snapshot).
--
--   EnchantUI.init(ctx)   once (ctx: gui, makeCard, toast)
--   EnchantUI.open()      the crystal's prompt
--   EnchantUI.close()     Escape, leaving the park
--   EnchantUI.isOpen()
--
-- The window: your cards on the left (enchanted ones glow in their enchant's colour), the card you
-- picked big on the right with its enchant, Enchant (Coins) and Lucky (Gems) buttons, the odds and
-- how close the next sure Epic is. The roll: the card's rim flickers through the colours, slows
-- down and lands on the enchant's rarity with a painted burst (bigger for rarer). Rolling a card
-- that already has an enchant asks: keep the new one or the old one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local Enchants = require(here:WaitForChild("Enchants"))
local EnchantFx = require(here:WaitForChild("EnchantFx"))
local DeckRules = require(here:WaitForChild("DeckRules"))
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
local BAD = rgb(235, 110, 110)
local CRYSTAL = rgb(150, 210, 255)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local EnchantUI = {}

local S = {
	ctx = nil,
	win = nil,
	snap = nil, -- the latest "Decks" snapshot (cards, enchants, enchantPity, enchantPending)
	pick = nil, -- the card picked
	rolling = false, -- the roll animation is playing
	busy = false, -- a request is on its way
	result = nil, -- the last roll, for the choice panel
	note = nil,
}
EnchantUI.S = S -- (for the tests)

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

local function menuAction()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	return remotes and remotes:FindFirstChild("MenuAction")
end

local function fire(what, options)
	local r = menuAction()
	if r then
		r:FireServer(what, options or {})
	end
end

local function fit(frame, width, height)
	local cam = workspace.CurrentCamera
	local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local scale = math.min(1, (view.X - 24) / width, (view.Y - 24) / height)
	if scale < 1 then
		make("UIScale", { Name = "Fit", Scale = math.max(0.4, scale) }, frame)
	end
end

local function face(parent, id, enchant)
	if not (S.ctx and S.ctx.makeCard) then
		return nil
	end
	local card = S.ctx.makeCard(parent, id, UDim2.fromScale(1, 1), nil, "compact")
	if card then
		for _, d in ipairs(card:GetDescendants()) do
			if d:IsA("GuiObject") then
				d.Active = false
			end
		end
		if enchant then
			EnchantFx.decorateCard(card, enchant)
		end
	end
	return card
end

local function enchantsMap()
	return (S.snap and S.snap.enchants) or {}
end

local function pending()
	return S.snap and type(S.snap.enchantPending) == "table" and S.snap.enchantPending or nil
end

local function rarityColor(r)
	return EnchantFx.color(r)
end

-- The cards you could enchant, best first: enchanted ones, then by rarity, then by name.
local function myCards()
	local list = {}
	local owned = (S.snap and S.snap.cards) or {}
	local rank = {}
	for i, r in ipairs(CardData.Rarities) do
		rank[r] = i
	end
	for id, n in pairs(owned) do
		if (n or 0) > 0 and Enchants.canEnchant(id) and DeckRules.collectible(id) then
			table.insert(list, id)
		end
	end
	local en = enchantsMap()
	table.sort(list, function(a, b)
		local ea, eb = Enchants.Rank[Enchants.rarityOf(en[a]) or ""] or 0, Enchants.Rank[Enchants.rarityOf(en[b]) or ""] or 0
		if ea ~= eb then
			return ea > eb
		end
		local da, db = CardData.Cards[a], CardData.Cards[b]
		if rank[da.rarity] ~= rank[db.rarity] then
			return rank[da.rarity] > rank[db.rarity]
		end
		return da.name < db.name
	end)
	return list
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local render -- set below

local function enchantLine(parent, eid, props)
	local e = Enchants.get(eid)
	local box = make("Frame", { Name = "EnchantInfo", Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = TILE }, parent)
	for k, v in pairs(props or {}) do
		box[k] = v
	end
	corner(box, 10)
	if e then
		local col = rarityColor(e.rarity)
		stroke(box, col, 2)
		text(box, "◆ " .. e.name, { Name = "Name", Font = TITLE_FONT, TextSize = 19, TextColor3 = col, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left })
		text(box, e.rarity .. " enchant · " .. e.text, { Name = "Text", TextSize = 13, Position = UDim2.fromOffset(12, 29), Size = UDim2.new(1, -24, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	else
		text(box, "Not enchanted yet", { Name = "Name", Font = TITLE_FONT, TextSize = 18, TextColor3 = DIM, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left })
		text(box, "Touch the crystal: a rune of a random rarity goes on every copy of this card.", { TextSize = 13, TextColor3 = DIM, Position = UDim2.fromOffset(12, 31), Size = UDim2.new(1, -24, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	end
	return box
end

local function oddsText(lucky)
	local odds = lucky and Enchants.LuckyOdds or Enchants.Odds
	local parts = {}
	for _, r in ipairs(Enchants.Rarities) do
		if odds[r] > 0 then
			table.insert(parts, r .. " " .. odds[r] .. "%")
		end
	end
	return table.concat(parts, " · ")
end

local function drawGrid(list)
	local en = enchantsMap()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local ids = myCards()
	for i, id in ipairs(ids) do
		local cell = make("TextButton", { Name = "Cell_" .. id, Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromOffset(84, 118), LayoutOrder = i }, list)
		face(cell, id, en[id])
		if S.pick == id then
			local sel = make("Frame", { Name = "Picked", BackgroundTransparency = 1, Size = UDim2.new(1, 6, 1, 6), Position = UDim2.fromOffset(-3, -3), ZIndex = 40 }, cell)
			corner(sel, 12)
			stroke(sel, GOLD, 3)
		end
		cell.Activated:Connect(function()
			if S.rolling or pending() then
				return
			end
			S.pick = id
			S.note = nil
			Juice.sound("tick", 1.2, 0.35)
			render()
		end)
	end
	if #ids == 0 then
		text(list, "You have no creatures or spells to enchant yet. Open some packs!", { TextColor3 = DIM, Size = UDim2.new(1, -8, 0, 40) })
	end
end

local function drawSide(side)
	for _, c in ipairs(side:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local id = S.pick
	if not id then
		text(side, "Pick a card on the left.", { TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 20), TextXAlignment = Enum.TextXAlignment.Center })
		return
	end
	local d = CardData.Cards[id]
	local en = enchantsMap()
	local stage = make("Frame", { Name = "Stage", Size = UDim2.fromOffset(150, 210), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 }, side)
	local big = face(stage, id, en[id])
	if big then
		big.Name = "BigCard"
	end
	text(side, d.name, { Name = "CardName", Font = TITLE_FONT, TextSize = 20, TextColor3 = GOLD, Position = UDim2.fromOffset(0, 218), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	enchantLine(side, en[id], { Position = UDim2.fromOffset(0, 246) })
	local p = pending()
	if p then
		-- the choice: keep the new rune or the old one
		local new, old = Enchants.get(p.enchant), Enchants.get(en[p.card])
		text(side, "Which rune stays on " .. (CardData.Cards[p.card] and CardData.Cards[p.card].name or "the card") .. "?", { Name = "Ask", Font = TITLE_FONT, TextSize = 16, Position = UDim2.fromOffset(0, 316), Size = UDim2.new(1, 0, 0, 22) })
		local keepNew = button(side, "Keep new: " .. (new and new.name or "?"), new and rarityColor(new.rarity):Lerp(INK, 0.35) or TILE, function()
			if S.busy then
				return
			end
			S.busy = true
			fire("EnchantChoose", { keep = "new" })
		end, { Name = "KeepNew", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 342), TextSize = 16 })
		keepNew.TextTruncate = Enum.TextTruncate.AtEnd
		local keepOld = button(side, "Keep old: " .. (old and old.name or "?"), TILE, function()
			if S.busy then
				return
			end
			S.busy = true
			fire("EnchantChoose", { keep = "old" })
		end, { Name = "KeepOld", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 388), TextSize = 16 })
		keepOld.TextTruncate = Enum.TextTruncate.AtEnd
		if new then
			text(side, new.rarity .. " · " .. new.text, { TextSize = 12, TextColor3 = rarityColor(new.rarity), Position = UDim2.fromOffset(0, 432), Size = UDim2.new(1, 0, 0, 30) })
		end
		return
	end
	-- the buttons
	local coins = Enchants.Cost.Coins or 0
	local gems = Enchants.LuckyCost.Gems or 0
	local go = button(side, "", rgb(96, 70, 170), function()
		EnchantUI.roll(false)
	end, { Name = "EnchantButton", Size = UDim2.new(0.5, -4, 0, 44), Position = UDim2.fromOffset(0, 318) })
	UIKit.caption(go, "Coins", "Enchant  " .. coins)
	local lucky = button(side, "Lucky  " .. gems .. " 💎", rgb(50, 120, 170), function()
		EnchantUI.roll(true)
	end, { Name = "LuckyButton", Size = UDim2.new(0.5, -4, 0, 44), Position = UDim2.new(0.5, 4, 0, 318), TextSize = 16 })
	lucky.TextTruncate = Enum.TextTruncate.AtEnd
	local pity = (S.snap and S.snap.enchantPity) or 0
	local left = Enchants.untilPity(pity)
	text(side, left <= 1 and "★ Your next enchant is Epic or better!" or ("★ Epic or better within " .. left .. " enchants"), { Name = "Pity", TextSize = 13, TextColor3 = left <= 1 and GOLD or TEXT, Position = UDim2.fromOffset(0, 368), Size = UDim2.new(1, 0, 0, 18) })
	text(side, "Odds: " .. oddsText(false), { Name = "Odds", TextSize = 11, TextColor3 = DIM, Position = UDim2.fromOffset(0, 388), Size = UDim2.new(1, 0, 0, 28) })
	text(side, "Lucky: no Commons · " .. oddsText(true), { TextSize = 11, TextColor3 = DIM, Position = UDim2.fromOffset(0, 414), Size = UDim2.new(1, 0, 0, 28) })
	text(side, "Enchants count against bots and in the Campaign. In duels with players they glow but cards play their printed numbers.", { TextSize = 11, TextColor3 = DIM, Position = UDim2.fromOffset(0, 442), Size = UDim2.new(1, 0, 0, 28) })
	if S.note then
		text(side, S.note[1], { Name = "Note", TextSize = 13, TextColor3 = S.note[2], Position = UDim2.fromOffset(0, 472), Size = UDim2.new(1, 0, 0, 20) })
	end
end

function render()
	local win = S.win
	if not win or S.rolling then
		return
	end
	local p = pending()
	if p and S.pick ~= p.card then
		S.pick = p.card
	end
	drawGrid(win.Body.Cards)
	drawSide(win.Body.Side)
end

---------------------------------------------------------------------------
-- The roll
---------------------------------------------------------------------------

function EnchantUI.roll(lucky)
	if S.busy or S.rolling or not S.pick or pending() then
		return
	end
	S.busy = true
	S.note = nil
	fire("Enchant", { id = S.pick, mode = lucky and "lucky" or "coins" })
	task.delay(5, function()
		S.busy = false
	end)
end

-- The rim flickers through the colours, slows down and lands on the result.
local function playRoll(r, after)
	local win = S.win
	local stage = win and win.Body.Side:FindFirstChild("Stage")
	local big = stage and stage:FindFirstChild("BigCard")
	if not big then
		after()
		return
	end
	S.rolling = true
	local rank = Enchants.Rank[r.rarity] or 1
	local rim = make("Frame", { Name = "RollRim", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 14, 1, 14), ZIndex = 45 }, big)
	corner(rim, 14)
	local rs = stroke(rim, TEXT, 6)
	local word = text(stage, "", { Name = "RollWord", Font = TITLE_FONT, TextSize = 30, TextStrokeTransparency = 0.2, Size = UDim2.new(1.6, 0, 0, 36), Position = UDim2.new(-0.3, 0, 0.5, -18), ZIndex = 60, TextXAlignment = Enum.TextXAlignment.Center })
	Juice.sound("swish", 0.9, 0.4)
	-- flicker: fast, then slower; rarer results keep going a little longer (suspense)
	local ticks = 14 + rank * 2
	local idx = math.random(1, #Enchants.Rarities)
	for i = 1, ticks do
		idx = idx % #Enchants.Rarities + 1
		local show = (i == ticks) and r.rarity or Enchants.Rarities[idx]
		rs.Color = EnchantFx.color(show)
		word.Text = show
		word.TextColor3 = EnchantFx.color(show)
		Juice.sound("tick", 0.9 + (i / ticks) * 0.6, 0.25)
		task.wait(0.04 + (i / ticks) ^ 2 * 0.22)
		if not big.Parent then
			break
		end
	end
	-- land
	if big.Parent then
		local col = EnchantFx.color(r.rarity)
		word.Text = string.upper(r.rarity)
		word.TextColor3 = col
		EnchantFx.screenBurst(stage, UDim2.fromScale(0.5, 0.5), 240 + rank * 30, r.rarity)
		Juice.flash(win, col, 0.5 + rank * 0.05, 0.55)
		if rank >= 4 then
			Juice.shake(win, 4 + rank, 0.4)
			Juice.stars(stage, 0.5, 0.5, 6 + rank * 3)
		end
		if rank >= 5 then
			Juice.confetti(win, 0.5, 0.35, 30 + rank * 6)
		end
		Juice.sound(rank >= 4 and "fanfare" or "chime", 1, 0.55)
		Juice.pop(big, 1.15, 0.35)
		task.wait(1.1 + rank * 0.15)
	end
	if rim.Parent then
		rim:Destroy()
	end
	if word.Parent then
		TweenService:Create(word, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.45, function()
			word:Destroy()
		end)
	end
	S.rolling = false
	after()
end

local function onResult(data)
	if data.what ~= "Enchant" and data.what ~= "EnchantChoose" then
		return false
	end
	S.busy = false
	if not data.ok then
		S.note = { tostring(data.why or "That didn't work"), BAD }
		Juice.sound("thud", 1.2, 0.3)
		render()
		return true
	end
	if data.what == "Enchant" then
		local e = Enchants.get(data.enchant)
		playRoll({ rarity = data.rarity or (e and e.rarity) or "Common" }, function()
			S.note = data.pending and { "A " .. (data.rarity or "") .. " rune! Keep it, or keep the old one?", GOLD } or { "◆ " .. (e and e.name or "Enchanted") .. "!", rarityColor(data.rarity) }
			render()
		end)
	else
		S.note = { data.kept == "new" and "The new rune is on." or "The old rune stays.", TEXT }
		render()
	end
	return true
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function EnchantUI.isOpen()
	return S.win ~= nil and S.win.Parent ~= nil
end

function EnchantUI.close()
	if S.win then
		local w = S.win
		S.win = nil
		S.rolling = false
		UIKit.close(w)
	end
end

function EnchantUI.open()
	if not S.ctx or EnchantUI.isOpen() then
		return
	end
	local f = make("Frame", { Name = "EnchantWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(760, 560), BackgroundColor3 = PANEL }, S.ctx.gui)
	S.win = f
	corner(f, 16)
	stroke(f, CRYSTAL, 2)
	fit(f, 800, 600)
	text(f, "◆ Enchanting Crystal", { Font = TITLE_FONT, TextSize = 26, TextColor3 = CRYSTAL, Size = UDim2.new(1, -70, 0, 32), Position = UDim2.fromOffset(18, 10), TextXAlignment = Enum.TextXAlignment.Left })
	text(f, "Put a rune on a card. Every rune rarity glows in its own colour.", { TextColor3 = DIM, Size = UDim2.new(1, -70, 0, 18), Position = UDim2.fromOffset(18, 42), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.closeButton(f, EnchantUI.close, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -48, 0, 10) })
	-- a short brief the first time, and a ? to see it again (MenuBriefs)
	local MenuBriefs = require(here:WaitForChild("MenuBriefs"))
	MenuBriefs.helpButton(f, "Enchant", { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -92, 0, 10) }, "center")
	MenuBriefs.maybe("Enchant", { place = "center", still = function()
		return f.Parent ~= nil and S.win == f
	end })
	local body = make("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 1, -84) }, f)
	local cards = make("ScrollingFrame", { Name = "Cards", BackgroundColor3 = INK, BackgroundTransparency = 0.4, BorderSizePixel = 0, Size = UDim2.new(1, -306, 1, 0), ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, body)
	corner(cards, 12)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(84, 118), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, cards)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, cards)
	make("Frame", { Name = "Side", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 290, 1, 0) }, body)
	UIKit.animateIn(f)
	if UIKit.Focus and UIKit.Focus.watch then
		pcall(UIKit.Focus.watch, f)
	end
	render()
	fire("GetDecks")
end

function EnchantUI.init(ctx)
	S.ctx = ctx
	local r = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MenuAction")
	r.OnClientEvent:Connect(function(what, data)
		if type(data) ~= "table" then
			return
		end
		if what == "Decks" then
			S.snap = data
			render()
		elseif what == "CardResult" and EnchantUI.isOpen() then
			onResult(data)
		end
	end)
end

return EnchantUI

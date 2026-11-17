-- EnchantUI: the Enchanting Crystal's window in the Park. Client only. ParkClient opens it from
-- the crystal's "Enchant" prompt. The rules are in Enchants, the save and the dice on the server
-- (EconomyManager.enchantCard / chooseEnchant through MenuServer's "Enchant" and
-- "EnchantChoose", answered by "CardResult" and a fresh "Decks" snapshot).
--
--   EnchantUI.init(ctx)   once (ctx: gui, makeCard, toast, hideMenus(hidden) for the enchant scene)
--   EnchantUI.open()      the crystal's prompt
--   EnchantUI.close()     closes the window (and the enchant scene, at once): leaving the Park
--   EnchantUI.escape()    Escape: puts the enchant scene away and keeps the window; true if it did
--   EnchantUI.isOpen()
--
-- The window: your cards on the left (enchanted ones glow in their rune's colour), the card you
-- picked big on the right with its rune, Enchant (Shards) and Lucky (Gems) buttons, the odds, how
-- close the next sure Epic is and where Shards come from; your Shards at the top. Enchant and
-- Lucky play the enchant itself in front of everything (EnchantStage): the card comes forward,
-- every menu steps away, the world blurs, and the rune lands with a pop and a shake that grow with
-- its rarity. Rolling a card that already wears a rune asks: keep the new one or the old one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local Enchants = require(here:WaitForChild("Enchants"))
local EnchantFx = require(here:WaitForChild("EnchantFx"))
local EnchantStage = require(here:WaitForChild("EnchantStage"))
local DeckRules = require(here:WaitForChild("DeckRules"))
local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
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
local BOLD_FONT = Enum.Font.GothamBold

local EARN_SHARDS = "Shards come from the Campaign, the hourly Challenge, the Trophy Road and achievements."

local EnchantUI = {}

local S = {
	ctx = nil,
	win = nil,
	snap = nil, -- the latest "Decks" snapshot (cards, enchants, enchantPity, enchantPending)
	pick = nil, -- the card picked
	busy = false, -- a request is on its way
	busyToken = nil,
	stage = nil, -- the enchant scene while it's up (EnchantStage)
	shards = nil, -- the Shards number at the top of the window
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

-- A request is on its way: no second one until it's answered (or a while has passed).
local function setBusy()
	S.busy = true
	local token = {}
	S.busyToken = token
	task.delay(EnchantStage.Timeout + 2, function()
		if S.busyToken == token then
			S.busy = false
			S.busyToken = nil
		end
	end)
end

local function clearBusy()
	S.busy = false
	S.busyToken = nil
end

local function fit(frame, width, height)
	local cam = workspace.CurrentCamera
	local view = cam and cam.ViewportSize or Vector2.new(1280, 720)
	local scale = math.min(1, (view.X - 24) / width, (view.Y - 24) / height)
	if scale < 1 then
		make("UIScale", { Name = "Fit", Scale = math.max(0.4, scale) }, frame)
	end
end

-- A card face that ignores clicks (its cell or holder takes them). gem: the rune gem's size.
local function face(parent, id, enchant, gem)
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
			EnchantFx.decorateCard(card, enchant, { gem = gem })
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

-- Is the enchant scene up (or still flying the card back)?
local function staged()
	return S.stage ~= nil
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
		text(box, e.rarity .. " rune · " .. e.text, { Name = "Text", TextSize = 13, Position = UDim2.fromOffset(12, 29), Size = UDim2.new(1, -24, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	else
		text(box, "No rune yet", { Name = "Name", Font = TITLE_FONT, TextSize = 18, TextColor3 = DIM, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Left })
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
		face(cell, id, en[id], 14)
		if S.pick == id then
			local sel = make("Frame", { Name = "Picked", BackgroundTransparency = 1, Size = UDim2.new(1, 6, 1, 6), Position = UDim2.fromOffset(-3, -3), ZIndex = 40 }, cell)
			corner(sel, 12)
			stroke(sel, GOLD, 3)
		end
		cell.Activated:Connect(function()
			if staged() or pending() then
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
	local big = face(stage, id, en[id], 20)
	if big then
		big.Name = "BigCard"
	end
	text(side, d.name, { Name = "CardName", Font = TITLE_FONT, TextSize = 20, TextColor3 = GOLD, Position = UDim2.fromOffset(0, 218), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center })
	enchantLine(side, en[id], { Position = UDim2.fromOffset(0, 246) })
	local p = pending()
	if p then
		-- the choice (when the enchant scene was put away before it): the new rune or the old one
		local new, old = Enchants.get(p.enchant), Enchants.get(en[p.card])
		text(side, "Which rune stays on " .. (CardData.Cards[p.card] and CardData.Cards[p.card].name or "the card") .. "?", { Name = "Ask", Font = TITLE_FONT, TextSize = 16, Position = UDim2.fromOffset(0, 316), Size = UDim2.new(1, 0, 0, 22) })
		local keepNew = button(side, "Keep new: " .. (new and new.name or "?"), new and rarityColor(new.rarity):Lerp(INK, 0.35) or TILE, function()
			if S.busy then
				return
			end
			setBusy()
			fire("EnchantChoose", { keep = "new" })
		end, { Name = "KeepNew", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 342), TextSize = 16 })
		keepNew.TextTruncate = Enum.TextTruncate.AtEnd
		local keepOld = button(side, "Keep old: " .. (old and old.name or "?"), TILE, function()
			if S.busy then
				return
			end
			setBusy()
			fire("EnchantChoose", { keep = "old" })
		end, { Name = "KeepOld", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 388), TextSize = 16 })
		keepOld.TextTruncate = Enum.TextTruncate.AtEnd
		if new then
			text(side, new.rarity .. " · " .. new.text, { TextSize = 12, TextColor3 = rarityColor(new.rarity), Position = UDim2.fromOffset(0, 432), Size = UDim2.new(1, 0, 0, 30) })
		end
		if S.note then
			text(side, S.note[1], { Name = "Note", TextSize = 13, Font = BOLD_FONT, TextColor3 = S.note[2], Position = UDim2.fromOffset(0, 468), Size = UDim2.new(1, 0, 0, 34) })
		end
		return
	end
	-- the buttons: Enchant (Shards) and Lucky (Gems), darker when you can't afford them (pressing
	-- one still says where to get more)
	local cur, cost = ShopCatalog.priceOf(Enchants.Cost)
	local lcur, lcost = ShopCatalog.priceOf(Enchants.LuckyCost)
	local go = button(side, "", rgb(124, 72, 206), function()
		EnchantUI.roll(false)
	end, { Name = "EnchantButton", Size = UDim2.new(0.5, -4, 0, 44), Position = UDim2.fromOffset(0, 316) })
	UIKit.caption(go, cur, "Enchant  " .. cost)
	local lucky = button(side, "", rgb(50, 120, 170), function()
		EnchantUI.roll(true)
	end, { Name = "LuckyButton", Size = UDim2.new(0.5, -4, 0, 44), Position = UDim2.new(0.5, 4, 0, 316) })
	UIKit.caption(lucky, lcur, "Lucky  " .. lcost)
	if cur and (player:GetAttribute(cur) or 0) < cost then
		go.BackgroundColor3 = rgb(70, 56, 96)
	end
	if lcur and (player:GetAttribute(lcur) or 0) < lcost then
		lucky.BackgroundColor3 = rgb(48, 64, 86)
	end
	-- everything under the buttons, one line after another
	local y = 366
	local function line(str, props, height)
		local t = text(side, str, props)
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(1, 0, 0, height)
		y += height + 4
		return t
	end
	if S.note then
		line(S.note[1], { Name = "Note", TextSize = 13, Font = BOLD_FONT, TextColor3 = S.note[2] }, 34)
	end
	local pity = (S.snap and S.snap.enchantPity) or 0
	local left = Enchants.untilPity(pity)
	line(left <= 1 and "★ Your next enchant is Epic or better!" or ("★ Epic or better within " .. left .. " enchants"), { Name = "Pity", TextSize = 13, TextColor3 = left <= 1 and GOLD or TEXT }, 18)
	line(EARN_SHARDS, { Name = "EarnShards", TextSize = 12, TextColor3 = UIKit.Color.shard:Lerp(TEXT, 0.35) }, 30)
	line("Odds: " .. oddsText(false), { Name = "Odds", TextSize = 11, TextColor3 = DIM }, 28)
	line("Lucky: no Commons · " .. oddsText(true), { Name = "LuckyOdds", TextSize = 11, TextColor3 = DIM }, 28)
	line("Runes count against bots and in the Campaign. In duels with players they glow, but cards play their printed numbers.", { Name = "DuelNote", TextSize = 11, TextColor3 = DIM }, 28)
end

local function drawShards()
	if S.shards and S.shards.Parent then
		S.shards.Text = ShopCatalog.format(player:GetAttribute("Shards") or 0)
	end
end

function render()
	local win = S.win
	if not win then
		return
	end
	local p = pending()
	if p and S.pick ~= p.card then
		S.pick = p.card
	end
	drawShards()
	drawGrid(win.Body.Cards)
	drawSide(win.Body.Side)
end

---------------------------------------------------------------------------
-- The enchant
---------------------------------------------------------------------------

-- Not enough Shards (or Gems): say where they come from.
local function cantAfford(cur, cost)
	local msg = cur == "Shards" and ("You need " .. cost .. " Shards. " .. EARN_SHARDS) or ("Lucky needs " .. cost .. " " .. tostring(cur) .. ".")
	Juice.sound("thud", 1.2, 0.3)
	local stage = S.stage
	if stage and stage.alive then
		stage:note(msg)
		return
	end
	S.note = { msg, BAD }
	render()
	local side = S.win and S.win.Body.Side
	local b = side and side:FindFirstChild(cur == "Shards" and "EnchantButton" or "LuckyButton")
	if b then
		Juice.shake(b, 5, 0.3)
	end
end

-- Opens the enchant scene for the picked card (the request is already on its way).
local function openStage(lucky)
	local id = S.pick
	local side = S.win and S.win.Body.Side
	local holder = side and side:FindFirstChild("Stage")
	local stage
	stage = EnchantStage.open({
		cardId = id,
		enchant = enchantsMap()[id],
		lucky = lucky,
		makeCard = S.ctx.makeCard,
		hideMenus = S.ctx.hideMenus,
		from = holder and holder:FindFirstChild("BigCard"),
		onAgain = function(again)
			EnchantUI.roll(again)
		end,
		onChoose = function(keep)
			setBusy()
			fire("EnchantChoose", { keep = keep })
		end,
		onClosed = function()
			if S.stage == stage then
				S.stage = nil
			end
			render()
		end,
	})
	S.stage = stage
end

-- Enchant (lucky = false, Shards) or Lucky (Gems) the picked card: from the window, or again
-- from the enchant scene's own buttons.
function EnchantUI.roll(lucky)
	if S.busy or not S.pick or pending() or not S.ctx then
		return
	end
	local stage = S.stage
	if stage and not (stage.alive and stage.phase == "result") then
		return -- (mid-roll, or still flying the card back)
	end
	local cur, cost = ShopCatalog.priceOf(lucky and Enchants.LuckyCost or Enchants.Cost)
	if cur and (player:GetAttribute(cur) or 0) < cost then
		cantAfford(cur, cost)
		return
	end
	setBusy()
	S.note = nil
	fire("Enchant", { id = S.pick, mode = lucky and "lucky" or "shards" })
	if stage then
		stage:again(lucky)
	else
		openStage(lucky)
	end
end

-- The server's answer to Enchant / EnchantChoose: to the enchant scene while it's up, else a line
-- in the window. (A fresh "Decks" snapshot follows it.)
local function onResult(data)
	if data.what ~= "Enchant" and data.what ~= "EnchantChoose" then
		return false
	end
	clearBusy()
	-- keep the snapshot in step until the fresh one arrives (so "Enchant again" works at once)
	local snap = S.snap
	if data.ok and snap and type(data.id) == "string" then
		snap.enchants = snap.enchants or {}
		if data.what == "Enchant" then
			if data.pending then
				snap.enchantPending = { card = data.id, enchant = data.enchant }
			else
				snap.enchants[data.id] = data.enchant
			end
			snap.enchantPity = tonumber(data.pity) or snap.enchantPity
		else
			snap.enchantPending = nil
			snap.enchants[data.id] = data.enchant
		end
	end
	local stage = S.stage
	if stage and stage.alive then
		if data.what == "Enchant" then
			stage:result(data)
		else
			stage:chosen(data)
		end
		return true
	end
	if not data.ok then
		S.note = { tostring(data.why or "That didn't work."), BAD }
		Juice.sound("thud", 1.2, 0.3)
	elseif data.what == "Enchant" then
		local e = Enchants.get(data.enchant)
		S.note = data.pending and { "A " .. (data.rarity or "new") .. " rune! Keep it, or keep the old one?", GOLD } or { "◆ " .. (e and e.name or "A rune") .. " is on!", rarityColor(data.rarity) }
	else
		S.note = { data.kept == "new" and "The new rune is on." or "The old rune stays.", TEXT }
	end
	render()
	return true
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function EnchantUI.isOpen()
	return S.win ~= nil and S.win.Parent ~= nil
end

function EnchantUI.close()
	local stage = S.stage
	if stage then
		S.stage = nil
		stage:close(true)
	end
	if S.win then
		local w = S.win
		S.win = nil
		S.shards = nil
		UIKit.close(w, function()
			w:Destroy()
		end)
	end
end

-- Escape: the enchant scene goes first (the card flies back, the window stays open).
function EnchantUI.escape()
	local stage = S.stage
	if stage and stage.alive then
		stage:close()
		return true
	end
	return false
end

function EnchantUI.open()
	if not S.ctx or EnchantUI.isOpen() then
		return
	end
	local f = make("Frame", { Name = "EnchantWindow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(760, 640), BackgroundColor3 = PANEL }, S.ctx.gui)
	S.win = f
	corner(f, 16)
	stroke(f, CRYSTAL, 2)
	fit(f, 800, 680)
	text(f, "◆ Enchanting Crystal", { Font = TITLE_FONT, TextSize = 26, TextColor3 = CRYSTAL, Size = UDim2.new(1, -260, 0, 32), Position = UDim2.fromOffset(18, 10), TextXAlignment = Enum.TextXAlignment.Left })
	text(f, "Put a rune on a card. Every rune rarity glows in its own colour.", { TextColor3 = DIM, Size = UDim2.new(1, -70, 0, 18), Position = UDim2.fromOffset(18, 42), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.closeButton(f, EnchantUI.close, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -48, 0, 10) })
	-- your Shards, next to the ? and the close button
	local pill = make("Frame", { Name = "ShardsPill", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -104, 0, 12), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = INK, BackgroundTransparency = 0.25 }, f)
	corner(pill, 16)
	make("UIStroke", { Color = UIKit.Color.shard, Thickness = 1.5, Transparency = 0.45 }, pill)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }, pill)
	local _, shards = UIKit.currency(pill, "Shards", ShopCatalog.format(player:GetAttribute("Shards") or 0), { size = 18, height = 32 })
	S.shards = shards
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
		elseif what == "CardResult" and (EnchantUI.isOpen() or S.stage ~= nil) then
			onResult(data)
		end
	end)
	-- your Shards at the top of the window (and the buttons' prices darken when you run out)
	player:GetAttributeChangedSignal("Shards"):Connect(function()
		if not EnchantUI.isOpen() then
			return
		end
		if staged() then
			drawShards() -- (the window is hidden behind the enchant scene)
			return
		end
		render()
		local pill = S.shards and S.shards.Parent and S.shards.Parent.Parent
		if pill then
			Juice.pop(pill, 1.12, 0.35)
		end
	end)
end

return EnchantUI

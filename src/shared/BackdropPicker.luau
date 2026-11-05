-- Match backgrounds at the Deck Shelf: pick the world around the Duel Table for your matches,
-- try one on, buy one, or see how far the Trophy Road is from it. Client only.
--
-- The worlds are cosmetics (ShopCatalog, kind "backdrop"): Card Den and "Surprise me" are free,
-- Gumdrop Plaza, Frostglass Lake and Midnight Mall are sold in the Shop, Sunset Grasslands,
-- Ember Caldera and Cosmic Void are earned on the Trophy Road (Trophy Wall). The server owns
-- what you own and what you wear (EconomyManager); this screen shows ShopUI's snapshot and sends
-- "Buy" / "Equip" through the Shop's remote.
--
-- Preview: the world goes up around the table and the camera floats through it, with a small
-- bar at the bottom (wear / buy, the next and previous worlds, back). DeckWarsClient does the
-- camera and hides the menu (ui.previewBackdrop / ui.endBackdropPreview).
--
--   BackdropPicker.init(kit)       -- once, from DeckWarsClient
--   BackdropPicker.render(parent)  -- draws the picker into the Deck Shelf's big left panel
--   BackdropPicker.preview(key)    -- the preview (also from the Shop's background tiles)
--   BackdropPicker.endPreview()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
local Backdrops = require(here:WaitForChild("Backdrops"))
local Progression = require(here:WaitForChild("Progression"))
local Juice = require(here:WaitForChild("Juice"))

local rgb, make, tween = Juice.rgb, Juice.make, Juice.tween

local BackdropPicker = {}

local GOLD = rgb(255, 220, 90)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(176, 170, 196)
local GOOD = rgb(90, 200, 120)
local TILE = rgb(38, 32, 56)
local INK = rgb(14, 11, 22)
local WHITE = Color3.new(1, 1, 1)
local COIN = rgb(255, 200, 70)
local GEM = rgb(110, 200, 255)
local TROPHY = rgb(255, 176, 70)
local TITLE_FONT = Enum.Font.FredokaOne

local kit = nil
local state = {
	parent = nil, -- the Deck Shelf panel while the picker is open
	previewing = nil, -- the key being previewed
	bar = nil,
	confirm = nil, -- { id, untilT } a Gem buy waiting for its second tap
	listening = false,
}

local function snap()
	local ShopUI = require(here:WaitForChild("ShopUI"))
	return ShopUI.snapshot()
end

local function shopAction()
	return ReplicatedStorage:WaitForChild("EconomyRemotes"):WaitForChild("ShopAction")
end

-- The backgrounds in the order they show: free ones, Shop ones, Trophy Road ones.
local function list()
	local out = {}
	for _, c in ipairs(ShopCatalog.Cosmetics) do
		if c.kind == "backdrop" then
			table.insert(out, c)
		end
	end
	local rank = function(c)
		return c.default and 0 or (c.road and 2 or 1)
	end
	table.sort(out, function(a, b)
		if rank(a) ~= rank(b) then
			return rank(a) < rank(b)
		end
		return a.order < b.order
	end)
	return out
end

local function roadStop(id)
	for i, stop in ipairs(Progression.TrophyRoad) do
		if stop.cosmetic == id then
			return i, stop
		end
	end
	return nil, nil
end

local function trophies()
	return Players.LocalPlayer:GetAttribute("Trophies") or 0
end

local function owns(c, s)
	return c.default or (s and s.owned and s.owned[c.id] == true)
end

local function wearing(c, s)
	local eq = s and s.equipped and s.equipped.backdrop or ShopCatalog.DefaultEquipped.backdrop
	return eq == c.id
end

local function priceText(price)
	local cur, amount = ShopCatalog.priceOf(price)
	return (ShopCatalog.Icon[cur] or "") .. " " .. ShopCatalog.format(amount), cur, amount
end

local function balance(s, cur)
	return s and (cur == "Gems" and s.gems or s.coins) or 0
end

local function corner(obj, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 10) }, obj)
end

local function text(parent, str, props)
	local base = { BackgroundTransparency = 1, Font = kit and kit.BODY_FONT or Enum.Font.GothamMedium, TextScaled = false, TextSize = 14, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, Text = str }
	for k, v in pairs(props or {}) do
		base[k] = v
	end
	return make("TextLabel", base, parent)
end

local function pill(parent, label, color, onClick, props)
	local b = make("TextButton", {
		Text = label,
		Font = TITLE_FONT,
		TextSize = 16,
		TextColor3 = WHITE,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 9)
	make("UIStroke", { Thickness = 1.5, Color = color:Lerp(WHITE, 0.35), Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, rgb(205, 200, 215)) }, b)
	if onClick then
		b.Activated:Connect(onClick)
	end
	Juice.button(b, { grow = 1.05 })
	return b
end

-- The little painting of a world on its card: its two colours, a horizon and its emoji.
local function art(parent, info, size)
	local box = make("Frame", { Name = "Art", Size = size, BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true }, parent)
	corner(box, 10)
	local c1, c2 = info.colors[1], info.colors[2]
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(c1:Lerp(WHITE, 0.15), c2) }, box)
	-- far hills
	for k = 0, 2 do
		local hill = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.18 + k * 0.33, 0, 0.62 - (k % 2) * 0.06, 0),
			Size = UDim2.fromScale(0.7, 0.8),
			BackgroundColor3 = c2:Lerp(INK, 0.35 + k * 0.08),
			BorderSizePixel = 0,
		}, box)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, hill)
	end
	-- the table in the middle, tiny
	local tbl = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.34, 0.12), BackgroundColor3 = rgb(90, 58, 36), BorderSizePixel = 0 }, box)
	corner(tbl, 4)
	local felt = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -5), BackgroundColor3 = rgb(40, 92, 60), BorderSizePixel = 0 }, tbl)
	corner(felt, 3)
	local e = text(box, info.emoji, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromScale(0.5, 0.5), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBold })
	Juice.bob(e, 3, 1.6)
	-- a soft vignette
	local v = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2 }, box)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 0.45) }) }, v)
	return box
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function equip(c)
	shopAction():FireServer("Equip", "backdrop", c.id)
	Juice.sound("chime", 1.1, 0.4)
end

local function buy(c, button)
	local s = snap()
	local label, cur, amount = priceText(c.price)
	if balance(s, cur) < amount then
		local ShopUI = require(here:WaitForChild("ShopUI"))
		ShopUI.toast("Not enough " .. tostring(cur) .. " for " .. c.name .. ".", "bad")
		if button then
			Juice.shake(button, 5, 0.25)
		end
		return
	end
	if cur == "Gems" then
		local cf = state.confirm
		if not (cf and cf.id == c.id and time() < cf.untilT) then
			state.confirm = { id = c.id, untilT = time() + 3 }
			if button then
				button.Text = "Tap again: " .. label
				task.delay(3, function()
					if button.Parent and state.confirm and state.confirm.id == c.id and time() >= state.confirm.untilT then
						button.Text = label
						state.confirm = nil
					end
				end)
			end
			return
		end
		state.confirm = nil
	end
	shopAction():FireServer("Buy", "cosmetic", c.id)
end

-- The main button for a background: Wearing / Wear / Buy / Trophy Road.
local function actionButton(parent, c, s, props)
	if owns(c, s) then
		if wearing(c, s) then
			local b = pill(parent, "✓  Wearing", GOOD:Lerp(TILE, 0.35), nil, props)
			b.AutoButtonColor = false
			return b
		end
		return pill(parent, "Wear", rgb(90, 150, 255), function()
			equip(c)
		end, props)
	elseif c.road then
		local _, stop = roadStop(c.id)
		local need = stop and stop.at or 0
		local b = pill(parent, "🏆 " .. math.min(trophies(), need) .. " / " .. need, TROPHY:Lerp(TILE, 0.55), function()
			local ShopUI = require(here:WaitForChild("ShopUI"))
			ShopUI.toast("🏆 " .. c.name .. " is on the Trophy Road at " .. need .. " trophies. Win matches to get there, then claim it at the Trophy Wall.", "info", { time = 5 })
		end, props)
		return b
	end
	local label, cur, amount = priceText(c.price)
	local color = cur == "Gems" and GEM or COIN
	local b
	b = pill(parent, label, balance(s, cur) >= amount and color:Lerp(INK, 0.15) or color:Lerp(rgb(70, 66, 86), 0.65), function()
		buy(c, b)
	end, props)
	b.TextColor3 = balance(s, cur) >= amount and INK or DIM
	return b
end

---------------------------------------------------------------------------
-- The grid (Deck Shelf left panel)
---------------------------------------------------------------------------
local function statusLine(c, s)
	if wearing(c, s) then
		return "In your matches now", GOLD
	elseif owns(c, s) then
		return c.default and "Free" or "Unlocked", GOOD
	elseif c.road then
		local _, stop = roadStop(c.id)
		return "Trophy Road reward at " .. (stop and stop.at or "?") .. " 🏆", TROPHY
	end
	return "In the Shop", DIM
end

function BackdropPicker.render(parent)
	state.parent = parent
	local s = snap()
	local root = make("Frame", { Name = "Backgrounds", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	text(root, "Match backgrounds", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(16, 8), Font = TITLE_FONT, TextSize = 28, TextColor3 = GOLD })
	text(root, "The world around the Duel Table in your matches. Only you see yours. Unlock more in the Shop or on the Trophy Road.", {
		Size = UDim2.new(1, -32, 0, 36),
		Position = UDim2.fromOffset(16, 42),
		TextColor3 = DIM,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local scroll = make("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.new(1, -24, 1, -92),
		Position = UDim2.fromOffset(12, 84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, root)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(212, 262), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10) }, scroll)
	for i, c in ipairs(list()) do
		local info = Backdrops.ByKey[c.backdrop]
		if info then
			local on = wearing(c, s)
			local card = make("Frame", { Name = "BG_" .. c.backdrop, BackgroundColor3 = on and rgb(58, 48, 30) or TILE, LayoutOrder = i, BorderSizePixel = 0 }, scroll)
			corner(card, 14)
			make("UIStroke", { Thickness = on and 2.5 or 1.2, Color = on and GOLD or rgb(80, 72, 108), Transparency = on and 0 or 0.35 }, card)
			art(card, info, UDim2.new(1, -16, 0, 112)).Position = UDim2.fromOffset(8, 8)
			local locked = not owns(c, s)
			if locked then
				local lock = text(card, "🔒", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 12), Size = UDim2.fromOffset(28, 28), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
				lock.TextTransparency = 0.1
			end
			text(card, c.name, { Position = UDim2.fromOffset(12, 126), Size = UDim2.new(1, -24, 0, 24), Font = TITLE_FONT, TextSize = 19, TextTruncate = Enum.TextTruncate.AtEnd })
			local st, stColor = statusLine(c, s)
			text(card, st, { Position = UDim2.fromOffset(12, 150), Size = UDim2.new(1, -24, 0, 16), TextSize = 12, TextColor3 = stColor })
			text(card, c.blurb or info.blurb or "", { Position = UDim2.fromOffset(12, 168), Size = UDim2.new(1, -24, 0, 44), TextSize = 12, TextColor3 = DIM, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
			local row = make("Frame", { Position = UDim2.new(0, 10, 1, -46), Size = UDim2.new(1, -20, 0, 36), BackgroundTransparency = 1 }, card)
			if c.backdrop ~= "Random" then
				pill(row, "👁", rgb(70, 64, 100), function()
					BackdropPicker.preview(c.backdrop)
				end, { Name = "Preview", Size = UDim2.new(0, 40, 1, 0), TextSize = 17 })
				actionButton(row, c, s, { Name = "Action", Size = UDim2.new(1, -46, 1, 0), Position = UDim2.fromOffset(46, 0) })
			else
				actionButton(row, c, s, { Name = "Action", Size = UDim2.fromScale(1, 1) })
			end
			-- the cards slide up into place one after another
			card.BackgroundTransparency = 1
			tween(card, 0.35, { BackgroundTransparency = 0 })
			Juice.popIn(card, 0.03 * i, { twist = 0, time = 0.35, sound = false })
		end
	end
	return root
end

-- Repaints the picker when the save changes (bought, worn, a road reward claimed).
local function refresh()
	local p = state.parent
	if p and p.Parent then
		local old = p:FindFirstChild("Backgrounds")
		if old and old.Parent then
			old:Destroy()
			BackdropPicker.render(p)
		end
	end
	if state.previewing then
		BackdropPicker.drawBar()
	end
end
BackdropPicker.refresh = refresh

---------------------------------------------------------------------------
-- Preview: the world around the table, the camera floating through it
---------------------------------------------------------------------------
local function previewList()
	local out = {}
	for _, c in ipairs(list()) do
		if c.backdrop ~= "Random" then
			table.insert(out, c)
		end
	end
	return out
end

function BackdropPicker.drawBar()
	local key = state.previewing
	if not key then
		return
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("DeckWarsBackdropPreview")
	if not gui then
		gui = make("ScreenGui", { Name = "DeckWarsBackdropPreview", ResetOnSpawn = false, DisplayOrder = 30, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
	end
	gui.Enabled = true
	local fresh = state.bar == nil or state.bar.Parent == nil
	if state.bar then
		state.bar:Destroy()
	end
	local s = snap()
	local c = ShopCatalog.BackdropByKey[key]
	local info = Backdrops.ByKey[key]
	local bar = make("Frame", { Name = "PreviewBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28), Size = UDim2.fromOffset(620, 92), BackgroundColor3 = INK, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, gui)
	state.bar = bar
	corner(bar, 18)
	make("UIStroke", { Thickness = 1.5, Color = info and info.colors[1] or GOLD, Transparency = 0.25 }, bar)
	make("UIGradient", { Rotation = 0, Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 195, 215)) }, bar)
	pill(bar, "◀", rgb(60, 54, 86), function()
		BackdropPicker.step(-1)
	end, { Name = "PrevWorld", Size = UDim2.fromOffset(40, 40), Position = UDim2.new(0, 14, 0.5, -20) })
	text(bar, (info and info.emoji or "") .. "  " .. (c and c.name or key), { Position = UDim2.fromOffset(66, 12), Size = UDim2.new(1, -330, 0, 30), Font = TITLE_FONT, TextSize = 24, TextColor3 = WHITE, TextTruncate = Enum.TextTruncate.AtEnd })
	local st, stColor = "", DIM
	if c then
		st, stColor = statusLine(c, s)
	end
	text(bar, st, { Position = UDim2.fromOffset(66, 44), Size = UDim2.new(1, -330, 0, 18), TextSize = 13, TextColor3 = stColor })
	text(bar, "Esc to go back", { Position = UDim2.fromOffset(66, 64), Size = UDim2.new(1, -330, 0, 16), TextSize = 11, TextColor3 = DIM })
	if c then
		actionButton(bar, c, s, { Name = "Action", Size = UDim2.fromOffset(150, 44), Position = UDim2.new(1, -258, 0.5, -22) })
	end
	pill(bar, "Back", rgb(110, 60, 76), function()
		BackdropPicker.endPreview()
	end, { Name = "EndPreview", Size = UDim2.fromOffset(60, 44), Position = UDim2.new(1, -100, 0.5, -22) })
	pill(bar, "▶", rgb(60, 54, 86), function()
		BackdropPicker.step(1)
	end, { Name = "NextWorld", Size = UDim2.fromOffset(28, 40), Position = UDim2.new(1, -36, 0.5, -20) })
	if fresh then
		bar.Position = UDim2.new(0.5, 0, 1, 120)
		tween(bar, 0.45, { Position = UDim2.new(0.5, 0, 1, -28) }, Enum.EasingStyle.Back)
	end
end

function BackdropPicker.step(dir)
	local items = previewList()
	local at = 1
	for i, c in ipairs(items) do
		if c.backdrop == state.previewing then
			at = i
		end
	end
	local nextC = items[(at - 1 + dir) % #items + 1]
	if nextC then
		BackdropPicker.preview(nextC.backdrop)
	end
end

function BackdropPicker.preview(key)
	if not (kit and kit.preview) then
		return false
	end
	if not kit.preview(key) then
		return false
	end
	state.previewing = key
	BackdropPicker.drawBar()
	Juice.sound("whoosh", 1, 0.3)
	return true
end

function BackdropPicker.endPreview()
	if not state.previewing then
		return
	end
	state.previewing = nil
	local bar = state.bar
	state.bar = nil
	if bar and bar.Parent then
		tween(bar, 0.25, { Position = UDim2.new(0.5, 0, 1, 120) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(0.3, function()
			bar:Destroy()
		end)
	end
	if kit and kit.endPreview then
		kit.endPreview()
	end
end

-- Drops the preview without touching the camera or the world (a match is taking over).
function BackdropPicker.cancel()
	state.previewing = nil
	if state.bar then
		state.bar:Destroy()
		state.bar = nil
	end
end

function BackdropPicker.isPreviewing()
	return state.previewing ~= nil
end

function BackdropPicker.init(k)
	kit = k
	if state.listening then
		return
	end
	state.listening = true
	local ShopUI = require(here:WaitForChild("ShopUI"))
	ShopUI.onSnapshot(function()
		refresh()
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Trophies"):Connect(refresh)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not state.previewing then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace or key == Enum.KeyCode.ButtonB then
			-- (deferred: the room's own keys must not see this press as "back" once the menu returns)
			task.defer(BackdropPicker.endPreview)
		elseif not processed and (key == Enum.KeyCode.Right or key == Enum.KeyCode.D or key == Enum.KeyCode.DPadRight) then
			BackdropPicker.step(1)
		elseif not processed and (key == Enum.KeyCode.Left or key == Enum.KeyCode.A or key == Enum.KeyCode.DPadLeft) then
			BackdropPicker.step(-1)
		end
	end)
end

return BackdropPicker

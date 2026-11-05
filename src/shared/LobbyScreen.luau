-- The Duel Table panel (play the bot, or open a table for friends: 1v1, 2v2 or an 8-player
-- tournament), the tournament bracket, and short messages from the server ("That table is full").
-- Your party (PartyScreen) sits down with you when you lead it and open a table.
-- Client only. DeckWarsClient calls LobbyScreen.init(ctx) once, then LobbyScreen.show(body) when
-- the Duel Table panel opens.

local LobbyScreen = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local CardData = require(Shared:WaitForChild("CardData"))
local StarterDecks = require(Shared:WaitForChild("StarterDecks"))

local TABS = {
	{ key = "Bot", text = "🤖 Bot" },
	{ key = "Duel", text = "⚔ 1v1" },
	{ key = "Team", text = "👥 2v2" },
	{ key = "Cup", text = "🏆 Cup" },
}
local MODE_TEXT = {
	Bot = "Play Bot Bonkers. Good for learning the lanes.",
	Duel = "1v1 against a friend. Open a table, your friend joins it.",
	Team = "2v2: you and a teammate share 40 hit points and 8 lanes. Empty seats get bots.",
	Cup = "Tournament: 8 players, quarter-finals, semi-finals, final. Empty seats get bots.",
}
local DIFFS = { "Easy", "Medium", "Hard" }

function LobbyScreen.init(ctx)
	local make, corner, label, button, panel = ctx.make, ctx.corner, ctx.label, ctx.button, ctx.panel
	local WHITE, BLACK, BODY_FONT = ctx.WHITE, ctx.BLACK, ctx.BODY_FONT
	local player = ctx.player
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local MenuAction = Remotes:WaitForChild("MenuAction")
	local LobbyEvent = Remotes:WaitForChild("LobbyEvent")
	local ui = ctx.ui

	local L = {
		lobbies = {}, -- the latest list from the server
		tab = "Bot",
		deck = "Snack",
		difficulty = "Medium",
		body = nil, -- the station panel body while the Duel Table panel is open
		left = {}, -- [lobby id] = true: tournaments you left (you still show in their bracket)
		bracket = nil, -- { lobbyId, bracket } of your tournament
		bracketPending = false,
	}

	local function familyColor(f)
		local t = CardData.FamilyColors[f] or CardData.FamilyColors.Any
		return Color3.fromRGB(t[1], t[2], t[3])
	end

	local function mySlot(lobby)
		for i = 1, lobby.size do
			local s = lobby.slots[i]
			if s and s.kind == "human" and s.userId == player.UserId then
				return i
			end
		end
		return nil
	end

	-- The lobby you're in (or nil).
	local function myLobby()
		for _, lobby in ipairs(L.lobbies) do
			if mySlot(lobby) and not L.left[lobby.id] then
				return lobby
			end
		end
		return nil
	end

	---------------------------------------------------------------------------
	-- Toasts
	---------------------------------------------------------------------------

	ui.toast = label(ctx.gui, "", {
		Name = "Toast",
		Size = UDim2.fromOffset(560, 40),
		Position = UDim2.new(0.5, 0, 1, -84),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(35, 30, 50),
		BackgroundTransparency = 0.1,
		TextColor3 = Color3.fromRGB(255, 225, 140),
		Font = ctx.BODY_FONT,
		TextScaled = false,
		TextSize = 17,
		ZIndex = 60,
		Visible = false,
	})
	corner(ui.toast, 10)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, ui.toast)
	local toastToken = nil
	-- (kept in a local: MatchScreen puts its own in-match toast in ui.toast later, so the room's
	-- toasts used to land on the hidden match screen)
	local roomToast = ui.toast
	function LobbyScreen.toast(text)
		local token = {}
		toastToken = token
		roomToast.Text = text
		roomToast.Visible = true
		task.delay(3.5, function()
			if toastToken == token then
				roomToast.Visible = false
			end
		end)
	end

	---------------------------------------------------------------------------
	-- The bracket
	---------------------------------------------------------------------------

	ui.bracketPanel = panel(ui.menuUI, UDim2.fromOffset(660, 400), UDim2.fromOffset(24, 232), Vector2.new(0, 0))
	ui.bracketPanel.Name = "BracketPanel"
	ui.bracketPanel.Visible = false
	ui.bracketTitle = label(ui.bracketPanel, "🏆 Tournament", { Size = UDim2.new(1, -140, 0, 32), Position = UDim2.fromOffset(14, 12), TextScaled = false, TextSize = 24, TextColor3 = Color3.fromRGB(255, 220, 90), TextXAlignment = Enum.TextXAlignment.Left })
	button(ui.bracketPanel, "Close", Color3.fromRGB(110, 60, 70), function()
		ui.bracketPanel.Visible = false
	end, { Name = "CloseBracket", Size = UDim2.fromOffset(100, 36), Position = UDim2.new(1, -12, 0, 10), AnchorPoint = Vector2.new(1, 0) })
	ui.bracketBody = make("Frame", { Name = "Rounds", Size = UDim2.new(1, -28, 1, -64), Position = UDim2.fromOffset(14, 54), BackgroundTransparency = 1 }, ui.bracketPanel)

	local function entrantBox(parent, who, game, pos, size)
		local box = make("Frame", { Size = size, Position = pos, BackgroundColor3 = Color3.fromRGB(25, 22, 38) }, parent)
		corner(box, 8)
		local playing = game and game.status == "playing"
		make("UIStroke", { Thickness = playing and 3 or 1, Color = playing and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(90, 80, 120) }, box)
		local function line(e, y)
			local text, color = "…", Color3.fromRGB(150, 145, 170)
			if e then
				text = (e.bot and "🤖 " or "") .. e.name
				color = WHITE
				if e.userId == player.UserId then
					color = Color3.fromRGB(150, 255, 170)
				end
				if game and game.winner then
					if game.winner == e.slot then
						color = Color3.fromRGB(255, 220, 90)
						text = "★ " .. text
					else
						color = Color3.fromRGB(130, 120, 140)
					end
				end
			end
			label(box, text, { Size = UDim2.new(1, -12, 0.5, -3), Position = UDim2.new(0, 6, y, 2), Font = BODY_FONT, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left })
		end
		line(who and who.a, 0)
		line(who and who.b, 0.5)
		if playing then
			label(box, "⚔", { Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextColor3 = Color3.fromRGB(255, 200, 80) })
		end
		return box
	end

	function L.drawBracket()
		ui.bracketBody:ClearAllChildren()
		local b = L.bracket and L.bracket.bracket
		if not b then
			return
		end
		local colW = 0.29
		for r, round in ipairs(b.rounds) do
			local x = (r - 1) * 0.33
			label(ui.bracketBody, round.name, { Size = UDim2.new(colW, 0, 0, 24), Position = UDim2.new(x, 0, 0, 0), TextColor3 = Color3.fromRGB(255, 200, 120) })
			local n = #round.matches
			for k, game in ipairs(round.matches) do
				-- Spread the boxes so each one sits between the two it comes from.
				local slotH = (1 - 0.1) / n
				local y = 0.1 + slotH * (k - 1) + slotH / 2
				entrantBox(ui.bracketBody, game, game, UDim2.new(x, 0, y, -26), UDim2.new(colW, 0, 0, 52))
			end
		end
		if b.champion then
			ui.bracketTitle.Text = "🏆 Champion: " .. b.champion
		else
			ui.bracketTitle.Text = "🏆 Tournament"
		end
	end

	function L.showBracket()
		if not L.bracket then
			return
		end
		L.drawBracket()
		if ctx.getMode() == "menu" then
			ui.bracketPanel.Visible = true
			L.bracketPending = false
		else
			L.bracketPending = true
		end
	end

	-- Back in the room after a match: show the bracket if a tournament is on.
	function LobbyScreen.onMenu()
		if L.bracketPending or (L.bracket and not L.bracket.bracket.champion and not L.left[L.bracket.lobbyId]) then
			L.showBracket()
		end
	end

	---------------------------------------------------------------------------
	-- The Duel Table panel
	---------------------------------------------------------------------------

	local function send(what, options)
		MenuAction:FireServer(what, options or {})
	end

	local function clear(body)
		for _, c in ipairs(body:GetChildren()) do
			c:Destroy()
		end
	end

	-- The look of the panel: real font sizes everywhere (no squeezed text), sections with small
	-- gold headings, deck tiles with their family's colour, segmented pickers and one big button.
	local UIKit = require(Shared:WaitForChild("UIKit"))
	local Juice = require(Shared:WaitForChild("Juice"))
	local KC = UIKit.Color
	local TITLE, BODY, BOLD = UIKit.TITLE_FONT, UIKit.BODY_FONT, UIKit.BOLD_FONT
	local FAMILY_EMOJI = { Snack = "🍪", Junk = "🔩", Weather = "❄", Critter = "🐾", Spooky = "👻", Robo = "🤖", Any = "🃏" }

	local function txt(parent, text, size, color, props)
		local l = make("TextLabel", {
			BackgroundTransparency = 1,
			Text = text,
			Font = BODY,
			TextSize = size or 14,
			TextColor3 = color or KC.text,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}, parent)
		for k, v in pairs(props or {}) do
			l[k] = v
		end
		return l
	end

	-- A small gold heading with a thin line after it.
	local function heading(parent, text, order)
		local h = make("Frame", { Name = "Heading", Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		local l = make("TextLabel", { BackgroundTransparency = 1, Text = string.upper(text), Font = TITLE, TextSize = 15, TextColor3 = KC.gold, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Left }, h)
		local line = make("Frame", { Name = "Line", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(1, -8, 0, 1), BackgroundColor3 = KC.line, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, h)
		-- the line starts after the words
		local function fit()
			line.Size = UDim2.new(1, -(l.AbsoluteSize.X + 10), 0, 1)
		end
		l:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		return h
	end

	-- A flat, rounded tile button (Text left empty: its contents are drawn inside).
	local function tileButton(parent, name, on, order)
		local b = make("TextButton", {
			Name = name,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = on and KC.tileHi or KC.tile,
			LayoutOrder = order or 0,
		}, parent)
		corner(b, 10)
		make("UIStroke", { Thickness = on and 2.5 or 1, Color = on and KC.gold or KC.line, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		Juice.button(b, { grow = 1.03 })
		b.MouseEnter:Connect(function()
			if not on then
				TweenService:Create(b, TweenInfo.new(0.15), { BackgroundColor3 = KC.tileHi }):Play()
			end
		end)
		b.MouseLeave:Connect(function()
			if not on then
				TweenService:Create(b, TweenInfo.new(0.2), { BackgroundColor3 = KC.tile }):Play()
			end
		end)
		return b
	end

	-- A segmented picker: one rounded bar, the picked part in gold. items = { { key, text }... }
	local function segmented(parent, items, current, onPick, opts)
		opts = opts or {}
		local bar = make("Frame", { Name = opts.name or "Picker", Size = UDim2.new(1, 0, 0, opts.height or 42), BackgroundColor3 = Color3.fromRGB(20, 17, 32), LayoutOrder = opts.order or 0 }, parent)
		corner(bar, 12)
		make("UIStroke", { Thickness = 1, Color = KC.line, Transparency = 0.2 }, bar)
		make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, bar)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, bar)
		local n = #items
		for i, it in ipairs(items) do
			local on = it.key == current
			local b = make("TextButton", {
				Name = (opts.prefix or "") .. it.key,
				Text = it.text,
				RichText = true,
				AutoButtonColor = false,
				Font = TITLE,
				TextSize = opts.textSize or 16,
				TextColor3 = on and KC.ink or KC.text,
				BackgroundColor3 = on and KC.gold or KC.tile,
				BackgroundTransparency = on and 0 or 1,
				Size = UDim2.new(1 / n, -4 * (n - 1) / n, 1, 0),
				LayoutOrder = i,
			}, bar)
			corner(b, 9)
			if on then
				make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 196, 70)) }, b)
			else
				b.MouseEnter:Connect(function()
					TweenService:Create(b, TweenInfo.new(0.15), { BackgroundTransparency = 0.3 }):Play()
				end)
				b.MouseLeave:Connect(function()
					TweenService:Create(b, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
				end)
			end
			Juice.button(b, { grow = 1.04 })
			b.Activated:Connect(function()
				onPick(it.key)
			end)
		end
		return bar
	end

	local function row(parent, height, order)
		local f = make("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
		return f
	end

	local function small(parent, text, color, fn, width, order, name)
		return button(parent, text, color, fn, { Name = name or "Button", Size = UDim2.new(0, width or 70, 1, 0), LayoutOrder = order or 0, TextScaled = false, TextSize = 15 })
	end

	-- One deck: its family's colour on the left, its emoji, its name and a short line under it.
	local function deckTile(parent, key, name, sub, family, on, ok, order, onClick)
		local b = tileButton(parent, "Deck_" .. key, on, order)
		local fam = familyColor(family)
		local strip = make("Frame", { Name = "Strip", Size = UDim2.new(0, 5, 1, -14), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = fam, BorderSizePixel = 0 }, b)
		corner(strip, 3)
		make("TextLabel", { Name = "Emoji", BackgroundTransparency = 1, Text = FAMILY_EMOJI[family] or "🃏", TextSize = 22, Font = TITLE, Size = UDim2.new(0, 28, 1, 0), Position = UDim2.fromOffset(16, 0) }, b)
		make("TextLabel", {
			Name = "DeckName",
			BackgroundTransparency = 1,
			Text = (ok and "" or "⚠ ") .. name,
			Font = TITLE,
			TextSize = 16,
			TextColor3 = ok and (on and Color3.fromRGB(255, 240, 200) or KC.text) or KC.dim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -58, 0, 20),
			Position = UDim2.fromOffset(48, 7),
		}, b)
		make("TextLabel", {
			Name = "Sub",
			BackgroundTransparency = 1,
			Text = sub,
			Font = BODY,
			TextSize = 12,
			TextColor3 = fam:Lerp(WHITE, 0.45),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -58, 0, 16),
			Position = UDim2.fromOffset(48, 28),
		}, b)
		if on then
			local tick = make("TextLabel", { Name = "Picked", Text = "✓", Font = TITLE, TextSize = 13, TextColor3 = KC.ink, BackgroundColor3 = KC.gold, Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -6, 0, 6), AnchorPoint = Vector2.new(1, 0) }, b)
			corner(tick, 9)
		end
		b.Activated:Connect(onClick)
		return b
	end

	local function deckGrid(parent, name, order)
		local g = make("Frame", { Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		make("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 50), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, g)
		return g
	end

	-- A soft dark card for a block of info.
	local function infoCard(parent, order, name)
		local f = make("Frame", { Name = name or "Info", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(22, 18, 34), LayoutOrder = order }, parent)
		corner(f, 10)
		make("UIStroke", { Thickness = 1, Color = KC.line, Transparency = 0.4 }, f)
		make("UIPadding", { PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, f)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, f)
		return f
	end

	-- The big green button at the bottom.
	local function bigButton(parent, text, name, order, fn)
		local b = button(parent, text, Color3.fromRGB(58, 178, 88), fn, { Name = name, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = order, TextScaled = false, TextSize = 24 })
		b:FindFirstChildOfClass("UIStroke").Color = Color3.fromRGB(16, 50, 26)
		Juice.shine(b, 3.6, UDim.new(0, 10))
		return b
	end

	-- A list row (a table, a seat): dark, rounded, with room for buttons on the right.
	local function listRow(parent, name, order, mine)
		local r = make("Frame", { Name = name, Size = UDim2.new(1, -6, 0, 44), BackgroundColor3 = mine and Color3.fromRGB(34, 58, 46) or KC.tile, LayoutOrder = order }, parent)
		corner(r, 10)
		make("UIStroke", { Thickness = 1, Color = mine and Color3.fromRGB(90, 190, 120) or KC.line, Transparency = 0.3 }, r)
		return r
	end

	function L.renderBot(body)
		heading(body, "Bot difficulty", 20)
		local win = ctx.WinGems
		local items = {}
		for _, d in ipairs(DIFFS) do
			local reward = win and win[d] and ("\n<font size=\"12\" face=\"GothamMedium\">win +" .. win[d] .. " 💎</font>") or ""
			table.insert(items, { key = d, text = d .. reward })
		end
		segmented(body, items, L.difficulty, function(d)
			if d == L.difficulty then
				return
			end
			L.difficulty = d
			if ctx.prefs then
				ctx.prefs.set("Difficulty", d)
			end
			L.render()
		end, { name = "Difficulty", prefix = "Diff_", height = win and 54 or 42, textSize = 17, order = 21 })
		bigButton(body, "⚔  Sit down and play!", "PlayBot", 22, function()
			send("StartBotMatch", { deck = L.deck, difficulty = L.difficulty })
		end)
		if player:GetAttribute("FirstWinReady") == true and ctx.FirstWinBonus then
			txt(body, "⭐ Your first win today pays +" .. ctx.FirstWinBonus .. " 💎 more", 13, Color3.fromRGB(255, 210, 140), { Name = "FirstWin", TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 23 })
		end
	end

	-- Your party (see PartyScreen): who leads it and what happens when they open a table.
	local function partyLine()
		local PS = ctx.partyScreen
		local party = PS and PS.party and PS.party()
		if not party then
			return nil
		end
		if PS.isLeader() then
			return "👥 Your party (" .. #party.members .. ") sits down with you at any table you open or join."
		end
		return "👥 You're in " .. PS.leaderName() .. "'s party: when they open a table, you sit down with them."
	end
	local function inParty(userId)
		local PS = ctx.partyScreen
		return PS and PS.hasMember and userId ~= player.UserId and PS.hasMember(userId)
	end

	function L.renderList(body)
		local line = partyLine()
		if line then
			txt(body, line, 13, Color3.fromRGB(205, 175, 255), { Name = "PartyHint", LayoutOrder = 19 })
		end
		heading(body, "Open tables", 21)
		local scroll = make("Frame", { Name = "LobbyList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 22 }, body)
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		local any = false
		for i, lobby in ipairs(L.lobbies) do
			if lobby.mode == L.tab then
				any = true
				local taken = 0
				for k = 1, lobby.size do
					if lobby.slots[k] and lobby.slots[k].kind ~= "empty" then
						taken += 1
					end
				end
				local r = listRow(scroll, "Lobby_" .. lobby.id, i)
				make("TextLabel", { BackgroundTransparency = 1, Text = lobby.host .. "'s table", Font = TITLE, TextSize = 16, TextColor3 = KC.text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, -112, 0, 20), Position = UDim2.fromOffset(12, 4) }, r)
				make("TextLabel", { BackgroundTransparency = 1, Text = taken .. " / " .. lobby.size .. " seated" .. (lobby.started and "  ·  playing" or ""), Font = BODY, TextSize = 12, TextColor3 = KC.dim, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -112, 0, 16), Position = UDim2.fromOffset(12, 24) }, r)
				if lobby.started and lobby.cup then
					button(r, "Bracket", Color3.fromRGB(90, 80, 140), function()
						L.bracket = { lobbyId = lobby.id, bracket = lobby.cup }
						L.showBracket()
					end, { Size = UDim2.fromOffset(92, 32), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextScaled = false, TextSize = 15 })
				elseif not lobby.started then
					button(r, "Join", Color3.fromRGB(70, 130, 220), function()
						send("JoinLobby", { id = lobby.id, deck = L.deck })
					end, { Name = "Join_" .. lobby.id, Size = UDim2.fromOffset(92, 32), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), TextScaled = false, TextSize = 16 })
				end
			end
		end
		if not any then
			txt(scroll, "No open tables yet. Open one and tell your friends to join!", 13, KC.dim, { TextXAlignment = Enum.TextXAlignment.Center })
		end
		bigButton(body, "Open a new " .. (L.tab == "Cup" and "tournament" or "table"), "CreateLobby", 23, function()
			send("CreateLobby", { mode = L.tab, deck = L.deck })
		end)
	end

	function L.renderLobby(body, lobby)
		local me = mySlot(lobby)
		local host = lobby.hostId == player.UserId
		if lobby.started then
			txt(body, lobby.mode == "Cup" and "The tournament is on!" or "Match on! You'll be back at this table after it.", 17, KC.gold, { Font = TITLE, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 20 })
			if lobby.cup then
				button(body, "View bracket", Color3.fromRGB(90, 80, 140), function()
					L.bracket = { lobbyId = lobby.id, bracket = lobby.cup }
					L.showBracket()
				end, { Name = "ViewBracket", Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 21, TextScaled = false, TextSize = 19 })
				button(body, "Leave the tournament", Color3.fromRGB(110, 60, 70), function()
					L.left[lobby.id] = true
					send("LeaveLobby")
					L.render()
				end, { Name = "LeaveLobby", Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 22, TextScaled = false, TextSize = 17 })
			end
			return
		end
		heading(body, lobby.label .. " · host " .. lobby.host, 20)
		local scroll = make("Frame", { Name = "Slots", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 21 }, body)
		make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		for i = 1, lobby.size do
			if lobby.mode == "Team" and (i == 1 or i == 3) then
				txt(scroll, i == 1 and "Team A" or "Team B", 13, i == 1 and Color3.fromRGB(150, 220, 255) or Color3.fromRGB(255, 170, 150), { Font = TITLE, LayoutOrder = i * 10 - 1 })
			end
			local s = lobby.slots[i] or { kind = "empty" }
			local r = listRow(scroll, "Slot_" .. i, i * 10, i == me)
			local text
			if s.kind == "empty" then
				text = i .. ".  (empty seat)"
			else
				local deckName = s.deckName or (StarterDecks[s.deck] and StarterDecks[s.deck].name)
				text = i .. ".  " .. (s.kind == "bot" and "🤖 " or "") .. (inParty(s.userId) and "👥 " or "") .. s.name .. (deckName and ("  ·  " .. deckName) or "")
			end
			local nameLabel = make("TextLabel", { BackgroundTransparency = 1, Text = text, Font = BODY, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = s.kind == "empty" and KC.dim or WHITE, Size = UDim2.new(1, -162, 1, 0), Position = UDim2.fromOffset(12, 0) }, r)
			if s.kind ~= "empty" and s.deck then
				nameLabel.TextColor3 = familyColor(s.deckFamily or (StarterDecks[s.deck] and StarterDecks[s.deck].family) or "Any"):Lerp(WHITE, 0.4)
			end
			local buttons = make("Frame", { Size = UDim2.new(0, 150, 1, -10), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 }, r)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, buttons)
			if s.kind == "empty" then
				if host then
					small(buttons, "+ Bot", Color3.fromRGB(80, 110, 160), function()
						send("SetSlot", { slot = i, what = "addBot", value = "Medium" })
					end, 66, 1, "AddBot_" .. i)
				end
				if lobby.mode ~= "Duel" and lobby.mode ~= "Cup" then
					small(buttons, "Sit", Color3.fromRGB(70, 130, 220), function()
						send("JoinLobby", { id = lobby.id, deck = L.deck, slot = i })
					end, 52, 2, "Sit_" .. i)
				end
			elseif s.kind == "bot" and host then
				local nextDiff = DIFFS[(table.find(DIFFS, s.difficulty) or 2) % 3 + 1]
				small(buttons, (s.difficulty or "Medium"):sub(1, 3), Color3.fromRGB(240, 160, 50), function()
					send("SetSlot", { slot = i, what = "botDifficulty", value = nextDiff })
				end, 46, 1, "BotDiff_" .. i)
				local order = StarterDecks.Order
				local nextDeck = order[(table.find(order, s.deck) or 0) % #order + 1]
				small(buttons, "Deck", Color3.fromRGB(90, 80, 140), function()
					send("SetSlot", { slot = i, what = "botDeck", value = nextDeck })
				end, 52, 2, "BotDeck_" .. i)
				UIKit.closeButton(buttons, function()
					send("SetSlot", { slot = i, what = "removeBot" })
				end, { Name = "RemoveBot_" .. i, Size = UDim2.fromOffset(32, 32), LayoutOrder = 3 })
			elseif s.kind == "human" and host and i ~= me then
				small(buttons, "Kick", Color3.fromRGB(110, 60, 70), function()
					send("SetSlot", { slot = i, what = "kick" })
				end, 54, 1, "Kick_" .. i)
			end
		end
		if host then
			txt(body, "Empty seats get Medium bots when you start.", 12, KC.dim, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 22 })
			bigButton(body, "Start  ▶", "StartLobby", 23, function()
				send("StartLobby")
			end)
		else
			txt(body, "Waiting for " .. lobby.host .. " to start…", 15, KC.dim, { Font = TITLE, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 23 })
		end
		button(body, "Leave the table", Color3.fromRGB(110, 60, 70), function()
			send("LeaveLobby")
		end, { Name = "LeaveLobby", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 24, TextScaled = false, TextSize = 17 })
	end

	function L.render()
		local body = L.body
		if not (body and body.Parent and ctx.duelPanelOpen()) then
			L.body = nil
			return
		end
		local keep = body:FindFirstChild("DuelScroll")
		local scrollY = keep and keep.CanvasPosition.Y or 0
		clear(body)
		-- everything scrolls, so nothing is ever squeezed or cut off on a small screen
		local scroller = make("ScrollingFrame", {
			Name = "DuelScroll",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = KC.line,
		}, body)
		make("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6), PaddingTop = UDim.new(0, 2) }, scroller)
		make("UIListLayout", { Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, scroller)
		body = scroller
		local lobby = myLobby()
		if lobby then
			L.tab = lobby.mode
		end
		local items = {}
		for _, t in ipairs(TABS) do
			table.insert(items, { key = t.key, text = t.text })
		end
		segmented(body, items, L.tab, function(key)
			if myLobby() then
				LobbyScreen.toast("Leave your table first to switch.")
				return
			end
			if key ~= L.tab then
				L.tab = key
				L.render()
			end
		end, { name = "Modes", prefix = "Tab_", height = 42, textSize = 16, order = 1 })
		txt(body, MODE_TEXT[L.tab], 13, KC.dim, { Name = "ModeText", TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2 })
		-- Your deck: one of your own (built at the Deck Shelf, keys "s1", "s2"...) or a practice deck.
		local mine, decksLoaded = {}, false
		if ctx.myDecks then
			mine, decksLoaded = ctx.myDecks()
		end
		local function pickDeck(key)
			L.deck = key
			if ctx.prefs then
				ctx.prefs.set("Deck", key)
			end
			if myLobby() then
				send("SetDeck", { deck = key })
			end
			L.render()
		end
		local myInfo = nil
		if #mine > 0 then
			heading(body, "My decks", 3)
			local myGrid = deckGrid(body, "MyDecks", 3)
			for i, d in ipairs(mine) do
				local on = d.key == L.deck
				if on then
					myInfo = d
				end
				local hero = CardData.Heroes[d.hero]
				local sub = table.concat(d.themes or {}, " + ") .. " · " .. tostring(d.count) .. " cards"
				if not d.ok then
					sub = tostring(d.problem or "Not finished")
				elseif hero then
					sub = sub .. " · " .. hero.name
				end
				deckTile(myGrid, d.key, d.name, sub, d.family, on, d.ok, i, function()
					if not d.ok then
						LobbyScreen.toast("That deck isn't ready: " .. tostring(d.problem or "fix it at the Deck Shelf"))
						return
					end
					pickDeck(d.key)
				end)
			end
		end
		heading(body, "Practice decks", 3)
		local grid = deckGrid(body, "Decks", 3)
		for i, key in ipairs(StarterDecks.Order) do
			local deck = StarterDecks[key]
			local hero = CardData.Heroes[deck.hero]
			deckTile(grid, key, deck.name, deck.family .. (hero and (" · " .. hero.name) or ""), deck.family, key == L.deck, true, i, function()
				pickDeck(key)
			end)
		end
		if decksLoaded and not myInfo and not StarterDecks[L.deck] then
			L.deck = "Snack" -- (a saved deck that was deleted or broke since)
		end
		-- How the picked deck plays, in a few words.
		local info = infoCard(body, 4, "DeckInfo")
		if myInfo then
			local hero = CardData.Heroes[myInfo.hero]
			txt(info, myInfo.name, 16, familyColor(myInfo.family):Lerp(WHITE, 0.5), { Font = TITLE, LayoutOrder = 1 })
			txt(info, table.concat(myInfo.themes or {}, " + ") .. ", " .. tostring(myInfo.count) .. " cards" .. (hero and (", hero " .. hero.name) or "") .. ".", 13, KC.dim, { LayoutOrder = 2 })
		else
			local deck = StarterDecks[L.deck] or StarterDecks.Snack
			local rule = CardData.FamilyRules[deck.family]
			txt(info, (FAMILY_EMOJI[deck.family] or "") .. "  " .. deck.name .. "  ·  Hero " .. CardData.Heroes[deck.hero].name, 16, familyColor(deck.family):Lerp(WHITE, 0.5), { Font = TITLE, LayoutOrder = 1 })
			txt(info, (rule and (rule.text .. ".") or deck.blurb or ""), 13, KC.dim, { LayoutOrder = 2 })
		end
		if lobby then
			L.renderLobby(body, lobby)
		elseif L.tab == "Bot" then
			L.renderBot(body)
		else
			L.renderList(body)
		end
		task.defer(function()
			if scroller.Parent then
				scroller.CanvasPosition = Vector2.new(0, scrollY)
			end
		end)
	end

	-- Your saved deck and bot difficulty (see prefs in DeckWarsClient). The match background is
	-- picked at the Deck Shelf now (BackdropPicker) and saved with your cosmetics.
	function LobbyScreen.applyPrefs(prefs)
		local deck = prefs.get("Deck")
		if type(deck) == "string" and (StarterDecks[deck] or string.match(deck, "^s%d+$")) then
			L.deck = deck
		end
		local diff = prefs.get("Difficulty")
		if table.find(DIFFS, diff) then
			L.difficulty = diff
		end
		L.render()
	end

	function LobbyScreen.refresh()
		L.render()
	end

	function LobbyScreen.show(body)
		L.body = body
		send("RequestLobbies")
		L.render()
	end

	LobbyEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "lobbies" then
			L.lobbies = payload.list or {}
			-- Your tournament's bracket rides along with the list.
			for _, lobby in ipairs(L.lobbies) do
				if lobby.cup and mySlot(lobby) and not L.left[lobby.id] then
					L.bracket = { lobbyId = lobby.id, bracket = lobby.cup }
				end
			end
			L.render()
			if ui.bracketPanel.Visible then
				L.drawBracket()
			end
		elseif payload.kind == "bracket" then
			if not L.left[payload.lobbyId] then
				L.bracket = { lobbyId = payload.lobbyId, bracket = payload.bracket }
				-- Pop up when the tournament starts and when it has a champion; otherwise just keep
				-- it fresh (it also shows after each of your matches, see onMenu).
				local key = payload.lobbyId .. (payload.bracket.champion and ":done" or "")
				if ui.bracketPanel.Visible then
					L.drawBracket()
				elseif L.popped ~= key then
					L.popped = key
					L.showBracket()
				end
			end
		elseif payload.kind == "toast" then
			LobbyScreen.toast(tostring(payload.text))
		end
	end)

	LobbyScreen.L = L
	return LobbyScreen
end

return LobbyScreen

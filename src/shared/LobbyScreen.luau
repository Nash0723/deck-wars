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

	local function row(parent, height, order)
		local f = make("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, f)
		return f
	end

	local function small(parent, text, color, fn, width, order, name)
		return button(parent, text, color, fn, { Name = name or "Button", Size = UDim2.new(0, width or 70, 1, 0), LayoutOrder = order or 0, TextScaled = false, TextSize = 16 })
	end

	function L.renderBot(body)
		label(body, "Bot difficulty", { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 20 })
		local r = row(body, 38, 21)
		for i, d in ipairs(DIFFS) do
			small(r, d, d == L.difficulty and Color3.fromRGB(240, 160, 50) or Color3.fromRGB(80, 80, 110), function()
				L.difficulty = d
				if ctx.prefs then
					ctx.prefs.set("Difficulty", d)
				end
				L.render()
			end, 110, i, "Diff_" .. d)
		end
		button(body, "Sit down and play!", Color3.fromRGB(60, 180, 90), function()
			send("StartBotMatch", { deck = L.deck, difficulty = L.difficulty })
		end, { Name = "PlayBot", Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 22, TextScaled = false, TextSize = 24 })
		local win = ctx.WinGems
		if win then
			label(body, "Win: +" .. win.Easy .. " / +" .. win.Medium .. " / +" .. win.Hard .. " 💎", { Size = UDim2.new(1, 0, 0, 22), Font = BODY_FONT, TextColor3 = Color3.fromRGB(150, 220, 255), LayoutOrder = 23 })
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
			label(body, line, { Name = "PartyHint", Size = UDim2.new(1, 0, 0, 34), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(205, 175, 255), LayoutOrder = 19 })
		end
		button(body, "Open a new " .. (L.tab == "Cup" and "tournament" or "table"), Color3.fromRGB(60, 180, 90), function()
			send("CreateLobby", { mode = L.tab, deck = L.deck })
		end, { Name = "CreateLobby", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 20 })
		label(body, "Open tables", { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 21 })
		local scroll = make("ScrollingFrame", { Name = "LobbyList", Size = UDim2.new(1, 0, 0, 130), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, LayoutOrder = 22 }, body)
		make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
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
				local r = make("Frame", { Size = UDim2.new(1, -8, 0, 36), BackgroundColor3 = Color3.fromRGB(25, 22, 38), LayoutOrder = i }, scroll)
				corner(r, 8)
				label(r, lobby.host .. "'s table   " .. taken .. "/" .. lobby.size .. (lobby.started and "   (playing)" or ""), { Size = UDim2.new(1, -96, 1, -8), Position = UDim2.fromOffset(8, 4), Font = BODY_FONT, TextXAlignment = Enum.TextXAlignment.Left })
				if lobby.started and lobby.cup then
					button(r, "Bracket", Color3.fromRGB(90, 80, 140), function()
						L.bracket = { lobbyId = lobby.id, bracket = lobby.cup }
						L.showBracket()
					end, { Size = UDim2.fromOffset(84, 28), Position = UDim2.new(1, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
				elseif not lobby.started then
					button(r, "Join", Color3.fromRGB(70, 130, 220), function()
						send("JoinLobby", { id = lobby.id, deck = L.deck })
					end, { Name = "Join_" .. lobby.id, Size = UDim2.fromOffset(84, 28), Position = UDim2.new(1, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
				end
			end
		end
		if not any then
			label(scroll, "No open tables yet. Open one and tell your friends to join!", { Size = UDim2.new(1, -8, 0, 44), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(200, 200, 220) })
		end
	end

	function L.renderLobby(body, lobby)
		local me = mySlot(lobby)
		local host = lobby.hostId == player.UserId
		if lobby.started then
			label(body, lobby.mode == "Cup" and "The tournament is on!" or "Match on! You'll be back at this table after it.", { Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextColor3 = Color3.fromRGB(255, 220, 90), LayoutOrder = 20 })
			if lobby.cup then
				button(body, "View bracket", Color3.fromRGB(90, 80, 140), function()
					L.bracket = { lobbyId = lobby.id, bracket = lobby.cup }
					L.showBracket()
				end, { Name = "ViewBracket", Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 21 })
				button(body, "Leave the tournament", Color3.fromRGB(110, 60, 70), function()
					L.left[lobby.id] = true
					send("LeaveLobby")
					L.render()
				end, { Name = "LeaveLobby", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 22 })
			end
			return
		end
		label(body, lobby.label .. " · host " .. lobby.host, { Size = UDim2.new(1, 0, 0, 22), Font = BODY_FONT, TextColor3 = Color3.fromRGB(255, 220, 140), LayoutOrder = 20 })
		local scroll = make("ScrollingFrame", { Name = "Slots", Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, LayoutOrder = 21 }, body)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		for i = 1, lobby.size do
			if lobby.mode == "Team" and (i == 1 or i == 3) then
				label(scroll, i == 1 and "Team A" or "Team B", { Size = UDim2.new(1, -8, 0, 18), Font = BODY_FONT, TextColor3 = i == 1 and Color3.fromRGB(150, 220, 255) or Color3.fromRGB(255, 170, 150), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i * 10 - 1 })
			end
			local s = lobby.slots[i] or { kind = "empty" }
			local r = make("Frame", { Name = "Slot_" .. i, Size = UDim2.new(1, -8, 0, 32), BackgroundColor3 = i == me and Color3.fromRGB(35, 60, 45) or Color3.fromRGB(25, 22, 38), LayoutOrder = i * 10 }, scroll)
			corner(r, 8)
			local text
			if s.kind == "empty" then
				text = i .. ". (empty)"
			else
				local deckName = s.deckName or (StarterDecks[s.deck] and StarterDecks[s.deck].name)
				text = i .. ". " .. (s.kind == "bot" and "🤖 " or "") .. (inParty(s.userId) and "👥 " or "") .. s.name .. (deckName and (" · " .. deckName) or "")
			end
			local nameLabel = label(r, text, { Size = UDim2.new(1, -150, 1, -8), Position = UDim2.fromOffset(8, 4), Font = BODY_FONT, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = s.kind == "empty" and Color3.fromRGB(150, 145, 170) or WHITE })
			if s.kind ~= "empty" and s.deck then
				nameLabel.TextColor3 = familyColor(s.deckFamily or (StarterDecks[s.deck] and StarterDecks[s.deck].family) or "Any"):Lerp(WHITE, 0.4)
			end
			local buttons = make("Frame", { Size = UDim2.new(0, 142, 1, -6), Position = UDim2.new(1, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 }, r)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4) }, buttons)
			if s.kind == "empty" then
				if host then
					small(buttons, "+ Bot", Color3.fromRGB(80, 110, 160), function()
						send("SetSlot", { slot = i, what = "addBot", value = "Medium" })
					end, 66, 1, "AddBot_" .. i)
				end
				if lobby.mode ~= "Duel" and lobby.mode ~= "Cup" then
					small(buttons, "Sit", Color3.fromRGB(70, 130, 220), function()
						send("JoinLobby", { id = lobby.id, deck = L.deck, slot = i })
					end, 50, 2, "Sit_" .. i)
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
				end, 50, 2, "BotDeck_" .. i)
				small(buttons, "✕", Color3.fromRGB(110, 60, 70), function()
					send("SetSlot", { slot = i, what = "removeBot" })
				end, 30, 3, "RemoveBot_" .. i)
			elseif s.kind == "human" and host and i ~= me then
				small(buttons, "Kick", Color3.fromRGB(110, 60, 70), function()
					send("SetSlot", { slot = i, what = "kick" })
				end, 50, 1, "Kick_" .. i)
			end
		end
		local r = row(body, 44, 22)
		if host then
			small(r, "Start ▶", Color3.fromRGB(60, 180, 90), function()
				send("StartLobby")
			end, 200, 1, "StartLobby")
		else
			label(r, "Waiting for " .. lobby.host .. " to start", { Size = UDim2.new(0, 200, 1, 0), Font = BODY_FONT, TextColor3 = Color3.fromRGB(200, 200, 220), LayoutOrder = 1 })
		end
		small(r, "Leave", Color3.fromRGB(110, 60, 70), function()
			send("LeaveLobby")
		end, 120, 2, "LeaveLobby")
		label(body, host and "Empty seats get Medium bots when you start." or "", { Size = UDim2.new(1, 0, 0, 18), Font = BODY_FONT, TextColor3 = Color3.fromRGB(180, 180, 200), LayoutOrder = 23 })
	end

	-- The background you'll play in (see Backdrops): only on your screen, so it can be picked any time.
	function L.renderBackdrop(body)
		local BD = ctx.backdrops
		if not BD then
			return
		end
		local list = BD.List
		local index = 1
		for i, b in ipairs(list) do
			if b.key == BD.choice then
				index = i
			end
		end
		local function choose(i)
			local b = list[(i - 1) % #list + 1]
			BD.choice = b.key
			if ctx.prefs then
				ctx.prefs.set("Backdrop", b.key)
			end
			LobbyScreen.toast(b.emoji .. " " .. b.name .. ": " .. b.blurb)
			L.render()
		end
		local r = row(body, 30, 5)
		r.Name = "Backdrop"
		label(r, "Background", { Size = UDim2.new(0, 84, 1, 0), Font = BODY_FONT, TextColor3 = Color3.fromRGB(230, 225, 240), LayoutOrder = 0 })
		small(r, "◀", Color3.fromRGB(70, 60, 110), function()
			choose(index - 1)
		end, 34, 1, "BackdropPrev")
		local current = list[index]
		local b = small(r, "", Color3.fromRGB(255, 255, 255), function()
			choose(index + 1)
		end, 196, 2, "BackdropName")
		-- The button shows the world's colours, with its name on top.
		local swatch = make("Frame", { Name = "Swatch", Size = UDim2.new(1, 16, 1, 8), Position = UDim2.fromOffset(-8, -4), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = b.ZIndex }, b)
		corner(swatch, 10)
		make("UIGradient", { Color = ColorSequence.new(current.colors[1], current.colors[2]), Rotation = 0 }, swatch)
		label(b, current.emoji .. " " .. current.name, { Name = "BackdropText", TextStrokeTransparency = 0.25, ZIndex = b.ZIndex + 1 })
		small(r, "▶", Color3.fromRGB(70, 60, 110), function()
			choose(index + 1)
		end, 34, 3, "BackdropNext")
	end

	function L.render()
		local body = L.body
		if not (body and body.Parent and ctx.duelPanelOpen()) then
			L.body = nil
			return
		end
		clear(body)
		make("UIListLayout", { Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, body)
		local lobby = myLobby()
		if lobby then
			L.tab = lobby.mode
		end
		local tabs = row(body, 34, 1)
		for i, t in ipairs(TABS) do
			local on = L.tab == t.key
			small(tabs, t.text, on and Color3.fromRGB(240, 160, 50) or Color3.fromRGB(70, 60, 110), function()
				if myLobby() then
					LobbyScreen.toast("Leave your table first to switch.")
					return
				end
				L.tab = t.key
				L.render()
			end, 84, i, "Tab_" .. t.key)
		end
		label(body, MODE_TEXT[L.tab], { Size = UDim2.new(1, 0, 0, 34), Font = BODY_FONT, TextWrapped = true, TextColor3 = Color3.fromRGB(230, 225, 240), LayoutOrder = 2 })
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
			label(body, "My decks", { Size = UDim2.new(1, 0, 0, 18), Font = BODY_FONT, TextColor3 = Color3.fromRGB(255, 220, 140), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 })
			local myGrid = make("Frame", { Name = "MyDecks", Size = UDim2.new(1, 0, 0, math.ceil(#mine / 3) * 36 - 4), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
			make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -4, 0, 32), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }, myGrid)
			for i, d in ipairs(mine) do
				local fam = familyColor(d.family)
				local on = d.key == L.deck
				if on then
					myInfo = d
				end
				local b = button(myGrid, (d.ok and "" or "⚠ ") .. d.name, on and fam or fam:Lerp(Color3.fromRGB(40, 35, 60), d.ok and 0.65 or 0.85), function()
					if not d.ok then
						LobbyScreen.toast("That deck isn't ready: " .. tostring(d.problem or "fix it at the Deck Shelf"))
						return
					end
					pickDeck(d.key)
				end, { Name = "Deck_" .. d.key, LayoutOrder = i, TextScaled = false, TextSize = 14 })
				b.TextColor3 = on and BLACK or WHITE
			end
			label(body, "Practice decks", { Size = UDim2.new(1, 0, 0, 18), Font = BODY_FONT, TextColor3 = Color3.fromRGB(200, 195, 220), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 3 })
		end
		local grid = make("Frame", { Name = "Decks", Size = UDim2.new(1, 0, 0, 2 * 32 + 4), BackgroundTransparency = 1, LayoutOrder = 3 }, body)
		make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -4, 0, 32), CellPadding = UDim2.fromOffset(6, 4), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		for i, key in ipairs(StarterDecks.Order) do
			local fam = familyColor(StarterDecks[key].family)
			local on = key == L.deck
			local b = button(grid, StarterDecks[key].name, on and fam or fam:Lerp(Color3.fromRGB(40, 35, 60), 0.65), function()
				pickDeck(key)
			end, { Name = "Deck_" .. key, LayoutOrder = i, TextScaled = false, TextSize = 14 })
			b.TextColor3 = on and BLACK or WHITE
		end
		if decksLoaded and not myInfo and not StarterDecks[L.deck] then
			L.deck = "Snack" -- (a saved deck that was deleted or broke since)
		end
		if myInfo then
			local hero = CardData.Heroes[myInfo.hero]
			label(body, "Your deck: " .. table.concat(myInfo.themes or {}, " + ") .. ", " .. tostring(myInfo.count) .. " cards" .. (hero and (", hero " .. hero.name) or "") .. ".", { Name = "DeckInfo", Size = UDim2.new(1, 0, 0, 34), Font = BODY_FONT, TextWrapped = true, TextColor3 = familyColor(myInfo.family):Lerp(WHITE, 0.55), LayoutOrder = 4 })
		else
			local deck = StarterDecks[L.deck] or StarterDecks.Snack
			local rule = CardData.FamilyRules[deck.family]
			-- How the deck plays, in a few words.
			label(body, (rule and (rule.text .. ". ") or "") .. "Hero: " .. CardData.Heroes[deck.hero].name .. ".", { Name = "DeckInfo", Size = UDim2.new(1, 0, 0, 34), Font = BODY_FONT, TextWrapped = true, TextColor3 = familyColor(deck.family):Lerp(WHITE, 0.55), LayoutOrder = 4 })
		end
		L.renderBackdrop(body)
		if lobby then
			L.renderLobby(body, lobby)
		elseif L.tab == "Bot" then
			L.renderBot(body)
		else
			L.renderList(body)
		end
	end

	-- Your saved deck, bot difficulty and background (see prefs in DeckWarsClient).
	function LobbyScreen.applyPrefs(prefs)
		local deck = prefs.get("Deck")
		if type(deck) == "string" and (StarterDecks[deck] or string.match(deck, "^s%d+$")) then
			L.deck = deck
		end
		local diff = prefs.get("Difficulty")
		if table.find(DIFFS, diff) then
			L.difficulty = diff
		end
		local bd = prefs.get("Backdrop")
		if ctx.backdrops and type(bd) == "string" and ctx.backdrops.ByKey[bd] then
			ctx.backdrops.choice = bd
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

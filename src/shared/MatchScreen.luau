-- The match screen for the lane rules: the lanes on the Duel Table, the creatures and buildings
-- in them, the heroes, your hand, the HUD, and the playback of everything the server sends.
-- Client only. DeckWarsClient calls MatchScreen.init(ctx) once with its helpers (GUI makers,
-- cards, models, camera) and then forwards clicks and frames to it.
--
-- Your team always sits on the near side of the table (toward your chair). Lane 1 is on your left,
-- and enemy lane i faces your lane i. In 1v1 each side has 4 lanes; in 2v2 it's 8 (your teammate's
-- 4 lanes next to yours).

local MatchScreen = {}

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local CardData = require(Shared:WaitForChild("CardData"))
local CreatureBuilder = require(Shared:WaitForChild("CreatureBuilder"))
local Progression = require(Shared:WaitForChild("Progression"))

local ABORT = "MatchScreenAbort" -- thrown to stop playback when the match ended meanwhile

function MatchScreen.init(ctx)
	local S = {} -- state
	local F = {} -- functions (kept in a table so this function doesn't run out of local slots)
	local ui = ctx.ui
	local make, corner, label, button, panel = ctx.make, ctx.corner, ctx.label, ctx.button, ctx.panel
	local WHITE, BLACK, FONT, BODY_FONT = ctx.WHITE, ctx.BLACK, ctx.FONT, ctx.BODY_FONT
	local PACE = ctx.PACE
	local BASE_PACE = ctx.PACE
	local FAST_PACE = 0.6 -- "⏩ Speed: Fast" plays everything at this pace (times the normal one)
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local MatchEvent = Remotes:WaitForChild("MatchEvent")
	local MatchAction = Remotes:WaitForChild("MatchAction")
	local MenuAction = Remotes:WaitForChild("MenuAction")
	local player = ctx.player
	local camera = ctx.camera
	local duelTable = ctx.duelTable
	local board = ctx.board

	S.view = nil
	S.queue = {}
	S.processing = false
	S.matchId = 0
	S.playing = -1
	S.busy = false
	S.turnEndsAt = 0
	S.units = {} -- [uid] = entry
	S.heroes = {} -- [seat] = entry
	S.pads = {} -- [team][lane] = { creature = part, building = part, strip = part }
	S.scrap = {} -- [team][lane] = { parts }
	S.pick = nil -- what you're aiming right now
	S.logLines = {}
	S.layout = nil

	local function rgb(t)
		return Color3.fromRGB(t[1], t[2], t[3])
	end
	local function familyColor(f)
		return rgb(CardData.FamilyColors[f] or CardData.FamilyColors.Any)
	end
	local function cardName(id)
		local c = CardData.Cards[id]
		return c and c.name or tostring(id)
	end
	local function clock()
		return ctx.getClock()
	end

	---------------------------------------------------------------------------
	-- HUD
	---------------------------------------------------------------------------

	ui.matchUI = make("Frame", { Name = "MatchUI", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, ctx.gui)
	ui.flashFrame = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 1, ZIndex = 50 }, ctx.gui)
	ui.vignette = make("ImageLabel", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/ui/VignetteOverlay.png",
		ImageTransparency = 0.35,
		ZIndex = 0,
		Visible = false,
	}, ctx.gui)

	local function hpBar(parent, pos, size, fillColor, backColor)
		local back = make("Frame", { Size = size, Position = pos, BackgroundColor3 = backColor }, parent)
		corner(back, 8)
		local trail = make("Frame", { Name = "Trail", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 226, 165), ZIndex = 2 }, back)
		corner(trail, 8)
		local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = fillColor, ZIndex = 3 }, back)
		corner(fill, 8)
		local text = label(back, "25", { ZIndex = 4, TextScaled = false, TextSize = math.max(12, math.floor(size.Y.Offset * 0.58)), TextStrokeTransparency = 0.6 })
		make("UIScale", { Scale = 1 }, back)
		return { back = back, fill = fill, trail = trail, text = text, value = nil }
	end

	-- The other side, top middle: name, cards in hand and magic, and hit points.
	ui.enemyBar = panel(ui.matchUI, UDim2.fromOffset(440, 54), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	ui.enemyNames = label(ui.enemyBar, "Opponent", { Size = UDim2.new(0.54, -22, 0, 20), Position = UDim2.fromOffset(14, 8), TextScaled = false, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	ui.enemyInfo = label(ui.enemyBar, "", { Size = UDim2.new(0.54, -22, 0, 16), Position = UDim2.fromOffset(14, 30), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = Color3.fromRGB(190, 185, 215), TextXAlignment = Enum.TextXAlignment.Left })
	ui.enemyHp = hpBar(ui.enemyBar, UDim2.new(0.54, 0, 0, 13), UDim2.new(0.46, -14, 0, 28), Color3.fromRGB(225, 80, 90), Color3.fromRGB(55, 22, 32))

	-- Your side, bottom left: hit points, magic and your hero's Big Move. (Your name is on your hero.)
	ui.myBar = panel(ui.matchUI, UDim2.fromOffset(264, 122), UDim2.new(0, 14, 1, -14), Vector2.new(0, 1))
	ui.myNames = label(ui.myBar, "You", { Size = UDim2.new(1, -24, 0, 1), Visible = false })
	ui.myHp = hpBar(ui.myBar, UDim2.fromOffset(12, 12), UDim2.new(1, -24, 0, 30), Color3.fromRGB(80, 200, 110), Color3.fromRGB(20, 50, 30))
	ui.magicText = label(ui.myBar, "✨ 0/0", { Size = UDim2.fromOffset(70, 22), Position = UDim2.fromOffset(12, 48), TextScaled = false, TextSize = 17, TextColor3 = Color3.fromRGB(150, 210, 255), TextXAlignment = Enum.TextXAlignment.Left })
	ui.magicGems = make("Frame", { Size = UDim2.new(1, -150, 0, 13), Position = UDim2.fromOffset(86, 53), BackgroundTransparency = 1 }, ui.myBar)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5) }, ui.magicGems)
	ui.deckText = label(ui.myBar, "", { Name = "DeckCount", Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, -12, 0, 50), AnchorPoint = Vector2.new(1, 0), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = Color3.fromRGB(170, 165, 195), TextXAlignment = Enum.TextXAlignment.Right })
	ui.bigMoveButton = button(ui.myBar, "Big Move", Color3.fromRGB(110, 80, 160), nil, { Name = "BigMoveButton", Size = UDim2.new(1, -24, 0, 36), Position = UDim2.fromOffset(12, 76), TextScaled = false, TextSize = 19 })

	-- BATTLE ends your turn (bottom right), with whose turn it is just above it.
	ui.battleButton = button(ui.matchUI, "⚔ BATTLE!", Color3.fromRGB(205, 80, 60), nil, { Name = "BattleButton", Size = UDim2.fromOffset(190, 66), Position = UDim2.new(1, -18, 1, -18), AnchorPoint = Vector2.new(1, 1), TextScaled = false, TextSize = 30 })
	ui.turnText = label(ui.matchUI, "", { Size = UDim2.fromOffset(320, 26), Position = UDim2.new(1, -20, 1, -90), AnchorPoint = Vector2.new(1, 1), TextScaled = false, TextSize = 21, TextStrokeTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Right })
	-- The seconds left only show near the end of a turn.
	ui.timerText = label(ui.matchUI, "", { Size = UDim2.fromOffset(200, 20), Position = UDim2.new(1, -20, 1, -118), AnchorPoint = Vector2.new(1, 1), Font = BODY_FONT, TextScaled = false, TextSize = 16, TextStrokeTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Right })
	ui.matchLabel = label(ui.matchUI, "", { Size = UDim2.fromOffset(420, 18), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextColor3 = Color3.fromRGB(255, 220, 140), TextStrokeTransparency = 0.6 })

	-- Everything else waits behind the ⚙ button (top right): how to play, speed, sound, the match
	-- log, and leaving.
	ui.menuButton = button(ui.matchUI, "⚙", Color3.fromRGB(60, 56, 84), function()
		F.toggleMenu()
	end, { Name = "MenuButton", Size = UDim2.fromOffset(46, 42), Position = UDim2.new(1, -14, 0, 12), AnchorPoint = Vector2.new(1, 0) })
	ui.menuPanel = panel(ui.matchUI, UDim2.fromOffset(240, 0), UDim2.new(1, -14, 0, 62), Vector2.new(1, 0))
	ui.menuPanel.Name = "MatchMenu"
	ui.menuPanel.AutomaticSize = Enum.AutomaticSize.Y
	ui.menuPanel.Visible = false
	ui.menuPanel.ZIndex = 35
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, ui.menuPanel)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ui.menuPanel)
	local function menuItem(text, order, color, fn, name)
		return button(ui.menuPanel, text, color or Color3.fromRGB(70, 66, 100), fn, { Name = name, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = order })
	end
	ui.helpButton = menuItem("❓ How to play", 1, nil, function()
		ui.menuPanel.Visible = false
		F.toggleHelp()
	end, "HelpButton")
	ui.speedButton = menuItem("⏩ Speed: Normal", 2, nil, function()
		F.setFast(not S.fast, true)
	end, "SpeedButton")
	ui.soundButton = menuItem("🔊 Sound: On", 3, nil, function()
		F.setSound(not S.soundOn, true)
	end, "SoundButton")
	ui.logButton = menuItem("📜 Match log: Off", 4, nil, function()
		F.setLog(not ui.logFrame.Visible)
	end, "LogButton")
	-- Leaving a match that's still on forfeits it, so the first click only asks.
	ui.leaveButton = menuItem("Leave match", 5, Color3.fromRGB(120, 60, 70), function()
		F.pressLeave()
	end, "LeaveButton")

	-- Your hand, bottom middle (between your bar and BATTLE).
	-- The whole card shows (cost, picture, attack and health); hover one for its full text.
	ui.handFrame = make("Frame", { Name = "Hand", Size = UDim2.new(1, -500, 0, 152), Position = UDim2.new(0.5, 38, 1, -8), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 }, ui.matchUI)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, -10), SortOrder = Enum.SortOrder.LayoutOrder }, ui.handFrame)

	-- One line that says what to do next, for a player's first few matches.
	ui.coach = label(ui.matchUI, "", { Name = "CoachText", TextScaled = false, TextSize = 16, Size = UDim2.fromOffset(500, 30), Position = UDim2.new(0.5, 38, 1, -196), AnchorPoint = Vector2.new(0.5, 1), Font = BODY_FONT, TextColor3 = Color3.fromRGB(235, 232, 245), BackgroundColor3 = Color3.fromRGB(22, 18, 32), BackgroundTransparency = 0.35, Visible = false })
	corner(ui.coach, 10)
	make("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, ui.coach)
	-- Short messages ("Not enough magic") show for a moment under the other side's bar.
	ui.toast = label(ui.matchUI, "", { Name = "Toast", Size = UDim2.fromOffset(520, 32), Position = UDim2.new(0.5, 0, 0, 94), AnchorPoint = Vector2.new(0.5, 0), Font = BODY_FONT, TextScaled = false, TextSize = 16, TextWrapped = true, BackgroundColor3 = Color3.fromRGB(22, 18, 32), BackgroundTransparency = 0.25, Visible = false, ZIndex = 12 })
	corner(ui.toast, 10)
	make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, ui.toast)

	-- The match log: every play, Spark and hit in words (off unless you turn it on in the ⚙ menu).
	ui.logFrame = make("Frame", { Name = "MatchLog", Size = UDim2.fromOffset(330, 200), Position = UDim2.new(1, -14, 0, 62), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = Color3.fromRGB(20, 16, 30), BackgroundTransparency = 0.45, Visible = false }, ui.matchUI)
	corner(ui.logFrame, 10)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, ui.logFrame)
	make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }, ui.logFrame)

	-- Choices (Spark, Skip, Cancel), just above your hand.
	ui.promptBar = panel(ui.matchUI, UDim2.fromOffset(560, 100), UDim2.new(0.5, 38, 1, -192), Vector2.new(0.5, 1))
	ui.promptBar.Name = "PromptBar"
	ui.promptBar.Visible = false
	ui.promptText = label(ui.promptBar, "", { Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 8) })
	ui.promptOptions = make("Frame", { Name = "Options", Size = UDim2.new(1, -24, 1, -50), Position = UDim2.fromOffset(12, 44), BackgroundTransparency = 1 }, ui.promptBar)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) }, ui.promptOptions)

	ui.bannerText = label(ui.matchUI, "", { Size = UDim2.fromOffset(520, 50), Position = UDim2.fromScale(0.5, 0.32), AnchorPoint = Vector2.new(0.5, 0.5), TextScaled = false, TextSize = 38, TextColor3 = Color3.fromRGB(255, 220, 90), TextStrokeColor3 = Color3.fromRGB(30, 20, 14), TextStrokeTransparency = 0.35, Visible = false, ZIndex = 10 })
	ui.bannerScale = make("UIScale", { Scale = 1 }, ui.bannerText)
	ui.popupHolder = make("Frame", { Size = UDim2.fromOffset(200, 280), Position = UDim2.fromScale(0.5, 0.45), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 8 }, ui.matchUI)
	ui.previewHolder = make("Frame", { Size = UDim2.fromOffset(220, 308), Position = UDim2.new(0, 16, 0.4, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1, Visible = false }, ui.matchUI)
	ui.rollText = label(ui.matchUI, "", { Size = UDim2.fromOffset(520, 40), Position = UDim2.fromScale(0.5, 0.27), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = Color3.fromRGB(255, 230, 120), TextStrokeTransparency = 0, Visible = false, ZIndex = 12 })
	ui.tip = label(ui.matchUI, "", { Size = UDim2.fromOffset(300, 26), Font = BODY_FONT, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 0.25, BackgroundColor3 = Color3.fromRGB(20, 16, 30), Visible = false, ZIndex = 20 })
	corner(ui.tip, 6)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, ui.tip)

	-- The result: who won, how it went, what you earned (Gems, XP, quests) and what next.
	ui.resultPanel = panel(ui.matchUI, UDim2.fromOffset(520, 0), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	ui.resultPanel.Name = "ResultPanel"
	ui.resultPanel.AutomaticSize = Enum.AutomaticSize.Y
	ui.resultPanel.Visible = false
	ui.resultPanel.ZIndex = 30
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, ui.resultPanel)
	make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, ui.resultPanel)
	ui.resultTitle = label(ui.resultPanel, "", { Size = UDim2.new(1, 0, 0, 48), TextScaled = false, TextSize = 42, TextColor3 = Color3.fromRGB(255, 220, 90), TextStrokeColor3 = Color3.fromRGB(30, 20, 14), TextStrokeTransparency = 0.5, LayoutOrder = 1, ZIndex = 31 })
	ui.resultText = label(ui.resultPanel, "", { Size = UDim2.new(1, 0, 0, 22), Font = BODY_FONT, TextScaled = false, TextSize = 16, TextWrapped = true, LayoutOrder = 2, ZIndex = 31 })
	ui.resultStats = label(ui.resultPanel, "", { Name = "ResultStats", Size = UDim2.new(1, 0, 0, 18), Font = BODY_FONT, TextScaled = false, TextSize = 13, TextColor3 = Color3.fromRGB(190, 200, 235), LayoutOrder = 3, ZIndex = 31 })
	ui.resultRewards = make("Frame", { Name = "Rewards", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4, ZIndex = 31 }, ui.resultPanel)
	make("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, ui.resultRewards)
	ui.resultButtons = make("Frame", { Name = "ResultButtons", Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, LayoutOrder = 5, ZIndex = 31 }, ui.resultPanel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, ui.resultButtons)
	ui.resultCountdown = label(ui.resultPanel, "", { Name = "ResultCountdown", Size = UDim2.new(1, 0, 0, 20), Font = BODY_FONT, TextColor3 = Color3.fromRGB(170, 165, 195), LayoutOrder = 6, ZIndex = 31 })

	-- How to play, on one short screen (⚙ > How to play, or the ? key).
	ui.helpPanel = panel(ui.matchUI, UDim2.fromOffset(600, 440), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	ui.helpPanel.Name = "HelpPanel"
	ui.helpPanel.Visible = false
	ui.helpPanel.ZIndex = 40
	local helpTitle = label(ui.helpPanel, "How to play", { Size = UDim2.new(1, -150, 0, 32), Position = UDim2.fromOffset(18, 14), TextScaled = false, TextSize = 26, TextColor3 = Color3.fromRGB(255, 220, 90), TextXAlignment = Enum.TextXAlignment.Left })
	if ctx.headingStyle then
		helpTitle.TextColor3 = WHITE
		ctx.headingStyle(helpTitle)
	end
	button(ui.helpPanel, "Got it!", Color3.fromRGB(60, 160, 90), function()
		ui.helpPanel.Visible = false
	end, { Name = "CloseHelp", Size = UDim2.fromOffset(120, 38), Position = UDim2.new(1, -14, 0, 12), AnchorPoint = Vector2.new(1, 0) })
	do
		local scroll = make("ScrollingFrame", { Name = "HelpText", Size = UDim2.new(1, -32, 1, -66), Position = UDim2.fromOffset(16, 56), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6 }, ui.helpPanel)
		local lines = {
			"<b>1.</b> Every turn you get ✨ magic (" .. CardData.StartMagic .. " at first, 1 more each turn, up to " .. CardData.MaxMagic .. ") and draw a card.",
			"",
			"<b>2.</b> Drag a card with a <font color=\"#6eff82\">green outline</font> onto a glowing spot (or click it, then the spot). Each lane has a <b>Front</b> and a <b>Back</b> spot for creatures and a building slot behind them that helps both.",
			"",
			"<b>3.</b> Click one of your creatures to 🌀 <b>Spark</b> it (the purple ability on its card) or ↕ <b>Shift</b> it to the other row for " .. (CardData.ShiftCost or 1) .. " ✨. Either way it skips its attack this turn.",
			"",
			"<b>4.</b> Press <b>⚔ BATTLE!</b> to end your turn. Front creatures hit the first enemy in their lane (Front first, then Back), or the hero if the lane is empty. Back creatures wait, unless they're <b>Ranged</b>, and step up when the Front spot is free.",
			"",
			"<b>Good to know</b>",
			"• New creatures wait a turn before they attack (💤), unless they have Zoom.",
			"• A creature on its own landscape gets +1 attack (already in its number).",
			"• <b>Overkill</b>: damage left over after a creature falls rolls on to the next one in the lane, then the hero.",
			"• Deal " .. CardData.BigMoveCharge .. " damage and your hero's ★ <b>Big Move</b> is ready (once a match).",
			"• Hover anything to see what it does.",
			"",
			"You win when the other side's hit points reach 0.",
			"",
			"<font color=\"#b4aed2\">Keys: 1-9 pick a card · Space BATTLE · F Spark · B Big Move · Esc cancel · ? this screen · R play again</font>",
		}
		make("TextLabel", {
			Name = "Body",
			Size = UDim2.new(1, -12, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			RichText = true,
			TextWrapped = true,
			TextScaled = false,
			TextSize = 19,
			Font = BODY_FONT,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = table.concat(lines, "\n"),
		}, scroll)
	end

	function F.log(text, color)
		local l = label(ui.logFrame, text, { Size = UDim2.new(1, 0, 0, 18), Font = BODY_FONT, TextScaled = false, TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color or WHITE, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = #S.logLines + 1 })
		table.insert(S.logLines, l)
		while #S.logLines > 9 do
			table.remove(S.logLines, 1):Destroy()
		end
	end

	-- A short message under the other side's bar for a moment (and in the log).
	local toastToken = nil
	function F.notice(text, color)
		F.log(text, color)
		local token = {}
		toastToken = token
		ui.toast.Text = text
		ui.toast.TextColor3 = color or WHITE
		ui.toast.Visible = true
		task.delay(2.6, function()
			if toastToken == token then
				ui.toast.Visible = false
			end
		end)
	end

	-- Sounds: quiet, and only for things that happen (a card lands, a hit, a pop, your turn).
	-- ⚙ > Sound turns them off.
	local TableSounds = nil
	pcall(function()
		TableSounds = require(Shared:WaitForChild("TableSounds", 5))
	end)
	S.soundOn = true
	local SOUND_VOLUME = 0.5
	function F.sound(name, opts)
		if not S.soundOn or not TableSounds then
			return
		end
		opts = opts or {}
		local scale = ctx.sfxScale and ctx.sfxScale() or 1 -- the Sound effects volume in Settings
		if scale <= 0 then
			return
		end
		pcall(TableSounds.play, name, { volume = (opts.volume or 1) * SOUND_VOLUME * scale, pitch = opts.pitch })
	end

	local bannerToken = nil
	function F.banner(text, seconds, color)
		local token = {}
		bannerToken = token
		ui.bannerText.Text = text
		ui.bannerText.TextColor3 = color or Color3.fromRGB(255, 220, 90)
		ui.bannerText.TextTransparency = 0
		ui.bannerText.TextStrokeTransparency = 0.35
		ui.bannerText.Visible = true
		ui.bannerScale.Scale = 0.6
		TweenService:Create(ui.bannerScale, TweenInfo.new(0.35 * PACE, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay((seconds or 1.3) * PACE, function()
			if bannerToken ~= token then
				return
			end
			TweenService:Create(ui.bannerText, TweenInfo.new(0.3 * PACE), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(0.32 * PACE, function()
				if bannerToken == token then
					ui.bannerText.Visible = false
				end
			end)
		end)
	end

	function F.flash(color, strength, seconds)
		ui.flashFrame.BackgroundColor3 = color
		ui.flashFrame.BackgroundTransparency = 1 - strength
		TweenService:Create(ui.flashFrame, TweenInfo.new((seconds or 0.5) * PACE), { BackgroundTransparency = 1 }):Play()
	end

	function F.setBar(bar, value, max)
		local fraction = math.clamp(value / math.max(1, max), 0, 1)
		bar.text.Text = tostring(math.max(0, value)) .. " / " .. tostring(max)
		local before = bar.fill.Size.X.Scale
		TweenService:Create(bar.fill, TweenInfo.new(0.5 * PACE, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(fraction, 1) }):Play()
		if fraction < before - 0.001 then
			TweenService:Create(bar.trail, TweenInfo.new(0.7 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.45 * PACE), { Size = UDim2.fromScale(fraction, 1) }):Play()
			local pop = bar.back:FindFirstChildOfClass("UIScale")
			if pop then
				pop.Scale = 1.08
				TweenService:Create(pop, TweenInfo.new(0.35 * PACE, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
		else
			bar.trail.Size = UDim2.fromScale(fraction, 1)
		end
	end

	local popupToken = nil
	function F.popup(cardId, seconds, fromTop)
		ui.popupHolder:ClearAllChildren()
		local token = {}
		popupToken = token
		local card = ctx.makeCard(ui.popupHolder, cardId, UDim2.fromScale(1, 1))
		ctx.cardLife.wake(card, true)
		card.Position = UDim2.fromScale(0, fromTop and -1.6 or 1.6)
		TweenService:Create(card, TweenInfo.new(0.4 * PACE, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0, 0) }):Play()
		task.delay((seconds or 1.4) * PACE, function()
			if popupToken ~= token then
				return
			end
			TweenService:Create(card, TweenInfo.new(0.25 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0.4, 0.6), Size = UDim2.fromScale(0.15, 0.15) }):Play()
			task.delay(0.27 * PACE, function()
				if popupToken == token then
					ui.popupHolder:ClearAllChildren()
				end
			end)
		end)
	end

	S.previewKey = nil
	function F.preview(cardId, cost)
		local key = cardId .. ":" .. tostring(cost)
		if S.previewKey ~= key then
			ui.previewHolder:ClearAllChildren()
			ctx.cardLife.wake(ctx.makeCard(ui.previewHolder, cardId, UDim2.fromScale(1, 1), cost), true)
			local def = CardData.Cards[cardId]
			local lines = {}
			for _, kw in ipairs(CardData.Keywords) do
				if def.keywords and def.keywords[kw] then
					table.insert(lines, kw .. ": " .. CardData.KeywordText[kw])
				end
			end
			local rule = def.type == "Creature" and CardData.FamilyRules[def.family]
			if rule and rule.rule then
				table.insert(lines, rule.name .. ": " .. rule.text)
			end
			if def.type == "Creature" and def.family ~= "Any" then
				table.insert(lines, "Home: +1 attack on " .. (CardData.Terrains[def.family] or def.family))
			end
			for _, word in ipairs({ "Combo", "Power", "Charge", "Soak", "Scrap" }) do
				if CardData.RuleText[word] and string.find((def.text or "") .. (def.sparkText or ""), word, 1, true) then
					table.insert(lines, word .. ": " .. CardData.RuleText[word])
				end
			end
			if def.type == "Building" then
				table.insert(lines, "Buildings sit behind a lane and help the creature in it. One per lane.")
			end
			if #lines > 0 then
				local rows = 0
				for _, line in ipairs(lines) do
					rows += math.max(1, math.ceil(#line / 30))
				end
				local help = label(ui.previewHolder, table.concat(lines, "\n"), {
					Name = "KeywordHelp",
					Size = UDim2.new(1, 0, 0, 16 * rows + 10),
					Position = UDim2.new(0, 0, 1, 6),
					Font = BODY_FONT,
					TextScaled = false,
					TextSize = 14,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					BackgroundTransparency = 0.25,
					BackgroundColor3 = Color3.fromRGB(20, 16, 30),
				})
				corner(help, 8)
				make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4) }, help)
			end
			S.previewKey = key
		end
		ui.previewHolder.Visible = true
	end

	function F.hidePreview()
		ui.previewHolder.Visible = false
	end

	---------------------------------------------------------------------------
	-- The lanes on the table
	--
	-- Like the Card Wars board: each side is one stretch of land split into lanes that touch.
	-- Every lane is its landscape (sand, snow, grass...), kept plain so the creatures stand out,
	-- with a soft round spot where its creature stands and a flat stone foundation behind it for a
	-- building. A wooden frame goes around the whole field and a gold seam runs where the two
	-- sides meet.
	---------------------------------------------------------------------------

	S.boardFolder = Instance.new("Folder")
	S.boardFolder.Name = "LaneBoard"
	S.boardFolder.Parent = workspace

	-- Where each board part sits when it's not rising out of the table.
	S.rest = setmetatable({}, { __mode = "k" })

	local GOLD = Color3.fromRGB(215, 175, 80)
	-- How see-through the ring a creature stands in is when nothing is happening there.
	local RING_REST = 0.6

	-- What each landscape looks like: its ground and the colour of the ring a creature stands in.
	local LANDS = {
		Snack = { material = Enum.Material.Sand, shade = 0.12, accent = Color3.fromRGB(255, 170, 70) }, -- Soda Swamp
		Junk = { material = Enum.Material.CorrodedMetal, shade = 0.3, accent = Color3.fromRGB(255, 120, 220) }, -- Glitter Junkyard
		Weather = { material = Enum.Material.Snow, shade = 0.05, accent = Color3.fromRGB(150, 220, 255) }, -- Static Snowfield
		Critter = { material = Enum.Material.Grass, shade = 0.25, accent = Color3.fromRGB(255, 200, 225) }, -- Pillow Peaks
		Spooky = { material = Enum.Material.Slate, shade = 0.3, accent = Color3.fromRGB(190, 120, 255) }, -- Mushroom Mall
		Robo = { material = Enum.Material.DiamondPlate, shade = 0.25, accent = Color3.fromRGB(255, 120, 40) }, -- Lava Laundromat
	}
	local PLAIN = { material = Enum.Material.Ground, shade = 0.45, accent = GOLD }

	local function groundColor(family)
		local look = LANDS[family] or PLAIN
		return familyColor(family):Lerp(Color3.fromRGB(30, 26, 32), look.shade)
	end

	-- The old tile board, its frame and the energy crystals are hidden in a match; in 2v2 also the
	-- hero pedestals and card piles (the wider field and the four heroes need the room).
	S.hidden = {}
	local ALWAYS_HIDE = { BoardBed = true, BoardFrame = true, FrameCap = true, HalfwayLine = true, HalfwayMark = true, TilePlinth = true, CrystalSocket = true }
	function F.hideTableParts(all)
		for _, folder in ipairs({ board, duelTable }) do
			for _, d in ipairs(folder:GetChildren()) do
				if d:IsA("BasePart") then
					local name = d.Name
					local always = ALWAYS_HIDE[name] or name:match("^Tile_") or name:match("^Energy_")
					local wideOnly = name:match("^Hero") or name:match("^Pedestal") or name:match("^Deck") or name:match("^Discard")
					if always or (all and wideOnly) then
						if not S.hidden[d] then
							S.hidden[d] = { d.Transparency, d.CanQuery }
						end
						d.Transparency = 1
						d.CanQuery = false
					end
				end
			end
		end
	end
	function F.restoreTableParts()
		for d, saved in pairs(S.hidden) do
			if d.Parent then
				d.Transparency = saved[1]
				d.CanQuery = saved[2]
			end
		end
		S.hidden = {}
	end

	local function part(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.SmoothPlastic
		for k, v in pairs(props) do
			p[k] = v
		end
		p.Parent = props.Parent or S.boardFolder
		S.rest[p] = p.CFrame
		return p
	end

	-- A cylinder standing up: `h` tall, `d` across, its bottom at the CFrame `base` (which can lean).
	local function upright(base, h, d, props)
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(h, d, d)
		props.CFrame = base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		return part(props)
	end

	local function laneAttrs(p, team, lane, slot)
		p:SetAttribute("Team", team)
		p:SetAttribute("Lane", lane)
		p:SetAttribute("Slot", slot)
	end

	-- Height of the felt on the table (the field and the 2v2 heroes stand on it).
	function F.feltTop()
		local felt = duelTable:FindFirstChild("Felt")
		return felt and (felt.Position.Y + felt.Size.Y / 2) or 4.1
	end

	-- Where everything goes, for a side `width` lanes wide. In 1v1 the field is exactly as big as
	-- the old board; in 2v2 it's 8 lanes wide and spreads over the felt.
	function F.makeLayout(width)
		local wide = width > 4
		local pitch = wide and 2.55 or 3.075
		local base = F.feltTop()
		local L = {
			width = width,
			pitch = pitch,
			wide = wide,
			half = 7.35, -- how deep each side is
			frame = 0.36, -- how wide the wooden frame is
			base = base,
			groundTop = base + 0.26,
			-- Each side has two rows of creatures per lane (Front nearest the middle, Back behind
			-- it) and a building slot behind those.
			creatureZ = 1.95, -- the Front row
			backZ = 4.2, -- the Back row
			buildingZ = 6.25,
		}
		L.rowGap = L.backZ - L.creatureZ
		L.spot = math.min(pitch * 0.82, 2.1) -- how wide a creature's spot is
		L.padTop = L.groundTop
		L.frameTop = L.groundTop + 0.16
		L.halfWidth = pitch * width / 2
		function L.x(lane)
			return (lane - (width + 1) / 2) * pitch
		end
		-- z for my team (near, +z) or the enemy (far, -z)
		function L.z(team, z)
			return (team == S.myTeam) and z or -z
		end
		return L
	end

	function F.buildBoard(v)
		S.ghost = nil -- (its model goes with the board)
		S.boardFolder:ClearAllChildren()
		S.pads = {}
		S.scrap = {}
		local L = F.makeLayout(v.width)
		S.layout = L
		F.hideTableParts(L.wide)
		if ctx.setTableWidth then
			ctx.setTableWidth(v.width)
		end
		local W, D, fw = L.halfWidth, L.half, L.frame
		-- The base under the field, and the wooden frame around it with gold caps on the corners
		-- and where the two sides meet.
		part({ Name = "LaneBase", Size = Vector3.new(2 * (W + fw), 0.12, 2 * (D + fw)), CFrame = CFrame.new(0, L.base + 0.06, 0), Color = Color3.fromRGB(46, 36, 32), Material = Enum.Material.Wood, CanQuery = false })
		local frameTop = L.frameTop
		local fh = frameTop - L.base
		local frameColor = Color3.fromRGB(150, 105, 65)
		for _, sx in ipairs({ -1, 1 }) do
			part({ Name = "LaneFrame", Size = Vector3.new(fw, fh, 2 * (D + fw)), CFrame = CFrame.new(sx * (W + fw / 2), L.base + fh / 2, 0), Color = frameColor, Material = Enum.Material.Wood, Reflectance = 0.04, CanQuery = false })
			part({ Name = "LaneFrame", Size = Vector3.new(2 * W, fh, fw), CFrame = CFrame.new(0, L.base + fh / 2, sx * (D + fw / 2)), Color = frameColor, Material = Enum.Material.Wood, Reflectance = 0.04, CanQuery = false })
			for _, sz in ipairs({ -1, 0, 1 }) do
				part({ Name = "LaneFrameCap", Size = Vector3.new(fw + 0.1, 0.1, fw + 0.1), CFrame = CFrame.new(sx * (W + fw / 2), frameTop + 0.05, sz * (D + fw / 2)), Color = GOLD, Material = Enum.Material.Metal, Reflectance = 0.15, CanQuery = false })
			end
		end
		for t = 1, 2 do
			S.pads[t] = {}
			S.scrap[t] = {}
			for lane = 1, v.width do
				F.buildLane(v, t, lane)
			end
			-- Thin grooves between the lanes; in 2v2 a gold line between teammates' halves.
			for lane = 1, v.width - 1 do
				local x = (L.x(lane) + L.x(lane + 1)) / 2
				local split = L.wide and lane == (v.lanesPerSeat or 4)
				part({ Name = split and "TeamSplit" or "LaneLine", Size = Vector3.new(split and 0.1 or 0.05, 0.03, D - 0.12), CFrame = CFrame.new(x, L.groundTop + 0.005, L.z(t, D / 2 + 0.06)), Color = split and GOLD or Color3.fromRGB(22, 18, 20), Transparency = split and 0 or 0.4, Material = split and Enum.Material.Neon or Enum.Material.SmoothPlastic, CanQuery = false })
			end
		end
		-- The seam where the two sides meet: a thin gold line.
		part({ Name = "MidLine", Size = Vector3.new(2 * W, 0.03, 0.08), CFrame = CFrame.new(0, L.groundTop + 0.01, 0), Color = GOLD, Material = Enum.Material.SmoothPlastic, Transparency = 0.2, CanQuery = false })
		-- The lanes rise out of the table one after another, from the middle outwards.
		local mid = (v.width + 1) / 2
		for t = 1, 2 do
			for lane = 1, v.width do
				F.riseLane(t, lane, (0.25 + math.abs(lane - mid) * 0.12 + (t == S.myTeam and 0 or 0.06)) * PACE, 2.2)
			end
		end
	end

	function F.buildLane(v, t, lane)
		local L = S.layout
		local x = L.x(lane)
		local D = L.half
		local land = v.lanes[t][lane].landscape
		local look = LANDS[land] or PLAIN
		local groundBottom = L.base + 0.12
		local groundH = L.groundTop - groundBottom
		-- The ground: the lanes touch, so each side reads as one stretch of land.
		local strip = part({ Name = "LaneStrip", Size = Vector3.new(L.pitch, groundH, D), CFrame = CFrame.new(x, groundBottom + groundH / 2, L.z(t, D / 2)), Color = groundColor(land), Material = look.material, CanQuery = true })
		laneAttrs(strip, t, lane, "creature")
		laneAttrs(strip, t, lane, "strip") -- (which row a click on the ground means is worked out from where it lands)
		-- The creature spots, Front and Back: a soft ring in the landscape's colour around a lighter
		-- circle (the Back spot a little darker, so the two rows read apart).
		local cz = L.z(t, L.creatureZ)
		local backz = L.z(t, L.backZ)
		local spot = L.spot
		local flat = CFrame.Angles(0, 0, math.pi / 2)
		local ring = part({ Name = "CreatureRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, spot, spot), CFrame = CFrame.new(x, L.groundTop + 0.006, cz) * flat, Color = look.accent, Material = Enum.Material.SmoothPlastic, Transparency = RING_REST, CanQuery = false })
		local cpad = part({ Name = "CreaturePad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, spot - 0.16, spot - 0.16), CFrame = CFrame.new(x, L.groundTop + 0.012, cz) * flat, Color = groundColor(land):Lerp(WHITE, 0.3), Transparency = 0.35, CanQuery = true })
		laneAttrs(cpad, t, lane, "creature")
		local backRing = part({ Name = "BackRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, spot, spot), CFrame = CFrame.new(x, L.groundTop + 0.006, backz) * flat, Color = look.accent, Material = Enum.Material.SmoothPlastic, Transparency = RING_REST, CanQuery = false })
		local bkpad = part({ Name = "BackPad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, spot - 0.16, spot - 0.16), CFrame = CFrame.new(x, L.groundTop + 0.012, backz) * flat, Color = groundColor(land):Lerp(WHITE, 0.12), Transparency = 0.35, CanQuery = true })
		laneAttrs(bkpad, t, lane, "back")
		-- The building's foundation behind it: a stone slab on a dark rim.
		local bz = L.z(t, L.buildingZ)
		local rim = part({ Name = "BuildingRim", Size = Vector3.new(L.pitch * 0.58 + 0.14, 0.02, 1.64), CFrame = CFrame.new(x, L.groundTop + 0.008, bz), Color = Color3.fromRGB(28, 22, 24), Transparency = 0.15, CanQuery = false })
		local bpad = part({ Name = "BuildingPad", Size = Vector3.new(L.pitch * 0.58, 0.03, 1.5), CFrame = CFrame.new(x, L.groundTop + 0.016, bz), Color = groundColor(land):Lerp(Color3.fromRGB(20, 16, 18), 0.4), Material = Enum.Material.Cobblestone, CanQuery = true })
		laneAttrs(bpad, t, lane, "building")
		-- Glowing frames shown when you can pick a spot: one for each row and one for the building.
		local function glowAt(z, depth)
			return part({ Name = "LaneGlow", Size = Vector3.new(L.pitch * 0.86, 0.04, depth), CFrame = CFrame.new(x, L.groundTop + 0.03, z), Color = Color3.fromRGB(255, 210, 90), Material = Enum.Material.Neon, Transparency = 1, CanQuery = false })
		end
		local glow = glowAt(cz, L.rowGap - 0.12)
		local backGlow = glowAt(backz, L.rowGap - 0.12)
		local buildGlow = glowAt(bz, 1.6)
		-- (The landscape's name shows when you hover the lane.)
		S.pads[t][lane] = { strip = strip, ring = ring, creature = cpad, backRing = backRing, back = bkpad, rim = rim, building = bpad, glow = glow, backGlow = backGlow, buildGlow = buildGlow, landscape = land, deco = {}, weather = nil }
		S.scrap[t][lane] = {}
		F.decorate(t, lane)
	end

	-- Everything in a lane that rises out of the table (the ground and its spots).
	function F.laneParts(pad)
		local out = { pad.strip, pad.ring, pad.creature, pad.backRing, pad.back, pad.rim, pad.building }
		for _, d in ipairs(pad.deco) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- The lane comes up out of the table (from `depth` studs down) after `delay` seconds.
	function F.riseLane(team, lane, delay, depth)
		local pad = S.pads[team] and S.pads[team][lane]
		if not pad then
			return
		end
		local seconds = 0.55 * PACE
		local info = TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, delay)
		for _, p in ipairs(F.laneParts(pad)) do
			local goal = S.rest[p] or p.CFrame
			p.CFrame = CFrame.new(0, -depth, 0) * goal
			TweenService:Create(p, info, { CFrame = goal }):Play()
		end
	end

	-- Bring a creature's ring to full glow for a moment (a creature landed, or it's battling).
	function F.flareRing(team, lane, color, row)
		local pad = S.pads[team] and S.pads[team][lane]
		local ring = pad and (row == 2 and pad.backRing or pad.ring)
		if not (ring and ring.Parent) then
			return
		end
		local look = LANDS[pad.landscape] or PLAIN
		ring.Color = color or look.accent
		ring.Transparency = 0.15
		TweenService:Create(ring, TweenInfo.new(0.9 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = RING_REST, Color = look.accent }):Play()
	end

	-- Lanes are kept plain (just their ground) so the creatures stand out; this only clears anything
	-- left over in a lane.
	function F.decorate(team, lane)
		local pad = S.pads[team] and S.pads[team][lane]
		if not pad then
			return
		end
		for _, d in ipairs(pad.deco) do
			d:Destroy()
		end
		pad.deco = {}
		pad.weather = nil
	end

	-- A card changed a lane's landscape: the new land rises out of the table.
	function F.setLandscape(team, lane, family)
		local pad = S.pads[team] and S.pads[team][lane]
		if not pad or pad.landscape == family then
			return
		end
		pad.landscape = family
		local look = LANDS[family] or PLAIN
		pad.strip.Material = look.material
		pad.strip.Color = groundColor(family)
		pad.creature.Color = groundColor(family):Lerp(WHITE, 0.3)
		pad.ring.Color = look.accent
		pad.back.Color = groundColor(family):Lerp(WHITE, 0.12)
		pad.backRing.Color = look.accent
		pad.building.Color = groundColor(family):Lerp(Color3.fromRGB(20, 16, 18), 0.4)
		F.decorate(team, lane)
		F.riseLane(team, lane, 0, 0.9)
		F.flareRing(team, lane)
	end

	-- A unit's spot: "creature" (the Front row), "back" (the Back row) or "building".
	function F.slotOf(u)
		if u.kind == "building" then
			return "building"
		end
		return u.row == 2 and "back" or "creature"
	end
	function F.rowOfSlot(slot)
		return slot == "back" and 2 or (slot == "creature" and 1 or nil)
	end

	function F.slotCF(team, lane, slot)
		local L = S.layout
		local z = L.z(team, slot == "building" and L.buildingZ or (slot == "back" and L.backZ or L.creatureZ))
		local cf = CFrame.new(L.x(lane), L.padTop + 0.03, z)
		if team ~= S.myTeam then
			cf = cf * CFrame.Angles(0, math.pi, 0)
		end
		return cf
	end

	function F.glowLanes(list, color)
		for t = 1, 2 do
			for _, pad in pairs(S.pads[t] or {}) do
				pad.glow.Transparency = 1
				pad.backGlow.Transparency = 1
				pad.buildGlow.Transparency = 1
			end
		end
		for _, item in ipairs(list or {}) do
			local pad = S.pads[item.team] and S.pads[item.team][item.lane]
			if pad then
				local slot = item.slot or (item.row == 2 and "back" or "creature")
				local g = slot == "building" and pad.buildGlow or (slot == "back" and pad.backGlow or pad.glow)
				g.Color = item.color or color or Color3.fromRGB(255, 210, 90)
				g.Transparency = 0.45
			end
		end
	end

	-- Scrap piles in a lane: little grey heaps beside the creature's spot.
	function F.setScrap(team, lane, amount)
		local heaps = S.scrap[team] and S.scrap[team][lane]
		if not heaps then
			return
		end
		while #heaps > amount do
			table.remove(heaps):Destroy()
		end
		local pad = S.pads[team][lane]
		while #heaps < amount do
			local k = #heaps + 1
			local p = part({ Name = "Scrap", Shape = Enum.PartType.Ball, Size = Vector3.new(0.45, 0.45, 0.45), CFrame = CFrame.new(pad.creature.Position.X - 0.75 + k * 0.38, S.layout.groundTop + 0.08, pad.creature.Position.Z + (team == S.myTeam and -1.05 or 1.05)), Color = Color3.fromRGB(150, 145, 140), Material = Enum.Material.CorrodedMetal, CanQuery = false })
			table.insert(heaps, p)
		end
	end

	---------------------------------------------------------------------------
	-- Effects
	---------------------------------------------------------------------------

	function F.step(seconds)
		task.wait((seconds or 0.3) * PACE)
		if S.playing ~= S.matchId then
			error(ABORT, 0)
		end
	end

	function F.fxPart(pos, size)
		local p = part({ Name = "FX", Size = size or Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos), Transparency = 1, CanQuery = false })
		Debris:AddItem(p, 4)
		return p
	end


	function F.floatText(pos, text, color, big)
		local holder = F.fxPart(pos)
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(big and 220 or 160, big and 60 or 42)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Parent = holder
		local l = label(bb, text, { TextColor3 = color or WHITE, TextStrokeTransparency = 0 })
		TweenService:Create(bb, TweenInfo.new(1.1 * PACE, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
		TweenService:Create(l, TweenInfo.new(1.1 * PACE, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end

	function F.flashModel(model, color, seconds)
		if not model or not model.Parent then
			return
		end
		local h = Instance.new("Highlight")
		h.FillColor = color
		h.FillTransparency = 0.35
		h.OutlineTransparency = 1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
		TweenService:Create(h, TweenInfo.new((seconds or 0.35) * PACE), { FillTransparency = 1 }):Play()
		Debris:AddItem(h, (seconds or 0.35) * PACE + 0.1)
	end

	-- A creature that's hit rocks back a little (away from `dir`) and settles again.
	function F.knock(entry, dir)
		if not (entry.model and entry.model.Parent) or entry.busy then
			return
		end
		local home = entry.home
		local push = (dir or Vector3.new(0, 0, -1)) * 0.35
		entry.busy = true
		F.tween(0.3, function(a)
			if entry.model.Parent then
				local k = math.sin(a * math.pi)
				entry.model:PivotTo(home + push * k)
			end
		end, function()
			entry.busy = false
		end)
	end

	-- Runs fn(alpha) every frame while alpha goes from 0 to 1, then calls done.
	function F.tween(seconds, fn, done)
		local value = Instance.new("NumberValue")
		local conn = value.Changed:Connect(fn)
		local tw = TweenService:Create(value, TweenInfo.new(math.max(0.01, seconds * PACE), Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
		tw.Completed:Connect(function()
			conn:Disconnect()
			fn(1)
			value:Destroy()
			if done then
				done()
			end
		end)
		tw:Play()
		return tw
	end

	---------------------------------------------------------------------------
	-- Units and heroes
	---------------------------------------------------------------------------

	function F.unitPosition(entry)
		if entry.model and entry.model.Parent then
			return entry.home.Position + Vector3.new(0, entry.height * 0.6, 0)
		end
		return F.slotCF(entry.team, entry.lane, entry.slot or entry.kind).Position
	end

	function F.makeLabel(entry)
		local root = entry.model.PrimaryPart or entry.model:FindFirstChildWhichIsA("BasePart")
		local bb = Instance.new("BillboardGui")
		bb.Name = "Stats"
		bb.Size = UDim2.fromOffset(120, 44)
		bb.StudsOffsetWorldSpace = Vector3.new(0, entry.height + 0.55, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 80
		bb.Adornee = root
		bb.Parent = entry.model
		local back = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Color3.fromRGB(25, 20, 35), BackgroundTransparency = 0.2 }, bb)
		corner(back, 8)
		entry.statsLabel = label(back, "", { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), RichText = true })
		entry.statusLabel = label(bb, "", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 25), TextStrokeTransparency = 0.3, Font = BODY_FONT })
	end

	function F.setStats(entry, u)
		entry.data = u
		if entry.kind ~= "creature" or not entry.statsLabel then
			return
		end
		local atkColor = u.atk > (u.baseAtk or u.atk) and "#8CFF8C" or (u.atk < (u.baseAtk or u.atk) and "#FF9C9C" or "#FFFFFF")
		local hpColor = u.hp < u.maxHp and "#FF9C9C" or "#FFFFFF"
		entry.statsLabel.Text = string.format('<font color="%s">⚔%d</font>  <font color="%s">❤%d</font>', atkColor, u.atk, hpColor, u.hp)
		local bits = {}
		if u.new then
			table.insert(bits, "💤")
		end
		if u.sparked then
			table.insert(bits, "🌀")
		end
		if u.power and u.power > 0 then
			table.insert(bits, "⚡" .. u.power)
		end
		if u.soaked then
			table.insert(bits, "💧")
		end
		if u.shield then
			table.insert(bits, "🛡")
		end
		if u.frozen then
			table.insert(bits, "❄")
		end
		entry.statusLabel.Text = table.concat(bits, " ")
	end

	-- How big a unit's model stands on the board (its spot is about 2 studs across).
	function F.unitScale(id, kind)
		local info = CreatureBuilder.info(id) or { height = 2.5, width = 2.5, depth = 2.5 }
		local widest = math.max(info.width or 2.5, info.depth or 2.5, 0.5)
		local L = S.layout
		if kind == "building" then
			return math.min(0.5, L.pitch * 0.62 / widest, 1.6 / math.max(info.height, 0.5)), info
		end
		return math.min(0.6, L.spot * 0.98 / widest, 2.6 / math.max(info.height, 0.5)), info
	end

	---------------------------------------------------------------------------
	-- Placement preview: while you place a creature or a building (clicked or dragged), a see-through
	-- copy of it glides after the pointer and snaps onto the nearest spot it can go, so you see
	-- exactly where it will land before you let go.
	---------------------------------------------------------------------------
	function F.hideGhost(destroy)
		local g = S.ghost
		if not g then
			return
		end
		g.spot = nil
		if destroy then
			if g.model then
				g.model:Destroy()
			end
			S.ghost = nil
		elseif g.model then
			g.model.Parent = nil
		end
	end

	function F.ghostModel(id, kind)
		local model = ctx.buildModel(id)
		local s = F.unitScale(id, kind)
		ctx.setScale(model, s)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanQuery = false
				d.CanCollide = false
				d.CastShadow = false
				d.Transparency = math.max(d.Transparency, 0.55)
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("Smoke") then
				d:Destroy()
			end
		end
		local h = Instance.new("Highlight")
		h.FillTransparency = 0.75
		h.FillColor = Color3.fromRGB(255, 220, 120)
		h.OutlineColor = Color3.fromRGB(255, 220, 120)
		h.OutlineTransparency = 0.1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
		return model, h
	end

	-- The spot nearest the pointer (on the table's ground plane) that the picked card can go to.
	function F.nearestSpot(pick, px, py)
		local L = S.layout
		local ray = camera:ViewportPointToRay(px, py)
		if math.abs(ray.Direction.Y) < 1e-4 then
			return nil
		end
		local tHit = (L.groundTop - ray.Origin.Y) / ray.Direction.Y
		if tHit <= 0 then
			return nil
		end
		local at = ray.Origin + ray.Direction * tHit
		local c = CardData.Cards[pick.id]
		local radius = 0.7 * math.min(L.pitch, L.rowGap) + 0.45
		local best, bestD = nil, radius
		for _, item in ipairs(F.spotsFor(pick.action, c)) do
			local slot = item.slot or (item.row == 2 and "back" or "creature")
			local p = F.slotCF(S.myTeam, item.lane, slot).Position
			local d = ((p - at) * Vector3.new(1, 0, 1)).Magnitude
			if d < bestD then
				best, bestD = { lane = item.lane, row = item.row, slot = slot, replace = item.replace }, d
			end
		end
		return best
	end

	function F.updateGhost(dt)
		local pick = S.pick
		if not (pick and pick.kind == "card" and pick.step == "lane" and S.layout and F.myTurn()) then
			F.hideGhost(true)
			return
		end
		local c = CardData.Cards[pick.id]
		if not c or (c.type ~= "Creature" and c.type ~= "Building") then
			F.hideGhost(true)
			return
		end
		local g = S.ghost
		if not g or g.id ~= pick.id or g.handUid ~= pick.handUid then
			F.hideGhost(true)
			local model, h = F.ghostModel(pick.id, c.type == "Building" and "building" or "creature")
			g = { id = pick.id, handUid = pick.handUid, model = model, highlight = h, cf = nil }
			S.ghost = g
		end
		local p = F.pointer()
		local spot = F.nearestSpot(pick, p.X, p.Y)
		g.spot = spot
		if not spot then
			g.model.Parent = nil
			g.cf = nil
			return
		end
		local target = F.slotCF(S.myTeam, spot.lane, spot.slot)
		local color = spot.replace and Color3.fromRGB(255, 150, 70) or Color3.fromRGB(255, 220, 120)
		g.highlight.FillColor = color
		g.highlight.OutlineColor = color
		if not g.cf then
			g.cf = target * CFrame.new(0, 0.6, 0)
		end
		local a = 1 - math.exp(-(dt or 1 / 60) * 16)
		g.cf = g.cf:Lerp(target, a)
		local bob = 0.12 + math.sin(clock() * 4) * 0.06
		g.model:PivotTo(g.cf * CFrame.new(0, bob, 0))
		g.model.Parent = S.boardFolder
	end

	function F.spawnUnit(u, quick)
		local existing = S.units[u.uid]
		if existing then
			return existing
		end
		local model = ctx.buildModel(u.id)
		local s, info = F.unitScale(u.id, u.kind)
		ctx.setScale(model, s)
		local slot = F.slotOf(u)
		local home = F.slotCF(u.team, u.lane, slot)
		model:PivotTo(home)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanQuery = true
				d.CanCollide = false
			end
		end
		model.Parent = S.boardFolder
		local entry = { uid = u.uid, id = u.id, kind = u.kind, slot = slot, row = u.row, team = u.team, lane = u.lane, owner = u.owner, model = model, home = home, height = info.height * s, scale = s, phase = math.random() * 6.28, busy = false }
		S.units[u.uid] = entry
		if u.kind == "creature" then
			F.makeLabel(entry)
			F.setStats(entry, u)
		end
		if not quick then
			entry.busy = true
			model:PivotTo(home * CFrame.new(0, -1.2, 0))
			if u.kind == "creature" then
				F.flareRing(u.team, u.lane, nil, u.row)
			end
			F.tween(0.45, function(a)
				if model.Parent then
					model:PivotTo(home * CFrame.new(0, -1.2 * (1 - a) + math.sin(a * math.pi) * 0.5, 0))
				end
			end, function()
				entry.busy = false
			end)
		end
		return entry
	end

	function F.removeUnit(uid, how)
		local entry = S.units[uid]
		if not entry then
			return
		end
		S.units[uid] = nil
		local model = entry.model
		if not model.Parent then
			return
		end
		if how == "quick" then
			model:Destroy()
			return
		end
		F.flashModel(model, WHITE, 0.25)
		local start = entry.home
		F.tween(0.4, function(a)
			if model.Parent then
				if how == "bounce" then
					model:PivotTo(start * CFrame.new(0, a * 6, 0) * CFrame.Angles(0, a * 6, 0))
				else
					ctx.setScale(model, entry.scale * (1 - 0.9 * a))
					model:PivotTo(start * CFrame.new(0, -a * 0.3, 0))
				end
			end
		end, function()
			model:Destroy()
		end)
	end

	function F.moveUnit(entry, lane, team, row)
		entry.lane = lane
		entry.team = team or entry.team
		if entry.kind == "creature" and row then
			entry.row = row
			entry.slot = row == 2 and "back" or "creature"
		end
		local from = entry.home
		local to = F.slotCF(entry.team, lane, entry.slot or entry.kind)
		entry.home = to
		entry.busy = true
		F.tween(0.45, function(a)
			if entry.model.Parent then
				local p = from.Position:Lerp(to.Position, a) + Vector3.new(0, math.sin(a * math.pi) * 1.4, 0)
				entry.model:PivotTo(CFrame.new(p) * (to - to.Position))
			end
		end, function()
			entry.busy = false
		end)
	end

	function F.heroCF(seat)
		local v = S.view
		local L = S.layout
		local sv = v.seats[seat]
		local mine = sv.team == S.myTeam
		if not L.wide then
			local spot = board:FindFirstChild(mine and "Hero_Near" or "Hero_Far")
			if spot then
				local p = spot.Position
				local top = p.Y + spot.Size.X / 2 -- cylinders lie on their side: X is their height
				local cf = CFrame.new(p.X, top, p.Z)
				return mine and cf * CFrame.Angles(0, -0.55, 0) or cf * CFrame.Angles(0, math.pi + 0.55, 0)
			end
		end
		-- 2v2: each hero stands behind its player's lanes.
		local x = 0
		for _, lane in ipairs(sv.lanes) do
			x += L.x(lane)
		end
		x /= #sv.lanes
		local z = L.z(sv.team, L.half + L.frame + 1.35)
		local cf = CFrame.new(x, F.feltTop() + 0.32, z)
		return mine and cf or cf * CFrame.Angles(0, math.pi, 0)
	end

	function F.placeHeroes(v)
		for _, entry in pairs(S.heroes) do
			if entry.model then
				entry.model:Destroy()
			end
			if entry.pedestal then
				entry.pedestal:Destroy()
			end
		end
		S.heroes = {}
		for seat, sv in ipairs(v.seats) do
			local model = ctx.buildModel("hero_" .. sv.hero)
			local info = CreatureBuilder.info("hero_" .. sv.hero) or { height = 3 }
			local s = S.layout.wide and 0.5 or 0.62
			ctx.setScale(model, s)
			local cf = F.heroCF(seat)
			local entry = { seat = seat, model = model, home = cf, height = info.height * s, phase = math.random() * 6 }
			if S.layout.wide then
				entry.pedestal = part({ Name = "HeroDisc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.2, 2.2), CFrame = CFrame.new(cf.Position - Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromRGB(230, 225, 215), Material = Enum.Material.Marble, CanQuery = true })
				entry.pedestal:SetAttribute("HeroSeat", seat)
			end
			model:PivotTo(entry.home)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CanQuery = true
				elseif d:IsA("ParticleEmitter") or d:IsA("Sparkles") or d:IsA("Fire") or d:IsA("Smoke") then
					d:Destroy() -- heroes stand still and calm; their sparkles filled the side of the screen
				end
			end
			model.Parent = S.boardFolder
			model:SetAttribute("HeroSeat", seat)
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(170, 20)
			bb.StudsOffsetWorldSpace = Vector3.new(0, entry.height + 0.5, 0)
			bb.AlwaysOnTop = true
			bb.LightInfluence = 0
			bb.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			bb.Parent = model
			local nm = (v.names and v.names[seat] and v.names[seat].name) or sv.name
			label(bb, nm, { TextScaled = false, TextSize = 15, Font = BODY_FONT, TextStrokeTransparency = 0.5, TextColor3 = sv.team == S.myTeam and Color3.fromRGB(190, 255, 200) or Color3.fromRGB(255, 200, 190) })
			S.heroes[seat] = entry
		end
	end

	function F.heroPos(team)
		-- The middle of a team's heroes (for hits on the team's hit points).
		local sum, n = Vector3.zero, 0
		for seat, entry in pairs(S.heroes) do
			if S.view.seats[seat].team == team then
				sum += entry.home.Position
				n += 1
			end
		end
		return n > 0 and (sum / n + Vector3.new(0, 1.2, 0)) or Vector3.new(0, 5, team == S.myTeam and 8 or -8)
	end

	-- The opponent's chair: Bot Bonkers sits there in bot matches.
	function F.placeBotAvatar(v)
		if S.botAvatar then
			S.botAvatar:Destroy()
			S.botAvatar = nil
		end
		if v.teamMode then
			return
		end
		local enemySeat = nil
		for seat, sv in ipairs(v.seats) do
			if sv.team ~= S.myTeam then
				enemySeat = seat
			end
		end
		local n = v.names and v.names[enemySeat]
		if not (n and n.bot) then
			return
		end
		local seatFar = duelTable:FindFirstChild("Seat_Far")
		local model = nil
		if type(n.boss) == "string" and CardData.Cards[n.boss] then
			-- a campaign boss sits in the chair itself, as tall as Bot Bonkers
			local ok, built = pcall(CreatureBuilder.build, n.boss)
			if ok and built then
				model = built
				local info = CreatureBuilder.info(n.boss) or { height = 2.5 }
				local ref = CreatureBuilder.info("bot_bonkers") or { height = 6 }
				if ctx.setScale and info.height and info.height > 0 then
					ctx.setScale(model, math.clamp((ref.height or 6) / info.height, 0.5, 4))
				end
			end
		end
		model = model or CreatureBuilder.build("bot_bonkers")
		if not (model and seatFar) then
			return
		end
		model.Name = "BotOpponent"
		model:PivotTo(CFrame.new(seatFar.Position.X, 0, seatFar.Position.Z) * seatFar.CFrame.Rotation)
		model.Parent = S.boardFolder
		S.botAvatar = model
		S.botBase = model:GetPivot()
	end

	---------------------------------------------------------------------------
	-- Hand
	---------------------------------------------------------------------------

	S.handCards = {} -- [uid] = holder
	function F.refreshHand(v)
		local seen = {}
		local legal = {}
		for _, a in ipairs(v.legal or {}) do
			if a.kind == "play" then
				legal[a.handUid] = a
			end
		end
		for i, h in ipairs(v.hand) do
			seen[h.uid] = true
			local holder = S.handCards[h.uid]
			if not holder or holder:GetAttribute("Cost") ~= h.cost then
				if holder then
					holder:Destroy()
				end
				holder = make("TextButton", { Name = "HandCard_" .. h.id, Text = "", Size = UDim2.fromOffset(106, 148), BackgroundTransparency = 1, AutoButtonColor = false }, ui.handFrame)
				holder:SetAttribute("Cost", h.cost)
				holder:SetAttribute("HandUid", h.uid)
				-- Calm cards in your hand: the picture stays still and nothing sweeps across them.
				local card = ctx.makeCard(holder, h.id, UDim2.fromScale(1, 1), h.cost, "compact")
				card.Name = "Card"
				make("UIStroke", { Name = "Playable", Thickness = 4, Color = Color3.fromRGB(110, 255, 130), Transparency = 1 }, card)
				local uid = h.uid
				holder.MouseEnter:Connect(function()
					S.handHover = uid
					card.Position = UDim2.fromOffset(0, -30)
					F.preview(h.id, h.cost)
				end)
				holder.MouseLeave:Connect(function()
					if S.handHover == uid then
						S.handHover = nil
					end
					if not (S.pick and S.pick.handUid == uid) then
						card.Position = UDim2.fromOffset(0, 0)
					end
					F.hidePreview()
				end)
				holder.Activated:Connect(function()
					if S.dragDropped then
						S.dragDropped = false
						return
					end
					F.onCardClicked(uid)
				end)
				-- Press and drag the card onto the table to play it (like Card Wars).
				holder.InputBegan:Connect(function(input)
					local t = input.UserInputType
					if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
						F.dragBegin(uid, h.id, Vector2.new(input.Position.X, input.Position.Y))
					end
				end)
				S.handCards[h.uid] = holder
			end
			holder.LayoutOrder = i
			local playable = legal[h.uid] ~= nil
			local stroke = holder.Card:FindFirstChild("Playable")
			if stroke then
				stroke.Transparency = playable and 0.1 or 1
			end
		end
		for uid, holder in pairs(S.handCards) do
			if not seen[uid] then
				holder:Destroy()
				S.handCards[uid] = nil
			end
		end
	end

	function F.clearHand()
		for _, holder in pairs(S.handCards) do
			holder:Destroy()
		end
		S.handCards = {}
	end

	---------------------------------------------------------------------------
	-- Your moves
	---------------------------------------------------------------------------

	function F.myTurn()
		local v = S.view
		return v and not v.over and v.current == v.you and not S.busy and not S.processing
	end

	function F.legal(kind, key, value)
		for _, a in ipairs(S.view and S.view.legal or {}) do
			if a.kind == kind and (key == nil or a[key] == value) then
				return a
			end
		end
		return nil
	end

	function F.clearPick()
		S.pick = nil
		F.hideGhost(true)
		ui.promptBar.Visible = false
		for _, c in ipairs(ui.promptOptions:GetChildren()) do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		F.glowLanes({})
		for _, holder in pairs(S.handCards) do
			if holder:FindFirstChild("Card") and S.handHover ~= holder:GetAttribute("HandUid") then
				holder.Card.Position = UDim2.fromOffset(0, 0)
			end
		end
	end

	function F.prompt(text, options)
		ui.promptText.Text = text
		for _, c in ipairs(ui.promptOptions:GetChildren()) do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		for _, o in ipairs(options or {}) do
			button(ui.promptOptions, o.text, o.color or Color3.fromRGB(70, 110, 190), o.fn, { Name = o.name or "Option", Size = UDim2.fromOffset(o.width or 170, 46) })
		end
		button(ui.promptOptions, "Cancel", Color3.fromRGB(110, 60, 70), function()
			F.clearPick()
		end, { Name = "Cancel", Size = UDim2.fromOffset(110, 46) })
		ui.promptBar.Visible = true
	end

	function F.send(action)
		if not F.myTurn() then
			return
		end
		F.clearPick()
		if action.kind ~= "battle" then
			S.actedThisTurn = true
		end
		S.battleArmedUntil = 0
		S.busy = true
		F.refreshButtons()
		MatchAction:FireServer(action)
	end

	-- Targets as lane glows: creatures you can aim at glow red (enemy) or green (yours).
	function F.targetGlows(targets)
		local list = {}
		for _, t in ipairs(targets or {}) do
			local row = t.row
			if not row then
				-- (a whole-lane target: light the spot of the creature it would hit first)
				local l = S.view and S.view.lanes[t.team] and S.view.lanes[t.team][t.lane]
				row = (l and not l.creature and l.back) and 2 or 1
			end
			table.insert(list, { team = t.team, lane = t.lane, row = row, color = t.team == S.myTeam and Color3.fromRGB(110, 255, 140) or Color3.fromRGB(255, 90, 80) })
		end
		F.glowLanes(list)
	end

	function F.onCardClicked(uid)
		if not F.myTurn() then
			return
		end
		local a = F.legal("play", "handUid", uid)
		local entry = nil
		for _, h in ipairs(S.view.hand) do
			if h.uid == uid then
				entry = h
			end
		end
		if not entry then
			return
		end
		local c = CardData.Cards[entry.id]
		if not a then
			F.notice(entry.cost > (S.view.seats[S.view.you].magic or 0) and ("Not enough ✨ magic for " .. c.name .. " yet") or ("You can't play " .. c.name .. " right now"), Color3.fromRGB(255, 170, 170))
			return
		end
		F.clearPick()
		local holder = S.handCards[uid]
		if holder and holder:FindFirstChild("Card") then
			holder.Card.Position = UDim2.fromOffset(0, -30)
		end
		if c.type == "Creature" or c.type == "Building" then
			S.pick = { kind = "card", handUid = uid, id = entry.id, step = "lane", action = a }
			F.glowLanes(F.spotsFor(a, c))
			F.prompt(c.type == "Building" and ("Pick a building slot for " .. c.name) or ("Pick a Front or Back spot for " .. c.name), {})
		elseif a.needsTarget then
			S.pick = { kind = "card", handUid = uid, id = entry.id, step = "target", action = a }
			F.targetGlows(a.targets)
			F.prompt("Pick a target for " .. c.name, {})
		else
			F.send({ kind = "play", handUid = uid })
		end
	end

	-- Where a creature or building card can go, as glows: creatures on any of your Front or Back
	-- spots (gold when empty, orange when it would replace one of yours), buildings in a building slot.
	function F.spotsFor(a, c)
		local list = {}
		if c.type == "Building" then
			for _, lane in ipairs(a.lanes or {}) do
				table.insert(list, { team = S.myTeam, lane = lane, slot = "building" })
			end
		else
			for _, t in ipairs(a.tiles or {}) do
				table.insert(list, { team = S.myTeam, lane = t.lane, row = t.row, replace = t.replace, color = t.replace and Color3.fromRGB(255, 150, 70) or nil })
			end
		end
		return list
	end

	-- The spot a hit on the board means for the card being placed (or nil).
	function F.spotForHit(pick, hit)
		if not (hit and hit.team == S.myTeam and hit.lane) then
			return nil
		end
		local c = CardData.Cards[pick.id]
		if c.type == "Building" then
			if table.find(pick.action.lanes or {}, hit.lane) then
				return { lane = hit.lane, slot = "building" }
			end
			return nil
		end
		local row = hit.row
		if not row then
			return nil
		end
		for _, t in ipairs(pick.action.tiles or {}) do
			if t.lane == hit.lane and t.row == row then
				return { lane = t.lane, row = t.row, slot = row == 2 and "back" or "creature", replace = t.replace }
			end
		end
		return nil
	end

	-- A click on the table: a spot, a creature or a hero.
	function F.onBoardClick(hit)
		local pick = S.pick
		if not F.myTurn() then
			return
		end
		if pick and pick.kind == "card" and pick.step == "lane" then
			local spot = (S.ghost and S.ghost.spot) or F.spotForHit(pick, hit)
			if spot then
				local c = CardData.Cards[pick.id]
				if c.type == "Creature" and c.target and pick.action.targets and #pick.action.targets > 0 then
					pick.lane = spot.lane
					pick.row = spot.row
					pick.step = "target"
					F.hideGhost(true)
					F.targetGlows(pick.action.targets)
					F.prompt("Pick a target for " .. c.name .. " (or skip)", {
						{
							text = "Skip",
							name = "Skip",
							fn = function()
								F.send({ kind = "play", handUid = pick.handUid, lane = pick.lane, row = pick.row })
							end,
						},
					})
				else
					F.send({ kind = "play", handUid = pick.handUid, lane = spot.lane, row = spot.row })
				end
			end
			return
		end
		if pick and (pick.kind == "card" or pick.kind == "bigmove") and pick.step == "target" then
			local targets = pick.kind == "bigmove" and pick.action.targets or pick.action.targets
			-- A target on a row matches that row; a whole-lane target matches anywhere in the lane.
			local chosen = nil
			for _, t in ipairs(targets or {}) do
				if t.team == hit.team and t.lane == hit.lane and (t.row == nil or t.row == hit.row) then
					chosen = t
					break
				end
			end
			if chosen then
				if pick.kind == "bigmove" then
					F.send({ kind = "bigmove", target = chosen })
				else
					F.send({ kind = "play", handUid = pick.handUid, lane = pick.lane, row = pick.row, target = chosen })
				end
				return
			end
			return
		end
		-- Clicking one of your creatures: Spark it.
		if hit.unit and hit.unit.kind == "creature" and hit.unit.owner == S.view.you then
			F.selectCreature(hit.unit)
		end
	end

	function F.selectCreature(entry)
		F.clearPick()
		local c = CardData.Cards[entry.id]
		local spark = F.legal("spark", "uid", entry.uid)
		local options = {}
		if c.sparkText then
			if spark then
				table.insert(options, {
					text = "🌀 SPARK (" .. (c.sparkCost or 0) .. "✨)",
					name = "Spark",
					color = Color3.fromRGB(150, 80, 200),
					width = 200,
					fn = function()
						F.send({ kind = "spark", uid = entry.uid })
					end,
				})
			end
		end
		local shift = F.legal("shift", "uid", entry.uid)
		if shift then
			local other = entry.row == 2 and "Front" or "Back"
			table.insert(options, {
				text = "↕ SHIFT to " .. other .. " (" .. (S.view.shiftCost or 1) .. "✨)",
				name = "Shift",
				color = Color3.fromRGB(70, 130, 200),
				width = 220,
				fn = function()
					F.send({ kind = "shift", uid = entry.uid })
				end,
			})
		end
		S.pick = { kind = "unit", uid = entry.uid }
		F.glowLanes({ { team = entry.team, lane = entry.lane, row = entry.row, color = Color3.fromRGB(150, 200, 255) } })
		local text = c.name
		if c.sparkText then
			text = text .. ": " .. c.sparkText .. (spark and "" or (entry.data and entry.data.sparked and " (already Sparked)" or " (not enough magic)"))
		end
		ui.promptText.TextScaled = true
		F.prompt(text, options)
	end

	---------------------------------------------------------------------------
	-- Dragging a card onto the table
	--
	-- Press a card in your hand and drag it: once it has moved a little, a small copy follows the
	-- pointer and your lanes light up; let go over a lane (or a target) to play it there. Spells
	-- that don't aim are played by letting go anywhere above your hand. A press without moving is
	-- still a click (click the card, then the lane).
	---------------------------------------------------------------------------

	local DRAG_START = 12 -- pixels before a press turns into a drag
	local okGuiService, GuiService = pcall(function()
		return game:GetService("GuiService")
	end)
	-- Input positions leave out the bar at the top of the screen; the table and our GUI count it.
	local function toViewport(p)
		if okGuiService and GuiService then
			local ok, inset = pcall(function()
				return GuiService:GetGuiInset()
			end)
			if ok and typeof(inset) == "Vector2" then
				return p + inset
			end
		end
		return p
	end

	function F.pointer()
		if S.drag and S.drag.touchPos then
			return S.drag.touchPos
		end
		return UserInputService:GetMouseLocation()
	end

	function F.dragBegin(uid, id, screenPos)
		if not F.myTurn() then
			return
		end
		S.drag = { uid = uid, id = id, start = toViewport(screenPos), started = false }
	end

	function F.dragUpdate()
		local d = S.drag
		if not d then
			return
		end
		local p = F.pointer()
		if not d.started then
			if (p - d.start).Magnitude < DRAG_START then
				return
			end
			local a = F.myTurn() and F.legal("play", "handUid", d.uid)
			if not a then
				S.drag = nil
				return
			end
			d.started = true
			local c = CardData.Cards[d.id]
			-- Creatures, buildings and aimed spells light up where they can go.
			if c.type ~= "Spell" or a.needsTarget then
				F.onCardClicked(d.uid)
				ui.promptBar.Visible = false
			end
			local cost = nil
			for _, h in ipairs(S.view.hand) do
				if h.uid == d.uid then
					cost = h.cost
				end
			end
			d.ghost = ctx.makeCard(ui.matchUI, d.id, UDim2.fromOffset(96, 134), cost, "compact")
			d.ghost.Name = "DragCard"
			d.ghost.AnchorPoint = Vector2.new(0.5, 0.6)
			d.ghost.Rotation = -4
			d.ghost.ZIndex = 25
		end
		if d.ghost then
			d.ghost.Position = UDim2.fromOffset(p.X, p.Y)
			-- over a spot, the see-through creature on the table shows where it goes instead
			d.ghost.Visible = not (S.ghost and S.ghost.spot)
		end
	end

	function F.dragEnd()
		local d = S.drag
		if not d then
			return
		end
		local p = F.pointer()
		S.drag = nil
		if not d.started then
			return
		end
		if d.ghost then
			d.ghost:Destroy()
		end
		-- Letting go over the same card would also count as a click on it; skip that one.
		S.dragDropped = true
		task.delay(0.25, function()
			S.dragDropped = false
		end)
		local a = F.myTurn() and F.legal("play", "handUid", d.uid)
		if not a then
			F.clearPick()
			return
		end
		local c = CardData.Cards[d.id]
		if c.type == "Spell" and not a.needsTarget then
			local height = camera.ViewportSize and camera.ViewportSize.Y or 720
			if p.Y < height - 190 then
				F.send({ kind = "play", handUid = d.uid })
			end
			return
		end
		local before = S.pick and S.pick.handUid == d.uid and S.pick.step
		local hit = F.boardAt(p.X, p.Y, true)
		if before and ((hit and hit.lane) or (S.ghost and S.ghost.spot)) then
			F.onBoardClick(hit or {})
		end
		-- Missed: put it back (unless it went on to pick a target).
		if S.pick and S.pick.handUid == d.uid and S.pick.step == before then
			F.clearPick()
		end
	end

	UserInputService.InputChanged:Connect(function(input)
		if S.drag and input.UserInputType == Enum.UserInputType.Touch then
			S.drag.touchPos = toViewport(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if S.drag and (t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch) then
			if t == Enum.UserInputType.Touch then
				S.drag.touchPos = toViewport(Vector2.new(input.Position.X, input.Position.Y))
			end
			F.dragEnd()
		end
	end)

	-- Cards you could still play this turn.
	function F.countPlayable()
		local n = 0
		for _, a in ipairs(S.view and S.view.legal or {}) do
			if a.kind == "play" then
				n += 1
			end
		end
		return n
	end

	-- BATTLE ends your turn. If you haven't done anything yet and could still play cards, the first
	-- press only says so (a misclick on the first turn is the easiest way to throw a match).
	function F.pressBattle()
		if not F.myTurn() then
			return
		end
		local playable = F.countPlayable()
		if playable > 0 and not S.actedThisTurn and clock() > (S.battleArmedUntil or 0) then
			S.battleArmedUntil = clock() + 3
			ui.battleButton.Text = "Sure? Again ⚔"
			F.notice("You can still play " .. playable .. " card" .. (playable == 1 and "" or "s") .. ". Press BATTLE again to end your turn.", Color3.fromRGB(255, 220, 120))
			task.delay(3, function()
				if S.view and clock() >= (S.battleArmedUntil or 0) then
					F.refreshButtons()
				end
			end)
			return
		end
		F.send({ kind = "battle" })
	end

	function F.pressLeave()
		local over = not S.view or S.view.over
		if over or clock() <= (S.leaveArmedUntil or 0) then
			S.leaveArmedUntil = 0
			MenuAction:FireServer("LeaveMatch")
			return
		end
		S.leaveArmedUntil = clock() + 3
		local team = S.view.mode == "Team"
		ui.leaveButton.Text = team and "Leave? (click again)" or "Forfeit? (click again)"
		F.notice(team and "If you leave, a bot takes your seat." or "Leaving now gives the match away.", Color3.fromRGB(255, 170, 170))
		task.delay(3, function()
			if clock() >= (S.leaveArmedUntil or 0) then
				ui.leaveButton.Text = "Leave match"
			end
		end)
	end

	-- F with nothing picked: if exactly one creature can Spark, pick it (F again Sparks it).
	function F.pressSpark()
		if not F.myTurn() then
			return
		end
		if S.pick and S.pick.kind == "unit" then
			if F.legal("spark", "uid", S.pick.uid) then
				F.send({ kind = "spark", uid = S.pick.uid })
			end
			return
		end
		local sparks = {}
		for _, a in ipairs(S.view.legal or {}) do
			if a.kind == "spark" and S.units[a.uid] then
				table.insert(sparks, a.uid)
			end
		end
		if #sparks == 1 then
			F.selectCreature(S.units[sparks[1]])
		elseif #sparks > 1 then
			F.log("Click the creature you want to Spark (the shimmering ones can).", Color3.fromRGB(220, 170, 255))
		end
	end

	-- Your hand in the order it's shown (for the number keys).
	function F.handInOrder()
		local list = {}
		for uid, holder in pairs(S.handCards) do
			table.insert(list, { uid = uid, order = holder.LayoutOrder })
		end
		table.sort(list, function(a, b)
			return a.order < b.order
		end)
		local out = {}
		for i, e in ipairs(list) do
			out[i] = e.uid
		end
		return out
	end

	function F.toggleHelp()
		ui.helpPanel.Visible = not ui.helpPanel.Visible
	end

	function F.toggleMenu()
		ui.menuPanel.Visible = not ui.menuPanel.Visible
	end

	function F.setSound(on, save)
		S.soundOn = on
		ui.soundButton.Text = on and "🔊 Sound: On" or "🔇 Sound: Off"
		if save and ctx.prefs then
			ctx.prefs.set("Sound", on)
		end
	end

	function F.setLog(on)
		ui.logFrame.Visible = on
		ui.logButton.Text = on and "📜 Match log: On" or "📜 Match log: Off"
	end

	function F.setFast(on, save)
		S.fast = on
		ui.speedButton.Text = on and "⏩ Speed: Fast" or "⏩ Speed: Normal"
		PACE = BASE_PACE * (S.fast and FAST_PACE or 1)
		if ctx.setPace then
			ctx.setPace(PACE)
		end
		if ctx.getMode() == "match" then
			MatchAction:FireServer({ kind = "speed", fast = on })
		end
		if save and ctx.prefs then
			ctx.prefs.set("Fast", on)
		end
	end

	-- The Table speed setting (Slow / Normal / Fast in Settings): the pace everything is played at,
	-- before the ⏩ toggle in the ⚙ menu speeds it up further.
	function MatchScreen.setBasePace(p)
		BASE_PACE = p
		PACE = BASE_PACE * (S.fast and FAST_PACE or 1)
		if ctx.setPace then
			ctx.setPace(PACE)
		end
	end

	function MatchScreen.toggleMenu()
		F.toggleMenu()
	end

	-- The part to show an emote bubble over: your hero (mine = true) or the other side's first one.
	function MatchScreen.heroPart(mine)
		if not S.view then
			return nil
		end
		for seat, entry in pairs(S.heroes) do
			local sv = S.view.seats[seat]
			if sv and (sv.team == S.myTeam) == mine and entry.model and entry.model.Parent then
				return entry.model.PrimaryPart or entry.model:FindFirstChildWhichIsA("BasePart")
			end
		end
		return nil
	end

	-- Your saved settings (DeckWarsClient calls this when they arrive from the server).
	function MatchScreen.applyPrefs(prefs)
		local sound = prefs.get("Sound")
		if sound ~= nil and (sound == true) ~= (S.soundOn == true) then
			F.setSound(sound == true, false)
		end
		local fast = prefs.get("Fast")
		if fast ~= nil and (fast == true) ~= (S.fast == true) then
			F.setFast(fast == true, false)
		end
	end

	-- Keys (with a keyboard). Returns true if the key did something here.
	local NUMBER_KEYS = {}
	for i, name in ipairs({ "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
		NUMBER_KEYS[Enum.KeyCode[name]] = i
		NUMBER_KEYS[Enum.KeyCode["Keypad" .. name]] = i
	end
	function MatchScreen.onKey(key)
		if ctx.getMode() ~= "match" or not S.view then
			return false
		end
		local K = Enum.KeyCode
		if key == K.Escape or key == K.Q then
			if ui.helpPanel.Visible then
				ui.helpPanel.Visible = false
			elseif ui.menuPanel.Visible then
				ui.menuPanel.Visible = false
			else
				F.clearPick()
			end
		elseif key == K.Slash or key == K.H then
			F.toggleHelp()
		elseif key == K.R and ui.resultPanel.Visible then
			F.playAgain()
		elseif key == K.Space or key == K.Return or key == K.KeypadEnter then
			F.pressBattle()
		elseif key == K.B then
			F.pressBigMove()
		elseif key == K.F then
			F.pressSpark()
		elseif NUMBER_KEYS[key] then
			local uid = F.handInOrder()[NUMBER_KEYS[key]]
			if uid then
				F.onCardClicked(uid)
			end
		else
			return false
		end
		return true
	end

	ui.battleButton.Activated:Connect(function()
		F.pressBattle()
	end)
	function F.pressBigMove()
		if not F.myTurn() then
			return
		end
		local a = F.legal("bigmove")
		if not a then
			return
		end
		F.clearPick()
		local hero = CardData.Heroes[S.view.seats[S.view.you].hero]
		if a.targets then
			S.pick = { kind = "bigmove", step = "target", action = a }
			F.targetGlows(a.targets)
			F.prompt(hero.bigMove .. ": pick an enemy lane", {})
		else
			F.send({ kind = "bigmove" })
		end
	end
	ui.bigMoveButton.Activated:Connect(F.pressBigMove)

	---------------------------------------------------------------------------
	-- HUD refresh
	---------------------------------------------------------------------------

	function F.seatName(v, seat)
		return (v.names and v.names[seat] and v.names[seat].name) or (v.seats[seat] and v.seats[seat].name) or ("Player " .. seat)
	end

	function F.refreshButtons()
		local v = S.view
		if not v then
			return
		end
		local mine = v.current == v.you and not v.over
		local can = F.myTurn()
		-- Nothing left to do but battle? Then the button lights up.
		local anything = false
		for _, a in ipairs(v.legal or {}) do
			if a.kind ~= "battle" and a.kind ~= "endturn" then
				anything = true
			end
		end
		S.onlyBattle = can and not anything
		ui.battleButton.AutoButtonColor = can
		ui.battleButton.BackgroundColor3 = not can and Color3.fromRGB(90, 80, 95) or (S.onlyBattle and Color3.fromRGB(235, 110, 50) or Color3.fromRGB(205, 80, 60))
		ui.battleButton.Text = (mine and v.turn == 1) and "End turn" or "⚔ BATTLE!"
		local me = v.seats[v.you]
		local hero = me and CardData.Heroes[me.hero]
		if hero then
			if me.bigMoveUsed then
				ui.bigMoveButton.Text = hero.bigMove .. " (used)"
				ui.bigMoveButton.BackgroundColor3 = Color3.fromRGB(70, 60, 80)
			elseif me.bigMoveReady then
				ui.bigMoveButton.Text = "★ " .. hero.bigMove .. " ready!"
				ui.bigMoveButton.BackgroundColor3 = can and Color3.fromRGB(220, 150, 50) or Color3.fromRGB(150, 110, 60)
			else
				ui.bigMoveButton.Text = "★ " .. hero.bigMove .. " " .. math.min(me.dealt, CardData.BigMoveCharge) .. "/" .. CardData.BigMoveCharge
				ui.bigMoveButton.BackgroundColor3 = Color3.fromRGB(90, 70, 130)
			end
		end
	end

	function F.refreshUI(v)
		local myTeam = v.team
		local enemyTeam = 3 - myTeam
		local mineNames, enemyNames, enemyInfo = {}, {}, {}
		for seat, sv in ipairs(v.seats) do
			local nm = F.seatName(v, seat)
			if sv.team == myTeam then
				table.insert(mineNames, seat == v.you and (nm .. " (you)") or nm)
			else
				table.insert(enemyNames, nm)
				table.insert(enemyInfo, "🃏 " .. sv.handCount .. " in hand   ✨ " .. sv.magic .. "/" .. sv.maxMagic)
			end
		end
		ui.myNames.Text = table.concat(mineNames, " & ")
		ui.enemyNames.Text = table.concat(enemyNames, " & ")
		ui.enemyInfo.Text = table.concat(enemyInfo, "   ")
		local mt, et = v.teams[myTeam], v.teams[enemyTeam]
		if ui.myHp.value ~= mt.hp then
			ui.myHp.value = mt.hp
			F.setBar(ui.myHp, mt.hp, mt.maxHp)
		end
		if ui.enemyHp.value ~= et.hp then
			ui.enemyHp.value = et.hp
			F.setBar(ui.enemyHp, et.hp, et.maxHp)
		end
		local me = v.seats[v.you]
		ui.magicText.Text = "✨ " .. me.magic .. "/" .. me.maxMagic
		ui.deckText.Text = "🃏" .. me.deckCount
		for _, c in ipairs(ui.magicGems:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i = 1, math.max(me.maxMagic, me.magic) do
			local gem = make("Frame", { Size = UDim2.fromOffset(13, 13), Rotation = 45, BackgroundColor3 = i <= me.magic and Color3.fromRGB(120, 200, 255) or Color3.fromRGB(50, 60, 80) }, ui.magicGems)
			corner(gem, 3)
		end
		-- Tournament rounds say which round it is (a bot match needs no label: the name is on the bar).
		ui.matchLabel.Text = (v.mode == "Bot") and "" or (v.label or "")
		if v.over then
			S.turnState = "over"
		elseif v.current == v.you then
			S.turnState = "you"
		else
			S.turnState = "other"
			S.otherName = F.seatName(v, v.current)
			S.otherTeam = v.seats[v.current].team == myTeam
		end
		F.refreshHand(v)
		F.refreshButtons()
	end

	-- Make the 3D table match the view exactly.
	function F.syncBoard(v)
		local present = {}
		for t = 1, 2 do
			for lane, l in ipairs(v.lanes[t]) do
				F.setLandscape(t, lane, l.landscape)
				F.setScrap(t, lane, l.scrap or 0)
				for _, u in ipairs({ l.creature, l.back, l.building }) do
					if u then
						present[u.uid] = true
						local entry = S.units[u.uid]
						if not entry then
							entry = F.spawnUnit(u, true)
						elseif entry.lane ~= u.lane or entry.team ~= u.team or (u.kind == "creature" and entry.row ~= u.row) then
							entry.lane, entry.team, entry.row = u.lane, u.team, u.row
							entry.slot = F.slotOf(u)
							entry.home = F.slotCF(u.team, u.lane, entry.slot)
							entry.model:PivotTo(entry.home)
						end
						entry.owner = u.owner
						F.setStats(entry, u)
					end
				end
			end
		end
		for uid in pairs(S.units) do
			if not present[uid] then
				F.removeUnit(uid, "quick")
			end
		end
	end

	---------------------------------------------------------------------------
	-- Playback: one event at a time
	---------------------------------------------------------------------------

	local ANIM = {}

	local function unitText(e, text, color)
		local entry = S.units[e.uid]
		if entry then
			F.floatText(F.unitPosition(entry) + Vector3.new(0, 0.4, 0), text, color)
		end
	end

	ANIM.turn = function(e)
		local v = S.view
		F.clearPick()
		local mine = e.seat == v.you
		local nm = F.seatName(v, e.seat)
		if mine then
			S.actedThisTurn = false
			S.battleArmedUntil = 0
			F.banner("Your turn", 0.9, Color3.fromRGB(170, 255, 190))
			F.sound("ding", { volume = 0.6 })
		end
		F.log("— " .. nm .. "'s turn (" .. e.magic .. " magic) —", Color3.fromRGB(200, 200, 230))
		F.step(mine and 0.5 or 0.3)
	end

	ANIM.draw = function(e)
		if e.seat == S.view.you and e.id then
			F.log("You draw " .. cardName(e.id) .. ".", Color3.fromRGB(190, 230, 255))
		end
	end

	ANIM.burn = function(e)
		F.log((e.seat == S.view.you and "Your" or (F.seatName(S.view, e.seat) .. "'s")) .. " hand is full: a card burns" .. (e.id and (" (" .. cardName(e.id) .. ")") or "") .. ".", Color3.fromRGB(255, 170, 120))
	end

	ANIM.fatigue = function(e)
		F.log(F.seatName(S.view, e.seat) .. " has no cards left: " .. e.amount .. " damage!", Color3.fromRGB(255, 140, 140))
	end

	ANIM.play = function(e)
		local v = S.view
		local mine = e.seat == v.you
		if mine and S.stats then
			S.stats.played += 1
		end
		F.log(F.seatName(v, e.seat) .. " plays " .. cardName(e.id) .. ".", mine and Color3.fromRGB(170, 255, 180) or Color3.fromRGB(255, 200, 170))
		if not mine then
			-- Show what the other side played, like turning their card over.
			F.popup(e.id, 1.2, true)
			F.step(0.9)
		end
	end

	ANIM.summon = function(e)
		local u = e.unit
		if e.replaced then
			F.removeUnit(e.replaced)
		end
		F.spawnUnit(u)
		F.sound("thudSmall", { volume = 0.7 })
		F.step(e.how == "play" and 0.5 or 0.3)
	end

	ANIM.build = function(e)
		if e.replaced then
			F.removeUnit(e.replaced)
		end
		F.spawnUnit(e.unit)
		F.sound("thudSmall", { volume = 0.6, pitch = 0.85 })
		F.step(0.4)
	end

	ANIM.spell = function(e)
		local v = S.view
		if e.seat == v.you then
			F.popup(e.id, 1.0, false)
		end
		if e.target then
			F.glowLanes({ { team = e.target.team, lane = e.target.lane, color = Color3.fromRGB(200, 140, 255) } })
		end
		F.step(0.7)
		F.glowLanes({})
	end

	ANIM.spark = function(e)
		local entry = S.units[e.uid]
		if S.view and e.seat == S.view.you and S.stats then
			S.stats.sparks += 1
		end
		F.log(F.seatName(S.view, e.seat) .. " Sparks " .. cardName(e.id) .. "!", Color3.fromRGB(220, 170, 255))
		if entry then
			F.floatText(F.unitPosition(entry), "SPARK!", Color3.fromRGB(220, 160, 255), true)
			F.sound("swish", { volume = 0.6 })
			local home = entry.home
			entry.busy = true
			F.tween(0.5, function(a)
				if entry.model.Parent then
					entry.model:PivotTo(home * CFrame.new(0, math.sin(a * math.pi) * 0.8, 0) * CFrame.Angles(0, a * math.pi * 2, 0))
				end
			end, function()
				entry.busy = false
			end)
		end
		F.step(0.6)
	end

	ANIM.move = function(e)
		local entry = S.units[e.uid]
		if entry then
			F.moveUnit(entry, e.to, e.team, e.toRow)
			if e.how == "stepUp" then
				unitText(e, "⬆ Steps up", Color3.fromRGB(200, 230, 255))
			end
		end
		F.step(e.how == "swap" and 0.25 or 0.45)
	end

	-- Shift: a creature trades rows in its lane (the move events right after it do the moving).
	ANIM.shift = function(e)
		local entry = S.units[e.uid]
		if entry then
			F.log(F.seatName(S.view, e.seat) .. " shifts " .. cardName(entry.id) .. ".", Color3.fromRGB(200, 230, 255))
			unitText(e, "↕ Shift", Color3.fromRGB(200, 230, 255))
			F.sound("swish", { volume = 0.4, pitch = 1.2 })
		end
		F.step(0.2)
	end

	-- Overkill: the damage left over after a creature falls rolls on down the lane.
	ANIM.overkill = function(e)
		local entry = S.units[e.uid]
		local pos = entry and F.unitPosition(entry) or (S.pads[e.team] and S.pads[e.team][e.lane] and S.pads[e.team][e.lane].creature.Position)
		if pos then
			F.floatText(pos + Vector3.new(0, 0.9, 0), "Overkill " .. tostring(e.amount) .. (e.toHero and " → hero!" or " →"), Color3.fromRGB(255, 160, 90))
		end
		F.step(0.2)
	end

	ANIM.battle = function(e)
		if e.skipped then
			F.log("No battle on the very first turn.", Color3.fromRGB(200, 200, 220))
			return
		end
		F.sound("whooshShort", { volume = 0.6 })
		F.step(0.3)
	end

	ANIM.attack = function(e)
		local entry = S.units[e.uid]
		if not entry then
			return
		end
		local target = e.target and S.units[e.target]
		local targetPos
		if target then
			targetPos = target.home.Position
		else
			targetPos = F.heroPos(e.hero or (3 - entry.team))
		end
		local home = entry.home
		local toward = (targetPos - home.Position) * Vector3.new(1, 0, 1)
		local reach = math.min(toward.Magnitude * 0.55, 3.2)
		local dir = toward.Magnitude > 0.01 and toward.Unit or Vector3.new(0, 0, -1)
		entry.busy = true
		F.tween(0.22, function(a)
			if entry.model.Parent then
				entry.model:PivotTo(home + dir * reach * a + Vector3.new(0, math.sin(a * math.pi) * 0.4, 0))
			end
		end)
		F.step(0.24)
		-- The hit: a thump, and the target rocks back a little.
		F.sound("punch", { volume = 0.55, pitch = 0.9 + math.random() * 0.2 })
		if target then
			F.knock(target, dir)
		end
		F.tween(0.25, function(a)
			if entry.model.Parent then
				entry.model:PivotTo(home + dir * reach * (1 - a))
			end
		end, function()
			entry.busy = false
		end)
		F.step(0.15)
	end

	ANIM.damage = function(e)
		local entry = S.units[e.uid]
		if entry then
			if e.amount > 0 then
				F.floatText(F.unitPosition(entry), "-" .. e.amount, Color3.fromRGB(255, 90, 90), e.amount >= 4)
				F.flashModel(entry.model, Color3.fromRGB(255, 60, 60), 0.3)
			else
				F.floatText(F.unitPosition(entry), "0", Color3.fromRGB(200, 200, 200))
			end
			if entry.data then
				entry.data.hp = e.hp
				F.setStats(entry, entry.data)
			end
		end
		F.step(0.18)
	end

	ANIM.heroDamage = function(e)
		local pos = F.heroPos(e.team)
		F.floatText(pos + Vector3.new(0, 1, 0), "-" .. e.amount, Color3.fromRGB(255, 70, 70), true)
		F.sound("thud", { volume = 0.6 })
		local bar = e.team == S.myTeam and ui.myHp or ui.enemyHp
		bar.value = e.hp
		F.setBar(bar, e.hp, S.view.teams[e.team].maxHp)
		for seat, h in pairs(S.heroes) do
			if S.view.seats[seat].team == e.team then
				F.flashModel(h.model, Color3.fromRGB(255, 60, 60), 0.35)
			end
		end
		F.step(0.35)
	end

	ANIM.heroHeal = function(e)
		if e.amount <= 0 then
			return
		end
		local pos = F.heroPos(e.team)
		F.floatText(pos + Vector3.new(0, 1, 0), "+" .. e.amount, Color3.fromRGB(120, 255, 140), true)
		local bar = e.team == S.myTeam and ui.myHp or ui.enemyHp
		bar.value = e.hp
		F.setBar(bar, e.hp, S.view.teams[e.team].maxHp)
		F.step(0.25)
	end

	ANIM.heal = function(e)
		local entry = S.units[e.uid]
		if entry and e.amount > 0 then
			F.floatText(F.unitPosition(entry), "+" .. e.amount, Color3.fromRGB(120, 255, 140))
			F.step(0.15)
		end
	end

	ANIM.pop = function(e)
		F.removeUnit(e.uid)
		F.sound("bonk", { volume = 0.45 })
		F.step(0.35)
	end

	ANIM.wreck = function(e)
		F.removeUnit(e.uid)
		F.step(0.3)
	end

	ANIM.bounce = function(e)
		F.removeUnit(e.uid, "bounce")
		F.step(0.35)
	end

	ANIM.stats = function(e)
		local entry = S.units[e.unit.uid]
		if entry then
			F.setStats(entry, e.unit)
		end
	end

	ANIM.buff = function(e)
		local bits = {}
		if e.atk ~= 0 then
			table.insert(bits, (e.atk > 0 and "+" or "") .. e.atk .. " ⚔")
		end
		if e.hp ~= 0 then
			table.insert(bits, (e.hp > 0 and "+" or "") .. e.hp .. " ❤")
		end
		unitText(e, table.concat(bits, " "), Color3.fromRGB(140, 255, 160))
		F.step(0.12)
	end
	ANIM.power = function(e)
		unitText(e, "+" .. e.amount .. " ⚡ Power", Color3.fromRGB(255, 230, 110))
		F.step(0.1)
	end
	ANIM.soak = function(e)
		unitText(e, "💧 Soaked", Color3.fromRGB(120, 190, 255))
		F.step(0.1)
	end
	ANIM.keyword = function(e)
		unitText(e, "+" .. e.keyword, Color3.fromRGB(255, 220, 140))
		F.step(0.1)
	end
	ANIM.wash = function(e)
		unitText(e, "🧼 Washed!", Color3.fromRGB(200, 240, 255))
		F.step(0.2)
	end
	ANIM.shield = function(e)
		unitText(e, "🛡 Bubble Wrap", Color3.fromRGB(200, 240, 255))
	end
	ANIM.blocked = function(e)
		unitText(e, "🛡 Blocked!", Color3.fromRGB(200, 240, 255))
		F.step(0.15)
	end
	ANIM.freeze = function(e)
		unitText(e, "❄ Frozen", Color3.fromRGB(180, 230, 255))
	end
	ANIM.thaw = function(e)
		unitText(e, "❄ Thaws (skips this attack)", Color3.fromRGB(180, 230, 255))
		F.step(0.2)
	end
	ANIM.boo = function(e)
		unitText(e, "👻 Boo! -attack", Color3.fromRGB(220, 180, 255))
	end
	ANIM.grudge = function(e)
		F.log("Grudge! It hits back on the way out.", Color3.fromRGB(220, 160, 255))
	end
	ANIM.scrap = function(e)
		F.setScrap(e.team, e.lane, e.amount)
	end
	ANIM.landscape = function(e)
		F.setLandscape(e.team, e.lane, e.family)
		F.step(0.15)
	end
	ANIM.magic = function(e)
		if e.seat == S.view.you then
			F.log("+1 magic (" .. e.magic .. " now).", Color3.fromRGB(150, 210, 255))
		end
	end
	ANIM.ability = function(e)
		local entry = S.units[e.uid]
		if entry then
			F.floatText(F.unitPosition(entry) + Vector3.new(0, 0.6, 0), cardName(e.id) .. "!", Color3.fromRGB(255, 230, 150))
			F.flashModel(entry.model, Color3.fromRGB(255, 230, 150), 0.3)
		end
		F.step(0.25)
	end
	ANIM.roll = function(e)
		ui.rollText.Text = "🎲 " .. cardName(e.id) .. ": " .. tostring(e.result)
		ui.rollText.Visible = true
		F.log("🎲 " .. cardName(e.id) .. ": " .. tostring(e.result), Color3.fromRGB(255, 230, 120))
		F.step(0.8)
		ui.rollText.Visible = false
	end
	ANIM.bigmove = function(e)
		local hero = CardData.Heroes[e.hero]
		F.banner("★ " .. (hero and hero.bigMove or "Big Move") .. "!", 1.2, Color3.fromRGB(255, 200, 80))
		F.sound("gong", { volume = 0.5 })
		F.log(F.seatName(S.view, e.seat) .. " uses " .. (hero and hero.bigMove or "a Big Move") .. "!", Color3.fromRGB(255, 210, 120))
		F.step(1.0)
	end
	ANIM.win = function(e)
		F.step(0.3)
	end

	function F.animate(e)
		local fn = ANIM[e.type]
		if fn then
			fn(e)
		end
	end

	-- How long the result stays up before the server sends everyone back (MatchServer's
	-- RESULT_SCREEN_SECONDS), for the countdown.
	local RESULT_SECONDS = 12

	function F.playAgain()
		if not (S.view and S.view.over and S.view.mode == "Bot") or S.rematchSent then
			return
		end
		S.rematchSent = true
		local b = ui.resultButtons:FindFirstChild("PlayAgain")
		if b then
			b.Text = "Shuffling…"
			b.AutoButtonColor = false
		end
		MenuAction:FireServer("Rematch")
	end

	-- Everything that starts fresh with each match (also a rematch or the next tournament round).
	function F.resetMatchState()
		S.stats = { played = 0, sparks = 0 }
		S.actedThisTurn = false
		S.battleArmedUntil = 0
		S.leaveArmedUntil = 0
		S.warnedTurn = nil
		S.onlyBattle = false
		S.resultAt = nil
		S.rematchSent = false
		S.drag = nil
		ui.leaveButton.Text = "Leave match"
		ui.resultPanel.Visible = false
		ui.helpPanel.Visible = false
		ui.menuPanel.Visible = false
		ui.toast.Visible = false
		ui.coach.Visible = false
		ui.handFrame.Visible = true
		if S.fast then
			MatchAction:FireServer({ kind = "speed", fast = true })
		end
	end

	-- One line on the result screen (a reward, a quest...).
	function F.rewardRow(text, color, order)
		return label(ui.resultRewards, text, { Size = UDim2.new(1, 0, 0, 22), Font = BODY_FONT, TextScaled = false, TextSize = 16, TextColor3 = color or WHITE, LayoutOrder = order, ZIndex = 31 })
	end

	-- Your level bar on the result screen: it fills with the match's XP (and rolls over on a level up).
	function F.xpBar(r, order)
		local row = make("Frame", { Name = "XPRow", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 31 }, ui.resultRewards)
		local lvl = label(row, "Level " .. r.levelBefore, { Name = "Level", Size = UDim2.fromOffset(90, 26), Position = UDim2.fromOffset(0, 2), TextColor3 = Color3.fromRGB(255, 220, 120), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 31 })
		local back = make("Frame", { Size = UDim2.new(1, -180, 0, 16), Position = UDim2.fromOffset(94, 7), BackgroundColor3 = Color3.fromRGB(62, 54, 92), ZIndex = 31 }, row)
		corner(back, 8)
		local need = Progression.xpForLevel(r.levelBefore)
		local fill = make("Frame", { Name = "Fill", Size = UDim2.fromScale(math.clamp(r.xpBefore / need, 0, 1), 1), BackgroundColor3 = Color3.fromRGB(130, 200, 255), ZIndex = 32 }, back)
		corner(fill, 8)
		label(row, "+" .. r.xp .. " XP", { Size = UDim2.fromOffset(80, 26), Position = UDim2.new(1, -80, 0, 2), TextColor3 = Color3.fromRGB(150, 210, 255), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 31 })
		task.delay(0.4 * PACE, function()
			if r.levelAfter > r.levelBefore then
				TweenService:Create(fill, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 1) }):Play()
				task.delay(0.55, function()
					if not fill.Parent then
						return
					end
					lvl.Text = "Level " .. r.levelAfter
					fill.Size = UDim2.fromScale(0, 1)
					TweenService:Create(fill, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(r.xpAfter / Progression.xpForLevel(r.levelAfter), 0, 1), 1) }):Play()
					F.sound("ding", { volume = 0.8, pitch = 1.2 })
				end)
			else
				TweenService:Create(fill, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(r.xpAfter / Progression.xpForLevel(r.levelAfter), 0, 1), 1) }):Play()
			end
		end)
	end

	-- "Next" / "Try again" on a campaign result (the server starts the stage).
	function F.campaignAgain(what)
		if S.rematchSent then
			return
		end
		S.rematchSent = true
		for _, b in ipairs(ui.resultButtons:GetChildren()) do
			if b:IsA("TextButton") then
				b.AutoButtonColor = false
			end
		end
		local b = ui.resultButtons:FindFirstChild(what)
		if b then
			b.Text = "Shuffling…"
		end
		MenuAction:FireServer(what)
	end

	-- The campaign part of the result: the three stars (new ones pop in), first-clear and drop
	-- cards, chests, titles and what opened.
	function F.campaignResult(c)
		if ctx.onCampaignResult then
			pcall(ctx.onCampaignResult, c) -- (the Campaign map takes the new save straight away)
		end
		local camp = S.campaign or {}
		local texts = camp.stars or { "Win", "Win with half your hit points left", "Win in time" }
		local row = make("Frame", { Name = "CampaignStars", Size = UDim2.new(1, 0, 0, 74), BackgroundTransparency = 1, LayoutOrder = 1, ZIndex = 31 }, ui.resultRewards)
		local before = tonumber(c.starsBefore) or 0
		for i = 1, 3 do
			local got = c.stars and c.stars[i] == true
			local had = bit32.band(before, bit32.lshift(1, i - 1)) ~= 0
			local cell = make("Frame", { Name = "Star" .. i, Size = UDim2.new(1 / 3, -6, 1, 0), Position = UDim2.new((i - 1) / 3, 3, 0, 0), BackgroundTransparency = 1, ZIndex = 31 }, row)
			local star = label(cell, (got or had) and "★" or "☆", { Name = "Glyph", Size = UDim2.new(1, 0, 0, 40), TextScaled = false, TextSize = 38, TextColor3 = (got or had) and Color3.fromRGB(255, 214, 80) or Color3.fromRGB(110, 104, 140), ZIndex = 32 })
			label(cell, texts[i] or "", { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 42), Font = BODY_FONT, TextScaled = false, TextSize = 12, TextWrapped = true, TextColor3 = got and WHITE or Color3.fromRGB(170, 165, 195), ZIndex = 32 })
			if got and not had then
				star.TextTransparency = 1
				task.delay((0.3 + 0.35 * i) * PACE, function()
					if star.Parent then
						star.TextTransparency = 0
						local sc = make("UIScale", { Scale = 2.2 }, star)
						TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
						F.sound("ding", { volume = 0.5, pitch = 1 + 0.15 * i })
					end
				end)
			end
		end
		local order = 2
		for _, card in ipairs(c.cards or {}) do
			local def = CardData.Cards[card.id]
			if def then
				order += 1
				local col = CardData.RarityColors[def.rarity] or { 255, 255, 255 }
				F.rewardRow("🃏 " .. tostring(card.why) .. ": " .. def.name .. " (" .. def.rarity .. ")" .. (card.isNew and "  NEW!" or ""), Color3.fromRGB(col[1], col[2], col[3]), order)
			end
		end
		for _, t in ipairs(c.titles or {}) do
			order += 1
			F.rewardRow("🏅 New title: " .. t, Color3.fromRGB(255, 220, 120), order)
		end
		for _, u in ipairs(c.unlocked or {}) do
			order += 1
			F.rewardRow("🔓 " .. u, Color3.fromRGB(150, 255, 170), order)
		end
	end

	function F.showResult(payload)
		local r = payload.result
		local title = r == "win" and "VICTORY!" or (r == "draw" and "DRAW" or "DEFEAT")
		ui.resultTitle.Text = title
		ui.resultTitle.TextColor3 = r == "win" and Color3.fromRGB(255, 220, 90) or (r == "draw" and WHITE or Color3.fromRGB(255, 130, 130))
		local text = r == "win" and "Your creatures win the day!" or (r == "draw" and "Nobody wins this time." or "Good try! Every match still counts for your level and quests.")
		if S.view and S.view.mode == "Cup" then
			text = r == "win" and "You go through to the next round!" or "You're out of the tournament."
		end
		ui.resultText.Text = text
		-- How the match went.
		local v = S.view
		local me = v and v.seats[v.you]
		local st = S.stats or { played = 0, sparks = 0 }
		ui.resultStats.Text = string.format("%d turns · %d cards played · %d Sparks · %d damage dealt", v and v.turn or 0, st.played, st.sparks, me and me.dealt or 0)
		-- What you earned: Gems line by line, then your level bar, then the quests this match moved.
		for _, c in ipairs(ui.resultRewards:GetChildren()) do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		local rw = payload.rewards
		if type(rw) == "table" then
			local order = 10
			for i, g in ipairs(rw.gems or {}) do
				order += 1
				local row = F.rewardRow("+" .. g.amount .. " 💎  " .. g.label, Color3.fromRGB(130, 220, 255), order)
				row.TextTransparency = 1
				task.delay((0.25 + 0.3 * i) * PACE, function()
					if row.Parent then
						TweenService:Create(row, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()
						F.sound("ding", { volume = 0.35, pitch = 0.9 + 0.1 * i })
					end
				end)
			end
			for _, up in ipairs(rw.levelUps or {}) do
				order += 1
				F.rewardRow("+" .. up.gems .. " 💎  Level " .. up.level .. "!", Color3.fromRGB(255, 220, 120), order)
			end
			if (tonumber(rw.trophies) or 0) > 0 then
				order += 1
				F.rewardRow("+" .. rw.trophies .. " 🏆  Trophy Road", Color3.fromRGB(255, 196, 90), order)
			end
			if rw.levelBefore then
				order += 1
				F.xpBar(rw, order)
			end
			for _, q in ipairs(rw.quests or {}) do
				local def = Progression.QuestById[q.id]
				if def then
					order += 1
					local done = q.progress >= q.target
					F.rewardRow((done and "✅ " or "📜 ") .. def.text .. "  " .. q.progress .. "/" .. q.target .. (done and "  (claim it on the Trophy Wall)" or ""), done and Color3.fromRGB(140, 255, 160) or Color3.fromRGB(220, 215, 235), order)
				end
			end
		elseif payload.gemsEarned then
			F.rewardRow("+" .. payload.gemsEarned .. " 💎 Gems", Color3.fromRGB(130, 220, 255), 1)
		end
		if type(rw) == "table" and type(rw.campaign) == "table" then
			F.campaignResult(rw.campaign)
		end
		-- What next.
		for _, c in ipairs(ui.resultButtons:GetChildren()) do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		local mode = v and v.mode
		local function leave()
			MenuAction:FireServer("LeaveMatch")
		end
		if mode == "Campaign" then
			local won = r == "win"
			local camp = S.campaign
			local isChallenge = camp and type(camp.id) == "string" and string.sub(camp.id, 1, 10) == "Challenge:"
			if won and not isChallenge then
				button(ui.resultButtons, "Next ▶", Color3.fromRGB(60, 170, 90), function()
					F.campaignAgain("CampaignNext")
				end, { Name = "CampaignNext", Size = UDim2.fromOffset(150, 46), LayoutOrder = 1 })
			end
			button(ui.resultButtons, won and "⟳ Again" or "⟳ Try again", won and Color3.fromRGB(70, 130, 220) or Color3.fromRGB(60, 170, 90), function()
				F.campaignAgain("CampaignRetry")
			end, { Name = "CampaignRetry", Size = UDim2.fromOffset(won and 130 or 170, 46), LayoutOrder = 2 })
			button(ui.resultButtons, "Map", Color3.fromRGB(90, 80, 140), leave, { Name = "BackToMap", Size = UDim2.fromOffset(110, 46), LayoutOrder = 3 })
			S.resultBack = "Back to the map"
		elseif mode == "Bot" then
			button(ui.resultButtons, "⟳ Play again", Color3.fromRGB(60, 170, 90), F.playAgain, { Name = "PlayAgain", Size = UDim2.fromOffset(200, 46), LayoutOrder = 1 })
			button(ui.resultButtons, "Back", Color3.fromRGB(90, 80, 140), leave, { Name = "BackToRoom", Size = UDim2.fromOffset(140, 46), LayoutOrder = 2 })
			S.resultBack = "Back at the Duel Table"
		elseif mode == "Duel" or mode == "Team" then
			button(ui.resultButtons, "Back to the table", Color3.fromRGB(70, 130, 220), leave, { Name = "BackToTable", Size = UDim2.fromOffset(220, 46), LayoutOrder = 1 })
			S.resultBack = "Back at the table"
		else
			button(ui.resultButtons, "OK", Color3.fromRGB(70, 130, 220), leave, { Name = "BackToRoom", Size = UDim2.fromOffset(140, 46), LayoutOrder = 1 })
			S.resultBack = "Back to the room"
		end
		S.resultAt = clock() + RESULT_SECONDS
		ui.menuPanel.Visible = false
		ui.coach.Visible = false
		ui.handFrame.Visible = false -- the match is over: just the result
		ui.resultPanel.Visible = true
		if r == "win" then
			F.sound("sting3", { volume = 0.8 })
		end
	end

	function F.handleUpdate(payload)
		local first = S.view == nil or payload.started
		S.view = payload.view
		S.turnEndsAt = tonumber(S.view.turnEndsAt) or 0
		if first then
			S.myTeam = S.view.team
			F.buildBoard(S.view)
			F.placeHeroes(S.view)
			F.placeBotAvatar(S.view)
			F.clearHand()
			for uid in pairs(S.units) do
				F.removeUnit(uid, "quick")
			end
			local firstName = F.seatName(S.view, payload.firstSeat or S.view.current)
			local opening = (payload.firstSeat == S.view.you) and "You go first" or (firstName .. " goes first")
			if payload.cupRound then
				opening = payload.cupRound .. ": " .. opening
			end
			local camp = payload.campaign or S.campaign
			if camp and payload.started then
				-- the stage's name and rules first
				F.banner(camp.title, 1.6, Color3.fromRGB(255, 214, 120))
				F.step(1.3)
				for _, rule in ipairs(camp.rules or {}) do
					F.log((rule.emoji or "•") .. " " .. rule.name .. ": " .. rule.text, Color3.fromRGB(255, 200, 150))
				end
				if camp.boss then
					F.log("👑 Boss: " .. tostring(camp.name) .. " (" .. tostring(camp.enemyHp) .. " hit points)", Color3.fromRGB(255, 180, 120))
				end
			end
			F.banner(opening, 1.4, Color3.fromRGB(255, 225, 140))
			F.step(1.2)
		end
		for _, e in ipairs(payload.events or {}) do
			local ok, err = pcall(F.animate, e)
			if not ok then
				if err == ABORT then
					error(ABORT, 0)
				end
				warn("[MatchScreen] animation error: " .. tostring(err))
			end
		end
		F.syncBoard(S.view)
		if payload.notice then
			F.log(payload.notice, Color3.fromRGB(255, 220, 120))
		end
		if payload.result then
			F.showResult(payload)
		end
	end

	function F.processQueue()
		if S.processing then
			return
		end
		S.processing = true
		local caughtUp = false
		while #S.queue > 0 do
			local payload = table.remove(S.queue, 1)
			S.playing = S.matchId
			local ok, err = pcall(F.handleUpdate, payload)
			if not ok and err ~= ABORT then
				warn("[MatchScreen] update error: " .. tostring(err))
			end
			if S.playing == S.matchId and ctx.getMode() == "match" then
				S.busy = false
				if S.view then
					pcall(F.syncBoard, S.view)
					F.refreshUI(S.view)
					caughtUp = true
				end
				if type(payload.seq) == "number" then
					MatchAction:FireServer({ kind = "ack", seq = payload.seq })
				end
			end
		end
		S.processing = false
		ctx.actionCam.release(0.3)
		if ctx.leanCamera then
			ctx.leanCamera(nil)
		end
		if caughtUp and S.view then
			F.refreshButtons()
		end
	end

	---------------------------------------------------------------------------
	-- Entering and leaving
	---------------------------------------------------------------------------

	function F.enter(payload)
		S.matchId += 1
		S.lastMode = payload and payload.view and payload.view.mode or nil
		S.campaign = payload and payload.campaign or nil
		ctx.setMode("match")
		ctx.onEnterMatch(payload)
		ui.matchUI.Visible = true
		F.resetMatchState()
		S.turnState = "other"
		S.turnEndsAt = 0
		for _, l in ipairs(S.logLines) do
			l:Destroy()
		end
		S.logLines = {}
		S.view = nil
		ui.myHp.value, ui.enemyHp.value = nil, nil
	end

	function F.exit()
		S.matchId += 1
		F.clearPick()
		F.clearHand()
		F.hidePreview()
		ui.popupHolder:ClearAllChildren()
		ui.rollText.Visible = false
		ui.bannerText.Visible = false
		ui.matchUI.Visible = false
		ui.resultPanel.Visible = false
		ui.menuPanel.Visible = false
		if S.drag and S.drag.ghost then
			S.drag.ghost:Destroy()
		end
		S.drag = nil
		for uid in pairs(S.units) do
			F.removeUnit(uid, "quick")
		end
		for _, entry in pairs(S.heroes) do
			if entry.model then
				entry.model:Destroy()
			end
		end
		S.heroes = {}
		if S.botAvatar then
			S.botAvatar:Destroy()
			S.botAvatar = nil
		end
		S.boardFolder:ClearAllChildren()
		F.restoreTableParts()
		S.view = nil
		S.busy = false
		S.queue = {}
		ctx.setMode("menu")
		ctx.onExitMatch(S.lastMode)
	end

	function F.onMatchEvent(payload)
		if type(payload) ~= "table" then
			return
		end
		if S.deferred then
			table.insert(S.deferred, payload)
			return
		end
		if payload.kind == "update" and payload.started and ctx.getMode() == "pull" then
			-- A match started while a pack opening plays (a friend pressed Start): let the
			-- opening finish, then sit down.
			S.deferred = { payload }
			task.spawn(function()
				local waited = 0
				while ctx.getMode() == "pull" and waited < 60 do
					waited += task.wait(0.2)
				end
				local list = S.deferred
				S.deferred = nil
				for _, p in ipairs(list) do
					F.onMatchEvent(p)
				end
			end)
			return
		end
		if payload.kind == "update" then
			if payload.started then
				-- A new match (tournaments start one after another without leaving the screen).
				if ctx.getMode() ~= "match" then
					F.enter(payload)
				else
					S.lastMode = payload.view and payload.view.mode or S.lastMode
					S.campaign = payload.campaign
					S.matchId += 1
					S.queue = {}
					S.view = nil
					F.clearHand()
					F.resetMatchState()
				end
			end
			if ctx.getMode() ~= "match" then
				return
			end
			table.insert(S.queue, payload)
			task.spawn(F.processQueue)
		elseif payload.kind == "timer" then
			if ctx.getMode() == "match" then
				S.turnEndsAt = tonumber(payload.turnEndsAt) or 0
			end
		elseif payload.kind == "error" then
			S.busy = false
			F.notice(tostring(payload.message), Color3.fromRGB(255, 140, 140))
			if S.view then
				F.refreshUI(S.view)
			end
		elseif payload.kind == "ended" then
			if ctx.getMode() == "match" then
				F.exit()
			end
		end
	end
	MatchEvent.OnClientEvent:Connect(F.onMatchEvent)

	---------------------------------------------------------------------------
	-- Mouse and frames
	---------------------------------------------------------------------------

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { S.boardFolder }

	-- What is under a screen point: { team, lane, slot, unit } or { heroSeat } or nil.
	function F.boardAt(x, y, isViewport)
		local ray = isViewport and camera:ViewportPointToRay(x, y) or camera:ScreenPointToRay(x, y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, rayParams)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		local node = inst
		while node and node.Parent and node.Parent ~= S.boardFolder do
			node = node.Parent
		end
		if node and node:GetAttribute("HeroSeat") then
			return { heroSeat = node:GetAttribute("HeroSeat") }
		end
		if node and node:IsA("Model") then
			for _, entry in pairs(S.units) do
				if entry.model == node then
					local slot = entry.slot or entry.kind
					return { team = entry.team, lane = entry.lane, slot = slot, row = F.rowOfSlot(slot), unit = entry }
				end
			end
			return nil
		end
		local team, lane = inst:GetAttribute("Team"), inst:GetAttribute("Lane")
		if team and lane then
			local slot = inst:GetAttribute("Slot")
			local L = S.layout
			local snapped = false
			if slot == "strip" and L then
				-- The ground of a lane: the nearest spot to where the pointer landed.
				local d = math.abs(hit.Position.Z)
				if d >= (L.backZ + L.buildingZ) / 2 then
					slot = "building"
				elseif d >= (L.creatureZ + L.backZ) / 2 then
					slot = "back"
				else
					slot = "creature"
				end
				snapped = true
			end
			local l = S.view and S.view.lanes[team] and S.view.lanes[team][lane]
			local u = l and (slot == "building" and l.building or (slot == "back" and l.back or l.creature))
			return { team = team, lane = lane, slot = slot, row = F.rowOfSlot(slot), unit = u and S.units[u.uid], snapped = snapped }
		end
		return nil
	end

	function MatchScreen.onClick(pos, rightClick)
		if ctx.getMode() ~= "match" or not S.view then
			return
		end
		if rightClick then
			F.clearPick()
			return
		end
		local hit = F.boardAt(pos.X, pos.Y, false)
		if S.pick and S.pick.step == "lane" and S.ghost and S.ghost.spot then
			F.onBoardClick(hit or {}) -- (the placement preview has snapped onto a spot)
		elseif hit and hit.lane then
			F.onBoardClick(hit)
		elseif S.pick and S.pick.kind == "unit" then
			F.clearPick()
		end
	end

	function F.updateHover()
		if not S.view then
			ui.tip.Visible = false
			return
		end
		local m = UserInputService:GetMouseLocation()
		local hit = F.boardAt(m.X, m.Y, true)
		local tip = nil
		if hit and hit.lane then
			local l = S.view.lanes[hit.team][hit.lane]
			local fam = l.landscape
			local where = hit.slot == "building" and "Building slot" or (hit.row == 2 and "Back row" or "Front row")
			tip = where .. " · " .. (CardData.Terrains[fam] or fam) .. " (" .. fam .. " creatures +1 ⚔)"
			if l.scrap and l.scrap > 0 then
				tip = tip .. " · Scrap ×" .. l.scrap
			end
			local owner = l.owner and F.seatName(S.view, l.owner)
			if owner and S.view.teamMode then
				tip = owner .. "'s lane · " .. tip
			end
			if not S.handHover then
				local u = hit.unit and hit.unit.data
				if u then
					F.preview(u.id)
				else
					F.hidePreview()
				end
			end
		elseif hit and hit.heroSeat then
			local sv = S.view.seats[hit.heroSeat]
			local hero = sv and CardData.Heroes[sv.hero]
			if hero then
				tip = hero.name .. " · " .. hero.bigMove .. ": " .. hero.text
			end
		elseif not S.handHover then
			F.hidePreview()
		end
		if tip and not S.handHover then
			ui.tip.Text = tip
			local w = math.clamp(utf8.len(tip) * 8, 160, 620)
			local vp = camera.ViewportSize or Vector2.new(1280, 720)
			local x = m.X + 18
			if x + w > vp.X - 8 then
				x = math.max(8, m.X - w - 12) -- flip to the left of the mouse near the right edge
			end
			ui.tip.Size = UDim2.fromOffset(w, 26)
			ui.tip.Position = UDim2.fromOffset(x, math.min(m.Y + 16, vp.Y - 34))
			ui.tip.Visible = true
		else
			ui.tip.Visible = false
		end
	end

	-- The coach line: what to do next, for a player's first matches (the server counts them in the
	-- MatchesPlayed attribute). After COACH_MATCHES matches it stays out of the way.
	local COACH_MATCHES = 8
	function F.updateCoach()
		local text = nil
		local v = S.view
		local played = player:GetAttribute("MatchesPlayed")
		local learning = type(played) ~= "number" or played < COACH_MATCHES
		if learning and v and not v.over and S.turnState == "you" and not ui.resultPanel.Visible and not ui.helpPanel.Visible then
			if S.processing or S.busy then
				text = nil
			elseif S.drag and S.drag.started then
				text = "Let go over a glowing lane"
			elseif S.pick and S.pick.kind == "card" then
				local c = CardData.Cards[S.pick.id]
				if S.pick.step == "lane" then
					text = c and c.type == "Building" and "Click a glowing lane to build behind it" or "Click one of your glowing lanes"
				else
					text = "Click a glowing target"
				end
			elseif S.pick and S.pick.kind == "bigmove" then
				text = "Click an enemy lane"
			elseif S.pick then
				text = nil -- a creature is picked: its Spark choice is showing
			elseif F.countPlayable() > 0 then
				text = "Drag a card with a green outline onto your lanes"
			elseif S.onlyBattle then
				text = "All done? Press ⚔ BATTLE!"
			else
				text = "Click a glowing creature to Spark it, or press ⚔ BATTLE"
			end
		end
		if text and not ui.promptBar.Visible then
			ui.coach.Text = text
			ui.coach.Visible = true
		else
			ui.coach.Visible = false
		end
	end

	function F.updateTurnText()
		if S.turnState == "you" then
			ui.turnText.Text = "Your turn"
			ui.turnText.TextColor3 = Color3.fromRGB(150, 255, 170)
			if S.turnEndsAt > 0 then
				local left = math.max(0, math.ceil(S.turnEndsAt - workspace:GetServerTimeNow()))
				ui.timerText.Text = left <= 20 and ("⏱ " .. left .. "s") or ""
				ui.timerText.TextColor3 = left <= 10 and Color3.fromRGB(255, 110, 110) or WHITE
				-- One warning per turn when time is nearly up.
				if left <= 10 and left > 0 and S.view and S.warnedTurn ~= S.view.turn and not S.processing then
					S.warnedTurn = S.view.turn
					F.notice("⏱ 10 seconds left! Then your creatures battle on their own.", Color3.fromRGB(255, 150, 140))
				end
			else
				ui.timerText.Text = ""
			end
		elseif S.turnState == "over" then
			ui.turnText.Text = "Match over"
			ui.turnText.TextColor3 = WHITE
			ui.timerText.Text = ""
		else
			ui.turnText.Text = (S.otherName or "Opponent") .. "'s turn"
			ui.turnText.TextColor3 = S.otherTeam and Color3.fromRGB(170, 230, 255) or Color3.fromRGB(255, 220, 160)
			ui.timerText.Text = ""
		end
	end

	-- Creatures breathe and sway a little while they wait.
	function F.idle(dt)
		local t = clock()
		for _, entry in pairs(S.units) do
			if entry.kind == "creature" and not entry.busy and entry.model.Parent then
				local bob = (math.sin(t * 1.3 + entry.phase) + 1) * 0.02
				local lean = math.sin(t * 1.3 + entry.phase + 0.9) * 0.014
				entry.model:PivotTo(entry.home * CFrame.new(0, bob, 0) * CFrame.Angles(lean, 0, 0))
			end
		end
		for _, entry in pairs(S.heroes) do
			if entry.model.Parent then
				local bob = (math.sin(t * 1.1 + entry.phase) + 1) * 0.012
				entry.model:PivotTo(entry.home * CFrame.new(0, bob, 0))
			end
		end
		if S.botAvatar and S.botBase then
			local lean = (S.turnState == "other") and 0.07 or 0
			S.botAvatar:PivotTo(S.botBase * CFrame.new(0, 2.45 + math.sin(t * 1.6) * 0.04, 0) * CFrame.Angles(-lean, 0, 0) * CFrame.new(0, -2.45, 0))
		end
		-- Your creatures that can still Spark glow softly on your turn.
		if F.myTurn() and not S.pick then
			for t2 = 1, 2 do
				for _, pad in pairs(S.pads[t2] or {}) do
					pad.glow.Transparency = 1
				end
			end
			for _, a in ipairs(S.view.legal or {}) do
				if a.kind == "spark" then
					local entry = S.units[a.uid]
					local pad = entry and S.pads[entry.team] and S.pads[entry.team][entry.lane]
					if pad then
						pad.glow.Color = Color3.fromRGB(150, 110, 255)
						pad.glow.Transparency = 0.7
						pad.glow.CFrame = CFrame.new(pad.creature.Position.X, S.layout.padTop + 0.04, pad.creature.Position.Z)
					end
				end
			end
		end
	end

	function MatchScreen.update(dt)
		if ctx.getMode() ~= "match" then
			ui.vignette.Visible = false
			return
		end
		ui.vignette.Visible = true
		local t = clock()
		if ui.resultPanel.Visible and S.resultAt then
			local left = math.max(0, math.ceil(S.resultAt - t))
			ui.resultCountdown.Text = left > 0 and ((S.resultBack or "Back to the room") .. " in " .. left .. "s") or ""
		end
		F.updateTurnText()
		F.dragUpdate()
		F.updateCoach()
		F.updateHover()
		F.updateGhost(dt)
		F.idle(dt)
	end

	MatchScreen.F = F
	MatchScreen.S = S
	return MatchScreen
end

return MatchScreen

-- MenuBriefs: a short, good-looking brief the first time you open each menu, instead of a
-- step-by-step tutorial. Client only.
--
-- Open a station, a Park window or your first match and a card glides in: an icon medallion, the
-- menu's name, one line on what it's for, three numbered beats on how it works and a tip. "Got
-- it" puts it away for good; the round ? button on that menu brings it back whenever you like.
-- "Skip all briefs" turns them all off (Settings > "Show menu briefs again" turns them back on).
-- Which briefs you've seen is saved with your account (the SeenBriefs pref).
--
--   MenuBriefs.init({ get = fn() -> string, set = fn(string) })  once, from DeckWarsClient (prefs)
--   MenuBriefs.maybe(key, opts) -> shown?    the first time only (opts below)
--   MenuBriefs.show(key, opts)               always (the ? button)
--   MenuBriefs.helpButton(parent, key, props, place) -> a round ? button that shows that brief
--   MenuBriefs.close() / MenuBriefs.isOpen() / MenuBriefs.current()
--   MenuBriefs.seen(key) / MenuBriefs.resetAll() / MenuBriefs.skipAll()
--
-- opts: place = "left" (beside a station panel on the right, the default), "center" (dims the
--       screen; Park windows), "match" (small, top left, no dim, nothing blocked: the turn
--       clock is running); onClose = fn(); still = fn() -> false to drop a pending brief
--       (the menu closed before it came up).
--
-- The words are in MenuBriefs.Briefs below: change them there.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Juice = require(here:WaitForChild("Juice"))

local rgb, make = Juice.rgb, Juice.make

local MenuBriefs = {}

local player = Players.LocalPlayer

local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium
local BOLD_FONT = Enum.Font.GothamBold
local BLACK_FONT = Enum.Font.GothamBlack
local CARD = rgb(19, 15, 27)
local CARD_TOP = rgb(29, 23, 41)
local TEXT = rgb(244, 239, 250)
local DIM = rgb(176, 168, 196)
local FAINT = rgb(120, 112, 140)
local GOLD = rgb(255, 214, 120)
local INK = rgb(28, 19, 14)

local SKIP_ALL = "ALL" -- in the seen list: every brief is off

---------------------------------------------------------------------------
-- The briefs
---------------------------------------------------------------------------
-- key = { icon, title, tag (one line), accent, beats = { { head, body } x3 }, tip }
MenuBriefs.Briefs = {
	Room = {
		icon = "🏠",
		title = "Your Room",
		tag = "Home base. Every part of Deck Wars starts here.",
		accent = rgb(255, 196, 92),
		beats = {
			{ "Pick a station", "Click anything that lights up in the room, or use the dock at the bottom. A / D hop between stations." },
			{ "Learn as you go", "Each menu gives you a quick brief like this one the first time you open it. No long tutorial." },
			{ "Need it again?", "Press the round ? on any menu to bring its brief back." },
		},
		tip = "New here? The Campaign (the painting over the fireplace) teaches the game one battle at a time.",
	},
	DuelTable = {
		icon = "⚔",
		title = "Duel Table",
		tag = "Real players. 1v1, 2v2 or an 8-player Cup.",
		accent = rgb(236, 92, 72),
		beats = {
			{ "Open a table", "Pick 1v1, 2v2 or Cup, then one of your own decks or a practice deck." },
			{ "Bring your party", "Lead a party (👥 top right) and your friends sit down with you." },
			{ "Win big", "Wins pay Coins, Gems, XP and trophies for the Trophy Road. A Cup win pays the most." },
		},
		tip = "Bot matches live in the Campaign.",
	},
	Campaign = {
		icon = "🗺",
		title = "Campaign",
		tag = "7 worlds, 6 acts each, and a boss waiting at the end.",
		accent = rgb(110, 196, 120),
		beats = {
			{ "Your decks, their rules", "Every act is a match against a named opponent, played with a deck you built." },
			{ "Three stars an act", "★ win · ★ keep half your hit points · ★ finish inside the turn limit." },
			{ "Push further", "Beat a boss to open the next world and its Hard mode. First clears pay Gems, Shards and a card." },
		},
		tip = "Star chests open at 6, 12 and 18 stars in every world.",
	},
	DeckShelf = {
		icon = "📚",
		title = "Deck Shelf",
		tag = "Your collection, your decks, your style.",
		accent = rgb(120, 162, 255),
		beats = {
			{ "Build a deck", "+ New or Edit: name it, pick a hero and up to 2 themes, then tap cards to add them. 20 to 40 cards; copies are fine (only one of each creature on the board at a time)." },
			{ "Mind the land", "Your themes set the terrain of each lane. A creature on its own terrain hits +1 harder." },
			{ "Level your cards", "Two copies of a card at the same level fuse into one copy a level higher." },
		},
		tip = "Tap a card, then tap the big card to inspect its 3D model up close. 🌄 Match background picks the world around your table.",
	},
	PackParty = {
		icon = "🎁",
		title = "Pack Party",
		tag = "Open packs. Grow the collection.",
		accent = rgb(255, 120, 196),
		beats = {
			{ "Pick a pack", "The Brawl Pack holds every card. A themed pack gives its family 3 cards in 4." },
			{ "Slash it open", "Swipe fast across the pack to cut it, then tap the card to flip it." },
			{ "Odds, out loud", "Every pack shows the exact chance of every card. A 10-pack always holds an Epic or better." },
		},
		tip = "Common, Rare, Epic, Mythic, Legendary, Secret: that's the climb.",
	},
	ShopCounter = {
		icon = "🛒",
		title = "Shop",
		tag = "Spend Coins, swap currencies, grab boosts.",
		accent = rgb(255, 200, 80),
		beats = {
			{ "Daily Cards", "Six cards for Coins, the same for everyone, new every day." },
			{ "Deck & Field", "Board themes, card backs, match backgrounds, emotes and more deck slots." },
			{ "Exchange & Boosts", "Swap Coins and Gems, Lucky charms for better pack odds, XP snacks for faster levels." },
		},
		tip = "Anything that costs Gems asks for a second tap, so nothing gets bought by accident.",
	},
	TrophyWall = {
		icon = "🏆",
		title = "Trophy Wall",
		tag = "Your trophies, achievements and daily reward in one place.",
		accent = rgb(255, 176, 70),
		beats = {
			{ "Trophy Road", "Every finished match earns trophies and they never go down. Claim stops for Coins, Gems, Shards and backgrounds." },
			{ "Achievements", "Big milestones. Claim each one once for Gems and Shards." },
			{ "Quests moved out", "Quests are claimed at the Quest Hall in the Park now. The card here shows today's and walks you there." },
		},
		tip = "Three backgrounds can only be won on the Trophy Road.",
	},
	ParkDoor = {
		icon = "🌳",
		title = "The Park",
		tag = "Step outside. Everyone in the server is out there.",
		accent = rgb(96, 206, 140),
		beats = {
			{ "Walk around", "You walk as your own avatar, with your creature at your side." },
			{ "Places to go", "Quest Hall, Pull Altar, Enchanting Crystal, Trading Post, Hall of Pulls and the leaderboards." },
			{ "Show off", "Whoever holds the rarest cards takes the Top Collector's pedestal." },
		},
		tip = "Walk up to anything with a prompt and press E.",
	},
	Radio = {
		icon = "⚙",
		title = "Settings",
		tag = "Make the game play your way.",
		accent = rgb(170, 160, 200),
		beats = {
			{ "Sound", "Sound effects and music, each on its own slider." },
			{ "Camera", "The action camera, camera lean and screen shake." },
			{ "Speed & quality", "Table speed, quick pack fights, and Low quality for slower devices." },
		},
		tip = "Your settings save to your account and follow you to every server.",
	},
	PullAltar = {
		icon = "✨",
		title = "Pull Altar",
		tag = "The Pack Party, out in the open.",
		accent = rgb(255, 120, 196),
		beats = {
			{ "Same packs", "The same packs, prices and odds as the Pack Party in your room." },
			{ "Big pulls get seen", "Mythic and up lights a pillar over the altar, a banner for everyone and a line in the Hall of Pulls." },
			{ "Secrets go global", "A Secret pull is announced to every server." },
		},
		tip = "Banners wait a few seconds, so they never spoil your own reveal.",
	},
	Enchant = {
		icon = "◆",
		title = "Enchanting Crystal",
		tag = "Roll a rune onto a card.",
		accent = rgb(214, 120, 255),
		beats = {
			{ "Pick a card", "Any creature or spell you own. Buildings can't hold a rune." },
			{ "Shards or Lucky", "20 Shards a roll, or Gems for Lucky: no Common runes and better odds. Earn Shards in the Campaign, the hourly Challenge, on the Trophy Road and from achievements." },
			{ "It sticks", "The rune rides on every copy in every deck. It powers up against bots and in the Campaign; in duels it only glows." },
		},
		tip = "8 enchants in a row below Epic and the next one is Epic or better.",
	},
	QuestHall = {
		icon = "📜",
		title = "Quest Hall",
		tag = "Finish quests anywhere. Claim them here, with Quill.",
		accent = rgb(214, 150, 255),
		beats = {
			{ "Three kinds", "3 daily quests, 5 weekly quests, and Journey quests for every Campaign world." },
			{ "Claim at the counter", "Each finished quest pays Gems, Shards and XP, and adds Renown." },
			{ "Renown chests", "Renown fills the track along the bottom. Four chests open on it, and it starts again every week." },
		},
		tip = "Swap one daily and one weekly quest for free. Finished quests wait for you, even after the day ends.",
	},
	Trade = {
		icon = "🤝",
		title = "Trading Post",
		tag = "Swap cards with other players.",
		accent = rgb(255, 214, 102),
		beats = {
			{ "Meet up", "Both of you stand at the Trading Post. Pick a player and ask." },
			{ "Make the offer", "Each side puts in cards, then presses Lock in." },
			{ "Seal it", "Once both have locked in, both confirm and the cards swap." },
		},
		tip = "Cards your decks use stay with you.",
	},
	MyLook = {
		icon = "⭐",
		title = "My Look",
		tag = "How everyone in the Park sees you.",
		accent = rgb(255, 214, 102),
		beats = {
			{ "Title", "Wear a title you've earned on your nameplate." },
			{ "Companion", "Pick one of your creatures to walk with you." },
			{ "Nameplate", "Shows your title, level and Campaign stars to everyone." },
		},
		tip = "Rarer pulls and Campaign star chests unlock new titles.",
	},
	Match = {
		icon = "⚔",
		title = "Your First Duel",
		tag = "Four lanes a side. Break their hero.",
		accent = rgb(236, 92, 72),
		beats = {
			{ "Play cards", "Drag a card onto a glowing spot. Front fights, Back waits (Ranged shoots from there). Buildings go behind." },
			{ "Spark and Shift", "Click a creature: 🌀 Spark uses its ability, ↕ Shift swaps its row. It skips its attack." },
			{ "⚔ BATTLE!", "Ends your turn. Creatures hit the first enemy in their lane, or the hero if it's empty." },
		},
		tip = "Press ? any time for the full rules.",
	},
}

---------------------------------------------------------------------------
-- What you've seen (saved as one word list: "DuelTable,Campaign,...")
---------------------------------------------------------------------------

local S = {
	ctx = nil,
	seen = nil, -- { [key] = true }
	gui = nil,
	open = nil, -- { key, holder, dim, conns, onClose, closing }
	token = 0,
}

local function loadSeen()
	if S.seen then
		return S.seen
	end
	local raw = nil
	if S.ctx and S.ctx.get then
		raw = S.ctx.get()
	end
	if raw == nil then
		raw = player:GetAttribute("PrefSeenBriefs")
	end
	local set = {}
	if type(raw) == "string" then
		for word in string.gmatch(raw, "[%w]+") do
			set[word] = true
		end
	end
	-- (only keep the list once the saved one has arrived: a late save mustn't be overwritten)
	if raw ~= nil or player:GetAttribute("ProgressLoaded") == true then
		S.seen = set
	end
	return set
end

local function saveSeen()
	local list = {}
	for key in pairs(S.seen or {}) do
		table.insert(list, key)
	end
	table.sort(list)
	local str = table.concat(list, ",")
	if S.ctx and S.ctx.set then
		S.ctx.set(str)
	end
end

function MenuBriefs.seen(key)
	local set = loadSeen()
	return set[SKIP_ALL] == true or set[key] == true
end

local function markSeen(key)
	local set = loadSeen()
	S.seen = set
	if not set[key] then
		set[key] = true
		saveSeen()
	end
end
MenuBriefs.markSeen = markSeen

function MenuBriefs.skipAll()
	markSeen(SKIP_ALL)
end

function MenuBriefs.resetAll()
	S.seen = {}
	saveSeen()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function corner(obj, px)
	return make("UICorner", { CornerRadius = UDim.new(0, px) }, obj)
end

local function guiRoot()
	if S.gui and S.gui.Parent then
		return S.gui
	end
	S.gui = make("ScreenGui", {
		Name = "MenuBriefs",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 58, -- over the room's menus and Park windows, under the toasts and the Park's fade
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	return S.gui
end

local function darken(c, k)
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

-- Every see-through value under root, remembered, so the card fades as one piece.
local FADE_PROPS = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	UIStroke = { "Transparency" },
}
local function fadeTree(root, memo, alpha, time)
	local function one(inst)
		local props = FADE_PROPS[inst.ClassName]
		if not props then
			return
		end
		local base = memo[inst]
		if not base then
			base = {}
			for _, p in ipairs(props) do
				base[p] = inst[p]
			end
			memo[inst] = base
		end
		local goal = {}
		for p, v in pairs(base) do
			goal[p] = v + (1 - v) * alpha
		end
		if time and time > 0 then
			TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		else
			for p, v in pairs(goal) do
				inst[p] = v
			end
		end
	end
	one(root)
	for _, d in ipairs(root:GetDescendants()) do
		one(d)
	end
end

local function text(parent, str, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Font = BODY_FONT,
		Text = str,
		TextColor3 = TEXT,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- Builds the card. Returns holder (the thing that moves), card, rows (for the staggered slide).
local function buildCard(brief, place, firstTime)
	local accent = brief.accent or GOLD
	local small = place == "match"
	local W = small and 360 or 448
	local pad = small and 16 or 22

	local holder = make("Frame", {
		Name = "Brief",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(W, 300),
	}, guiRoot())
	if place == "center" then
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
	elseif place == "match" then
		holder.AnchorPoint = Vector2.new(0, 0)
		holder.Position = UDim2.fromOffset(20, 96)
	else
		-- beside the station panel (which sits on the right)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.36, 0.5)
	end
	local scale = make("UIScale", { Scale = 1 }, holder)

	-- soft drop shadow
	local shadow = make("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.55,
		Size = UDim2.new(1, 10, 1, 14),
		Position = UDim2.fromOffset(-5, 2),
		ZIndex = 1,
	}, holder)
	corner(shadow, 22)

	local card = make("Frame", {
		Name = "Card",
		BackgroundColor3 = CARD,
		BackgroundTransparency = 0.04,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		ZIndex = 2,
	}, holder)
	corner(card, 18)
	local edge = make("UIStroke", { Thickness = 1.5, Color = accent, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	make("UIGradient", {
		Rotation = 35,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, accent),
			ColorSequenceKeypoint.new(0.5, rgb(255, 255, 255)),
			ColorSequenceKeypoint.new(1, accent),
		}),
	}, edge)

	-- the header's colour wash, from the accent into the card
	local wash = make("Frame", {
		Name = "Wash",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, small and 92 or 118),
		ZIndex = 2,
	}, card)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
	}, wash)
	-- a thin accent strip down the left edge
	local strip = make("Frame", {
		Name = "Strip",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, 0),
		ZIndex = 3,
	}, card)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.85) }),
	}, strip)

	local content = make("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -pad * 2, 0, 0),
		Position = UDim2.fromOffset(pad, pad - 2),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 3,
	}, card)
	local layout = make("UIListLayout", { Padding = UDim.new(0, small and 8 or 12), SortOrder = Enum.SortOrder.LayoutOrder }, content)

	-- Header: medallion + kicker + title + tag
	local medal = small and 52 or 66
	local head = make("Frame", { Name = "Head", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, medal), LayoutOrder = 1, ZIndex = 3 }, content)
	local disc = make("Frame", {
		Name = "Medallion",
		BackgroundColor3 = darken(accent, 0.32),
		Size = UDim2.fromOffset(medal, medal),
		ZIndex = 4,
	}, head)
	corner(disc, medal)
	make("UIGradient", { Rotation = 120, Color = ColorSequence.new(darken(accent, 1.0), darken(accent, 0.35)), Transparency = NumberSequence.new(0.35) }, disc)
	local ring = make("UIStroke", { Thickness = 2, Color = accent, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, disc)
	local ringGrad = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
			ColorSequenceKeypoint.new(0.25, accent),
			ColorSequenceKeypoint.new(0.75, darken(accent, 0.55)),
			ColorSequenceKeypoint.new(1, rgb(255, 255, 255)),
		}),
	}, ring)
	local icon = text(disc, brief.icon or "★", {
		Name = "Icon",
		Size = UDim2.fromScale(1, 1),
		TextSize = small and 26 or 34,
		Font = BOLD_FONT,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 5,
	})
	local tx = medal + 14
	text(head, (firstTime and "FIRST LOOK" or "HOW IT WORKS"), {
		Name = "Kicker",
		Font = BLACK_FONT,
		TextSize = small and 11 or 12,
		TextColor3 = accent,
		Size = UDim2.new(1, -tx, 0, 14),
		Position = UDim2.fromOffset(tx, small and 2 or 4),
		ZIndex = 4,
	})
	local title = text(head, brief.title, {
		Name = "Title",
		Font = TITLE_FONT,
		TextSize = small and 24 or 30,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -tx, 0, small and 26 or 34),
		Position = UDim2.fromOffset(tx, small and 16 or 20),
		ZIndex = 4,
	})
	local shine = make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, TEXT),
			ColorSequenceKeypoint.new(0.45, TEXT),
			ColorSequenceKeypoint.new(0.5, accent:Lerp(rgb(255, 255, 255), 0.55)),
			ColorSequenceKeypoint.new(0.55, TEXT),
			ColorSequenceKeypoint.new(1, TEXT),
		}),
		Offset = Vector2.new(-1, 0),
	}, title)
	text(content, brief.tag or "", {
		Name = "Tag",
		TextColor3 = DIM,
		TextSize = small and 14 or 16,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		ZIndex = 3,
	})
	make("Frame", {
		Name = "Rule",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
		LayoutOrder = 3,
		ZIndex = 3,
	}, content)

	-- The three beats
	local rows = {}
	for i, beat in ipairs(brief.beats or {}) do
		local row = make("Frame", {
			Name = "Beat" .. i,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 3 + i,
			ZIndex = 3,
		}, content)
		local slide = make("Frame", {
			Name = "Slide",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 3,
		}, row)
		local numW = small and 30 or 38
		text(slide, string.format("%02d", i), {
			Name = "Num",
			Font = BLACK_FONT,
			TextSize = small and 17 or 21,
			TextColor3 = accent,
			Size = UDim2.fromOffset(numW, 24),
			ZIndex = 4,
		})
		local words = make("Frame", {
			Name = "Words",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -numW, 0, 0),
			Position = UDim2.fromOffset(numW, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 3,
		}, slide)
		make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, words)
		text(words, beat[1], { Name = "Head", Font = BOLD_FONT, TextSize = small and 15 or 17, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, ZIndex = 4 })
		text(words, beat[2], { Name = "Body", TextColor3 = DIM, TextSize = small and 13 or 15, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, ZIndex = 4 })
		table.insert(rows, slide)
	end

	-- The tip
	if brief.tip then
		local tipBox = make("Frame", {
			Name = "Tip",
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.88,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 10,
			ZIndex = 3,
		}, content)
		corner(tipBox, 10)
		make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, tipBox)
		text(tipBox, "<font color=\"#" .. accent:ToHex() .. "\"><b>TIP</b></font>   " .. brief.tip, {
			Name = "Text",
			RichText = true,
			TextSize = small and 13 or 14,
			TextColor3 = TEXT,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			ZIndex = 4,
		})
	end

	-- Footer: Skip all (first time only) · Got it
	local foot = make("Frame", { Name = "Foot", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, small and 36 or 42), LayoutOrder = 11, ZIndex = 3 }, content)
	local gotIt = make("TextButton", {
		Name = "GotIt",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, small and 108 or 132, 1, 0),
		BackgroundColor3 = accent,
		Font = BOLD_FONT,
		Text = "Got it",
		TextSize = small and 16 or 18,
		TextColor3 = INK,
		ZIndex = 4,
	}, foot)
	corner(gotIt, 10)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 255, 255), rgb(205, 198, 214)) }, gotIt)
	Juice.button(gotIt, { grow = 1.05 })
	local skip = nil
	if firstTime then
		skip = make("TextButton", {
			Name = "SkipAll",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0, 150, 1, 0),
			Font = BODY_FONT,
			RichText = true,
			Text = "<u>Skip all briefs</u>",
			TextSize = 13,
			TextColor3 = FAINT,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}, foot)
		skip.MouseEnter:Connect(function()
			skip.TextColor3 = DIM
		end)
		skip.MouseLeave:Connect(function()
			skip.TextColor3 = FAINT
		end)
	end

	-- the card is as tall as what's in it
	local function fit()
		holder.Size = UDim2.fromOffset(W, layout.AbsoluteContentSize.Y / math.max(scale.Scale, 0.01) + pad * 2)
	end
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
	fit()

	-- smaller screens get a smaller card
	local function fitScreen()
		local cam = workspace.CurrentCamera
		local vh = cam and cam.ViewportSize.Y or 800
		local vw = cam and cam.ViewportSize.X or 1280
		local s = math.clamp(math.min(vh / 860, vw / (W * 2.1)), 0.62, 1)
		scale.Scale = s
	end
	fitScreen()

	return {
		holder = holder,
		card = card,
		scale = scale,
		rows = rows,
		gotIt = gotIt,
		skip = skip,
		ringGrad = ringGrad,
		shine = shine,
		icon = icon,
		fit = fit,
		fitScreen = fitScreen,
	}
end

---------------------------------------------------------------------------
-- Showing and closing
---------------------------------------------------------------------------

function MenuBriefs.isOpen()
	return S.open ~= nil and not S.open.closing
end

function MenuBriefs.current()
	return S.open and not S.open.closing and S.open.key or nil
end

function MenuBriefs.close(instant)
	local o = S.open
	if not o or o.closing then
		return
	end
	o.closing = true
	S.open = nil
	for _, c in ipairs(o.conns) do
		c:Disconnect()
	end
	local t = instant and 0 or 0.22
	if o.dim then
		TweenService:Create(o.dim, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	end
	if not instant then
		TweenService:Create(o.parts.scale, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = o.parts.scale.Scale * 0.95 }):Play()
		fadeTree(o.parts.holder, o.memo, 1, t)
	end
	task.delay(t + 0.02, function()
		o.parts.holder:Destroy()
		if o.dim then
			o.dim:Destroy()
		end
	end)
	if o.onClose then
		task.spawn(o.onClose)
	end
end

function MenuBriefs.show(key, opts)
	opts = opts or {}
	local brief = MenuBriefs.Briefs[key]
	if not brief then
		return false
	end
	if S.open then
		if S.open.key == key then
			return true
		end
		MenuBriefs.close(true)
	end
	local place = opts.place or "left"
	local firstTime = opts.firstTime == true
	local parts = buildCard(brief, place, firstTime)
	local o = { key = key, parts = parts, conns = {}, memo = {}, onClose = opts.onClose }
	S.open = o

	-- the dim (also catches clicks so the room behind doesn't react); not in a match
	if place ~= "match" then
		o.dim = make("TextButton", {
			Name = "BriefDim",
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		}, guiRoot())
		parts.holder.ZIndex = 1
		TweenService:Create(o.dim, TweenInfo.new(0.3), { BackgroundTransparency = place == "center" and 0.5 or 0.62 }):Play()
	end

	local function done()
		markSeen(key)
		MenuBriefs.close()
	end
	parts.gotIt.Activated:Connect(done)
	if parts.skip then
		parts.skip.Activated:Connect(function()
			markSeen(key)
			MenuBriefs.skipAll()
			Juice.sound("tick", 0.9, 0.3)
			MenuBriefs.close()
		end)
	end
	table.insert(o.conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Return or k == Enum.KeyCode.KeypadEnter or k == Enum.KeyCode.ButtonA or (k == Enum.KeyCode.Escape and place ~= "match") then
			done()
		end
	end))
	local cam = workspace.CurrentCamera
	if cam then
		table.insert(o.conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			parts.fitScreen()
			parts.fit()
		end))
	end

	-- In: rises a little, springs to size, fades up; the beats slide in one after another.
	local finalScale = parts.scale.Scale
	local finalPos = parts.holder.Position
	fadeTree(parts.holder, o.memo, 1, 0)
	parts.scale.Scale = finalScale * 0.92
	parts.holder.Position = finalPos + UDim2.fromOffset(0, 26)
	for _, r in ipairs(parts.rows) do
		r.Position = UDim2.fromOffset(18, 0)
	end
	fadeTree(parts.holder, o.memo, 0, 0.32)
	TweenService:Create(parts.scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = finalScale }):Play()
	TweenService:Create(parts.holder, TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = finalPos }):Play()
	for i, r in ipairs(parts.rows) do
		TweenService:Create(r, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.12 + i * 0.08), { Position = UDim2.fromOffset(0, 0) }):Play()
	end
	-- the icon pops, the title catches the light once, the medallion's ring turns slowly
	Juice.popIn(parts.icon, 0.12, { twist = 0, sound = false })
	task.delay(0.35, function()
		if parts.shine.Parent then
			TweenService:Create(parts.shine, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Offset = Vector2.new(1, 0) }):Play()
		end
	end)
	local checkIn = 0
	table.insert(o.conns, RunService.RenderStepped:Connect(function(dt)
		parts.ringGrad.Rotation = (parts.ringGrad.Rotation + dt * 40) % 360
		-- the menu it was for has gone (you stepped to another station, the match ended): it goes too
		checkIn -= dt
		if opts.still and checkIn <= 0 then
			checkIn = 0.25
			if not opts.still() then
				if firstTime then
					markSeen(key)
				end
				MenuBriefs.close()
			end
		end
	end))
	Juice.sound("whoosh", 1.25, 0.18)
	task.delay(0.15, function()
		Juice.sound("chime", 1.1, 0.25)
	end)
	return true
end

-- The first time only. Waits a moment (the station panel slides in first) and gives up if the
-- menu closed in the meantime (opts.still).
function MenuBriefs.maybe(key, opts)
	opts = opts or {}
	if not MenuBriefs.Briefs[key] or MenuBriefs.seen(key) then
		return false
	end
	S.token += 1
	local token = S.token
	task.delay(opts.delay or 0.45, function()
		if token ~= S.token or MenuBriefs.seen(key) then
			return
		end
		if opts.still and not opts.still() then
			return
		end
		local o = table.clone(opts)
		o.firstTime = true
		MenuBriefs.show(key, o)
	end)
	return true
end

-- Drops a brief that's waiting to come up (the menu it was for closed).
function MenuBriefs.cancelPending()
	S.token += 1
end

-- A round ? button (the size and look of the drawn ✕ next to it) that shows `key`'s brief.
-- key can be a function that returns the key (a panel shared by several menus).
function MenuBriefs.helpButton(parent, key, props, place)
	local b = make("TextButton", {
		Name = "BriefButton",
		AutoButtonColor = false,
		BackgroundColor3 = rgb(70, 56, 104),
		Size = UDim2.fromOffset(34, 34),
		Font = TITLE_FONT,
		Text = "?",
		TextSize = 22,
		TextColor3 = rgb(255, 236, 200),
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
	make("UIStroke", { Thickness = 2.5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 255, 255), rgb(196, 186, 206)) }, b)
	b:SetAttribute("Caption", "How it works")
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	Juice.button(b, { grow = 1.08 })
	b.Activated:Connect(function()
		local k = type(key) == "function" and key() or key
		if k then
			if MenuBriefs.current() == k then
				MenuBriefs.close()
			else
				MenuBriefs.show(k, { place = place })
			end
		end
	end)
	return b
end

function MenuBriefs.init(ctx)
	S.ctx = ctx
	S.seen = nil
	-- your saved list arrives with your progress: read it again then
	player:GetAttributeChangedSignal("PrefSeenBriefs"):Connect(function()
		local raw = player:GetAttribute("PrefSeenBriefs")
		if type(raw) == "string" then
			local set = S.seen or {}
			for word in string.gmatch(raw, "[%w]+") do
				set[word] = true
			end
			S.seen = set
		end
	end)
end

return MenuBriefs

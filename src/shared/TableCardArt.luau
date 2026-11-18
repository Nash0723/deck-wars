-- TableCardArt: the faces of the real cards that lie on the Duel Table in a match.
--
-- Every creature and building stands on its own card, a spell is shown over the table while it
-- works, and when a unit falls its card turns face down onto the shared trash pile. These are the
-- pictures drawn on those cards (MatchScreen makes the 3D cards and moves them):
--
--   TableCardArt.face(gui, id, level) -- the card's face: its family's painted scene (CardStyle),
--        the frame, the rarity's gems and foil, cost, name, attack and health. Returns the card
--        frame and `refs` (its live parts: see setStats, flash and fade).
--   TableCardArt.setStats(refs, u)   -- the attack and health badges follow the creature on the
--        board: green when raised, red when hurt or lowered, and they pop when they change.
--   TableCardArt.flash(refs, color, seconds) -- the card lights up in a colour and fades back.
--   TableCardArt.fade(refs, amount, seconds) -- the card greys out (its creature is gone).
--   TableCardArt.back(gui, id)       -- the card's back: the card's biome art with the rarity foil
--        (CardBacks), shown at once (no wake-up pop: it's a card on a pile, not a pull). With no
--        id it's a plain back (the top of a deck: nobody knows that card yet).
--   TableCardArt.CanvasSize          -- the pixel size both are drawn at (the card is 1.45 x 1.98).
--
-- `gui` is a SurfaceGui (or any GuiBase2d). Client only, GUI only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local here = script.Parent
local CardData = require(here:WaitForChild("CardData"))
local CardStyle = require(here:WaitForChild("CardStyle"))

-- The card backs live with the pack opening (PackBrawl). Loaded on first use, and a back that
-- can't be drawn falls back to a plain navy back.
local PackArt, CardBacks = nil, nil
local function backMods()
	if PackArt == nil then
		local ok = pcall(function()
			local pb = ReplicatedStorage:WaitForChild("PackBrawl", 10)
			PackArt = require(pb:WaitForChild("PackArt"))
			CardBacks = require(pb:WaitForChild("CardBacks"))
		end)
		if not ok then
			PackArt, CardBacks = false, false
		end
	end
	return PackArt, CardBacks
end

local TableCardArt = {}

TableCardArt.CanvasSize = Vector2.new(300, 410)

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)
local UP = Color3.fromRGB(140, 255, 150) -- raised
local DOWN = Color3.fromRGB(255, 150, 150) -- hurt or lowered

local function rgb(t, fallback)
	if type(t) ~= "table" then
		return fallback
	end
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(p, px)
	return make("UICorner", { CornerRadius = UDim.new(0, px) }, p)
end

local function text(parent, str, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1,
		Text = str,
		TextScaled = true,
		Font = Enum.Font.FredokaOne,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.35,
		TextStrokeColor3 = Color3.fromRGB(30, 20, 30),
		ZIndex = 6,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

-- A round stat badge (cost top-left, attack bottom-left, health bottom-right). Returns the badge
-- and its number.
local function badge(parent, x, y, value, color, px)
	local b = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = color,
		ZIndex = 7,
	}, parent)
	corner(b, px)
	make("UIStroke", { Thickness = 5, Color = WHITE }, b)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, Color3.fromRGB(200, 200, 200)) }, b)
	make("UIScale", { Scale = 1 }, b)
	local n = text(b, tostring(value), { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.11, 0.1), ZIndex = 8, TextStrokeTransparency = 0.1 })
	return b, n
end

-- The emoji for a spell's art window when there's no creature in it.
local SPELL_MARK = "✨"

function TableCardArt.face(gui, id, level)
	local def = CardData.Cards[id]
	if not def then
		return nil, nil
	end
	local famColor = rgb(CardData.FamilyColors[def.family], WHITE)
	local tierColor = rgb(CardData.RarityColors[def.rarity], WHITE)
	if def.rarity == "Common" then
		tierColor = Color3.fromRGB(242, 230, 201)
	end
	local card = make("Frame", { Name = "Front", Size = UDim2.fromScale(1, 1), BackgroundColor3 = famColor:Lerp(WHITE, 0.55), BorderSizePixel = 0, ZIndex = 1 }, gui)
	corner(card, 22)
	card:SetAttribute("KeepColors", true) -- (the cozy menu colours leave table cards alone)
	local stroke = make("UIStroke", { Thickness = 10, Color = tierColor }, card)
	if def.rarity == "Secret" then
		make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 170)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 235, 130)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(130, 220, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 140, 255)),
			}),
			Rotation = 35,
		}, stroke)
	end
	pcall(CardStyle.dress, card, def, famColor, tierColor, { radius = 22, gemSize = 20 })
	-- the painted scene (the family's world) in the art window
	local art = make("Frame", { Name = "Art", Size = UDim2.fromScale(0.86, 0.47), Position = UDim2.fromScale(0.07, 0.14), BackgroundColor3 = famColor, ClipsDescendants = true, ZIndex = 2 }, card)
	corner(art, 14)
	make("UIStroke", { Thickness = 3, Color = famColor:Lerp(BLACK, 0.4) }, art)
	pcall(CardStyle.scene, art, def, { lite = true })
	if def.type == "Spell" then
		text(art, SPELL_MARK, { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), TextStrokeTransparency = 1, ZIndex = 4 })
	end
	-- name plate
	local plate = make("Frame", { Name = "NamePlate", Size = UDim2.fromScale(0.9, 0.13), Position = UDim2.fromScale(0.05, 0.635), BackgroundColor3 = famColor:Lerp(BLACK, 0.35), BackgroundTransparency = 0.05, ZIndex = 4 }, card)
	corner(plate, 12)
	make("UIStroke", { Thickness = 2, Color = tierColor, Transparency = 0.2 }, plate)
	text(plate, def.name or id, { Size = UDim2.new(0.92, 0, 0.8, 0), Position = UDim2.fromScale(0.04, 0.1), ZIndex = 5 })
	-- type line (and level from Lv 2)
	local line = def.type .. ((def.family and def.family ~= "Any") and (" · " .. def.family) or "")
	if (level or 1) >= 2 then
		line ..= "  ·  Lv " .. level
	end
	text(card, line, { Size = UDim2.fromScale(0.62, 0.06), Position = UDim2.fromScale(0.19, 0.785), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(60, 50, 70), TextStrokeTransparency = 1, ZIndex = 4 })
	local refs = { card = card }
	-- cost
	badge(card, 0.13, 0.075, def.cost or 0, Color3.fromRGB(45, 95, 210), 82)
	-- attack and health (creatures): they follow the creature on the board (setStats)
	if def.type == "Creature" then
		refs.atkBadge, refs.atk = badge(card, 0.15, 0.9, def.atk or 0, Color3.fromRGB(215, 70, 50), 96)
		refs.hpBadge, refs.hp = badge(card, 0.85, 0.9, def.hp or 0, Color3.fromRGB(60, 170, 80), 96)
		refs.lastAtk, refs.lastHp = def.atk, def.hp
	end
	-- a glow over the whole card (it lights up when its creature climbs out) and a grey veil (its
	-- creature is gone), both clear until used
	refs.glow = make("Frame", { Name = "Glow", Size = UDim2.fromScale(1, 1), BackgroundColor3 = famColor:Lerp(WHITE, 0.45), BackgroundTransparency = 1, ZIndex = 20 }, card)
	corner(refs.glow, 22)
	make("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0.05),
			NumberSequenceKeypoint.new(1, 0.6),
		}),
	}, refs.glow)
	refs.veil = make("Frame", { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(28, 24, 34), BackgroundTransparency = 1, ZIndex = 21 }, card)
	corner(refs.veil, 22)
	return card, refs
end

local function pop(b)
	local sc = b and b:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = 1.45
		TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- u: the unit as the server sends it (atk, hp, maxHp, baseAtk).
function TableCardArt.setStats(refs, u)
	if not (refs and refs.atk and u) then
		return
	end
	local atk, hp = tonumber(u.atk) or 0, tonumber(u.hp) or 0
	local baseAtk = tonumber(u.baseAtk) or atk
	local maxHp = tonumber(u.maxHp) or hp
	local def = u.id and CardData.Cards[u.id]
	local baseHp = def and def.hp or maxHp
	refs.atk.Text = tostring(atk)
	refs.hp.Text = tostring(hp)
	refs.atk.TextColor3 = (atk > baseAtk and UP) or (atk < baseAtk and DOWN) or WHITE
	refs.hp.TextColor3 = (hp < maxHp and DOWN) or (hp > baseHp and UP) or WHITE
	if refs.lastAtk ~= nil and refs.lastAtk ~= atk then
		pop(refs.atkBadge)
	end
	if refs.lastHp ~= nil and refs.lastHp ~= hp then
		pop(refs.hpBadge)
	end
	refs.lastAtk, refs.lastHp = atk, hp
end

function TableCardArt.flash(refs, color, seconds)
	local g = refs and refs.glow
	if not (g and g.Parent) then
		return
	end
	if color then
		g.BackgroundColor3 = color
	end
	g.BackgroundTransparency = 0.05
	TweenService:Create(g, TweenInfo.new(seconds or 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

function TableCardArt.fade(refs, amount, seconds)
	local v = refs and refs.veil
	if not (v and v.Parent) then
		return
	end
	TweenService:Create(v, TweenInfo.new(seconds or 0.3), { BackgroundTransparency = 1 - (amount or 0.55) }):Play()
end

function TableCardArt.back(gui, id)
	local def = id and CardData.Cards[id]
	local pa, cb = backMods()
	local back = nil
	if pa then
		local ok = pcall(function()
			back = pa.cardBack(gui)
		end)
		if not ok then
			back = nil
		end
	end
	if not back then
		back = make("Frame", { Name = "Back", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(32, 38, 74), BorderSizePixel = 0 }, gui)
		corner(back, 16)
		make("UIStroke", { Thickness = 6, Color = Color3.fromRGB(242, 230, 201) }, back)
		text(back, "DECK\nWARS", { Size = UDim2.fromScale(0.6, 0.25), Position = UDim2.fromScale(0.2, 0.375), TextColor3 = Color3.fromRGB(242, 230, 201), TextStrokeTransparency = 1 })
		return back
	end
	back:SetAttribute("KeepColors", true)
	if cb and def then
		pcall(function()
			local st = cb.dress(back, def.rarity, def.family)
			if st then
				-- shown at once: no wake-up flash, pop or sound on the table
				st.awake = true
				st.trim.GroupTransparency = 0
				local edge = back:FindFirstChildOfClass("UIStroke")
				if edge and st.look and st.look.edge then
					edge.Color = st.look.edge
				end
			end
		end)
	end
	return back
end

return TableCardArt

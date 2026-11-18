-- TableCardArt: the faces of the real cards that lie on the Duel Table in a match.
--
-- Every creature and building stands on its own card, a spell is laid on the table while it
-- works, and when a unit falls its card turns face down onto the shared trash pile. These are the
-- pictures drawn on those cards (MatchScreen makes the 3D cards and moves them):
--
--   TableCardArt.face(gui, id, level) -- the card's face: its family's painted scene (CardStyle),
--        the frame, the rarity's gems and foil, cost, name, attack and health.
--   TableCardArt.back(gui, id)       -- the card's back: the card's biome art with the rarity foil
--        (CardBacks), shown at once (no wake-up pop: it's a card on a pile, not a pull).
--   TableCardArt.CanvasSize          -- the pixel size both are drawn at (the card is 1.5 x 2.05).
--
-- `gui` is a SurfaceGui (or any GuiBase2d). Client only, GUI only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- A round stat badge (cost top-left, attack bottom-left, health bottom-right).
local function badge(parent, x, y, value, color, anchorX)
	local b = make("Frame", {
		AnchorPoint = Vector2.new(anchorX, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(78, 78),
		BackgroundColor3 = color,
		ZIndex = 5,
	}, parent)
	corner(b, 40)
	make("UIStroke", { Thickness = 4, Color = WHITE }, b)
	text(b, tostring(value), { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 6 })
	return b
end

-- The emoji for a spell's art window when there's no creature in it.
local SPELL_MARK = "✨"

function TableCardArt.face(gui, id, level)
	local def = CardData.Cards[id]
	if not def then
		return nil
	end
	local famColor = rgb(CardData.FamilyColors[def.family], WHITE)
	local tierColor = rgb(CardData.RarityColors[def.rarity], WHITE)
	if def.rarity == "Common" then
		tierColor = Color3.fromRGB(242, 230, 201)
	end
	local card = make("Frame", { Name = "Front", Size = UDim2.fromScale(1, 1), BackgroundColor3 = famColor:Lerp(WHITE, 0.55), BorderSizePixel = 0, ZIndex = 1 }, gui)
	corner(card, 22)
	card:SetAttribute("KeepColors", true) -- (the cozy menu colours leave table cards alone)
	local stroke = make("UIStroke", { Thickness = 9, Color = tierColor }, card)
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
	local art = make("Frame", { Name = "Art", Size = UDim2.fromScale(0.86, 0.5), Position = UDim2.fromScale(0.07, 0.15), BackgroundColor3 = famColor, ClipsDescendants = true, ZIndex = 2 }, card)
	corner(art, 14)
	make("UIStroke", { Thickness = 3, Color = famColor:Lerp(BLACK, 0.4) }, art)
	pcall(CardStyle.scene, art, def, { lite = true })
	if def.type == "Spell" then
		text(art, SPELL_MARK, { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), TextStrokeTransparency = 1, ZIndex = 4 })
	end
	-- name plate
	local plate = make("Frame", { Name = "NamePlate", Size = UDim2.fromScale(0.9, 0.13), Position = UDim2.fromScale(0.05, 0.67), BackgroundColor3 = famColor:Lerp(BLACK, 0.35), BackgroundTransparency = 0.05, ZIndex = 4 }, card)
	corner(plate, 12)
	text(plate, def.name or id, { Size = UDim2.new(0.92, 0, 0.8, 0), Position = UDim2.fromScale(0.04, 0.1), ZIndex = 5 })
	-- type line (and level from Lv 2)
	local line = def.type .. ((def.family and def.family ~= "Any") and (" · " .. def.family) or "")
	if (level or 1) >= 2 then
		line ..= "  ·  Lv " .. level
	end
	text(card, line, { Size = UDim2.fromScale(0.8, 0.065), Position = UDim2.fromScale(0.1, 0.815), Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(60, 50, 70), TextStrokeTransparency = 1, ZIndex = 4 })
	-- cost
	badge(card, 0.12, 0.08, def.cost or 0, Color3.fromRGB(40, 90, 200), 0.5)
	-- attack and health (creatures)
	if def.type == "Creature" then
		badge(card, 0.12, 0.93, def.atk or 0, Color3.fromRGB(215, 70, 50), 0.5)
		badge(card, 0.88, 0.93, def.hp or 0, Color3.fromRGB(60, 170, 80), 0.5)
	end
	return card
end

function TableCardArt.back(gui, id)
	local def = CardData.Cards[id]
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

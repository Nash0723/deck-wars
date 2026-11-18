--!strict
-- CardStyle: what makes a card look like a collectible.
--
--   CardStyle.scene(art, def, opts)  -- a little painted place behind the creature, by family:
--        Snack   candy hills, lollipops and sprinkles under a pink sky
--        Critter green hills, a sun and flowers
--        Weather a storm sky with clouds, snow and a faint bolt
--        Junk    scrap piles, a tyre and gears at dusk
--        Spooky  a full moon over the dark mall, lit windows and wisps
--        Robo    a neon grid floor, circuit traces and stars
--        Any     green card-table felt under a spotlight
--     The scene sits at the art frame's own ZIndex; the creature (or spell icon) goes above it.
--     opts.lite = true: fewer bits (cards in a big grid, or the hand in a match).
--   CardStyle.dress(card, def, opts) -- the card's body: a soft pattern, an inner border, and the
--     rarity's touches (a gem on the bottom edge from Rare, corner gems from Epic, a holo foil from
--     Mythic). Goes under everything already on the card (ZIndex 0).
--
-- Shared by the client's cards (makeCard) and the pack reveal's card face. GUI only.

local CardStyle = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local BLACK = Color3.fromRGB(0, 0, 0)

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		(inst :: any)[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- A small seeded random, so a card's sprinkles and stars sit in the same place every time.
local function seeded(str: string)
	local s = 7
	for i = 1, #str do
		s = (s * 31 + string.byte(str, i)) % 2147483646
	end
	s += 1
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

local function blob(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, tr: number?, z: number): Frame
	local f = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), BackgroundColor3 = color, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z }, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	return f
end

local function rect(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, rot: number?, tr: number?, z: number): Frame
	return make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), Rotation = rot or 0, BackgroundColor3 = color, BackgroundTransparency = tr or 0, BorderSizePixel = 0, ZIndex = z }, parent)
end

local function vgrad(parent: Instance, top: Color3, bottom: Color3)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom) }, parent)
end

-- Hard-edged stripes as a gradient (n stripes of two colours). Each stripe takes 2 keypoints and
-- Roblox allows at most 20 in a ColorSequence (more is an error, and the card isn't drawn at all),
-- so n is capped at 10.
local function stripes(parent: Instance, a: Color3, b: Color3, n: number, rot: number)
	n = math.clamp(math.floor(n), 1, 10)
	local keys = {}
	for k = 0, n - 1 do
		local x0, x1 = k / n, (k + 1) / n
		local col = (k % 2 == 0) and a or b
		table.insert(keys, ColorSequenceKeypoint.new(x0, col))
		table.insert(keys, ColorSequenceKeypoint.new(math.max(x0, x1 - 0.001), col))
	end
	keys[#keys] = ColorSequenceKeypoint.new(1, (n % 2 == 1) and a or b)
	make("UIGradient", { Rotation = rot, Color = ColorSequence.new(keys) }, parent)
end

---------------------------------------------------------------------------
-- Scenes
---------------------------------------------------------------------------
local Scenes = {}

function Scenes.Snack(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(255, 176, 206), rgb(255, 228, 186))
	blob(root, 0.8, 0.18, 0.34, 0.42, rgb(255, 244, 214), 0.2, z) -- a soft sugar sun
	if not lite then
		for k = 1, 2 do -- lollipops on the hills
			local x = k == 1 and 0.14 or 0.88
			rect(root, x, 0.62, 0.025, 0.36, WHITE, 0, 0, z)
			local pop = blob(root, x, 0.42, 0.2, 0.26, WHITE, 0, z)
			stripes(pop, k == 1 and rgb(255, 90, 140) or rgb(120, 200, 255), WHITE, 6, 35)
		end
	end
	blob(root, 0.2, 1.02, 0.8, 0.5, rgb(255, 140, 180), 0, z)
	blob(root, 0.82, 1.04, 0.8, 0.46, rgb(150, 230, 200), 0, z)
	blob(root, 0.5, 1.1, 0.9, 0.4, rgb(255, 205, 150), 0, z)
	local colors = { WHITE, rgb(255, 90, 140), rgb(120, 200, 255), rgb(255, 230, 90), rgb(170, 255, 140) }
	for _ = 1, lite and 5 or 10 do
		local s = rect(root, 0.05 + r() * 0.9, 0.08 + r() * 0.6, 0.018, 0.07, colors[1 + math.floor(r() * #colors)], r() * 180, 0.1, z)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, s)
	end
end

function Scenes.Critter(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(140, 205, 255), rgb(214, 242, 255))
	blob(root, 0.82, 0.2, 0.22, 0.28, rgb(255, 236, 140), 0, z)
	blob(root, 0.82, 0.2, 0.34, 0.44, rgb(255, 244, 190), 0.65, z)
	if not lite then
		for _, c in ipairs({ { 0.2, 0.2 }, { 0.42, 0.13 } }) do -- a few fluffy clouds
			blob(root, c[1], c[2], 0.2, 0.12, WHITE, 0.15, z)
			blob(root, c[1] + 0.07, c[2] - 0.03, 0.14, 0.12, WHITE, 0.15, z)
		end
	end
	blob(root, 0.22, 1.0, 0.9, 0.5, rgb(120, 200, 90), 0, z)
	blob(root, 0.85, 1.02, 0.8, 0.45, rgb(90, 175, 70), 0, z)
	local petals = { WHITE, rgb(255, 230, 90), rgb(255, 150, 190), rgb(190, 160, 255) }
	for _ = 1, lite and 4 or 9 do
		blob(root, 0.05 + r() * 0.9, 0.82 + r() * 0.14, 0.035, 0.045, petals[1 + math.floor(r() * #petals)], 0, z)
	end
end

function Scenes.Weather(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(60, 96, 170), rgb(170, 210, 245))
	if not lite then
		rect(root, 0.72, 0.36, 0.05, 0.3, rgb(255, 240, 140), 22, 0.45, z) -- a faint bolt
		rect(root, 0.75, 0.6, 0.05, 0.26, rgb(255, 240, 140), -28, 0.45, z)
	end
	for _, c in ipairs({ { 0.22, 0.18 }, { 0.62, 0.12 }, { 0.9, 0.24 } }) do
		blob(root, c[1], c[2], 0.3, 0.16, rgb(235, 242, 255), 0.05, z)
		blob(root, c[1] - 0.08, c[2] + 0.03, 0.18, 0.13, rgb(220, 230, 250), 0.05, z)
		blob(root, c[1] + 0.09, c[2] + 0.02, 0.2, 0.14, rgb(225, 235, 252), 0.05, z)
	end
	blob(root, 0.5, 1.08, 1.4, 0.4, rgb(235, 245, 255), 0, z) -- a snowy ground
	for _ = 1, lite and 6 or 14 do
		local s = 0.02 + r() * 0.025
		blob(root, r(), 0.3 + r() * 0.55, s, s * 1.3, WHITE, 0.2, z)
	end
end

local function gear(root: Frame, x: number, y: number, size: number, color: Color3, z: number)
	local g = blob(root, x, y, size, size * 1.35, color, 0, z)
	make("UIStroke", { Thickness = 2, Color = color:Lerp(BLACK, 0.4) }, g)
	for k = 0, 5 do
		local a = k * math.pi / 3
		rect(root, x + math.cos(a) * size * 0.55, y + math.sin(a) * size * 0.74, size * 0.26, size * 0.3, color, math.deg(a), 0, z)
	end
	blob(root, x, y, size * 0.36, size * 0.48, color:Lerp(BLACK, 0.45), 0, z)
end

function Scenes.Junk(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(70, 104, 110), rgb(222, 170, 120))
	blob(root, 0.22, 0.32, 0.26, 0.34, rgb(255, 210, 150), 0.35, z) -- a hazy sunset
	if not lite then
		gear(root, 0.86, 0.3, 0.16, rgb(170, 160, 140), z)
		local tyre = blob(root, 0.14, 0.7, 0.2, 0.27, rgb(40, 40, 44), 0, z)
		make("UIStroke", { Thickness = 2, Color = rgb(20, 20, 22) }, tyre)
		blob(root, 0.14, 0.7, 0.09, 0.12, rgb(90, 90, 96), 0, z)
	end
	blob(root, 0.25, 1.05, 0.8, 0.52, rgb(110, 98, 84), 0, z)
	blob(root, 0.8, 1.06, 0.8, 0.5, rgb(132, 118, 98), 0, z)
	for _ = 1, lite and 3 or 6 do -- planks and bits poking out of the heaps
		rect(root, 0.1 + r() * 0.8, 0.8 + r() * 0.1, 0.16 + r() * 0.1, 0.035, rgb(150, 120, 90):Lerp(rgb(90, 110, 120), r()), -40 + r() * 80, 0, z)
	end
	for _ = 1, lite and 2 or 5 do -- a few glints of glitter
		blob(root, r(), 0.6 + r() * 0.35, 0.02, 0.026, rgb(255, 240, 180), 0, z)
	end
end

function Scenes.Spooky(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(34, 18, 64), rgb(110, 60, 140))
	blob(root, 0.78, 0.22, 0.42, 0.55, rgb(200, 255, 170), 0.85, z) -- the moon's glow
	blob(root, 0.78, 0.22, 0.24, 0.32, rgb(250, 246, 210), 0, z)
	blob(root, 0.72, 0.18, 0.05, 0.06, rgb(220, 214, 180), 0, z)
	-- the mall's dark roofline with lit windows
	local heights = { 0.4, 0.55, 0.32, 0.48, 0.36 }
	for k, hgt in ipairs(heights) do
		local x = (k - 0.5) / #heights
		rect(root, x, 1 - hgt / 2, 0.21, hgt, rgb(26, 14, 44), 0, 0, z)
		if not lite or k % 2 == 1 then
			for j = 0, 1 do
				rect(root, x - 0.04 + j * 0.08, 1 - hgt + 0.1, 0.035, 0.05, rgb(255, 214, 110), 0, r() < 0.3 and 0.7 or 0, z)
			end
		end
	end
	for _ = 1, lite and 2 or 5 do -- wisps
		blob(root, 0.08 + r() * 0.84, 0.25 + r() * 0.4, 0.06, 0.05, rgb(186, 255, 140), 0.45, z)
	end
end

function Scenes.Robo(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(16, 18, 44), rgb(64, 36, 96))
	for _ = 1, lite and 5 or 10 do
		blob(root, r(), r() * 0.45, 0.012, 0.016, WHITE, 0.2, z)
	end
	-- the neon grid floor: rows getting closer near the horizon, and lines fanning out
	local floor = rect(root, 0.5, 0.79, 1, 0.42, rgb(30, 14, 60), 0, 0, z)
	vgrad(floor, rgb(40, 16, 80), rgb(16, 10, 30))
	rect(root, 0.5, 0.58, 1, 0.012, rgb(255, 120, 230), 0, 0, z)
	for k = 1, 4 do
		rect(root, 0.5, 0.58 + (k / 4) ^ 1.6 * 0.42, 1, 0.008, rgb(80, 230, 255), 0, 0.35, z)
	end
	for k = -4, 4 do
		rect(root, 0.5 + k * 0.08, 0.79, 0.008, 0.44, rgb(80, 230, 255), k * 14, 0.4, z)
	end
	if not lite then -- circuit traces in the sky
		rect(root, 0.18, 0.18, 0.22, 0.01, rgb(255, 160, 60), 0, 0.3, z)
		rect(root, 0.29, 0.26, 0.01, 0.16, rgb(255, 160, 60), 0, 0.3, z)
		blob(root, 0.07, 0.18, 0.035, 0.045, rgb(255, 160, 60), 0.1, z)
		blob(root, 0.29, 0.34, 0.035, 0.045, rgb(255, 160, 60), 0.1, z)
	end
end

function Scenes.Any(root: Frame, r: () -> number, z: number, lite: boolean)
	vgrad(root, rgb(40, 110, 76), rgb(14, 46, 32))
	blob(root, 0.5, 0.45, 0.9, 0.9, rgb(255, 250, 220), 0.82, z) -- the lamp over the table
	blob(root, 0.5, 0.45, 0.55, 0.55, rgb(255, 250, 220), 0.85, z)
	for _ = 1, lite and 3 or 7 do
		local s = make("TextLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.06 + r() * 0.88, 0.08 + r() * 0.84), Size = UDim2.fromScale(0.1, 0.12), BackgroundTransparency = 1, Text = "✦", TextScaled = true, TextColor3 = rgb(255, 226, 140), TextTransparency = 0.45, ZIndex = z }, root)
		s.Rotation = r() * 40
	end
end

-- The painted place behind the creature, inside the art frame.
function CardStyle.scene(art: GuiObject, def: any, opts: { lite: boolean? }?)
	local fam = def.family
	local fn = Scenes[fam] or Scenes.Any
	if def.type == "Spell" and Scenes[fam] == nil then
		fn = Scenes.Any
	end
	local z = art.ZIndex
	local root = make("Frame", { Name = "Scene", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, ZIndex = z }, art)
	-- (the art frame's own gradient would tint the scene; the scene paints the whole window)
	for _, g in ipairs(art:GetChildren()) do
		if g:IsA("UIGradient") then
			g:Destroy()
		end
	end
	fn(root, seeded(def.id or "card"), z, (opts and opts.lite) == true)
	-- a soft shade along the bottom so the creature's feet stand out
	local shade = make("Frame", { Name = "Shade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.4), BackgroundColor3 = BLACK, BorderSizePixel = 0, ZIndex = z }, root)
	make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0.72) }, shade)
	return root
end

---------------------------------------------------------------------------
-- The card's body
---------------------------------------------------------------------------
local RARITY = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }

local function gem(parent: Instance, x: number, y: number, size: number, color: Color3)
	local g = make("Frame", { Name = "Gem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromOffset(size, size), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 3 }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, g)
	make("UIStroke", { Thickness = 2, Color = color:Lerp(BLACK, 0.5) }, g)
	make("UIGradient", { Rotation = 45, Color = ColorSequence.new(color:Lerp(WHITE, 0.6), color:Lerp(BLACK, 0.15)) }, g)
	return g
end

-- opts.radius: the card's corner radius in pixels; opts.compact: a hand card (fewer touches);
-- opts.gemSize: pixel size of the gems (default 12).
function CardStyle.dress(card: GuiObject, def: any, famColor: Color3, rarityColor: Color3, opts: { radius: number?, compact: boolean?, gemSize: number? }?)
	local o = opts or {}
	local radius = o.radius or 10
	local rank = RARITY[def.rarity] or 1
	-- the body: a gentle top-to-bottom shading of the family colour, with soft diagonal stripes
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WHITE, rgb(222, 222, 222)) }, card)
	local pattern = make("Frame", { Name = "Pattern", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 0 }, card)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, pattern)
	stripes(pattern, famColor:Lerp(WHITE, 0.7), famColor:Lerp(WHITE, 0.25), 10, 45)
	-- an inner border, like a printed frame
	local inner = make("Frame", { Name = "InnerFrame", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8), BackgroundTransparency = 1, ZIndex = 0 }, card)
	make("UICorner", { CornerRadius = UDim.new(0, math.max(2, radius - 4)) }, inner)
	make("UIStroke", { Thickness = 1.5, Color = famColor:Lerp(BLACK, 0.45), Transparency = 0.35 }, inner)
	-- the rarity's touches
	local size = o.gemSize or 12
	if rank >= 2 then
		gem(card, 0.5, 1, size + 2, rarityColor)
	end
	if rank >= 3 and not o.compact then
		gem(card, 0, 1, size, rarityColor)
		gem(card, 1, 1, size, rarityColor)
		gem(card, 1, 0, size, rarityColor)
	end
	if rank >= 4 then
		-- a holographic foil over the whole card (very faint, so the text stays easy to read)
		local holo = make("Frame", { Name = "Holo", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.88, BorderSizePixel = 0, ZIndex = 0 }, card)
		make("UICorner", { CornerRadius = UDim.new(0, radius) }, holo)
		make("UIGradient", {
			Rotation = 35,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb(255, 120, 160)),
				ColorSequenceKeypoint.new(0.25, rgb(255, 230, 120)),
				ColorSequenceKeypoint.new(0.5, rgb(130, 255, 200)),
				ColorSequenceKeypoint.new(0.75, rgb(120, 190, 255)),
				ColorSequenceKeypoint.new(1, rgb(220, 130, 255)),
			}),
		}, holo)
	end
end

return CardStyle

-- CozyTheme: every menu in warm wood, cream and honey instead of cool purple and navy. Client only.
--
-- The menus were all built on a dark purple-navy chrome (panels, tiles, outlines, lavender text).
-- Rather than retint hundreds of colors by hand in every screen, this watches the player's GUI and
-- turns that chrome warm as it appears (and whenever a script or tween changes it later):
--   dark purple / navy   -> dark chocolate and walnut browns
--   pale lavender / grey -> cream, parchment and soft tan (text, outlines)
-- Everything that means something keeps its color: gold, gems (blue), good (green), bad (red),
-- rarity and family colors (they're saturated, so the rules leave them alone), and anything
-- inside a frame with the attribute KeepColors = true (cards). The pack opening screens are
-- skipped entirely (they're all rarity light shows).
--
--   CozyTheme.color(c)          -> the cozy version of a Color3 (unchanged if it isn't chrome)
--   CozyTheme.attach(container) -- theme everything in it now and from now on (call once)

local CozyTheme = {}

-- The family and rarity colors are never touched (Robo's silver is pale enough to look like chrome).
local KEEP = {}
pcall(function()
	local CardData = require(script.Parent:WaitForChild("CardData"))
	for _, list in ipairs({ CardData.FamilyColors or {}, CardData.RarityColors or {} }) do
		for _, c in pairs(list) do
			KEEP[c[1] * 65536 + c[2] * 256 + c[3]] = true
		end
	end
end)

-- The pack opening screens (PackBrawl) are left as they are. The reveal renames the PackOpen
-- screen to PackBrawlReveal / PackBrawlFan when it takes over, so those are listed too (they
-- weren't, and the pulled cards came out recoloured: Spooky, Robo and Weather faces turned brown).
-- A ScreenGui with the KeepColors attribute is skipped whatever its name (PackOpen sets it).
local SKIP_GUIS = {
	PackDive = true,
	PackBrawlOut = true,
	PackBrawlGui = true,
	PackOpen = true,
	PackReveal = true,
	PackBrawlReveal = true,
	PackBrawlFan = true,
}

-- Converts one color. Idempotent: a converted color comes back unchanged (its hue is outside the
-- range that gets converted), so a property that is set again can't run away.
function CozyTheme.color(c)
	if KEEP[math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)] then
		return c
	end
	local h, s, v = c:ToHSV()
	if s < 0.04 then
		return c -- greys, black and white stay
	end
	if h >= 0.6 and h < 0.9 and v < 0.62 and s < 0.65 then
		-- dark chrome: chocolate (darkest) to walnut and toffee (lighter)
		return Color3.fromHSV(0.068, math.clamp(0.22 + s * 0.6, 0.28, 0.56), math.min(1, v * 1.06))
	end
	if h >= 0.66 and h < 0.9 and s < 0.25 then
		-- pale chrome: cream and parchment (text, light outlines)
		return Color3.fromHSV(0.09, math.clamp(s * 0.9 + 0.05, 0.06, 0.3), v)
	end
	if h >= 0.66 and h < 0.9 and s < 0.6 and v < 0.85 then
		-- mid lavender chrome (secondary buttons, outlines): toffee
		return Color3.fromHSV(0.075, math.clamp(0.2 + s * 0.6, 0.3, 0.55), math.min(1, v * 1.05))
	end
	return c
end
local cozy = CozyTheme.color

local function cozySequence(seq)
	local changed = false
	local points = {}
	for _, k in ipairs(seq.Keypoints) do
		local c = cozy(k.Value)
		if c ~= k.Value then
			changed = true
		end
		table.insert(points, ColorSequenceKeypoint.new(k.Time, c))
	end
	return changed and ColorSequence.new(points) or nil
end

local PROPS = {
	GuiObject = { "BackgroundColor3", "BorderColor3" },
	TextLabel = { "TextColor3", "TextStrokeColor3" },
	TextButton = { "TextColor3", "TextStrokeColor3" },
	TextBox = { "TextColor3", "TextStrokeColor3", "PlaceholderColor3" },
	ScrollingFrame = { "ScrollBarImageColor3" },
	UIStroke = { "Color" },
}

local function kept(inst, root)
	local p = inst
	while p and p ~= root do
		if p:GetAttribute("KeepColors") == true then
			return true
		end
		if p:IsA("ScreenGui") then
			return SKIP_GUIS[p.Name] == true
		end
		p = p.Parent
	end
	return false
end

local function propsOf(inst)
	local list = {}
	if inst:IsA("GuiObject") then
		for _, n in ipairs(PROPS.GuiObject) do
			table.insert(list, n)
		end
		for cls, names in pairs(PROPS) do
			if cls ~= "GuiObject" and inst:IsA(cls) then
				for _, n in ipairs(names) do
					table.insert(list, n)
				end
			end
		end
	elseif inst:IsA("UIStroke") then
		list = PROPS.UIStroke
	end
	return list
end

local function themeOne(inst, root)
	local isGradient = inst:IsA("UIGradient")
	local list = isGradient and {} or propsOf(inst)
	if #list == 0 and not isGradient then
		return
	end
	if kept(inst, root) then
		return
	end
	for _, name in ipairs(list) do
		local function apply()
			local ok, c = pcall(function()
				return inst[name]
			end)
			if ok and typeof(c) == "Color3" then
				local w = cozy(c)
				if w ~= c then
					inst[name] = w
				end
			end
		end
		apply()
		inst:GetPropertyChangedSignal(name):Connect(apply)
	end
	if isGradient then
		local function apply()
			local seq = cozySequence(inst.Color)
			if seq then
				inst.Color = seq
			end
		end
		apply()
		inst:GetPropertyChangedSignal("Color"):Connect(apply)
	end
end

local attached = {}
function CozyTheme.attach(container)
	if attached[container] then
		return
	end
	attached[container] = true
	for _, d in ipairs(container:GetDescendants()) do
		themeOne(d, container)
	end
	container.DescendantAdded:Connect(function(d)
		-- (deferred: a card sets KeepColors right after it is parented, and new objects often get
		-- their colors set just after they're parented too)
		task.defer(function()
			if d.Parent then
				themeOne(d, container)
			end
		end)
	end)
end

return CozyTheme

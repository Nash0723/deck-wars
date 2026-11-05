-- Small shared helpers for the Pack Brawl client modules: colors, easing, instance maker.

local Kit = {}

-- Where the Brawl Box floats: far above and away from everything else.
Kit.ORIGIN = Vector3.new(0, 2000, 0)
-- Creature models are built for the duel table; the arena shows them bigger.
Kit.SCALE = 1.6

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
Kit.rgb = rgb

Kit.TierColor = {
	Common = rgb(242, 230, 201),
	Rare = rgb(61, 165, 255),
	Epic = rgb(166, 77, 255),
	Mythic = rgb(255, 59, 92),
	Legendary = rgb(255, 194, 26),
	Secret = rgb(255, 255, 255),
}
Kit.TierAccent = {
	Common = rgb(138, 90, 60),
	Rare = rgb(255, 255, 255),
	Epic = rgb(255, 95, 210),
	Mythic = rgb(255, 138, 43),
	Legendary = rgb(255, 255, 255),
	Secret = rgb(10, 6, 18),
}
-- Post effects per tier: bloom intensity, bloom threshold, contrast, saturation, tint.
Kit.TierGrade = {
	Common = { 0.3, 1.8, 0.15, 0.1, rgb(255, 255, 255) },
	Rare = { 0.5, 1.5, 0.2, 0.15, rgb(232, 242, 255) },
	Epic = { 0.7, 1.3, 0.25, 0.2, rgb(255, 255, 255) },
	Mythic = { 0.9, 1.2, 0.3, 0.25, rgb(255, 237, 232) },
	Legendary = { 1.2, 1.0, 0.35, 0.3, rgb(255, 250, 235) },
	Secret = { 1.8, 0.8, 0.4, 0.35, rgb(255, 255, 255) },
}
-- Camera numbers per tier: base FOV, FOV punch, max shake (studs), max shake roll (degrees).
Kit.TierCamera = {
	Common = { 50, 4, 0.15, 0.8 },
	Rare = { 50, 6, 0.25, 1.5 },
	Epic = { 55, 8, 0.4, 2.5 },
	Mythic = { 55, 10, 0.6, 3.5 },
	Legendary = { 60, 12, 0.8, 5 },
	Secret = { 60, 14, 1.2, 7 },
}
Kit.FamilyColor = {
	Snack = rgb(255, 150, 90),
	Junk = rgb(140, 130, 110),
	Weather = rgb(120, 190, 255),
	Critter = rgb(150, 220, 110),
	Spooky = rgb(170, 110, 220),
	Robo = rgb(200, 200, 215),
	Any = rgb(240, 240, 240),
}

-- Rainbow color that cycles every 2 seconds (Secret).
function Kit.prism(t, offset)
	return Color3.fromHSV(((t / 2) + (offset or 0)) % 1, 0.75, 1)
end

function Kit.tierColor(tier, t)
	if tier == "Secret" then
		return Kit.prism(t or 0)
	end
	return Kit.TierColor[tier] or Kit.TierColor.Common
end

-- Easing (x from 0 to 1)
function Kit.outQuad(x)
	return 1 - (1 - x) * (1 - x)
end
function Kit.inQuad(x)
	return x * x
end
function Kit.inOutQuad(x)
	return x < 0.5 and 2 * x * x or 1 - (-2 * x + 2) ^ 2 / 2
end
function Kit.outCubic(x)
	return 1 - (1 - x) ^ 3
end
function Kit.outBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
function Kit.inOutSine(x)
	return -(math.cos(math.pi * x) - 1) / 2
end
function Kit.clamp01(x)
	return math.clamp(x, 0, 1)
end

-- Ring position { x, z } (+ height) to a world Vector3.
function Kit.world(p, y)
	return Kit.ORIGIN + Vector3.new(p.x, y or 0, p.z)
end

-- Instance.new + properties + parent in one go.
function Kit.make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- An anchored, non-colliding, non-queryable part (everything in the brawl is just for show).
function Kit.part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	if parent then
		p.Parent = parent
	end
	return p
end

-- Built-in particle textures that ship with Roblox.
Kit.TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
Kit.TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
Kit.TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

return Kit

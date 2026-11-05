-- Biome pulls: which world a pack opens in, and how each world escalates level by level.
-- Pure data plus small helpers (no instances), so the tests can check it headlessly.
-- The stage that plays these recipes is BiomeStage.luau; the levels come from Scripts.addEnv.
--
-- World levels: 0 Calm, 1 Stir, 2 Quake, 3 Awaken, 4 Sky Break, 5 World Turn (Secret only).
-- World keys are the match backdrops' keys (DeckWars.Backdrops): Candy, Meadow, Ice, Fire,
-- Space, Mall. Positions below are in the backdrop's own space (the Duel Table at 0, 0, 0).

local BiomeFx = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

BiomeFx.Levels = { [0] = "Calm", "Stir", "Quake", "Awaken", "Sky Break", "World Turn" }

-- The six pull worlds, in the order the seed picks from.
BiomeFx.Worlds = { "Candy", "Meadow", "Ice", "Fire", "Space", "Mall" }
BiomeFx.IsWorld = {}
for _, k in ipairs(BiomeFx.Worlds) do
	BiomeFx.IsWorld[k] = true
end

-- Each themed pack has a home world (by pack id, see Packs.luau).
BiomeFx.PackWorld = {
	snack = "Candy",
	critter = "Meadow",
	weather = "Ice",
	junk = "Fire",
	robo = "Space",
	spooky = "Mall",
}

-- The world a pull plays in. Themed packs: their home world. The Brawl Pack: the world the
-- player picked for the Duel Table (`choice`), or one picked by the pull's seed when that is the
-- room or "Surprise me". Never depends on the rolled card, so it gives nothing away.
function BiomeFx.worldFor(packId: string?, seed: number?, choice: string?): string
	local home = packId and BiomeFx.PackWorld[packId]
	if home then
		return home
	end
	if choice and BiomeFx.IsWorld[choice] then
		return choice
	end
	local s = math.floor(math.abs(tonumber(seed) or 0))
	return BiomeFx.Worlds[(s % #BiomeFx.Worlds) + 1]
end

-- How far the light leans toward the tier colour, and how much brighter, per level.
BiomeFx.Tint = { [0] = 0, 0.12, 0.16, 0.2, 0.24, 0.3 }
BiomeFx.Bright = { [0] = 1, 1.04, 1.08, 1.1, 1.16, 1.2 }
-- How much the world's own particles speed up per level (calm fake endings use Calm).
BiomeFx.ParticleRate = { [0] = 1, 2, 2.5, 3, 3.5, 3.5 }
BiomeFx.Calm = 0.3
-- How hard plants and small props sway per level (degrees).
BiomeFx.Sway = { [0] = 0, 2.5, 4, 5, 7, 7 }
-- The storm's share of its full rate per level (it starts at Awaken).
BiomeFx.Storm = { [0] = 0, 0, 0, 0.35, 1, 0 }
-- Take the Top: how high the table rises above the world, by tier (studs).
BiomeFx.Podium = { Common = 1.5, Rare = 2.5, Epic = 3.5, Mythic = 4.5, Legendary = 5.5, Secret = 6 }

-- Per world:
--   name        what players see
--   landmark    the set piece that wakes at level 3: { center = Vector3, radius = studs } picks
--               parts near a point; { named = "Landmark" } picks parts by name; { craters = true }
--               picks the volcano craters (glowing discs far out)
--   beaconTop   where the light pillar starts when the landmark has no top of its own
--   glow        the landmark's light and pillar colour
--   eye         the opening in the sky at level 4
--   stormTint   the sky and fog colour from level 3 on
--   storm       the level 3 to 4 weather: particle settings
--   floor       the podium column: { color, material }
--   banner      the banner that drops in when the fight calls for one
--   dust        dust puffs and knock-down dust
BiomeFx.Recipe = {
	Candy = {
		name = "Gumdrop Plaza",
		landmark = { center = Vector3.new(-150, 0, -70), radius = 50 },
		beaconTop = Vector3.new(-150, 77, -70),
		glow = rgb(255, 120, 190),
		eye = rgb(235, 30, 60),
		stormTint = rgb(255, 150, 205),
		storm = { colors = { rgb(255, 225, 60), rgb(80, 180, 255) }, size = { 0.35, 0.3 }, speed = { 8, 12 }, life = { 3, 4 }, rate = 160, spin = 180, down = true },
		floor = { color = rgb(235, 45, 80), material = Enum.Material.SmoothPlastic },
		banner = rgb(255, 120, 180),
		dust = rgb(255, 205, 230),
	},
	Meadow = {
		name = "Sunset Grasslands",
		landmark = { center = Vector3.new(-120, 0, -75), radius = 42 },
		beaconTop = Vector3.new(-120, 100, -75),
		glow = rgb(255, 205, 120),
		eye = rgb(255, 175, 95),
		stormTint = rgb(170, 95, 165),
		storm = { colors = { rgb(255, 170, 215), rgb(255, 250, 240) }, size = { 0.55, 0.45 }, speed = { 6, 10 }, life = { 3, 5 }, rate = 120, spin = 240, side = true },
		floor = { color = rgb(150, 112, 70), material = Enum.Material.Ground },
		banner = rgb(110, 175, 70),
		dust = rgb(190, 160, 110),
	},
	Ice = {
		name = "Frostglass Lake",
		landmark = { center = Vector3.new(110, 0, -170), radius = 72 },
		beaconTop = Vector3.new(110, 132, -170),
		glow = rgb(140, 240, 255),
		eye = rgb(120, 255, 190),
		stormTint = rgb(130, 170, 255),
		storm = { colors = { rgb(255, 255, 255), rgb(210, 235, 255) }, size = { 0.45, 0.35 }, speed = { 12, 18 }, life = { 3, 4 }, rate = 260, spin = 90, down = true },
		floor = { color = rgb(150, 210, 255), material = Enum.Material.Glacier },
		banner = rgb(120, 255, 200),
		dust = rgb(235, 245, 255),
	},
	Fire = {
		name = "Ember Caldera",
		landmark = { craters = true },
		beaconTop = Vector3.new(0, 120, -260),
		glow = rgb(255, 120, 30),
		eye = rgb(255, 80, 25),
		stormTint = rgb(200, 55, 30),
		storm = { colors = { rgb(255, 150, 60), rgb(90, 80, 80) }, size = { 0.5, 0.15 }, speed = { 3, 7 }, life = { 3, 5 }, rate = 140, spin = 60, down = true },
		floor = { color = rgb(40, 32, 38), material = Enum.Material.Basalt },
		banner = rgb(255, 110, 30),
		dust = rgb(120, 90, 80),
	},
	Space = {
		name = "Cosmic Void",
		landmark = { center = Vector3.new(-160, -45, -190), radius = 105 },
		beaconTop = Vector3.new(-160, 5, -190),
		glow = rgb(120, 230, 255),
		eye = rgb(200, 90, 255),
		stormTint = rgb(150, 80, 255),
		storm = { colors = { rgb(255, 255, 255), rgb(150, 230, 255) }, size = { 0.7, 0 }, speed = { 45, 65 }, life = { 1, 1.6 }, rate = 40, spin = 0, meteor = true },
		floor = { color = rgb(85, 78, 100), material = Enum.Material.Slate },
		banner = rgb(120, 230, 255),
		dust = rgb(170, 160, 200),
	},
	Mall = {
		name = "Midnight Mall",
		landmark = { named = "Landmark" },
		beaconTop = Vector3.new(-6, 52, -96),
		glow = rgb(255, 80, 200),
		eye = rgb(170, 255, 150),
		stormTint = rgb(110, 255, 170),
		storm = { colors = { rgb(170, 255, 150), rgb(120, 255, 220) }, size = { 0.5, 0.1 }, speed = { 3, 6 }, life = { 3, 5 }, rate = 90, spin = 120, up = true },
		floor = { color = rgb(90, 86, 104), material = Enum.Material.Concrete },
		banner = rgb(255, 80, 200),
		dust = rgb(140, 120, 170),
	},
}

function BiomeFx.recipe(world: string)
	return BiomeFx.Recipe[world] or BiomeFx.Recipe.Candy
end

-- Lighting for a level: the world's own lighting leaned toward the tier colour and, from
-- Awaken on, toward the world's storm colour. base = the world theme's lighting table.
function BiomeFx.lightingFor(base, level: number, tierColor: Color3, recipe)
	local tint = BiomeFx.Tint[level] or 0
	local storm = level >= 3 and level < 5 and 0.3 or 0
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	local function lean(c)
		if typeof(c) ~= "Color3" then
			return c
		end
		return c:Lerp(recipe.stormTint, storm):Lerp(tierColor, tint)
	end
	out.Ambient = lean(base.Ambient)
	out.OutdoorAmbient = lean(base.OutdoorAmbient)
	out.ColorShift_Top = lean(base.ColorShift_Top)
	if base.Brightness then
		out.Brightness = base.Brightness * (BiomeFx.Bright[level] or 1)
	end
	return out
end

return BiomeFx

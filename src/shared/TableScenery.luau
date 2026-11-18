-- The biome scenery on the Duel Table: what makes each lane look like its land (Soda Swamp,
-- Glitter Junkyard, Static Snowfield, Pillow Peaks, Mushroom Mall, Lava Laundromat).
--
-- Client only: MatchScreen.F.decorate calls TableScenery.build for every lane and keeps the parts
-- it gets back with the lane (so they drop onto the table with it and are rebuilt when a card
-- changes the land). Everything here is decoration: nothing can be clicked or touched.
--
-- What a lane gets, and why it never gets in the way of the fight:
--  * A border along both long sides of the lane (candy rope, snowbanks, stitched piping, a
--    riveted rail, mossy roots, a basalt curb with lava in its seam). It is at most ~0.14 studs
--    tall and runs outside the glowing pick frames, so the lanes read apart.
--  * Two small, flat touches on the ground (a soda puddle, an ice patch, a button...), only in the
--    gaps between the creature spots, never on a spot or the building foundation.
--  * Behind the back edge, on the felt, the land carries on as a low hill (a "berm" in the land's
--    own ground), with a little set piece on it: a big piece (a swirl lollipop, a snowy pine, a
--    giant toadstool...), a medium one beside it and small ones in front. On the far side these are
--    full size: they stand behind the enemy's buildings, so they frame the top of the board and
--    hide nothing. On your side the hill is lower and carries only the small pieces, since it sits
--    between your chair and the board.
--
-- Shapes are kept round and soft (ellipsoids via SpecialMesh spheres, balls and cylinders) and
-- each land has its own small palette. A few glows breathe slowly (TableScenery.animate) and the
-- far set pieces give off a gentle trickle of bubbles, glitter, snow, fluff, spores or steam.

local TableScenery = {}

local function c3(r, g, b)
	return Color3.fromRGB(r, g, b)
end
local M = Enum.Material
local WHITE = c3(255, 255, 255)

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

---------------------------------------------------------------------------
-- The kit: builds parts for one lane. `placer(foot, sc, yaw)` gives shape helpers whose offsets
-- are in studs from the foot, times the scale, turned by `yaw` about the vertical.
---------------------------------------------------------------------------
local function newKit(opts)
	local K = { parts = {}, life = {}, parent = opts.parent, rng = Random.new(opts.seed or 1) }
	function K.pick(list)
		return list[K.rng:NextInteger(1, #list)]
	end
	function K.num(a, b)
		return K.rng:NextNumber(a, b)
	end
	local function make(props, shadow)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = shadow and true or false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = M.SmoothPlastic
		p.Name = "Scenery"
		local mesh = props.mesh
		props.mesh = nil
		for k, v in pairs(props) do
			p[k] = v
		end
		if mesh then
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.Sphere
			m.Parent = p
		end
		p.Parent = K.parent
		table.insert(K.parts, p)
		return p
	end
	K.make = make

	function K.placer(foot, sc, yaw, shadow)
		yaw = yaw or 0
		local turn = CFrame.Angles(0, yaw, 0)
		local P = { sc = sc }
		local function at(o)
			return foot + (turn * CFrame.new(o[1] * sc, o[2] * sc, o[3] * sc)).Position
		end
		P.at = at
		local function put(props, o, rot)
			props.CFrame = CFrame.new(at(o)) * turn * (rot or CFrame.identity) * (props.CFrame or CFrame.identity)
			return make(props, shadow)
		end
		local function extra(e, t)
			if e then
				for k, v in pairs(e) do
					t[k] = v
				end
			end
			return t
		end
		-- a block centred at `o`
		function P.blk(size, o, color, mat, rot, e)
			return put(extra(e, { Size = Vector3.new(size[1] * sc, size[2] * sc, size[3] * sc), Color = color, Material = mat or M.SmoothPlastic }), o, rot)
		end
		-- a ball centred at `o`
		function P.ball(d, o, color, mat, e)
			return put(extra(e, { Shape = Enum.PartType.Ball, Size = Vector3.new(d * sc, d * sc, d * sc), Color = color, Material = mat or M.SmoothPlastic }), o)
		end
		-- an ellipsoid (x, y, z extents) centred at `o`
		function P.egg(size, o, color, mat, rot, e)
			return put(extra(e, { Size = Vector3.new(size[1] * sc, size[2] * sc, size[3] * sc), Color = color, Material = mat or M.SmoothPlastic, mesh = true }), o, rot)
		end
		-- a cylinder standing up, its bottom at `o` (`rot` leans it about its bottom)
		function P.cyl(h, d, o, color, mat, rot, e)
			local props = extra(e, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(h * sc, d * sc, d * sc), Color = color, Material = mat or M.SmoothPlastic })
			props.CFrame = CFrame.new(0, h * sc / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
			return put(props, o, rot)
		end
		-- a cylinder lying along the z axis (toward your chair), centred at `o`
		function P.tubeZ(len, d, o, color, mat, rot, e)
			local props = extra(e, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(len * sc, d * sc, d * sc), Color = color, Material = mat or M.SmoothPlastic })
			props.CFrame = CFrame.Angles(0, math.pi / 2, 0)
			return put(props, o, rot)
		end
		-- a cylinder lying along the x axis, centred at `o`
		function P.tubeX(len, d, o, color, mat, rot, e)
			return put(extra(e, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(len * sc, d * sc, d * sc), Color = color, Material = mat or M.SmoothPlastic }), o, rot)
		end
		-- a flat disc lying on the ground, centred at `o`
		function P.disc(d, t, o, color, mat, e)
			local props = extra(e, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(t * sc, d * sc, d * sc), Color = color, Material = mat or M.SmoothPlastic })
			props.CFrame = CFrame.Angles(0, 0, math.pi / 2)
			return put(props, o)
		end
		-- a disc standing up, facing your chair, centred at `o`
		function P.face(d, t, o, color, mat, rot, e)
			local props = extra(e, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(t * sc, d * sc, d * sc), Color = color, Material = mat or M.SmoothPlastic })
			props.CFrame = CFrame.Angles(0, -math.pi / 2, 0)
			return put(props, o, rot)
		end
		return P
	end

	-- make a part breathe: its transparency drifts between `lo` and `hi`
	function K.glow(p, lo, hi, speed)
		table.insert(K.life, { p = p, lo = lo, hi = hi, speed = speed or 1.4, phase = K.rng:NextNumber(0, 6.28) })
		return p
	end

	-- a soft, never-ending trickle of particles from a box (studs) centred at `pos`
	function K.emit(pos, box, cfg)
		local holder = make({ Name = "SceneryFx", Size = Vector3.new(math.max(0.1, box[1]), math.max(0.1, box[2]), math.max(0.1, box[3])), CFrame = CFrame.new(pos), Transparency = 1 })
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = TEX[cfg.tex] or TEX.smoke
		local keys = {}
		for i, c in ipairs(cfg.colors) do
			table.insert(keys, ColorSequenceKeypoint.new(#cfg.colors == 1 and 0 or (i - 1) / (#cfg.colors - 1), c))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, cfg.colors[1]))
		end
		pe.Color = ColorSequence.new(keys)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, cfg.size[1]), NumberSequenceKeypoint.new(1, cfg.size[2]) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, cfg.alpha or 0.35), NumberSequenceKeypoint.new(0.75, 0.6), NumberSequenceKeypoint.new(1, 1) })
		pe.Lifetime = NumberRange.new(cfg.life[1], cfg.life[2])
		pe.Speed = NumberRange.new(cfg.speed[1], cfg.speed[2])
		pe.SpreadAngle = Vector2.new(cfg.spread or 20, cfg.spread or 20)
		pe.EmissionDirection = cfg.dir or Enum.NormalId.Top
		pe.Acceleration = cfg.accel or Vector3.zero
		pe.Drag = cfg.drag or 0.5
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-40, 40)
		pe.LightEmission = cfg.glow or 0
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		pe.Rate = cfg.rate or 2
		pe.Parent = holder
		return pe
	end
	return K
end

---------------------------------------------------------------------------
-- The lands. Each has:
--   border(K, x, z0, z1, top, inward)  the strip along one long side of a lane (`inward` is the
--                                      x direction toward the lane's middle)
--   touch(K, P)                       a small flat thing on the ground (in a gap between spots)
--   big(K, P), mid(K, P), small(K, P) the set piece behind the back edge (P's foot is on the hill)
--   fx(K, pos, sc)                    the trickle of particles over a far set piece (optional)
---------------------------------------------------------------------------
local LANDS = {}

-- Soda Swamp (Snack): a candy shore. Swirl lollipops, ball pops, gumdrops, candy canes, fizzing soda.
do
	local CANDY = { c3(255, 84, 120), c3(255, 160, 50), c3(90, 200, 255), c3(170, 110, 255), c3(110, 225, 140), c3(255, 220, 80) }
	local CREAM = c3(255, 248, 240)
	local function swirlPop(K, P, h)
		local a = K.pick(CANDY)
		local b = K.rng:NextNumber() < 0.5 and CREAM or K.pick(CANDY)
		if b == a then
			b = CREAM
		end
		local d = 1.0
		P.cyl(h, 0.13, { 0, 0, 0 }, CREAM)
		local cy = h + d * 0.46
		-- rings of two colours, each smaller one a little thicker so it shows front and back
		for i, f in ipairs({ 1, 0.8, 0.6, 0.4, 0.2 }) do
			P.egg({ d * f, d * f, 0.2 + i * 0.035 }, { 0, cy, 0 }, (i % 2 == 1) and a or b, M.SmoothPlastic, nil, { Reflectance = 0.05 })
		end
		P.egg({ 0.2, 0.12, 0.06 }, { -0.2, cy + 0.22, 0.14 }, WHITE, M.SmoothPlastic, CFrame.Angles(0, 0, 0.6), { Transparency = 0.4 }) -- a shine
		-- a ribbon bow under the sweet
		P.egg({ 0.28, 0.14, 0.08 }, { -0.13, h + 0.02, 0.06 }, a:Lerp(WHITE, 0.3), nil, CFrame.Angles(0, 0, 0.45))
		P.egg({ 0.28, 0.14, 0.08 }, { 0.13, h + 0.02, 0.06 }, a:Lerp(WHITE, 0.3), nil, CFrame.Angles(0, 0, -0.45))
		P.ball(0.09, { 0, h + 0.02, 0.07 }, a)
	end
	local function ballPop(K, P, h)
		local a = K.pick(CANDY)
		P.cyl(h, 0.09, { 0, 0, 0 }, CREAM)
		P.ball(0.6, { 0, h + 0.27, 0 }, a, M.SmoothPlastic, { Reflectance = 0.08 })
		P.egg({ 0.62, 0.13, 0.62 }, { 0, h + 0.27, 0 }, a:Lerp(WHITE, 0.55), nil, CFrame.Angles(0.35, 0, 0.2)) -- a stripe round it
		P.ball(0.12, { -0.13, h + 0.43, 0.2 }, WHITE, M.SmoothPlastic, { Transparency = 0.35 }) -- a shine
	end
	local function cane(K, P, h)
		local red, white = c3(225, 40, 60), CREAM
		local n = 8
		for i = 0, n - 1 do
			P.cyl(h / n + 0.01, 0.15, { 0, i * h / n, 0 }, (i % 2 == 0) and red or white)
		end
		-- the hook: beads along a half circle
		local r = 0.24
		for i = 1, 9 do
			local ang = i / 9 * math.pi
			P.ball(0.155, { r - math.cos(ang) * r, h + math.sin(ang) * r, 0 }, (math.floor(i / 2) % 2 == 0) and white or red)
		end
	end
	local function gumdrop(K, P, d, o, col)
		col = col or K.pick(CANDY)
		P.egg({ d, d * 0.95, d }, { o[1], 0, o[3] }, col, M.SmoothPlastic, nil, { Reflectance = 0.05 }) -- half sunk: a dome
		for k = 1, 3 do
			local a = k * 2.1
			P.ball(d * 0.09, { o[1] + math.cos(a) * d * 0.22, d * 0.4, o[3] + math.sin(a) * d * 0.22 }, WHITE) -- sugar
		end
	end
	local function bonbon(K, P, o)
		-- a wrapped sweet: the candy and the two twisted ends of its wrapper
		local a = K.pick(CANDY)
		P.egg({ 0.42, 0.26, 0.26 }, { o[1], 0.13, o[3] }, a)
		P.egg({ 0.16, 0.22, 0.22 }, { o[1] - 0.27, 0.13, o[3] }, a:Lerp(WHITE, 0.4))
		P.egg({ 0.16, 0.22, 0.22 }, { o[1] + 0.27, 0.13, o[3] }, a:Lerp(WHITE, 0.4))
	end
	local function soda(K, P, h)
		local glass = K.pick({ c3(130, 70, 40), c3(70, 150, 90), c3(220, 110, 50) })
		P.cyl(h * 0.6, 0.44, { 0, 0, 0 }, glass, M.Glass, nil, { Transparency = 0.2 })
		P.egg({ 0.44, 0.3, 0.44 }, { 0, h * 0.6, 0 }, glass, M.Glass, nil, { Transparency = 0.2 })
		P.cyl(h * 0.28, 0.16, { 0, h * 0.62, 0 }, glass, M.Glass, nil, { Transparency = 0.2 })
		P.cyl(0.07, 0.2, { 0, h * 0.9, 0 }, c3(225, 45, 60), M.Metal)
		P.cyl(h * 0.24, 0.46, { 0, h * 0.18, 0 }, c3(255, 240, 215)) -- the label
		P.cyl(0.04, 0.47, { 0, h * 0.3, 0 }, c3(225, 45, 60)) -- a red stripe on it
	end
	LANDS.Snack = {
		border = function(K, x, z0, z1, top, inward)
			-- a candy rope: cream with red bands
			local P = K.placer(Vector3.new(x, top + 0.06, (z0 + z1) / 2), 1)
			local len = z1 - z0
			P.tubeZ(len, 0.12, { 0, 0, 0 }, c3(255, 246, 236))
			local n = math.floor(len / 0.6)
			for i = 0, n - 1 do
				P.tubeZ(0.16, 0.135, { 0, 0, -len / 2 + (i + 0.5) * len / n }, c3(230, 50, 75))
			end
		end,
		touch = function(K, P)
			-- a fizzing soda puddle
			P.egg({ 0.75, 0.04, 0.52 }, { 0, 0.005, 0 }, c3(190, 100, 45), M.Glass, nil, { Transparency = 0.2 })
			P.egg({ 0.5, 0.045, 0.32 }, { -0.05, 0.006, -0.02 }, c3(235, 150, 80), M.Glass, nil, { Transparency = 0.35 })
			for k = 1, 3 do
				K.glow(P.ball(0.06 + k * 0.012, { (k - 2) * 0.14, 0.03, (k % 2) * 0.08 - 0.04 }, c3(255, 240, 210), M.Neon), 0.1, 0.75, 1.6 + k * 0.4)
			end
		end,
		big = function(K, P)
			if K.rng:NextNumber() < 0.65 then
				swirlPop(K, P, K.num(1.25, 1.5))
			else
				cane(K, P, K.num(1.5, 1.8))
			end
		end,
		mid = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				ballPop(K, P, K.num(0.7, 0.85))
			else
				soda(K, P, K.num(0.9, 1.05))
			end
		end,
		small = function(K, P)
			if K.rng:NextNumber() < 0.6 then
				gumdrop(K, P, K.num(0.36, 0.48), { 0, 0, 0 })
				gumdrop(K, P, 0.26, { 0.3, 0, 0.12 })
			else
				bonbon(K, P, { 0, 0, 0 })
			end
		end,
		fx = function(K, pos, sc)
			K.emit(pos + Vector3.new(0, 1.2 * sc, 0), { 1.2 * sc, 0.6 * sc, 0.5 * sc }, { tex = "spark", colors = { c3(255, 245, 225), c3(255, 190, 120) }, size = { 0.1, 0.03 }, life = { 1.5, 2.5 }, speed = { 0.2, 0.45 }, accel = Vector3.new(0, 0.35, 0), rate = 2, glow = 0.6, spread = 40, alpha = 0.25 })
		end,
	}
end

-- Glitter Junkyard (Junk): scrap towers with a mirror ball, old TVs, tyres, crates, glitter.
do
	local RUST = { c3(160, 90, 55), c3(85, 125, 130), c3(125, 118, 112), c3(175, 140, 70), c3(115, 75, 95) }
	local GLITTER = { c3(255, 110, 215), c3(255, 225, 100), c3(120, 225, 255) }
	local function tyre(K, P, d, o, lying)
		if lying then
			P.cyl(0.26, d, { o[1], o[2] or 0, o[3] }, c3(38, 34, 36), M.Rubber)
			P.cyl(0.27, d * 0.45, { o[1], o[2] or 0, o[3] }, c3(150, 150, 160), M.Metal)
		else
			P.face(d, 0.26, { o[1], d / 2 - 0.05, o[3] }, c3(38, 34, 36), M.Rubber)
			P.face(d * 0.45, 0.27, { o[1], d / 2 - 0.05, o[3] }, c3(150, 150, 160), M.Metal)
		end
	end
	local function crate(K, P, s, o, rot)
		local col = K.pick({ c3(150, 110, 70), c3(120, 90, 60) })
		P.blk({ s, s, s }, { o[1], (o[2] or 0) + s / 2, o[3] }, col, M.WoodPlanks, rot)
		P.blk({ s + 0.02, 0.06, s + 0.02 }, { o[1], (o[2] or 0) + s * 0.5, o[3] }, col:Lerp(c3(40, 30, 20), 0.4), M.Wood, rot)
	end
	local function tv(K, P, o, rot)
		P.blk({ 0.62, 0.5, 0.48 }, { o[1], (o[2] or 0) + 0.25, o[3] }, K.pick(RUST), M.Metal, rot)
		local screen = P.blk({ 0.46, 0.34, 0.04 }, { o[1], (o[2] or 0) + 0.26, o[3] + 0.24 }, K.pick(GLITTER), M.Neon, rot)
		K.glow(screen, 0.05, 0.4, 2.6)
		P.cyl(0.32, 0.03, { o[1] - 0.1, (o[2] or 0) + 0.5, o[3] }, c3(60, 60, 65), M.Metal, CFrame.Angles(0, 0, 0.5))
		P.cyl(0.32, 0.03, { o[1] + 0.1, (o[2] or 0) + 0.5, o[3] }, c3(60, 60, 65), M.Metal, CFrame.Angles(0, 0, -0.5))
	end
	LANDS.Junk = {
		border = function(K, x, z0, z1, top, inward)
			-- a riveted metal rail
			local P = K.placer(Vector3.new(x, top, (z0 + z1) / 2), 1)
			local len = z1 - z0
			P.blk({ 0.11, 0.08, len }, { 0, 0.04, 0 }, c3(120, 95, 80), M.CorrodedMetal)
			local n = math.floor(len / 0.9)
			for i = 0, n - 1 do
				P.ball(0.07, { 0, 0.085, -len / 2 + (i + 0.5) * len / n }, c3(200, 190, 170), M.Metal)
			end
		end,
		touch = function(K, P)
			if K.rng:NextNumber() < 0.6 then
				-- an oil puddle with a glittery sheen
				P.egg({ 0.78, 0.035, 0.55 }, { 0, 0.005, 0 }, c3(35, 30, 40), M.SmoothPlastic, nil, { Reflectance = 0.3 })
				K.glow(P.egg({ 0.5, 0.04, 0.3 }, { 0.06, 0.008, 0.02 }, K.pick(GLITTER), M.Neon, nil, { Transparency = 0.5 }), 0.45, 0.8, 1.2)
			else
				P.cyl(0.07, 0.17, { -0.1, 0, 0 }, c3(160, 160, 170), M.Metal) -- a nut
				P.disc(0.24, 0.035, { 0.16, 0.018, 0.08 }, K.pick({ c3(220, 60, 60), c3(70, 140, 230) }), M.Metal) -- a bottle cap
			end
		end,
		big = function(K, P)
			-- a scrap tower: a tyre, a crate and a TV piled up, a mirror ball on a pole on top
			tyre(K, P, 0.8, { 0, 0.02, 0 }, true)
			crate(K, P, 0.55, { 0.03, 0.27, 0 }, CFrame.Angles(0, 0.3, 0))
			tv(K, P, { -0.02, 0.82, 0.02 }, CFrame.Angles(0, -0.2, 0.05))
			P.cyl(0.55, 0.05, { 0.12, 1.3, -0.05 }, c3(140, 140, 150), M.Metal)
			local ball = P.ball(0.3, { 0.12, 1.95, -0.05 }, c3(220, 220, 235), M.Foil, { Reflectance = 0.5 })
			K.glow(P.ball(0.1, { 0.04, 2.0, 0.08 }, K.pick(GLITTER), M.Neon), 0, 0.7, 2)
			return ball
		end,
		mid = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				tyre(K, P, 0.75, { 0, 0, 0 }, true)
				tyre(K, P, 0.72, { 0.02, 0.26, 0 }, true)
				tyre(K, P, 0.7, { 0, 0.52, 0 }, false)
			else
				-- a crooked neon sign
				P.cyl(1.0, 0.07, { 0, 0, 0 }, c3(100, 95, 95), M.CorrodedMetal, CFrame.Angles(0, 0, 0.08))
				P.blk({ 0.72, 0.38, 0.06 }, { 0.06, 1.0, 0.05 }, c3(60, 40, 70), M.Metal, CFrame.Angles(0, 0, -0.1))
				K.glow(P.blk({ 0.58, 0.07, 0.07 }, { 0.06, 1.06, 0.08 }, c3(255, 120, 220), M.Neon, CFrame.Angles(0, 0, -0.1)), 0, 0.55, 2.4)
				K.glow(P.blk({ 0.4, 0.07, 0.07 }, { 0.06, 0.94, 0.08 }, c3(120, 225, 255), M.Neon, CFrame.Angles(0, 0, -0.1)), 0, 0.55, 1.9)
			end
		end,
		small = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				crate(K, P, 0.36, { 0, 0, 0 }, CFrame.Angles(0, K.num(-0.5, 0.5), 0))
			else
				-- a dented can on its side
				P.tubeX(0.34, 0.2, { 0, 0.1, 0 }, K.pick({ c3(220, 60, 60), c3(70, 160, 230), c3(90, 200, 120) }), M.Metal, CFrame.Angles(0, K.num(-1, 1), 0))
			end
			K.glow(P.ball(0.07, { 0.25, 0.05, 0.15 }, K.pick(GLITTER), M.Neon), 0, 0.7, 2.5)
		end,
		fx = function(K, pos, sc)
			K.emit(pos + Vector3.new(0, 1.2 * sc, 0), { 1.4 * sc, 1.2 * sc, 0.6 * sc }, { tex = "spark", colors = GLITTER, size = { 0.12, 0.02 }, life = { 0.8, 1.4 }, speed = { 0.05, 0.2 }, accel = Vector3.new(0, -0.2, 0), rate = 2, glow = 1, spread = 180, alpha = 0.2 })
		end,
	}
end

-- Static Snowfield (Weather): snowy pines, snowmen, ice crystals that crackle, snowdrifts.
do
	local PINE, SNOW, ICE = c3(38, 92, 78), c3(246, 250, 255), c3(175, 228, 255)
	local function pine(K, P, h)
		P.cyl(h * 0.2, 0.16, { 0, 0, 0 }, c3(100, 70, 50), M.Wood)
		local tiers = 4
		for i = 0, tiers - 1 do
			local f = 1 - i / tiers
			local y = h * 0.2 + i * h * 0.19
			local w = h * 0.5 * f + 0.18
			P.egg({ w, h * 0.26, w }, { 0, y + h * 0.1, 0 }, PINE:Lerp(c3(20, 60, 50), i * 0.08), M.Grass)
			P.egg({ w * 0.6, h * 0.07, w * 0.6 }, { 0, y + h * 0.21, 0 }, SNOW, M.Snow) -- a cap of snow on the tier
		end
		P.ball(h * 0.09, { 0, h * 1.0, 0 }, SNOW, M.Snow)
	end
	local function crystal(K, P, h)
		for k = -1, 1 do
			local hh = h * (k == 0 and 1 or 0.62)
			P.blk({ 0.17, hh, 0.17 }, { k * 0.13, hh / 2 - 0.04, 0 }, ICE, M.Ice, CFrame.Angles(0, 0.78, k * 0.32), { Transparency = 0.15, Reflectance = 0.2 })
		end
		K.glow(P.blk({ 0.05, h * 0.7, 0.05 }, { 0, h * 0.37, 0.02 }, c3(210, 245, 255), M.Neon), 0, 0.85, 3.2) -- static crackling in its core
	end
	local function snowman(K, P, h)
		P.ball(h * 0.5, { 0, h * 0.2, 0 }, SNOW, M.Snow)
		P.ball(h * 0.37, { 0, h * 0.56, 0 }, SNOW, M.Snow)
		P.ball(h * 0.27, { 0, h * 0.84, 0 }, SNOW, M.Snow)
		P.cyl(0.18, 0.045, { 0, h * 0.83, h * 0.12 }, c3(255, 140, 40), nil, CFrame.Angles(math.pi / 2, 0, 0)) -- carrot nose
		for _, sx in ipairs({ -1, 1 }) do
			P.ball(0.045, { sx * h * 0.06, h * 0.89, h * 0.12 }, c3(30, 30, 35)) -- coal eyes
			P.cyl(h * 0.35, 0.035, { sx * h * 0.16, h * 0.6, 0 }, c3(110, 75, 50), M.Wood, CFrame.Angles(0, 0, -sx * 1.0)) -- stick arms
		end
		P.cyl(0.08, h * 0.3, { 0, h * 0.7, 0 }, c3(80, 160, 235), M.Fabric) -- a scarf
		P.blk({ 0.08, 0.2, 0.04 }, { h * 0.08, h * 0.63, h * 0.14 }, c3(80, 160, 235), M.Fabric, CFrame.Angles(0, 0, 0.2))
	end
	LANDS.Weather = {
		border = function(K, x, z0, z1, top, inward)
			-- a soft snowbank
			local P = K.placer(Vector3.new(x, top, (z0 + z1) / 2), 1)
			local len = z1 - z0
			local n = 3
			for i = 0, n - 1 do
				P.egg({ 0.2, 0.2, len / n * 1.25 }, { 0, 0.02, -len / 2 + (i + 0.5) * len / n }, SNOW, M.Snow)
			end
		end,
		touch = function(K, P)
			if K.rng:NextNumber() < 0.55 then
				P.egg({ 0.7, 0.03, 0.5 }, { 0, 0.005, 0 }, ICE, M.Ice, nil, { Transparency = 0.2, Reflectance = 0.25 })
			else
				P.egg({ 0.42, 0.2, 0.32 }, { 0, 0, 0 }, SNOW, M.Snow)
				P.egg({ 0.26, 0.14, 0.22 }, { 0.22, 0, 0.1 }, SNOW, M.Snow)
			end
		end,
		big = function(K, P)
			pine(K, P, K.num(1.8, 2.2))
		end,
		mid = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				snowman(K, P, K.num(0.95, 1.1))
			else
				pine(K, P, K.num(1.0, 1.2))
			end
		end,
		small = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				crystal(K, P, K.num(0.45, 0.6))
			else
				P.egg({ 0.6, 0.32, 0.45 }, { 0, 0, 0 }, SNOW, M.Snow) -- a snowdrift
				P.egg({ 0.36, 0.22, 0.3 }, { 0.28, 0, 0.1 }, SNOW, M.Snow)
			end
		end,
		fx = function(K, pos, sc)
			K.emit(pos + Vector3.new(0, 2.6 * sc, 0), { 2.2 * sc, 0.1, 1.2 * sc }, { tex = "spark", colors = { SNOW, ICE }, size = { 0.09, 0.06 }, life = { 3, 4 }, speed = { 0.3, 0.6 }, dir = Enum.NormalId.Bottom, accel = Vector3.new(0, -0.1, 0), rate = 3, glow = 0.4, spread = 25, alpha = 0.2 })
		end,
	}
end

-- Pillow Peaks (Critter): plump pillows, a giant sewing spool and needle, yarn balls, buttons.
do
	local PASTEL = { c3(255, 196, 222), c3(196, 222, 255), c3(255, 238, 180), c3(205, 245, 205), c3(228, 206, 255) }
	local function pillow(K, P, w, o, rot)
		local col = K.pick(PASTEL)
		P.egg({ w, w * 0.3, w * 0.72 }, o, col, M.Fabric, rot)
		-- the four corners pinch out into little tufts
		local cf = rot or CFrame.identity
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			local off = (cf * CFrame.new(c[1] * w * 0.4, 0, c[2] * w * 0.27)).Position
			P.egg({ w * 0.2, w * 0.12, w * 0.2 }, { o[1] + off.X, o[2], o[3] + off.Z }, col:Lerp(WHITE, 0.15), M.Fabric, rot)
		end
		P.ball(0.08, { o[1], o[2] + w * 0.14, o[3] }, col:Lerp(c3(90, 70, 110), 0.35), M.Fabric) -- the button in its middle
	end
	local function pillowStack(K, P, n)
		local y = 0.1
		for i = 1, n do
			local w = 1.0 - i * 0.1
			pillow(K, P, w, { K.num(-0.06, 0.06), y, K.num(-0.04, 0.04) }, CFrame.Angles(0, K.num(-0.35, 0.35), K.num(-0.06, 0.06)))
			y = y + w * 0.26
		end
	end
	local function pillowFort(K, P)
		-- a little mountain of pillows with a pennant on its peak
		local rows = {
			{ -0.46, 0.12, 0.05, 0.95 }, { 0.46, 0.12, 0.05, 0.95 }, { 0, 0.12, -0.35, 0.95 },
			{ -0.22, 0.4, -0.08, 0.85 }, { 0.25, 0.4, -0.05, 0.85 },
			{ 0.02, 0.66, -0.06, 0.75 },
		}
		for _, r in ipairs(rows) do
			pillow(K, P, r[4], { r[1], r[2], r[3] }, CFrame.Angles(0, K.num(-0.3, 0.3), K.num(-0.08, 0.08)))
		end
		P.cyl(0.75, 0.04, { 0.02, 0.72, -0.06 }, c3(150, 110, 80), M.Wood)
		P.blk({ 0.34, 0.2, 0.03 }, { 0.19, 1.34, -0.06 }, K.pick(PASTEL):Lerp(c3(255, 110, 150), 0.4), M.Fabric, CFrame.Angles(0, 0, -0.08))
	end
	local function spool(K, P)
		local wood = c3(225, 190, 140)
		local thread = K.pick({ c3(255, 120, 160), c3(120, 170, 255), c3(140, 210, 120) })
		P.cyl(0.12, 0.9, { 0, 0, 0 }, wood, M.Wood)
		P.cyl(0.8, 0.66, { 0, 0.12, 0 }, thread, M.Fabric)
		P.cyl(0.12, 0.9, { 0, 0.92, 0 }, wood, M.Wood)
		-- a big needle stuck in, leaning
		P.cyl(1.3, 0.06, { 0.12, 0.95, 0.05 }, c3(210, 215, 225), M.Metal, CFrame.Angles(0.05, 0, -0.35))
		-- the loose thread hanging down
		P.tubeX(0.5, 0.04, { 0.42, 0.5, 0.2 }, thread, M.Fabric, CFrame.Angles(0, 0.4, 1.2))
	end
	local function yarn(K, P, d, o)
		local col = K.pick(PASTEL):Lerp(c3(255, 110, 150), 0.35)
		P.ball(d, { o[1], d / 2 - 0.04, o[3] }, col, M.Fabric)
		P.egg({ d * 1.03, d * 0.25, d * 1.03 }, { o[1], d / 2 - 0.04, o[3] }, col:Lerp(WHITE, 0.25), M.Fabric, CFrame.Angles(0.6, 0, 0.3))
		P.egg({ d * 1.03, d * 0.25, d * 1.03 }, { o[1], d / 2 - 0.04, o[3] }, col:Lerp(WHITE, 0.25), M.Fabric, CFrame.Angles(-0.5, 0.8, 0))
		P.tubeX(0.4, 0.04, { o[1] + d * 0.55, 0.02, o[3] + 0.08 }, col, M.Fabric, CFrame.Angles(0, 0.5, 0))
	end
	LANDS.Critter = {
		border = function(K, x, z0, z1, top, inward)
			-- a plump piped seam with white stitches beside it
			local P = K.placer(Vector3.new(x, top, (z0 + z1) / 2), 1)
			local len = z1 - z0
			P.tubeZ(len, 0.11, { 0, 0.04, 0 }, c3(255, 236, 244), M.Fabric)
			local n = math.floor(len / 0.55)
			for i = 0, n - 1 do
				P.blk({ 0.03, 0.02, 0.16 }, { inward * 0.12, 0.005, -len / 2 + (i + 0.5) * len / n }, WHITE, M.Fabric)
			end
		end,
		touch = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				local col = K.pick(PASTEL):Lerp(c3(90, 70, 110), 0.25)
				P.disc(0.34, 0.04, { 0, 0.02, 0 }, col)
				for _, d in ipairs({ { -0.055, -0.055 }, { 0.055, -0.055 }, { -0.055, 0.055 }, { 0.055, 0.055 } }) do
					P.disc(0.05, 0.05, { d[1], 0.025, d[2] }, c3(60, 45, 70))
				end
			else
				P.egg({ 0.3, 0.16, 0.26 }, { 0, 0.03, 0 }, c3(255, 250, 248), M.Fabric)
				P.egg({ 0.2, 0.12, 0.18 }, { 0.17, 0.02, 0.08 }, c3(255, 234, 244), M.Fabric)
			end
		end,
		big = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				spool(K, P)
			else
				pillowFort(K, P)
			end
		end,
		mid = function(K, P)
			pillowStack(K, P, K.rng:NextInteger(2, 3))
		end,
		small = function(K, P)
			yarn(K, P, K.num(0.36, 0.44), { 0, 0, 0 })
		end,
		fx = function(K, pos, sc)
			K.emit(pos + Vector3.new(0, 0.9 * sc, 0), { 1.4 * sc, 0.4 * sc, 0.6 * sc }, { tex = "smoke", colors = { c3(255, 250, 245), c3(255, 225, 240) }, size = { 0.16, 0.28 }, life = { 2.5, 3.5 }, speed = { 0.1, 0.25 }, accel = Vector3.new(0, 0.05, 0), rate = 1, spread = 60, alpha = 0.45 })
		end,
	}
end

-- Mushroom Mall (Spooky): giant glowing toadstools, mall lanterns, drifting spores.
do
	local CAPS = { c3(175, 90, 235), c3(235, 90, 165), c3(80, 200, 175), c3(125, 110, 235) }
	local STEM = c3(236, 226, 212)
	local function toadstool(K, P, h, d, o, cap)
		cap = cap or K.pick(CAPS)
		o = o or { 0, 0, 0 }
		P.cyl(h * 0.85, d * 0.24, { o[1], 0, o[3] }, STEM)
		P.egg({ d * 0.36, d * 0.2, d * 0.36 }, { o[1], 0.02, o[3] }, STEM) -- a swollen foot
		K.glow(P.egg({ d * 0.86, d * 0.16, d * 0.86 }, { o[1], h * 0.86, o[3] }, cap:Lerp(WHITE, 0.45), M.Neon), 0.25, 0.65, 0.9) -- glowing gills
		P.egg({ d, d * 0.52, d }, { o[1], h * 0.92, o[3] }, cap)
		for k = 1, 4 do
			local a = k / 4 * math.pi * 2 + K.num(0, 1)
			local r = d * (k % 2 == 0 and 0.15 or 0.3)
			local y = h * 0.92 + d * 0.26 * math.sqrt(1 - (r / (d * 0.5)) ^ 2) -- (on the cap's surface)
			P.egg({ d * 0.15, d * 0.07, d * 0.15 }, { o[1] + math.cos(a) * r, y, o[3] + math.sin(a) * r }, c3(250, 244, 255), M.SmoothPlastic)
		end
	end
	local function lantern(K, P, h)
		P.cyl(h, 0.08, { 0, 0, 0 }, c3(45, 35, 60), M.Metal)
		P.cyl(0.08, 0.26, { 0, 0, 0 }, c3(45, 35, 60), M.Metal)
		P.tubeX(0.34, 0.05, { 0.15, h - 0.04, 0 }, c3(45, 35, 60), M.Metal)
		P.egg({ 0.3, 0.08, 0.3 }, { 0.3, h - 0.08, 0 }, c3(45, 35, 60), M.Metal)
		K.glow(P.ball(0.22, { 0.3, h - 0.22, 0 }, c3(150, 255, 205), M.Neon), 0, 0.3, 0.9)
	end
	LANDS.Spooky = {
		border = function(K, x, z0, z1, top, inward)
			-- a mossy root with little glowing mushrooms growing on it
			local P = K.placer(Vector3.new(x, top, (z0 + z1) / 2), 1)
			local len = z1 - z0
			P.tubeZ(len, 0.11, { 0, 0.04, 0 }, c3(70, 50, 75), M.Wood)
			for _, f in ipairs({ -0.3, 0.05, 0.38 }) do
				local z = f * len + K.num(-0.3, 0.3)
				P.cyl(0.1, 0.035, { 0, 0.07, z }, STEM)
				K.glow(P.egg({ 0.1, 0.05, 0.1 }, { 0, 0.18, z }, K.pick(CAPS):Lerp(WHITE, 0.2), M.Neon), 0.1, 0.6, K.num(0.7, 1.3))
			end
		end,
		touch = function(K, P)
			if K.rng:NextNumber() < 0.55 then
				toadstool(K, P, 0.18, 0.2, { 0, 0, 0 })
				toadstool(K, P, 0.12, 0.14, { 0.14, 0, 0.1 })
			else
				P.blk({ 0.42, 0.02, 0.42 }, { -0.1, 0.01, 0 }, c3(70, 58, 88), M.Slate, CFrame.Angles(0, K.num(-0.3, 0.3), 0))
				P.blk({ 0.3, 0.02, 0.3 }, { 0.2, 0.01, 0.18 }, c3(86, 72, 104), M.Slate, CFrame.Angles(0, K.num(-0.3, 0.3), 0))
			end
		end,
		big = function(K, P)
			toadstool(K, P, K.num(1.6, 1.9), K.num(1.25, 1.45))
		end,
		mid = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				lantern(K, P, K.num(1.2, 1.4))
			else
				local cap = K.pick(CAPS)
				toadstool(K, P, 0.95, 0.8, { 0, 0, 0 }, cap)
				toadstool(K, P, 0.55, 0.48, { 0.42, 0, 0.12 }, cap)
			end
		end,
		small = function(K, P)
			toadstool(K, P, 0.38, 0.36, { 0, 0, 0 })
			toadstool(K, P, 0.26, 0.26, { 0.25, 0, 0.1 })
		end,
		fx = function(K, pos, sc)
			K.emit(pos + Vector3.new(0, 1.0 * sc, 0), { 1.6 * sc, 1.0 * sc, 0.8 * sc }, { tex = "spark", colors = { c3(205, 145, 255), c3(140, 255, 205) }, size = { 0.1, 0.03 }, life = { 2.5, 4 }, speed = { 0.08, 0.2 }, accel = Vector3.new(0, 0.12, 0), rate = 2, glow = 0.9, spread = 180, alpha = 0.3 })
		end,
	}
end

-- Lava Laundromat (Robo): washers with lava churning in the drum, a steaming vent, laundry.
do
	local LAVA = c3(255, 125, 30)
	local function washer(K, P, h)
		local body = K.pick({ c3(236, 238, 242), c3(205, 215, 225), c3(175, 190, 205) })
		P.blk({ 0.95, h, 0.85 }, { 0, h / 2, 0 }, body, M.Metal)
		P.blk({ 0.95, h * 0.16, 0.06 }, { 0, h * 0.9, 0.43 }, c3(60, 65, 78), M.Metal) -- the control strip
		K.glow(P.face(0.1, 0.04, { 0.3, h * 0.9, 0.47 }, c3(120, 255, 150), M.Neon), 0, 0.5, 2)
		P.face(0.12, 0.04, { 0.12, h * 0.9, 0.47 }, c3(200, 200, 210), M.Metal)
		P.face(h * 0.64, 0.06, { 0, h * 0.42, 0.43 }, c3(70, 75, 88), M.Metal) -- the door rim
		K.glow(P.face(h * 0.5, 0.08, { 0, h * 0.42, 0.43 }, LAVA, M.Neon), 0, 0.3, 1.1) -- lava in the drum
		P.face(h * 0.22, 0.09, { h * 0.08, h * 0.47, 0.43 }, c3(255, 210, 120), M.Neon) -- a hot swirl
	end
	local function vent(K, P, h)
		-- a tall steaming pipe with a glowing crown
		P.cyl(h, 0.36, { 0, 0, 0 }, c3(90, 95, 108), M.Metal)
		for _, f in ipairs({ 0.3, 0.65 }) do
			P.cyl(0.06, 0.42, { 0, h * f, 0 }, c3(60, 62, 72), M.Metal)
		end
		K.glow(P.cyl(0.08, 0.4, { 0, h - 0.04, 0 }, LAVA, M.Neon), 0, 0.35, 1)
	end
	local function basket(K, P)
		local wicker = c3(195, 155, 100)
		P.blk({ 0.66, 0.04, 0.48 }, { 0, 0.02, 0 }, wicker, M.WoodPlanks)
		for _, s in ipairs({ -1, 1 }) do
			P.blk({ 0.66, 0.32, 0.04 }, { 0, 0.16, s * 0.23 }, wicker, M.WoodPlanks)
			P.blk({ 0.04, 0.32, 0.48 }, { s * 0.32, 0.16, 0 }, wicker, M.WoodPlanks)
		end
		for k = 1, 3 do
			P.egg({ 0.14, 0.1, 0.32 }, { (k - 2) * 0.17, 0.33, K.num(-0.08, 0.08) }, K.pick({ c3(255, 95, 95), c3(95, 170, 255), c3(255, 220, 95), c3(165, 115, 255) }), M.Fabric, CFrame.Angles(K.num(-0.4, 0.4), K.num(-1, 1), 0))
		end
	end
	local function towels(K, P)
		local y = 0
		for _ = 1, 3 do
			P.blk({ 0.5, 0.1, 0.36 }, { K.num(-0.03, 0.03), y + 0.05, 0 }, K.pick({ c3(255, 200, 210), c3(200, 230, 255), c3(255, 245, 200) }), M.Fabric, CFrame.Angles(0, K.num(-0.15, 0.15), 0))
			y = y + 0.1
		end
	end
	LANDS.Robo = {
		border = function(K, x, z0, z1, top, inward)
			-- a basalt curb with lava glowing in its seam
			local P = K.placer(Vector3.new(x, top, (z0 + z1) / 2), 1)
			local len = z1 - z0
			P.blk({ 0.13, 0.08, len }, { 0, 0.04, 0 }, c3(52, 44, 46), M.Basalt)
			K.glow(P.blk({ 0.035, 0.02, len - 0.1 }, { 0, 0.085, 0 }, LAVA, M.Neon), 0, 0.35, 0.8)
		end,
		touch = function(K, P)
			if K.rng:NextNumber() < 0.55 then
				local x, z = -0.27, K.num(-0.08, 0.08)
				for _ = 1, 3 do
					local nx, nz = x + 0.18, z + K.num(-0.13, 0.13)
					local len = math.sqrt((nx - x) ^ 2 + (nz - z) ^ 2)
					K.glow(P.blk({ len + 0.03, 0.02, 0.045 }, { (x + nx) / 2, 0.01, (z + nz) / 2 }, LAVA, M.Neon, CFrame.Angles(0, -math.atan2(nz - z, nx - x), 0)), 0, 0.4, 1.3)
					x, z = nx, nz
				end
			else
				P.blk({ 0.36, 0.02, 0.36 }, { -0.1, 0.01, 0 }, c3(205, 210, 220), M.Marble, CFrame.Angles(0, K.num(-0.2, 0.2), 0))
				P.egg({ 0.14, 0.08, 0.32 }, { 0.18, 0.03, 0.12 }, K.pick({ c3(255, 95, 95), c3(95, 170, 255) }), M.Fabric, CFrame.Angles(0, K.num(-1.2, 1.2), 0))
			end
		end,
		big = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				-- two washers stacked, the top one a little turned
				washer(K, P, 1.0)
				washer(K, K.placer(P.at({ 0, 1.0, 0 }), P.sc, 0.12, true), 0.85)
			else
				vent(K, P, K.num(1.7, 2.0))
			end
		end,
		mid = function(K, P)
			washer(K, P, K.num(0.9, 1.05))
		end,
		small = function(K, P)
			if K.rng:NextNumber() < 0.5 then
				basket(K, P)
			else
				towels(K, P)
			end
		end,
		fx = function(K, pos, sc)
			K.emit(pos + Vector3.new(0, 1.6 * sc, 0), { 0.6 * sc, 0.2, 0.4 * sc }, { tex = "smoke", colors = { c3(240, 240, 240), c3(255, 220, 200) }, size = { 0.3, 0.8 }, life = { 1.6, 2.4 }, speed = { 0.35, 0.6 }, accel = Vector3.new(0, 0.25, 0), rate = 1.5, spread = 20, alpha = 0.55 })
		end,
	}
end

-- How big the set pieces behind the far edge are (they're seen from across the table).
local FAR_SCALE = 1.7
local SIDE_SCALE = 1.3

-- A mound of the land's own ground, its top `h` above the felt; returns where a prop standing
-- `dx`, `dz` from its middle has its feet.
local function mound(K, opts, at, w, d, h)
	local sink = h * 1.3
	K.make({
		Name = "SceneryHill",
		Size = Vector3.new(w, (h + sink) * 2, d),
		CFrame = CFrame.new(at.X, opts.base - sink, at.Z),
		Color = (opts.ground or c3(120, 110, 100)):Lerp(c3(30, 26, 32), 0.12),
		Material = opts.groundMaterial or M.Ground,
		mesh = true,
	}, false)
	return function(dx, dz)
		local u, v = dx / (w / 2), dz / (d / 2)
		local q = math.max(0, 1 - u * u - v * v)
		local y = opts.base - sink + (h + sink) * math.sqrt(q) - 0.04
		return Vector3.new(at.X + dx, math.max(opts.base, y), at.Z + dz)
	end
end

function TableScenery.backdrop(K, land, opts, s, k)
	local pitch = opts.pitch
	local hillD = 2.3
	local hillZ = opts.frameOut + hillD * 0.4 -- (it starts right at the frame)
	local onHill = mound(K, opts, Vector3.new(opts.cx, 0, s * hillZ), pitch * 1.25, hillD, 0.45)
	-- `dz` toward the board
	local function spot(dx, dz)
		return onHill(dx, -s * dz)
	end
	local flip = K.rng:NextNumber() < 0.5 and 1 or -1
	local sc = FAR_SCALE * k
	land.big(K, K.placer(spot(flip * 0.12 * pitch, -0.35), sc, K.num(-0.25, 0.25), true))
	land.mid(K, K.placer(spot(-flip * 0.3 * pitch, -0.1), sc * 0.95, K.num(-0.25, 0.25), true))
	land.small(K, K.placer(spot(-flip * 0.05 * pitch, 0.6), sc * 0.85, K.num(-0.3, 0.3), true))
	land.small(K, K.placer(spot(flip * 0.36 * pitch, 0.55), sc * 0.7, K.num(-0.3, 0.3), true))
	if land.fx then
		land.fx(K, spot(0, 0), sc)
	end
end

-- The felt beside the field, next to an outer lane's half of the table: a big piece, a medium one
-- and small ones on little mounds, kept away from whatever stands there (heroes, the deck, the
-- trash pile and the path the cards fly along: opts.avoid = { { x, z, radius }, ... }).
function TableScenery.sidePieces(K, land, opts, s, k)
	local out = opts.outer -- -1 left, +1 right
	local edge = opts.fieldEdge -- x of the frame's outer side (positive)
	-- dx from the frame, z from the middle line (on this lane's side), what goes there, how wide
	local slots = {
		{ 0.95, 6.6, "big", 0.95 },
		{ 0.95, 1.4, "mid", 0.7 },
		{ 3.7, 5.3, "mid", 0.7 },
		{ 3.9, 1.9, "small", 0.45 },
		{ 2.5, 8.2, "small", 0.45 },
		{ 4.2, 8.0, "small", 0.45 },
	}
	for _, slot in ipairs(slots) do
		local x, z = out * (edge + slot[1]), s * slot[2]
		local ok = math.abs(x) + slot[4] < (opts.feltEdge or 11.4) and math.abs(z) + slot[4] < (opts.feltDepth or 9.9)
		for _, a in ipairs(opts.avoid or {}) do
			local dx, dz = x - a[1], z - a[2]
			if math.sqrt(dx * dx + dz * dz) < a[3] + slot[4] then
				ok = false
			end
		end
		if opts.mine and slot[3] == "big" then
			ok = false -- (on your side the big piece would loom right in front of you)
		end
		if ok then
			local size = slot[4] * 2.4
			local foot = mound(K, opts, Vector3.new(x, 0, z), size, size * 0.85, 0.22)(0, 0)
			local sc = SIDE_SCALE * (slot[3] == "small" and 0.85 or 1) * (opts.mine and 0.85 or 1) -- (yours are closer to you)
			land[slot[3]](K, K.placer(foot, sc, K.num(-0.4, 0.4), true))
		end
	end
end

---------------------------------------------------------------------------
-- Build one lane's scenery.
-- opts: family, cx (lane centre x), pitch (lane width), groundTop (the lane's top), base (the
-- felt's top), half (how deep a side is), frameOut (where the frame ends, from the middle line),
-- dir (+1 your side, -1 the far side), mine, seed, parent, ground (Color3), groundMaterial,
-- keepClear (x positions to keep the set piece away from, e.g. the 2v2 heroes).
-- Returns { parts = { BasePart }, life = { glow entries } }.
---------------------------------------------------------------------------
function TableScenery.build(opts)
	local land = LANDS[opts.family]
	local K = newKit(opts)
	if not land then
		return { parts = K.parts, life = K.life }
	end
	local s = opts.dir
	local k = opts.pitch / 3.075 -- (2v2 lanes are narrower)
	local cx = opts.cx
	local half = opts.half

	-- The borders along both long sides.
	local inset = 0.12 * k
	for _, side in ipairs({ -1, 1 }) do
		local x = cx + side * (opts.pitch / 2 - inset)
		local a, b = s * 0.12, s * (half - 0.12)
		land.border(K, x, math.min(a, b), math.max(a, b), opts.groundTop, -side)
	end

	-- One small flat touch on the ground, in a gap between the two creature spots.
	local side = K.rng:NextNumber() < 0.5 and 1 or -1
	land.touch(K, K.placer(Vector3.new(cx + side * 1.08 * k, opts.groundTop, s * 3.07), k * 0.85, K.num(-0.4, 0.4)))

	-- Behind the far side's back edge: the land carries on as a low hill with a set piece on it.
	if not opts.mine then
		local clear = true
		for _, x in ipairs(opts.keepClear or {}) do
			if math.abs(x - cx) < 1.6 then
				clear = false
			end
		end
		if clear then
			TableScenery.backdrop(K, land, opts, s, k)
		end
	end
	-- Beside the field: the outer lanes also dress the felt next to their half of the table.
	if opts.outer then
		TableScenery.sidePieces(K, land, opts, s, k)
	end
	return { parts = K.parts, life = K.life }
end

-- The breathing glows: call every frame with the glow lists of the lanes and the time.
function TableScenery.animate(lists, t)
	for _, list in ipairs(lists) do
		for _, g in ipairs(list) do
			if g.p.Parent then
				g.p.Transparency = g.lo + (g.hi - g.lo) * (0.5 + 0.5 * math.sin(t * g.speed + g.phase))
			end
		end
	end
end

return TableScenery

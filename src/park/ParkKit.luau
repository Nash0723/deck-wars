-- ParkKit (ModuleScript, ServerScriptService): the park's Blender-made models and its painted ground.
--
-- The models live in ServerStorage.ParkKit, one Model per prop (Oak, Maple, Tree, Sycamore, Willow,
-- StrandA, StrandB, StoneA..C, Bush, Bench, Lamp, Bridge, Gazebo, Duck, Lavender, Marigold,
-- Hydrangea, Jasmine, Reeds, LilyPad, LilyFlower). Each holds MeshParts named for what they are
-- ("Trunk", "Leaves", ...) with the Model's pivot at the prop's foot. ParkBuilder builds every prop
-- out of plain parts first, then calls Kit.dress: the mesh goes on top and the plain parts are
-- hidden (the ones you can bump into stay as invisible colliders, the rest are removed). With no
-- ParkKit in the place (the tests), nothing is dressed and the plain parts are what you see.
--
-- Kit.paintGround paints the terrain: lawns, a carved pond with still water and a pebbly shore, the
-- island, gravel paths, and wooded hills rising all round the glasshouse. The hills keep climbing
-- to the edge of the painted ground and end higher than the camera can go (it stays under the
-- glass roof), so from inside you never see past the edge of the world.

local ServerStorage = game:GetService("ServerStorage")

local Kit = {}
Kit.Origin = Vector3.new(0, 0, 0) -- (ParkBuilder sets this: where the park stands)
Kit.WaterLevel = -0.9
Kit.painted = false -- (true once the ground is terrain: props then stand on Kit.groundY)

local function store()
	return ServerStorage:FindFirstChild("ParkKit")
end

function Kit.has(name)
	local s = store()
	return s ~= nil and s:FindFirstChild(name) ~= nil
end

-- A copy of a prop, standing at `cf` (in the park's own coordinates), scaled and coloured.
function Kit.put(name, parent, cf, scale, colors)
	local s = store()
	local template = s and s:FindFirstChild(name)
	if not template then
		return nil
	end
	local m = template:Clone()
	if scale and math.abs(scale - 1) > 0.001 then
		m:ScaleTo(scale)
	end
	m:PivotTo(CFrame.new(Kit.Origin) * cf)
	for partName, color in pairs(colors or {}) do
		for _, p in ipairs(m:GetChildren()) do
			if p.Name == partName then
				p.Color = color
			end
		end
	end
	m.Parent = parent
	return m
end

-- The plain parts that stay, hidden, as what you bump into. Every other plain part is removed once
-- the mesh is on, and the meshes themselves are never solid (their shapes make clumsy hitboxes).
local KEEP = { Trunk = true, Seat = true, Backrest = true, Deck = true, Plinth = true, Step = true, Post = true, Rail = true, Wall = true, Foot = true }

-- Puts a prop's mesh into `model` (built of plain parts already) and hides those parts. Returns the
-- mesh parts by name, or nil if the kit has no such prop. `replace` removes every plain part.
function Kit.dress(model, name, cf, scale, colors, replace)
	local m = Kit.put(name, nil, cf, scale, colors)
	if not m then
		return nil
	end
	local byName = {}
	for _, p in ipairs(m:GetChildren()) do
		byName[p.Name] = byName[p.Name] or p
	end
	for _, old in ipairs(model:GetChildren()) do
		if old:IsA("BasePart") and not old:IsA("Seat") then
			local twin = byName[old.Name]
			if twin then
				for _, c in ipairs(old:GetChildren()) do
					c.Parent = twin -- (a lantern's light moves into the new glass)
				end
				for k, v in pairs(old:GetAttributes()) do
					twin:SetAttribute(k, v)
				end
			end
			if replace or not (KEEP[old.Name] and old.CanCollide) then
				old:Destroy()
			else
				old.Transparency = 1
				old.CastShadow = false
			end
		end
	end
	for _, p in ipairs(m:GetChildren()) do
		p.Parent = model
	end
	m:Destroy()
	return byName
end

-- The willow's curtain: six hanging sectors round the crown, each one a "Strand" the client sways.
function Kit.willowStrands(model, cf, scale, greens, rng)
	if not Kit.has("StrandA") then
		return
	end
	local crown = cf * CFrame.new(2.5 * scale, 8.7 * scale, 0)
	for k = 0, 5 do
		local m = Kit.put(k % 2 == 0 and "StrandA" or "StrandB", nil, CFrame.new(crown.Position) * CFrame.Angles(0, k * math.pi / 3 + rng:NextNumber(-0.1, 0.1), 0), scale * rng:NextNumber(0.94, 1.08))
		for _, p in ipairs(m:GetChildren()) do
			p.Name = "Strand"
			p.Color = greens[k % #greens + 1]:Lerp(Color3.fromRGB(78, 116, 56), 0.4) -- (a shade deeper than the crown)
			p:SetAttribute("Phase", rng:NextNumber(0, math.pi * 2))
			p.Parent = model
		end
		m:Destroy()
	end
end

---------------------------------------------------------------------------
-- The ground
---------------------------------------------------------------------------

local function smooth(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local shape = nil -- { pondR = function(angle), island = radius } once the ground is painted
Kit.HillTop = 84 -- the highest the hills go (the painted ground reaches this at its corners)
Kit.GroundHalf = 244 -- the painted ground runs this far from the middle (a square)

-- How high the ground is at (x, z), in the park's own coordinates.
local function height(x, z)
	local r = math.sqrt(x * x + z * z)
	local pr = shape.pondR(math.atan2(x, z))
	if r < pr then
		local bed = -1.3 - 4.7 * smooth((pr - r) / 3.5)
		local isl = shape.island
		if r < isl + 3.5 then
			return math.max(bed, 0.5 - 6.5 * smooth((r - (isl - 1.5)) / 5))
		end
		return bed
	end
	local h = -1.3 * (1 - smooth((r - pr) / 1.4)) -- (a short, steep shore: the water stops near the edge)
	if r > 129 then
		local s = smooth((r - 129) / 105)
		h += s * (70 + 7 * math.noise(x / 37, z / 37, 3.3) + 3 * math.noise(x / 13, z / 13, 9.1)) + math.max(0, r - 234) * 0.1
	end
	return math.min(h, Kit.HillTop)
end

function Kit.groundY(x, z)
	if not (Kit.painted and shape) then
		return 0
	end
	return height(x, z)
end

-- Paints the park into `terrain`. opts: pondR (function of the angle), island (radius), loop and
-- paths (lists of points along the gravel paths; the loop closes on itself).
function Kit.paintGround(terrain, origin, opts)
	shape = { pondR = opts.pondR, island = opts.island }
	local M = Enum.Material
	local CELL, HALF, Y0 = 4, Kit.GroundHalf, -12
	local NY = math.ceil((Kit.HillTop + 4 - Y0) / CELL)
	local N = HALF * 2 / CELL
	-- the gravel paths as segments { ax, az, bx, bz, half width }
	local segs = {}
	local function add(points, half, closed)
		for i = 1, #points - (closed and 0 or 1) do
			local a, b = points[i], points[i % #points + 1]
			table.insert(segs, { a.X, a.Z, b.X, b.Z, half })
		end
	end
	add(opts.loop or {}, 2.9, true)
	for _, pts in ipairs(opts.paths or {}) do
		add(pts, 4, false)
	end
	local function onPath(x, z, margin)
		for _, s in ipairs(segs) do
			local dx, dz = s[3] - s[1], s[4] - s[2]
			local len2 = dx * dx + dz * dz
			local t = len2 > 0 and math.clamp(((x - s[1]) * dx + (z - s[2]) * dz) / len2, 0, 1) or 0
			local px, pz = s[1] + dx * t - x, s[2] + dz * t - z
			if px * px + pz * pz < (s[5] + margin) * (s[5] + margin) then
				return true
			end
		end
		return false
	end
	local WL = Kit.WaterLevel
	local mats, occ = table.create(N), table.create(N)
	for i = 1, N do
		local x = -HALF + (i - 0.5) * CELL
		local mi, oi = table.create(NY), table.create(NY)
		for j = 1, NY do
			mi[j], oi[j] = table.create(N), table.create(N)
		end
		for k = 1, N do
			local z = -HALF + (k - 0.5) * CELL
			local h = (height(x - 1, z - 1) + height(x + 1, z - 1) + height(x - 1, z + 1) + height(x + 1, z + 1)) / 4
			local r = math.sqrt(x * x + z * z)
			local pr = shape.pondR(math.atan2(x, z))
			-- mown lawn through the park; long grass on the slopes and in a few wild patches
			local solid = M.LeafyGrass
			if r > 134 or (r > pr + 10 and r < 116 and math.noise(x / 26, z / 26, 7.7) > 0.22 and not onPath(x, z, 9)) then -- (mown along the glass wall)
				solid = M.Grass
			end
			if r < pr - 1 and r > shape.island + 2 then
				solid = M.Mud
			elseif math.abs(r - pr) < 2.6 or math.abs(r - shape.island - 1) < 1.6 then
				solid = M.Ground -- (the pebbly shore)
			elseif r < 126 and r > pr and onPath(x, z, 0) then
				solid = M.Sand -- (gravel)
			end
			-- the strip along the shore is always solid ground at lawn level, never water: terrain
			-- comes in 4-stud blocks, and a low shore block would fill with water and spread it over
			-- the shore (where the stones and the path are)
			local shore = r >= pr - 0.5 and r < pr + 3
			for j = 1, NY do
				local y0 = Y0 + (j - 1) * CELL
				local o = math.clamp((h - 2 - y0) / CELL, 0, 1) -- (smooth terrain stands half a cell proud)
				if shore and y0 < 0 and y0 >= -CELL then
					o = math.max(o, 0.55)
				end
				if o < 0.5 and y0 < WL and r < pr + 3 then
					mi[j][k], oi[j][k] = M.Water, math.clamp((WL - y0) / CELL, 0, 1)
				elseif o > 0 then
					mi[j][k], oi[j][k] = solid, o
				else
					mi[j][k], oi[j][k] = M.Air, 0
				end
			end
		end
		mats[i], occ[i] = mi, oi
		if i % 20 == 0 then
			task.wait()
		end
	end
	local lo = origin + Vector3.new(-HALF, Y0, -HALF)
	terrain:WriteVoxels(Region3.new(lo, lo + Vector3.new(HALF * 2, NY * CELL, HALF * 2)), CELL, mats, occ)
	pcall(function()
		terrain:SetMaterialColor(M.Grass, Color3.fromRGB(90, 142, 62))
		terrain:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(104, 154, 70))
		terrain:SetMaterialColor(M.Sand, Color3.fromRGB(166, 152, 128))
		terrain:SetMaterialColor(M.Ground, Color3.fromRGB(150, 138, 114))
		terrain:SetMaterialColor(M.Mud, Color3.fromRGB(70, 62, 50))
	end)
	-- a calm, clear, mirror-like pond
	for k, v in pairs({ WaterColor = Color3.fromRGB(36, 72, 64), WaterReflectance = 1, WaterTransparency = 0.25, WaterWaveSize = 0.03, WaterWaveSpeed = 5, Decoration = true }) do
		pcall(function()
			terrain[k] = v
		end)
	end
	Kit.painted = true
	return true
end

return Kit

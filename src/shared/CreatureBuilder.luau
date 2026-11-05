-- Builds creature, gadget and hero models for the duel table from CreatureModelData.
-- Every model stands on y = 0 and faces -Z. Use Model:PivotTo to place it.
--
-- To use your own model for a card, put a Model named after the card id
-- (for example "toaster_knight") in ReplicatedStorage.CreatureModels. The client uses it instead.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local Data = req("CreatureModelData")

local CreatureBuilder = {}

local SHAPES = {
	S = Enum.PartType.Ball,
	C = Enum.PartType.Cylinder,
}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local CONFETTI = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 60)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 220, 120)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(230, 90, 255)),
})

local function addEffect(part, e)
	local kind = e[1]
	if kind == "Fire" then
		local fire = Instance.new("Fire")
		fire.Size = e[3]
		fire.Heat = e[4]
		fire.Color = rgb(e[5], e[6], e[7])
		fire.SecondaryColor = rgb(e[8], e[9], e[10])
		fire.Parent = part
	elseif kind == "Sparkles" then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = rgb(e[3], e[4], e[5])
		sparkles.Parent = part
	elseif kind == "Smoke" then
		local smoke = Instance.new("Smoke")
		smoke.Color = rgb(e[3], e[4], e[5])
		smoke.Opacity = e[6]
		smoke.RiseVelocity = e[7]
		smoke.Size = e[8]
		smoke.Parent = part
	elseif kind == "PointLight" then
		local light = Instance.new("PointLight")
		light.Color = rgb(e[3], e[4], e[5])
		light.Brightness = e[6]
		light.Range = e[7]
		light.Parent = part
	elseif kind == "Confetti" then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Rate = 8
		emitter.Lifetime = NumberRange.new(1.2, 2.2)
		emitter.Speed = NumberRange.new(1.5, 3)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.Acceleration = Vector3.new(0, -3, 0)
		emitter.Size = NumberSequence.new(0.18)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-200, 200)
		emitter.Color = CONFETTI
		emitter.LightEmission = 0.3
		emitter.Parent = part
	end
end

-- Is there built-in model data for this id?
function CreatureBuilder.has(id)
	return Data[id] ~= nil
end

-- Size information: { height = ..., width = ..., depth = ... } or nil.
function CreatureBuilder.info(id)
	local d = Data[id]
	if not d then
		return nil
	end
	return { height = d.height, width = d.width, depth = d.depth }
end

-- Returns a new Model (not parented) or nil if there is no data for the id.
-- The model's PrimaryPart is an invisible "Root" part at its feet.
function CreatureBuilder.build(id)
	local spec = Data[id]
	if not spec then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = id
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 0.1, 1)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local parts = {}
	for i, p in ipairs(spec.parts) do
		local shape = p[1]
		local part
		if shape == "W" then
			part = Instance.new("WedgePart")
		else
			part = Instance.new("Part")
			local partType = SHAPES[shape]
			if partType then
				part.Shape = partType
			end
		end
		part.Name = p[2]
		part.Size = Vector3.new(p[3], p[4], p[5])
		part.CFrame = CFrame.new(p[6], p[7], p[8]) * CFrame.Angles(math.rad(p[9]), math.rad(p[10]), math.rad(p[11]))
		part.Color = rgb(p[12], p[13], p[14])
		part.Material = Enum.Material[p[15]]
		part.Transparency = p[16]
		part.Reflectance = p[17]
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if shape == "E" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		part.Parent = model
		parts[i] = part
	end
	for _, e in ipairs(spec.effects or {}) do
		local part = parts[e[2]]
		if part then
			addEffect(part, e)
		end
	end
	return model
end

return CreatureBuilder

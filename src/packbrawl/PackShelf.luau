-- The 3D Pack Shelf in the Pack Party corner (client only; nothing here replicates).
--
-- The room has Stations.PackParty.PackShelf with one Model per pack (ShelfPack_<pack id>) on a
-- glass riser, and MascotSpot_<pack id> markers. This module:
--   * puts a small figurine of each family's mascot next to its pack (built once, here),
--   * lifts the pack under the mouse, and brings the chosen pack forward off the shelf,
--     standing it upright and turning it gently, with its riser light turned up,
--   * runs the marquee bulbs,
--   * sends the chosen pack flying at the camera when it is opened, and puts it back after.
-- Packs are moved part by part (CFrame), never with physics.
--
--   PackShelf.attach()           -> true if the room has a shelf
--   PackShelf.setActive(on)      -- the Pack Party station is open (hover and selection show)
--   PackShelf.select(packId)
--   PackShelf.packAt(pos, isScreen) -> packId or nil (what is under a mouse/touch point)
--   PackShelf.hover(packId or nil)
--   PackShelf.launch(packId)     -- the pack leaps at the camera and hides
--   PackShelf.restore()          -- every pack back on the shelf

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local Packs = require(here:WaitForChild("Packs"))
local CreatureBuilder = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("CreatureBuilder"))

local PackShelf = {}

PackShelf.MascotHeight = 2.2 -- studs (the figurines are scaled down to this)

local state = {
	attached = false,
	active = false,
	shelf = nil,
	packs = {}, -- [packId] = { parts = { {part, rel, tr} }, home = CFrame, lift, fwd, upright, spin, glow, light, backlight, mascot }
	selected = nil,
	hovered = nil,
	launched = nil,
	bulbs = {},
	t = 0,
	conn = nil,
}
PackShelf.state = state -- (for tests)

local function shelfModel()
	local room = workspace:FindFirstChild("MenuRoom")
	local stations = room and room:FindFirstChild("Stations")
	local pp = stations and stations:FindFirstChild("PackParty")
	return pp and pp:FindFirstChild("PackShelf")
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- The riser part named `name` closest to the pack (each pack has its own riser).
local function nearest(shelf, name, pos)
	local best, bestD = nil, math.huge
	for _, d in ipairs(shelf:GetChildren()) do
		if d.Name == name and d:IsA("BasePart") then
			local dist = (flat(d.Position) - flat(pos)).Magnitude + math.abs(d.Position.Y - pos.Y) * 0.25
			if dist < bestD then
				best, bestD = d, dist
			end
		end
	end
	return best
end

local function buildMascot(spot, cardId)
	if not CreatureBuilder.has(cardId) then
		return nil
	end
	local model = CreatureBuilder.build(cardId)
	if not model then
		return nil
	end
	model.Name = "Mascot_" .. cardId
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Light") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("ParticleEmitter") or d:IsA("Sparkles") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	local info = CreatureBuilder.info(cardId)
	local h = info and info.height or 4
	pcall(function()
		model:ScaleTo(PackShelf.MascotHeight / math.max(h, 0.5))
	end)
	model:PivotTo(spot.CFrame)
	model.Parent = spot.Parent
	return { model = model, home = spot.CFrame, hop = 0 }
end

local function place(p, cf)
	for _, e in ipairs(p.parts) do
		e.part.CFrame = cf * e.rel
	end
end

local function setHidden(p, hidden)
	for _, e in ipairs(p.parts) do
		e.part.Transparency = hidden and 1 or e.tr
		for _, g in ipairs(e.part:GetChildren()) do
			if g:IsA("SurfaceGui") then
				g.Enabled = not hidden
			end
		end
	end
end

local function approach(cur, target, dt, speed)
	return cur + (target - cur) * (1 - math.exp(-dt * speed))
end

local function update(dt)
	state.t += dt
	local t = state.t
	for id, p in pairs(state.packs) do
		local sel = state.active and state.selected == id
		local hov = state.active and state.hovered == id and not sel
		local tLift = sel and 0.45 or (hov and 0.18 or 0)
		local tFwd = sel and 1.0 or (hov and 0.25 or 0)
		local tUp = sel and 1 or 0
		if state.launched == id then
			tLift, tFwd, tUp = 1.2, 9, 1
		end
		local speed = state.launched == id and 9 or 7
		p.lift = approach(p.lift, tLift, dt, speed)
		p.fwd = approach(p.fwd, tFwd, dt, speed)
		p.upright = approach(p.upright, tUp, dt, speed)
		p.spin = sel and (math.sin(t * 1.3) * 0.22) or approach(p.spin, 0, dt, 6)
		local bob = sel and math.sin(t * 2.2) * 0.06 or 0
		local moving = p.lift > 0.002 or p.fwd > 0.002 or math.abs(p.spin) > 0.002 or sel
		if moving or p.wasMoving then
			-- forward = toward the room (the pack's own +Z, flattened), lift = straight up
			local fwdDir = flat(p.home.LookVector * -1)
			fwdDir = fwdDir.Magnitude > 0 and fwdDir.Unit or Vector3.new(0, 0, 1)
			local pos = p.home.Position + Vector3.new(0, p.lift + bob, 0) + fwdDir * p.fwd
			local cf = CFrame.new(pos) * (p.home - p.home.Position) * CFrame.Angles(math.rad(8) * p.upright, 0, 0) * CFrame.Angles(0, p.spin, 0)
			place(p, cf)
		end
		p.wasMoving = moving
		-- lights: the chosen pack's niche glows brighter
		local glowK = sel and 1 or (hov and 0.5 or 0)
		p.glowK = approach(p.glowK or 0, glowK, dt, 6)
		if p.light then
			p.light.Brightness = 1.6 + p.glowK * 2.4 + (sel and math.sin(t * 4) * 0.3 or 0)
		end
		if p.backlight then
			p.backlight.Transparency = 0.72 - p.glowK * 0.3
		end
		-- the mascot of the chosen pack bounces happily; the others stand still
		local m = p.mascot
		if m and m.model.Parent then
			if sel or m.hop > 0.001 then
				m.hop = sel and 1 or approach(m.hop, 0, dt, 6)
				local jump = math.abs(math.sin(t * 3.2)) * 0.22 * m.hop
				local turn = math.sin(t * 1.6) * 0.3 * m.hop
				m.model:PivotTo(m.home * CFrame.new(0, jump, 0) * CFrame.Angles(0, turn, 0))
			end
		end
	end
	-- marquee: a slow chase of brighter bulbs
	local n = #state.bulbs
	if n > 0 then
		local head = math.floor(t * 6) % 6
		for i, b in ipairs(state.bulbs) do
			local on = (i % 6) == head
			b.Color = on and Color3.fromRGB(255, 250, 225) or Color3.fromRGB(235, 196, 120)
		end
	end
end

function PackShelf.attach()
	if state.attached then
		return state.shelf ~= nil
	end
	state.attached = true
	local shelf = shelfModel()
	state.shelf = shelf
	if not shelf then
		return false
	end
	for _, def in ipairs(Packs.List) do
		local m = shelf:FindFirstChild("ShelfPack_" .. def.id)
		local body = m and m:FindFirstChild("PackBody")
		if body then
			local p = { parts = {}, home = body.CFrame, lift = 0, fwd = 0, upright = 0, spin = 0 }
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(p.parts, { part = d, rel = body.CFrame:ToObjectSpace(d.CFrame), tr = d.Transparency })
				end
			end
			local glow = nearest(shelf, "RiserGlow", body.Position)
			p.glow = glow
			p.light = glow and glow:FindFirstChildOfClass("PointLight")
			p.backlight = nearest(shelf, "PackBacklight", body.Position)
			local spot = shelf:FindFirstChild("MascotSpot_" .. def.id)
			if spot and def.mascot then
				p.mascot = buildMascot(spot, def.mascot)
			end
			state.packs[def.id] = p
		end
	end
	for _, d in ipairs(shelf:GetChildren()) do
		if d.Name == "MarqueeBulb" and d:IsA("BasePart") then
			table.insert(state.bulbs, d)
		end
	end
	state.conn = RunService.RenderStepped:Connect(update)
	return true
end

function PackShelf.has()
	return state.shelf ~= nil
end

function PackShelf.setActive(on)
	state.active = on and true or false
	if not on then
		state.hovered = nil
	end
end

function PackShelf.select(id)
	if state.packs[id] then
		state.selected = id
	end
end

function PackShelf.hover(id)
	state.hovered = id
end

-- Which pack is under a point on the screen (or nil).
function PackShelf.packAt(pos, isScreen)
	local shelf = state.shelf
	local camera = workspace.CurrentCamera
	if not (shelf and camera) then
		return nil
	end
	local ray = isScreen and camera:ScreenPointToRay(pos.X, pos.Y) or camera:ViewportPointToRay(pos.X, pos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { shelf }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 200, params)
	local inst = hit and hit.Instance
	while inst and inst ~= shelf do
		local id = string.match(inst.Name, "^ShelfPack_(%w+)$") or string.match(inst.Name, "^Mascot_(.+)$")
		if id then
			if state.packs[id] then
				return id
			end
			for pid, p in pairs(state.packs) do
				if p.mascot and p.mascot.model == inst then
					return pid
				end
			end
		end
		inst = inst.Parent
	end
	-- a hit on a riser picks the pack standing on it
	if hit and (hit.Instance.Name == "PackRiser" or hit.Instance.Name == "PackPlate") then
		local best, bestD = nil, 1.6
		for pid, p in pairs(state.packs) do
			local dist = (flat(p.home.Position) - flat(hit.Instance.Position)).Magnitude
			if dist < bestD and math.abs(p.home.Position.Y - hit.Instance.Position.Y) < 2.5 then
				best, bestD = pid, dist
			end
		end
		return best
	end
	return nil
end

function PackShelf.launch(id)
	local p = state.packs[id]
	if not p then
		return
	end
	state.launched = id
	task.delay(0.3, function()
		if state.launched == id then
			setHidden(p, true)
		end
	end)
end

function PackShelf.restore()
	local id = state.launched
	state.launched = nil
	local p = id and state.packs[id]
	if p then
		-- it pops back in at its spot and settles
		p.lift, p.fwd = 0.6, 0
		setHidden(p, false)
	end
end

return PackShelf

-- Rig: splits a creature model (from CreatureModelData) into moving parts, so Pack Brawl
-- fighters can punch, kick, block and fall instead of moving as one solid block.
--
-- Pure Lua (no Roblox instances), so the tests can rig every creature headlessly.
--
-- Bones (roles):
--   body            the torso. Turns about the hips (or the base, for creatures without legs).
--   head            any head with its face, hat, ears... Child of body. Some creatures have several.
--   armL / armR     arm, hand, and whatever the hand holds (spear, wand, shield...). Child of body.
--   legL / legR     legs and feet. Quadrupeds get legFL, legFR, legBL, legBR. Child of the root.
--   tail, wingL, wingR   children of body.
-- Every part that is none of these rides on the body.
--
-- Pivots (shoulder, hip, neck...) are worked out from where the parts sit, so new creatures
-- rig themselves. RIG_OVERRIDES fixes the few odd shapes by hand.

local function req(name)
	if script then
		local rs = game:GetService("ReplicatedStorage")
		local own = script.Parent:FindFirstChild(name)
		if own then
			return require(own)
		end
		return require(rs:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end

local Data = req("CreatureModelData")

local Rig = {}

local function set(list)
	local s = {}
	for _, n in ipairs(list) do
		s[n] = true
	end
	return s
end

local ARM = set({
	"Arm", "Hand", "Fist", "Claw", "Glove", "Forearm", "Elbow", "UpperArm", "Sleeve", "TinyArm",
	"ArmPipe", "ArmCrane", "ArmOut", "ArmUp", "Joint", "Peg", "Paw", "Shoulder", "Epaulette", "Fringe",
	-- details added by the model overhaul
	"Thumb", "Finger", "Knuckle", "Cuff", "Bracer", "Gauntlet", "Wristband", "Pauldron", "Bicep", "ArmBand",
	"ArmPlate", "Piston", "Pincer", "Mitt", "Bone", "Talon",
})
-- things a creature holds: they move with the hand on their side
local HELD = set({
	"Shield", "ShieldGrid", "Spear", "SpearTip", "ForkHandle", "ForkNeck", "ForkTine", "Wafer", "WaferTop",
	"KnifeHandle", "KnifeBlade", "ShieldCrust", "ToastShield", "Jam", "Glue", "GlueCap", "Wrench", "WrenchJaw",
	"PlungerStick", "PlungerCup", "Scepter", "Cheese", "FishBone", "FishRib", "Banana", "BroomStick", "Bristles",
	"Flashlight", "FlashLens", "Cane", "CaneTop", "Wand", "WandStar", "Cannon", "IceCube", "Staff", "Orb",
	"Spyglass", "SpyglassLens", "Butter",
	-- details added by the model overhaul
	"SpearFlag", "SpearBand", "SpearSeed", "ShieldRim", "ShieldBoss", "ShieldSalt", "ForkGrip", "ForkPommel",
	"KnifeEdge", "KnifeGuard", "WandBand", "WandGlow", "StaffGem", "StaffBand", "ScepterBand", "ScepterTop",
	"PlungerBand", "WrenchBolt", "CaneBand", "FlashBand", "CannonRing", "CannonMouth", "FishTail", "FishEye",
	"BananaTip", "BroomBand", "SpyglassBand", "GlueLabel", "WaferStripe", "Lollipop", "LollipopSwirl",
})
-- held things that are swung like weapons
local WEAPON = set({
	"Spear", "ForkHandle", "Wafer", "KnifeBlade", "Wrench", "PlungerStick", "Scepter", "BroomStick",
	"Flashlight", "Cane", "Wand", "Cannon", "Staff", "Spyglass", "FishBone", "Banana", "Glue",
})
local LEG = set({
	"Leg", "Foot", "Shoe", "Boot", "Thigh", "Shin", "Knee", "Hoof", "FrontLeg", "FrontFoot", "BackFoot",
	"LegCan", "Hip", "Tread",
	-- details added by the model overhaul
	"Sole", "Toe", "Laces", "Ankle", "Kneepad", "Sock", "Heel", "Greave", "ShinPlate", "Claws", "Spat",
})
local TAIL = set({ "Tail", "TailTip", "Tail2" })
local WING = set({ "Wing", "WingLow", "WingSpot", "WingTip" })
local WHEEL = set({ "Wheel", "Tire", "Hubcap", "WheelHub" })
local HEAD_ANCHOR = set({ "Head", "DinoHead", "Skull", "TV", "Hood", "BunnyHead" })
local BODY_ANCHOR = set({
	"Body", "DinoBody", "Torso", "Fridge", "Barrel", "Can", "Cabinet", "Robe", "Coat", "Motor", "Bin",
	"Cactus", "Stem", "Pocket", "Shell", "Pancake", "Base", "Box",
})
-- face and head things: they follow the nearest head (if the creature has one)
local FACE = set({
	"Eye", "Pupil", "Lid", "Glint", "Brow", "Mouth", "Tongue", "Tooth", "Ear", "EarInner", "EarInside",
	"Cheek", "Nose", "Nostril", "Snout", "Muzzle", "Beak", "BeakTip", "Whisker", "Antenna", "AntennaTip",
	"AntlerPalm", "AntlerBase", "AntlerTine", "Horn", "HatBrim", "HatCrown", "HatBand", "HatDent", "HatCone",
	"HatTip", "HatCorner", "HatTrim", "HatStar", "Hat", "Helmet", "HelmetRim", "HelmetStrap", "Cap", "CapBill",
	"CapBadge", "Plume", "PlumeTop", "Crown", "CrownPoint", "CrownBand", "Hair", "Mask", "MaskFrame", "Bandit",
	"Snorkel", "SnorkelMouth", "Glasses", "Monocle", "MonocleChain", "Mustache", "Jaw", "Socket", "SocketGlow",
	"NoseHole", "Screen", "ScreenEye", "ScreenMouth", "Lash", "FacePatch", "EyePatch", "EyePatchStrap",
	"Feather", "Bun", "Headband", "Face", "Lidhalf", "EyeGlow", "EyeLED", "EyeBump", "Eyeball", "Stalk",
	"Earpiece", "EarWire", "HoodDark", "Spark", "Spike", "Knob", "HeadSauce", "Tuft", "Flower",
	-- details added by the model overhaul
	"Iris", "EyeRim", "Lash", "Teeth", "Lip", "Freckle", "Blush", "Dimple", "Fang", "Tusk", "Bump", "Basil",
	"HatFeather", "HatPin", "HatGem", "CrownGem", "CrownGemShine", "HelmetRidge", "HelmetRivet", "NoseGuard",
	"CheekGuard", "Goggle", "GoggleLens", "Forelock", "Mane", "Whiskers", "Snoot", "Chin", "Beard", "Brim",
	"Visor", "VisorGlow", "Halo",
})

-- Per-creature fixes: { noHead = true } keeps the face on the body, { body = "PartName" } picks
-- the torso, { blob = true } turns all limbs off, { noLegs = true } keeps legs still,
-- { keepOnBody = { PartName = true } } keeps those parts off the head.
local RIG_OVERRIDES = {
	-- the bin rim belongs to the bin, not the raccoon's head
	dumpster_diver = { keepOnBody = { BinRim = true } },
	-- wheel-and-stand creatures: the stand and wheel are props, not legs
	hamster_wheel_hero = { body = "Body" },
	-- three pigeons in one card: the wings flap, the legs patter
	pigeon_squad = {},
	-- tornado funnels are the body
	tornado_twins = { noLegs = true },
	-- the snail's "Foot" is its whole slimy base
	sergeant_snail = { noLegs = true },
	-- couch legs are stubby furniture legs
	couch_golem = {},
	-- buildings
	spiked_fence = { blob = true },
	bouncy_castle = { blob = true },
	lemonade_stand = { blob = true },
	snack_bar = { blob = true },
	wind_turbine = { blob = true },
	spooky_crypt = { blob = true },
	charging_station = { blob = true },
	scrap_catapult = { blob = true },
	haunted_arcade = { blob = true },
	rocket_lunchbox = { blob = true },
	disco_cactus = {},
	bunny_burrow = {},
}
Rig.Overrides = RIG_OVERRIDES

---------------------------------------------------------------------------
-- Small vector / matrix helpers (row-major 3x3, CFrame.Angles order: R = Rx * Ry * Rz)
---------------------------------------------------------------------------
local rad = math.rad
local function mmul(a, b)
	return {
		a[1] * b[1] + a[2] * b[4] + a[3] * b[7], a[1] * b[2] + a[2] * b[5] + a[3] * b[8], a[1] * b[3] + a[2] * b[6] + a[3] * b[9],
		a[4] * b[1] + a[5] * b[4] + a[6] * b[7], a[4] * b[2] + a[5] * b[5] + a[6] * b[8], a[4] * b[3] + a[5] * b[6] + a[6] * b[9],
		a[7] * b[1] + a[8] * b[4] + a[9] * b[7], a[7] * b[2] + a[8] * b[5] + a[9] * b[8], a[7] * b[3] + a[8] * b[6] + a[9] * b[9],
	}
end
local function mvec(m, x, y, z)
	return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end
local function euler(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return mmul(mmul(X, Y), Z)
end
Rig.euler = euler
Rig.mmul = mmul
Rig.mvec = mvec

-- Both ends of a part's long axis (cylinders run along X, like in Roblox).
local function ends(p)
	local sx, sy, sz = p.size[1], p.size[2], p.size[3]
	local ax, len
	if p.shape == "C" then
		ax, len = { 1, 0, 0 }, sx
	elseif sx >= sy and sx >= sz then
		ax, len = { 1, 0, 0 }, sx
	elseif sy >= sz then
		ax, len = { 0, 1, 0 }, sy
	else
		ax, len = { 0, 0, 1 }, sz
	end
	local dx, dy, dz = mvec(p.rot, ax[1] * len / 2, ax[2] * len / 2, ax[3] * len / 2)
	local c = p.pos
	return { c[1] + dx, c[2] + dy, c[3] + dz }, { c[1] - dx, c[2] - dy, c[3] - dz }
end

-- Lowest and highest y a part reaches (rough, from its rotated box).
local function yRange(p)
	local lo, hi = math.huge, -math.huge
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local _, y = mvec(p.rot, sx * p.size[1] / 2, sy * p.size[2] / 2, sz * p.size[3] / 2)
				lo = math.min(lo, p.pos[2] + y)
				hi = math.max(hi, p.pos[2] + y)
			end
		end
	end
	return lo, hi
end

local function dist2(a, b)
	return (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2
end

---------------------------------------------------------------------------
-- Rigging
---------------------------------------------------------------------------
local cache = {}

-- Returns the rig for a model id, or nil when there is no model data.
-- rig = {
--   id, height, kind ("biped" | "arms" | "legs" | "quad" | "blob"),
--   has = { arms, legs, quad, head, tail, wings, wheels, weapon, shield },
--   bones = { [boneName] = { role, pivot = {x,y,z}, parent = "body" | "root", side = -1 | 1 | 0, n } },
--   partBone = { [part index] = boneName or "body" },
--   weaponSide = -1 | 1 | nil,
-- }
function Rig.get(id)
	if cache[id] ~= nil then
		return cache[id] or nil
	end
	local spec = Data[id]
	if not spec then
		cache[id] = false
		return nil
	end
	local rig = Rig.build(id, spec)
	cache[id] = rig
	return rig
end

function Rig.build(id, spec)
	local ov = RIG_OVERRIDES[id] or {}
	local h = spec.height or 3
	local parts = {}
	for i, p in ipairs(spec.parts) do
		parts[i] = {
			i = i,
			shape = p[1],
			name = p[2],
			size = { p[3], p[4], p[5] },
			pos = { p[6], p[7], p[8] },
			rot = euler(rad(p[9]), rad(p[10]), rad(p[11])),
		}
	end

	-- torso anchors (several for multi-creature cards like the pigeon squad)
	local anchors = {}
	for _, p in ipairs(parts) do
		if (ov.body and p.name == ov.body) or (not ov.body and BODY_ANCHOR[p.name]) then
			table.insert(anchors, p)
		end
	end
	if #anchors > 1 and not (#anchors == 3 and id == "pigeon_squad") then
		-- keep only the biggest of the same name (layers, pancakes...)
		table.sort(anchors, function(a, b)
			return a.size[1] * a.size[2] * a.size[3] > b.size[1] * b.size[2] * b.size[3]
		end)
		anchors = { anchors[1] }
	end
	local function nearestAnchor(p)
		local best, bd = nil, math.huge
		for k, a in ipairs(anchors) do
			local d = (p.pos[1] - a.pos[1]) ^ 2 + (p.pos[3] - a.pos[3]) ^ 2
			if d < bd then
				best, bd = k, d
			end
		end
		return best or 1, anchors[best or 1]
	end
	local function sideOf(p)
		local _, a = nearestAnchor(p)
		local cx = a and a.pos[1] or 0
		local dx = p.pos[1] - cx
		if math.abs(dx) < 0.12 then
			return 0
		end
		return dx < 0 and -1 or 1
	end

	local role = {} -- part index -> "arm" | "held" | "leg" | "tail" | "wing" | "head" | nil
	local hasArm = { [-1] = false, [1] = false }
	local hasWing = { [-1] = false, [1] = false }
	local blob = ov.blob
	for _, p in ipairs(parts) do
		local n = p.name
		local side = sideOf(p)
		if blob then
			-- buildings and props keep everything on the body
		elseif ARM[n] and side ~= 0 then
			if n == "Paw" and p.pos[2] < 0.3 * h then
				-- low paws are feet
				role[p.i] = not ov.noLegs and "leg" or nil
			elseif n ~= "Shoulder" or math.abs(p.pos[1]) > 0.35 then
				role[p.i] = "arm"
				hasArm[side] = true
			end
		elseif LEG[n] and side ~= 0 and not ov.noLegs then
			role[p.i] = "leg"
		elseif TAIL[n] then
			role[p.i] = "tail"
		elseif WING[n] and side ~= 0 then
			role[p.i] = "wing"
			hasWing[side] = true
		end
	end
	if not blob then
		for _, p in ipairs(parts) do
			local side = sideOf(p)
			if HELD[p.name] and side ~= 0 and hasArm[side] and not role[p.i] then
				if p.name ~= "Butter" or math.abs(p.pos[1]) > 0.8 then
					role[p.i] = "held"
				end
			elseif HELD[p.name] and side ~= 0 and hasWing[side] and not role[p.i] then
				role[p.i] = "wingheld"
			end
		end
	end

	-- heads
	local heads = {}
	if not blob and not ov.noHead then
		for _, p in ipairs(parts) do
			if HEAD_ANCHOR[p.name] and not role[p.i] then
				table.insert(heads, p)
			end
		end
	end
	-- a "Head" that is really the whole body (bolt bug, hamster...) is not a separate head
	if #heads == 1 then
		local hd = heads[1]
		local _, a = nearestAnchor(hd)
		if a and a ~= hd then
			local hv = hd.size[1] * hd.size[2] * hd.size[3]
			local av = a.size[1] * a.size[2] * a.size[3]
			local lo = yRange(hd)
			local alo, ahi = yRange(a)
			-- the head must sit mostly above the torso's middle
			if lo < (alo + ahi) / 2 - 0.05 * h and hv > av * 0.6 then
				heads = {}
			end
		end
	end
	local headOf = {}
	if #heads > 0 then
		for _, p in ipairs(parts) do
			if not role[p.i] and not (ov.keepOnBody and ov.keepOnBody[p.name]) then
				local best, bd = nil, math.huge
				for k, hd in ipairs(heads) do
					local d = dist2(p.pos, hd.pos)
					if d < bd then
						best, bd = k, d
					end
				end
				local hd = heads[best]
				local r = math.max(hd.size[1], hd.size[2], hd.size[3]) * 0.5
				local lo = yRange(hd)
				local close = math.sqrt(bd) <= r + 0.75
				local smaller = p.size[1] * p.size[2] * p.size[3] < hd.size[1] * hd.size[2] * hd.size[3] * 0.7
				if p == hd or (FACE[p.name] and close and p.pos[2] >= lo - 0.15) or (smaller and math.sqrt(bd) <= r * 0.95 and p.pos[2] >= lo) then
					role[p.i] = "head"
					headOf[p.i] = best
				end
			end
		end
	end

	-- legs: two sides, or four (front/back) for quadrupeds
	local legParts = {}
	for _, p in ipairs(parts) do
		if role[p.i] == "leg" then
			table.insert(legParts, p)
		end
	end
	local quad = false
	local grounded = {}
	for _, p in ipairs(legParts) do
		local lo = yRange(p)
		if lo < 0.12 * h then
			table.insert(grounded, p)
		end
	end
	if #grounded >= 4 then
		local zs = {}
		for _, p in ipairs(grounded) do
			table.insert(zs, p.pos[3])
		end
		table.sort(zs)
		quad = (zs[#zs] - zs[1]) > 0.5 and #anchors == 1
	end
	local zMid = 0
	if quad then
		local s = 0
		for _, p in ipairs(legParts) do
			s += p.pos[3]
		end
		zMid = s / #legParts
	end

	local bones = {}
	local partBone = {}
	local function addTo(name, p, info)
		local b = bones[name]
		if not b then
			b = { name = name, parts = {}, role = info.role, parent = info.parent, side = info.side or 0, n = info.n }
			bones[name] = b
		end
		table.insert(b.parts, p)
		partBone[p.i] = name
	end
	local function sideName(s)
		return s < 0 and "L" or "R"
	end
	for _, p in ipairs(parts) do
		local r = role[p.i]
		local s = sideOf(p)
		local k = nearestAnchor(p)
		local suffix = k > 1 and ("#" .. k) or ""
		if r == "arm" or r == "held" then
			addTo("arm" .. sideName(s) .. suffix, p, { role = "arm" .. sideName(s), parent = "body", side = s })
		elseif r == "leg" then
			if quad then
				-- models face -Z: front legs have the smaller z
				local fb = p.pos[3] < zMid and "F" or "B"
				addTo("leg" .. fb .. sideName(s), p, { role = "leg" .. fb .. sideName(s), parent = "root", side = s })
			else
				addTo("leg" .. sideName(s) .. suffix, p, { role = "leg" .. sideName(s), parent = "root", side = s })
			end
		elseif r == "tail" then
			addTo("tail" .. suffix, p, { role = "tail", parent = "body", side = 0 })
		elseif r == "wing" or r == "wingheld" then
			addTo("wing" .. sideName(s) .. suffix, p, { role = "wing" .. sideName(s), parent = "body", side = s })
		elseif r == "head" then
			local n = headOf[p.i]
			addTo(n > 1 and ("head#" .. n) or "head", p, { role = "head", parent = "body", side = 0, n = n })
		else
			addTo("body", p, { role = "body", parent = "root", side = 0 })
		end
	end
	if not bones.body then
		bones.body = { name = "body", parts = {}, role = "body", parent = "root", side = 0 }
	end

	-- pivots
	local bodyAnchor = anchors[1]
	local bx = bodyAnchor and bodyAnchor.pos[1] or 0
	local bz = bodyAnchor and bodyAnchor.pos[3] or 0
	local hipY = 0
	for name, b in pairs(bones) do
		if b.role:sub(1, 3) == "leg" then
			local top, sx, sz = -math.huge, 0, 0
			for _, p in ipairs(b.parts) do
				local _, hi = yRange(p)
				top = math.max(top, hi)
				sx += p.pos[1]
				sz += p.pos[3]
			end
			-- hips sit a little below the top of the leg
			top = math.max(top - 0.06 * h, 0.05)
			b.pivot = { sx / #b.parts, top, sz / #b.parts }
			hipY = math.max(hipY, top)
		end
	end
	hipY = math.min(hipY, h * 0.55)
	for name, b in pairs(bones) do
		if b.pivot then
			continue
		end
		local r = b.role
		if r == "body" then
			b.pivot = { bx, hipY, bz }
		elseif r == "head" then
			local hd = heads[b.n or 1]
			local lo = yRange(hd)
			b.pivot = { hd.pos[1], lo + 0.1 * (hd.pos[2] - lo), hd.pos[3] + 0.1 }
		else
			-- shoulder / tail root / wing root: the part end closest to the torso's middle
			local _, ca = nearestAnchor(b.parts[1])
			local center = ca and { ca.pos[1], ca.pos[2], ca.pos[3] } or { 0, h * 0.5, 0 }
			local best, bd = nil, math.huge
			local candidates = {}
			for _, p in ipairs(b.parts) do
				local isHeld = role[p.i] == "held" or role[p.i] == "wingheld"
				if not isHeld then
					local a, c = ends(p)
					table.insert(candidates, a)
					table.insert(candidates, c)
				end
			end
			if #candidates == 0 then
				for _, p in ipairs(b.parts) do
					table.insert(candidates, p.pos)
				end
			end
			for _, c in ipairs(candidates) do
				local d
				if r:sub(1, 3) == "arm" or r:sub(1, 4) == "wing" then
					-- shoulders: closest sideways to the torso, then highest
					d = math.abs(c[1] - center[1]) * 3 - c[2] * 0.4
				else
					d = dist2(c, center)
				end
				if d < bd then
					best, bd = c, d
				end
			end
			b.pivot = { best[1], best[2], best[3] }
		end
	end

	-- parts of the torso that sit below the hips (a mannequin stand, a skateboard deck...) stay
	-- with the feet instead of swinging with the torso
	if hipY > 0.15 and bones.body then
		local keep, base = {}, {}
		for _, p in ipairs(bones.body.parts) do
			local _, hi = yRange(p)
			if hi < hipY - 0.02 then
				table.insert(base, p)
				partBone[p.i] = "base"
			else
				table.insert(keep, p)
			end
		end
		if #base > 0 then
			bones.body.parts = keep
			bones.base = { name = "base", parts = base, role = "base", parent = "root", side = 0, pivot = { bx, 0, bz } }
		end
	end

	-- limb lengths (shoulder to fingertip, hip to toe) and, for arms, the turn that makes the
	-- arm hang straight down: poses are written for a hanging arm, whatever way it was modeled
	for _, b in pairs(bones) do
		local r = b.role
		if r:sub(1, 3) == "arm" or r:sub(1, 3) == "leg" or r:sub(1, 4) == "wing" or r == "tail" then
			local far, fd = nil, 0
			for _, p in ipairs(b.parts) do
				if role[p.i] ~= "held" and role[p.i] ~= "wingheld" then
					local a, c = ends(p)
					for _, q in ipairs({ a, c, p.pos }) do
						local d = math.sqrt(dist2(q, b.pivot))
						if d > fd then
							far, fd = q, d
						end
					end
				end
			end
			b.len = math.max(fd, 0.2)
			if r:sub(1, 3) == "arm" and far and fd > 0.3 then
				local dx, dy, dz = far[1] - b.pivot[1], far[2] - b.pivot[2], far[3] - b.pivot[3]
				local l = math.sqrt(dx * dx + dy * dy + dz * dz)
				dx, dy, dz = dx / l, dy / l, dz / l
				-- rotation taking (dx, dy, dz) to straight down (0, -1, 0)
				-- axis = d x down = (dz, 0, -dx), angle from d . down = -dy
				local c = -dy
				local ax, ay, az = dz, 0, -dx
				local sn = math.sqrt(ax * ax + ay * ay + az * az)
				if sn > 1e-4 then
					ax, ay, az = ax / sn, ay / sn, az / sn
					local ang = math.atan2(sn, c)
					local co, si = math.cos(ang), math.sin(ang)
					local t = 1 - co
					b.fix = {
						t * ax * ax + co, t * ax * ay - si * az, t * ax * az + si * ay,
						t * ax * ay + si * az, t * ay * ay + co, t * ay * az - si * ax,
						t * ax * az - si * ay, t * ay * az + si * ax, t * az * az + co,
					}
				elseif c < 0 then
					-- pointing straight up: flip over the X axis
					b.fix = { 1, 0, 0, 0, -1, 0, 0, 0, -1 }
				end
			end
		end
	end

	-- front-to-back size (rearing up turns about the back feet, diving about the front)
	local zMin, zMax = math.huge, -math.huge
	for _, p in ipairs(parts) do
		zMin = math.min(zMin, p.pos[3])
		zMax = math.max(zMax, p.pos[3])
	end

	-- what this creature can do
	local has = {
		arms = (bones.armL ~= nil) or (bones.armR ~= nil),
		bothArms = bones.armL ~= nil and bones.armR ~= nil,
		legs = (bones.legL ~= nil and bones.legR ~= nil) or quad,
		quad = quad,
		head = bones.head ~= nil,
		tail = bones.tail ~= nil,
		wings = bones.wingL ~= nil or bones.wingR ~= nil,
		wheels = false,
		weapon = false,
		heads = #heads,
	}
	local weaponSide
	for _, p in ipairs(parts) do
		if WHEEL[p.name] then
			has.wheels = true
		end
		if WEAPON[p.name] and (role[p.i] == "held" or role[p.i] == "wingheld") then
			has.weapon = true
			weaponSide = sideOf(p)
		end
	end
	local kind
	if quad then
		kind = "quad"
	elseif has.arms and has.legs then
		kind = "biped"
	elseif has.arms then
		kind = "arms"
	elseif has.legs then
		kind = "legs"
	else
		kind = "blob"
	end
	-- pivots must be finite
	for _, b in pairs(bones) do
		for k = 1, 3 do
			assert(b.pivot[k] == b.pivot[k] and math.abs(b.pivot[k]) < 1e6, "bad pivot in " .. id)
		end
	end
	return {
		id = id,
		height = h,
		kind = kind,
		has = has,
		bones = bones,
		partBone = partBone,
		weaponSide = weaponSide,
		parts = parts,
		zMin = zMin,
		zMax = zMax,
	}
end

---------------------------------------------------------------------------
-- Posing: turns a pose (from Moves) into one transform per bone, in model space.
-- A transform is { m = 3x3 rotation (row-major), t = {x,y,z} }: point' = m * point + t.
---------------------------------------------------------------------------
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function boneTf(pivot, e, h, mirror, limb, fix)
	-- e = { p, y, r, x, u, f } (degrees and fractions of the creature's height; for limbs the
	-- offsets are fractions of the limb's length, so long arms don't fly off their shoulders)
	-- p: limbs swing forward (+) / back; body and head lean forward (+) / back
	-- y: twist, r: roll out (+) for limbs (mirrored per side), lean to the side for body
	-- x: sideways (outward for limbs), u: up, f: forward (models face -Z)
	if not e then
		if not fix then
			return nil
		end
		e = {}
	end
	local p = rad(e.p or 0)
	if not limb then
		p = -p
	end
	local yw = rad(e.y or 0) * mirror
	local rl = rad(e.r or 0) * mirror
	local m = euler(p, yw, rl)
	if fix then
		m = mmul(m, fix)
	end
	local ox = (e.x or 0) * h * mirror
	local oy = (e.u or 0) * h
	local oz = -(e.f or 0) * h
	local px, py, pz = pivot[1], pivot[2], pivot[3]
	local rx, ry, rz = mvec(m, -px, -py, -pz)
	return { m = m, t = { rx + px + ox, ry + py + oy, rz + pz + oz } }
end

local function compose(a, b)
	-- a after b: point -> a(b(point))
	if not a then
		return b
	end
	if not b then
		return a
	end
	local m = mmul(a.m, b.m)
	local x, y, z = mvec(a.m, b.t[1], b.t[2], b.t[3])
	return { m = m, t = { x + a.t[1], y + a.t[2], z + a.t[3] } }
end
Rig.compose = compose

-- pose = { body = e, head = e, lead = e (attacking arm), rear = e, legLead = e, legRear = e,
--          tail = e, wings = e, root = e } with lead = "R" or "L".
-- Returns { [boneName] = transform } for every bone that moves (others stay put).
function Rig.solve(rig, pose)
	local out = {}
	local h = rig.height
	local leadSide = (pose.leadSide == "L") and -1 or 1
	local function entryFor(b)
		local r = b.role
		if r == "body" then
			return pose.body, 1, false
		elseif r == "head" then
			return pose.head, 1, false
		elseif r == "tail" then
			return pose.tail, 1, false
		elseif r == "armL" or r == "armR" then
			local s = r == "armL" and -1 or 1
			return (s == leadSide) and pose.lead or pose.rear, s, true
		elseif r == "legL" or r == "legR" then
			local s = r == "legL" and -1 or 1
			return (s == leadSide) and pose.legLead or pose.legRear, s, true
		elseif r == "legFL" or r == "legFR" or r == "legBL" or r == "legBR" then
			local s = r:sub(5, 5) == "L" and -1 or 1
			local front = r:sub(4, 4) == "F"
			local e
			if front then
				e = (s == leadSide) and (pose.frontLead or pose.legLead) or (pose.frontRear or pose.legRear)
			else
				e = (s == leadSide) and (pose.backLead or pose.legRear) or (pose.backRear or pose.legLead)
			end
			return e, s, true
		elseif r == "wingL" or r == "wingR" then
			local s = r == "wingL" and -1 or 1
			local e = pose.wings
			if not rig.has.arms then
				-- no arms: the wings do the punching (and hold things, like a spyglass)
				local arm = (s == leadSide) and pose.lead or pose.rear
				if arm then
					local sum = {}
					for _, f in ipairs({ "p", "y", "r", "x", "u", "f" }) do
						local v = (e and e[f] or 0) + (arm[f] or 0) * 0.8
						if v ~= 0 then
							sum[f] = v
						end
					end
					e = sum
				end
			end
			return e, s, true
		end
		return nil, 1, false
	end
	local bodyE, rootE = pose.body, pose.root
	if rig.kind == "quad" and bodyE and (bodyE.p or bodyE.u or bodyE.f) then
		-- four legs: leaning means tipping the whole animal, not snapping it at the hips
		bodyE = table.clone(bodyE)
		rootE = rootE and table.clone(rootE) or {}
		rootE.p = (rootE.p or 0) + (bodyE.p or 0) * 0.35
		rootE.f = (rootE.f or 0) + (bodyE.f or 0)
		rootE.u = (rootE.u or 0) + math.max(bodyE.u or 0, 0)
		bodyE.p, bodyE.u, bodyE.f = nil, nil, nil
	end
	local bodyTf = boneTf(rig.bones.body.pivot, bodyE, h, 1, false)
	for name, b in pairs(rig.bones) do
		local e, mirror, limb = entryFor(b)
		local tf
		if name == "body" then
			tf = bodyTf
		elseif b.role == "base" then
			tf = nil
		else
			-- extra heads bob a little out of step
			if b.role == "head" and b.n and b.n > 1 and pose.head and pose.headLag then
				local lag = pose.headLag[b.n]
				if lag then
					e = lag
				end
			end
			tf = boneTf(b.pivot, e, limb and (b.len or h) * 0.5 or h, mirror, limb, b.fix)
			if b.parent == "body" then
				tf = compose(bodyTf, tf)
			end
		end
		if tf then
			out[name] = tf
		end
	end
	if rootE then
		-- tipping back turns about the heels, tipping forward about the toes
		local pz = rig.bones.body.pivot[3]
		if (rootE.p or 0) < 0 then
			pz = pz + (rig.zMax - pz) * 0.7
		elseif (rootE.p or 0) > 0 then
			pz = pz + (rig.zMin - pz) * 0.7
		end
		local rootTf = boneTf({ rig.bones.body.pivot[1], 0, pz }, rootE, h, leadSide, false)
		for name, b in pairs(rig.bones) do
			out[name] = compose(rootTf, out[name] or { m = IDENT, t = { 0, 0, 0 } })
		end
	end
	return out
end

-- Model-space position of part i under solved transforms (used by the tests and the preview).
function Rig.partPos(rig, solved, i)
	local p = rig.parts[i]
	local tf = solved[rig.partBone[i]]
	if not tf then
		return p.pos[1], p.pos[2], p.pos[3]
	end
	local x, y, z = mvec(tf.m, p.pos[1], p.pos[2], p.pos[3])
	return x + tf.t[1], y + tf.t[2], z + tf.t[3]
end

return Rig

-- Moves: the fighting animations of Pack Brawl creatures, as keyframed poses.
-- Pure Lua (no Roblox instances), so the tests check every move on every creature.
--
-- A pose names bones by what they do, not by side:
--   body, head, tail, wings, root (the whole creature, legs included)
--   lead / rear         the attacking arm and the other arm
--   legLead / legRear   the leg on the attacking side and the other leg
--   frontLead, frontRear, backLead, backRear   four-legged creatures (fall back to legLead/legRear)
-- Each entry is { p, y, r, x, u, f }:
--   p  swing forward (+) / back for limbs; lean forward (+) / back for body, head, root (degrees)
--   y  twist (degrees), r  roll: limbs out (+) / in, body tilts to the lead side (+)
--   x  sideways (toward the lead side for body/root, outward for limbs), u up, f forward
--      (x, u, f are fractions of the creature's height)
--
-- Attack moves hit at their `contact` time. Scripts.luau starts the swing that much earlier,
-- so the fist (or foot, head, tail...) lands exactly when the hit cue fires.

local Moves = {}

local KEYS = { "body", "head", "lead", "rear", "legLead", "legRear", "frontLead", "frontRear", "backLead", "backRear", "tail", "wings", "root" }
local FIELDS = { "p", "y", "r", "x", "u", "f" }
Moves.KEYS = KEYS

-- Contact times (seconds from swing start to the hit) by power, and for signature moves.
Moves.Contact = { 0.12, 0.2, 0.3 }
Moves.SignatureContact = 0.45

local function sm(a)
	return a * a * (3 - 2 * a)
end
local EASE = {
	smooth = sm,
	linear = function(a)
		return a
	end,
	out = function(a)
		return 1 - (1 - a) ^ 3
	end,
	inn = function(a)
		return a * a * a
	end,
	snap = function(a)
		return 1 - (1 - a) ^ 5
	end,
}

---------------------------------------------------------------------------
-- Pose helpers
---------------------------------------------------------------------------
local function copy(pose)
	local out = {}
	for k, v in pairs(pose) do
		if type(v) == "table" then
			local e = {}
			for f, n in pairs(v) do
				e[f] = n
			end
			out[k] = e
		else
			out[k] = v
		end
	end
	return out
end

-- a with b laid over it (b's entries replace a's)
local function over(a, b)
	local out = copy(a)
	for k, v in pairs(b) do
		if type(v) == "table" then
			local e = {}
			for f, n in pairs(v) do
				e[f] = n
			end
			out[k] = e
		else
			out[k] = v
		end
	end
	return out
end
Moves.over = over

local function lerpPose(a, b, w, wrapRoot)
	local out = {}
	for _, k in ipairs(KEYS) do
		local ea, eb = a[k], b[k]
		if ea or eb then
			local e = {}
			for _, f in ipairs(FIELDS) do
				local x, y = ea and ea[f] or 0, eb and eb[f] or 0
				if wrapRoot and f == "y" and (k == "root" or k == "body") then
					-- turn the short way (a 720 degree spin blends back to 0 without unwinding)
					x = x % 360
					y = y % 360
					if y - x > 180 then
						x += 360
					elseif x - y > 180 then
						y += 360
					end
				end
				if x ~= 0 or y ~= 0 then
					e[f] = x + (y - x) * w
				end
			end
			out[k] = e
		end
	end
	return out
end
Moves.lerp = lerpPose

-- Blends an animation pose (b) over a base pose (a) with weight w.
function Moves.blend(a, b, w)
	if w >= 1 then
		return b
	end
	if w <= 0 then
		return a
	end
	return lerpPose(a, b, w, true)
end

---------------------------------------------------------------------------
-- Base poses (what a creature does when no move is playing)
---------------------------------------------------------------------------
local GUARD = {
	body = { p = 8, y = -12 },
	head = { p = -4 },
	lead = { p = 62, r = -14, f = 0.04 },
	rear = { p = 44, r = -20, f = 0.02 },
	legLead = { p = 14, r = 4 },
	legRear = { p = -12, r = 4 },
	frontLead = { p = 4 },
	frontRear = { p = -4 },
	backLead = { p = -4 },
	backRear = { p = 4 },
	wings = { r = 12 },
}
Moves.GUARD = GUARD

-- Fighting stance: guard up, bouncing on the toes, breathing.
function Moves.stance(now, phase, rig)
	local b = math.abs(math.sin(now * 4.6 + phase))
	local s = math.sin(now * 2.3 + phase)
	local pose = copy(GUARD)
	pose.root = { u = 0.035 * b }
	pose.body.p += 3 * s
	pose.body.y += 4 * s
	pose.body.u = -0.015 * (1 - b)
	pose.lead.p += 6 * math.sin(now * 2.3 + phase + 1)
	pose.rear.p += 5 * math.sin(now * 2.3 + phase + 2.2)
	pose.legLead.p += 4 * (1 - b)
	pose.legRear.p -= 4 * (1 - b)
	pose.head.p += 3 * math.sin(now * 2.3 + phase + 0.5)
	pose.tail = { y = 18 * math.sin(now * 3.1 + phase), p = 6 * math.sin(now * 2.2 + phase) }
	pose.wings = { r = 12 + 10 * math.sin(now * 7 + phase) }
	if rig and rig.kind == "quad" then
		pose.body = { p = 3 * s }
		pose.head = { p = 10 + 4 * s }
	elseif rig and (rig.kind == "blob" or rig.kind == "arms") then
		-- no legs: sway and rock instead of bouncing
		pose.root = { u = 0.03 * b }
		pose.body = { p = 6 + 4 * s, r = 3 * math.sin(now * 1.7 + phase) }
	end
	return pose
end

-- Running / walking cycle while a fighter moves across the ring.
function Moves.run(now, phase, speed, rig)
	local w = now * (8 + 6 * math.min(speed, 1.5)) + phase
	local s, c = math.sin(w), math.cos(w)
	local amp = 28 + 14 * math.min(speed, 1.5)
	local pose = {
		root = { u = 0.05 * math.abs(c) },
		body = { p = 12 + 6 * math.min(speed, 1.5), y = 8 * s },
		head = { p = -6 },
		lead = { p = 30 - amp * 0.8 * s, r = -6 },
		rear = { p = 30 + amp * 0.8 * s, r = -6 },
		legLead = { p = amp * s },
		legRear = { p = -amp * s },
		frontLead = { p = amp * 0.8 * s },
		frontRear = { p = -amp * 0.8 * s },
		backLead = { p = -amp * 0.8 * s },
		backRear = { p = amp * 0.8 * s },
		tail = { y = 20 * c, p = -10 },
		wings = { r = 25 + 25 * s },
	}
	if rig and rig.kind == "quad" then
		pose.body = { p = 2 * s }
		pose.head = { p = 15 + 6 * c }
	elseif rig and (rig.kind == "blob" or rig.kind == "arms") then
		-- no legs: hop-scoot along
		pose.root = { u = 0.09 * math.abs(s), p = 6 }
		pose.body = { p = 10, r = 8 * s }
	end
	return pose
end

-- Knocked out on the floor: everything goes limp and floppy.
function Moves.limp(now, phase)
	local t = math.sin(now * 1.3 + phase) * 3
	return {
		body = { p = -6 },
		head = { p = -25, y = 35 + t, r = 15 },
		lead = { p = 20, r = 85 },
		rear = { p = 35, r = 70 },
		legLead = { p = 25, r = 22 },
		legRear = { p = 10, r = 30 },
		frontLead = { p = 50 },
		frontRear = { p = 35 },
		backLead = { p = -40 },
		backRear = { p = -30 },
		tail = { p = -20, y = 10 },
		wings = { r = 70 },
	}
end

---------------------------------------------------------------------------
-- Keyframed moves
---------------------------------------------------------------------------
-- move = { dur, contact (attacks), loop, frames = { { t, pose, ease } }, headStagger }
local M = {}
Moves.list = M

local function move(def)
	-- every frame without a pose of its own holds the guard
	for _, fr in ipairs(def.frames) do
		fr[2] = fr[2] == "guard" and GUARD or fr[2]
	end
	def.dur = def.dur or def.frames[#def.frames][1]
	return def
end

local G = GUARD
local function g(t)
	return over(G, t)
end

------------------------------ attacks: arms ------------------------------
M.jab = move({
	contact = 0.12,
	frames = {
		{ 0, "guard" },
		{ 0.05, g({ lead = { p = 48, r = -10, f = -0.04 }, body = { p = 6, y = -20 } }) },
		{ 0.12, g({ lead = { p = 96, r = -6, f = 0.36, u = 0.04 }, rear = { p = 50, r = -24 }, body = { p = 14, y = 22, f = 0.04 }, head = { p = 6 }, legLead = { p = 22 }, legRear = { p = -18 } }), "snap" },
		{ 0.2, g({ lead = { p = 90, r = -6, f = 0.3 }, body = { p = 12, y = 18 } }) },
		{ 0.34, "guard" },
	},
})

M.cross = move({
	contact = 0.12,
	frames = {
		{ 0, "guard" },
		{ 0.05, g({ lead = { p = 40, r = 0, f = -0.06 }, body = { p = 4, y = -32 } }) },
		{ 0.12, g({ lead = { p = 98, r = -16, f = 0.42, x = -0.04 }, rear = { p = 55, r = -28 }, body = { p = 18, y = 38, f = 0.06 }, legRear = { p = -26 }, legLead = { p = 24 } }), "snap" },
		{ 0.22, g({ lead = { p = 88, r = -12, f = 0.32 }, body = { p = 14, y = 30 } }) },
		{ 0.36, "guard" },
	},
})

M.hook = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.1, g({ lead = { p = 70, r = 62, f = -0.02 }, body = { p = 6, y = -40 }, head = { p = 0 } }) },
		{ 0.2, g({ lead = { p = 88, r = 8, f = 0.26, x = -0.06 }, body = { p = 14, y = 38 }, legLead = { p = 18 }, legRear = { p = -20 } }), "snap" },
		{ 0.32, g({ lead = { p = 78, r = -36, f = 0.12, x = -0.12 }, body = { p = 12, y = 52 } }) },
		{ 0.52, "guard" },
	},
})

M.uppercut = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.11, g({ lead = { p = -12, r = 6, u = -0.04 }, body = { p = 24, u = -0.08, y = -14 }, head = { p = 8 }, legLead = { p = 30, r = 12 }, legRear = { p = -24, r = 12 }, root = { u = -0.03 } }) },
		{ 0.2, g({ lead = { p = 165, r = -8, f = 0.18, u = 0.16 }, body = { p = -16, u = 0.06, y = 18 }, head = { p = -14 }, root = { u = 0.07 }, legLead = { p = 10 }, legRear = { p = -6 } }), "snap" },
		{ 0.32, g({ lead = { p = 172, f = 0.12, u = 0.2 }, body = { p = -10, u = 0.04 }, root = { u = 0.04 } }) },
		{ 0.52, "guard" },
	},
})

M.haymaker = move({
	contact = 0.3,
	frames = {
		{ 0, "guard" },
		{ 0.18, g({ lead = { p = -45, r = 45, f = -0.08, u = 0.04 }, rear = { p = 60, r = -10 }, body = { p = -4, y = -55 }, legRear = { p = -24 }, legLead = { p = 10 } }) },
		{ 0.24, g({ lead = { p = -40, r = 50, f = -0.08, u = 0.05 }, body = { p = -6, y = -60 } }) },
		{ 0.3, g({ lead = { p = 98, r = 0, f = 0.44, u = 0.04 }, rear = { p = 30, r = 30 }, body = { p = 22, y = 44, f = 0.08 }, root = { f = 0.08 }, legLead = { p = 32 }, legRear = { p = -30 } }), "snap" },
		{ 0.46, g({ lead = { p = 82, r = -30, f = 0.25, x = -0.08 }, body = { p = 18, y = 50 } }) },
		{ 0.7, "guard" },
	},
})

M.doubleAxe = move({
	contact = 0.3,
	frames = {
		{ 0, "guard" },
		{ 0.2, g({ lead = { p = 172, r = -12, u = 0.08 }, rear = { p = 172, r = -12, u = 0.08 }, body = { p = -16, u = 0.04, y = 0 }, head = { p = -12 }, root = { u = 0.05 } }) },
		{ 0.3, g({ lead = { p = 62, r = -18, f = 0.22 }, rear = { p = 62, r = -18, f = 0.22 }, body = { p = 34, u = -0.06, y = 0, f = 0.06 }, head = { p = 12 }, root = { u = -0.02 }, legLead = { p = 26, r = 10 }, legRear = { p = -22, r = 10 } }), "snap" },
		{ 0.45, g({ lead = { p = 55, f = 0.16 }, rear = { p = 55, f = 0.16 }, body = { p = 28, u = -0.05, y = 0 } }) },
		{ 0.7, "guard" },
	},
})

-- Weapon overhead chop (spears, forks, wands, plungers...)
M.overhead = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.12, g({ lead = { p = 175, r = 8, u = 0.08, f = -0.04 }, body = { p = -14, y = -16 }, head = { p = -10 }, legRear = { p = -20 } }) },
		{ 0.2, g({ lead = { p = 70, r = -8, f = 0.26 }, body = { p = 28, y = 12, f = 0.05 }, head = { p = 10 }, legLead = { p = 28 }, legRear = { p = -24 } }), "snap" },
		{ 0.34, g({ lead = { p = 58, f = 0.18 }, body = { p = 24, y = 10 } }) },
		{ 0.55, "guard" },
	},
})

M.overheadBig = move({
	contact = 0.3,
	frames = {
		{ 0, "guard" },
		{ 0.22, g({ lead = { p = 200, r = 10, u = 0.12, f = -0.08 }, rear = { p = 120, r = 20 }, body = { p = -22, y = -20, u = 0.03 }, head = { p = -16 }, root = { u = 0.05 }, legRear = { p = -24 } }) },
		{ 0.3, g({ lead = { p = 62, r = -10, f = 0.32 }, rear = { p = 40, r = 30 }, body = { p = 36, y = 14, f = 0.08, u = -0.04 }, head = { p = 14 }, root = { u = -0.03 }, legLead = { p = 34, r = 8 }, legRear = { p = -30, r = 8 } }), "snap" },
		{ 0.48, g({ lead = { p = 52, f = 0.22 }, body = { p = 30, y = 10, u = -0.04 } }) },
		{ 0.72, "guard" },
	},
})

-- Weapon thrust (spears, canes, flashlights)
M.thrust = move({
	contact = 0.12,
	frames = {
		{ 0, "guard" },
		{ 0.06, g({ lead = { p = 70, f = -0.1 }, body = { p = 4, y = -20 } }) },
		{ 0.12, g({ lead = { p = 92, f = 0.48, u = 0.03 }, body = { p = 16, y = 18, f = 0.06 }, legLead = { p = 26 }, legRear = { p = -22 } }), "snap" },
		{ 0.22, g({ lead = { p = 88, f = 0.36 }, body = { p = 12, y = 14 } }) },
		{ 0.36, "guard" },
	},
})

------------------------------ attacks: legs ------------------------------
M.kick = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.1, g({ legLead = { p = 62, u = 0.08, f = 0.04 }, body = { p = -10, y = -6 }, lead = { p = 60, r = 10 }, rear = { p = 30, r = 25 } }) },
		{ 0.2, g({ legLead = { p = 96, u = 0.12, f = 0.26 }, legRear = { p = -10 }, body = { p = -22, f = -0.03 }, lead = { p = 30, r = 45 }, rear = { p = 20, r = 45 }, head = { p = -8 } }), "snap" },
		{ 0.32, g({ legLead = { p = 50, u = 0.05, f = 0.08 }, body = { p = -10 } }) },
		{ 0.5, "guard" },
	},
})

M.stomp = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.12, g({ legLead = { p = 55, u = 0.18, f = 0.1 }, body = { p = -12, r = -8 }, lead = { p = 20, r = 50 }, rear = { p = 20, r = 50 }, root = { u = 0.03 } }) },
		{ 0.2, g({ legLead = { p = 12, f = 0.14 }, body = { p = 18, r = 6, u = -0.04 }, root = { u = -0.02 } }), "inn" },
		{ 0.34, g({ legLead = { p = 10, f = 0.1 }, body = { p = 12 } }) },
		{ 0.5, "guard" },
	},
})

M.spinKick = move({
	contact = 0.3,
	frames = {
		{ 0, "guard" },
		{ 0.15, g({ root = { y = -70, u = 0.02 }, body = { p = 6 }, legLead = { p = 20, r = 10 } }) },
		{ 0.3, g({ root = { y = 30, u = 0.06 }, legLead = { p = 85, r = 70, u = 0.15, f = 0.12 }, body = { p = -18, r = -20 }, lead = { p = 40, r = 70 }, rear = { p = 40, r = 70 }, head = { p = -10 } }), "out" },
		{ 0.46, g({ root = { y = 55, u = 0.02 }, legLead = { p = 50, r = 40, u = 0.06 }, body = { p = -8, r = -8 } }) },
		{ 0.7, g({ root = { y = 0 } }) },
	},
})

------------------------------ attacks: heads, bodies, tails, wings ------------------------------
M.headbutt = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.12, g({ body = { p = -26, u = 0.02 }, head = { p = -26 }, root = { f = -0.04 }, lead = { p = 20, r = 30 }, rear = { p = 20, r = 30 } }) },
		{ 0.2, g({ body = { p = 36, f = 0.14 }, head = { p = 32, f = 0.05 }, root = { f = 0.1 }, lead = { p = 0, r = 25 }, rear = { p = 0, r = 25 } }), "snap" },
		{ 0.34, g({ body = { p = 20, f = 0.08 }, head = { p = 14 } }) },
		{ 0.52, "guard" },
	},
})

M.bump = move({
	contact = 0.12,
	frames = {
		{ 0, "guard" },
		{ 0.06, g({ body = { p = -14, u = -0.04 }, root = { u = -0.02 } }) },
		{ 0.12, g({ body = { p = 26, f = 0.16, u = 0.02 }, root = { f = 0.12, u = 0.04 }, head = { p = 18 } }), "snap" },
		{ 0.34, "guard" },
	},
})

M.bodySlam = move({
	contact = 0.3,
	frames = {
		{ 0, "guard" },
		{ 0.18, g({ body = { p = -18, u = -0.08 }, root = { u = -0.05 }, lead = { p = 100, r = 40 }, rear = { p = 100, r = 40 }, legLead = { r = 16 }, legRear = { r = 16 } }) },
		{ 0.24, g({ body = { p = -6, u = 0.06 }, root = { u = 0.2, f = 0.08 } }), "out" },
		{ 0.3, g({ body = { p = 40, f = 0.2, u = -0.04 }, root = { u = 0.02, f = 0.16 }, head = { p = 20 }, lead = { p = 140, r = 30, f = 0.2 }, rear = { p = 140, r = 30, f = 0.2 } }), "inn" },
		{ 0.46, g({ body = { p = 30, f = 0.14 }, root = { f = 0.12 } }) },
		{ 0.7, "guard" },
	},
})

M.tailWhip = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.1, g({ root = { y = -100 }, tail = { y = -30, p = 10 }, body = { p = 10 } }) },
		{ 0.2, g({ root = { y = -185 }, tail = { y = 55, p = -10 }, body = { p = 14 } }), "snap" },
		{ 0.32, g({ root = { y = -230 }, tail = { y = -40 } }) },
		{ 0.55, g({ root = { y = -360 } }) },
	},
})

M.wingSlap = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.12, g({ wings = { r = 75, p = -20 }, lead = { p = -30, r = 70 }, body = { p = -12 }, root = { u = 0.06 } }) },
		{ 0.2, g({ wings = { r = -10, p = 60 }, lead = { p = 80, r = 10, f = 0.2 }, body = { p = 24, f = 0.08 }, root = { u = 0.03, f = 0.06 } }), "snap" },
		{ 0.34, g({ wings = { r = 20, p = 30 }, body = { p = 14 } }) },
		{ 0.52, "guard" },
	},
})

-- Four-legged: rear up on the back legs, crash down with the front hooves.
M.rearStomp = move({
	contact = 0.3,
	frames = {
		{ 0, "guard" },
		{ 0.2, g({ root = { p = -32, u = 0.04 }, frontLead = { p = 70 }, frontRear = { p = 50 }, head = { p = -20 }, tail = { p = -30 } }) },
		{ 0.3, g({ root = { p = 6, f = 0.12 }, frontLead = { p = -12 }, frontRear = { p = -8 }, head = { p = 28 } }), "inn" },
		{ 0.45, g({ root = { p = 4, f = 0.1 }, head = { p = 18 } }) },
		{ 0.7, "guard" },
	},
})

M.charge = move({
	contact = 0.2,
	frames = {
		{ 0, "guard" },
		{ 0.1, g({ head = { p = 38 }, body = { p = 10, u = -0.03 }, root = { f = -0.05 }, frontLead = { p = -20 }, backLead = { p = 20 } }) },
		{ 0.2, g({ head = { p = 30, f = 0.06 }, body = { p = 16, f = 0.08 }, root = { f = 0.16 }, frontLead = { p = 30 }, backLead = { p = -30 } }), "snap" },
		{ 0.34, g({ head = { p = -20 }, root = { f = 0.08 } }) },
		{ 0.52, "guard" },
	},
})

------------------------------ defense and reactions ------------------------------
M.block = move({
	frames = {
		{ 0, "guard" },
		{ 0.08, g({ lead = { p = 82, r = -38, f = 0.1, u = 0.06 }, rear = { p = 76, r = -42, f = 0.08, u = 0.05 }, body = { p = 14, u = -0.04, y = 0 }, head = { p = 18, u = -0.02 }, legLead = { p = 18, r = 8 }, legRear = { p = -18, r = 8 }, wings = { r = -20, p = 60 } }), "snap" },
		{ 0.22, g({ lead = { p = 80, r = -36, f = 0.06, u = 0.05 }, rear = { p = 74, r = -40, f = 0.05, u = 0.04 }, body = { p = 6, u = -0.03, y = 0, f = -0.03 }, head = { p = 14 }, root = { f = -0.05 }, wings = { r = -20, p = 60 } }) },
		{ 0.42, "guard" },
	},
})

M.duck = move({
	frames = {
		{ 0, "guard" },
		{ 0.08, g({ body = { p = 42, u = -0.12 }, root = { u = -0.05 }, head = { p = 22 }, lead = { p = 60, r = -20 }, rear = { p = 60, r = -20 }, legLead = { p = 30, r = 16 }, legRear = { p = -30, r = 16 } }), "snap" },
		{ 0.26, g({ body = { p = 38, u = -0.1 }, root = { u = -0.04 }, head = { p = 18 } }) },
		{ 0.44, "guard" },
	},
})

M.sway = move({
	frames = {
		{ 0, "guard" },
		{ 0.08, g({ body = { p = -38, f = -0.06 }, root = { f = -0.16 }, head = { p = -18 }, lead = { p = 30, r = 30 }, rear = { p = 20, r = 40 }, legLead = { p = 26 } }), "snap" },
		{ 0.26, g({ body = { p = -30, f = -0.05 }, root = { f = -0.13 }, head = { p = -12 } }) },
		{ 0.44, "guard" },
	},
})

M.sidestep = move({
	frames = {
		{ 0, "guard" },
		{ 0.09, g({ root = { x = -0.42, u = 0.04, y = -18 }, body = { r = -16, p = 10 }, legRear = { r = 24 }, legLead = { r = -10 } }), "snap" },
		{ 0.28, g({ root = { x = -0.36, y = -14 }, body = { r = -8, p = 8 } }) },
		{ 0.5, "guard" },
	},
})

M.flinch = move({
	frames = {
		{ 0, "guard" },
		{ 0.05, g({ head = { p = -34, y = 12 }, body = { p = -16, f = -0.03 }, lead = { p = 24, r = 32 }, rear = { p = 14, r = 36 }, root = { f = -0.05 }, tail = { p = 30 }, wings = { r = 60 } }), "snap" },
		{ 0.14, g({ head = { p = -20, y = 8 }, body = { p = -10 }, root = { f = -0.03 } }) },
		{ 0.32, "guard" },
	},
})

M.stagger = move({
	frames = {
		{ 0, "guard" },
		{ 0.06, g({ head = { p = -44, y = 22, r = 10 }, body = { p = -26, r = 16, f = -0.04 }, lead = { p = -20, r = 62 }, rear = { p = -10, r = 70 }, legLead = { p = -22, r = 10 }, legRear = { p = 26, r = 10 }, root = { f = -0.06 }, tail = { p = 40 }, wings = { r = 80 } }), "snap" },
		{ 0.22, g({ head = { p = -8, y = -12 }, body = { p = -12, r = -10 }, lead = { p = 20, r = 40 }, rear = { p = 30, r = 30 }, legLead = { p = 8, r = 14 }, legRear = { p = -6, r = 14 } }) },
		{ 0.36, g({ head = { p = 6 }, body = { p = 4, r = 6 } }) },
		{ 0.56, "guard" },
	},
})

-- Knocked flying: arched back, limbs flailing (loops while in the air).
M.launch = move({
	loop = true,
	frames = {
		{ 0, { body = { p = -32 }, head = { p = -40, y = 10 }, lead = { p = -40, r = 100 }, rear = { p = 60, r = 90 }, legLead = { p = 40, r = 20 }, legRear = { p = -30, r = 25 }, tail = { p = 50 }, wings = { r = 90 } } },
		{ 0.12, { body = { p = -36 }, head = { p = -30, y = -10 }, lead = { p = 70, r = 85 }, rear = { p = -30, r = 105 }, legLead = { p = -25, r = 25 }, legRear = { p = 45, r = 20 }, tail = { p = 30 }, wings = { r = 40 } } },
		{ 0.24, { body = { p = -32 }, head = { p = -40, y = 10 }, lead = { p = -40, r = 100 }, rear = { p = 60, r = 90 }, legLead = { p = 40, r = 20 }, legRear = { p = -30, r = 25 }, tail = { p = 50 }, wings = { r = 90 } } },
	},
})

-- Crashing in feet- or fist-first (a crasher's landing hit).
M.dive = move({
	frames = {
		{ 0, { body = { p = 30 }, head = { p = -20 }, lead = { p = 160, f = 0.15 }, rear = { p = 150, f = 0.1 }, legLead = { p = -40 }, legRear = { p = -50 }, wings = { r = 80 } } },
		{ 0.3, { body = { p = 34 }, head = { p = -14 }, lead = { p = 165, f = 0.18 }, rear = { p = 155, f = 0.12 }, legLead = { p = -45 }, legRear = { p = -55 }, wings = { r = 80 } } },
		{ 0.55, "guard" },
	},
})

------------------------------ loops for scenes ------------------------------
M.cheer = move({
	loop = true,
	frames = {
		{ 0, { root = { u = 0 }, body = { p = -10 }, head = { p = -16 }, lead = { p = 165, r = 15 }, rear = { p = 140, r = 30 }, legLead = { r = 8 }, legRear = { r = 8 }, wings = { r = 90 }, tail = { y = 30 } } },
		{ 0.25, { root = { u = 0.06 }, body = { p = -14 }, head = { p = -22 }, lead = { p = 178, r = 10, u = 0.06 }, rear = { p = 160, r = 25, u = 0.05 }, legLead = { p = 10 }, legRear = { p = -10 }, wings = { r = 40 }, tail = { y = -30 } } },
		{ 0.5, { root = { u = 0 }, body = { p = -10 }, head = { p = -16 }, lead = { p = 165, r = 15 }, rear = { p = 140, r = 30 }, legLead = { r = 8 }, legRear = { r = 8 }, wings = { r = 90 }, tail = { y = 30 } } },
	},
})

M.flex = move({
	loop = true,
	frames = {
		{ 0, { body = { p = -6, u = 0.02 }, head = { p = -12 }, lead = { p = 10, r = 85 }, rear = { p = 10, r = 85 }, legLead = { r = 12 }, legRear = { r = 12 }, wings = { r = 80 } } },
		{ 0.5, { body = { p = -8, u = 0.03 }, head = { p = -16, y = 10 }, lead = { p = 20, r = 95, u = 0.03 }, rear = { p = 20, r = 95, u = 0.03 }, legLead = { r = 14 }, legRear = { r = 14 }, wings = { r = 95 } } },
		{ 1.0, { body = { p = -6, u = 0.02 }, head = { p = -12 }, lead = { p = 10, r = 85 }, rear = { p = 10, r = 85 }, legLead = { r = 12 }, legRear = { r = 12 }, wings = { r = 80 } } },
	},
})

M.flail = move({
	loop = true,
	frames = {
		{ 0, { body = { p = 20, r = 20 }, head = { p = -20 }, lead = { p = 150, r = 40 }, rear = { p = -40, r = 80 }, legLead = { p = 60 }, legRear = { p = -40 }, wings = { r = 90 } } },
		{ 0.1, { body = { p = -10, r = -20 }, head = { p = 20, y = 30 }, lead = { p = -30, r = 90 }, rear = { p = 140, r = 30 }, legLead = { p = -40 }, legRear = { p = 60 }, wings = { r = 10 } } },
		{ 0.2, { body = { p = 20, r = 20 }, head = { p = -20 }, lead = { p = 150, r = 40 }, rear = { p = -40, r = 80 }, legLead = { p = 60 }, legRear = { p = -40 }, wings = { r = 90 } } },
	},
})

M.grapple = move({
	loop = true,
	frames = {
		{ 0, g({ lead = { p = 92, r = -10, f = 0.28 }, rear = { p = 88, r = -10, f = 0.26 }, body = { p = 26, y = 0, f = 0.05 }, head = { p = 14 }, legLead = { p = 30 }, legRear = { p = -34 } }) },
		{ 0.17, g({ lead = { p = 96, r = -14, f = 0.32 }, rear = { p = 84, r = -8, f = 0.22 }, body = { p = 30, y = 8, f = 0.07 }, head = { p = 18 }, legLead = { p = 34 }, legRear = { p = -38 } }) },
		{ 0.34, g({ lead = { p = 92, r = -10, f = 0.28 }, rear = { p = 88, r = -10, f = 0.26 }, body = { p = 26, y = 0, f = 0.05 }, head = { p = 14 }, legLead = { p = 30 }, legRear = { p = -34 } }) },
	},
})

M.powerUp = move({
	loop = true,
	frames = {
		{ 0, { body = { p = 16, u = -0.06 }, head = { p = 10 }, lead = { p = -30, r = 35 }, rear = { p = -30, r = 35 }, legLead = { p = 10, r = 18 }, legRear = { p = -10, r = 18 }, wings = { r = 100 }, root = { u = -0.02 } } },
		{ 0.05, { body = { p = 16, u = -0.06, r = 2 }, head = { p = 12 }, lead = { p = -34, r = 38 }, rear = { p = -26, r = 32 }, legLead = { p = 10, r = 18 }, legRear = { p = -10, r = 18 }, wings = { r = 110 }, root = { u = -0.02, x = 0.01 } } },
		{ 0.1, { body = { p = 16, u = -0.06 }, head = { p = 10 }, lead = { p = -30, r = 35 }, rear = { p = -30, r = 35 }, legLead = { p = 10, r = 18 }, legRear = { p = -10, r = 18 }, wings = { r = 100 }, root = { u = -0.02 } } },
	},
})

M.push = move({
	loop = true,
	frames = {
		{ 0, g({ lead = { p = 92, r = -6, f = 0.34 }, rear = { p = 92, r = -6, f = 0.34 }, body = { p = 18, y = 0 }, head = { p = 4 }, legLead = { p = 30 }, legRear = { p = -30 } }) },
		{ 0.08, g({ lead = { p = 94, r = -4, f = 0.36 }, rear = { p = 90, r = -8, f = 0.32 }, body = { p = 20, y = 2 }, head = { p = 6 }, legLead = { p = 30 }, legRear = { p = -30 } }) },
		{ 0.16, g({ lead = { p = 92, r = -6, f = 0.34 }, rear = { p = 92, r = -6, f = 0.34 }, body = { p = 18, y = 0 }, head = { p = 4 }, legLead = { p = 30 }, legRear = { p = -30 } }) },
	},
})

---------------------------------------------------------------------------
-- Signature moves (Epic and up). Contact at Moves.SignatureContact (0.45 s).
---------------------------------------------------------------------------
local SIG = {}
Moves.Signatures = SIG

-- Spaghetti Hydra: three heads strike one after another.
SIG.spaghetti_hydra = move({
	name = "Noodle Barrage",
	contact = 0.45,
	headStagger = 0.1,
	frames = {
		{ 0, "guard" },
		{ 0.15, g({ head = { p = -40, u = 0.06, f = -0.1 }, body = { p = -10 } }) },
		{ 0.25, g({ head = { p = 50, f = 0.3, u = -0.04 }, body = { p = 14, f = 0.06 } }), "snap" },
		{ 0.35, g({ head = { p = 20, f = 0.1 }, body = { p = 6 } }) },
		{ 0.45, g({ head = { p = 55, f = 0.34 }, body = { p = 20, f = 0.1 }, root = { f = 0.06 } }), "snap" },
		{ 0.65, g({ head = { p = 10 } }) },
		{ 0.9, "guard" },
	},
})

-- Glitter Gremlin: hops up and spikes the glue bottle down.
SIG.glitter_gremlin = move({
	name = "Glue Bomb",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.18, g({ body = { p = 20, u = -0.08 }, root = { u = -0.04 }, lead = { p = -20, r = 30 }, rear = { p = -20, r = 30 } }) },
		{ 0.33, g({ root = { u = 0.4 }, lead = { p = 200, u = 0.08 }, rear = { p = 120, r = 40 }, body = { p = -18 }, legLead = { p = 30 }, legRear = { p = -30 } }), "out" },
		{ 0.45, g({ root = { u = 0.12, f = 0.12 }, lead = { p = 60, f = 0.3 }, body = { p = 34, f = 0.08 }, head = { p = 14 } }), "inn" },
		{ 0.62, g({ root = { u = 0, f = 0.08 }, lead = { p = 50, f = 0.2 }, body = { p = 20 } }) },
		{ 0.9, "guard" },
	},
})

-- Lightning Llama: rears up crackling, hammers both front hooves down.
SIG.lightning_llama = move({
	name = "Thunder Rear",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.25, g({ root = { p = -40, u = 0.06 }, frontLead = { p = 85 }, frontRear = { p = 60 }, head = { p = -30 }, tail = { p = -40 } }) },
		{ 0.35, g({ root = { p = -44, u = 0.08 }, frontLead = { p = 60 }, frontRear = { p = 90 }, head = { p = -36, y = 10 } }) },
		{ 0.45, g({ root = { p = 8, f = 0.16 }, frontLead = { p = -14 }, frontRear = { p = -10 }, head = { p = 34 } }), "inn" },
		{ 0.62, g({ root = { p = 4, f = 0.12 }, head = { p = 20 } }) },
		{ 0.9, "guard" },
	},
})

-- Pigeon Squad: three pecks in a row, wings flapping.
SIG.pigeon_squad = move({
	name = "Squad Peck",
	contact = 0.45,
	headStagger = 0.08,
	frames = {
		{ 0, "guard" },
		{ 0.2, g({ head = { p = -30, f = -0.06 }, wings = { r = 80 }, body = { p = -8 } }) },
		{ 0.3, g({ head = { p = 55, f = 0.2, u = -0.06 }, wings = { r = 10 }, body = { p = 20 }, root = { f = 0.05 } }), "snap" },
		{ 0.38, g({ head = { p = -10 }, wings = { r = 80 } }) },
		{ 0.45, g({ head = { p = 60, f = 0.24, u = -0.08 }, wings = { r = 0 }, body = { p = 24 }, root = { f = 0.1 } }), "snap" },
		{ 0.65, g({ head = { p = 10 }, wings = { r = 50 } }) },
		{ 0.9, "guard" },
	},
})

-- Mall Cop Phantom: winds the flashlight way back and brings it down hard.
SIG.mall_cop_phantom = move({
	name = "Lights Out",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.15, g({ lead = { p = 120, f = 0.1 }, body = { p = -6, y = -10 }, head = { p = -10 } }) },
		{ 0.32, g({ lead = { p = 210, u = 0.12, f = -0.1 }, body = { p = -24, y = -24 }, head = { p = -18 }, root = { u = 0.04 } }) },
		{ 0.45, g({ lead = { p = 60, f = 0.32 }, body = { p = 34, y = 14, f = 0.08 }, head = { p = 12 }, root = { f = 0.08 } }), "snap" },
		{ 0.64, g({ lead = { p = 50, f = 0.2 }, body = { p = 24 } }) },
		{ 0.9, "guard" },
	},
})

-- Microwave Mage: twirls the wand in circles, then jabs it forward.
SIG.microwave_mage = move({
	name = "Defrost Hex",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.1, g({ lead = { p = 130, r = 40, u = 0.06 }, body = { p = -8, y = -10 } }) },
		{ 0.2, g({ lead = { p = 150, r = -20, u = 0.08 }, body = { p = -10, y = 6 } }) },
		{ 0.3, g({ lead = { p = 130, r = 40, u = 0.06 }, body = { p = -8, y = -14 } }) },
		{ 0.38, g({ lead = { p = 80, f = -0.08 }, body = { p = 0, y = -24 } }) },
		{ 0.45, g({ lead = { p = 95, f = 0.5, u = 0.03 }, rear = { p = -20, r = 50 }, body = { p = 18, y = 24, f = 0.08 }, legLead = { p = 28 }, legRear = { p = -26 } }), "snap" },
		{ 0.66, g({ lead = { p = 90, f = 0.34 }, body = { p = 14, y = 18 } }) },
		{ 0.9, "guard" },
	},
})

-- Burrito Bouncer: jab, cross, then a rising uppercut.
SIG.burrito_bouncer = move({
	name = "Bouncer's Combo",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.08, g({ lead = { p = 96, f = 0.34 }, body = { p = 14, y = 22 } }), "snap" },
		{ 0.15, "guard" },
		{ 0.23, g({ rear = { p = 98, f = 0.4, r = -16 }, body = { p = 16, y = -34 } }), "snap" },
		{ 0.32, g({ lead = { p = -12, u = -0.04 }, body = { p = 24, u = -0.08 }, root = { u = -0.03 }, legLead = { p = 30, r = 12 }, legRear = { p = -24, r = 12 } }) },
		{ 0.45, g({ lead = { p = 168, f = 0.18, u = 0.18 }, body = { p = -18, u = 0.06, y = 20 }, head = { p = -14 }, root = { u = 0.1 } }), "snap" },
		{ 0.62, g({ lead = { p = 172, u = 0.2 }, body = { p = -10 }, root = { u = 0.05 } }) },
		{ 0.9, "guard" },
	},
})

-- Scrapheap Titan: both arms high, wrench and crane claw slam down together.
SIG.scrapheap_titan = move({
	name = "Scrap Crusher",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.3, g({ lead = { p = 185, u = 0.1 }, rear = { p = 185, u = 0.1 }, body = { p = -18, u = 0.03 }, head = { p = -14 }, root = { u = 0.04 } }) },
		{ 0.36, g({ lead = { p = 192, u = 0.12 }, rear = { p = 192, u = 0.12 }, body = { p = -20, u = 0.04 } }) },
		{ 0.45, g({ lead = { p = 60, f = 0.28 }, rear = { p = 60, f = 0.28 }, body = { p = 34, u = -0.06, f = 0.08 }, head = { p = 14 }, legLead = { p = 26, r = 12 }, legRear = { p = -26, r = 12 } }), "snap" },
		{ 0.64, g({ lead = { p = 52, f = 0.2 }, rear = { p = 52, f = 0.2 }, body = { p = 28, u = -0.05 } }) },
		{ 0.95, "guard" },
	},
})

-- Tornado Twins: spin up into a whirl, arms flung out.
SIG.tornado_twins = move({
	name = "Twin Cyclone",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.15, g({ root = { y = -60 }, lead = { r = 80, p = 60 }, rear = { r = 80, p = 60 } }) },
		{ 0.45, g({ root = { y = 540, u = 0.1, f = 0.12 }, lead = { r = 100, p = 90 }, rear = { r = 100, p = 90 }, body = { r = 14 } }), "smooth" },
		{ 0.7, g({ root = { y = 720, u = 0, f = 0.06 } }), "out" },
		{ 0.85, g({ root = { y = 720 } }) },
	},
})

-- Sergeant Snail: ducks into the shell and fires itself forward.
SIG.sergeant_snail = move({
	name = "Shell Shock",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.3, g({ head = { p = 10, f = -0.25, u = -0.12 }, body = { p = 14, u = -0.04 }, root = { f = -0.12 } }) },
		{ 0.45, g({ head = { p = 20, f = -0.2, u = -0.1 }, body = { p = 10 }, root = { f = 0.3, u = 0.04 } }), "snap" },
		{ 0.62, g({ head = { p = -20, f = 0.04 }, root = { f = 0.12 } }) },
		{ 0.9, "guard" },
	},
})

-- Escalator Wraith: both claws rise and rake down across each other.
SIG.escalator_wraith = move({
	name = "Down Escalator",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.3, g({ lead = { p = 170, r = 50, u = 0.08 }, rear = { p = 170, r = 50, u = 0.08 }, body = { p = -16 }, head = { p = -16 }, root = { u = 0.06 } }) },
		{ 0.45, g({ lead = { p = 70, r = -45, f = 0.26 }, rear = { p = 70, r = -45, f = 0.26 }, body = { p = 30, f = 0.08 }, head = { p = 18 }, root = { u = 0.02, f = 0.08 } }), "snap" },
		{ 0.64, g({ lead = { p = 40, r = -60, f = 0.16 }, rear = { p = 40, r = -60, f = 0.16 }, body = { p = 22 } }) },
		{ 0.9, "guard" },
	},
})

-- Mecha Fridge: rocket punch, the arm fires out far and reels back in.
SIG.mecha_fridge = move({
	name = "Rocket Punch",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.3, g({ lead = { p = 85, f = -0.12, r = 10 }, body = { p = 6, y = -36 }, rear = { p = 60, r = -20 }, legRear = { p = -24 } }) },
		{ 0.38, g({ lead = { p = 92, f = -0.14 }, body = { p = 8, y = -40, r = 2 } }) },
		{ 0.45, g({ lead = { p = 92, f = 1.0, u = 0.04 }, body = { p = 16, y = 28 }, legLead = { p = 26 }, legRear = { p = -24 } }), "snap" },
		{ 0.6, g({ lead = { p = 92, f = 0.9 }, body = { p = 14, y = 24 } }) },
		{ 0.8, g({ lead = { p = 85, f = 0.1 } }) },
		{ 1.0, "guard" },
	},
})

-- Queen Parfait: a full royal spin with the wafer sword held out.
SIG.queen_parfait = move({
	name = "Royal Wafer Waltz",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.15, g({ root = { y = -60 }, lead = { p = 90, r = 60 }, body = { p = -6 } }) },
		{ 0.45, g({ root = { y = 300, f = 0.1 }, lead = { p = 92, r = 80, f = 0.1 }, rear = { p = 30, r = 70 }, body = { p = 8, r = -10 } }), "smooth" },
		{ 0.6, g({ root = { y = 360, f = 0.06 }, lead = { p = 80, r = 20 } }) },
		{ 0.9, g({ root = { y = 360 } }) },
	},
})

-- The Junk King: leaps and slams the plunger down with both hands.
SIG.the_junk_king = move({
	name = "Royal Flush",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.16, g({ body = { p = 20, u = -0.08 }, root = { u = -0.04 }, lead = { p = 40 }, rear = { p = 40 } }) },
		{ 0.32, g({ root = { u = 0.35, f = 0.06 }, lead = { p = 195, u = 0.1 }, rear = { p = 185, u = 0.1, r = -20 }, body = { p = -20 }, legLead = { p = 20 }, legRear = { p = -20 } }), "out" },
		{ 0.45, g({ root = { u = 0, f = 0.14 }, lead = { p = 60, f = 0.3 }, rear = { p = 60, f = 0.26, r = -24 }, body = { p = 36, u = -0.06, f = 0.06 }, head = { p = 14 } }), "inn" },
		{ 0.65, g({ root = { f = 0.1 }, lead = { p = 50, f = 0.2 }, body = { p = 24, u = -0.04 } }) },
		{ 0.95, "guard" },
	},
})

-- Stormlord Nimbus: raises the scepter high, crackles, brings the storm down.
SIG.stormlord_nimbus = move({
	name = "Scepter of Storms",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.25, g({ lead = { p = 180, u = 0.14 }, rear = { p = 120, r = 50 }, body = { p = -18, u = 0.04 }, head = { p = -20 }, root = { u = 0.08 } }) },
		{ 0.3, g({ lead = { p = 182, u = 0.15, r = 4 }, body = { p = -19, u = 0.05 }, root = { u = 0.09 } }) },
		{ 0.35, g({ lead = { p = 178, u = 0.14, r = -4 }, body = { p = -18, u = 0.04 }, root = { u = 0.08 } }) },
		{ 0.45, g({ lead = { p = 64, f = 0.34 }, rear = { p = 40, r = 40 }, body = { p = 34, f = 0.08 }, head = { p = 14 }, root = { u = 0 } }), "snap" },
		{ 0.66, g({ lead = { p = 54, f = 0.22 }, body = { p = 24 } }) },
		{ 0.95, "guard" },
	},
})

-- Big Momma Moose: lowers the antlers, charges, then tosses the target skyward.
SIG.big_momma_moose = move({
	name = "Antler Toss",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.22, g({ head = { p = 52 }, root = { f = -0.06, p = 6 }, frontLead = { p = -20 }, backLead = { p = 18 } }) },
		{ 0.38, g({ head = { p = 48, f = 0.05 }, root = { f = 0.2, p = 8 }, frontLead = { p = 34 }, backLead = { p = -30 } }) },
		{ 0.45, g({ head = { p = -38, u = 0.06 }, root = { f = 0.24, p = -12 }, frontLead = { p = 40 }, frontRear = { p = 20 } }), "snap" },
		{ 0.66, g({ head = { p = -20 }, root = { f = 0.12, p = -6 } }) },
		{ 0.95, "guard" },
	},
})

-- The Mannequin Duke: a fencing lunge with the cane, free hand flourished behind.
SIG.the_mannequin_duke = move({
	name = "Cane Riposte",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.18, g({ lead = { p = 120, r = 30, u = 0.04 }, rear = { p = 150, r = 40, u = 0.06 }, body = { p = -6, y = -30 }, head = { p = -12 } }) },
		{ 0.34, g({ lead = { p = 80, f = -0.06 }, rear = { p = 160, r = 60, u = 0.08 }, body = { p = 0, y = -40 }, legRear = { p = -20 } }) },
		{ 0.45, g({ lead = { p = 96, f = 0.6, u = 0.02 }, rear = { p = -30, r = 70, u = 0.1 }, body = { p = 22, y = 30, f = 0.12, u = -0.05 }, root = { f = 0.14 }, legLead = { p = 50, f = 0.1 }, legRear = { p = -40 }, head = { p = 6 } }), "snap" },
		{ 0.66, g({ lead = { p = 92, f = 0.45 }, body = { p = 18, y = 26, f = 0.1 }, root = { f = 0.1 }, legLead = { p = 44 }, legRear = { p = -34 } }) },
		{ 0.95, "guard" },
	},
})

-- Mega Blender Prime: claws out, spins up like a blade, three full turns.
SIG.mega_blender_prime = move({
	name = "Frappé Frenzy",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.12, g({ lead = { r = 85, p = 80 }, rear = { r = 85, p = 80 }, body = { p = -6 }, root = { y = -40 } }) },
		{ 0.45, g({ root = { y = 720, f = 0.14 }, lead = { r = 95, p = 90 }, rear = { r = 95, p = 90 }, body = { p = 6 } }), "inn" },
		{ 0.75, g({ root = { y = 1080, f = 0.08 }, lead = { r = 70, p = 80 }, rear = { r = 70, p = 80 } }), "out" },
		{ 0.95, g({ root = { y = 1080 } }) },
	},
})

-- Captain Confetti: a spinning wing buffet, then a spyglass bonk.
SIG.captain_confetti = move({
	name = "Shiver Me Sparkles",
	contact = 0.45,
	frames = {
		{ 0, "guard" },
		{ 0.25, g({ root = { y = 360, u = 0.2 }, wings = { r = 90 }, lead = { p = 0, r = 90 }, rear = { p = 0, r = 90 } }), "smooth" },
		{ 0.35, g({ root = { y = 360, u = 0.22 }, lead = { p = 180, r = 20 }, wings = { r = 70 }, body = { p = -14 } }) },
		{ 0.45, g({ root = { y = 360, u = 0.04, f = 0.1 }, lead = { p = 60, f = 0.26 }, wings = { r = 0, p = 50 }, body = { p = 30, f = 0.08 } }), "snap" },
		{ 0.65, g({ root = { y = 360, f = 0.06 }, wings = { r = 40 } }) },
		{ 0.95, g({ root = { y = 360 } }) },
	},
})

-- Omega Microwave: a blur of alternating punches, then a double uppercut.
do
	local frames = { { 0, "guard" } }
	for k = 0, 5 do
		local t = 0.03 + k * 0.05
		local arm = (k % 2 == 0) and "lead" or "rear"
		local other = (k % 2 == 0) and "rear" or "lead"
		local f = g({ body = { p = 16, y = (k % 2 == 0) and 24 or -24, f = 0.05 } })
		f[arm] = { p = 96, f = 0.4, r = -8 }
		f[other] = { p = 50, r = -10, f = -0.02 }
		table.insert(frames, { t, f, "snap" })
	end
	table.insert(frames, { 0.36, g({ lead = { p = -14, u = -0.04 }, rear = { p = -14, u = -0.04 }, body = { p = 24, u = -0.08 }, root = { u = -0.04 }, legLead = { p = 26, r = 14 }, legRear = { p = -22, r = 14 } }) })
	table.insert(frames, { 0.45, g({ lead = { p = 170, f = 0.16, u = 0.18 }, rear = { p = 170, f = 0.16, u = 0.18 }, body = { p = -18, u = 0.06, y = 0 }, head = { p = -16 }, root = { u = 0.16 } }), "snap" })
	table.insert(frames, { 0.66, g({ lead = { p = 176, u = 0.2 }, rear = { p = 176, u = 0.2 }, body = { p = -10 }, root = { u = 0.06 } }) })
	table.insert(frames, { 0.95, "guard" })
	SIG.omega_microwave = move({ name = "Omega Rush", contact = 0.45, frames = frames })
end

---------------------------------------------------------------------------
-- Sampling
---------------------------------------------------------------------------
-- Pose of move m at t seconds after it started.
function Moves.sample(m, t)
	local frames = m.frames
	if m.loop then
		t = t % m.dur
	end
	if t <= frames[1][1] then
		return frames[1][2]
	end
	for k = 2, #frames do
		local fr = frames[k]
		if t <= fr[1] then
			local prev = frames[k - 1]
			local a = (t - prev[1]) / math.max(fr[1] - prev[1], 1e-4)
			local ease = EASE[fr[3] or "smooth"] or sm
			return lerpPose(prev[2], fr[2], ease(a), false)
		end
	end
	return frames[#frames][2]
end

-- Looks a move up by name (shared moves first, then signatures by creature id).
function Moves.get(name)
	return M[name] or SIG[name]
end

---------------------------------------------------------------------------
-- Choosing moves for a creature (rig from Rig.luau)
---------------------------------------------------------------------------
-- k counts the creature's swings, so it mixes its moves up. sig = true for Epic+ finishers.
function Moves.pickAttack(rig, power, k, id, sig)
	if sig and SIG[id] then
		return id
	end
	local has = rig and rig.has or {}
	local kind = rig and rig.kind or "blob"
	k = k or 0
	local options
	if power == 1 then
		if has.weapon then
			options = { "thrust", "jab", "cross" }
		elseif has.arms then
			options = { "jab", "cross", "jab" }
		elseif kind == "quad" then
			options = { "charge", "bump" }
		elseif has.wings then
			options = { "wingSlap", "bump" }
		elseif has.head then
			options = { "headbutt", "bump" }
		else
			options = { "bump" }
		end
	elseif power == 2 then
		if has.weapon then
			options = { "overhead", "hook", "thrust" }
		elseif has.arms then
			options = { "hook", "uppercut" }
			if has.legs then
				table.insert(options, "kick")
			end
		elseif kind == "quad" then
			options = { "charge", "headbutt" }
		elseif has.legs then
			options = { "kick", "stomp" }
		elseif has.wings then
			options = { "wingSlap" }
		else
			options = { "headbutt" }
		end
		if has.tail then
			table.insert(options, "tailWhip")
		end
	else
		if has.weapon then
			options = { "overheadBig", "haymaker" }
		elseif has.arms then
			options = has.bothArms and { "haymaker", "doubleAxe" } or { "haymaker" }
			if has.legs then
				table.insert(options, "spinKick")
			end
		elseif kind == "quad" then
			options = { "rearStomp" }
		elseif has.legs then
			options = { "spinKick", "bodySlam" }
		else
			options = { "bodySlam" }
		end
	end
	return options[(k % #options) + 1]
end

function Moves.pickDodge(k)
	local options = { "duck", "sway", "sidestep" }
	return options[(k % #options) + 1]
end

-- Hit reaction for a hit of this power (blocked hits use "block").
function Moves.pickReaction(power, ko)
	if ko then
		return "launch"
	end
	return power >= 2 and "stagger" or "flinch"
end

return Moves

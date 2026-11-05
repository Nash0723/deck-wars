-- The Pack Brawl choreography: turns a cast (from Casting) into a timeline of cues.
-- Pure Lua, no Roblox instances, so it is tested headlessly. The Director plays the cues.
--
-- Ring space: x left/right, z toward (+) or away from (-) the camera's home side, y up.
-- The ring floor is 24 x 24 studs; the ropes stand at +-RING. Positions are { x = , z = }.
--
-- Cue = { t = seconds, k = kind, ... }. Kinds and their fields are listed in the README
-- section "Pack Brawl" and handled one by one in Director.luau.

local Scripts = {}

Scripts.RING = 10.5 -- ropes
Scripts.FIGHT = 8.6 -- fighters stay inside this while fighting
Scripts.PACK = { x = 0, z = -2.5 }
Scripts.Length = { Common = 4.0, Rare = 6.0, Epic = 8.0, Mythic = 10.0, Legendary = 12.5, Secret = 15.0 }
Scripts.FakeOutLength = 1.8 -- extra seconds when the fake ending plays

local RING, FIGHT = Scripts.RING, Scripts.FIGHT

local function v(x, z)
	return { x = x, z = z }
end
local function dist(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end
local function clampIn(p, lim)
	return v(math.clamp(p.x, -lim, lim), math.clamp(p.z, -lim, lim))
end

---------------------------------------------------------------------------
-- Builder
---------------------------------------------------------------------------
local B = {}
B.__index = B

local function newBuilder(cast)
	local self = setmetatable({}, B)
	self.cast = cast
	self.cues = {}
	self.pos = {} -- where each fighter is (or will be) after the cues so far
	self.state = {} -- nil (not in yet), "in", "out" (knocked out of the fight)
	self.shift = 0 -- added to every time (the fake ending pushes the rest later)
	self.rngState = (cast.seed or 1) % 2147483647
	if self.rngState <= 0 then
		self.rngState = 1
	end
	return self
end

-- Small deterministic random in [0, 1) so the builder needs no other modules.
function B:rand()
	self.rngState = (self.rngState * 48271) % 2147483647
	return self.rngState / 2147483647
end

function B:cue(t, k, fields)
	local c = fields or {}
	c.t = t + self.shift
	c.k = k
	table.insert(self.cues, c)
	return c
end

function B:enter(t, i, style, to, dur, extra)
	local f = extra or {}
	f.who, f.style, f.to, f.dur = i, style, to, dur
	self:cue(t, "enter", f)
	self.pos[i] = to
	self.state[i] = "in"
end

function B:move(t, i, to, dur, style)
	self:cue(t, "move", { who = i, to = to, dur = dur, style = style or "hop" })
	self.pos[i] = to
end

-- a hits b. power 1 = light, 2 = heavy, 3 = finisher. opts:
--   ko = "ropes" | "out" | "sky" (knocked out, flies there), dist = knockback studs,
--   word = comic burst text, dir = { x, z } push direction (default: away from a).
function B:hit(t, a, b, power, opts)
	opts = opts or {}
	local pa, pb = self.pos[a], self.pos[b]
	local dx, dz = pb.x - pa.x, pb.z - pa.z
	if opts.dir then
		dx, dz = opts.dir.x, opts.dir.z
	end
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.01 then
		dx, dz, len = (self:rand() - 0.5), 1, 1
		len = math.sqrt(dx * dx + 1)
	end
	dx, dz = dx / len, dz / len
	local to, dur
	if opts.ko == "ropes" then
		-- slide out to the ropes in that direction
		local s = math.huge
		if math.abs(dx) > 0.01 then
			s = math.min(s, (RING - 0.9 - pb.x * math.sign(dx)) / math.abs(dx))
		end
		if math.abs(dz) > 0.01 then
			s = math.min(s, (RING - 0.9 - pb.z * math.sign(dz)) / math.abs(dz))
		end
		s = math.max(s, 1.5)
		to = clampIn(v(pb.x + dx * s, pb.z + dz * s), RING - 0.9)
		dur = 0.45
	elseif opts.ko == "out" then
		to = v(pb.x + dx * 22, pb.z + dz * 22)
		dur = 0.7
	elseif opts.ko == "sky" then
		to = v(pb.x + dx * 6, pb.z + dz * 6)
		dur = 1.1
	elseif opts.blocked then
		-- guard up: barely pushed back
		to = clampIn(v(pb.x + dx * 0.25, pb.z + dz * 0.25), FIGHT)
		dur = 0.15
	else
		local d = opts.dist or ({ 0.7, 1.8, 3.2 })[power] or 1
		to = clampIn(v(pb.x + dx * d, pb.z + dz * d), FIGHT)
		dur = 0.12 + 0.08 * power
	end
	-- the attacker darts in; the hit lands 0.12 s later
	if not opts.noLunge then
		self:cue(t, "lunge", { who = a, target = b, dur = 0.24 })
	end
	self:cue(t + (opts.noLunge and 0 or 0.12), "hit", {
		who = b,
		by = a,
		power = power,
		to = to,
		dur = dur,
		ko = opts.ko,
		word = opts.word,
		blocked = opts.blocked,
		-- only creatures sent flying out of the ring tumble; everyone else reels and falls
		spin = opts.ko == "out" or opts.ko == "sky",
	})
	self.pos[b] = to
	if opts.ko then
		self.state[b] = "out"
	end
end

-- a swings at b and misses: b ducks, sways or sidesteps.
function B:whiff(t, a, b)
	self:cue(t, "lunge", { who = a, target = b, dur = 0.24 })
	self:cue(t + 0.02, "dodge", { who = b, by = a, contact = t + 0.12 + self.shift, power = 1 })
end

-- n alternating light hits between a and b, starting at t, gap seconds apart.
-- After the first punch, some get blocked and some dodged, so it reads as a real fight.
function B:exchange(t, a, b, n, gap, power)
	for k = 0, n - 1 do
		local x, y = a, b
		if k % 2 == 1 then
			x, y = b, a
		end
		local r = self:rand()
		if k > 0 and r < 0.22 then
			self:hit(t + k * gap, x, y, power or 1, { dist = 0.5, blocked = true })
		elseif k > 0 and r < 0.38 then
			self:whiff(t + k * gap, x, y)
		else
			self:hit(t + k * gap, x, y, power or 1, { dist = 0.5 })
		end
	end
	return t + n * gap
end

function B:alive(exceptWinner)
	local out = {}
	for i = 1, #self.cast.fighters do
		if self.state[i] == "in" and not (exceptWinner and i == self.cast.winner) then
			table.insert(out, i)
		end
	end
	return out
end

function B:cam(t, shot, fields)
	local f = fields or {}
	f.shot = shot
	return self:cue(t, "cam", f)
end

-- Opening: pack lands, rips, two starters tumble out.
function B:opening()
	self:cue(0, "pack", { at = Scripts.PACK })
	self:cue(0, "hype", { tier = "Common" })
	self:cam(0, "wide", { yaw = 18, dist = 19, height = 7, fov = 50, drift = 3, blend = 0 })
	self:cue(0.3, "sfx", { name = "rip" })
	self:enter(0.35, 1, "tumble", v(-2.6, 0.2), 0.45)
	self:enter(0.38, 2, "tumble", v(2.6, -0.2), 0.45)
	self:cue(0.85, "music", { name = "brawl" })
end

-- A crasher arrives with its tier's flare.
local CRASH_WORDS = { "WHAM!", "KRAK!", "FWOOSH!", "BAM!", "KA-CHUNK!", "ZAP!", "THOOM!" }
function B:crash(t, i, style, to, opts)
	opts = opts or {}
	local tier = self.cast.fighters[i].tier
	local dur = ({ cannonball = 0.32, burrow = 0.3, drop = 0.18, skid = 0.3 })[style] or 0.3
	self:enter(t, i, style, to, dur, { from = opts.from })
	self:cue(t + dur, "hype", { tier = tier })
	self:cue(t + dur, "shock", { at = to, tier = tier, size = 10 })
	self:cue(t + dur, "word", { who = i, text = CRASH_WORDS[(i % #CRASH_WORDS) + 1] })
	self:cue(t + dur, "sfx", { name = style == "burrow" and "burrow" or "land" })
	if style == "cannonball" then
		self:cue(t, "sfx", { name = "twang" })
	end
	return t + dur
end

-- The pulled card's victory pose, then the reveal.
function B:finish(t, length, full, orbit)
	local w = self.cast.winner
	local wf = self.cast.fighters[w]
	self:cue(t, "pose", { who = w, full = full, tier = self.cast.tier, losers = self:losers() })
	self:cue(t, "sting", { tier = self.cast.tier })
	if orbit then
		self:cam(t, "orbit", { who = w, from = 20, to = 20 + orbit, dur = length - t - 0.4, dist = 10, height = 3.5, fov = 42, blend = 0.35 })
	else
		self:cam(t, "focus", { who = w, yaw = 20, dist = 9, height = 3, fov = 42, blend = 0.3, drift = 4 })
	end
	self:cam(length - 0.4, "push", { who = w, fov = 30, dur = 0.4 })
	self:cue(length - 0.25, "wipe", { tier = self.cast.tier })
	self:cue(length, "finish", { winner = w, id = wf.id })
end

function B:losers()
	local out = {}
	for i = 1, #self.cast.fighters do
		if i ~= self.cast.winner and self.state[i] ~= nil then
			table.insert(out, i)
		end
	end
	return out
end

-- The winner enters in its own way. Buildings always fall from the sky; spells fly in as a card.
function B:winnerEntrance(t, style, to, dur)
	local w = self.cast.winner
	local kind = self.cast.fighters[w].kind
	if kind == "building" then
		style, dur = "drop", 0.2
	elseif kind == "spell" then
		style, dur = "spellcard", 0.35
	end
	self:enter(t, w, style, to, dur, { winner = true })
	self:cue(t + dur, "hype", { tier = self.cast.tier })
	return t + dur
end

-- "It's Not Over": fighter i fake-wins, the card frame starts sliding in, then it cracks.
-- Returns the extra time added (the caller shifts the rest of the script).
function B:fakeOut(t, i)
	for _, j in ipairs(self:alive(true)) do
		if j ~= i then
			self:hit(t, i, j, 3, { ko = "ropes", word = "POW!" })
			t += 0.25
		end
	end
	self:move(t + 0.2, i, v(0, 1), 0.3, "hop")
	self:cue(t + 0.55, "fakepose", { who = i })
	self:cam(t + 0.55, "focus", { who = i, yaw = 15, dist = 8, height = 2.8, fov = 40, blend = 0.4 })
	self:cue(t + 0.55, "sfx", { name = "fakesting" })
	self:cue(t + 1.0, "fakeframe", {})
	self:cue(t + 1.55, "fakecrack", {})
	self:cue(t + 1.55, "sfx", { name = "glass" })
	return 1.8
end

---------------------------------------------------------------------------
-- Tiers
---------------------------------------------------------------------------
local tierScripts = {}

function tierScripts.Common(b)
	local W = b.cast.winner
	b:opening()
	b:exchange(0.8, 1, 2, 4, 0.26)
	b:cam(1.9, "push", { at = Scripts.PACK, fov = 42, dur = 0.5 })
	b:cue(2.15, "sfx", { name = "pop" })
	b:winnerEntrance(2.2, "pop", v(0, -0.6), 0.25)
	b:hit(2.45, W, 1, 2, { ko = "ropes", word = "BONK!" })
	b:hit(2.7, W, 2, 2, { ko = "ropes", word = "BONK!" })
	b:finish(3.0, 4.0, false)
end

function tierScripts.Rare(b)
	local W, C = b.cast.winner, 3
	b:opening()
	b:exchange(0.8, 1, 2, 4, 0.25)
	b:cam(1.75, "focus", { at = v(-6, 0), yaw = -10, dist = 13, height = 5, fov = 48, dutch = 4, blend = 0.2 })
	local land = b:crash(1.8, C, "cannonball", v(0, 0.6), { from = v(-RING - 6, 2) })
	b:hit(land, C, 2, 3, { ko = "out", word = "WHAM!", noLunge = true })
	b:cam(land + 0.1, "wide", { yaw = 12, dist = 17, height = 6, fov = 50, blend = 0.35, drift = 4 })
	b:move(2.55, C, v(0.6, 0.4), 0.2, "dash")
	b:move(2.55, 1, v(-0.6, 0.2), 0.2, "dash")
	b:cue(2.75, "shove", { a = C, b = 1, dur = 0.6 })
	b:cue(3.25, "sfx", { name = "whoosh" })
	b:winnerEntrance(3.3, "skid", v(2.4, 1.6), 0.3)
	b:cue(3.55, "spin", { who = W, dur = 0.35, turns = 1 })
	b:hit(3.6, W, C, 3, { ko = "ropes", word = "SMACK!", noLunge = true, dir = v(1, -0.4) })
	b:hit(3.6, W, 1, 3, { ko = "ropes", noLunge = true, dir = v(-1, -0.2) })
	b:cue(3.62, "hitstop", { dur = 0.06 })
	b:finish(4.4, 6.0, true)
end

function tierScripts.Epic(b)
	local W, C = b.cast.winner, 3
	b:opening()
	b:exchange(0.75, 1, 2, 3, 0.26)
	local land = b:crash(1.55, C, "cannonball", v(0, -1.5), { from = v(RING + 6, -4) })
	b:cam(land, "wide", { yaw = -25, dist = 16, height = 6, fov = 55, dutch = -8, blend = 0.25, drift = -5 })
	-- exchange 1: the slam
	b:hit(2.2, C, 1, 3, { word = "SLAM!", dist = 3 })
	b:cue(2.35, "arena", { what = "tiles", at = b.pos[1] })
	b:cue(2.34, "hitstop", { dur = 0.08 })
	b:cam(2.6, "focus", { who = 2, yaw = 30, dist = 10, height = 3.5, fov = 50, dutch = 8, blend = 0.2 })
	-- exchange 2: the double clothesline
	b:hit(2.7, 2, C, 1)
	b:hit(2.95, C, 2, 2, { word = "THWACK!" })
	b:hit(3.2, 1, C, 2)
	b:cue(3.32, "hitstop", { dur = 0.08 })
	-- exchange 3: the pile-up
	b:cam(3.6, "wide", { yaw = 5, dist = 14, height = 8, fov = 52, dutch = -8, blend = 0.3 })
	for _, i in ipairs({ 1, 2, C }) do
		b:move(3.7, i, v((i - 2) * 0.9, -0.5), 0.3, "dash")
	end
	b:cue(4.0, "clash", { who = { 1, 2, C }, at = v(0, -0.5) })
	b:hit(4.02, 1, 2, 2, { noLunge = true, dist = 3 })
	b:hit(4.02, 2, C, 2, { noLunge = true, dist = 3, dir = v(1, -0.6) })
	b:hit(4.02, C, 1, 2, { noLunge = true, dist = 3, dir = v(-1, 0.5) })
	b:cue(4.04, "hitstop", { dur = 0.08 })
	-- the drop
	b:cue(4.6, "marker", { at = v(0, 0), tier = "Epic", dur = 0.4 })
	b:cue(4.55, "sfx", { name = "whistle" })
	b:cam(4.6, "crane", { at = v(0, 0), fov = 75, dist = 15, height = 4, lookUp = 12, blend = 0.3 })
	b:winnerEntrance(4.85, "drop", v(0, 0), 0.15)
	b:cue(5.0, "shock", { at = v(0, 0), tier = "Epic", size = 26 })
	b:cue(5.0, "sfx", { name = "crater" })
	b:cue(5.0, "arena", { what = "crater", at = v(0, 0) })
	b:cam(5.0, "wide", { yaw = 15, dist = 13, height = 5, fov = 45, dutch = 8, blend = 0 })
	for _, i in ipairs({ 1, 2, C }) do
		b:hit(5.0, W, i, 3, { ko = "ropes", noLunge = true })
	end
	b:cue(5.02, "slowmo", { scale = 0.25, dur = 0.3 })
	b:finish(5.8, 8.0, true, 70)
end

-- A brawl ball: everyone still in tumbles together across the ring, with big hits.
local function brawlBall(b, t0, t1, hitTimes, flashTier)
	local who = b:alive(true)
	b:cue(t0, "brawlball", { who = who, from = v(-4, 0), to = v(4, -1), dur = t1 - t0 })
	for k, ht in ipairs(hitTimes) do
		b:cue(ht, "flash", { tier = flashTier, dur = 0.08 })
		b:cue(ht, "lines", {})
		b:cue(ht, "shake", { amount = 0.6 })
		b:cue(ht, "sfx", { name = "heavy" })
		b:cue(ht, "word", { at = v(-4 + 8 * (ht - t0) / (t1 - t0), -0.5), text = ({ "KRAK!", "POW!", "WHAM!", "BOOM!" })[(k - 1) % 4 + 1] })
	end
	for _, i in ipairs(who) do
		b.pos[i] = v(4 + (b:rand() - 0.5) * 3, -1 + (b:rand() - 0.5) * 3)
	end
	b:cue(t1, "brawlballend", { who = who, to = (function()
		local out = {}
		for _, i in ipairs(who) do
			out[i] = b.pos[i]
		end
		return out
	end)() })
end

function tierScripts.Mythic(b)
	local W = b.cast.winner
	local n = #b.cast.fighters
	local E, M = n - 2, n - 1 -- the Epic and Mythic crashers
	b:opening()
	b:exchange(0.65, 1, 2, 3, 0.24)
	-- Rare crasher
	local R = 3
	local land = b:crash(1.4, R, "cannonball", v(0, 2), { from = v(-RING - 6, 3) })
	b:hit(land + 0.12, R, 1, 2)
	b:hit(land + 0.4, 2, R, 1)
	if b.cast.fakeOut then
		local extra = b:fakeOut(2.1, R)
		b.shift += extra
		b.punted = R
	end
	-- Epic crasher: five-way scramble, two get thrown into the corner posts
	land = b:crash(2.4, E, "cannonball", v(4, -2), { from = v(RING + 6, -3) })
	b:cam(land, "wide", { yaw = -20, dist = 16, height = 7, fov = 55, dutch = -12, blend = 0.2, drift = 6 })
	if b.punted then
		b:hit(land, E, b.punted, 3, { ko = "out", word = "IT'S NOT OVER!", noLunge = true })
		b.punted = nil
	end
	local alive = b:alive(true)
	local thrown = 0
	for _, j in ipairs(alive) do
		if j ~= E and thrown < 2 then
			thrown += 1
			b:hit(land + 0.2 + thrown * 0.3, E, j, 2, { dist = 3.5, word = thrown == 1 and "CRUNCH!" or nil })
			b:cue(land + 0.4 + thrown * 0.3, "arena", { what = "post", index = thrown })
		end
	end
	-- Mythic crasher bursts up through the floor
	land = b:crash(3.6, M, "burrow", v(-3, -3), {})
	b:cue(land, "arena", { what = "banner" })
	b:cue(land, "arena", { what = "tiles", at = v(-3, -3) })
	b:cam(land, "focus", { who = M, yaw = -30, dist = 10, height = 3, fov = 50, dutch = 10, blend = 0.15 })
	-- beam clash between the Epic and Mythic crashers
	b:move(4.2, E, v(6.5, -5.5), 0.25, "dash")
	b:move(4.2, M, v(-6.5, -5.5), 0.25, "dash")
	b:cue(4.5, "beam", { a = M, b = E, at = v(0, -5.5), dur = 2.5 })
	b:cue(4.5, "sfx", { name = "beam" })
	b:cam(4.5, "wide", { yaw = 0, dist = 15, height = 5, fov = 55, dutch = 12, blend = 0.3, drift = 3, look = v(0, -4) })
	for _, j in ipairs(b:alive(true)) do
		if j ~= E and j ~= M then
			b:move(4.8, j, v(b.pos[j].x * 0.5, -3.5 + (b:rand() - 0.5)), 1.2, "drag")
		end
	end
	-- time stop
	b:cue(6.0, "timestop", {})
	b:cue(6.0, "sfx", { name = "tick" })
	b:cam(6.0, "orbit", { at = v(0, -4), from = 0, to = 90, dur = 1.0, dist = 12, height = 4, fov = 40, blend = 0.15 })
	b:winnerEntrance(6.05, "walk", v(0.4, -4.4), 0.6)
	b:cue(6.75, "flick", { who = W, at = v(0, -5.5) })
	b:move(6.8, W, v(0, -1.5), 0.25, "walk")
	b:cue(7.0, "timeresume", {})
	b:cue(7.0, "detonate", { at = v(0, -5.5), tier = "Mythic" })
	b:cue(7.0, "flash", { tier = "Mythic", dur = 0.12 })
	b:cue(7.0, "sfx", { name = "boom" })
	b:cam(7.0, "wide", { yaw = 0, dist = 18, height = 8, fov = 58, dutch = -6, blend = 0 })
	for _, j in ipairs(b:alive(true)) do
		local p = b.pos[j]
		b:hit(7.0, W, j, 3, { ko = "out", noLunge = true, dir = v(p.x - 0, p.z + 5.5) })
	end
	b:cue(7.05, "shake", { amount = 1 })
	b:finish(7.6, 10.0 + (b.cast.fakeOut and 0 or 0), true, 90)
end

function tierScripts.Legendary(b)
	local W = b.cast.winner
	local n = #b.cast.fighters
	b:opening()
	b:exchange(0.6, 1, 2, 2, 0.24)
	local t = 1.2
	local styles = { "cannonball", "burrow", "cannonball", "drop", "burrow" }
	local spots = { v(-4, 2), v(4, -2.5), v(-5, -3), v(5, 2), v(0, -4) }
	for i = 3, n - 1 do
		local k = i - 2
		local spot = spots[k]
		local from = styles[k] == "cannonball" and v(spot.x > 0 and RING + 6 or -RING - 6, spot.z) or nil
		local land = b:crash(t, i, styles[k], spot, { from = from })
		if b.punted then
			b:hit(land, i, b.punted, 3, { ko = "out", word = "IT'S NOT OVER!", noLunge = true })
			b.punted = nil
		end
		b:cam(land, "focus", { who = i, yaw = (k % 2 == 0) and 28 or -28, dist = 11, height = 4, fov = 56, dutch = (k % 2 == 0) and 15 or -15, blend = 0.15 })
		t = land + 0.25
		if k == 1 and b.cast.fakeOut then
			b:hit(land + 0.1, i, 1, 2)
			local extra = b:fakeOut(t, i)
			b.shift += extra
			b.punted = i
		end
	end
	-- battle royale
	b:cam(3.6, "wide", { yaw = 0, dist = 18, height = 8, fov = 60, dutch = 0, blend = 0.3, drift = 8 })
	brawlBall(b, 3.6, 5.0, { 3.9, 4.35, 4.8 }, "Legendary")
	local M = n - 1
	b:cue(5.1, "tornado", { who = M, others = b:alive(true), dur = 1.3 })
	b:cue(5.1, "sfx", { name = "wind" })
	b:cam(5.1, "orbit", { at = v(0, 0), from = 0, to = 60, dur = 1.4, dist = 16, height = 6, fov = 60, dutch = 15, blend = 0.3 })
	b:cue(5.6, "flash", { tier = "Legendary", dur = 0.06 })
	-- everyone stops; a golden card descends
	local ring = b:alive(true)
	for k, j in ipairs(ring) do
		local a = math.rad(200 + (k - 1) * (140 / math.max(#ring - 1, 1)))
		b:move(6.45, j, v(math.cos(a) * 5.5, -math.sin(a) * 5.5 - 1), 0.2, "hop")
	end
	b:cue(6.6, "bigcard", { at = v(0, 1), dur = 0.6, tier = "Legendary" })
	b:cue(6.6, "sfx", { name = "choir" })
	b:cam(6.6, "crane", { at = v(0, 1), fov = 60, dist = 14, height = 2, lookUp = 14, blend = 0.4 })
	b:winnerEntrance(7.2, "stepout", v(0, 1), 0.3)
	b:cam(7.2, "focus", { who = W, yaw = 0, dist = 12, height = 4, fov = 55, blend = 0.3 })
	for _, j in ipairs(ring) do
		b:move(7.25, j, v(b.pos[j].x * 0.55, b.pos[j].z * 0.55 + 0.4), 0.3, "dash")
	end
	-- the ultimate
	b:cue(7.6, "ultimate", { who = W, dur = 1.6, targets = ring })
	b:cue(7.6, "sfx", { name = "charge" })
	b:cam(7.6, "wide", { yaw = -15, dist = 17, height = 6, fov = 62, dutch = -15, blend = 0.2, drift = -6 })
	for k, j in ipairs(ring) do
		b:hit(7.95 + (k - 1) * 0.11, W, j, 3, { ko = "sky", noLunge = true })
	end
	for k, ft in ipairs({ 7.95, 8.3, 8.65 }) do
		b:cue(ft, "flash", { tier = "Legendary", dur = 0.07 })
		b:cue(ft, "lines", {})
		b:cue(ft, "shake", { amount = 0.8 })
		b:cue(ft, "dutchflip", {})
	end
	b:cue(8.9, "stars", { who = ring })
	b:finish(9.4, 12.5, true, 360)
end

function tierScripts.Secret(b)
	local W = b.cast.winner
	local n = #b.cast.fighters
	b:opening()
	b:exchange(0.55, 1, 2, 2, 0.2)
	local t = 1.0
	local styles = { "cannonball", "burrow", "drop", "cannonball", "drop" }
	local spots = { v(-4, 2), v(4, -2.5), v(-5, -3), v(5, 2), v(0, -4) }
	for i = 3, n - 1 do
		local k = i - 2
		local spot = spots[k]
		local from = styles[k] == "cannonball" and v(spot.x > 0 and RING + 6 or -RING - 6, spot.z) or nil
		local land = b:crash(t, i, styles[k], spot, { from = from })
		if b.punted then
			b:hit(land, i, b.punted, 3, { ko = "out", word = "IT'S NOT OVER!", noLunge = true })
			b.punted = nil
		end
		if k % 2 == 1 then
			b:cam(land, "focus", { who = i, yaw = -25, dist = 11, height = 4, fov = 58, dutch = -15, blend = 0.15 })
		end
		t = land + 0.2
		if k == 1 and b.cast.fakeOut then
			b:hit(land + 0.1, i, 1, 2)
			local extra = b:fakeOut(t, i)
			b.shift += extra
			b.punted = i
		end
	end
	b:cam(3.2, "wide", { yaw = 0, dist = 18, height = 8, fov = 60, drift = 10, blend = 0.3 })
	brawlBall(b, 3.2, 5.3, { 3.5, 4.0, 4.5, 5.0 }, "Legendary")
	-- the two Legendaries square up and start their ultimates at the same moment
	local L1, L2 = n - 2, n - 1
	b:move(5.4, L1, v(-5, 0), 0.25, "dash")
	b:move(5.4, L2, v(5, 0), 0.25, "dash")
	b:cue(5.6, "charge", { who = L1, dur = 0.4 })
	b:cue(5.6, "charge", { who = L2, dur = 0.4 })
	b:cue(5.6, "sfx", { name = "charge" })
	b:cam(5.6, "wide", { yaw = 0, dist = 13, height = 3, fov = 50, dutch = 10, blend = 0.2 })
	-- reality breaks
	b:cue(6.0, "crack", { dur = 0.8 })
	b:cue(6.0, "sfx", { name = "glass" })
	b:cue(6.0, "musicstop", {})
	b:cue(6.3, "shear", {})
	b:cue(6.8, "blackout", { dur = 1.4 })
	b:cue(7.3, "sfx", { name = "heartbeat" })
	b:cue(7.7, "sfx", { name = "heartbeat" })
	b:cue(7.8, "eyes", { dur = 0.4 })
	-- behind the black: the winner arrives, everyone else is launched
	b:winnerEntrance(8.0, "appear", v(0, 0), 0.05)
	local others = b:alive(true)
	b:cue(8.15, "unshear", {})
	b:cue(8.2, "whiteflash", { dur = 0.8 })
	b:cue(8.2, "theme", {})
	for k, j in ipairs(others) do
		b:hit(8.2, W, j, 3, { ko = "sky", noLunge = true, dir = v(math.cos(k * 1.3), math.sin(k * 1.3)) })
	end
	b:cue(8.5, "freeze", { index = 1, who = W })
	b:cue(8.85, "freeze", { index = 2, who = W })
	b:cue(9.2, "freeze", { index = 3, who = W })
	b:cue(9.55, "unfreeze", {})
	-- the arena comes back with the winner standing on the pile
	b:cue(10.0, "reassemble", { who = W, pile = others })
	for k, j in ipairs(others) do
		b.pos[j] = v(math.cos(k * 2.1) * 1.2, math.sin(k * 2.1) * 1.2)
	end
	b:cue(10.0, "hype", { tier = "Secret" })
	b:finish(10.4, 15.0, true, 360)
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- Returns { tier, length, cues (sorted by time), fighters = cast.fighters, winner }.
function Scripts.build(cast)
	local b = newBuilder(cast)
	local fn = assert(tierScripts[cast.tier], "no script for tier " .. tostring(cast.tier))
	fn(b)
	Scripts.addSwings(b.cues, cast)
	local length = 0
	for _, c in ipairs(b.cues) do
		if c.k == "finish" then
			length = c.t
		end
	end
	-- stable sort by time (cues added at the same time keep their order)
	for i, c in ipairs(b.cues) do
		c.order = i
	end
	table.sort(b.cues, function(x, y)
		if x.t == y.t then
			return x.order < y.order
		end
		return x.t < y.t
	end)
	Scripts.addEnv(b.cues, cast)
	return { tier = cast.tier, length = length, cues = b.cues, fighters = cast.fighters, winner = cast.winner, fakeOut = cast.fakeOut }
end

-- The world's escalation (biome pulls): "env" cues that raise the world level 0..5 as the fight
-- climbs. Levels: 0 Calm, 1 Stir, 2 Quake, 3 Awaken, 4 Sky Break, 5 World Turn (Secret only).
-- The world only climbs on beats the fight already has, one level per beat, and never above the
-- level of the rarest crasher seen so far, so the world gives away nothing the fight hasn't.
-- Legendary's level 4 opens with its tornado or golden card, Secret's level 5 with the crack.
-- By the winner's entrance the world has reached the pulled tier's level (missing levels cascade).
-- Fake endings calm the world (calm = true) and the crack slams it back (slam = true).
-- Big hits at the top level send a pulse (pulse = cue kind) for landmark strikes.
-- cues must be sorted by time; the env cues are merged in, still sorted.
Scripts.EnvBeats = { hype = true, arena = true, beam = true, brawlball = true, tornado = true, bigcard = true, crack = true }
Scripts.EnvPulses = { detonate = true, ultimate = true, bigcard = true }
Scripts.EnvCascadeGap = 0.15
local ENV_RANK = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }
function Scripts.addEnv(cues, cast)
	local target = math.min((ENV_RANK[cast.tier] or 1) - 1, 5)
	local level, allowed = 0, 0
	local env = {}
	local function emit(t, fields)
		fields.t = t
		fields.k = "env"
		fields.level = level
		table.insert(env, fields)
	end
	local winnerIn = nil
	for _, c in ipairs(cues) do
		if c.k == "enter" and c.who == cast.winner and not winnerIn then
			winnerIn = c.t
		end
	end
	local cascaded = false
	for _, c in ipairs(cues) do
		-- before the winner's entrance lands, catch up any level the timeline had no beat for
		if not cascaded and winnerIn and c.t >= winnerIn then
			cascaded = true
			local cap = math.min(target, 4)
			local k = 0
			while level < cap do
				level += 1
				emit(winnerIn + k * Scripts.EnvCascadeGap, { cascade = true })
				k += 1
			end
			allowed = math.max(allowed, level)
		end
		if c.k == "hype" and ENV_RANK[c.tier] then
			allowed = math.max(allowed, math.min(ENV_RANK[c.tier] - 1, 4))
		elseif (c.k == "tornado" or c.k == "bigcard") and target >= 4 then
			allowed = math.max(allowed, 4)
		elseif c.k == "crack" and target >= 5 then
			allowed = 5
		end
		if Scripts.EnvBeats[c.k] and level < allowed then
			level += 1
			emit(c.t, {})
		elseif Scripts.EnvPulses[c.k] and level >= 3 then
			emit(c.t, { pulse = c.k })
		end
		if c.k == "fakepose" then
			emit(c.t, { calm = true })
		elseif c.k == "fakecrack" then
			emit(c.t, { slam = true })
		end
	end
	-- (a timeline with no winner entrance never happens, but never end below the tier either)
	while level < math.min(target, 4) do
		level += 1
		emit(cues[#cues].t, { cascade = true })
	end
	if #env == 0 then
		return
	end
	for i, c in ipairs(cues) do
		c.order = i
	end
	local n = #cues
	for i, e in ipairs(env) do
		e.order = n + i
		table.insert(cues, e)
	end
	table.sort(cues, function(x, y)
		if x.t == y.t then
			return x.order < y.order
		end
		return x.t < y.t
	end)
end

-- Swings: every hit (and every dodged punch) gets a "swing" cue for the attacker, started early
-- enough that the punch, kick or headbutt lands exactly on the hit. Epic and better creatures
-- use their signature move for their big (power 3) hits, which winds up longer.
local RANK = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }
Scripts.Contact = { 0.12, 0.2, 0.3 }
Scripts.SignatureContact = 0.45

function Scripts.addSwings(cues, cast)
	local enters = {}
	for _, c in ipairs(cues) do
		if c.k == "enter" then
			enters[c.who] = c
		end
	end
	local want = {}
	for _, c in ipairs(cues) do
		if (c.k == "hit" or c.k == "dodge") and c.by then
			local f = cast.fighters[c.by]
			local power = c.power or 1
			local sig = power >= 3 and f and f.kind == "creature" and (RANK[f.tier] or 1) >= RANK.Epic
			local contactT = c.k == "dodge" and c.contact or c.t
			local lead = sig and Scripts.SignatureContact or Scripts.Contact[power] or 0.2
			table.insert(want, { who = c.by, target = c.who, power = power, sig = sig or nil, contact = contactT, t = contactT - lead, blocked = c.blocked, dodged = c.k == "dodge" or nil })
		end
	end
	table.sort(want, function(x, y)
		if x.contact == y.contact then
			return x.who < y.who
		end
		return x.contact < y.contact
	end)
	local lastContact = {}
	for _, w in ipairs(want) do
		local prev = lastContact[w.who]
		-- one swing per blow: a sweep that hits several fighters at once is one move
		if not prev or w.t > prev + 0.02 then
			local e = enters[w.who]
			if e and w.t < e.t + (e.dur or 0) then
				-- still flying in: crash in fists first
				w.dive = true
				w.t = math.max(w.t, e.t)
			end
			w.t = math.max(w.t, 0)
			lastContact[w.who] = w.contact
			table.insert(cues, { t = w.t, k = "swing", who = w.who, target = w.target, power = w.power, sig = w.sig, contact = w.contact, dive = w.dive, blocked = w.blocked, dodged = w.dodged })
		end
	end
end

-- Where to jump when the player skips: the reveal, except Secret jumps to the blinding flash
-- (if that is still ahead), so nobody misses the moment entirely.
function Scripts.skipTarget(script, now)
	if script.tier == "Secret" then
		for _, c in ipairs(script.cues) do
			if c.k == "whiteflash" and c.t > now + 0.05 then
				return c.t - 0.02, false
			end
		end
	end
	return script.length, true
end

return Scripts

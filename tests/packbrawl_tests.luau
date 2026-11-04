-- Headless tests for the Pack Brawl pull cinematic (rates, casting, choreography).
-- Run with: luaurun tests/packbrawl_tests.luau src/packbrawl src/shared
local CardData = require("CardData")
local PullRates = require("PullRates")
local Casting = require("Casting")
local Scripts = require("Scripts")
local Rng = require("Rng")
local Rig = require("Rig")
local Moves = require("Moves")
local ModelData = require("CreatureModelData")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. msg)
	end
end

-- Rarity names
check(table.concat(CardData.Rarities, ",") == "Common,Rare,Epic,Mythic,Legendary,Secret", "tiers are Common..Secret low to high")
for id, def in pairs(CardData.Cards) do
	check(PullRates.Rank[def.rarity] ~= nil, id .. " has a known tier (" .. tostring(def.rarity) .. ")")
	check(CardData.RarityColors[def.rarity] ~= nil, id .. " tier has a color")
end

-- Odds
local sum = 0
for _, t in ipairs(PullRates.Tiers) do
	sum += PullRates.Odds[t]
	check(#PullRates.Pool[t] > 0, "pool for " .. t .. " is not empty")
end
check(math.abs(sum - 100) < 1e-9, "odds add up to 100 (" .. sum .. ")")

do
	local rng = Rng.new(42)
	local rand = function()
		return rng:next()
	end
	local counts = {}
	local N = 200000
	for _ = 1, N do
		local t = PullRates.rollTier(rand)
		counts[t] = (counts[t] or 0) + 1
	end
	for _, t in ipairs(PullRates.Tiers) do
		local got = 100 * (counts[t] or 0) / N
		check(math.abs(got - PullRates.Odds[t]) < math.max(0.15 * PullRates.Odds[t], 0.08), string.format("%s rolls about %.1f%% (got %.2f%%)", t, PullRates.Odds[t], got))
	end
	-- 10-pulls always hold an Epic or better
	local floorRank = PullRates.Rank[PullRates.TenPullFloor]
	local okAll = true
	for _ = 1, 3000 do
		local r = PullRates.roll(10, rand)
		local best = 0
		for _, id in ipairs(r.cards) do
			best = math.max(best, PullRates.Rank[CardData.Cards[id].rarity])
		end
		if best < floorRank or PullRates.Rank[CardData.Cards[r.cards[r.best]].rarity] ~= best or #r.cards ~= 10 then
			okAll = false
		end
	end
	check(okAll, "every 10-pull has an Epic or better and best points at the rarest card")
	local forced = PullRates.roll(1, rand, "Secret")
	check(CardData.Cards[forced.cards[1]].rarity == "Secret", "forced tier works")
end

-- Casting + scripts for every pullable card and many seeds
local KNOWN = {
	pack = true, hype = true, cam = true, sfx = true, enter = true, music = true, lunge = true, hit = true,
	shock = true, word = true, pose = true, sting = true, wipe = true, finish = true, shove = true, spin = true,
	hitstop = true, arena = true, clash = true, marker = true, slowmo = true, move = true, beam = true,
	timestop = true, flick = true, timeresume = true, detonate = true, flash = true, shake = true,
	brawlball = true, brawlballend = true, lines = true, tornado = true, bigcard = true, ultimate = true,
	dutchflip = true, stars = true, charge = true, crack = true, musicstop = true, shear = true, blackout = true,
	eyes = true, unshear = true, whiteflash = true, theme = true, freeze = true, unfreeze = true,
	reassemble = true, fakepose = true, fakeframe = true, fakecrack = true, swing = true, dodge = true,
}
local fakeSeen = { Mythic = 0, Legendary = 0, Secret = 0 }
local scriptsBuilt = 0
local ids = {}
for _, t in ipairs(PullRates.Tiers) do
	for _, id in ipairs(PullRates.Pool[t]) do
		table.insert(ids, id)
	end
end
for _, id in ipairs(ids) do
	for seed = 1, 25 do
		local cast = Casting.build(id, seed * 7919)
		local tier = cast.tier
		local fs = cast.fighters
		local okCast = fs[cast.winner].id == id and cast.winner == #fs and #fs == 3 + #Casting.Crashers[tier]
		local seen = {}
		for i, f in ipairs(fs) do
			if seen[f.id] then
				okCast = false
			end
			seen[f.id] = true
			if i ~= cast.winner then
				okCast = okCast and f.kind == "creature" and PullRates.Rank[f.tier] <= PullRates.Rank[tier]
			end
		end
		okCast = okCast and fs[1].tier == "Common" and fs[2].tier == "Common"
		check(okCast, "cast for " .. id .. " seed " .. seed)
		if cast.fakeOut then
			fakeSeen[tier] += 1
		end

		local s = Scripts.build(cast)
		scriptsBuilt += 1
		local want = Scripts.Length[tier] + (cast.fakeOut and Scripts.FakeOutLength or 0)
		local okS = math.abs(s.length - want) < 1e-6
		local entered, out, enterT = {}, {}, {}
		local lastT = -1
		local problems = {}
		for _, c in ipairs(s.cues) do
			if c.t < lastT then
				table.insert(problems, "unsorted at " .. c.k)
			end
			lastT = c.t
			if not KNOWN[c.k] then
				table.insert(problems, "unknown cue " .. tostring(c.k))
			end
			if c.t > s.length + 1e-6 then
				table.insert(problems, c.k .. " after the end")
			end
			for _, field in ipairs({ "who", "by", "target", "a", "b" }) do
				local w = c[field]
				if type(w) == "number" and (w < 1 or w > #fs) then
					table.insert(problems, c.k .. "." .. field .. " out of range")
				end
			end
			if c.k == "enter" then
				if entered[c.who] then
					table.insert(problems, "fighter " .. c.who .. " enters twice")
				end
				entered[c.who] = true
				enterT[c.who] = c.t
			elseif c.k == "hit" or c.k == "lunge" then
				if not entered[c.who] or (c.by and not entered[c.by]) then
					table.insert(problems, c.k .. " before fighter entered at t=" .. c.t)
				end
				if c.k == "hit" and c.ko then
					out[c.who] = true
				end
				if c.k == "hit" and c.who == cast.winner then
					table.insert(problems, "winner gets hit")
				end
			end
		end
		-- every hit and dodge has its attacker's swing, started so the blow lands on time
		local swingAt = {}
		for _, c in ipairs(s.cues) do
			if c.k == "swing" then
				swingAt[c.who .. "@" .. string.format("%.4f", c.contact)] = c
				if not c.dive and math.abs((c.contact - c.t) - (c.sig and Scripts.SignatureContact or Scripts.Contact[c.power])) > 1e-6 and c.t > 1e-9 then
					table.insert(problems, "swing lead time off at t=" .. c.t)
				end
				if enterT[c.who] == nil or c.t < enterT[c.who] - 1e-9 then
					table.insert(problems, "swing before fighter " .. c.who .. " entered")
				end
				if c.sig and fs[c.who].kind ~= "creature" then
					table.insert(problems, "signature for a non-creature")
				end
			end
		end
		for _, c in ipairs(s.cues) do
			if (c.k == "hit" or c.k == "dodge") and c.by then
				local key = c.by .. "@" .. string.format("%.4f", c.k == "dodge" and c.contact or c.t)
				if not swingAt[key] then
					-- a sweep hitting several at once shares one swing
					local shared = false
					for _, w in ipairs(s.cues) do
						if w.k == "swing" and w.who == c.by and math.abs(w.contact - (c.k == "dodge" and c.contact or c.t)) <= 0.021 then
							shared = true
						end
					end
					if not shared then
						-- or the attacker is still mid-swing from just before
						for _, w in ipairs(s.cues) do
							if w.k == "swing" and w.who == c.by and w.contact < c.t and w.contact > c.t - 0.5 then
								shared = true
							end
						end
					end
					if not shared then
						table.insert(problems, c.k .. " at t=" .. c.t .. " has no swing")
					end
				end
			end
		end
		for i = 1, #fs do
			if not entered[i] then
				table.insert(problems, "fighter " .. i .. " never enters")
			elseif i ~= cast.winner then
				if not out[i] then
					table.insert(problems, "fighter " .. i .. " (" .. fs[i].id .. ") is never knocked out")
				end
				if enterT[i] > enterT[cast.winner] then
					table.insert(problems, "fighter " .. i .. " enters after the winner")
				end
			end
		end
		check(okS and #problems == 0, "script " .. id .. " seed " .. seed .. " (" .. tier .. (cast.fakeOut and ", fake" or "") .. "): length " .. s.length .. "/" .. want .. " " .. table.concat(problems, "; "))
		local skipT, toReveal = Scripts.skipTarget(s, 1.0)
		if tier == "Secret" then
			check(not toReveal and skipT < s.length, "Secret skip jumps to the flash")
		else
			check(toReveal and skipT == s.length, tier .. " skip jumps to the reveal")
		end
	end
end
-- Rigs and moves: every creature model splits into moving parts, and every move keeps the
-- parts together (nothing flies off, nothing goes NaN)
check(Moves.Contact[1] == Scripts.Contact[1] and Moves.Contact[2] == Scripts.Contact[2] and Moves.Contact[3] == Scripts.Contact[3], "move and script contact times agree")
check(Moves.SignatureContact == Scripts.SignatureContact, "signature contact times agree")
local moveNames = {}
for name in pairs(Moves.list) do
	table.insert(moveNames, name)
end
table.sort(moveNames)
local rigged, kinds = 0, {}
for id in pairs(ModelData) do
	local rig = Rig.get(id)
	check(rig ~= nil and rig.bones.body ~= nil, id .. " rigs")
	rigged += 1
	kinds[rig.kind] = (kinds[rig.kind] or 0) + 1
	local h = rig.height
	local list = table.clone(moveNames)
	if Moves.Signatures[id] then
		table.insert(list, id)
	end
	local worst, worstWhere = 0, ""
	local okFinite = true
	for _, name in ipairs(list) do
		local m = Moves.get(name)
		for step = 0, 20 do
			local t = m.dur * step / 20
			for _, lead in ipairs({ "L", "R" }) do
				local pose = table.clone(Moves.sample(m, t))
				pose.leadSide = lead
				local solved = Rig.solve(rig, pose)
				-- the root (spins, sidesteps) moves everything together; measure against it
				local rootless = table.clone(pose)
				rootless.root = nil
				local solved2 = Rig.solve(rig, rootless)
				for i, p in ipairs(rig.parts) do
					local x, y, z = Rig.partPos(rig, solved2, i)
					local x2, y2, z2 = Rig.partPos(rig, solved, i)
					if x ~= x or y ~= y or z ~= z or x2 ~= x2 or y2 ~= y2 or z2 ~= z2 then
						okFinite = false
					end
					local d = math.sqrt((x - p.pos[1]) ^ 2 + (y - p.pos[2]) ^ 2 + (z - p.pos[3]) ^ 2)
					if d > worst then
						worst, worstWhere = d, name .. "@" .. t .. " " .. p.name
					end
				end
			end
		end
	end
	check(okFinite, id .. ": every move stays finite")
	-- a hand can swing over the head (about 2 heights for a tall arm); more means it came off
	check(worst < h * 2.2 + 1.5, string.format("%s: parts stay attached (moved %.2f of height %.2f at %s)", id, worst, h, worstWhere))
end
check(rigged >= 60, "all creature models rigged (" .. rigged .. ")")
check((kinds.biped or 0) >= 10 and (kinds.quad or 0) >= 3, "rigs found bipeds and four-legged creatures")
-- every Epic+ creature has a signature move with the shared contact time
for id, def in pairs(CardData.Cards) do
	if def.type == "Creature" and not def.token and PullRates.Rank[def.rarity] >= PullRates.Rank.Epic then
		local sig = Moves.Signatures[id]
		check(sig ~= nil and sig.name ~= nil and math.abs(sig.contact - Moves.SignatureContact) < 1e-9, id .. " has a signature move")
	end
end
-- every creature can pick an attack of every power
for id in pairs(ModelData) do
	local rig = Rig.get(id)
	for power = 1, 3 do
		for k = 0, 3 do
			local name = Moves.pickAttack(rig, power, k, id, false)
			check(Moves.get(name) ~= nil and Moves.get(name).contact ~= nil, id .. " picks a real attack for power " .. power)
		end
	end
end
-- important rigs look right
local function bonesOf(id)
	local r = Rig.get(id)
	return r.bones, r
end
do
	local b, r = bonesOf("toaster_knight")
	check(r.kind == "biped" and r.has.weapon and b.armR and b.armL and b.legL and b.legR, "toaster knight: two arms, two legs, a weapon")
	local knife = false
	for _, p in ipairs(b.armR.parts) do
		knife = knife or p.name == "KnifeBlade"
	end
	check(knife, "toaster knight's knife moves with its arm")
	b, r = bonesOf("lightning_llama")
	check(r.kind == "quad" and b.legFL and b.legBR and b.head and b.tail, "llama: four legs, head and tail")
	b, r = bonesOf("spaghetti_hydra")
	check(r.has.heads == 3, "hydra has three heads")
	b, r = bonesOf("the_mannequin_duke")
	check(b.base ~= nil, "the duke's stand stays on the floor when he leans")
	b, r = bonesOf("captain_confetti")
	check(b.wingL and b.wingR and r.has.weapon, "captain confetti swings the spyglass with a wing")
end


-- Packs: the shelf's packs, their odds, prices and rolls
do
	local Packs = require("Packs")
	check(#Packs.List == 7 and Packs.List[1].id == "brawl", "7 packs: the Brawl Pack first, then one per family")
	local famSeen = {}
	for _, def in ipairs(Packs.List) do
		if def.family then
			famSeen[def.family] = true
			check(def.mascot and CardData.Cards[def.mascot] and CardData.Cards[def.mascot].family == def.family, def.id .. ": its mascot is one of its family's cards")
			check(def.terrain ~= nil, def.id .. ": has a home terrain")
		end
		check(#def.color == 3 and #def.dark == 3 and #def.accent == 3, def.id .. ": has its colors")
		-- exact card odds add up to 100 and every pack can give every tier
		local map, list = Packs.cardOdds(def.id)
		local total, tiers = 0, {}
		for _, e in ipairs(list) do
			total += e.chance
			tiers[e.tier] = (tiers[e.tier] or 0) + e.chance
			check(e.chance > 0, def.id .. ": " .. e.id .. " has a chance")
			check(not CardData.Cards[e.id].token, def.id .. ": no tokens in packs (" .. e.id .. ")")
			if def.family then
				check(e.family == def.family or e.family == "Any" or e.tier == "Secret", def.id .. ": only its family, shared cards or a Secret (" .. e.id .. ")")
			end
		end
		check(math.abs(total - 100) < 1e-6, def.id .. ": card odds add up to 100% (" .. total .. ")")
		for _, t in ipairs(PullRates.Tiers) do
			check(math.abs((tiers[t] or 0) - PullRates.Odds[t]) < 1e-6, def.id .. ": " .. t .. " keeps the shelf-wide rarity odds")
		end
	end
	for _, f in ipairs(CardData.Families) do
		check(famSeen[f], "a pack for the " .. f .. " family")
	end
	check(Packs.price(1) == 100 and Packs.price(10) == 900 and Packs.price(3) == nil, "prices: 100 Gems, 900 for 10, nothing else")
	check(Packs.valid(nil) and Packs.valid("robo") and not Packs.valid("candy") and not Packs.valid(5), "pack ids are checked")
	check(Packs.percent(55) == "55%" and Packs.percent(4.5) == "4.5%" and Packs.percent(0.3) == "0.3%" and Packs.percent(0.075) == "0.075%" and Packs.percent(1) == "1%", "percent labels")
	-- a family's own card comes up 3 times in 4 (Common: both groups have cards)
	local rng = Rng.new(7)
	local rand = function()
		return rng:next()
	end
	local own, n = 0, 20000
	for _ = 1, n do
		local id = Packs.pickCard("snack", "Common", rand)
		if CardData.Cards[id].family == "Snack" then
			own += 1
		end
	end
	check(math.abs(own / n - Packs.ThemeShare) < 0.015, string.format("a Snack pack's Commons are Snack cards %.1f%% of the time (want 75%%)", own / n * 100))
	-- simulated pulls match the published per-card odds
	local map = Packs.cardOdds("critter")
	local seen, pulls = {}, 60000
	for _ = 1, pulls do
		local r = Packs.roll("critter", 1, rand)
		seen[r.cards[1]] = (seen[r.cards[1]] or 0) + 1
	end
	local worst = 0
	for id, pct in pairs(map) do
		local got = (seen[id] or 0) / pulls * 100
		if pct >= 1 then
			worst = math.max(worst, math.abs(got - pct) / pct)
		end
	end
	check(worst < 0.12, string.format("60,000 Critter pulls land within 12%% of the shown odds for every card of 1%% or more (worst %.1f%%)", worst * 100))
	-- 10 packs always hold an Epic or better; forced tiers; boosted odds
	for _ = 1, 300 do
		local r = Packs.roll("junk", 10, rand)
		local best = PullRates.Rank[CardData.Cards[r.cards[r.best]].rarity]
		check(best >= PullRates.Rank[PullRates.TenPullFloor], "10 Junk packs hold an Epic or better")
		if best < PullRates.Rank[PullRates.TenPullFloor] then
			break
		end
	end
	local r = Packs.roll("weather", 1, rand, "Secret")
	check(CardData.Cards[r.cards[1]].rarity == "Secret" and r.packId == "weather", "a forced Secret from the Weather pack (it has none of its own, so any Secret)")
	r = Packs.roll(nil, 1, rand)
	check(r.packId == "brawl", "no pack id means the Brawl Pack")
	if PullRates.luckyOdds then
		local lucky = PullRates.luckyOdds(2)
		local m1, m2 = Packs.cardOdds("robo"), Packs.cardOdds("robo", lucky)
		check(m2.omega_microwave > m1.omega_microwave * 1.9, "Luck boosts raise a themed pack's Secret chance too")
	end
end

for t, nFake in pairs(fakeSeen) do
	check(nFake > 0, "the fake ending shows up for " .. t)
end
print(string.format("Pack Brawl tests: %d passed, %d failed (%d scripts built)", passed, failed, scriptsBuilt))
if failed > 0 then
	error("tests failed")
end

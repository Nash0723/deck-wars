-- Headless tests for the Pack Brawl pull cinematic (rates, casting, choreography).
-- Run with: luaurun tests/packbrawl_tests.luau src/packbrawl src/shared
local CardData = require("CardData")
local PullRates = require("PullRates")
local Casting = require("Casting")
local Scripts = require("Scripts")
local Rng = require("Rng")

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
	reassemble = true, fakepose = true, fakeframe = true, fakecrack = true,
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
for t, nFake in pairs(fakeSeen) do
	check(nFake > 0, "the fake ending shows up for " .. t)
end
print(string.format("Pack Brawl tests: %d passed, %d failed (%d scripts built)", passed, failed, scriptsBuilt))
if failed > 0 then
	error("tests failed")
end

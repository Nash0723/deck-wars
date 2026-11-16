-- Headless tests for the Park's save logic: which cards a booth shows, picking them, likes (never
-- your own, once per booth per UTC day), your rarest pull and the titles it gives, which pulls get
-- a banner, where the booths stand, who the Top Collector is, and the park's real-time sky.
-- Run with: luaurun tests/park_tests.luau src/shared mock_roblox

_G.warn = function() end
local Mock = require("RobloxMock") -- (for Vector3 and CFrame)
for _, k in ipairs({ "Vector3", "CFrame", "typeof" }) do
	_G[k] = Mock.env[k]
end

local CardData = require("CardData")
local Park = require("Park")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. msg)
	end
end

local function byRarity(rarity, n)
	local out = {}
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if c.rarity == rarity and not c.token and #out < n then
			table.insert(out, id)
		end
	end
	return out
end

local commons = byRarity("Common", 6)
local rares = byRarity("Rare", 2)
local epic = byRarity("Epic", 1)[1]
local mythic = byRarity("Mythic", 1)[1]
local legendary = byRarity("Legendary", 1)[1]
local secret = byRarity("Secret", 1)[1]

-- A booth shows your rarest cards until you pick
do
	local d = { collection = { [commons[1]] = 3, [commons[2]] = 1, [rares[1]] = 1, [epic] = 1 } }
	local show = Park.showcaseOf(d)
	check(#show == 3, "a booth holds 3 cards")
	check(show[1] == epic and show[2] == rares[1], "the rarest come first")
	check(d.showcase and d.hub and d.hub.likes == 0, "the Park tables are added to an old save")

	-- picking
	check(Park.setShowcase(d, { commons[2] }) == true, "you can pick a card you own")
	show = Park.showcaseOf(d)
	check(show[1] == commons[2] and #show == 3, "your pick comes first, the rest fill up with your rarest")
	local ok, why = Park.setShowcase(d, { mythic })
	check(ok == false and why ~= nil, "you can't show a card you don't own")
	check(d.showcase.cards[1] == commons[2], "a refused pick changes nothing")
	ok = Park.setShowcase(d, { commons[1], commons[2], rares[1], epic })
	check(ok == false, "a booth holds at most 3 cards")
	ok = Park.setShowcase(d, { "no_such_card" })
	check(ok == false, "a card that doesn't exist is refused")
	check(Park.setShowcase(d, { epic, epic }) == true and #d.showcase.cards == 1, "the same card twice counts once")
	check(Park.setShowcase(d, {}) == true and #Park.showcaseOf(d) == 3, "no picks = your 3 rarest again")
	check(Park.setShowcase(d, "nope") == false, "junk from the client is refused")

	-- a card you sold or lost drops off the booth
	Park.setShowcase(d, { commons[2] })
	d.collection[commons[2]] = 0
	show = Park.showcaseOf(d)
	check(table.find(show, commons[2]) == nil, "a card you no longer own isn't shown")

	-- companion: your first creature on show
	local comp = Park.companionOf(d)
	check(comp == nil or CardData.Cards[comp].type == "Creature", "the companion is a creature")
end

-- An empty collection
do
	local d = { collection = {} }
	check(#Park.showcaseOf(d) == 0, "no cards, an empty booth")
	check(Park.companionOf(d) == nil, "no cards, no companion")
end

-- Likes
do
	local a, b = { collection = {} }, { collection = {} }
	local day = 20000 * 86400
	local ok, why = Park.like(a, 1, a, 1, day)
	check(ok == false and why ~= nil and a.hub.likes == 0, "you can't like your own booth")
	check(Park.like(a, 1, b, 2, day) == true and b.hub.likes == 1, "a like counts")
	check(Park.likedToday(a, 2, day), "it remembers you liked that booth today")
	ok = Park.like(a, 1, b, 2, day + 3600)
	check(ok == false and b.hub.likes == 1, "only once per booth a day")
	local c = { collection = {} }
	check(Park.like(a, 1, c, 3, day + 3600) == true and c.hub.likes == 1, "but you can like other booths the same day")
	check(Park.like(a, 1, b, 2, day + 86400) == true and b.hub.likes == 2, "and the same booth again the next day")
	check(not Park.likedToday(a, 3, day + 86400), "yesterday's likes are forgotten")
	check(a.hub.likes == 0, "liking doesn't give you likes")
end

-- Your rarest pull and titles
do
	local d = { collection = {} }
	check(#Park.titlesOf(d, {}) == 0 and Park.titleOf(d, {}) == nil, "no titles at first")
	check(Park.notePull(d, { commons[1] }, 100) == true, "a first pull is your best so far")
	check(#Park.titlesOf(d, {}) == 0, "a Common gives no title")
	check(Park.notePull(d, { commons[2], mythic, rares[1] }, 200) == true and d.hub.best.id == mythic, "a Mythic beats it")
	check(Park.notePull(d, { epic }, 300) == false and d.hub.best.id == mythic, "an Epic doesn't")
	check(Park.titleOf(d, {}) == Park.PullTitles.Mythic, "the Mythic gives a title")
	local earned = { "Den Graduate" }
	check(#Park.titlesOf(d, earned) == 2, "Campaign titles join it")
	check(Park.titleOf(d, earned) == "Den Graduate", "the newest title shows unless you pick one")
	check(Park.setTitle(d, earned, Park.PullTitles.Mythic) == true and Park.titleOf(d, earned) == Park.PullTitles.Mythic, "you can pick a title you have")
	check(Park.setTitle(d, earned, "Mall Legend") == false, "not one you haven't earned")
	check(Park.setTitle(d, earned, nil) == true and Park.titleOf(d, earned) == "Den Graduate", "clearing goes back to the newest")
	if secret then
		Park.notePull(d, { secret }, 400)
		check(Park.titleOf(d, {}) == Park.PullTitles.Secret, "a Secret pull gives the top pull title")
	end
end

-- Banners
do
	check(Park.announceLevel(commons[1]) == nil, "a Common gets no banner")
	check(Park.announceLevel(epic) == nil, "an Epic gets no banner")
	check(Park.announceLevel(mythic) == "server", "a Mythic gets a banner in this server")
	check(legendary == nil or Park.announceLevel(legendary) == "server", "so does a Legendary")
	check(secret == nil or Park.announceLevel(secret) == "cross", "a Secret is told to every server")
	check(Park.announceLevel("no_such_card") == nil, "unknown cards get nothing")
	check(Park.announceLevel(commons[1], true) == "cross", "a Shiny card is told to every server, whatever its rarity")
	-- the chat: Secret and Shiny pulls only
	check(not Park.chatWorthy({ rarity = "Legendary" }), "a Legendary isn't posted in the chat")
	check(Park.chatWorthy({ rarity = "Secret" }), "a Secret is posted in the chat")
	check(Park.chatWorthy({ rarity = "Common", shiny = true }), "a Shiny is posted in the chat")
	local line = Park.chatLine({ name = "<b>Nash</b>", rarity = "Secret", far = true }, "Omega Microwave", "FF00AA")
	check(string.find(line, "&lt;b&gt;Nash&lt;/b&gt;", 1, true) ~= nil and string.find(line, "<b>Nash</b>", 1, true) == nil, "names in the chat line can't inject rich text")
	check(string.find(line, "Omega Microwave", 1, true) ~= nil and string.find(line, "FF00AA", 1, true) ~= nil and string.find(line, "Secret", 1, true) ~= nil, "the chat line names the card, its rarity and colour: " .. line)
	local sorted = Park.sortRarest({ commons[1], mythic, rares[1], epic })
	check(sorted[1] == mythic and sorted[4] == commons[1], "rarest-first sorting")
end

-- Booths stand in a ring facing the altar, far enough apart, inside the hedge
do
	local seen = {}
	for i = 1, Park.Booths do
		local cf = Park.boothCFrame(i)
		local rel = cf.Position - Park.Origin
		check(math.abs(rel.Magnitude - Park.BoothRadius) < 1e-6, "booth " .. i .. " is on the ring")
		local toMiddle = (Park.Origin - cf.Position).Unit
		check(cf.LookVector:Dot(toMiddle) > 0.999, "booth " .. i .. " faces the altar")
		for j, other in ipairs(seen) do
			check((other - cf.Position).Magnitude > 20, "booths " .. j .. " and " .. i .. " don't overlap")
		end
		table.insert(seen, cf.Position)
		-- the four paths (N, E, S, W) stay free
		local angle = math.deg(math.atan2(rel.X, rel.Z)) % 90
		check(angle > 8 and angle < 82, "booth " .. i .. " stays off the paths")
	end
	local spawn = Park.spawnCFrame(0)
	check((spawn.Position - Park.Origin).Magnitude < 120, "you walk in inside the hedge")
end

---------------------------------------------------------------------------
-- The Top Collector: the rarest cards win, then how many different cards
---------------------------------------------------------------------------
do
	local function saveOf(list)
		local d = { collection = {} }
		for _, id in ipairs(list) do
			d.collection[id] = (d.collection[id] or 0) + 1
		end
		return d
	end
	local commons, rares, epics, mythics = byRarity("Common", 4), byRarity("Rare", 2), byRarity("Epic", 2), byRarity("Mythic", 1)
	local top, count = Park.rarestCards(saveOf({ commons[1], commons[2], rares[1], mythics[1], epics[1] }), 3)
	check(#top == 3 and top[1] == mythics[1] and top[2] == epics[1] and top[3] == rares[1] and count == 5, "rarestCards: the three rarest, rarest first, and how many cards")
	check(#Park.rarestCards({ collection = {} }) == 0 and #Park.rarestCards(nil) == 0, "an empty save has no rarest cards")
	check(#Park.rarestCards({ collection = { [commons[1]] = 0, nonsense = 3 } }) == 0, "copies of nothing and unknown cards don't count")
	local key = Park.collectionKey(saveOf({ commons[1], mythics[1] }))
	check(#key == Park.ChampionCards + 1 and key[1] == Park.Rank.Mythic and key[2] == Park.Rank.Common and key[3] == 0 and key[4] == 2, "the key is the three best ranks and the card count")
	check(Park.betterCollection({ 4, 1, 0, 2 }, { 3, 3, 3, 40 }), "one rarer card beats many lesser ones")
	check(Park.betterCollection({ 3, 2, 0, 2 }, { 3, 1, 1, 9 }), "then the second rarest decides")
	check(Park.betterCollection({ 3, 2, 1, 9 }, { 3, 2, 1, 8 }) and not Park.betterCollection({ 3, 2, 1, 8 }, { 3, 2, 1, 8 }), "then the number of cards; equal is not better")

	local alice = { id = "alice", d = saveOf({ mythics[1], commons[1] }) }
	local bob = { id = "bob", d = saveOf({ epics[1], epics[2], rares[1], commons[1], commons[2] }) }
	local carol = { id = "carol", d = saveOf({ mythics[1], commons[2] }) } -- as good as alice
	local nobody = { id = "nobody", d = saveOf({}) }
	check(Park.pickChampion({ bob, alice, nobody }) == alice, "the rarest card makes the Top Collector")
	check(Park.pickChampion({ nobody }) == nil and Park.pickChampion({}) == nil, "nobody with a card, no Top Collector")
	check(Park.pickChampion({ alice, carol }) == alice and Park.pickChampion({ carol, alice }) == carol, "on a tie the first one found has it")
	check(Park.pickChampion({ alice, carol }, "carol") == carol and Park.pickChampion({ carol, alice }, "carol") == carol, "the one already on the pedestal keeps it on a tie")
	check(Park.pickChampion({ alice, bob }, "bob") == alice, "but not against a better collection")
end

---------------------------------------------------------------------------
-- The park's sky: real sunrise and sunset stretched onto Roblox's clock
---------------------------------------------------------------------------
do
	-- at the equator on the equinox the day is about 12 hours, around local noon
	local rise, set = Park.sunTimes(0, 0, 80, 0)
	check(math.abs(rise - 6) < 0.3 and math.abs(set - 18) < 0.3, string.format("equator, equinox: sunrise about 6, sunset about 18 (%.2f, %.2f)", rise, set))
	-- Budapest: long days in June, short in December (east of Greenwich, UTC+1 in winter)
	local rJ, sJ = Park.sunTimes(47.5, 19.04, 172, 2)
	local rD, sD = Park.sunTimes(47.5, 19.04, 355, 1)
	check((sJ - rJ) % 24 > 15 and (sJ - rJ) % 24 < 17, string.format("Budapest in June: about 16 hours of day (%.2f)", (sJ - rJ) % 24))
	check((sD - rD) % 24 > 8 and (sD - rD) % 24 < 9.2, string.format("Budapest in December: about 8.5 hours of day (%.2f)", (sD - rD) % 24))
	check(math.abs(rJ - 4.8) < 0.4 and math.abs(sJ - 20.7) < 0.4, string.format("June sunrise near 4:50 and sunset near 20:45 (%.2f, %.2f)", rJ, sJ))
	-- the far north never gets an endless day or night
	for _, yday in ipairs({ 1, 172, 355 }) do
		local r, s = Park.sunTimes(89, 0, yday, 0)
		local day = (s - r) % 24
		check(day >= 1.5 and day <= 22.5, string.format("the pole on day %d still has a day and a night (%.2f)", yday, day))
	end
	-- the park clock: sunrise is 6, sunset is 18, noon and midnight in between
	check(math.abs(Park.skyClock(5, 5, 21) - 6) < 1e-9 and math.abs(Park.skyClock(21, 5, 21) - 18) < 1e-9, "sunrise lands on 6 and sunset on 18")
	check(math.abs(Park.skyClock(13, 5, 21) - 12) < 1e-9, "the middle of the day is 12")
	check(math.abs(Park.skyClock(1, 5, 21) - 0) < 1e-9 or math.abs(Park.skyClock(1, 5, 21) - 24) < 1e-9, "the middle of the night is midnight")
	local last = Park.skyClock(5, 5, 21)
	local forward = true
	for h = 5.25, 28.9, 0.25 do
		local c = Park.skyClock(h % 24, 5, 21)
		local step = (c - last) % 24
		if step <= 0 or step > 1 then
			forward = false
		end
		last = c
	end
	check(forward, "the park's clock only ever runs forward, without jumps")
	check(math.abs(Park.skyClock(12, 7, 7) - 11) < 1e-9, "a broken sunrise/sunset pair falls back to a 12 hour day (5 hours after a 7:00 sunrise is 11)")

	-- the light: every key is complete, and the blend hits the keys and stays between them
	local names = {}
	for k in pairs(Park.SkyKeys[1]) do
		names[k] = true
	end
	for i, key in ipairs(Park.SkyKeys) do
		for k in pairs(names) do
			check(key[k] ~= nil, "sky key " .. i .. " has " .. k)
		end
		check(i == 1 or key.c > Park.SkyKeys[i - 1].c, "sky keys are in order")
		local at = Park.sky(key.c)
		check(math.abs(at.Brightness - key.Brightness) < 1e-9 and math.abs(at.Ambient[1] - key.Ambient[1]) < 1e-9, "the sky at key " .. i .. " is that key")
	end
	local lo, hi = math.huge, -math.huge
	for _, key in ipairs(Park.SkyKeys) do
		lo, hi = math.min(lo, key.Brightness), math.max(hi, key.Brightness)
	end
	local inRange = true
	for c = 0, 24, 0.05 do
		local s = Park.sky(c)
		if s.Brightness < lo - 1e-9 or s.Brightness > hi + 1e-9 or s.c ~= nil then
			inRange = false
		end
	end
	check(inRange, "in between, the light stays between the keys")
	check(Park.sky(12.5).Brightness > Park.sky(0).Brightness and Park.sky(36.5).Brightness == Park.sky(12.5).Brightness, "midday is brighter than midnight, and the clock wraps")
	check(Park.darkness(12) == 0 and Park.darkness(0) == 1 and Park.darkness(22) == 1, "dark at night, not at noon")
	check(Park.darkness(18.15) > 0 and Park.darkness(18.15) < 1 and Park.darkness(6.3) > 0 and Park.darkness(6.3) < 1, "the lamps come on through sunset and go off through sunrise")

	-- the pond is always wider than the island, and inside the old booth ring
	for a = 0, 6.28, 0.1 do
		local r = Park.pondRadius(a)
		check(r > Park.IslandRadius + 5 and r < Park.BoothRadius - 10, string.format("the shore at angle %.1f is past the island and inside the lawn (%.1f)", a, r))
	end
end

print(string.format("park tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("park tests failed")
end

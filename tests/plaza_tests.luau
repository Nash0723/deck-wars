-- Headless tests for the Plaza's save logic: which cards a booth shows, picking them, likes (never
-- your own, once per booth per UTC day), your rarest pull and the titles it gives, which pulls get
-- a banner, and where the booths stand.
-- Run with: luaurun tests/plaza_tests.luau src/shared mock_roblox

_G.warn = function() end
local Mock = require("RobloxMock") -- (for Vector3 and CFrame)
for _, k in ipairs({ "Vector3", "CFrame", "typeof" }) do
	_G[k] = Mock.env[k]
end

local CardData = require("CardData")
local Plaza = require("Plaza")

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
	local show = Plaza.showcaseOf(d)
	check(#show == 3, "a booth holds 3 cards")
	check(show[1] == epic and show[2] == rares[1], "the rarest come first")
	check(d.showcase and d.hub and d.hub.likes == 0, "the Plaza tables are added to an old save")

	-- picking
	check(Plaza.setShowcase(d, { commons[2] }) == true, "you can pick a card you own")
	show = Plaza.showcaseOf(d)
	check(show[1] == commons[2] and #show == 3, "your pick comes first, the rest fill up with your rarest")
	local ok, why = Plaza.setShowcase(d, { mythic })
	check(ok == false and why ~= nil, "you can't show a card you don't own")
	check(d.showcase.cards[1] == commons[2], "a refused pick changes nothing")
	ok = Plaza.setShowcase(d, { commons[1], commons[2], rares[1], epic })
	check(ok == false, "a booth holds at most 3 cards")
	ok = Plaza.setShowcase(d, { "no_such_card" })
	check(ok == false, "a card that doesn't exist is refused")
	check(Plaza.setShowcase(d, { epic, epic }) == true and #d.showcase.cards == 1, "the same card twice counts once")
	check(Plaza.setShowcase(d, {}) == true and #Plaza.showcaseOf(d) == 3, "no picks = your 3 rarest again")
	check(Plaza.setShowcase(d, "nope") == false, "junk from the client is refused")

	-- a card you sold or lost drops off the booth
	Plaza.setShowcase(d, { commons[2] })
	d.collection[commons[2]] = 0
	show = Plaza.showcaseOf(d)
	check(table.find(show, commons[2]) == nil, "a card you no longer own isn't shown")

	-- companion: your first creature on show
	local comp = Plaza.companionOf(d)
	check(comp == nil or CardData.Cards[comp].type == "Creature", "the companion is a creature")
end

-- An empty collection
do
	local d = { collection = {} }
	check(#Plaza.showcaseOf(d) == 0, "no cards, an empty booth")
	check(Plaza.companionOf(d) == nil, "no cards, no companion")
end

-- Likes
do
	local a, b = { collection = {} }, { collection = {} }
	local day = 20000 * 86400
	local ok, why = Plaza.like(a, 1, a, 1, day)
	check(ok == false and why ~= nil and a.hub.likes == 0, "you can't like your own booth")
	check(Plaza.like(a, 1, b, 2, day) == true and b.hub.likes == 1, "a like counts")
	check(Plaza.likedToday(a, 2, day), "it remembers you liked that booth today")
	ok = Plaza.like(a, 1, b, 2, day + 3600)
	check(ok == false and b.hub.likes == 1, "only once per booth a day")
	local c = { collection = {} }
	check(Plaza.like(a, 1, c, 3, day + 3600) == true and c.hub.likes == 1, "but you can like other booths the same day")
	check(Plaza.like(a, 1, b, 2, day + 86400) == true and b.hub.likes == 2, "and the same booth again the next day")
	check(not Plaza.likedToday(a, 3, day + 86400), "yesterday's likes are forgotten")
	check(a.hub.likes == 0, "liking doesn't give you likes")
end

-- Your rarest pull and titles
do
	local d = { collection = {} }
	check(#Plaza.titlesOf(d, {}) == 0 and Plaza.titleOf(d, {}) == nil, "no titles at first")
	check(Plaza.notePull(d, { commons[1] }, 100) == true, "a first pull is your best so far")
	check(#Plaza.titlesOf(d, {}) == 0, "a Common gives no title")
	check(Plaza.notePull(d, { commons[2], mythic, rares[1] }, 200) == true and d.hub.best.id == mythic, "a Mythic beats it")
	check(Plaza.notePull(d, { epic }, 300) == false and d.hub.best.id == mythic, "an Epic doesn't")
	check(Plaza.titleOf(d, {}) == Plaza.PullTitles.Mythic, "the Mythic gives a title")
	local earned = { "Den Graduate" }
	check(#Plaza.titlesOf(d, earned) == 2, "Campaign titles join it")
	check(Plaza.titleOf(d, earned) == "Den Graduate", "the newest title shows unless you pick one")
	check(Plaza.setTitle(d, earned, Plaza.PullTitles.Mythic) == true and Plaza.titleOf(d, earned) == Plaza.PullTitles.Mythic, "you can pick a title you have")
	check(Plaza.setTitle(d, earned, "Mall Legend") == false, "not one you haven't earned")
	check(Plaza.setTitle(d, earned, nil) == true and Plaza.titleOf(d, earned) == "Den Graduate", "clearing goes back to the newest")
	if secret then
		Plaza.notePull(d, { secret }, 400)
		check(Plaza.titleOf(d, {}) == Plaza.PullTitles.Secret, "a Secret pull gives the top pull title")
	end
end

-- Banners
do
	check(Plaza.announceLevel(commons[1]) == nil, "a Common gets no banner")
	check(Plaza.announceLevel(epic) == nil, "an Epic gets no banner")
	check(Plaza.announceLevel(mythic) == "server", "a Mythic gets a banner in this server")
	check(legendary == nil or Plaza.announceLevel(legendary) == "server", "so does a Legendary")
	check(secret == nil or Plaza.announceLevel(secret) == "cross", "a Secret is told to every server")
	check(Plaza.announceLevel("no_such_card") == nil, "unknown cards get nothing")
	check(Plaza.announceLevel(commons[1], true) == "cross", "a Shiny card is told to every server, whatever its rarity")
	-- the chat: Secret and Shiny pulls only
	check(not Plaza.chatWorthy({ rarity = "Legendary" }), "a Legendary isn't posted in the chat")
	check(Plaza.chatWorthy({ rarity = "Secret" }), "a Secret is posted in the chat")
	check(Plaza.chatWorthy({ rarity = "Common", shiny = true }), "a Shiny is posted in the chat")
	local line = Plaza.chatLine({ name = "<b>Nash</b>", rarity = "Secret", far = true }, "Omega Microwave", "FF00AA")
	check(string.find(line, "&lt;b&gt;Nash&lt;/b&gt;", 1, true) ~= nil and string.find(line, "<b>Nash</b>", 1, true) == nil, "names in the chat line can't inject rich text")
	check(string.find(line, "Omega Microwave", 1, true) ~= nil and string.find(line, "FF00AA", 1, true) ~= nil and string.find(line, "Secret", 1, true) ~= nil, "the chat line names the card, its rarity and colour: " .. line)
	local sorted = Plaza.sortRarest({ commons[1], mythic, rares[1], epic })
	check(sorted[1] == mythic and sorted[4] == commons[1], "rarest-first sorting")
end

-- Booths stand in a ring facing the altar, far enough apart, inside the hedge
do
	local seen = {}
	for i = 1, Plaza.Booths do
		local cf = Plaza.boothCFrame(i)
		local rel = cf.Position - Plaza.Origin
		check(math.abs(rel.Magnitude - Plaza.BoothRadius) < 1e-6, "booth " .. i .. " is on the ring")
		local toMiddle = (Plaza.Origin - cf.Position).Unit
		check(cf.LookVector:Dot(toMiddle) > 0.999, "booth " .. i .. " faces the altar")
		for j, other in ipairs(seen) do
			check((other - cf.Position).Magnitude > 20, "booths " .. j .. " and " .. i .. " don't overlap")
		end
		table.insert(seen, cf.Position)
		-- the four paths (N, E, S, W) stay free
		local angle = math.deg(math.atan2(rel.X, rel.Z)) % 90
		check(angle > 8 and angle < 82, "booth " .. i .. " stays off the paths")
	end
	local spawn = Plaza.spawnCFrame(0)
	check((spawn.Position - Plaza.Origin).Magnitude < 120, "you walk in inside the hedge")
end

print(string.format("plaza tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("plaza tests failed")
end

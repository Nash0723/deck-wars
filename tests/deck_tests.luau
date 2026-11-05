-- Headless tests for deck building: the deck rules (themes, copies, ownership, lanes), the
-- starter collection, and PlayerDecks saving decks into the real EconomyManager profile.
-- Run with: luaurun tests/deck_tests.luau src/shared src/econ src/server src/packbrawl

local now = 1_800_000_000
_G.warn = function() end
_G.task = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			error(err)
		end
	end,
	wait = function(t)
		now += t or 0
	end,
	delay = function() end,
}

local CardData = require("CardData")
local DeckRules = require("DeckRules")
local StarterDecks = require("StarterDecks")
local MatchEngine = require("MatchEngine")
local ProfileStore = require("ProfileStore")
local EconomyManager = require("EconomyManager")

local passed, failed = 0, 0
local function check(cond, msg)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. msg)
	end
end
local function hasProblem(problems, pattern)
	for _, p in ipairs(problems) do
		if string.find(p, pattern, 1, true) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The starter collection and Starter Deck
---------------------------------------------------------------------------
local starterOwned = DeckRules.counts(DeckRules.starterGrant())
local starter = DeckRules.starterDeck()
local ok, problems = DeckRules.validate(starter, starterOwned)
check(ok, "the Starter Deck is legal with exactly the starter collection: " .. table.concat(problems, "; "))
check(#starter.cards == DeckRules.MinCards, "the Starter Deck has " .. DeckRules.MinCards .. " cards")
check(#DeckRules.StarterCharacters == 4, "4 starter characters")
for _, id in ipairs(DeckRules.StarterCharacters) do
	local d = CardData.Cards[id]
	check(d and d.type == "Creature" and not d.token, id .. " is a real creature")
	check(starterOwned[id] == 3, id .. ": 3 copies in the starter collection")
	check(table.find(starter.themes, d.family) ~= nil, id .. " fits the Starter Deck's themes")
end
for id in pairs(starterOwned) do
	check(DeckRules.collectible(id), id .. " in the starter collection is collectible")
end

---------------------------------------------------------------------------
-- The rules
---------------------------------------------------------------------------
local all = {}
for _, id in ipairs(CardData.List) do
	all[id] = 3
end

local function deckOf(themes, cards, lanes)
	return { name = "T", hero = "bonk", themes = themes, lanes = lanes or DeckRules.fixLanes(themes, nil), cards = cards }
end
local function familyCards(f, n)
	local out = {}
	for _, id in ipairs(CardData.List) do
		local d = CardData.Cards[id]
		if d.family == f and DeckRules.collectible(id) and DeckRules.copyLimit(id) == 3 then
			for _ = 1, 3 do
				if #out < n then
					table.insert(out, id)
				end
			end
		end
	end
	return out
end

local snack20 = familyCards("Snack", 20)
check(#snack20 == 20, "found 20 Snack cards for the tests")
ok = DeckRules.validate(deckOf({ "Snack" }, snack20), all)
check(ok, "a 20-card one-theme deck is legal")
ok, problems = DeckRules.validate(deckOf({}, snack20), all)
check(not ok and hasProblem(problems, "Pick a theme"), "a deck needs a theme")
ok, problems = DeckRules.validate(deckOf({ "Snack", "Junk", "Robo" }, snack20), all)
check(not ok and hasProblem(problems, "at most 2 themes"), "3 themes is too many")
ok, problems = DeckRules.validate(deckOf({ "Junk" }, snack20), all)
check(not ok and hasProblem(problems, "Not in this deck's themes"), "off-theme cards are caught")
local short = table.clone(snack20)
table.remove(short)
ok, problems = DeckRules.validate(deckOf({ "Snack" }, short), all)
check(not ok and hasProblem(problems, "Add 1 more card"), "19 cards is too few")
local long = table.clone(snack20)
for _, id in ipairs(familyCards("Critter", 11)) do
	table.insert(long, id)
end
ok, problems = DeckRules.validate(deckOf({ "Snack", "Critter" }, long), all)
check(not ok and hasProblem(problems, "Take out 1 card"), "31 cards is too many")
local four = table.clone(snack20)
table.insert(four, snack20[1])
ok, problems = DeckRules.validate(deckOf({ "Snack" }, four), all)
check(not ok and hasProblem(problems, "Too many copies"), "4 copies is too many")
-- one of a kind
local legend
for _, id in ipairs(CardData.List) do
	if CardData.Cards[id].rarity == "Legendary" and DeckRules.collectible(id) then
		legend = id
		break
	end
end
check(legend ~= nil and DeckRules.copyLimit(legend) == 1, "Legendary cards are one per deck")
-- ownership
local fewer = table.clone(all)
fewer[snack20[1]] = 1
ok, problems = DeckRules.validate(deckOf({ "Snack" }, snack20), fewer)
check(not ok and hasProblem(problems, "don't own enough"), "you can't use cards you don't own")
-- lanes
ok, problems = DeckRules.validate(deckOf({ "Snack", "Critter" }, snack20, { "Snack", "Junk", "Snack", "Critter" }), all)
check(not ok and hasProblem(problems, "lane"), "every lane must be one of the deck's themes")
local lanes = DeckRules.fixLanes({ "Snack", "Critter" }, { "Critter", "Junk" })
check(lanes[1] == "Critter" and lanes[2] ~= "Junk" and #lanes == CardData.Cols, "fixLanes keeps good lanes and fixes the rest")
local split = DeckRules.fixLanes({ "Snack", "Critter" }, nil)
check(split[1] == "Snack" and split[2] == "Snack" and split[3] == "Critter" and split[4] == "Critter", "two themes split the lanes 2 and 2")
-- tokens can't be put in decks
local token
for _, id in ipairs(CardData.List) do
	if CardData.Cards[id].token then
		token = id
		break
	end
end
check(token == nil or not DeckRules.collectible(token), "tokens are not collectible")

-- sanitize: garbage from a client
check(DeckRules.sanitize(nil) == nil and DeckRules.sanitize("x") == nil, "sanitize rejects non-tables")
local s = DeckRules.sanitize({ name = string.rep("A", 80) .. "\n", hero = "nobody", themes = { "Snack", "Snack", "Lava", 5 }, cards = { "jelly_bean_scout", "nope", 7, token }, lanes = { "Snack", "Lava" } })
check(#s.name <= DeckRules.MaxNameLength and not string.find(s.name, "\n"), "names are trimmed and cleaned")
check(s.hero == DeckRules.Heroes[1], "unknown heroes become the default hero")
check(#s.themes == 1 and s.themes[1] == "Snack", "unknown and repeated themes are dropped")
check(#s.cards == 1 and s.cards[1] == "jelly_bean_scout", "unknown cards and tokens are dropped")
check(s.lanes[2] == nil, "unknown lane terrains are dropped")
local huge = {}
for i = 1, 5000 do
	huge[i] = "jelly_bean_scout"
end
check(#DeckRules.sanitize({ cards = huge }).cards <= DeckRules.MaxCards + 10, "huge card lists are cut short")

-- autoFill only uses owned cards that fit, within the copy limits
local partial = deckOf({ "Snack", "Critter" }, { "jelly_bean_scout" })
local filled = DeckRules.autoFill(partial, starterOwned, DeckRules.MinCards)
check(#filled == DeckRules.MinCards, "Fill up reaches " .. DeckRules.MinCards .. " cards from the starter collection")
partial.cards = filled
ok, problems = DeckRules.validate(partial, starterOwned)
check(ok, "the filled deck is legal: " .. table.concat(problems, "; "))

-- every practice deck turns into a match setup that the engine accepts
for _, key in ipairs(StarterDecks.Order) do
	local p = DeckRules.fromPractice(StarterDecks[key])
	local setup = DeckRules.setupFor(p)
	check(setup.family == StarterDecks[key].family and #setup.lanes == CardData.Cols, key .. " practice deck makes a setup")
end
local m = MatchEngine.new({ DeckRules.setupFor(starter), DeckRules.setupFor(DeckRules.fromPractice(StarterDecks.Robo)) }, 7)
check(m.lanes[1][1].landscape == starter.lanes[1] and m.lanes[1][4].landscape == starter.lanes[4], "player 1's lanes come from the deck")
check(m.lanes[2][1].landscape ~= nil, "player 2's lanes have landscapes too")

---------------------------------------------------------------------------
-- PlayerDecks on top of the real EconomyManager (memory store)
---------------------------------------------------------------------------
local econObj = { __module = EconomyManager, IsA = function()
	return true
end }
local sharedObj = { WaitForChild = function(_, name)
	return name
end }
local services = {
	ServerStorage = { FindFirstChild = function(_, name)
		return name == "EconomyManager" and econObj or nil
	end },
	ServerScriptService = { FindFirstChild = function()
		return nil
	end },
	ReplicatedStorage = { WaitForChild = function()
		return sharedObj
	end },
}
_G.game = { GetService = function(_, n)
	return services[n]
end }
local origRequire = require
_G.require = function(x)
	if type(x) == "table" and x.__module then
		return x.__module
	end
	return origRequire(x)
end
local PlayerDecks = require("PlayerDecks")

EconomyManager.init({
	dataStore = ProfileStore.memoryStore(),
	jobId = "decktest",
	clock = function()
		return now
	end,
	wait = function(t)
		now += t or 0
	end,
	warn = _G.warn,
})
local nash = { UserId = 7, Name = "Nash" }
check(EconomyManager.load(nash) ~= nil, "Nash's profile loads")
local before = next(EconomyManager.getCollection(nash))
check(before == nil, "a new profile starts with no cards")
check(PlayerDecks.ensureStarter(nash), "the starter grant runs")
local col = EconomyManager.getCollection(nash)
for id, n in pairs(starterOwned) do
	check(col[id] == n, "starter grant: " .. id .. " x" .. n)
end
PlayerDecks.ensureStarter(nash)
check(EconomyManager.getCollection(nash).jelly_bean_scout == 3, "the starter is granted only once")
local d = EconomyManager.waitForData(nash)
check(d.stats.cardsPulled == 0 and d.stats.packsOpened == 0, "the starter grant doesn't count as pulls")
local snap = PlayerDecks.snapshot(nash)
check(snap.slots == EconomyManager.getDeckSlots(nash) and #snap.decks == 1 and snap.decks[1].ok, "the Starter Deck sits ready in slot 1")
local setup, deck = PlayerDecks.setupFor(nash, 1)
check(setup ~= nil and deck.name == "Starter Deck", "slot 1 makes a match setup")
-- save a second deck, unfinished, then finish it
ok, problems = PlayerDecks.saveDeck(nash, 2, { name = "Mice", hero = "granny_bolt", themes = { "Critter" }, cards = { "pocket_mouse" } })
check(not ok and hasProblem(problems, "more card"), "an unfinished deck saves with its problems")
check(PlayerDecks.setupFor(nash, 2) == nil, "an unfinished deck can't be played")
local cards = DeckRules.autoFill({ themes = { "Critter" }, cards = {} }, EconomyManager.getCollection(nash), 20)
ok = PlayerDecks.saveDeck(nash, 2, { name = "Mice", hero = "granny_bolt", themes = { "Critter" }, cards = cards })
check(not ok, "the starter collection doesn't have 20 Critter cards on its own")
ok, problems = PlayerDecks.saveDeck(nash, 9, starter)
check(not ok and hasProblem(problems, "slot"), "slots past your deck slots are refused")
ok = PlayerDecks.saveDeck(nash, 1.5, starter)
check(not ok, "half slots are refused")
-- cards you lose access to make the deck unplayable (checked at match time)
d.collection.pretzel_guard = 1
local s2, why = PlayerDecks.setupFor(nash, 1)
check(s2 == nil and string.find(why, "own", 1, true), "a deck with cards you no longer own can't be played")
d.collection.pretzel_guard = 3
check(PlayerDecks.deleteDeck(nash, 2), "deleting a deck")
check(#PlayerDecks.snapshot(nash).decks == 1, "the deleted deck is gone")
check(type(d.decks.s1) == "table", "decks are saved in the profile under string keys")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then
	error("deck tests failed")
end

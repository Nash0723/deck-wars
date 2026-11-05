-- Deck Wars deck rules: what a deck you build from your own collection may hold, the
-- starter collection every new player gets, and how a saved deck becomes a match setup.
-- Pure Luau with no Roblox parts, so the server, the deck builder screen and the tests all
-- use the same rules.
--
-- A saved deck looks like this:
--   { name = "Sweet Pack", hero = "bonk", themes = { "Snack", "Critter" },
--     lanes = { "Snack", "Snack", "Critter", "Critter" }, cards = { "jelly_bean_scout", ... } }
-- themes: the 1 or 2 families (MaxThemes) its cards may come from; "Any" cards always fit.
-- lanes:  the terrain of each of your 4 lanes, left to right from your chair. Each lane must
--         be one of the deck's themes. Creatures standing on their own family's terrain get
--         +1 attack, so the lanes are where your deck feels at home.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")

local DeckRules = {}

-- How many different themes (families) one deck may use. 2 keeps every deck's family rules
-- (Combo, Pack, Scrap, Soak...) strong and the game easy to balance; 4 would let one deck take
-- the best cards of two thirds of the game. Set it to 4 to try that out.
DeckRules.MaxThemes = 2
DeckRules.MinCards = 20
DeckRules.MaxCards = 30
DeckRules.MaxCopies = CardData.MaxCopies or 3
-- The rarest cards are one of a kind in a deck.
DeckRules.MaxCopiesByRarity = { Legendary = 1, Secret = 1 }
DeckRules.Heroes = { "bonk", "granny_bolt" }
DeckRules.MaxNameLength = 24
DeckRules.DefaultDeckSlots = 3

-- The starter collection: what every new player gets the first time they join.
-- The 4 starter characters (3 copies each, two Snacks and two Critters, so they fit one
-- two-theme deck) and 8 simple neutral cards, enough for the 20-card Starter Deck below.
-- Everything else comes from packs and the Shop.
DeckRules.StarterCharacters = { "jelly_bean_scout", "pretzel_guard", "pocket_mouse", "moth_mailman" }
DeckRules.StarterCards = {
	{ "jelly_bean_scout", 3 },
	{ "pretzel_guard", 3 },
	{ "pocket_mouse", 3 },
	{ "moth_mailman", 3 },
	{ "spare_battery", 2 },
	{ "snack_break", 2 },
	{ "wrong_turn", 2 },
	{ "spiked_fence", 2 },
}

local function expand(counts)
	local list = {}
	for _, pair in ipairs(counts) do
		for _ = 1, pair[2] do
			table.insert(list, pair[1])
		end
	end
	return list
end
DeckRules.expand = expand

-- The ids of the starter collection, one entry per copy (what gets granted on first join).
function DeckRules.starterGrant()
	return expand(DeckRules.StarterCards)
end

-- The deck every new player starts with in their first deck slot.
function DeckRules.starterDeck()
	return {
		name = "Starter Deck",
		hero = "bonk",
		themes = { "Snack", "Critter" },
		lanes = { "Snack", "Snack", "Critter", "Critter" },
		cards = expand(DeckRules.StarterCards),
	}
end

---------------------------------------------------------------------------
-- Checking a deck
---------------------------------------------------------------------------

local function isFamily(f)
	return type(f) == "string" and CardData.Terrains[f] ~= nil
end
DeckRules.isFamily = isFamily

-- Cards a player can put in a deck at all (no tokens like Ghost, Pigeon or Scrap).
function DeckRules.collectible(id)
	local d = type(id) == "string" and CardData.Cards[id]
	return d ~= nil and d ~= false and not d.token
end

function DeckRules.copyLimit(id)
	local d = CardData.Cards[id]
	return (d and DeckRules.MaxCopiesByRarity[d.rarity]) or DeckRules.MaxCopies
end

-- Does card `id` fit a deck with these themes? ("Any" cards fit every deck.)
function DeckRules.fits(id, themes)
	local d = CardData.Cards[id]
	if not d or d.token then
		return false
	end
	if d.family == "Any" then
		return true
	end
	return table.find(themes, d.family) ~= nil
end

-- { [id] = copies } for a list of ids.
function DeckRules.counts(cards)
	local n = {}
	for _, id in ipairs(cards) do
		n[id] = (n[id] or 0) + 1
	end
	return n
end

-- The families a list of cards uses (not counting "Any"), in CardData.Families order.
function DeckRules.familiesUsed(cards)
	local seen = {}
	for _, id in ipairs(cards) do
		local d = CardData.Cards[id]
		if d and d.family ~= "Any" then
			seen[d.family] = true
		end
	end
	local out = {}
	for _, f in ipairs(CardData.Families) do
		if seen[f] then
			table.insert(out, f)
		end
	end
	return out
end

-- Four lanes that only use the deck's themes: keeps the lanes given where they fit and fills
-- the rest by splitting the lanes between the themes (2 themes: 2 lanes each).
function DeckRules.fixLanes(themes, lanes)
	local out = {}
	local n = #themes
	for i = 1, CardData.Cols do
		local want = type(lanes) == "table" and lanes[i] or nil
		if n > 0 and table.find(themes, want) then
			out[i] = want
		elseif n > 0 then
			out[i] = themes[math.min(n, math.floor((i - 1) * n / CardData.Cols) + 1)]
		end
	end
	return out
end

-- Turns whatever a client sent into a clean deck table (or nil if it isn't one at all).
-- Unknown cards, families and heroes are dropped here; validate() then says what is wrong.
function DeckRules.sanitize(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local deck = { cards = {}, themes = {}, lanes = {} }
	local name = type(raw.name) == "string" and raw.name or ""
	name = string.gsub(name, "[%c]", "")
	name = string.match(name, "^%s*(.-)%s*$") or ""
	if #name > DeckRules.MaxNameLength then
		name = string.sub(name, 1, DeckRules.MaxNameLength)
	end
	deck.name = name ~= "" and name or "My Deck"
	deck.hero = (type(raw.hero) == "string" and table.find(DeckRules.Heroes, raw.hero)) and raw.hero or DeckRules.Heroes[1]
	if type(raw.themes) == "table" then
		for i = 1, math.min(#raw.themes, 6) do
			local f = raw.themes[i]
			if isFamily(f) and not table.find(deck.themes, f) then
				table.insert(deck.themes, f)
			end
		end
	end
	if type(raw.cards) == "table" then
		for i = 1, math.min(#raw.cards, DeckRules.MaxCards + 10) do
			local id = raw.cards[i]
			if DeckRules.collectible(id) then
				table.insert(deck.cards, id)
			end
		end
	end
	if type(raw.lanes) == "table" then
		for i = 1, CardData.Cols do
			deck.lanes[i] = isFamily(raw.lanes[i]) and raw.lanes[i] or nil
		end
	end
	return deck
end

-- Checks a deck against the rules, and against the player's collection when `owned`
-- ({ [id] = copies }) is given. Returns ok, problems (a list of short sentences).
function DeckRules.validate(deck, owned)
	local problems = {}
	local function add(text)
		table.insert(problems, text)
	end
	if type(deck) ~= "table" or type(deck.cards) ~= "table" or type(deck.themes) ~= "table" then
		return false, { "That isn't a deck" }
	end
	local themes = deck.themes
	if #themes == 0 then
		add("Pick a theme")
	elseif #themes > DeckRules.MaxThemes then
		add("Pick at most " .. DeckRules.MaxThemes .. " themes")
	end
	local n = #deck.cards
	if n < DeckRules.MinCards then
		add("Add " .. (DeckRules.MinCards - n) .. " more card" .. (DeckRules.MinCards - n == 1 and "" or "s") .. " (at least " .. DeckRules.MinCards .. ")")
	elseif n > DeckRules.MaxCards then
		add("Take out " .. (n - DeckRules.MaxCards) .. " card" .. (n - DeckRules.MaxCards == 1 and "" or "s") .. " (at most " .. DeckRules.MaxCards .. ")")
	end
	local counts = DeckRules.counts(deck.cards)
	local offTheme, tooMany, notOwned = {}, {}, {}
	for _, id in ipairs(CardData.List) do
		local c = counts[id]
		if c then
			local d = CardData.Cards[id]
			if not DeckRules.fits(id, themes) then
				table.insert(offTheme, d.name)
			end
			if c > DeckRules.copyLimit(id) then
				table.insert(tooMany, d.name)
			end
			if owned and c > (owned[id] or 0) then
				table.insert(notOwned, d.name)
			end
		end
	end
	for id in pairs(counts) do
		if not DeckRules.collectible(id) then
			add("Unknown card: " .. tostring(id))
		end
	end
	if #offTheme > 0 then
		add("Not in this deck's themes: " .. table.concat(offTheme, ", "))
	end
	if #tooMany > 0 then
		add("Too many copies (3 at most, 1 of each Legendary and Secret): " .. table.concat(tooMany, ", "))
	end
	if #notOwned > 0 then
		add("You don't own enough of: " .. table.concat(notOwned, ", "))
	end
	if type(deck.lanes) ~= "table" then
		add("Pick the terrain of your 4 lanes")
	else
		for i = 1, CardData.Cols do
			if not table.find(themes, deck.lanes[i]) then
				add("Each lane's terrain must be one of the deck's themes")
				break
			end
		end
	end
	if not table.find(DeckRules.Heroes, deck.hero) then
		add("Pick a hero")
	end
	return #problems == 0, problems
end

---------------------------------------------------------------------------
-- From a deck to a match
---------------------------------------------------------------------------

-- What MatchEngine.new wants for this deck (a built deck or one of the practice decks).
function DeckRules.setupFor(deck)
	local themes = (type(deck.themes) == "table" and #deck.themes > 0) and table.clone(deck.themes) or { deck.family }
	return {
		deck = table.clone(deck.cards),
		hero = deck.hero,
		family = themes[1],
		themes = themes,
		lanes = DeckRules.fixLanes(themes, deck.lanes),
	}
end

-- A practice deck (StarterDecks) in the same shape as a built deck.
function DeckRules.fromPractice(practice)
	return {
		name = practice.name,
		hero = practice.hero,
		themes = { practice.family },
		lanes = DeckRules.fixLanes({ practice.family }, nil),
		cards = table.clone(practice.cards),
	}
end

-- Fills a deck up to MinCards from the owned cards that fit, cheapest creatures first, then
-- spells and buildings. Used by the deck builder's "Fill up" button. Returns the new card list.
function DeckRules.autoFill(deck, owned, target)
	target = target or DeckRules.MinCards
	local cards = table.clone(deck.cards)
	local counts = DeckRules.counts(cards)
	local pool = {}
	for _, id in ipairs(CardData.List) do
		if DeckRules.fits(id, deck.themes) and (owned[id] or 0) > 0 then
			table.insert(pool, id)
		end
	end
	local function rank(id)
		local d = CardData.Cards[id]
		local typeRank = d.type == "Creature" and 0 or (d.type == "Spell" and 1 or 2)
		return typeRank * 100 + d.cost
	end
	table.sort(pool, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)
	local added = true
	while #cards < target and added do
		added = false
		for _, id in ipairs(pool) do
			if #cards >= target then
				break
			end
			local have = counts[id] or 0
			if have < DeckRules.copyLimit(id) and have < (owned[id] or 0) then
				table.insert(cards, id)
				counts[id] = have + 1
				added = true
			end
		end
	end
	return cards
end

return DeckRules

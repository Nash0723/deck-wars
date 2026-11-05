-- The Campaign: 7 worlds x 6 acts on the Duel Table, each inside its own world (Backdrops).
--
-- Every number for the Campaign lives in this file: worlds, opponents, bosses, rules, stars,
-- rewards, drops and the hourly Challenge. The server (MatchServer + CampaignData) and the
-- screen (CampaignUI) both read it, so the screen always shows what the server will do.
--
-- A stage is named by a string id:
--   "<world>:<act>:N"  Normal mode   (e.g. "Candy:3:N")
--   "<world>:<act>:H"  Hard mode
--   "Challenge:<hour>" this hour's Challenge (hour = os.time() // 3600)

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end
local CardData = req("CardData")
local StarterDecks = req("StarterDecks")

local Campaign = {}

Campaign.Acts = 6 -- act 6 is the boss
Campaign.HeroHp = CardData.HeroMaxHp -- the enemy's hit points unless a rule changes it

---------------------------------------------------------------------------
-- Rules (a stage has 0 to 3). Each one is applied by MatchServer when the match starts.
---------------------------------------------------------------------------

Campaign.Rules = {
	thickSkin = { name = "Thick Skin", text = "The enemy hero has 5 more hit points.", emoji = "🛡", enemyHp = 5 },
	tough = { name = "Tough", text = "The enemy hero has 10 more hit points.", emoji = "💪", enemyHp = 10 },
	quickDraw = { name = "Quick Draw", text = "The enemy starts with 1 extra card.", emoji = "🃏", extraCards = 1 },
	headStart = { name = "Head Start", text = "The enemy starts with 2 extra cards.", emoji = "🃏", extraCards = 2 },
	surge = { name = "Surge", text = "The enemy gets 1 extra magic every turn.", emoji = "✨", magicBonus = 1 },
	homeTurf = { name = "Home Turf", text = "Your lanes take the enemy's landscape, so only its family gets the home bonus.", emoji = "🏞", homeTurf = true },
	rush = { name = "Rush", text = "Your turns last 45 seconds.", emoji = "⏱", turnSeconds = 45 },
	bigStart = { name = "Big Start", text = "The enemy's Big Move is ready from the first turn.", emoji = "★", bigStart = true },
}
-- Rules the hourly Challenge can roll (two different ones).
Campaign.ChallengeRules = { "thickSkin", "quickDraw", "surge", "homeTurf", "rush", "bigStart" }

---------------------------------------------------------------------------
-- Worlds, in the order they open. `backdrop` is the Backdrops key; `family` is the deck the
-- opponents play (nil = a different themed deck each act); acts 1-5 are the opponents' names.
---------------------------------------------------------------------------

Campaign.Worlds = {
	{
		key = "Den",
		name = "Card Den",
		emoji = "🏠",
		backdrop = "Room",
		family = nil,
		blurb = "Your own room. A gentle start against the regulars of the Den.",
		title = "Den Graduate",
		opponents = { "Practice Pip", "Shuffle Sprout", "Dice Goblin", "Table Tidy", "Lamp Lurker" },
		decks = { "Snack", "Critter", "Weather", "Junk", "Robo", "Spooky" }, -- one per act
		difficulty = { "Easy", "Easy", "Easy", "Easy", "Medium", "Medium" },
		boss = { name = "Bot Bonkers", card = nil, rules = {} },
		tiers = { "basic", "basic", "basic", "basic", "normal", "normal" }, -- (the starter deck must keep up)
	},
	{
		key = "Candy",
		name = "Gumdrop Plaza",
		emoji = "🍬",
		backdrop = "Candy",
		family = "Snack",
		blurb = "Peppermint streets and gumdrop hills. The Snacks heal up and outlast you.",
		title = "Gumdrop Champion",
		opponents = { "Gumdrop Guard", "Licorice Lasso", "Toffee Tumbler", "Sherbet Sergeant", "Caramel Colonel" },
		boss = { name = "Queen Parfait", card = "queen_parfait", rules = { "tough" } },
	},
	{
		key = "Meadow",
		name = "Sunset Grasslands",
		emoji = "🌄",
		backdrop = "Meadow",
		family = "Critter",
		blurb = "Wildflower hills at sunset. Critters come in packs and grow side by side.",
		title = "Grassland Ranger",
		opponents = { "Burrow Scout", "Meadow Mole", "Firefly Flock", "Thicket Badger", "Antler Elder" },
		boss = { name = "Big Momma Moose", card = "big_momma_moose", rules = { "headStart" } },
	},
	{
		key = "Ice",
		name = "Frostglass Lake",
		emoji = "❄️",
		backdrop = "Ice",
		family = "Weather",
		blurb = "A frozen lake under the northern lights. Weather Soaks you, then Zaps you.",
		title = "Frostglass Warden",
		opponents = { "Drizzle Kid", "Sleet Skater", "Frost Hound", "Hail Warden", "Aurora Seer" },
		boss = { name = "Stormlord Nimbus", card = "stormlord_nimbus", rules = { "thickSkin" } },
	},
	{
		key = "Fire",
		name = "Ember Caldera",
		emoji = "🌋",
		backdrop = "Fire",
		family = "Junk",
		blurb = "Lava rivers and smoking volcanoes. Junk falls apart and comes back bigger.",
		title = "Caldera Breaker",
		opponents = { "Scrap Rat", "Cinder Tinker", "Slag Golem", "Furnace Foreman", "Magma Mechanic" },
		boss = { name = "The Junk King", card = "the_junk_king", rules = { "thickSkin" } },
		turnBonus = 1, -- (these decks play longer games)
	},
	{
		key = "Space",
		name = "Cosmic Void",
		emoji = "🌌",
		backdrop = "Space",
		family = "Robo",
		blurb = "A floating asteroid among the planets. Robos charge up and hit hard.",
		title = "Void Walker",
		opponents = { "Toaster Cadet", "Orbit Drone", "Comet Courier", "Satellite Sentinel", "Nebula Captain" },
		boss = { name = "Mega Blender Prime", card = "mega_blender_prime", rules = { "surge", "tough" } },
		turnBonus = 1, -- (these decks play longer games)
	},
	{
		key = "Mall",
		name = "Midnight Mall",
		emoji = "🌙",
		backdrop = "Mall",
		family = "Spooky",
		blurb = "A mall that never closes. The Spooky ones don't stay gone.",
		title = "Mall Legend",
		opponents = { "Lost Shopper", "Cart Phantom", "Food Court Ghoul", "Night Janitor", "Window Wraith" },
		boss = { name = "The Mannequin Duke", card = "the_mannequin_duke", rules = { "headStart", "tough", "homeTurf" } },
		turnBonus = 1, -- (these decks play longer games)
	},
}
Campaign.WorldByKey = {}
for i, w in ipairs(Campaign.Worlds) do
	w.index = i
	Campaign.WorldByKey[w.key] = w
end

-- Opponent strength per act (worlds without their own list).
Campaign.Difficulty = { "Easy", "Easy", "Medium", "Medium", "Hard", "Hard" }
-- One light rule on acts 2 and 4.
Campaign.ActRules = { [2] = { "quickDraw" }, [4] = { "thickSkin" } }
-- What the opponents' decks hold, by act: "basic" (no Epic or better), "normal" (no Legendary
-- or Secret), "full" (the whole themed deck), "boss" (full, plus the boss's Legendary twice).
Campaign.DeckTier = { "basic", "basic", "normal", "normal", "full", "boss" }
-- Hard mode: every act one step up; a Hard bot that can't go higher gets Thick Skin instead,
-- and the boss gets Big Start on top of its own rules.
Campaign.HardStep = { Easy = "Medium", Medium = "Hard", Hard = "Hard" }
Campaign.HardBossRule = "bigStart"

---------------------------------------------------------------------------
-- Stars and rewards
---------------------------------------------------------------------------

-- Star 1: win. Star 2: win with your hero at HealthyShare of its hit points or more.
-- Star 3: win within the stage's turn limit (your own turns).
Campaign.HealthyShare = 0.5
-- The third star: win within this many of your own turns (per act; +world.turnBonus, +1 on Hard).
-- Set from the balance run (bal/campaign_balance.luau): about half the wins make it.
Campaign.TurnLimit = { 6, 6, 7, 7, 8, 9 }
Campaign.HardTurnBonus = 1
Campaign.StarText = { "Win", "Win with half your hit points left", "Win within %d of your turns" }

-- First clear, in Gems, by act (Hard pays HardGems times as much, rounded).
Campaign.FirstClearGems = { 30, 35, 45, 55, 70, 100 }
Campaign.HardGems = 1.5
-- The card a first clear gives, by act: a card of that rarity from the opponents' family.
-- On Hard every act gives one step rarer, and the boss gives its own Legendary.
Campaign.FirstClearRarity = { "Common", "Common", "Rare", "Rare", "Epic", "Mythic" }
-- Replays (a stage you've cleared before): a chance at a family card, Common or Rare.
Campaign.ReplayDropChance = 0.25
Campaign.ReplayRareShare = 0.25 -- of those drops, how many are Rare (the rest Common)
Campaign.BossLegendaryChance = 0.02 -- a Normal boss replay can drop the boss's Legendary
Campaign.DropsPerDay = 10 -- most replay drops a player gets in a day (UTC)
-- Star chests per world: stars from Normal and Hard together.
Campaign.Chests = {
	{ stars = 6, gems = 50 },
	{ stars = 12, gems = 100, rarity = "Epic" },
	{ stars = 18, gems = 150, title = true },
}

-- The hourly Challenge.
Campaign.Challenge = {
	unlockAfter = "Den:6:N", -- open once this stage is cleared
	difficulty = "Hard",
	tier = "full",
	gems = 60,
	cardOdds = { { "Rare", 70 }, { "Epic", 25 }, { "Mythic", 5 } },
	turnLimit = 9,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local RANK = {}
for i, r in ipairs(CardData.Rarities) do
	RANK[r] = i
end
Campaign.RarityRank = RANK

local function collectible(id)
	local c = CardData.Cards[id]
	return c and not c.token
end

-- Every collectible card of a family and rarity, sorted by id (so picks are stable).
function Campaign.cardsOf(family, rarity)
	local out = {}
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if collectible(id) and c.family == family and c.rarity == rarity then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- A card of `family` and `rarity` (or the nearest rarer one the family has, then the nearest
-- commoner one), picked by `index` so the same stage always gives the same card.
function Campaign.pickCard(family, rarity, index)
	local start = RANK[rarity] or 1
	local order = {}
	for r = start, #CardData.Rarities do
		table.insert(order, CardData.Rarities[r])
	end
	for r = start - 1, 1, -1 do
		table.insert(order, CardData.Rarities[r])
	end
	for _, rr in ipairs(order) do
		local list = Campaign.cardsOf(family, rr)
		if #list > 0 then
			return list[((index or 1) - 1) % #list + 1]
		end
	end
	return nil
end

function Campaign.stageId(worldKey, act, hard)
	return worldKey .. ":" .. tostring(act) .. ":" .. (hard and "H" or "N")
end

-- "Candy:3:N" -> world, act, hard. nil for anything else.
function Campaign.parseId(id)
	if type(id) ~= "string" then
		return nil
	end
	local w, a, m = string.match(id, "^(%a+):(%d):([NH])$")
	local world = w and Campaign.WorldByKey[w]
	local act = tonumber(a)
	if not world or not act or act < 1 or act > Campaign.Acts then
		return nil
	end
	return world, act, m == "H"
end

function Campaign.challengeHour(now)
	return math.floor((now or os.time()) / 3600)
end

-- A small deterministic number generator (the same stage plays the same everywhere).
local function lcg(seed)
	local s = math.floor(seed) % 2147483647
	if s <= 0 then
		s = 1
	end
	return function(n)
		s = (s * 48271) % 2147483647
		return s % n + 1
	end
end

---------------------------------------------------------------------------
-- Opponent decks
---------------------------------------------------------------------------

-- The opponents' deck for a family and a tier (see Campaign.DeckTier). 30 cards.
function Campaign.enemyCards(family, tier, bossCard)
	local practice = StarterDecks[family]
	assert(practice, "no themed deck for " .. tostring(family))
	local cards = table.clone(practice.cards)
	local cap = (tier == "basic" and RANK.Rare) or (tier == "normal" and RANK.Mythic) or #CardData.Rarities
	-- Anything above the cap is swapped for a Common or Rare creature of the family, the ones the
	-- deck holds fewest of first, so no card ends up more than a few times.
	local counts = {}
	for _, id in ipairs(cards) do
		if (RANK[CardData.Cards[id].rarity] or 1) <= cap then
			counts[id] = (counts[id] or 0) + 1
		end
	end
	local pool = {}
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if collectible(id) and c.type == "Creature" and c.family == family and (RANK[c.rarity] or 1) <= math.min(cap, RANK.Rare) then
			table.insert(pool, id)
		end
	end
	table.sort(pool)
	for i, id in ipairs(cards) do
		if (RANK[CardData.Cards[id].rarity] or 1) > cap and #pool > 0 then
			local best = pool[1]
			for _, p in ipairs(pool) do
				local cp, cb = counts[p] or 0, counts[best] or 0
				if cp < cb or (cp == cb and CardData.Cards[p].cost < CardData.Cards[best].cost) then
					best = p
				end
			end
			cards[i] = best
			counts[best] = (counts[best] or 0) + 1
		end
	end
	if tier == "boss" and bossCard and CardData.Cards[bossCard] then
		-- the boss's Legendary twice: it replaces the two cheapest non-creature cards (or the cheapest cards)
		local have = 0
		for _, id in ipairs(cards) do
			if id == bossCard then
				have += 1
			end
		end
		local order = {}
		for i, id in ipairs(cards) do
			if id ~= bossCard then
				table.insert(order, i)
			end
		end
		table.sort(order, function(a, b)
			local ca, cb = CardData.Cards[cards[a]], CardData.Cards[cards[b]]
			local sa = ca.type == "Creature" and 1 or 0
			local sb = cb.type == "Creature" and 1 or 0
			if sa ~= sb then
				return sa < sb
			end
			if ca.cost ~= cb.cost then
				return ca.cost < cb.cost
			end
			return a < b
		end)
		local k = 1
		while have < 2 and order[k] do
			cards[order[k]] = bossCard
			have += 1
			k += 1
		end
	end
	return cards
end

---------------------------------------------------------------------------
-- Stages
---------------------------------------------------------------------------

local function addRule(list, id)
	for _, r in ipairs(list) do
		if r == id then
			return
		end
	end
	table.insert(list, id)
end

-- Everything about one stage: { id, world, act, hard, boss, name, title, difficulty, family,
-- hero, cards, rules, enemyHp, turnLimit, backdrop, firstGems, firstCard, bossCard }.
-- Returns nil for an unknown id. `now` is only used for the Challenge.
function Campaign.stage(id, now)
	if type(id) == "string" and string.sub(id, 1, 10) == "Challenge:" then
		return Campaign.challenge(tonumber(string.sub(id, 11)))
	end
	local world, act, hard = Campaign.parseId(id)
	if not world then
		return nil
	end
	local boss = act == Campaign.Acts
	local family = world.family or (world.decks and world.decks[act]) or "Snack"
	local difficulty = (world.difficulty and world.difficulty[act]) or Campaign.Difficulty[act]
	local rules = {}
	for _, r in ipairs(Campaign.ActRules[act] or {}) do
		addRule(rules, r)
	end
	if boss then
		for _, r in ipairs(world.boss.rules or {}) do
			addRule(rules, r)
		end
	end
	if hard then
		if difficulty == "Hard" and not boss then
			addRule(rules, "thickSkin")
		end
		difficulty = Campaign.HardStep[difficulty] or difficulty
		if boss then
			addRule(rules, Campaign.HardBossRule)
		end
	end
	local tier = (world.tiers and world.tiers[act]) or Campaign.DeckTier[act]
	local bossCard = boss and world.boss.card or nil
	if tier == "boss" and not bossCard then
		tier = "full"
	end
	if world.key == "Den" and tier == "full" then
		tier = "normal" -- the tutorial world never shows a Legendary
	end
	local enemyHp = Campaign.HeroHp
	for _, r in ipairs(rules) do
		enemyHp += Campaign.Rules[r].enemyHp or 0
	end
	-- the card a first clear gives
	local rarity = Campaign.FirstClearRarity[act]
	if hard then
		rarity = CardData.Rarities[math.min(RANK.Mythic, RANK[rarity] + 1)]
	end
	local firstCard
	if hard and boss and bossCard then
		firstCard = bossCard
	else
		firstCard = Campaign.pickCard(family, rarity, world.index * 7 + act)
	end
	local firstGems = Campaign.FirstClearGems[act]
	if hard then
		firstGems = math.floor(firstGems * Campaign.HardGems + 0.5)
	end
	local practice = StarterDecks[family]
	local name = boss and world.boss.name or world.opponents[act]
	return {
		id = Campaign.stageId(world.key, act, hard),
		world = world.key,
		worldName = world.name,
		act = act,
		hard = hard,
		boss = boss,
		name = name,
		title = world.name .. " · Act " .. act .. (boss and " · Boss" or "") .. (hard and " · Hard" or ""),
		difficulty = difficulty,
		family = family,
		hero = practice and practice.hero or "bonk",
		tier = tier,
		cards = Campaign.enemyCards(family, tier, bossCard),
		bossCard = bossCard,
		rules = rules,
		enemyHp = enemyHp,
		turnLimit = Campaign.TurnLimit[act] + (world.turnBonus or 0) + (hard and Campaign.HardTurnBonus or 0),
		backdrop = world.backdrop,
		firstGems = firstGems,
		firstCard = firstCard,
	}
end

-- This hour's Challenge: a stage from one of the 6 family worlds at full strength with two
-- random rules. Everyone in every server gets the same one in the same hour.
function Campaign.challenge(hour)
	hour = hour or Campaign.challengeHour()
	local roll = lcg(hour * 7919 + 17)
	local worlds = {}
	for _, w in ipairs(Campaign.Worlds) do
		if w.family then
			table.insert(worlds, w)
		end
	end
	local world = worlds[roll(#worlds)]
	local pool = table.clone(Campaign.ChallengeRules)
	local rules = {}
	for _ = 1, 2 do
		local i = roll(#pool)
		table.insert(rules, pool[i])
		table.remove(pool, i)
	end
	local enemyHp = Campaign.HeroHp
	for _, r in ipairs(rules) do
		enemyHp += Campaign.Rules[r].enemyHp or 0
	end
	local C = Campaign.Challenge
	local practice = StarterDecks[world.family]
	return {
		id = "Challenge:" .. hour,
		challenge = true,
		hour = hour,
		world = world.key,
		worldName = world.name,
		act = 5,
		hard = false,
		boss = false,
		name = world.opponents[5] .. "'s Challenge",
		title = "Challenge · " .. world.name,
		difficulty = C.difficulty,
		family = world.family,
		hero = practice.hero,
		tier = C.tier,
		cards = Campaign.enemyCards(world.family, C.tier, nil),
		rules = rules,
		enemyHp = enemyHp,
		turnLimit = C.turnLimit,
		backdrop = world.backdrop,
		firstGems = C.gems,
		firstCard = nil, -- a random card (Campaign.Challenge.cardOdds), rolled by the server
	}
end

-- The text of each star for a stage.
function Campaign.starTexts(stage)
	return { Campaign.StarText[1], Campaign.StarText[2], string.format(Campaign.StarText[3], stage.turnLimit) }
end

-- Which stars a finished match earns: { bool, bool, bool }.
-- r = { result = "win"/"loss"/"draw", hp = your hero's hit points at the end, maxHp, turns = your turns }
function Campaign.starsFor(stage, r)
	if r.result ~= "win" then
		return { false, false, false }
	end
	local maxHp = math.max(1, tonumber(r.maxHp) or Campaign.HeroHp)
	return {
		true,
		(tonumber(r.hp) or 0) >= math.ceil(maxHp * Campaign.HealthyShare),
		(tonumber(r.turns) or 999) <= stage.turnLimit,
	}
end

function Campaign.countStars(mask)
	local n = 0
	for _, b in ipairs({ 1, 2, 4 }) do
		if bit32.band(mask or 0, b) ~= 0 then
			n += 1
		end
	end
	return n
end

function Campaign.maskOf(stars)
	local m = 0
	for i, on in ipairs(stars) do
		if on then
			m = bit32.bor(m, bit32.lshift(1, i - 1))
		end
	end
	return m
end

---------------------------------------------------------------------------
-- Progress (the save's `campaign` table: { clears = { [stageId] = { stars = mask, wins = n } },
-- chests = { ["<world>:<n>"] = true }, ... }). These only read it.
---------------------------------------------------------------------------

function Campaign.cleared(save, id)
	local c = save and save.clears and save.clears[id]
	return c ~= nil and (c.wins or 0) > 0
end

function Campaign.worldUnlocked(save, worldKey)
	local w = Campaign.WorldByKey[worldKey]
	if not w then
		return false
	end
	if w.index == 1 then
		return true
	end
	local prev = Campaign.Worlds[w.index - 1]
	return Campaign.cleared(save, Campaign.stageId(prev.key, Campaign.Acts, false))
end

function Campaign.hardUnlocked(save, worldKey)
	return Campaign.cleared(save, Campaign.stageId(worldKey, Campaign.Acts, false))
end

-- Puts a stage's rules on a match that has just started (MatchEngine), for the opponent in seat
-- `enemySeat`: its hit points, extra cards, extra magic and a charged Big Move. Returns the shortest
-- turn time (seconds) a rule asks for, or nil. Home Turf is in the lanes, set before the match.
function Campaign.applyRules(m, stage, enemySeat)
	local es = m.seats[enemySeat]
	if not es then
		return nil
	end
	m.teams[es.team].hp = stage.enemyHp
	m.teams[es.team].maxHp = stage.enemyHp
	local seconds = nil
	for _, ruleId in ipairs(stage.rules or {}) do
		local rule = Campaign.Rules[ruleId]
		if rule then
			for _ = 1, rule.extraCards or 0 do
				m:draw(enemySeat)
			end
			if rule.magicBonus then
				es.magicBonus = (es.magicBonus or 0) + rule.magicBonus
				if m.current == enemySeat then
					es.magic += rule.magicBonus -- its first turn already started
				end
			end
			if rule.bigStart then
				es.dealt = math.max(es.dealt or 0, CardData.BigMoveCharge or 10)
			end
			if rule.turnSeconds then
				seconds = math.min(seconds or math.huge, rule.turnSeconds)
			end
		end
	end
	return seconds
end

-- Can this stage be played? Returns true, or false and why.
function Campaign.canPlay(save, id, now)
	if type(id) == "string" and string.sub(id, 1, 10) == "Challenge:" then
		local hour = tonumber(string.sub(id, 11))
		if hour ~= Campaign.challengeHour(now) then
			return false, "That Challenge is over. A new one starts every hour."
		end
		if not Campaign.cleared(save, Campaign.Challenge.unlockAfter) then
			return false, "Beat the Card Den boss to open the Challenge."
		end
		return true
	end
	local world, act, hard = Campaign.parseId(id)
	if not world then
		return false, "Unknown stage."
	end
	if not Campaign.worldUnlocked(save, world.key) then
		return false, "Beat the boss of the world before to open " .. world.name .. "."
	end
	if hard and not Campaign.hardUnlocked(save, world.key) then
		return false, "Beat " .. world.name .. "'s boss to open Hard mode."
	end
	if act > 1 and not Campaign.cleared(save, Campaign.stageId(world.key, act - 1, hard)) then
		return false, "Beat act " .. (act - 1) .. " first."
	end
	return true
end

-- Stars in a world (Normal and Hard together) and in the whole Campaign.
function Campaign.worldStars(save, worldKey)
	local n = 0
	for act = 1, Campaign.Acts do
		for _, hard in ipairs({ false, true }) do
			local c = save and save.clears and save.clears[Campaign.stageId(worldKey, act, hard)]
			n += c and Campaign.countStars(c.stars) or 0
		end
	end
	return n
end

function Campaign.totalStars(save)
	local n = 0
	for _, w in ipairs(Campaign.Worlds) do
		n += Campaign.worldStars(save, w.key)
	end
	return n
end

Campaign.MaxStars = #Campaign.Worlds * Campaign.Acts * 3 * 2

-- What a world's star chest n holds: { stars, gems, card (id or nil), title (or nil) }.
function Campaign.chest(worldKey, n)
	local w = Campaign.WorldByKey[worldKey]
	local def = Campaign.Chests[n]
	if not (w and def) then
		return nil
	end
	local family = w.family or "Critter"
	return {
		stars = def.stars,
		gems = def.gems,
		card = def.rarity and Campaign.pickCard(family, def.rarity, w.index * 3 + n) or nil,
		title = def.title and w.title or nil,
	}
end

-- The titles a save has earned from star chests.
function Campaign.titles(save)
	local out = {}
	for _, w in ipairs(Campaign.Worlds) do
		for n, def in ipairs(Campaign.Chests) do
			if def.title and save and save.chests and save.chests[w.key .. ":" .. n] then
				table.insert(out, w.title)
			end
		end
	end
	return out
end

return Campaign

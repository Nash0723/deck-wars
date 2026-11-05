-- Deck Wars shop catalog and economy numbers. Shared: the server uses it to charge and grant,
-- the Shop screen uses it to draw prices. Only the server's copy counts (EconomyManager checks
-- every price itself), so editing this on a client changes nothing.
--
-- Two currencies:
--   Gems  = premium / gacha currency. Spent on card packs (and a few premium cosmetics/boosts).
--           Bought with Robux (Gem bundles), earned slowly (daily login, first win, level ups,
--           a daily-limited Coin exchange).
--   Coins = earned by playing. Spent in the Shop: daily cards, deck slots, cosmetics, boosters.
--
-- Change prices here. Every price is a whole number. If you add an item, give it a unique id.

local function req(name)
	if script then
		local own = script.Parent:FindFirstChild(name)
		if own then
			return require(own)
		end
	end
	return require(name)
end

local CardData = req("CardData")
local Rng = req("Rng")

local ShopCatalog = {}

ShopCatalog.Currencies = { "Gems", "Coins" }
ShopCatalog.Icon = { Gems = "💎", Coins = "🪙" }
ShopCatalog.Color = { Gems = { 110, 200, 255 }, Coins = { 255, 200, 70 } }
ShopCatalog.MaxBalance = 999999999

---------------------------------------------------------------------------
-- Starting money, daily login, match rewards, levels
---------------------------------------------------------------------------

-- What a brand new player starts with (enough for a couple of packs and a first shop visit).
ShopCatalog.StartingGems = 300
ShopCatalog.StartingCoins = 500

-- Daily login, once per UTC day. The streak grows when you come back the next day (up to 7),
-- and resets if you skip a day. Day 7 of a streak adds the bonus Gems.
ShopCatalog.Daily = {
	coins = 150,
	coinsPerStreakDay = 25, -- day 1: 150, day 2: 175 ... day 7: 300
	gems = 15,
	maxStreak = 7,
	streakBonusGems = 60, -- on day 7 (and every day after while the streak holds at 7)
}

-- Bot match rewards. A match only pays if it was a real game: it lasted MinSeconds and you
-- took MinTurns turns (no rewards for leaving). Draws pay like a loss.
ShopCatalog.Match = {
	winCoins = { Easy = 60, Medium = 100, Hard = 160 },
	lossCoins = { Easy = 20, Medium = 30, Hard = 45 },
	winXp = { Easy = 40, Medium = 60, Hard = 90 },
	lossXp = { Easy = 15, Medium = 25, Hard = 35 },
	firstWinGems = 30, -- first win of the UTC day, any difficulty
	minSeconds = 60,
	minTurns = 3,
	maxPaidPerDay = 30, -- matches that pay per UTC day (stops farming bots all night)
	-- Gems for a win (the friend's rates), on top of the Coins above. A win against people pays
	-- pvpWinGems; with a bot on the other side it pays like that bot (so Easy bots don't farm).
	winGems = { Easy = 20, Medium = 35, Hard = 50 },
	pvpWinGems = 40,
	-- Cup (tournament) prizes when at least two real players entered.
	cupWinGems = 150,
	cupRunnerUpGems = 50,
}

-- XP needed to go from `level` to level + 1.
function ShopCatalog.xpForLevel(level: number): number
	return 100 + 25 * (math.max(1, level) - 1)
end
ShopCatalog.LevelUpGems = 40
ShopCatalog.LevelUpCoins = 100
ShopCatalog.MaxLevel = 200

---------------------------------------------------------------------------
-- Tab 1: Daily Card Rotation (single cards for Coins)
---------------------------------------------------------------------------

-- Every UTC day the shop shows these slots (same cards for everyone that day). Each slot can be
-- bought once per day. Legendary and Secret cards only come from packs.
ShopCatalog.DailySlots = { "Common", "Common", "Rare", "Rare", "Epic", "Mythic" }
ShopCatalog.CardPrice = { Common = 120, Rare = 350, Epic = 900, Mythic = 2400 }
ShopCatalog.DailySeed = 7351 -- change to reshuffle every future rotation

-- The UTC day number for a Unix time (days since 1 Jan 1970).
function ShopCatalog.dayNumber(unixTime: number): number
	return math.floor(unixTime / 86400)
end

-- Seconds until the next UTC midnight (when the rotation and daily limits reset).
function ShopCatalog.secondsToReset(unixTime: number): number
	return 86400 - (math.floor(unixTime) % 86400)
end

-- Cards that the shop may sell, by rarity (tokens left out), sorted so every server agrees.
local sellable = {}
do
	for _, r in ipairs(CardData.Rarities) do
		sellable[r] = {}
	end
	local ids = {}
	for id, def in pairs(CardData.Cards) do
		if not def.token and sellable[def.rarity] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		table.insert(sellable[CardData.Cards[id].rarity], id)
	end
end
ShopCatalog.Sellable = sellable

-- The day's rotation: { { slot = 1, id = cardId, rarity = "Common", price = 120 }, ... }.
-- The same day always gives the same cards, and no card shows twice in one day.
function ShopCatalog.dailyCards(day: number)
	local rng = Rng.new((day * 2654435761 + ShopCatalog.DailySeed) % 4294967296)
	-- warm up: xorshift's first numbers follow the seed closely
	for _ = 1, 4 do
		rng:next()
	end
	local out, used = {}, {}
	for slot, rarity in ipairs(ShopCatalog.DailySlots) do
		local pool = sellable[rarity] or {}
		local choices = {}
		for _, id in ipairs(pool) do
			if not used[id] then
				table.insert(choices, id)
			end
		end
		local id = rng:pick(choices)
		if id then
			used[id] = true
			table.insert(out, { slot = slot, id = id, rarity = rarity, price = ShopCatalog.CardPrice[rarity] })
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Tab 2: Deck & Field Cosmetics (and deck slots)
---------------------------------------------------------------------------

-- kind = "board" (table skin), "cardback" or "emote". price = { Coins = n } or { Gems = n };
-- default items are owned by everyone. The look of each one lives in Cosmetics.luau.
ShopCatalog.Cosmetics = {
	-- Board themes: recolor the duel table's felt, rim, board frame and inlays.
	{ id = "board_walnut", kind = "board", name = "Walnut Classic", default = true, blurb = "Dark walnut and green felt. The original table." },
	{ id = "board_midnight", kind = "board", name = "Midnight Velvet", price = { Coins = 900 }, blurb = "Deep blue velvet with silver trim." },
	{ id = "board_emerald", kind = "board", name = "Royal Emerald", price = { Coins = 900 }, blurb = "Emerald felt, black lacquer and gold." },
	{ id = "board_ember", kind = "board", name = "Ember Forge", price = { Coins = 1800 }, blurb = "Charred wood with glowing ember seams." },
	{ id = "board_frost", kind = "board", name = "Frost Glass", price = { Coins = 1800 }, blurb = "Ice-blue felt, pale birch and cold neon." },
	{ id = "board_starlight", kind = "board", name = "Starlight", price = { Gems = 350 }, blurb = "A night sky felt with glowing violet trim." },
	-- Card backs: the back of every face-down card you see (draws, the bot's hand).
	{ id = "back_indigo", kind = "cardback", name = "Classic Indigo", default = true, blurb = "The standard Deck Wars back." },
	{ id = "back_crimson", kind = "cardback", name = "Crimson Crest", price = { Coins = 600 }, blurb = "Red lacquer with a gold crest." },
	{ id = "back_jade", kind = "cardback", name = "Jade Lattice", price = { Coins = 600 }, blurb = "Green jade with a woven border." },
	{ id = "back_gold", kind = "cardback", name = "Gold Foil", price = { Coins = 1500 }, blurb = "Shiny gold foil that catches the light." },
	{ id = "back_void", kind = "cardback", name = "Void Spiral", price = { Gems = 250 }, blurb = "A slowly turning purple void." },
	-- Emotes: used from the 💬 button in a match; they pop up over your hero.
	{ id = "emote_hello", kind = "emote", name = "Hello!", icon = "👋", default = true },
	{ id = "emote_nice", kind = "emote", name = "Nice!", icon = "👍", default = true },
	{ id = "emote_haha", kind = "emote", name = "Ha ha!", icon = "😂", price = { Coins = 300 } },
	{ id = "emote_hmm", kind = "emote", name = "Hmm...", icon = "🤔", price = { Coins = 300 } },
	{ id = "emote_grr", kind = "emote", name = "Grr!", icon = "😤", price = { Coins = 300 } },
	{ id = "emote_fire", kind = "emote", name = "On fire!", icon = "🔥", price = { Coins = 700 } },
	{ id = "emote_gg", kind = "emote", name = "Good game", icon = "👑", price = { Gems = 120 } },
}
ShopCatalog.CosmeticById = {}
for i, c in ipairs(ShopCatalog.Cosmetics) do
	c.order = i
	ShopCatalog.CosmeticById[c.id] = c
end
ShopCatalog.DefaultEquipped = { board = "board_walnut", cardback = "back_indigo" }

-- Deck slots: how many saved decks you can keep.
ShopCatalog.DeckSlots = { start = 3, max = 10, price = { Coins = 600 } }

---------------------------------------------------------------------------
-- Tab 3: Currency Exchange & Boosts
---------------------------------------------------------------------------

-- Gem bundles are Roblox Developer Products (paid with Robux). Create them in the Creator
-- Dashboard (your experience > Monetization > Developer Products), then paste each product's
-- id here. A bundle with productId 0 shows as "Not on sale yet" and can't be bought.
ShopCatalog.GemBundles = {
	{ id = "gems_small", name = "Pouch of Gems", gems = 100, bonus = 0, robux = 49, productId = 0 },
	{ id = "gems_medium", name = "Sack of Gems", gems = 500, bonus = 50, robux = 229, productId = 0 },
	{ id = "gems_large", name = "Chest of Gems", gems = 1100, bonus = 200, robux = 449, productId = 0 },
	{ id = "gems_huge", name = "Vault of Gems", gems = 2400, bonus = 600, robux = 899, productId = 0 },
}
ShopCatalog.BundleById = {}
for _, b in ipairs(ShopCatalog.GemBundles) do
	ShopCatalog.BundleById[b.id] = b
end

-- Exchanges. perDay = how many times a day (nil = no limit).
ShopCatalog.Exchanges = {
	{ id = "coins_to_gems", name = "Coins → Gems", give = { Coins = 500 }, get = { Gems = 25 }, perDay = 3, blurb = "Trade play money for pack money. 3 times a day." },
	{ id = "gems_to_coins", name = "Gems → Coins", give = { Gems = 50 }, get = { Coins = 600 }, blurb = "Short on Coins? Trade some Gems." },
}
ShopCatalog.ExchangeById = {}
for _, e in ipairs(ShopCatalog.Exchanges) do
	ShopCatalog.ExchangeById[e.id] = e
end

-- Boosters.
--   luck: adds `charges` Lucky pulls. Each paid pack pull uses one; while you have charges the
--         odds of Epic and better are multiplied by LuckMultiplier (Common gives up the rest).
--   xp:   doubles the XP from matches for `minutes` (real time, it keeps counting while offline).
ShopCatalog.LuckMultiplier = 1.5
ShopCatalog.MaxLuckCharges = 50
ShopCatalog.MaxXpBoostMinutes = 24 * 60
ShopCatalog.Boosts = {
	{ id = "luck_small", kind = "luck", name = "Lucky Charm", charges = 3, price = { Coins = 2000 }, blurb = "Your next 3 pack pulls are lucky." },
	{ id = "luck_big", kind = "luck", name = "Lucky Horseshoe", charges = 10, price = { Gems = 150 }, blurb = "Your next 10 pack pulls are lucky." },
	{ id = "xp_small", kind = "xp", name = "XP Snack", minutes = 30, price = { Coins = 800 }, blurb = "Double match XP for 30 minutes." },
	{ id = "xp_big", kind = "xp", name = "XP Feast", minutes = 120, price = { Gems = 80 }, blurb = "Double match XP for 2 hours." },
}
ShopCatalog.BoostById = {}
for _, b in ipairs(ShopCatalog.Boosts) do
	ShopCatalog.BoostById[b.id] = b
end

-- A price table's single currency and amount ({ Coins = 600 } -> "Coins", 600).
function ShopCatalog.priceOf(price): (string?, number)
	if type(price) ~= "table" then
		return nil, 0
	end
	for _, cur in ipairs(ShopCatalog.Currencies) do
		if price[cur] then
			return cur, price[cur]
		end
	end
	return nil, 0
end

-- "1,234" style numbers for the screen.
function ShopCatalog.format(n: number): string
	local s = tostring(math.floor(n))
	local neg = string.sub(s, 1, 1) == "-"
	if neg then
		s = string.sub(s, 2)
	end
	local out = s
	while true do
		local k
		out, k = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then
			break
		end
	end
	return (neg and "-" or "") .. out
end

return ShopCatalog

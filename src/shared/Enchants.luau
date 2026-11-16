-- Enchants: a magic rune you put on one of your cards. Pure Luau (no Roblox parts): the server,
-- the Deck Shelf, the match engine and the match screen all use these rules.
--
-- How you get one
--   Open a card you own on the Deck Shelf and press Enchant. It costs Coins (Cost), or Gems for a
--   Lucky Enchant (LuckyCost: no Commons, better odds). The rune is rolled at random:
--     Common 46%  Rare 30%  Epic 14%  Mythic 7%  Legendary 2.5%  Secret 0.5%
--   Bad luck protection: after PityRolls enchants in a row below Epic, the next one is Epic or
--   better (the Deck Shelf shows how close you are).
--   A card holds one enchant. Enchanting a card that already has one rolls a new rune and lets
--   you choose: keep the new one or keep the old one (until you choose, you can't roll again).
--   An enchant belongs to the card, so every copy of it in every deck carries it.
--
-- What it does
--   Each rarity has its own runes (the rarer, the stronger), for creatures and for spells.
--   Buildings can't be enchanted. Like card levels, enchant powers count against bots and in the
--   Campaign; in a duel against another player the rune glows on the card but the card plays at
--   its printed numbers (InDuels), so nobody can buy a win.
--
-- What it looks like
--   Every rarity has its own colour (Colors, Palettes for LayerFx), the Secret one shifts through
--   the rainbow. EnchantFx draws the glow on cards, the aura on the table and the trigger effects.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")

local Enchants = {}

Enchants.Rarities = { "Common", "Rare", "Epic", "Mythic", "Legendary", "Secret" } -- low to high
Enchants.Rank = { Common = 1, Rare = 2, Epic = 3, Mythic = 4, Legendary = 5, Secret = 6 }
Enchants.Odds = { Common = 46, Rare = 30, Epic = 14, Mythic = 7, Legendary = 2.5, Secret = 0.5 }
Enchants.LuckyOdds = { Common = 0, Rare = 48, Epic = 30, Mythic = 14, Legendary = 6.5, Secret = 1.5 }
Enchants.Cost = { Coins = 250 }
Enchants.LuckyCost = { Gems = 60 }
Enchants.PityRolls = 8 -- this many below Epic in a row, and the next one is Epic or better
Enchants.InDuels = false -- do enchant powers count in matches against other players?

local function rgb(r, g, b)
	return { r, g, b }
end

-- One colour per rarity for the cards and the screens ({ r, g, b }); Secret cycles through Rainbow.
Enchants.Colors = {
	Common = rgb(214, 222, 236), -- moonlight silver
	Rare = rgb(64, 170, 255), -- sapphire
	Epic = rgb(176, 90, 255), -- amethyst
	Mythic = rgb(255, 64, 96), -- ruby
	Legendary = rgb(255, 196, 40), -- gold
	Secret = rgb(255, 255, 255),
}
Enchants.Rainbow = { rgb(255, 90, 120), rgb(255, 190, 70), rgb(120, 255, 150), rgb(80, 200, 255), rgb(190, 110, 255) }

-- LayerFx palettes (glow, rim, middle, core) for each rarity.
Enchants.Palettes = {
	Common = { rgb(200, 214, 240), rgb(96, 110, 140), rgb(222, 230, 246), rgb(255, 255, 255) },
	Rare = { rgb(70, 170, 255), rgb(20, 70, 180), rgb(110, 200, 255), rgb(236, 248, 255) },
	Epic = { rgb(180, 100, 255), rgb(84, 30, 170), rgb(206, 150, 255), rgb(250, 238, 255) },
	Mythic = { rgb(255, 70, 100), rgb(150, 14, 44), rgb(255, 120, 130), rgb(255, 236, 236) },
	Legendary = { rgb(255, 200, 60), rgb(176, 104, 10), rgb(255, 222, 110), rgb(255, 252, 230) },
	Secret = { rgb(255, 240, 255), rgb(150, 90, 220), rgb(160, 240, 255), rgb(255, 255, 255) },
}

---------------------------------------------------------------------------
-- The runes
--   for     "Creature" or "Spell"
--   atk/hp  more attack / health;  power  arrives with Power;  bubble  arrives with a Bubble
--   keywords  extra keywords (Zoom, Sturdy, Grudge, Haunt)
--   thorns  creatures that hit it take this much back;  leech  heals your hero this much each
--   time it deals damage;  selfHeal  heals itself this much when it does
--   rebirth  the first time it pops it rises again on its tile with this share of its health
--   costLess  costs this much less (never below 1);  heroHeal  heals your hero when cast;
--   draw  draws cards when cast
---------------------------------------------------------------------------
local LIST = {
	-- Creatures
	{ id = "thick_hide", name = "Thick Hide", rarity = "Common", ["for"] = "Creature", hp = 1, text = "+1 health" },
	{ id = "sharp_edge", name = "Sharp Edge", rarity = "Common", ["for"] = "Creature", atk = 1, text = "+1 attack" },
	{ id = "iron_hide", name = "Iron Hide", rarity = "Rare", ["for"] = "Creature", hp = 2, text = "+2 health" },
	{ id = "thorns", name = "Thorns", rarity = "Rare", ["for"] = "Creature", thorns = 1, hp = 1, text = "+1 health. Creatures that hit it take 1 damage back" },
	{ id = "head_start", name = "Head Start", rarity = "Rare", ["for"] = "Creature", power = 1, text = "Arrives with 1 Power" },
	{ id = "bubble_ward", name = "Bubble Ward", rarity = "Epic", ["for"] = "Creature", bubble = true, hp = 1, text = "+1 health. Arrives with a Bubble (blocks the first hit)" },
	{ id = "leech", name = "Leech", rarity = "Epic", ["for"] = "Creature", leech = 1, text = "Each time it deals damage, heal your hero 1" },
	{ id = "swift", name = "Swift", rarity = "Epic", ["for"] = "Creature", keywords = { "Zoom" }, atk = 1, text = "+1 attack and Zoom" },
	{ id = "fury", name = "Fury", rarity = "Mythic", ["for"] = "Creature", atk = 2, hp = 1, text = "+2 attack, +1 health" },
	{ id = "last_word", name = "Last Word", rarity = "Mythic", ["for"] = "Creature", keywords = { "Grudge" }, hp = 2, text = "+2 health and Grudge" },
	{ id = "restless", name = "Restless", rarity = "Mythic", ["for"] = "Creature", keywords = { "Haunt", "Sturdy" }, text = "Sturdy and Haunt" },
	{ id = "titan_blood", name = "Titan Blood", rarity = "Legendary", ["for"] = "Creature", atk = 2, hp = 3, text = "+2 attack, +3 health" },
	{ id = "vampire", name = "Vampire", rarity = "Legendary", ["for"] = "Creature", atk = 1, leech = 2, selfHeal = 1, text = "+1 attack. Each time it deals damage, heal your hero 2 and itself 1" },
	{ id = "phoenix", name = "Phoenix", rarity = "Legendary", ["for"] = "Creature", rebirth = 0.5, text = "The first time it pops, it rises again with half its health" },
	{ id = "starborn", name = "Starborn", rarity = "Secret", ["for"] = "Creature", atk = 3, hp = 3, bubble = true, text = "+3 attack, +3 health. Arrives with a Bubble" },
	{ id = "crown_of_ages", name = "Crown of Ages", rarity = "Secret", ["for"] = "Creature", atk = 2, hp = 2, keywords = { "Sturdy" }, rebirth = 1, text = "+2/+2 and Sturdy. The first time it pops, it rises again at full health" },
	-- Spells
	{ id = "inkwell", name = "Inkwell", rarity = "Common", ["for"] = "Spell", heroHeal = 1, text = "When cast, heal your hero 1" },
	{ id = "mending_ink", name = "Mending Ink", rarity = "Rare", ["for"] = "Spell", heroHeal = 2, text = "When cast, heal your hero 2" },
	{ id = "quick_cast", name = "Quick Cast", rarity = "Epic", ["for"] = "Spell", costLess = 1, text = "Costs 1 less (never below 1)" },
	{ id = "insight", name = "Insight", rarity = "Mythic", ["for"] = "Spell", draw = 1, text = "When cast, draw a card" },
	{ id = "echo", name = "Echo", rarity = "Legendary", ["for"] = "Spell", costLess = 1, draw = 1, text = "Costs 1 less (never below 1). When cast, draw a card" },
	{ id = "wellspring", name = "Wellspring", rarity = "Secret", ["for"] = "Spell", costLess = 1, draw = 1, heroHeal = 3, text = "Costs 1 less (never below 1). When cast, draw a card and heal your hero 3" },
}

Enchants.List = LIST
Enchants.ById = {}
for i, e in ipairs(LIST) do
	e.order = i
	Enchants.ById[e.id] = e
end

function Enchants.get(id)
	return type(id) == "string" and Enchants.ById[id] or nil
end

-- Can this card carry an enchant? (owned, collectible creatures and spells)
function Enchants.canEnchant(cardId)
	local c = type(cardId) == "string" and CardData.Cards[cardId]
	if not c or c.token then
		return false
	end
	return c.type == "Creature" or c.type == "Spell"
end

-- Is this enchant one that fits this card?
function Enchants.fits(enchantId, cardId)
	local e = Enchants.get(enchantId)
	local c = type(cardId) == "string" and CardData.Cards[cardId]
	return e ~= nil and c ~= nil and Enchants.canEnchant(cardId) and e["for"] == c.type
end

-- The runes of one rarity that fit a card.
function Enchants.pool(cardId, rarity)
	local c = CardData.Cards[cardId]
	local out = {}
	for _, e in ipairs(LIST) do
		if c and e["for"] == c.type and e.rarity == rarity then
			table.insert(out, e.id)
		end
	end
	return out
end

-- Rolls an enchant for a card. rand() returns a number in [0, 1).
--   lucky  Lucky Enchant odds;  pity  enchants in a row below Epic so far
-- Returns enchantId, rarity, newPity.
function Enchants.roll(cardId, rand, lucky, pity)
	pity = pity or 0
	local odds = lucky and Enchants.LuckyOdds or Enchants.Odds
	local floor = (pity >= Enchants.PityRolls) and 3 or 1
	local total = 0
	for _, r in ipairs(Enchants.Rarities) do
		if Enchants.Rank[r] >= floor and #Enchants.pool(cardId, r) > 0 then
			total += odds[r]
		end
	end
	local x = rand() * total
	local rarity = nil
	for _, r in ipairs(Enchants.Rarities) do
		if Enchants.Rank[r] >= floor and #Enchants.pool(cardId, r) > 0 and odds[r] > 0 then
			rarity = r
			x -= odds[r]
			if x < 0 then
				break
			end
		end
	end
	if not rarity then
		return nil, nil, pity
	end
	local pool = Enchants.pool(cardId, rarity)
	local id = pool[math.clamp(math.floor(rand() * #pool) + 1, 1, #pool)]
	local newPity = Enchants.Rank[rarity] >= 3 and 0 or pity + 1
	return id, rarity, newPity
end

-- Enchants left until the next Epic or better is sure.
function Enchants.untilPity(pity)
	return math.max(1, Enchants.PityRolls + 1 - (pity or 0))
end

-- Only the entries that are real enchants on cards that fit them ({ [cardId] = enchantId }).
function Enchants.sanitize(map)
	local out = {}
	if type(map) ~= "table" then
		return out
	end
	for cardId, eid in pairs(map) do
		if Enchants.fits(eid, cardId) then
			out[cardId] = eid
		end
	end
	return out
end

function Enchants.rarityOf(id)
	local e = Enchants.get(id)
	return e and e.rarity or nil
end

function Enchants.color(rarity)
	return Enchants.Colors[rarity] or Enchants.Colors.Common
end

return Enchants

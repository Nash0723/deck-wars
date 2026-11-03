-- Who fights in a Pack Brawl. Pure Lua (no Roblox instances), so it runs in the tests too.
-- Same pulled card + same seed = same cast.

local function req(name)
	if script then
		local rs = game:GetService("ReplicatedStorage")
		local own = script.Parent:FindFirstChild(name)
		if own then
			return require(own)
		end
		return require(rs:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local Rng = req("Rng")

local Casting = {}

-- Which crashers join before the pulled card, by the pulled card's tier.
-- Every brawl also starts with two Common starters.
Casting.Crashers = {
	Common = {},
	Rare = { "Rare" },
	Epic = { "Epic" },
	Mythic = { "Rare", "Epic", "Mythic" },
	Legendary = { "Rare", "Rare", "Epic", "Epic", "Mythic" },
	Secret = { "Rare", "Epic", "Mythic", "Legendary", "Legendary" },
}

-- Chance of the "It's Not Over" fake ending for these tiers.
Casting.FakeOutChance = { Mythic = 0.3, Legendary = 0.3, Secret = 0.3 }

-- Creatures (not tokens, buildings or spells) by tier, sorted so casts are stable.
local creaturesByTier = {}
for _, t in ipairs(CardData.Rarities) do
	creaturesByTier[t] = {}
end
do
	local ids = {}
	for id, def in pairs(CardData.Cards) do
		if def.type == "Creature" and not def.token then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local list = creaturesByTier[CardData.Cards[id].rarity]
		if list then
			table.insert(list, id)
		end
	end
end
Casting.CreaturesByTier = creaturesByTier

local function kindOf(def)
	if def.type == "Spell" then
		return "spell"
	elseif def.type == "Building" then
		return "building"
	end
	return "creature"
end

-- Picks a creature of this tier, preferring families that are not in the ring yet.
local function pickFighter(rng, tier, usedIds, usedFamilies)
	local fresh, any = {}, {}
	for _, id in ipairs(creaturesByTier[tier] or {}) do
		if not usedIds[id] then
			table.insert(any, id)
			if not usedFamilies[CardData.Cards[id].family] then
				table.insert(fresh, id)
			end
		end
	end
	local id = rng:pick(#fresh > 0 and fresh or any)
	if not id then
		-- Tier ran out (only happens with tiny tiers): fall back to any unused Common.
		for _, cid in ipairs(creaturesByTier.Common) do
			if not usedIds[cid] then
				id = cid
				break
			end
		end
	end
	return id
end

-- Returns {
--   tier = pulled tier, seed = seed,
--   fighters = { { id, name, tier, family, kind, role = "starter" | "crasher" | "winner" }, ... },
--   winner = index of the pulled card (always the last fighter),
--   fakeOut = true when the fake ending plays,
-- }
function Casting.build(pulledId: string, seed: number)
	local def = assert(CardData.Cards[pulledId], "unknown card " .. tostring(pulledId))
	local tier = def.rarity
	local rng = Rng.new(seed)
	local usedIds, usedFamilies = { [pulledId] = true }, {}
	local fighters = {}
	local function add(id, role)
		local d = CardData.Cards[id]
		usedIds[id] = true
		usedFamilies[d.family] = true
		table.insert(fighters, { id = id, name = d.name, tier = d.rarity, family = d.family, kind = kindOf(d), role = role })
	end
	for _ = 1, 2 do
		add(pickFighter(rng, "Common", usedIds, usedFamilies), "starter")
	end
	for _, t in ipairs(Casting.Crashers[tier] or {}) do
		add(pickFighter(rng, t, usedIds, usedFamilies), "crasher")
	end
	table.insert(fighters, { id = pulledId, name = def.name, tier = tier, family = def.family, kind = kindOf(def), role = "winner" })
	local fake = Casting.FakeOutChance[tier]
	return {
		tier = tier,
		seed = seed,
		fighters = fighters,
		winner = #fighters,
		fakeOut = fake ~= nil and rng:chance(fake),
	}
end

return Casting

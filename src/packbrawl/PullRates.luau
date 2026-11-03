-- Pack pull odds and rolling. Shared so the server rolls with it and the shop can show the odds.
-- The server is the only one that rolls for real; the client just plays what it is told.

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

local PullRates = {}

-- Low to high. Same names as CardData.Rarities.
PullRates.Tiers = { "Common", "Rare", "Epic", "Mythic", "Legendary", "Secret" }
PullRates.Rank = {}
for i, t in ipairs(PullRates.Tiers) do
	PullRates.Rank[t] = i
end

-- Percent chance per card. Adds up to 100.
PullRates.Odds = { Common = 55, Rare = 27, Epic = 12, Mythic = 4.5, Legendary = 1.2, Secret = 0.3 }

-- A 10-pull always holds at least one card of this tier or better.
PullRates.TenPullFloor = "Epic"

-- Cards that can come out of packs, by tier (tokens like Pigeon and Ghost are left out).
PullRates.Pool = {}
for _, t in ipairs(PullRates.Tiers) do
	PullRates.Pool[t] = {}
end
do
	local ids = {}
	for id, def in pairs(CardData.Cards) do
		if not def.token and PullRates.Pool[def.rarity] then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		table.insert(PullRates.Pool[CardData.Cards[id].rarity], id)
	end
end

-- rand() returns a number in [0, 1). Works with Random.new():NextNumber or Rng:next.
function PullRates.rollTier(rand: () -> number): string
	local roll = rand() * 100
	local acc = 0
	for _, t in ipairs(PullRates.Tiers) do
		acc += PullRates.Odds[t]
		if roll < acc then
			return t
		end
	end
	return "Common"
end

function PullRates.pickCard(tier: string, rand: () -> number): string
	local pool = PullRates.Pool[tier]
	local i = math.clamp(math.floor(rand() * #pool) + 1, 1, #pool)
	return pool[i]
end

-- Rolls count cards (1 or 10). forcedTier makes the first card that tier (test place only).
-- Returns { cards = { id, ... }, best = index of the rarest card }.
function PullRates.roll(count: number, rand: () -> number, forcedTier: string?)
	local cards, tiers = {}, {}
	for i = 1, count do
		local tier = (i == 1 and forcedTier) or PullRates.rollTier(rand)
		tiers[i] = tier
	end
	if count >= 10 and not forcedTier then
		local floorRank = PullRates.Rank[PullRates.TenPullFloor]
		local ok = false
		for _, t in ipairs(tiers) do
			if PullRates.Rank[t] >= floorRank then
				ok = true
			end
		end
		if not ok then
			tiers[count] = PullRates.TenPullFloor
		end
	end
	local best = 1
	for i = 1, count do
		cards[i] = PullRates.pickCard(tiers[i], rand)
		if PullRates.Rank[tiers[i]] > PullRates.Rank[tiers[best]] then
			best = i
		end
	end
	return { cards = cards, best = best }
end

return PullRates

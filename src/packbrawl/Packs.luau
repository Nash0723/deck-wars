-- The packs on the Pack Party shelf: the classic Brawl Pack (every card) and one themed pack per
-- family. Shared by the server (which rolls for real) and the client (which shows contents, odds
-- and prices). The rarity odds are the same for every pack (PullRates.Odds); a themed pack only
-- changes WHICH card of that rarity you get:
--
--   * 3 in 4 cards come from the pack's family, 1 in 4 from the shared cards (family "Any":
--     spells and buildings every deck can use).
--   * If the family has no card of the rolled rarity (most families have no Secret), the card
--     comes from every card of that rarity instead. So a Secret can turn up in any pack.
--
-- Packs.cardOdds(id) works out the exact chance of every card, which the shelf panel shows
-- before you buy (Roblox requires showing the odds of paid random items).

local function req(name)
	if script then
		local own = script.Parent:FindFirstChild(name)
		if own then
			return require(own)
		end
		return require(game:GetService("ReplicatedStorage"):WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local PullRates = req("PullRates")

local Packs = {}

Packs.Default = "brawl"
Packs.Currency = "Gems"
-- Price in Gems by how many packs you open at once.
Packs.Price = { [1] = 100, [10] = 900 }
-- Share of a themed pack's cards that come from its family.
Packs.ThemeShare = 0.75

-- Shelf order: the Brawl Pack crowns the top shelf, the six family packs fill the two below.
-- color = the pack's foil, dark = its shadow side, accent = trim and lettering,
-- mascot = the figurine standing next to it on the shelf (its family's Legendary).
Packs.List = {
	{ id = "brawl", name = "Brawl Pack", family = nil, tagline = "Every family, every card", color = { 92, 52, 170 }, dark = { 34, 22, 74 }, accent = { 255, 206, 72 }, mascot = nil, glyph = "DW" },
	{ id = "snack", name = "Sugar Rush Pack", family = "Snack", tagline = "Healers and heavy hitters", color = { 255, 104, 72 }, dark = { 150, 36, 40 }, accent = { 255, 224, 120 }, mascot = "queen_parfait", glyph = "SR" },
	{ id = "junk", name = "Scrap Heap Pack", family = "Junk", tagline = "Scrap, grit and big comebacks", color = { 28, 186, 160 }, dark = { 14, 82, 78 }, accent = { 255, 160, 70 }, mascot = "the_junk_king", glyph = "SH" },
	{ id = "weather", name = "Storm Front Pack", family = "Weather", tagline = "Soak them, then zap them", color = { 58, 140, 255 }, dark = { 22, 50, 140 }, accent = { 196, 244, 255 }, mascot = "stormlord_nimbus", glyph = "SF" },
	{ id = "critter", name = "Burrow Bunch Pack", family = "Critter", tagline = "Strength in numbers", color = { 104, 206, 64 }, dark = { 36, 104, 36 }, accent = { 255, 178, 210 }, mascot = "big_momma_moose", glyph = "BB" },
	{ id = "spooky", name = "Midnight Mall Pack", family = "Spooky", tagline = "Haunts that keep coming back", color = { 146, 72, 232 }, dark = { 52, 22, 104 }, accent = { 186, 255, 108 }, mascot = "the_mannequin_duke", glyph = "MM" },
	{ id = "robo", name = "Overclock Pack", family = "Robo", tagline = "Charge up and blast", color = { 112, 128, 168 }, dark = { 40, 44, 66 }, accent = { 255, 128, 40 }, mascot = "mega_blender_prime", glyph = "OC" },
}
Packs.ById = {}
for i, def in ipairs(Packs.List) do
	def.index = i
	def.terrain = def.family and CardData.Terrains[def.family] or nil
	Packs.ById[def.id] = def
end

function Packs.get(id)
	return Packs.ById[id or Packs.Default]
end

-- Is this a pack id the server accepts? (nil counts as the Brawl Pack.)
function Packs.valid(id)
	return id == nil or (type(id) == "string" and Packs.ById[id] ~= nil)
end

function Packs.price(count)
	return Packs.Price[count]
end

-- Card pools: [packId][tier] = { family = {...}, shared = {...}, all = {...} } (sorted ids).
local pools = {}
for _, def in ipairs(Packs.List) do
	local byTier = {}
	for _, tier in ipairs(PullRates.Tiers) do
		local entry = { family = {}, shared = {}, all = PullRates.Pool[tier] }
		if def.family then
			for _, id in ipairs(PullRates.Pool[tier]) do
				local fam = CardData.Cards[id].family
				if fam == def.family then
					table.insert(entry.family, id)
				elseif fam == "Any" then
					table.insert(entry.shared, id)
				end
			end
		end
		byTier[tier] = entry
	end
	pools[def.id] = byTier
end
Packs.Pools = pools

-- Returns the chance (0 to 1) that a card of `tier` from pack `id` comes from each group,
-- as a list of { ids, share }.
local function groups(id, tier)
	local def = Packs.get(id)
	local p = pools[def.id][tier]
	if not def.family then
		return { { ids = p.all, share = 1 } }
	end
	local fam, shared = p.family, p.shared
	if #fam > 0 and #shared > 0 then
		return { { ids = fam, share = Packs.ThemeShare }, { ids = shared, share = 1 - Packs.ThemeShare } }
	elseif #fam > 0 then
		return { { ids = fam, share = 1 } }
	elseif #shared > 0 then
		return { { ids = shared, share = 1 } }
	end
	return { { ids = p.all, share = 1 } }
end
Packs.groups = groups

-- The rarity odds in percent (the base odds, or a boosted table like PullRates.luckyOdds gives).
function Packs.tierOdds(odds)
	return odds or PullRates.Odds
end

function Packs.rollTier(rand, odds)
	odds = odds or PullRates.Odds
	local total = 0
	for _, t in ipairs(PullRates.Tiers) do
		total += odds[t] or 0
	end
	local roll = rand() * total
	local acc = 0
	for _, t in ipairs(PullRates.Tiers) do
		acc += odds[t] or 0
		if roll < acc then
			return t
		end
	end
	return PullRates.Tiers[1]
end

-- One card of `tier` from pack `id`. Uses rand() twice (group, then card).
function Packs.pickCard(id, tier, rand)
	local gs = groups(id, tier)
	local r = rand()
	local chosen = gs[#gs]
	local acc = 0
	for _, g in ipairs(gs) do
		acc += g.share
		if r < acc then
			chosen = g
			break
		end
	end
	local ids = chosen.ids
	local i = math.clamp(math.floor(rand() * #ids) + 1, 1, #ids)
	return ids[i]
end

-- Rolls `count` cards (1 or 10) from pack `id`. forcedTier makes the first card that tier
-- (Studio previews and dev rolls only). A 10-pull holds at least one PullRates.TenPullFloor card.
-- Returns { cards = { id, ... }, best = index of the rarest card, packId = id }.
function Packs.roll(id, count, rand, forcedTier, odds)
	id = Packs.get(id).id
	local tiers = {}
	for i = 1, count do
		tiers[i] = (i == 1 and forcedTier) or Packs.rollTier(rand, odds)
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
	local cards, best = {}, 1
	for i = 1, count do
		cards[i] = Packs.pickCard(id, tiers[i], rand)
		if PullRates.Rank[tiers[i]] > PullRates.Rank[tiers[best]] then
			best = i
		end
	end
	return { cards = cards, best = best, packId = id }
end

-- Exact chance (in percent) of each card for one card from pack `id`.
-- Returns a map { [cardId] = percent } and a list { { id, tier, chance, family } } sorted
-- rarest first, then by name.
function Packs.cardOdds(id, odds)
	odds = odds or PullRates.Odds
	local total = 0
	for _, t in ipairs(PullRates.Tiers) do
		total += odds[t] or 0
	end
	local map = {}
	for _, tier in ipairs(PullRates.Tiers) do
		local tierChance = (odds[tier] or 0) / total * 100
		for _, g in ipairs(groups(id, tier)) do
			for _, cid in ipairs(g.ids) do
				map[cid] = (map[cid] or 0) + tierChance * g.share / #g.ids
			end
		end
	end
	local list = {}
	for cid, chance in pairs(map) do
		local def = CardData.Cards[cid]
		table.insert(list, { id = cid, tier = def.rarity, chance = chance, family = def.family, name = def.name })
	end
	table.sort(list, function(a, b)
		local ra, rb = PullRates.Rank[a.tier], PullRates.Rank[b.tier]
		if ra ~= rb then
			return ra > rb
		end
		if (a.family == "Any") ~= (b.family == "Any") then
			return a.family ~= "Any"
		end
		return a.name < b.name
	end)
	return map, list
end

-- "0.3%", "4.5%", "0.075%": short but never rounds a real chance down to 0.
function Packs.percent(p)
	if p >= 10 then
		return string.format("%.0f%%", p)
	end
	local digits = p >= 1 and 1 or (p >= 0.1 and 2 or 3)
	local s = string.format("%." .. digits .. "f", p)
	s = string.gsub(s, "0+$", "")
	s = string.gsub(s, "%.$", "")
	return s .. "%"
end

function Packs.color(def, key)
	local c = def[key or "color"]
	return Color3.fromRGB(c[1], c[2], c[3])
end

return Packs

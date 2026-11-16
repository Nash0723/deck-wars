-- The Park: the shared park behind the room's front door, where everyone in the server walks
-- around as their avatar with a companion creature, opens packs at the Pull Altar, checks the
-- leaderboards and sees the Top Collector: whoever here has the rarest cards, standing on the
-- pedestal by the pond with their best cards on show. This file holds the numbers and the save
-- logic (used by ParkServer and the tests); ParkBuilder builds the place, ParkClient runs the
-- screen.
--
-- Save (on the one save, next to the Campaign):
--   d.showcase = { cards = { id, id, id } }           -- your picks: the first creature is your companion
--   d.hub = { likes = n,                               -- (old booth likes, kept in the save)
--             given = { day = utc day, ids = { ["<userId>"] = true } },
--             title = "name" or nil,                   -- the title on your nameplate (one you earned)
--             best = { id = cardId, at = os.time() } } -- your rarest pull ever

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end
local CardData = req("CardData")

local Park = {}

Park.Origin = Vector3.new(2000, 0, 0) -- far from the room and the match worlds
Park.Booths = 12 -- (the old booth ring: only the tests still use it)
Park.ShowcaseSize = 3
Park.ChampionCards = 3 -- cards on show at the Top Collector's stand
Park.BigPullRarity = "Mythic" -- this rarity and up gets a banner for the whole server
Park.CrossServerRarity = "Secret" -- this one is told to every server (MessagingService)
Park.FeedDelay = 3 -- seconds before a pull is announced (the puller's own chat line also waits until their opening is over)
Park.HallSize = 10 -- big pulls on the Hall of Pulls
Park.BoardSize = 10 -- names on each leaderboard
Park.BoardSeconds = 120 -- how often the leaderboards are saved and read
Park.CrossServerTopic = "DeckWarsBigPull"
Park.CrossServerGap = 3 -- seconds between two cross-server messages from one server (later ones wait their turn)
Park.ChatRarity = "Secret" -- this rarity (and any Shiny card, once they exist) is posted in everyone's chat

Park.Boards = {
	{ key = "Stars", name = "Campaign Stars", emoji = "★", store = "DeckWarsBoardStars_v1" },
	{ key = "Level", name = "Highest Level", emoji = "⬆", store = "DeckWarsBoardLevel_v1" },
}

local RANK = {}
for i, r in ipairs(CardData.Rarities) do
	RANK[r] = i
end
Park.Rank = RANK

local function utcDay(now)
	return math.floor((now or os.time()) / 86400)
end
Park.utcDay = utcDay

-- Fills in the Park tables on a save (old saves don't have them).
function Park.ensure(d)
	d.showcase = type(d.showcase) == "table" and d.showcase or {}
	d.showcase.cards = type(d.showcase.cards) == "table" and d.showcase.cards or {}
	local h = type(d.hub) == "table" and d.hub or {}
	d.hub = h
	h.likes = type(h.likes) == "number" and h.likes or 0
	h.given = type(h.given) == "table" and h.given or { day = -1, ids = {} }
	h.given.ids = type(h.given.ids) == "table" and h.given.ids or {}
	return d.showcase, h
end

local function rarityOf(id)
	local c = CardData.Cards[id]
	return c and RANK[c.rarity] or 0
end

-- Sorts card ids rarest first (then by name, so the order never jumps around).
function Park.sortRarest(ids)
	table.sort(ids, function(a, b)
		local ra, rb = rarityOf(a), rarityOf(b)
		if ra ~= rb then
			return ra > rb
		end
		return tostring(a) < tostring(b)
	end)
	return ids
end

-- The cards a booth shows: the ones you picked that you still own, filled up with your rarest.
function Park.showcaseOf(d)
	local showcase = Park.ensure(d)
	local collection = d.collection or {}
	local out, used = {}, {}
	for _, id in ipairs(showcase.cards) do
		if #out < Park.ShowcaseSize and (collection[id] or 0) > 0 and CardData.Cards[id] and not used[id] then
			table.insert(out, id)
			used[id] = true
		end
	end
	if #out < Park.ShowcaseSize then
		local owned = {}
		for id, n in pairs(collection) do
			if n > 0 and CardData.Cards[id] and not CardData.Cards[id].token and not used[id] then
				table.insert(owned, id)
			end
		end
		Park.sortRarest(owned)
		for _, id in ipairs(owned) do
			if #out >= Park.ShowcaseSize then
				break
			end
			table.insert(out, id)
		end
	end
	return out
end

-- Pick your booth's cards. Only cards you own count; returns true or false and why.
function Park.setShowcase(d, ids)
	if type(ids) ~= "table" then
		return false, "Pick up to 3 cards."
	end
	local showcase = Park.ensure(d)
	local collection = d.collection or {}
	local picked, used = {}, {}
	for _, id in ipairs(ids) do
		if type(id) ~= "string" or not CardData.Cards[id] then
			return false, "That card doesn't exist."
		end
		if (collection[id] or 0) <= 0 then
			return false, "You can only show cards you own."
		end
		if not used[id] then
			used[id] = true
			table.insert(picked, id)
		end
		if #picked > Park.ShowcaseSize then
			return false, "A booth holds 3 cards."
		end
	end
	showcase.cards = picked
	return true
end

-- The companion that walks next to you: the first creature of your showcase.
function Park.companionOf(d)
	for _, id in ipairs(Park.showcaseOf(d)) do
		local c = CardData.Cards[id]
		if c and c.type == "Creature" then
			return id
		end
	end
	-- (nothing picked, and only spells among your rarest: your rarest creature walks with you)
	for _, id in ipairs((Park.rarestCards(d, math.huge))) do
		if CardData.Cards[id].type == "Creature" then
			return id
		end
	end
	return nil
end

-- One like from `liker` (save dl, userId likerId) to the booth of `owner` (save dOwner, userId
-- ownerId), at most once per booth per UTC day and never your own. Returns true or false and why.
function Park.like(dl, likerId, dOwner, ownerId, now)
	local _, hl = Park.ensure(dl)
	local _, ho = Park.ensure(dOwner)
	if likerId == ownerId then
		return false, "That's your own booth!"
	end
	local today = utcDay(now)
	if hl.given.day ~= today then
		hl.given = { day = today, ids = {} }
	end
	local key = tostring(ownerId)
	if hl.given.ids[key] then
		return false, "You already liked this booth today."
	end
	hl.given.ids[key] = true
	ho.likes += 1
	return true
end

-- Has `dl` liked this owner's booth today?
function Park.likedToday(dl, ownerId, now)
	local _, hl = Park.ensure(dl)
	return hl.given.day == utcDay(now) and hl.given.ids[tostring(ownerId)] == true
end

-- Remember a pull if it is your rarest yet. Returns true when it is.
function Park.notePull(d, ids, now)
	local _, h = Park.ensure(d)
	local best = h.best and h.best.id
	local changed = false
	for _, id in ipairs(ids or {}) do
		if CardData.Cards[id] and rarityOf(id) > rarityOf(best) then
			best = id
			changed = true
		end
	end
	if changed then
		h.best = { id = best, at = now or os.time() }
	end
	return changed
end

-- The titles you can wear: Campaign titles (`earned`) and one from your rarest pull.
Park.PullTitles = {
	Rare = "Lucky Charm",
	Epic = "Pack Hunter",
	Mythic = "Mythic Finder",
	Legendary = "Living Legend",
	Secret = "Keeper of Secrets",
}
function Park.titlesOf(d, earned)
	local _, h = Park.ensure(d)
	local out = {}
	local best = h.best and CardData.Cards[h.best.id]
	if best and Park.PullTitles[best.rarity] then
		table.insert(out, Park.PullTitles[best.rarity])
	end
	for _, t in ipairs(earned or {}) do
		if not table.find(out, t) then
			table.insert(out, t)
		end
	end
	return out
end

-- The title on your nameplate: the one you picked if you still have it, else the newest one.
function Park.titleOf(d, earned)
	local _, h = Park.ensure(d)
	local all = Park.titlesOf(d, earned)
	if h.title and table.find(all, h.title) then
		return h.title
	end
	return all[#all]
end

function Park.setTitle(d, earned, title)
	local _, h = Park.ensure(d)
	if title == nil or title == "" then
		h.title = nil
		return true
	end
	if not table.find(Park.titlesOf(d, earned), title) then
		return false, "You haven't earned that title yet."
	end
	h.title = title
	return true
end

-- Is a pull of this card worth a banner? ("server", "cross" or nil). A Shiny card goes to every server.
function Park.announceLevel(id, shiny)
	local r = rarityOf(id)
	if shiny == true or r >= (RANK[Park.CrossServerRarity] or math.huge) then
		return "cross"
	elseif r >= (RANK[Park.BigPullRarity] or math.huge) then
		return "server"
	end
	return nil
end

-- Does this big pull go in the chat? (e = { rarity, shiny })
function Park.chatWorthy(e)
	if type(e) ~= "table" then
		return false
	end
	if e.shiny == true then
		return true
	end
	local need = RANK[Park.ChatRarity] or math.huge
	return (RANK[e.rarity] or 0) >= need
end

-- The chat line for a big pull (rich text), e = { name, card, rarity, shiny, far }.
function Park.chatLine(e, cardName, hex)
	local function esc(str)
		return (string.gsub(tostring(str), "[<>&\"']", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;", ["'"] = "&apos;" }))
	end
	local what = (e.shiny == true and "Shiny " or "") .. tostring(e.rarity or "")
	local where = e.far and "🌍 " or "✨ "
	return string.format('<font color="#%s"><b>%s%s</b> pulled a %s card: <b>%s</b>!</font>', hex or "FFFFFF", where, esc(e.name), esc(what), esc(cardName))
end

-- The Top Collector ----------------------------------------------------------------------------
-- Whoever in the server has the rarest cards. Collections are compared card by card from the
-- rarest down (the best card's rarity, then the second's, then the third's), then by how many
-- different cards they hold.

-- Your n rarest cards (not tokens), rarest first.
function Park.rarestCards(d, n)
	local owned = {}
	for id, count in pairs(d and d.collection or {}) do
		local c = CardData.Cards[id]
		if type(count) == "number" and count > 0 and c and not c.token then
			table.insert(owned, id)
		end
	end
	Park.sortRarest(owned)
	local out = {}
	for i = 1, math.min(n or Park.ChampionCards, #owned) do
		out[i] = owned[i]
	end
	return out, #owned
end

-- What a collection is judged by: { rank of the rarest, rank of the 2nd, rank of the 3rd, cards }.
function Park.collectionKey(d)
	local top, count = Park.rarestCards(d, Park.ChampionCards)
	local key = {}
	for i = 1, Park.ChampionCards do
		key[i] = top[i] and rarityOf(top[i]) or 0
	end
	key[Park.ChampionCards + 1] = count
	return key
end

-- Is collection key a strictly better than key b?
function Park.betterCollection(a, b)
	for i = 1, math.max(#a, #b) do
		local x, y = a[i] or 0, b[i] or 0
		if x ~= y then
			return x > y
		end
	end
	return false
end

-- Picks the Top Collector from { { id = any, d = save }, ... }. `current` (an id) keeps the spot on
-- a tie. Returns the winning entry (nil if nobody has a card).
function Park.pickChampion(entries, current)
	local best, bestKey = nil, nil
	for _, e in ipairs(entries) do
		local key = Park.collectionKey(e.d)
		if key[1] > 0 then
			if not best or Park.betterCollection(key, bestKey) or (e.id == current and not Park.betterCollection(bestKey, key)) then
				best, bestKey = e, key
			end
		end
	end
	return best
end

-- The park's sky ------------------------------------------------------------------------------
-- The park keeps the real time of day where the server is (ParkServer works out the place and
-- puts UtcOffset (seconds), Latitude and Longitude on Workspace.Park). The real sunrise and sunset
-- there are stretched onto Roblox's clock (sunrise at 6, sunset at 18), so the park's sun comes up
-- and goes down when it really does there, and the light passes through every mood in between:
-- misty pink dawn, fresh morning, bright midday, golden hour, sunset, blue hour and moonlit night.

Park.DefaultSun = { 6.5, 18.5 } -- local sunrise and sunset when the place isn't known
-- Set this to keep the park on one place's time instead of looking the server up online, e.g.
-- { offset = 3600, lat = 47.5, lon = 19.04, place = "Budapest, Hungary" } (offset in seconds).
Park.FixedPlace = nil

-- Today's sunrise and sunset in local hours at a latitude and longitude (degrees, east positive),
-- on day `yday` of the year (1..366), `offset` hours from UTC (NOAA's simple solar equations).
function Park.sunTimes(lat, lon, yday, offset)
	local g = 2 * math.pi / 365 * (yday - 1)
	local eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g) - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
	local decl = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g) - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g) - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g)
	local latR = math.rad(math.clamp(lat, -89, 89))
	local x = math.cos(math.rad(90.833)) / (math.cos(latR) * math.cos(decl)) - math.tan(latR) * math.tan(decl)
	x = math.clamp(x, -0.966, 0.966) -- (never an endless day or night: at least ~2 hours of either)
	local ha = math.deg(math.acos(x))
	local rise = (720 - 4 * (lon + ha) - eqtime) / 60 + offset
	local set = (720 - 4 * (lon - ha) - eqtime) / 60 + offset
	return rise % 24, set % 24
end

-- A real local hour on the park's clock: the day (sunrise..sunset) onto 6..18 and the night onto
-- 18..30 (that is, back round through 0 to 6).
function Park.skyClock(hour, rise, set)
	local day = (set - rise) % 24
	if day < 1 then
		day = 12
	end
	local sinceRise = (hour - rise) % 24
	if sinceRise <= day then
		return 6 + 12 * sinceRise / day
	end
	return (18 + 12 * (sinceRise - day) / (24 - day)) % 24
end

-- The light through the day, on the park's clock (c). Colors are { r, g, b }. In between two of
-- these, everything eases from one to the next.
Park.SkyKeys = {
	{ c = 0, Brightness = 1.2, Exposure = 0.35, Ambient = { 62, 66, 94 }, Outdoor = { 80, 90, 130 }, ShiftTop = { 150, 170, 225 }, ShiftBottom = { 20, 22, 40 }, Density = 0.34, Haze = 1.1, Glare = 0, AtmoColor = { 80, 96, 140 }, Decay = { 34, 40, 70 }, Saturation = -0.06, Contrast = 0.1, Tint = { 215, 222, 255 }, Rays = 0, Cover = 0.42, CloudDensity = 0.45, CloudColor = { 64, 74, 104 }, Diffuse = 0.3, Specular = 0.5 },
	{ c = 4.6, Brightness = 1.2, Exposure = 0.35, Ambient = { 64, 66, 94 }, Outdoor = { 84, 88, 128 }, ShiftTop = { 160, 170, 220 }, ShiftBottom = { 22, 24, 42 }, Density = 0.35, Haze = 1.3, Glare = 0, AtmoColor = { 96, 104, 150 }, Decay = { 40, 44, 76 }, Saturation = -0.05, Contrast = 0.1, Tint = { 215, 220, 255 }, Rays = 0, Cover = 0.44, CloudDensity = 0.45, CloudColor = { 72, 78, 110 }, Diffuse = 0.3, Specular = 0.5 },
	{ c = 5.6, Brightness = 1.3, Exposure = 0.2, Ambient = { 80, 72, 94 }, Outdoor = { 112, 98, 122 }, ShiftTop = { 232, 172, 172 }, ShiftBottom = { 40, 36, 56 }, Density = 0.38, Haze = 2.2, Glare = 0.2, AtmoColor = { 200, 170, 190 }, Decay = { 120, 96, 130 }, Saturation = 0, Contrast = 0.05, Tint = { 245, 226, 236 }, Rays = 0.05, Cover = 0.5, CloudDensity = 0.5, CloudColor = { 200, 160, 172 }, Diffuse = 0.4, Specular = 0.5 },
	{ c = 6.6, Brightness = 2, Exposure = 0.1, Ambient = { 104, 90, 92 }, Outdoor = { 150, 122, 118 }, ShiftTop = { 255, 186, 140 }, ShiftBottom = { 60, 50, 56 }, Density = 0.34, Haze = 2.4, Glare = 0.5, AtmoColor = { 255, 206, 178 }, Decay = { 190, 128, 130 }, Saturation = 0.05, Contrast = 0.06, Tint = { 255, 236, 222 }, Rays = 0.14, Cover = 0.48, CloudDensity = 0.55, CloudColor = { 255, 206, 186 }, Diffuse = 0.5, Specular = 0.5 },
	{ c = 8.2, Brightness = 2.6, Exposure = 0.05, Ambient = { 104, 104, 102 }, Outdoor = { 134, 140, 128 }, ShiftTop = { 255, 232, 200 }, ShiftBottom = { 66, 80, 58 }, Density = 0.26, Haze = 1.2, Glare = 0.2, AtmoColor = { 218, 230, 234 }, Decay = { 160, 172, 168 }, Saturation = 0.06, Contrast = 0.06, Tint = { 255, 250, 242 }, Rays = 0.08, Cover = 0.5, CloudDensity = 0.6, CloudColor = { 245, 245, 245 }, Diffuse = 0.6, Specular = 0.6 },
	{ c = 12.5, Brightness = 3, Exposure = 0, Ambient = { 108, 110, 104 }, Outdoor = { 138, 144, 130 }, ShiftTop = { 255, 240, 216 }, ShiftBottom = { 70, 86, 60 }, Density = 0.22, Haze = 0.7, Glare = 0.1, AtmoColor = { 214, 230, 232 }, Decay = { 150, 176, 150 }, Saturation = 0.08, Contrast = 0.08, Tint = { 255, 253, 248 }, Rays = 0.05, Cover = 0.55, CloudDensity = 0.65, CloudColor = { 255, 255, 255 }, Diffuse = 0.6, Specular = 0.6 },
	{ c = 15.5, Brightness = 2.9, Exposure = 0, Ambient = { 110, 106, 100 }, Outdoor = { 140, 140, 124 }, ShiftTop = { 255, 230, 196 }, ShiftBottom = { 72, 82, 58 }, Density = 0.24, Haze = 0.9, Glare = 0.2, AtmoColor = { 226, 228, 218 }, Decay = { 170, 170, 140 }, Saturation = 0.08, Contrast = 0.08, Tint = { 255, 246, 232 }, Rays = 0.07, Cover = 0.52, CloudDensity = 0.6, CloudColor = { 255, 250, 240 }, Diffuse = 0.6, Specular = 0.6 },
	{ c = 17.2, Brightness = 2.4, Exposure = 0.05, Ambient = { 116, 96, 86 }, Outdoor = { 156, 128, 104 }, ShiftTop = { 255, 196, 130 }, ShiftBottom = { 76, 60, 50 }, Density = 0.28, Haze = 1.6, Glare = 0.7, AtmoColor = { 255, 214, 168 }, Decay = { 190, 126, 100 }, Saturation = 0.12, Contrast = 0.08, Tint = { 255, 228, 196 }, Rays = 0.16, Cover = 0.5, CloudDensity = 0.55, CloudColor = { 255, 214, 170 }, Diffuse = 0.55, Specular = 0.6 },
	{ c = 18.2, Brightness = 1.5, Exposure = 0.12, Ambient = { 100, 78, 88 }, Outdoor = { 134, 96, 104 }, ShiftTop = { 255, 140, 96 }, ShiftBottom = { 60, 40, 56 }, Density = 0.32, Haze = 2, Glare = 0.9, AtmoColor = { 255, 164, 140 }, Decay = { 120, 70, 110 }, Saturation = 0.1, Contrast = 0.08, Tint = { 255, 214, 200 }, Rays = 0.2, Cover = 0.48, CloudDensity = 0.55, CloudColor = { 250, 150, 130 }, Diffuse = 0.45, Specular = 0.6 },
	{ c = 19.1, Brightness = 0.9, Exposure = 0.25, Ambient = { 72, 66, 98 }, Outdoor = { 88, 86, 132 }, ShiftTop = { 176, 150, 214 }, ShiftBottom = { 30, 28, 50 }, Density = 0.33, Haze = 1.6, Glare = 0.2, AtmoColor = { 132, 128, 188 }, Decay = { 70, 60, 118 }, Saturation = 0, Contrast = 0.1, Tint = { 228, 220, 255 }, Rays = 0.03, Cover = 0.45, CloudDensity = 0.5, CloudColor = { 120, 110, 160 }, Diffuse = 0.35, Specular = 0.5 },
	{ c = 20.6, Brightness = 1.2, Exposure = 0.35, Ambient = { 62, 66, 94 }, Outdoor = { 80, 90, 130 }, ShiftTop = { 152, 170, 225 }, ShiftBottom = { 20, 22, 40 }, Density = 0.34, Haze = 1.2, Glare = 0, AtmoColor = { 84, 98, 144 }, Decay = { 36, 42, 72 }, Saturation = -0.05, Contrast = 0.1, Tint = { 216, 222, 255 }, Rays = 0, Cover = 0.42, CloudDensity = 0.45, CloudColor = { 66, 76, 106 }, Diffuse = 0.3, Specular = 0.5 },
}

local function blend(a, b, t)
	if type(a) == "table" then
		return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
	end
	return a + (b - a) * t
end

-- The light at the park's clock c (0..24): every value eased between the two nearest keys.
function Park.sky(c)
	local keys = Park.SkyKeys
	local n = #keys
	c = c % 24
	local i = n
	for k = 1, n do
		if keys[k].c <= c then
			i = k
		end
	end
	local a, b = keys[i], keys[i % n + 1]
	local span = (b.c - a.c) % 24
	if span == 0 then
		span = 24
	end
	local t = ((c - a.c) % 24) / span
	t = t * t * (3 - 2 * t)
	local out = {}
	for k, v in pairs(a) do
		if k ~= "c" then
			out[k] = blend(v, b[k], t)
		end
	end
	return out
end

-- How dark it is (0 = day .. 1 = night): the lamps, string lights and fireflies follow this. They
-- come on through sunset and go off through sunrise.
function Park.darkness(c)
	c = c % 24
	local function ramp(x, from, to)
		return math.clamp((x - from) / (to - from), 0, 1)
	end
	if c >= 12 then
		return ramp(c, 17.4, 18.9)
	end
	return 1 - ramp(c, 5.7, 7)
end

-- The Park is a park: a pond in the middle with the Pull Altar on its island. Angles go round
-- the middle with a = 0 toward the Home gate (south): x = sin(a) * r, z = cos(a) * r.
Park.IslandRadius = 13
Park.WaterLevel = 0.22 -- the pond's surface, above the grass at 0
-- How far the pond's shore is from the middle at angle a (a bit wider east and west).
function Park.pondRadius(a)
	return 31 - 4.5 * math.cos(2 * a) + 2.2 * math.sin(3 * a + 1)
end

-- Booth i's spot, relative to Park.Origin: a ring of stalls on the lawn round the pond, facing it.
Park.BoothRadius = 60
function Park.boothCFrame(i)
	local angle = (i - 0.5) / Park.Booths * math.pi * 2
	local pos = Vector3.new(math.sin(angle) * Park.BoothRadius, 0, math.cos(angle) * Park.BoothRadius)
	return CFrame.lookAt(Park.Origin + pos, Park.Origin + Vector3.new(0, 0, 0))
end

-- Where you appear when you walk in: on the path just inside the glasshouse's Home door, facing
-- the altar.
function Park.spawnCFrame(n)
	local offset = ((n or 0) % 5 - 2) * 3
	return CFrame.lookAt(Park.Origin + Vector3.new(offset, 3.5, 114), Park.Origin + Vector3.new(offset, 3.5, 0))
end

return Park

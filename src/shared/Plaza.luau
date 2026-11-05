-- The Plaza: the shared lobby behind the room's front door, where everyone in the server walks
-- around as their avatar, shows off their best pulls at a booth, likes other booths, opens packs
-- at the Pull Altar and checks the leaderboards. This file holds the numbers and the save logic
-- (used by PlazaServer and the tests); PlazaBuilder builds the place, PlazaClient runs the screen.
--
-- Save (on the one save, next to the Campaign):
--   d.showcase = { cards = { id, id, id } }           -- your booth's 3 cards ({} = your 3 rarest)
--   d.hub = { likes = n,                               -- likes your booth got, ever
--             given = { day = utc day, ids = { ["<userId>"] = true } },  -- booths you liked today
--             title = "name" or nil,                   -- the title on your nameplate (one you earned)
--             best = { id = cardId, at = os.time() } } -- your rarest pull ever

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end
local CardData = req("CardData")

local Plaza = {}

Plaza.Origin = Vector3.new(2000, 0, 0) -- far from the room and the match worlds
Plaza.Booths = 12 -- one per player in a server
Plaza.ShowcaseSize = 3
Plaza.BigPullRarity = "Mythic" -- this rarity and up gets a banner for the whole server
Plaza.CrossServerRarity = "Secret" -- this one is told to every server (MessagingService)
Plaza.FeedDelay = 15 -- seconds before a pull is announced (so it doesn't spoil the puller's reveal)
Plaza.HallSize = 10 -- big pulls on the Hall of Pulls
Plaza.BoardSize = 10 -- names on each leaderboard
Plaza.BoardSeconds = 120 -- how often the leaderboards are saved and read
Plaza.CrossServerTopic = "DeckWarsBigPull"
Plaza.CrossServerGap = 3 -- seconds between two cross-server messages from one server (later ones wait their turn)
Plaza.ChatRarity = "Secret" -- this rarity (and any Shiny card, once they exist) is posted in everyone's chat

Plaza.Boards = {
	{ key = "Stars", name = "Campaign Stars", emoji = "★", store = "DeckWarsBoardStars_v1" },
	{ key = "Level", name = "Highest Level", emoji = "⬆", store = "DeckWarsBoardLevel_v1" },
	{ key = "Likes", name = "Most Liked Booths", emoji = "❤", store = "DeckWarsBoardLikes_v1" },
}

local RANK = {}
for i, r in ipairs(CardData.Rarities) do
	RANK[r] = i
end
Plaza.Rank = RANK

local function utcDay(now)
	return math.floor((now or os.time()) / 86400)
end
Plaza.utcDay = utcDay

-- Fills in the Plaza tables on a save (old saves don't have them).
function Plaza.ensure(d)
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
function Plaza.sortRarest(ids)
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
function Plaza.showcaseOf(d)
	local showcase = Plaza.ensure(d)
	local collection = d.collection or {}
	local out, used = {}, {}
	for _, id in ipairs(showcase.cards) do
		if #out < Plaza.ShowcaseSize and (collection[id] or 0) > 0 and CardData.Cards[id] and not used[id] then
			table.insert(out, id)
			used[id] = true
		end
	end
	if #out < Plaza.ShowcaseSize then
		local owned = {}
		for id, n in pairs(collection) do
			if n > 0 and CardData.Cards[id] and not CardData.Cards[id].token and not used[id] then
				table.insert(owned, id)
			end
		end
		Plaza.sortRarest(owned)
		for _, id in ipairs(owned) do
			if #out >= Plaza.ShowcaseSize then
				break
			end
			table.insert(out, id)
		end
	end
	return out
end

-- Pick your booth's cards. Only cards you own count; returns true or false and why.
function Plaza.setShowcase(d, ids)
	if type(ids) ~= "table" then
		return false, "Pick up to 3 cards."
	end
	local showcase = Plaza.ensure(d)
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
		if #picked > Plaza.ShowcaseSize then
			return false, "A booth holds 3 cards."
		end
	end
	showcase.cards = picked
	return true
end

-- The companion that walks next to you: the first creature of your showcase.
function Plaza.companionOf(d)
	for _, id in ipairs(Plaza.showcaseOf(d)) do
		local c = CardData.Cards[id]
		if c and c.type == "Creature" then
			return id
		end
	end
	return nil
end

-- One like from `liker` (save dl, userId likerId) to the booth of `owner` (save dOwner, userId
-- ownerId), at most once per booth per UTC day and never your own. Returns true or false and why.
function Plaza.like(dl, likerId, dOwner, ownerId, now)
	local _, hl = Plaza.ensure(dl)
	local _, ho = Plaza.ensure(dOwner)
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
function Plaza.likedToday(dl, ownerId, now)
	local _, hl = Plaza.ensure(dl)
	return hl.given.day == utcDay(now) and hl.given.ids[tostring(ownerId)] == true
end

-- Remember a pull if it is your rarest yet. Returns true when it is.
function Plaza.notePull(d, ids, now)
	local _, h = Plaza.ensure(d)
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
Plaza.PullTitles = {
	Rare = "Lucky Charm",
	Epic = "Pack Hunter",
	Mythic = "Mythic Finder",
	Legendary = "Living Legend",
	Secret = "Keeper of Secrets",
}
function Plaza.titlesOf(d, earned)
	local _, h = Plaza.ensure(d)
	local out = {}
	local best = h.best and CardData.Cards[h.best.id]
	if best and Plaza.PullTitles[best.rarity] then
		table.insert(out, Plaza.PullTitles[best.rarity])
	end
	for _, t in ipairs(earned or {}) do
		if not table.find(out, t) then
			table.insert(out, t)
		end
	end
	return out
end

-- The title on your nameplate: the one you picked if you still have it, else the newest one.
function Plaza.titleOf(d, earned)
	local _, h = Plaza.ensure(d)
	local all = Plaza.titlesOf(d, earned)
	if h.title and table.find(all, h.title) then
		return h.title
	end
	return all[#all]
end

function Plaza.setTitle(d, earned, title)
	local _, h = Plaza.ensure(d)
	if title == nil or title == "" then
		h.title = nil
		return true
	end
	if not table.find(Plaza.titlesOf(d, earned), title) then
		return false, "You haven't earned that title yet."
	end
	h.title = title
	return true
end

-- Is a pull of this card worth a banner? ("server", "cross" or nil). A Shiny card goes to every server.
function Plaza.announceLevel(id, shiny)
	local r = rarityOf(id)
	if shiny == true or r >= (RANK[Plaza.CrossServerRarity] or math.huge) then
		return "cross"
	elseif r >= (RANK[Plaza.BigPullRarity] or math.huge) then
		return "server"
	end
	return nil
end

-- Does this big pull go in the chat? (e = { rarity, shiny })
function Plaza.chatWorthy(e)
	if type(e) ~= "table" then
		return false
	end
	if e.shiny == true then
		return true
	end
	local need = RANK[Plaza.ChatRarity] or math.huge
	return (RANK[e.rarity] or 0) >= need
end

-- The chat line for a big pull (rich text), e = { name, card, rarity, shiny, far }.
function Plaza.chatLine(e, cardName, hex)
	local function esc(str)
		return (string.gsub(tostring(str), "[<>&\"']", { ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ['"'] = "&quot;", ["'"] = "&apos;" }))
	end
	local what = (e.shiny == true and "Shiny " or "") .. tostring(e.rarity or "")
	local where = e.far and "🌍 " or "✨ "
	return string.format('<font color="#%s"><b>%s%s</b> pulled a %s card: <b>%s</b>!</font>', hex or "FFFFFF", where, esc(e.name), esc(what), esc(cardName))
end

-- Booth i's spot, relative to Plaza.Origin: a ring facing the Pull Altar in the middle.
Plaza.BoothRadius = 46
function Plaza.boothCFrame(i)
	local angle = (i - 0.5) / Plaza.Booths * math.pi * 2
	local pos = Vector3.new(math.sin(angle) * Plaza.BoothRadius, 0, math.cos(angle) * Plaza.BoothRadius)
	return CFrame.lookAt(Plaza.Origin + pos, Plaza.Origin + Vector3.new(0, 0, 0))
end

-- Where you appear when you walk in: on the path just inside the Home gate, facing the altar.
function Plaza.spawnCFrame(n)
	local offset = ((n or 0) % 5 - 2) * 3
	return CFrame.lookAt(Plaza.Origin + Vector3.new(offset, 3.5, 100), Plaza.Origin + Vector3.new(offset, 3.5, 0))
end

return Plaza

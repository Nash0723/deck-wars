-- The Park's server: builds the park (ParkBuilder), walks characters in and out, keeps the Top
-- Collector (whoever in the server has the rarest cards) on the pedestal by the pond as their own
-- avatar with their best cards, takes companion and title picks, announces big pulls (to this
-- server and, for Secrets, to every server) and keeps the leaderboards. The rules and numbers are
-- in ReplicatedStorage.DeckWars.Park; the screen is ParkClient.
--
-- Remotes (ReplicatedStorage.ParkRemotes):
--   ParkAction (client -> server): "Enter", "Leave", "State", "SetShowcase" { cards },
--                                   "SetTitle" { title }, and the "Trade..." actions for
--                                   trading cards at the Trading Post (see TradeDesk)
--   ParkEvent  (server -> client): { kind = "entered" | "left" | "state" | "bigPull" | "hall" |
--                                   "boards" | "toast" | "trade..." (see TradeDesk), ... }
-- PullServer fires ServerScriptService.PullFeed (a BindableEvent made here) after each paid pull.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local Park = require(Shared:WaitForChild("Park"))
local CardData = require(Shared:WaitForChild("CardData"))
local Campaign = require(Shared:WaitForChild("Campaign"))
local ParkBuilder = require(script.Parent:WaitForChild("ParkBuilder"))
local CampaignData = require(script.Parent:WaitForChild("CampaignData"))
local Trade = require(Shared:WaitForChild("Trade"))
local TradeDesk = require(script.Parent:WaitForChild("TradeDesk"))

local remotes = ReplicatedStorage:WaitForChild("ParkRemotes")
local ParkAction = remotes:WaitForChild("ParkAction")
local ParkEvent = remotes:WaitForChild("ParkEvent")

local feed = ServerScriptService:FindFirstChild("PullFeed")
if not feed then
	feed = Instance.new("BindableEvent")
	feed.Name = "PullFeed"
	feed.Parent = ServerScriptService
end

local root = ParkBuilder.build(workspace)
local stand = root:FindFirstChild("TopCollector")

---------------------------------------------------------------------------
-- Save helpers
---------------------------------------------------------------------------

local function economy()
	local folder = ServerStorage:FindFirstChild("DeckWarsServer")
	local m = folder and folder:FindFirstChild("EconomyManager")
	if not m then
		return nil
	end
	local ok, econ = pcall(require, m)
	return ok and econ or nil
end

local function dataOf(player)
	return CampaignData.dataOf(player)
end

local function dirty(player)
	local econ = economy()
	if econ then
		pcall(econ.markDirty, player, "park")
	end
end

local function earnedTitles(d)
	return Campaign.titles(CampaignData.ensure(d))
end

---------------------------------------------------------------------------
-- Where in the world this server is: the park keeps the real time of day there (the client
-- turns it into the sky). Workspace.Park gets UtcOffset (seconds) and, when the place could be
-- looked up, Latitude, Longitude and ServerPlace ("City, Country"). The lookup needs "Allow HTTP
-- Requests" (Game Settings > Security); without it the server machine's own clock is used.
---------------------------------------------------------------------------

local HttpService = nil
pcall(function()
	HttpService = game:GetService("HttpService")
end)

local function getJson(url)
	if not HttpService then
		return nil
	end
	local ok, body = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not ok or type(body) ~= "string" then
		return nil
	end
	local ok2, data = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	return ok2 and type(data) == "table" and data or nil
end

local function locateServer()
	if type(Park.FixedPlace) == "table" then
		return Park.FixedPlace
	end
	local d = getJson("https://ipwho.is/")
	if d and d.success ~= false and type(d.latitude) == "number" and type(d.longitude) == "number" and type(d.timezone) == "table" and type(d.timezone.offset) == "number" then
		return { offset = d.timezone.offset, lat = d.latitude, lon = d.longitude, place = tostring(d.city or "") .. ", " .. tostring(d.country or "") }
	end
	d = getJson("http://ip-api.com/json/?fields=status,city,country,lat,lon,offset")
	if d and d.status == "success" and type(d.offset) == "number" and type(d.lat) == "number" and type(d.lon) == "number" then
		return { offset = d.offset, lat = d.lat, lon = d.lon, place = tostring(d.city or "") .. ", " .. tostring(d.country or "") }
	end
	return nil
end

-- The server machine's own offset from UTC (when the place can't be looked up).
local function machineOffset()
	local now = os.time()
	local here = os.date("*t", now)
	local utc = os.date("!*t", now)
	utc.isdst = false
	local ok, offset = pcall(function()
		return os.time(here) - os.time(utc)
	end)
	return ok and offset or 0
end

task.spawn(function()
	while true do
		local where = locateServer()
		if where then
			root:SetAttribute("UtcOffset", where.offset)
			root:SetAttribute("Latitude", where.lat)
			root:SetAttribute("Longitude", where.lon)
			root:SetAttribute("ServerPlace", where.place)
		elseif root:GetAttribute("Latitude") == nil then
			root:SetAttribute("UtcOffset", machineOffset())
		end
		-- (again now and then: summer time can start while a server runs; sooner if it didn't work)
		task.wait(where and 6 * 3600 or 300)
	end
end)

---------------------------------------------------------------------------
-- Your nameplate, and the Top Collector
---------------------------------------------------------------------------

local champion = nil -- the player on the pedestal
local updateChampion -- (below)

-- Puts a player's title, companion and collection on their attributes (nameplates, companions).
local function refresh(player)
	local d = dataOf(player)
	if not d then
		return
	end
	local title = Park.titleOf(d, earnedTitles(d))
	local _, hub = Park.ensure(d)
	local companion = Park.companionOf(d)
	local _, owned = Park.rarestCards(d, 0)
	pcall(function()
		player:SetAttribute("HubTitle", title or "")
		player:SetAttribute("Companion", companion or "")
		player:SetAttribute("CardsOwned", owned)
		local best = hub.best and CardData.Cards[hub.best.id]
		player:SetAttribute("BestRarity", best and best.rarity or "")
		player:SetAttribute("CampaignStars", Campaign.totalStars(CampaignData.ensure(d)))
	end)
	updateChampion()
end

-- The Top Collector's pose: the right hand raised to the card floating overhead, the head tipped
-- up to it, the left arm easy at the side. (Rotations of each joint, from its resting pose.)
local POSE = {
	RightShoulder = CFrame.Angles(math.rad(165), 0, math.rad(-15)),
	RightElbow = CFrame.Angles(math.rad(12), 0, 0),
	LeftShoulder = CFrame.Angles(0, 0, math.rad(-6)),
	Neck = CFrame.Angles(math.rad(14), 0, 0),
}

-- Stands the champion's own avatar on the pedestal (nil: an empty pedestal).
local avatarLoading = nil -- the player whose avatar is being made right now
local function placeAvatar(player)
	local old = stand and stand:FindFirstChild("Avatar")
	if old then
		old:Destroy()
	end
	local spot = stand and stand:FindFirstChild("AvatarSpot")
	if not (player and spot) then
		return
	end
	avatarLoading = player
	task.spawn(function()
		local made = false
		local function done()
			if avatarLoading == player then
				avatarLoading = nil
			end
			return made
		end
		local desc = nil
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			pcall(function()
				desc = hum:GetAppliedDescription()
			end)
		end
		if not desc then
			pcall(function()
				desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
			end)
		end
		if not desc then
			return done()
		end
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if not ok or not model then
			return done()
		end
		if champion ~= player or not stand.Parent or stand:FindFirstChild("Avatar") then
			model:Destroy() -- (someone else took the spot while it loaded)
			return done()
		end
		model.Name = "Avatar"
		local h = model:FindFirstChildOfClass("Humanoid")
		local rootPart = model:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			model:Destroy()
			return done()
		end
		if h then
			h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			h.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			h.BreakJointsOnDeath = false
			h.RequiresNeck = false
		end
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = p == rootPart
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
			elseif p:IsA("Motor6D") and POSE[p.Name] then
				p.C0 = p.C0 * POSE[p.Name]
			elseif p:IsA("Script") or p:IsA("LocalScript") then
				p:Destroy()
			end
		end
		-- feet on the pedestal, facing the way in
		local boxCf, size = model:GetBoundingBox()
		local rootAboveFeet = rootPart.Position.Y - (boxCf.Position.Y - size.Y / 2)
		model.PrimaryPart = rootPart
		model:PivotTo(CFrame.new(spot.Position + Vector3.new(0, rootAboveFeet, 0)) * spot.CFrame.Rotation)
		model.Parent = stand
		made = true
		done()
	end)
end

-- Picks the Top Collector out of everyone in the server and puts them on the pedestal.
local championQueued = false
local function pickChampion()
	championQueued = false
	if not stand then
		return
	end
	local entries = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local d = dataOf(p)
		if d then
			table.insert(entries, { id = p, d = d })
			-- (and everyone's card count, for the nameplates: a new player's starter cards often
			-- land just after their first refresh)
			local _, owned = Park.rarestCards(d, 0)
			pcall(function()
				p:SetAttribute("CardsOwned", owned)
			end)
		end
	end
	local best = Park.pickChampion(entries, champion)
	local who = best and best.id
	if who then
		local cards = Park.rarestCards(best.d, Park.ChampionCards)
		local _, count = Park.rarestCards(best.d, 0)
		stand:SetAttribute("ChampionId", who.UserId)
		stand:SetAttribute("ChampionName", who.DisplayName)
		stand:SetAttribute("Title", Park.titleOf(best.d, earnedTitles(best.d)) or "")
		stand:SetAttribute("Cards", table.concat(cards, ","))
		stand:SetAttribute("Count", count)
	else
		for _, a in ipairs({ "ChampionId", "ChampionName", "Title", "Cards", "Count" }) do
			stand:SetAttribute(a, nil)
		end
	end
	if who ~= champion then
		champion = who
		placeAvatar(who)
	elseif who and not stand:FindFirstChild("Avatar") and avatarLoading ~= who then
		placeAvatar(who) -- (it didn't load last time: try again)
	end
end

-- (a little later, once: several saves often change at once)
function updateChampion()
	if championQueued then
		return
	end
	championQueued = true
	task.delay(1, function()
		pcall(pickChampion)
	end)
end

---------------------------------------------------------------------------
-- Walking in and out
---------------------------------------------------------------------------

local inPark = {} -- [player] = true
local entered = 0

local function roomSpawn()
	local room = workspace:FindFirstChild("MenuRoom")
	local spawn = room and room:FindFirstChild("SpawnLocation", true)
	if spawn then
		return spawn.CFrame + Vector3.new(0, 3.5, 0)
	end
	return CFrame.new(0, 5, 0)
end

local function pivot(player, cf)
	local char = player.Character
	if char and char.PrimaryPart then
		char:PivotTo(cf)
		local root_ = char:FindFirstChild("HumanoidRootPart")
		if root_ then
			root_.AssemblyLinearVelocity = Vector3.zero
		end
		return true
	end
	return false
end

-- The big pulls on the Hall of Pulls (newest first) and the leaderboards.
local hall = {}
local boards = {}

local function enter(player)
	inPark[player] = true
	entered += 1
	pivot(player, Park.spawnCFrame(entered))
	pcall(function()
		player:SetAttribute("InPark", true)
	end)
	refresh(player)
	ParkEvent:FireClient(player, { kind = "entered", hall = hall, boards = boards })
end

local function leave(player)
	if not inPark[player] then
		return
	end
	inPark[player] = nil
	TradeDesk.drop(player) -- (a trade or a request to trade ends when you go home)
	pivot(player, roomSpawn())
	pcall(function()
		player:SetAttribute("InPark", false)
	end)
	ParkEvent:FireClient(player, { kind = "left" })
end

local function stateFor(player)
	local d = dataOf(player)
	if not d then
		return { kind = "state", loading = true }
	end
	local showcase = Park.ensure(d)
	local earned = earnedTitles(d)
	local owned = {}
	for id, n in pairs(d.collection or {}) do
		if n > 0 and CardData.Cards[id] and not CardData.Cards[id].token then
			table.insert(owned, id)
		end
	end
	Park.sortRarest(owned)
	return {
		kind = "state",
		picked = showcase.cards,
		showing = Park.showcaseOf(d),
		owned = owned,
		titles = Park.titlesOf(d, earned),
		title = Park.titleOf(d, earned),
		companion = Park.companionOf(d),
	}
end

---------------------------------------------------------------------------
-- Trading cards at the Trading Post. TradeDesk runs the steps of a trade (ask, offer, lock in,
-- confirm); the rules are in ReplicatedStorage.DeckWars.Trade. Both players have to stay within
-- Trade.Radius of Park.TradingPost.Desk (the part with the "Trade" prompt).
---------------------------------------------------------------------------

local function tradeDeskPart()
	local post = root:FindFirstChild("TradingPost")
	return post and post:FindFirstChild("Desk")
end

TradeDesk.init({
	send = function(player, payload)
		if typeof(player) == "Instance" and player.Parent then
			ParkEvent:FireClient(player, payload)
		end
	end,
	dataOf = dataOf,
	near = function(player)
		local desk = tradeDeskPart()
		local char = typeof(player) == "Instance" and player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		return inPark[player] == true and desk ~= nil and hrp ~= nil and (hrp.Position - desk.Position).Magnitude <= Trade.Radius
	end,
	playerById = function(userId)
		if type(userId) ~= "number" or userId ~= userId then
			return nil
		end
		local ok, found = pcall(function()
			return Players:GetPlayerByUserId(userId)
		end)
		return ok and found or nil
	end,
	changed = function(player)
		dirty(player)
		refresh(player) -- (your companion, your card count and the Top Collector follow your cards)
	end,
	save = function(player)
		local econ = economy()
		if econ and econ.saveNow then
			task.spawn(pcall, econ.saveNow, player)
		end
	end,
	now = time,
	clock = os.time,
})

task.spawn(function()
	while true do
		task.wait(0.5)
		pcall(TradeDesk.step)
	end
end)

-- Developers can try the trade window on their own: from the server,
--   game.ServerScriptService.TradePractice:Fire(player)
-- opens a trade with a pretend partner (TradeDesk.practice). No remote reaches this.
do
	local practice = Instance.new("BindableEvent")
	practice.Name = "TradePractice"
	practice.Parent = ServerScriptService
	practice.Event:Connect(function(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		local folder = ServerStorage:FindFirstChild("DeckWarsServer")
		local mod = folder and folder:FindFirstChild("DevAccess")
		local ok, DevAccess = pcall(require, mod)
		if ok and type(DevAccess) == "table" and DevAccess.isDev(player) then
			TradeDesk.practice(player)
		end
	end)
end

local lastAction = {}
ParkAction.OnServerEvent:Connect(function(player, what, options)
	if type(what) ~= "string" then
		return
	end
	options = type(options) == "table" and options or {}
	if TradeDesk.handle(player, what, options) then
		return -- (trade actions keep their own pace: see TradeDesk)
	end
	local now = time()
	if lastAction[player] and now - lastAction[player] < 0.25 then
		return
	end
	lastAction[player] = now
	if what == "Enter" then
		enter(player)
	elseif what == "Leave" then
		leave(player)
	elseif what == "State" then
		ParkEvent:FireClient(player, stateFor(player))
	elseif what == "SetShowcase" then
		local d = dataOf(player)
		if not d then
			return
		end
		local ok, why = Park.setShowcase(d, options.cards)
		if not ok then
			ParkEvent:FireClient(player, { kind = "toast", text = why })
			return
		end
		dirty(player)
		refresh(player)
		ParkEvent:FireClient(player, stateFor(player))
	elseif what == "SetTitle" then
		local d = dataOf(player)
		if not d then
			return
		end
		local ok, why = Park.setTitle(d, earnedTitles(d), options.title)
		if not ok then
			ParkEvent:FireClient(player, { kind = "toast", text = why })
			return
		end
		dirty(player)
		refresh(player)
		ParkEvent:FireClient(player, stateFor(player))
	end
end)

local function onJoin(player)
	player.CharacterAdded:Connect(function()
		if inPark[player] then
			-- (respawned while in the Park: back to the gate)
			task.defer(function()
				for _ = 1, 20 do
					if pivot(player, Park.spawnCFrame(entered)) then
						break
					end
					task.wait(0.1)
				end
			end)
		end
	end)
	task.spawn(function()
		for _ = 1, 60 do
			if not player.Parent then
				return
			end
			if dataOf(player) then
				refresh(player)
				return
			end
			task.wait(0.5)
		end
	end)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do
	onJoin(p)
end

Players.PlayerRemoving:Connect(function(player)
	inPark[player] = nil
	lastAction[player] = nil
	TradeDesk.drop(player, true)
	if champion == player then
		champion = nil
		placeAvatar(nil)
	end
	updateChampion()
end)

-- Every so often everyone catches up with things won elsewhere (Campaign titles, new cards), and
-- the Top Collector with them.
task.spawn(function()
	while true do
		task.wait(20)
		for _, player in ipairs(Players:GetPlayers()) do
			pcall(refresh, player)
		end
	end
end)

---------------------------------------------------------------------------
-- Big pulls
---------------------------------------------------------------------------

local MessagingService = nil
pcall(function()
	MessagingService = game:GetService("MessagingService")
end)
local lastCross = -math.huge

local function addToHall(entry)
	table.insert(hall, 1, entry)
	while #hall > Park.HallSize do
		table.remove(hall)
	end
	ParkEvent:FireAllClients({ kind = "hall", hall = hall })
end

local function announce(entry)
	ParkEvent:FireAllClients({ kind = "bigPull", name = entry.name, card = entry.card, rarity = entry.rarity, shiny = entry.shiny, far = entry.far, userId = entry.userId })
	addToHall(entry)
end

-- Cross-server messages leave at most one every CrossServerGap seconds; the rest wait in line.
local crossQueue = {}
local crossBusy = false
local function publishCross(entry)
	if not MessagingService then
		return
	end
	table.insert(crossQueue, entry)
	if crossBusy then
		return
	end
	crossBusy = true
	task.spawn(function()
		while #crossQueue > 0 do
			local left = Park.CrossServerGap - (time() - lastCross)
			if left > 0 then
				task.wait(left)
			end
			local e = table.remove(crossQueue, 1)
			lastCross = time()
			pcall(function()
				MessagingService:PublishAsync(Park.CrossServerTopic, { name = e.name, card = e.card, shiny = e.shiny, job = game.JobId })
			end)
		end
		crossBusy = false
	end)
end

feed.Event:Connect(function(player, cards, test)
	if typeof(player) ~= "Instance" or type(cards) ~= "table" then
		return
	end
	test = test == true -- (a free or forced developer roll: announced in this server only)
	local ids = {}
	local shinyOf = {}
	for _, c in ipairs(cards) do
		local id = type(c) == "table" and c.id or c
		if type(id) == "string" and CardData.Cards[id] then
			table.insert(ids, id)
			if type(c) == "table" and c.shiny == true then
				shinyOf[id] = true
			end
		end
	end
	local d = dataOf(player)
	if d and not test and Park.notePull(d, ids) then
		dirty(player)
	end
	if d and not test then
		refresh(player)
	end
	-- the rarest card of the pull (a Shiny one first), if it is worth a banner
	local sorted = Park.sortRarest(table.clone(ids))
	local best = sorted[1]
	for _, id in ipairs(sorted) do
		if shinyOf[id] then
			best = id
			break
		end
	end
	local level = best and Park.announceLevel(best, shinyOf[best])
	if not level then
		return
	end
	local entry = { name = player.DisplayName, card = best, rarity = CardData.Cards[best].rarity, shiny = shinyOf[best] or nil, userId = player.UserId, at = os.time() }
	task.delay(Park.FeedDelay, function()
		if test then
			ParkEvent:FireAllClients({ kind = "bigPull", name = entry.name, card = entry.card, rarity = entry.rarity, shiny = entry.shiny, userId = entry.userId })
			return
		end
		announce(entry)
		if level == "cross" then
			publishCross(entry)
		end
	end)
end)

if MessagingService then
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(Park.CrossServerTopic, function(message)
				local m = type(message) == "table" and message.Data
				if type(m) ~= "table" or m.job == game.JobId or type(m.card) ~= "string" then
					return
				end
				local card = CardData.Cards[m.card]
				if not card then
					return
				end
				announce({ name = tostring(m.name):sub(1, 30), card = m.card, rarity = card.rarity, shiny = m.shiny == true or nil, at = os.time(), far = true })
			end)
		end)
	end)
end

---------------------------------------------------------------------------
-- Leaderboards
---------------------------------------------------------------------------

local function valueFor(key, player)
	local d = dataOf(player)
	if not d then
		return nil
	end
	if key == "Stars" then
		return Campaign.totalStars(CampaignData.ensure(d))
	elseif key == "Level" then
		return tonumber(d.level) or 1
	end
	return nil
end

local names = {}
local function nameOf(userId)
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return names[userId]
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	names[userId] = ok and n or ("Player " .. userId)
	return names[userId]
end

local DataStoreService = nil
pcall(function()
	DataStoreService = game:GetService("DataStoreService")
end)

local function updateBoards()
	local out = {}
	for _, def in ipairs(Park.Boards) do
		local rows = nil
		local ok = DataStoreService ~= nil and pcall(function()
			local store = DataStoreService:GetOrderedDataStore(def.store)
			for _, p in ipairs(Players:GetPlayers()) do
				local v = valueFor(def.key, p)
				if v and v > 0 then
					store:SetAsync(tostring(p.UserId), math.floor(v))
				end
			end
			local pages = store:GetSortedAsync(false, Park.BoardSize)
			rows = {}
			for _, entry in ipairs(pages:GetCurrentPage()) do
				local id = tonumber(entry.key)
				if id then
					table.insert(rows, { name = nameOf(id), value = entry.value })
				end
			end
		end)
		if not ok or rows == nil then
			-- no DataStores (Studio without API access, or an outage): this server's players
			rows = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local v = valueFor(def.key, p)
				if v then
					table.insert(rows, { name = p.DisplayName, value = v })
				end
			end
			table.sort(rows, function(a, b)
				return a.value > b.value
			end)
			while #rows > Park.BoardSize do
				table.remove(rows)
			end
		end
		out[def.key] = rows
	end
	boards = out
	ParkEvent:FireAllClients({ kind = "boards", boards = boards })
end

task.spawn(function()
	task.wait(10)
	while true do
		pcall(updateBoards)
		task.wait(Park.BoardSeconds)
	end
end)

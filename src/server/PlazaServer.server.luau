-- The Plaza's server: builds the place (PlazaBuilder), gives every player a booth, walks
-- characters in and out, takes likes and showcase picks, announces big pulls (to this server and,
-- for Secrets, to every server) and keeps the leaderboards. The rules and numbers are in
-- ReplicatedStorage.DeckWars.Plaza; the screen is PlazaClient.
--
-- Remotes (ReplicatedStorage.PlazaRemotes):
--   PlazaAction (client -> server): "Enter", "Leave", "State", "SetShowcase" { cards },
--                                   "SetTitle" { title }
--   PlazaEvent  (server -> client): { kind = "entered" | "left" | "state" | "bigPull" | "hall" |
--                                   "boards" | "liked" | "likedBy" | "toast", ... }
-- PullServer fires ServerScriptService.PullFeed (a BindableEvent made here) after each paid pull.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local Plaza = require(Shared:WaitForChild("Plaza"))
local CardData = require(Shared:WaitForChild("CardData"))
local Campaign = require(Shared:WaitForChild("Campaign"))
local PlazaBuilder = require(script.Parent:WaitForChild("PlazaBuilder"))
local CampaignData = require(script.Parent:WaitForChild("CampaignData"))

local remotes = ReplicatedStorage:WaitForChild("PlazaRemotes")
local PlazaAction = remotes:WaitForChild("PlazaAction")
local PlazaEvent = remotes:WaitForChild("PlazaEvent")

local feed = ServerScriptService:FindFirstChild("PullFeed")
if not feed then
	feed = Instance.new("BindableEvent")
	feed.Name = "PullFeed"
	feed.Parent = ServerScriptService
end

local root = PlazaBuilder.build(workspace)
local boothFolder = root:WaitForChild("Booths")

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
		pcall(econ.markDirty, player, "plaza")
	end
end

local function earnedTitles(d)
	return Campaign.titles(CampaignData.ensure(d))
end

---------------------------------------------------------------------------
-- Booths
---------------------------------------------------------------------------

local boothOf = {} -- [player] = slot
local ownerOf = {} -- [slot] = player

local function boothModel(slot)
	return boothFolder:FindFirstChild("Booth" .. slot)
end

-- Puts a player's showcase, title and likes on their booth and their own attributes.
local function refresh(player)
	local d = dataOf(player)
	if not d then
		return
	end
	local cards = Plaza.showcaseOf(d)
	local title = Plaza.titleOf(d, earnedTitles(d))
	local _, hub = Plaza.ensure(d)
	local companion = Plaza.companionOf(d)
	pcall(function()
		player:SetAttribute("HubTitle", title or "")
		player:SetAttribute("Companion", companion or "")
		player:SetAttribute("BoothLikes", hub.likes)
		local best = hub.best and CardData.Cards[hub.best.id]
		player:SetAttribute("BestRarity", best and best.rarity or "")
		player:SetAttribute("CampaignStars", Campaign.totalStars(CampaignData.ensure(d)))
	end)
	local slot = boothOf[player]
	local m = slot and boothModel(slot)
	if m then
		m:SetAttribute("OwnerId", player.UserId)
		m:SetAttribute("OwnerName", player.DisplayName)
		m:SetAttribute("Title", title or "")
		m:SetAttribute("Likes", hub.likes)
		m:SetAttribute("Cards", table.concat(cards, ","))
		local heart = m:FindFirstChild("Heart")
		local like = heart and heart:FindFirstChild("Like")
		if like then
			like.Enabled = true
			like.ObjectText = player.DisplayName .. "'s booth"
		end
	end
end

local function clearBooth(slot)
	local m = boothModel(slot)
	if not m then
		return
	end
	for _, a in ipairs({ "OwnerId", "OwnerName", "Title", "Likes", "Cards" }) do
		m:SetAttribute(a, nil)
	end
	local heart = m:FindFirstChild("Heart")
	local like = heart and heart:FindFirstChild("Like")
	if like then
		like.Enabled = false
	end
end

local function assignBooth(player)
	if boothOf[player] then
		return boothOf[player]
	end
	for slot = 1, Plaza.Booths do
		if not ownerOf[slot] and boothModel(slot) then
			ownerOf[slot] = player
			boothOf[player] = slot
			pcall(function()
				player:SetAttribute("BoothSlot", slot)
			end)
			return slot
		end
	end
	return nil
end

-- Likes: the heart on each booth (its ProximityPrompt is handled right here on the server).
local function onLike(slot, liker)
	local owner = ownerOf[slot]
	if not owner or not owner.Parent then
		return
	end
	local dl, dOwner = dataOf(liker), dataOf(owner)
	if not (dl and dOwner) then
		PlazaEvent:FireClient(liker, { kind = "toast", text = "Your save is still loading." })
		return
	end
	local ok, why = Plaza.like(dl, liker.UserId, dOwner, owner.UserId)
	if not ok then
		PlazaEvent:FireClient(liker, { kind = "toast", text = why })
		return
	end
	dirty(liker)
	dirty(owner)
	refresh(owner)
	PlazaEvent:FireClient(liker, { kind = "liked", slot = slot, name = owner.DisplayName })
	PlazaEvent:FireClient(owner, { kind = "likedBy", name = liker.DisplayName, likes = Plaza.ensure(dOwner) and dOwner.hub.likes })
end

for slot = 1, Plaza.Booths do
	local m = boothModel(slot)
	local heart = m and m:FindFirstChild("Heart")
	local like = heart and heart:FindFirstChild("Like")
	if like then
		like.Triggered:Connect(function(who)
			onLike(slot, who)
		end)
	end
end

---------------------------------------------------------------------------
-- Walking in and out
---------------------------------------------------------------------------

local inPlaza = {} -- [player] = true
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
	inPlaza[player] = true
	entered += 1
	pivot(player, Plaza.spawnCFrame(entered))
	pcall(function()
		player:SetAttribute("InPlaza", true)
	end)
	refresh(player)
	PlazaEvent:FireClient(player, { kind = "entered", hall = hall, boards = boards })
end

local function leave(player)
	if not inPlaza[player] then
		return
	end
	inPlaza[player] = nil
	pivot(player, roomSpawn())
	pcall(function()
		player:SetAttribute("InPlaza", false)
	end)
	PlazaEvent:FireClient(player, { kind = "left" })
end

local function stateFor(player)
	local d = dataOf(player)
	if not d then
		return { kind = "state", loading = true }
	end
	local showcase = Plaza.ensure(d)
	local earned = earnedTitles(d)
	local owned = {}
	for id, n in pairs(d.collection or {}) do
		if n > 0 and CardData.Cards[id] and not CardData.Cards[id].token then
			table.insert(owned, id)
		end
	end
	Plaza.sortRarest(owned)
	return {
		kind = "state",
		picked = showcase.cards,
		showing = Plaza.showcaseOf(d),
		owned = owned,
		titles = Plaza.titlesOf(d, earned),
		title = Plaza.titleOf(d, earned),
		likes = d.hub.likes,
		booth = boothOf[player],
	}
end

local lastAction = {}
PlazaAction.OnServerEvent:Connect(function(player, what, options)
	if type(what) ~= "string" then
		return
	end
	options = type(options) == "table" and options or {}
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
		PlazaEvent:FireClient(player, stateFor(player))
	elseif what == "SetShowcase" then
		local d = dataOf(player)
		if not d then
			return
		end
		local ok, why = Plaza.setShowcase(d, options.cards)
		if not ok then
			PlazaEvent:FireClient(player, { kind = "toast", text = why })
			return
		end
		dirty(player)
		refresh(player)
		PlazaEvent:FireClient(player, stateFor(player))
	elseif what == "SetTitle" then
		local d = dataOf(player)
		if not d then
			return
		end
		local ok, why = Plaza.setTitle(d, earnedTitles(d), options.title)
		if not ok then
			PlazaEvent:FireClient(player, { kind = "toast", text = why })
			return
		end
		dirty(player)
		refresh(player)
		PlazaEvent:FireClient(player, stateFor(player))
	end
end)

local function onJoin(player)
	player.CharacterAdded:Connect(function()
		if inPlaza[player] then
			-- (respawned while in the Plaza: back to the gate)
			task.defer(function()
				for _ = 1, 20 do
					if pivot(player, Plaza.spawnCFrame(entered)) then
						break
					end
					task.wait(0.1)
				end
			end)
		end
	end)
	task.spawn(function()
		assignBooth(player)
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
	local slot = boothOf[player]
	if slot then
		ownerOf[slot] = nil
		clearBooth(slot)
	end
	boothOf[player] = nil
	inPlaza[player] = nil
	lastAction[player] = nil
end)

-- Every so often the booths catch up with things won elsewhere (Campaign titles, new cards).
task.spawn(function()
	while true do
		task.wait(20)
		for player in pairs(boothOf) do
			if player.Parent then
				pcall(refresh, player)
			end
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
	while #hall > Plaza.HallSize do
		table.remove(hall)
	end
	PlazaEvent:FireAllClients({ kind = "hall", hall = hall })
end

local function announce(entry)
	PlazaEvent:FireAllClients({ kind = "bigPull", name = entry.name, card = entry.card, rarity = entry.rarity, far = entry.far })
	addToHall(entry)
end

feed.Event:Connect(function(player, cards)
	if typeof(player) ~= "Instance" or type(cards) ~= "table" then
		return
	end
	local ids = {}
	for _, c in ipairs(cards) do
		local id = type(c) == "table" and c.id or c
		if type(id) == "string" and CardData.Cards[id] then
			table.insert(ids, id)
		end
	end
	local d = dataOf(player)
	if d and Plaza.notePull(d, ids) then
		dirty(player)
	end
	if d then
		refresh(player)
	end
	-- the rarest card of the pull, if it is worth a banner
	local sorted = Plaza.sortRarest(table.clone(ids))
	local best = sorted[1]
	local level = best and Plaza.announceLevel(best)
	if not level then
		return
	end
	local entry = { name = player.DisplayName, card = best, rarity = CardData.Cards[best].rarity, at = os.time() }
	task.delay(Plaza.FeedDelay, function()
		announce(entry)
		if level == "cross" and MessagingService and time() - lastCross >= Plaza.CrossServerGap then
			lastCross = time()
			pcall(function()
				MessagingService:PublishAsync(Plaza.CrossServerTopic, { name = entry.name, card = entry.card, job = game.JobId })
			end)
		end
	end)
end)

if MessagingService then
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(Plaza.CrossServerTopic, function(message)
				local m = type(message) == "table" and message.Data
				if type(m) ~= "table" or m.job == game.JobId or type(m.card) ~= "string" then
					return
				end
				local card = CardData.Cards[m.card]
				if not card then
					return
				end
				announce({ name = tostring(m.name):sub(1, 30), card = m.card, rarity = card.rarity, at = os.time(), far = true })
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
	elseif key == "Likes" then
		local _, hub = Plaza.ensure(d)
		return hub.likes
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
	for _, def in ipairs(Plaza.Boards) do
		local rows = nil
		local ok = DataStoreService ~= nil and pcall(function()
			local store = DataStoreService:GetOrderedDataStore(def.store)
			for _, p in ipairs(Players:GetPlayers()) do
				local v = valueFor(def.key, p)
				if v and v > 0 then
					store:SetAsync(tostring(p.UserId), math.floor(v))
				end
			end
			local pages = store:GetSortedAsync(false, Plaza.BoardSize)
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
			while #rows > Plaza.BoardSize do
				table.remove(rows)
			end
		end
		out[def.key] = rows
	end
	boards = out
	PlazaEvent:FireAllClients({ kind = "boards", boards = boards })
end

task.spawn(function()
	task.wait(10)
	while true do
		pcall(updateBoards)
		task.wait(Plaza.BoardSeconds)
	end
end)

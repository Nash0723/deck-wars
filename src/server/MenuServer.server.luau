-- Deck Wars menu server: the player's settings (Settings window) and saved decks (the Deck
-- Shelf's deck builder), plus the starter collection for new players.
-- Matches, lobbies, parties and rewards live in MatchServer; this script only answers these
-- MenuAction requests: LoadSettings, SaveSettings, GetDecks, SaveDeck, DeleteDeck, ClaimAchievement,
-- and the Deck Shelf's cards: FuseCard { id, level }, FuseAll { id }, FuseEverything, SellCard { id, level }
-- (each answered with "CardResult" and a fresh "Decks" snapshot; see CardLevels for the rules),
-- and the Enchanting Crystal's Enchant { id, mode = "shards" | "lucky" } and EnchantChoose
-- { keep = "new" | "old" } (see Enchants).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local Settings = require(Shared:WaitForChild("Settings"))
local PlayerDecks = require(ServerScriptService:WaitForChild("PlayerDecks"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local EconomyManager = require(game:GetService("ServerStorage"):WaitForChild("DeckWarsServer"):WaitForChild("EconomyManager"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MenuAction = Remotes:WaitForChild("MenuAction")
local LobbyEvent = Remotes:WaitForChild("LobbyEvent")

---------------------------------------------------------------------------
-- Player settings: kept in a DataStore so they are the same next visit.
-- In Studio this only works with Game Settings > Security > "Enable Studio Access to API
-- Services" turned on; without it (or if Roblox's DataStores are down) settings just
-- last until the player leaves, and nothing breaks.
---------------------------------------------------------------------------
local SETTINGS_SAVE_GAP = 15 -- seconds between DataStore writes per player (Roblox limits writes)
local settingsStore = nil
pcall(function()
	settingsStore = game:GetService("DataStoreService"):GetDataStore("DeckWarsSettings_v1")
end)
local playerSettings = {} -- [player] = { values = {...}, dirty = bool, lastSave = time }

local function settingsKey(player)
	return "u" .. player.UserId
end

local function loadSettings(player)
	local entry = playerSettings[player]
	if entry then
		return entry
	end
	entry = { values = Settings.sanitize(nil), dirty = false, lastSave = 0, loaded = false }
	playerSettings[player] = entry
	if settingsStore then
		local ok, data = pcall(function()
			return settingsStore:GetAsync(settingsKey(player))
		end)
		if ok and type(data) == "table" and not entry.dirty then -- (a save that came in meanwhile wins)
			entry.values = Settings.sanitize(data)
		end
	end
	entry.loaded = true
	return entry
end

local function saveSettings(player, entry)
	if not settingsStore or not entry.dirty then
		return
	end
	entry.dirty = false
	entry.lastSave = os.clock()
	local values = entry.values
	local ok, err = pcall(function()
		settingsStore:SetAsync(settingsKey(player), values)
	end)
	if not ok then
		warn("Deck Wars: could not save settings for " .. player.Name .. ": " .. tostring(err))
	end
end

task.spawn(function()
	while true do
		task.wait(5)
		for player, entry in pairs(playerSettings) do
			if entry.dirty and os.clock() - entry.lastSave >= SETTINGS_SAVE_GAP then
				task.spawn(saveSettings, player, entry)
			end
		end
	end
end)

pcall(function()
	game:BindToClose(function()
		-- all at once (one after another could run past the shutdown's 30 seconds on a full server)
		local left = 0
		for player, entry in pairs(playerSettings) do
			left += 1
			task.spawn(function()
				saveSettings(player, entry)
				left -= 1
			end)
		end
		local t0 = os.clock()
		while left > 0 and os.clock() - t0 < 25 do
			task.wait(0.1)
		end
	end)
end)

-- Deck and reward requests cost a profile read (and a save mark): a client may send at most 12
-- every 5 seconds.
local deckCalls = setmetatable({}, { __mode = "k" }) -- [player] = { t = window start, n = calls }
local function deckCallAllowed(player)
	local now = time()
	local c = deckCalls[player]
	if not c or now - c.t > 5 then
		c = { t = now, n = 0 }
		deckCalls[player] = c
	end
	c.n += 1
	return c.n <= 12
end

local CARD_ACTIONS = { FuseCard = true, FuseAll = true, FuseEverything = true, SellCard = true, Enchant = true, EnchantChoose = true }
-- (everything else that reads or writes the profile counts against the same limit)
local LIMITED = { GetDecks = true, SaveDeck = true, DeleteDeck = true, ClaimAchievement = true, ClaimRoad = true }

-- Fusing and selling: does it, tells the screen how it went, and sends the new collection.
local function cardAction(player, what, options)
	options = type(options) == "table" and options or {}
	local id = type(options.id) == "string" and options.id or nil
	local level = tonumber(options.level)
	local result = { what = what, id = id, level = level }
	if what == "FuseCard" then
		local ok, r = EconomyManager.fuseCard(player, id, level)
		result.ok = ok
		if ok then
			result.made = { r }
		else
			result.why = r
		end
	elseif what == "FuseAll" then
		local ok, n, made = EconomyManager.fuseAllCopies(player, id)
		result.ok = ok
		if ok then
			result.count, result.made = n, made
		else
			result.why = n
		end
	elseif what == "FuseEverything" then
		local ok, n, best = EconomyManager.fuseEverything(player)
		result.ok = ok
		if ok then
			result.count, result.best = n, best
		else
			result.why = n
		end
	elseif what == "Enchant" then
		-- the Enchanting Crystal in the Park (rules and odds in Enchants)
		local ok, r = EconomyManager.enchantCard(player, id, options.mode == "lucky" and "lucky" or "shards")
		result.ok = ok
		if ok then
			result.id, result.enchant, result.rarity, result.old, result.pending, result.pity = r.card, r.enchant, r.rarity, r.old, r.pending, r.pity
		else
			result.why = r
		end
	elseif what == "EnchantChoose" then
		local ok, r = EconomyManager.chooseEnchant(player, options.keep == "new")
		result.ok = ok
		if ok then
			result.id, result.enchant, result.kept = r.card, r.enchant, r.kept
		else
			result.why = r
		end
	elseif what == "SellCard" then
		local ok, r = EconomyManager.sellCard(player, id, level)
		result.ok = ok
		if ok then
			result.coins = r
		else
			result.why = r
		end
	end
	MenuAction:FireClient(player, "CardResult", result)
	local snap = PlayerDecks.snapshot(player)
	if snap then
		MenuAction:FireClient(player, "Decks", snap)
	end
	-- the Quest Hall's "enchant cards" and "fuse cards" quests
	if result.ok and PlayerData.noteQuest then
		if what == "Enchant" then
			PlayerData.noteQuest(player, "enchant", 1)
		elseif what == "FuseCard" or what == "FuseAll" or what == "FuseEverything" then
			PlayerData.noteQuest(player, "fuse", math.max(1, math.floor(tonumber(result.count) or 1)))
		end
	end
end

MenuAction.OnServerEvent:Connect(function(player, what, options)
	if (LIMITED[what] or CARD_ACTIONS[what]) and not deckCallAllowed(player) then
		return
	end
	if CARD_ACTIONS[what] then
		cardAction(player, what, options)
		return
	end
	if what == "LoadSettings" then
		local entry = loadSettings(player)
		MenuAction:FireClient(player, "Settings", entry.values)
	elseif what == "SaveSettings" and type(options) == "table" then
		local entry = loadSettings(player)
		entry.values = Settings.sanitize(options)
		entry.dirty = true
	elseif what == "GetDecks" then
		local snap = PlayerDecks.snapshot(player)
		if snap then
			MenuAction:FireClient(player, "Decks", snap)
		end
	elseif what == "SaveDeck" and type(options) == "table" then
		local ok, problems = PlayerDecks.saveDeck(player, options.slot, options.deck)
		MenuAction:FireClient(player, "DeckSaved", { slot = options.slot, ok = ok, problems = problems })
		local snap = PlayerDecks.snapshot(player)
		if snap then
			MenuAction:FireClient(player, "Decks", snap)
		end
	elseif what == "DeleteDeck" and type(options) == "table" then
		PlayerDecks.deleteDeck(player, options.slot)
		local snap = PlayerDecks.snapshot(player)
		if snap then
			MenuAction:FireClient(player, "Decks", snap)
		end
	elseif what == "ClaimAchievement" and type(options) == "table" then
		local r = PlayerData.claimAchievement(player, options.id)
		LobbyEvent:FireClient(player, { kind = "claimed", what = "achievement", ok = r ~= nil, id = options.id, gems = r and r.gems, shards = r and r.shards })
	elseif what == "ClaimRoad" and type(options) == "table" then
		local r = PlayerData.claimRoad and PlayerData.claimRoad(player, options.index)
		LobbyEvent:FireClient(player, { kind = "claimed", what = "road", ok = r ~= nil, index = options.index, gems = r and r.gems, coins = r and r.coins, shards = r and r.shards, cosmetic = r and r.cosmetic })
	end
end)

-- New players get the starter collection (4 starter characters and the Starter Deck).
local function welcome(player)
	task.spawn(function()
		pcall(PlayerDecks.ensureStarter, player)
		PlayerData.publish(player)
	end)
end
Players.PlayerAdded:Connect(welcome)
for _, player in ipairs(Players:GetPlayers()) do
	welcome(player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerDecks.forget(player)
	local entry = playerSettings[player]
	if entry then
		playerSettings[player] = nil
		saveSettings(player, entry)
	end
end)

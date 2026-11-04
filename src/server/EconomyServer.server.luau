-- Deck Wars economy server: loads every player's save (Gems, Coins, cards, cosmetics) with a
-- session lock, runs the Shop, Robux Gem bundles and the developer tools.
-- The rules and numbers live in ServerStorage.DeckWarsServer.EconomyManager and
-- ReplicatedStorage.DeckWars.ShopCatalog.
--
-- Saving in Studio needs Game Settings > Security > "Enable Studio Access to API Services".
-- Without it the game still runs, but nothing is saved after you stop (you'll see a notice).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local serverModules = ServerStorage:WaitForChild("DeckWarsServer")
local EconomyManager = require(serverModules:WaitForChild("EconomyManager"))
local DevAccess = require(serverModules:WaitForChild("DevAccess"))
local ProfileStore = require(serverModules:WaitForChild("ProfileStore"))
local ShopCatalog = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("ShopCatalog"))

local remotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local ShopAction = remotes:WaitForChild("ShopAction") -- client -> server: Snapshot, Buy, Equip, BuyGems, Emote
local EconomyEvent = remotes:WaitForChild("EconomyEvent") -- server -> client: snapshot, result, daily, reward, notice, emote, dev
local DevAction = remotes:WaitForChild("DevAction") -- client -> server, developers only

local SAVE_NAME = "DeckWarsPlayer_v1" -- the DataStore (change the _v1 to start everyone fresh)
local AUTOSAVE_SECONDS = 60
local ACTION_GAP = 0.2 -- seconds between Shop requests per player (spam guard)
local DEV_GIVE_MAX = 1000000

---------------------------------------------------------------------------
-- Pick the DataStore (or a memory store in Studio without API access)
---------------------------------------------------------------------------
local dataStore, memoryOnly = nil, false
do
	local ok, ds = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore(SAVE_NAME)
	end)
	if ok and ds then
		-- In Studio a place without API access fails on the first request, so try one.
		local probeOk = true
		if RunService:IsStudio() then
			probeOk = pcall(function()
				ds:GetAsync("probe")
			end)
		end
		if probeOk then
			dataStore = ds
		end
	end
	if not dataStore then
		memoryOnly = true
		dataStore = ProfileStore.memoryStore()
		warn("Deck Wars: DataStores aren't available (in Studio: Game Settings > Security > Enable Studio Access to API Services). Gems, Coins and cards will NOT be saved this session.")
	end
end

---------------------------------------------------------------------------
-- Telling the client
---------------------------------------------------------------------------
local pendingSnapshot = {}
local restricted = {} -- [player] = true when Robux Gem bundles aren't allowed (paid random items)

local function sendSnapshot(player)
	pendingSnapshot[player] = nil
	if player.Parent == nil then
		return
	end
	local snap = EconomyManager.snapshot(player)
	if snap then
		snap.gemsRestricted = restricted[player] == true
		EconomyEvent:FireClient(player, "snapshot", snap)
	end
end

-- Many changes in one frame send one snapshot.
local function queueSnapshot(player)
	if pendingSnapshot[player] then
		return
	end
	pendingSnapshot[player] = true
	task.defer(sendSnapshot, player)
end

EconomyManager.init({
	dataStore = dataStore,
	memoryOnly = memoryOnly,
	jobId = (game.JobId ~= "" and game.JobId) or ("studio-" .. tostring(math.random(1, 1e9))),
	onChanged = function(player)
		if typeof(player) == "Instance" then
			queueSnapshot(player)
		end
	end,
	onStolen = function(player)
		if player.Parent then
			player:Kick("Your Deck Wars save was opened in another server. Please rejoin.")
		end
	end,
	isDev = DevAccess.isDev,
})

-- For other server scripts (MatchServer's match rewards): EconomyManager.announce(player, kind, payload)
EconomyManager.announce = function(player, kind, payload)
	if typeof(player) == "Instance" and player.Parent then
		EconomyEvent:FireClient(player, kind, payload)
	end
end

task.spawn(DevAccess.resolve)

---------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------
local devTemplate = ServerStorage:FindFirstChild("DevControls")

local function giveDevControls(player)
	DevAccess.resolve()
	if not DevAccess.isDev(player) or not devTemplate then
		return
	end
	local pg = player:WaitForChild("PlayerGui", 30)
	if pg and not pg:FindFirstChild(devTemplate.Name) then
		local copy = devTemplate:Clone()
		copy:SetAttribute("Who", DevAccess.describe(player))
		copy.Parent = pg
	end
end

local function onJoin(player)
	task.spawn(function()
		local ok, policy = pcall(function()
			return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(player)
		end)
		if ok and type(policy) == "table" and policy.ArePaidRandomItemsRestricted then
			restricted[player] = true
			queueSnapshot(player)
		end
	end)
	local profile, why = EconomyManager.load(player)
	if not profile then
		if why == "left" then
			return
		end
		if player.Parent then
			if why == "locked" then
				player:Kick("Your Deck Wars save is still open in another server. Please wait a minute and rejoin.")
			else
				player:Kick("Deck Wars couldn't load your save (Roblox DataStores may be down). Please rejoin in a moment; nothing was lost.")
			end
		end
		return
	end
	local daily = EconomyManager.claimDaily(player)
	sendSnapshot(player)
	if daily then
		EconomyEvent:FireClient(player, "daily", daily)
	end
	if memoryOnly then
		EconomyEvent:FireClient(player, "notice", "Saving is off in this Studio test (turn on Studio Access to API Services to save).")
	end
	giveDevControls(player)
end

Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, p)
end

Players.PlayerRemoving:Connect(function(player)
	pendingSnapshot[player] = nil
	restricted[player] = nil
	EconomyManager.unload(player)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		EconomyManager.store():saveAll(AUTOSAVE_SECONDS * 0.5)
	end
end)

game:BindToClose(function()
	EconomyManager.store():releaseAll(25)
end)

---------------------------------------------------------------------------
-- The Shop
---------------------------------------------------------------------------
local lastAction = {}
local function tooFast(player)
	local t = time()
	if lastAction[player] and t - lastAction[player] < ACTION_GAP then
		return true
	end
	lastAction[player] = t
	return false
end
Players.PlayerRemoving:Connect(function(player)
	lastAction[player] = nil
end)

local function reply(player, ok, message, kind, id, extra)
	EconomyEvent:FireClient(player, "result", { ok = ok, message = message, kind = kind, id = id, extra = extra })
end

local MarketplaceService = game:GetService("MarketplaceService")

ShopAction.OnServerEvent:Connect(function(player, what, kind, id)
	if type(what) ~= "string" then
		return
	end
	if what == "Snapshot" then
		sendSnapshot(player)
		return
	end
	if tooFast(player) then
		return
	end
	if what == "Buy" and type(kind) == "string" and (type(id) == "string" or type(id) == "number" or id == nil) then
		local ok, message, extra = EconomyManager.buy(player, kind, id)
		reply(player, ok, message, kind, id, extra)
	elseif what == "Equip" and type(kind) == "string" and type(id) == "string" then
		local ok, message = EconomyManager.equip(player, kind, id)
		reply(player, ok, message, "equip", id)
	elseif what == "BuyGems" and type(kind) == "string" then
		local b = ShopCatalog.BundleById[kind]
		if not b then
			return
		end
		if b.productId == 0 then
			reply(player, false, "This Gem bundle isn't on sale yet.", "gems", kind)
		elseif restricted[player] then
			reply(player, false, "Gem bundles aren't available where you live, because Gems open random packs. You can still earn Gems by playing!", "gems", kind)
		else
			MarketplaceService:PromptProductPurchase(player, b.productId)
		end
	elseif what == "Emote" and type(kind) == "string" then
		local c = ShopCatalog.CosmeticById[kind]
		if c and c.kind == "emote" and EconomyManager.ownsCosmetic(player, kind) then
			-- (in PvP this will go to the opponent too)
			EconomyEvent:FireClient(player, "emote", { who = "you", id = kind })
		end
	end
end)

MarketplaceService.ProcessReceipt = function(receipt)
	return EconomyManager.processReceipt(receipt, function(userId)
		return Players:GetPlayerByUserId(userId)
	end, Enum.ProductPurchaseDecision)
end

---------------------------------------------------------------------------
-- Developer tools. Every request is checked against DevAccess on the server, so a hacked
-- client firing DevAction gets nothing. (Free rolls go through PullServer, which checks
-- DevAccess the same way.)
---------------------------------------------------------------------------
DevAction.OnServerEvent:Connect(function(player, what, a)
	if not DevAccess.isDev(player) then
		warn("Deck Wars: DevAction from a non-developer ignored: " .. player.Name .. " (" .. player.UserId .. ")")
		return
	end
	if type(what) ~= "string" or tooFast(player) then
		return
	end
	local ok, msg = false, "Unknown dev action."
	if what == "GiveGems" or what == "GiveCoins" then
		local n = tonumber(a)
		if n and EconomyManager.validAmount(n) and n <= DEV_GIVE_MAX then
			local cur = what == "GiveGems" and "Gems" or "Coins"
			ok = EconomyManager.devGive(player, cur, n)
			msg = ok and ("+" .. ShopCatalog.format(n) .. " " .. cur) or "Couldn't give that."
		else
			msg = "Pick an amount from 1 to " .. ShopCatalog.format(DEV_GIVE_MAX) .. "."
		end
	elseif what == "NewDay" then
		ok = EconomyManager.devNewDay(player)
		msg = ok and "New shop day: daily cards, exchanges and the login reward reset." or "Save not loaded."
		if ok then
			local daily = EconomyManager.claimDaily(player)
			if daily then
				EconomyEvent:FireClient(player, "daily", daily)
			end
		end
	elseif what == "Luck" then
		ok = EconomyManager.devLuck(player, a)
		msg = ok and ("Lucky pulls set to " .. tostring(math.clamp(math.floor(tonumber(a) or 0), 0, ShopCatalog.MaxLuckCharges))) or "Save not loaded."
	elseif what == "ResetSave" then
		ok = EconomyManager.devResetSave(player)
		msg = ok and "Your save is back to a brand new player's." or "Save not loaded."
	elseif what == "Status" then
		ok, msg = true, DevAccess.describe(player)
	end
	EconomyEvent:FireClient(player, "dev", { ok = ok, message = msg })
end)

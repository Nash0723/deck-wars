-- Pack pull server. The server decides what you pulled, takes the Gems and records the cards
-- before the cinematic starts; the client only plays the show.
--
-- PullRequest:FireServer(count, forcedTier, packId, free)
--   count      1 or 10
--   forcedTier a tier name: the first card is that tier (Studio previews and developers only)
--   packId     a pack from Packs.luau ("snack", "robo", ...); nil = the classic Brawl Pack
--   free       true = a free roll with the real odds (Studio and developers only)
-- The answer is PullResult:FireClient(player, result). A refused pull answers
-- { error = "gems" | "cooldown" | "busy" | "failed" | "pack", ... } so the client can say why.
--
-- Money and the saved collection come from ServerStorage's "EconomyManager" module (the
-- economy update). Until that is in the place, a test wallet stands in: everyone gets
-- TEST_WALLET_GEMS Gems per visit, nothing is saved. Developers are whoever ServerStorage's
-- "DevAccess" module says (DevAccess.isDev(player)); the whitelist is checked here, on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local PackBrawl = ReplicatedStorage:WaitForChild("PackBrawl")
local PullRates = require(PackBrawl:WaitForChild("PullRates"))
local Packs = require(PackBrawl:WaitForChild("Packs"))
local CardData = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("CardData"))
local remotes = ReplicatedStorage:WaitForChild("PullRemotes")
local PullRequest = remotes:WaitForChild("PullRequest")
local PullResult = remotes:WaitForChild("PullResult")

local COOLDOWN = 1.5
local TEST_WALLET_GEMS = 1000
-- Tier previews and free rolls work in Studio (and in the test place, which sets the
-- AllowTierPreview attribute). In a live game only DevAccess developers get them.
local ALLOW_TIER_PREVIEW = script:GetAttribute("AllowTierPreview")
if ALLOW_TIER_PREVIEW == nil then
	ALLOW_TIER_PREVIEW = RunService:IsStudio()
end

-- Finds and loads a server module by name (once). Returns nil if it isn't in the place.
local modules = {}
local function serverModule(name)
	local cached = modules[name]
	if cached ~= nil then
		return cached or nil
	end
	local inst = ServerStorage:FindFirstChild(name, true) or ServerScriptService:FindFirstChild(name, true)
	if not (inst and inst:IsA("ModuleScript")) then
		return nil -- not there (yet): look again next time
	end
	local ok, mod = pcall(require, inst)
	if not ok then
		warn("[PullServer] " .. name .. " failed to load: " .. tostring(mod))
		modules[name] = false
		return nil
	end
	modules[name] = mod
	return mod
end

local function call(mod, fname, ...)
	if not (mod and type(mod[fname]) == "function") then
		return false
	end
	return pcall(mod[fname], ...)
end

local function isDev(player)
	local ok, yes = call(serverModule("DevAccess"), "isDev", player)
	return ok and yes == true
end

---------------------------------------------------------------------------
-- Wallet: the EconomyManager, or the test wallet when there is none
---------------------------------------------------------------------------

local testGems = {} -- [player] = Gems (test wallet only)
local warnedTestWallet = false

local function economy()
	local econ = serverModule("EconomyManager")
	if econ and type(econ.trySpend) == "function" then
		return econ
	end
	if not warnedTestWallet then
		warnedTestWallet = true
		print("[PullServer] No EconomyManager in ServerStorage: using the test wallet (" .. TEST_WALLET_GEMS .. " Gems per visit, not saved).")
	end
	return nil
end

local function testWallet(player)
	if testGems[player] == nil then
		testGems[player] = TEST_WALLET_GEMS
		player:SetAttribute("Gems", TEST_WALLET_GEMS)
	end
	return testGems[player]
end

local function balance(player)
	local econ = economy()
	if econ then
		local ok, b = call(econ, "getBalance", player, Packs.Currency)
		return ok and tonumber(b) or player:GetAttribute(Packs.Currency) or 0
	end
	return testWallet(player)
end

local function pay(player, amount, reason)
	local econ = economy()
	if econ then
		local ok, paid = call(econ, "trySpend", player, Packs.Currency, amount, reason)
		return ok and paid == true
	end
	local have = testWallet(player)
	if have < amount then
		return false
	end
	testGems[player] = have - amount
	player:SetAttribute("Gems", testGems[player])
	return true
end

local function refund(player, amount, reason)
	local econ = economy()
	if econ then
		local ok = call(econ, "grant", player, Packs.Currency, amount, reason)
		if not ok then
			warn("[PullServer] refund of " .. amount .. " Gems to " .. player.Name .. " failed")
		end
		return
	end
	testGems[player] = testWallet(player) + amount
	player:SetAttribute("Gems", testGems[player])
end

---------------------------------------------------------------------------
-- Collection: the saved one in EconomyManager, or this visit's cards
---------------------------------------------------------------------------

local owned = {} -- [player] = { [cardId] = count } (only without EconomyManager.grantCards)

local function grantCards(player, cards)
	local econ = economy()
	if econ and type(econ.grantCards) == "function" then
		local ok, isNew, counts, unique = pcall(econ.grantCards, player, cards)
		if not ok or type(isNew) ~= "table" then
			error("grantCards failed: " .. tostring(isNew))
		end
		return isNew, counts or {}, unique
	end
	local mine = owned[player] or {}
	owned[player] = mine
	local isNew, counts = {}, {}
	for i, id in ipairs(cards) do
		isNew[i] = (mine[id] or 0) == 0
		mine[id] = (mine[id] or 0) + 1
		counts[i] = mine[id]
	end
	local unique = 0
	for _ in pairs(mine) do
		unique += 1
	end
	return isNew, counts, unique
end

---------------------------------------------------------------------------
-- Pulls
---------------------------------------------------------------------------

local rng = Random.new()
local lastPull = {} -- [player] = time() of their last pull
local busy = {}

local function refuse(player, why, extra)
	local payload = extra or {}
	payload.error = why
	PullResult:FireClient(player, payload)
end

PullRequest.OnServerEvent:Connect(function(player, count, forcedTier, packId, free)
	if busy[player] then
		return refuse(player, "busy")
	end
	if count ~= 1 and count ~= 10 then
		return
	end
	if not Packs.valid(packId) then
		return refuse(player, "pack")
	end
	local pack = Packs.get(packId)
	local now = time()
	if lastPull[player] and now - lastPull[player] < COOLDOWN then
		return refuse(player, "cooldown")
	end
	-- previews and free rolls: Studio or developers only
	local trusted = ALLOW_TIER_PREVIEW or ((forcedTier ~= nil or free == true) and isDev(player))
	if forcedTier ~= nil and (not trusted or type(forcedTier) ~= "string" or PullRates.Rank[forcedTier] == nil) then
		forcedTier = nil
	end
	local paid = not (trusted and (forcedTier ~= nil or free == true))
	local price = paid and Packs.price(count) or 0

	busy[player] = true
	lastPull[player] = now
	local okAll, err = pcall(function()
		if paid then
			if not pay(player, price, "pack:" .. pack.id .. "x" .. count) then
				refuse(player, "gems", { price = price, balance = balance(player), packId = pack.id })
				return
			end
		end
		local ok, payload = pcall(function()
			local odds = nil
			if paid then
				local okLuck, mult = call(economy(), "takePullLuck", player, count)
				mult = okLuck and tonumber(mult) or 1
				if mult and mult ~= 1 and type(PullRates.luckyOdds) == "function" then
					odds = PullRates.luckyOdds(mult)
				end
			end
			local result = Packs.roll(pack.id, count, function()
				return rng:NextNumber()
			end, forcedTier, odds)
			local isNew, counts, unique = grantCards(player, result.cards)
			return {
				cards = result.cards,
				best = result.best,
				packId = pack.id,
				seed = rng:NextInteger(1, 2 ^ 30),
				isNew = isNew,
				dupes = counts,
				uniqueOwned = unique,
				price = price,
				free = not paid,
			}
		end)
		if not ok then
			warn("[PullServer] pull failed for " .. player.Name .. ": " .. tostring(payload))
			if paid then
				refund(player, price, "refund:pack:" .. pack.id)
			end
			refuse(player, "failed")
			return
		end
		PullResult:FireClient(player, payload)
		-- The Plaza (PlazaServer): your rarest pull on your booth, and a banner for Mythic and up.
		-- Free and forced developer rolls don't count.
		if paid then
			local pullFeed = game:GetService("ServerScriptService"):FindFirstChild("PullFeed")
			if pullFeed and pullFeed:IsA("BindableEvent") then
				pullFeed:Fire(player, payload.cards)
			end
		end
		-- Achievements (Lucky Pull, Full Set) on the Trophy Wall. Dev forced-tier rolls don't count.
		local pd = game:GetService("ServerScriptService"):FindFirstChild("PlayerData")
		if pd then
			pcall(function()
				local best = payload.best
				local rarity = type(best) == "table" and best.rarity or (type(best) == "string" and best) or nil
				if rarity == nil then
					for _, id in ipairs(payload.cards or {}) do
						local cid = type(id) == "table" and id.id or id
						local c = CardData.Cards[cid]
						if c and (c.rarity == "Legendary" or c.rarity == "Secret") then
							rarity = c.rarity
						end
					end
				end
				require(pd).notePull(player, rarity, forcedTier ~= nil)
			end)
		end
	end)
	busy[player] = nil
	if not okAll then
		warn("[PullServer] " .. tostring(err))
	end
end)

-- Show the test wallet's Gems as soon as someone joins (the EconomyManager sets its own).
local function onJoin(player)
	task.defer(function()
		if not economy() and player.Parent then
			testWallet(player)
		end
	end)
end
Players.PlayerAdded:Connect(onJoin)
for _, p in ipairs(Players:GetPlayers()) do
	onJoin(p)
end

Players.PlayerRemoving:Connect(function(player)
	owned[player] = nil
	lastPull[player] = nil
	busy[player] = nil
	testGems[player] = nil
end)

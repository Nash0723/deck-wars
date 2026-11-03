-- Pack Brawl pull server. The server decides what you pulled and records it before the
-- cinematic starts; the client only plays the show. In this test place pulls are free and the
-- collection lives in memory (saving and prices come with packs and collection in step 3).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackBrawl = ReplicatedStorage:WaitForChild("PackBrawl")
local PullRates = require(PackBrawl:WaitForChild("PullRates"))
local remotes = ReplicatedStorage:WaitForChild("PullRemotes")
local PullRequest = remotes:WaitForChild("PullRequest")
local PullResult = remotes:WaitForChild("PullResult")

local COOLDOWN = 1.5
-- The tier preview buttons only work when this is on. The test place turns it on with the
-- AllowTierPreview attribute; without the attribute it is on only while testing in Studio,
-- so players in a live game can't force a Secret.
local ALLOW_TIER_PREVIEW = script:GetAttribute("AllowTierPreview")
if ALLOW_TIER_PREVIEW == nil then
	ALLOW_TIER_PREVIEW = game:GetService("RunService"):IsStudio()
end

local rng = Random.new()
local owned = {} -- [player] = { [cardId] = count }
local lastPull = {} -- [player] = time() of their last pull
local busy = {}

PullRequest.OnServerEvent:Connect(function(player, count, previewTier)
	if busy[player] then
		return
	end
	if count ~= 1 and count ~= 10 then
		return
	end
	local now = time()
	if lastPull[player] and now - lastPull[player] < COOLDOWN then
		return
	end
	if previewTier ~= nil and (not ALLOW_TIER_PREVIEW or type(previewTier) ~= "string" or PullRates.Rank[previewTier] == nil) then
		previewTier = nil
	end
	busy[player] = true
	lastPull[player] = now
	local result = PullRates.roll(count, function()
		return rng:NextNumber()
	end, previewTier)
	local mine = owned[player] or {}
	owned[player] = mine
	local isNew, dupes = {}, {}
	for i, id in ipairs(result.cards) do
		isNew[i] = (mine[id] or 0) == 0
		mine[id] = (mine[id] or 0) + 1
		dupes[i] = mine[id]
	end
	local total = 0
	for _ in pairs(mine) do
		total += 1
	end
	PullResult:FireClient(player, {
		cards = result.cards,
		best = result.best,
		seed = rng:NextInteger(1, 2 ^ 30),
		isNew = isNew,
		dupes = dupes,
		uniqueOwned = total,
	})
	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	owned[player] = nil
	lastPull[player] = nil
	busy[player] = nil
end)

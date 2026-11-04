-- Plays the economy inside the fake Roblox: joining (save load, daily reward, Gems/Coins
-- attributes), the currency counters, the Shop's three tabs (buying a daily card, a board theme
-- that repaints the table, a Gem item that needs two taps, an exchange), the developer panel
-- (only for whitelisted UserIds; free rolls; server refuses non-developers), match rewards,
-- autosave and the release on shutdown.
-- Usage (from the repo root): luaurun mock_roblox/econharness.luau mock_roblox

local M = require("RobloxMock")
local SRC = "src/"

for k, v in pairs(M.env) do
	_G[k] = v
end
local typeof = M.typeof

local game = M.service("Game", "DataModel")
local Workspace = M.service("Workspace")
local ReplicatedStorage = M.service("ReplicatedStorage")
local ServerScriptService = M.service("ServerScriptService")
local ServerStorage = M.service("ServerStorage")
local Players = M.service("Players")
local TweenService = M.service("TweenService")
local UserInputService = M.service("UserInputService")
local RunService = M.service("RunService")
local Debris = M.service("Debris")
local StarterGui = M.service("StarterGui")
local Lighting = M.service("Lighting")
local StarterPlayer = M.service("StarterPlayer")
local SoundService = M.service("SoundService")
local DataStoreService = M.service("DataStoreService")
local MarketplaceService = M.service("MarketplaceService")
local PolicyService = M.service("PolicyService")
for _, s in ipairs({ Workspace, ReplicatedStorage, ServerScriptService, ServerStorage, Players, TweenService, UserInputService, RunService, Debris, StarterGui, Lighting, StarterPlayer, SoundService, DataStoreService, MarketplaceService, PolicyService }) do
	s.Parent = game
end

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
Workspace.CurrentCamera = camera

M.build(require("WorldData")(), Workspace)

local function moduleFrom(path, name, parent)
	local m = Instance.new("ModuleScript")
	m.Name = name
	M.rec(m).sourcePath = path
	m.Parent = parent
	return m
end
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
local shared = folder("DeckWars", ReplicatedStorage)
for _, n in ipairs({ "CardData", "MatchEngine", "BotBrain", "Rng", "StarterDecks", "CreatureModelData", "CreatureBuilder", "Settings", "Juice", "TitleScreen", "ShopCatalog", "Cosmetics", "ShopUI", "DeckRules", "DeckBuilderUI" }) do
	moduleFrom(SRC .. "shared/" .. n .. ".luau", n, shared)
end
local pb = folder("PackBrawl", ReplicatedStorage)
for _, n in ipairs({ "Kit", "PullRates", "Casting", "Scripts", "Rig", "Moves", "Arena", "Fighters", "CamRig", "Fx", "Sfx", "Poses", "Director", "Reveal", "PackTease", "Packs", "PackShelf", "PackParty" }) do
	moduleFrom(SRC .. "packbrawl/" .. n .. ".luau", n, pb)
end
local function remoteFolder(name, list)
	local f = folder(name, ReplicatedStorage)
	for _, n in ipairs(list) do
		local r = Instance.new("RemoteEvent")
		r.Name = n
		r.Parent = f
	end
	return f
end
local pullRemotes = remoteFolder("PullRemotes", { "PullRequest", "PullResult" })
local remotes = remoteFolder("Remotes", { "MatchEvent", "MatchAction", "MenuAction" })
local econRemotes = remoteFolder("EconomyRemotes", { "ShopAction", "EconomyEvent", "DevAction" })
-- ServerStorage: the server modules and the dev panel template (like default.project.json)
local serverModules = folder("DeckWarsServer", ServerStorage)
for _, n in ipairs({ "EconomyManager", "DevAccess", "ProfileStore" }) do
	moduleFrom(SRC .. "econ/" .. n .. ".luau", n, serverModules)
end
local devTemplate = Instance.new("ScreenGui")
devTemplate.Name = "DevControls"
devTemplate.ResetOnSpawn = false
devTemplate.DisplayOrder = 50
devTemplate.Parent = ServerStorage
local devScript = Instance.new("LocalScript")
devScript.Name = "DevPanel"
devScript.Parent = devTemplate

-- The local player: Nash, signed in as DNash2307 (a whitelisted developer)
M.userIds = { DNash2307 = 5550001, donatjalt = 5550002 }
local player = M.new("Player", true)
player.Name = "DNash2307"
M.rec(player).props.DisplayName = "Nash"
M.rec(player).props.UserId = 5550001
player.Parent = Players
M.localPlayer = player
M.rec(Players).props.LocalPlayer = player
local playerGui = M.new("PlayerGui", true)
playerGui.Name = "PlayerGui"
playerGui.Parent = player
local playerScripts = M.new("PlayerScripts", true)
playerScripts.Name = "PlayerScripts"
playerScripts.Parent = player
local pm = Instance.new("ModuleScript")
pm.Name = "PlayerModule"
M.rec(pm).mockValue = { GetControls = function()
	return { Disable = function() end, Enable = function() end }
end }
pm.Parent = playerScripts
local character = Instance.new("Model")
character.Name = "Nash"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = character
Instance.new("Humanoid").Parent = character
character.PrimaryPart = root
character.Parent = Workspace
player.Character = character

-- Script loading (server scripts share one module cache, client scripts another)
local function makeEnv(scriptInst, cache)
	local env = setmetatable({}, { __index = _G })
	for k, v in pairs(M.env) do
		env[k] = v
	end
	env.game = game
	env.workspace = Workspace
	env.script = scriptInst
	env.require = function(mod)
		if typeof(mod) ~= "Instance" or mod.ClassName ~= "ModuleScript" then
			error("require expects a ModuleScript, got " .. typeof(mod), 2)
		end
		local r = M.rec(mod)
		if r.mockValue then
			return r.mockValue
		end
		if cache[mod] == nil then
			local f = __loadchunk(__readfile(r.sourcePath), r.sourcePath, makeEnv(mod, cache))
			cache[mod] = f()
		end
		return cache[mod]
	end
	return env
end
local serverCache, clientCache = {}, {}
local function runScript(path, scriptInst, cache)
	local f = __loadchunk(__readfile(path), path, makeEnv(scriptInst, cache))
	task.spawn(f)
end
local function scriptIn(parent, class, name)
	local s = Instance.new(class)
	s.Name = name
	s.Parent = parent
	return s
end

M.onFrame = function()
	RunService.RenderStepped:Fire(1 / 30)
	RunService.Heartbeat:Fire(1 / 30)
end

-- watch what the server sends and gets
local events = {}
econRemotes.EconomyEvent.OnClientEvent:Connect(function(kind, payload)
	table.insert(events, { kind = kind, payload = payload })
end)
local pullRequests = {}
pullRemotes.PullRequest.OnServerEvent:Connect(function(_, ...)
	table.insert(pullRequests, table.pack(...))
end)
local function lastEvent(kind)
	for i = #events, 1, -1 do
		if events[i].kind == kind then
			return events[i].payload, i
		end
	end
	return nil, 0
end

moduleFrom(SRC .. "server/PlayerDecks.luau", "PlayerDecks", ServerScriptService)
runScript(SRC .. "server/MatchServer.server.luau", scriptIn(ServerScriptService, "Script", "MatchServer"), serverCache)
runScript(SRC .. "pullserver/PullServer.server.luau", scriptIn(ServerScriptService, "Script", "PullServer"), serverCache)
runScript(SRC .. "server/EconomyServer.server.luau", scriptIn(ServerScriptService, "Script", "EconomyServer"), serverCache)
local clientScript = scriptIn(playerScripts, "LocalScript", "DeckWarsClient")
runScript(SRC .. "client/DeckWarsClient.client.luau", clientScript, clientCache)
M.advance(2)

---------------------------------------------------------------------------
-- GUI helpers
---------------------------------------------------------------------------
local function visible(g)
	local i = g
	while i and i ~= playerGui do
		if i:IsA("GuiObject") and not i.Visible then
			return false
		end
		i = i.Parent
	end
	return true
end
local function find(pred, root0)
	for _, d in ipairs((root0 or playerGui):GetDescendants()) do
		if pred(d) and visible(d) then
			return d
		end
	end
	return nil
end
local function findAll(pred, root0)
	local out = {}
	for _, d in ipairs((root0 or playerGui):GetDescendants()) do
		if pred(d) and visible(d) then
			table.insert(out, d)
		end
	end
	return out
end
local function buttonWithText(text, prefix, root0)
	return find(function(d)
		return d.ClassName == "TextButton" and (d.Text == text or (prefix and string.sub(d.Text, 1, #text) == text))
	end, root0)
end
local function labelStarting(text)
	return find(function(d)
		return d.ClassName == "TextLabel" and string.sub(d.Text, 1, #text) == text
	end)
end
local function named(name, root0)
	return find(function(d)
		return d.Name == name
	end, root0)
end
local function click(b, what)
	if not b then
		M.report("error", "button not found: " .. tostring(what))
		return
	end
	local ok, why = M.clickable(b)
	if ok then
		b.Activated:Fire()
	else
		M.report("error", "can't click " .. tostring(what) .. ": " .. why)
	end
	M.advance(0.3)
end
local function check(cond, msg)
	if not cond then
		M.report("error", "CHECK FAILED: " .. msg)
	else
		print("ok   " .. msg)
	end
end

local ShopCatalog = makeEnv(clientScript, clientCache).require(shared.ShopCatalog)
local Economy = makeEnv(nil, serverCache).require(serverModules.EconomyManager)

---------------------------------------------------------------------------
-- Joining
---------------------------------------------------------------------------
local start = ShopCatalog.StartingGems + ShopCatalog.Daily.gems
check(player:GetAttribute("Gems") == start, "Gems attribute after joining = starting Gems + daily (" .. tostring(player:GetAttribute("Gems")) .. ")")
check(player:GetAttribute("Coins") == ShopCatalog.StartingCoins + ShopCatalog.Daily.coins, "Coins attribute after joining")
check(lastEvent("snapshot") ~= nil, "the client got a snapshot")
check(lastEvent("daily") ~= nil, "the client got the daily reward")
check(playerGui:FindFirstChild("DevControls") ~= nil, "the whitelisted developer got the DevControls panel")
check(M.kicked[player] == nil, "nobody was kicked")
local store = M.dataStores.DeckWarsPlayer_v1
check(store ~= nil and store.data.u5550001 ~= nil, "the save was created in the DeckWarsPlayer_v1 DataStore")
check(store.data.u5550001.meta.lock ~= nil, "the save is locked by this server")

-- the dev panel LocalScript runs in the player's PlayerGui (the mock doesn't run cloned scripts itself)
local devCopy = playerGui:FindFirstChild("DevControls")
local devCopyScript = devCopy and devCopy:FindFirstChild("DevPanel")
if devCopyScript then
	runScript(SRC .. "devcontrols/DevPanel.client.luau", devCopyScript, clientCache)
	M.advance(0.5)
end

-- title screen -> room
local title = playerGui:FindFirstChild("DeckWarsTitle")
if title then
	click(title:FindFirstChild("Play", true), "PLAY")
	M.advance(4)
end
check(playerGui:FindFirstChild("DeckWarsTitle") == nil, "title screen gone")
M.advance(1.5)
check(labelStarting("Daily reward!") ~= nil, "the daily reward toast shows after the title screen")
local hud = named("CurrencyHud")
check(hud ~= nil, "the Gems / Coins counters show in the room")
M.advance(2)
check(hud and hud.Gems.Value.Text == "💎 " .. ShopCatalog.format(player:GetAttribute("Gems")), "the Gems counter shows the balance (" .. tostring(hud and hud.Gems.Value.Text) .. ")")

---------------------------------------------------------------------------
-- The Shop
---------------------------------------------------------------------------
click(buttonWithText("Shop", true), "Shop station")
M.advance(1)
local window = named("ShopWindow")
check(window ~= nil, "the Shop window opens at the Shop counter")
check(buttonWithText("Open the Shop") ~= nil, "the Shop counter panel shows")
check(labelStarting("Level 1") ~= nil, "the panel shows the level")

-- Daily cards
local function priceButtons()
	return findAll(function(d)
		return d.ClassName == "TextButton" and d.Parent and d.Parent.Name == "Tile" and (string.sub(d.Text, 1, 4) == "🪙" or string.sub(d.Text, 1, 4) == "💎")
	end, window)
end
local tiles = findAll(function(d)
	return d.Name == "Tile"
end, window)
check(#tiles == 6, "6 daily card tiles (" .. #tiles .. ")")
check(#findAll(function(d)
	return d.Name == "Card"
end, window) == 6, "each daily tile shows the card")
check(labelStarting("⏳ New cards in") ~= nil, "the reset countdown shows")
local coins0 = player:GetAttribute("Coins")
local first = priceButtons()[1]
local today = ShopCatalog.dailyCards(ShopCatalog.dayNumber(os.time()))
-- (new players already own the starter collection, so count from what they had)
local ownedBefore = Economy.ownsCard(player, today[1].id)
click(first, "buy the first daily card")
M.advance(0.5)

local res = lastEvent("result")
check(res and res.ok, "buying a daily card works (" .. tostring(res and res.message) .. ")")
check(player:GetAttribute("Coins") == coins0 - today[1].price, "the card's Coins were paid")
check(buttonWithText("Bought ✓", false, window) ~= nil, "the tile now says Bought")
check(Economy.ownsCard(player, today[1].id) == ownedBefore + 1, "the card is in the saved collection (" .. ownedBefore .. " before)")

-- Deck & Field: a board theme repaints the table
click(named("Tab_cosmetics"), "Deck & Field tab")
M.advance(0.5)
check(labelStarting("Board themes") ~= nil and labelStarting("Card backs") ~= nil and labelStarting("Emotes") ~= nil, "Deck & Field shows themes, card backs and emotes")
Economy.grant(player, "Coins", 5000, "test")
M.advance(0.5)
local felt = Workspace.MenuRoom.Stations.DuelTable:FindFirstChild("Felt")
local feltBefore = felt and felt.Color
local midnightBtn = nil
for _, t in ipairs(findAll(function(d)
	return d.Name == "Tile"
end, window)) do
	for _, d in ipairs(t:GetDescendants()) do
		if d.ClassName == "TextLabel" and d.Text == "Midnight Velvet" then
			midnightBtn = find(function(x)
				return x.ClassName == "TextButton"
			end, t)
		end
	end
end
click(midnightBtn, "buy Midnight Velvet")
M.advance(0.5)
local Cos = makeEnv(clientScript, clientCache).require(shared.Cosmetics)
check(felt ~= nil and felt.Color ~= feltBefore, "buying Midnight Velvet repaints the table felt")
check(felt and felt.Color == Cos.Boards.board_midnight.felt[1], "the felt is Midnight Velvet blue")
check(buttonWithText("Equipped ✓", false, window) ~= nil, "the bought theme shows Equipped")
-- equip Walnut again: the original felt comes back
local walnutEquip = nil
for _, t in ipairs(findAll(function(d)
	return d.Name == "Tile"
end, window)) do
	for _, d in ipairs(t:GetDescendants()) do
		if d.ClassName == "TextLabel" and d.Text == "Walnut Classic" then
			walnutEquip = buttonWithText("Equip", false, t)
		end
	end
end
click(walnutEquip, "equip Walnut Classic")
M.advance(0.5)
check(felt and felt.Color == feltBefore, "Walnut Classic puts the original felt back")

-- a Gem item needs two taps
local gems0 = player:GetAttribute("Gems")
local starBtn = nil
for _, t in ipairs(findAll(function(d)
	return d.Name == "Tile"
end, window)) do
	for _, d in ipairs(t:GetDescendants()) do
		if d.ClassName == "TextLabel" and d.Text == "Void Spiral" then
			starBtn = find(function(x)
				return x.ClassName == "TextButton"
			end, t)
		end
	end
end
click(starBtn, "Void Spiral (first tap)")
M.advance(0.3)
check(player:GetAttribute("Gems") == gems0 and starBtn and string.sub(starBtn.Text, 1, 9) == "Tap again", "the first tap on a Gem price only asks to confirm")
click(starBtn, "Void Spiral (second tap)")
M.advance(0.5)
check(player:GetAttribute("Gems") == gems0 - 250, "the second tap buys it with Gems")
check(Economy.snapshot(player).equipped.cardback == "back_void", "the new card back is equipped")

-- Exchange & Boosts
click(named("Tab_exchange"), "Exchange & Boosts tab")
M.advance(0.5)
check(#findAll(function(d)
	return d.ClassName == "TextButton" and d.Text == "Not on sale yet"
end, window) == #ShopCatalog.GemBundles, "Gem bundles without a product id show Not on sale yet")
local coinsBefore, gemsBefore = player:GetAttribute("Coins"), player:GetAttribute("Gems")
click(buttonWithText("Trade 🪙", true, window), "Coins -> Gems")
M.advance(0.5)
check(player:GetAttribute("Coins") == coinsBefore - 500 and player:GetAttribute("Gems") == gemsBefore + 25, "the Coins -> Gems exchange works")
check(labelStarting("🍀 Lucky pulls left") ~= nil or find(function(d)
	return d.ClassName == "TextLabel" and string.find(d.Text, "Lucky pulls left", 1, true) ~= nil
end) ~= nil, "the boosters show how many lucky pulls are left")

-- Robux bundle prompt only when it has a product id
local ServerCatalog = makeEnv(nil, serverCache).require(shared.ShopCatalog)
ServerCatalog.GemBundles[1].productId = 4242
econRemotes.ShopAction:FireServer("BuyGems", "gems_small")
M.advance(0.5)
check(#M.prompts == 1 and M.prompts[1].productId == 4242, "a set-up Gem bundle opens the Robux purchase prompt")
local receipt = { PlayerId = player.UserId, ProductId = 4242, PurchaseId = "abc-1", CurrencySpent = 49 }
local g1 = player:GetAttribute("Gems")
local decision = MarketplaceService.ProcessReceipt(receipt)
check(decision == Enum.ProductPurchaseDecision.PurchaseGranted, "ProcessReceipt grants the purchase")
check(player:GetAttribute("Gems") == g1 + ShopCatalog.GemBundles[1].gems, "the bundle's Gems arrived")
check(MarketplaceService.ProcessReceipt(receipt) == Enum.ProductPurchaseDecision.PurchaseGranted and player:GetAttribute("Gems") == g1 + ShopCatalog.GemBundles[1].gems, "a repeated receipt doesn't pay twice")
ServerCatalog.GemBundles[1].productId = 0

-- Unowned emote is refused by the server
local _, n0 = lastEvent("emote")
econRemotes.ShopAction:FireServer("Emote", "emote_fire")
M.advance(0.5)
local _, n1 = lastEvent("emote")
check(n1 == n0, "the server refuses an emote you don't own")
econRemotes.ShopAction:FireServer("Emote", "emote_hello")
M.advance(0.5)
local em = lastEvent("emote")
check(em and em.id == "emote_hello", "a default emote is echoed back")

click(named("Close", window), "close the Shop")
check(not window.Visible, "the Shop window closes")
click(buttonWithText("Back"), "Back")
M.advance(1.5)

---------------------------------------------------------------------------
-- Developer panel
---------------------------------------------------------------------------
local devGui = playerGui:FindFirstChild("DevControls")
click(named("DevTab", devGui), "DEV tab")
check(named("Panel", devGui) ~= nil, "the dev panel opens")
local gemsDev = player:GetAttribute("Gems")
click(named("GiveGems", devGui), "+1,000 Gems")
M.advance(0.5)
check(player:GetAttribute("Gems") == gemsDev + 1000, "the dev panel gives 1,000 Gems")
click(named("Free_Epic", devGui), "Free roll: Epic")
M.advance(0.5)
local req = pullRequests[#pullRequests]
check(req ~= nil and req[1] == 1 and req[2] == "Epic", "a free Epic roll asks the pull server for an Epic pull")
-- (the 4th argument, free = true, reaches PullServer once PackParty.request forwards it: the
-- pack shelf update adds that; until then pulls are free for everyone anyway)
print("note free flag forwarded by PackParty: " .. tostring(req and req[4]))
check(player:GetAttribute("Gems") == gemsDev + 1000, "a free roll costs no Gems")
-- let the cinematic play out and close
local PackParty = makeEnv(clientScript, clientCache).require(pb.PackParty)
for _ = 1, 120 do
	if not PackParty.isPlaying() then
		break
	end
	local tap = find(function(d)
		return d.ClassName == "TextButton" and (d.Name == "Tap" or d.Name == "Continue" or d.Name == "Skip")
	end)
	if tap and M.clickable(tap) then
		tap.Activated:Fire()
	end
	M.advance(0.5)
end
check(not PackParty.isPlaying(), "the free roll's cinematic finished")

-- a non-developer firing the dev remote gets nothing
M.rec(player).props.UserId = 777
local gemsHack = Economy.getBalance(player, "Gems")
local warn0 = M.warnings
econRemotes.DevAction:FireServer("GiveGems", 1000000)
M.advance(0.5)
check(Economy.getBalance(player, "Gems") == gemsHack, "DevAction from a non-developer gives nothing")
check(M.warnings == warn0 + 1, "and the server logs it")
M.warnings = warn0 -- (that warning was expected)
M.rec(player).props.UserId = 5550001

---------------------------------------------------------------------------
-- Match rewards, autosave, shutdown
---------------------------------------------------------------------------
local coinsM = player:GetAttribute("Coins")
local reward = Economy.matchReward(player, { result = "win", difficulty = "Hard", seconds = 400, turns = 9 })
Economy.announce(player, "reward", reward)
M.advance(0.6)
check(player:GetAttribute("Coins") == coinsM + ShopCatalog.Match.winCoins.Hard + (reward.levelCoins or 0), "a Hard win pays its Coins")
check(labelStarting("+" .. ShopCatalog.Match.winCoins.Hard .. " Coins") ~= nil, "the reward toast shows")

local writes0 = store.writes
M.advance(95)
check(store.writes > writes0, "the autosave wrote the save")
check(store.data.u5550001.data.coins == player:GetAttribute("Coins"), "the saved Coins match the game")
for _, fn in ipairs(M.closeFns) do
	task.spawn(fn)
end
M.advance(3)
check(store.data.u5550001.meta.lock == nil, "shutting down releases the save lock")

print(string.format("MOCK RESULT: %d errors, %d warnings", M.errors, M.warnings))

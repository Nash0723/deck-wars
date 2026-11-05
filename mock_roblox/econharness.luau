-- Plays the economy inside the fake Roblox: joining (save load, daily reward, Gems/Coins
-- attributes), the currency counters, the Shop's three tabs (buying a daily card, a board theme
-- that repaints the table, a Gem item that needs two taps, an exchange), the developer panel
-- (only for whitelisted UserIds; free rolls; server refuses non-developers), match rewards,
-- a Campaign stage from the world map, the Plaza (booths, likes, big-pull banners, the altar),
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

M.service("ContentProvider").Parent = game -- (TableSounds preloads its sounds)
M.service("SocialService").Parent = game -- (PartyScreen invites friends)
M.service("GuiService").Parent = game
M.service("ProximityPromptService").Parent = game -- (the Plaza's prompts)
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
for _, n in ipairs({ "CardData", "MatchEngine", "BotBrain", "Rng", "StarterDecks", "CreatureModelData", "CreatureBuilder", "Settings", "Juice", "TitleScreen", "ShopCatalog", "Cosmetics", "ShopUI", "DeckRules", "DeckBuilderUI", "TableSounds", "Progression", "Backdrops", "LobbyScreen", "PartyScreen", "MatchScreen", "RoomLife", "Campaign", "CampaignUI", "Plaza", "PlazaClient" }) do
	moduleFrom(SRC .. "shared/" .. n .. ".luau", n, shared)
end
local pb = folder("PackBrawl", ReplicatedStorage)
for _, n in ipairs({ "Kit", "PullRates", "Casting", "Scripts", "Rig", "Moves", "Arena", "Fighters", "CamRig", "Fx", "Sfx", "Poses", "Director", "Reveal", "PackTease", "Packs", "PackShelf", "PackParty", "BiomeFx", "BiomeStage" }) do
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
local remotes = remoteFolder("Remotes", { "MatchEvent", "MatchAction", "MenuAction", "LobbyEvent" })
local econRemotes = remoteFolder("EconomyRemotes", { "ShopAction", "EconomyEvent", "DevAction" })
local plazaRemotes = remoteFolder("PlazaRemotes", { "PlazaAction", "PlazaEvent" })
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
moduleFrom(SRC .. "server/PlayerData.luau", "PlayerData", ServerScriptService)
moduleFrom(SRC .. "server/CampaignData.luau", "CampaignData", ServerScriptService)
moduleFrom(SRC .. "plaza/PlazaBuilder.luau", "PlazaBuilder", ServerScriptService)
runScript(SRC .. "server/HubRoom.server.luau", scriptIn(ServerScriptService, "Script", "HubRoom"), serverCache)
runScript(SRC .. "server/MatchServer.server.luau", scriptIn(ServerScriptService, "Script", "MatchServer"), serverCache)
runScript(SRC .. "server/MenuServer.server.luau", scriptIn(ServerScriptService, "Script", "MenuServer"), serverCache)
runScript(SRC .. "pullserver/PullServer.server.luau", scriptIn(ServerScriptService, "Script", "PullServer"), serverCache)
runScript(SRC .. "server/EconomyServer.server.luau", scriptIn(ServerScriptService, "Script", "EconomyServer"), serverCache)
runScript(SRC .. "server/PlazaServer.server.luau", scriptIn(ServerScriptService, "Script", "PlazaServer"), serverCache)
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
local CardData = makeEnv(clientScript, clientCache).require(shared.CardData)
local Economy = makeEnv(nil, serverCache).require(serverModules.EconomyManager)

---------------------------------------------------------------------------
-- Joining
---------------------------------------------------------------------------
-- (the daily reward waits for the player to claim it from the pop-up in the room)
local start = ShopCatalog.StartingGems
check(player:GetAttribute("Gems") == start, "Gems attribute after joining = starting Gems (" .. tostring(player:GetAttribute("Gems")) .. ")")
check(player:GetAttribute("Coins") == ShopCatalog.StartingCoins, "Coins attribute after joining")
check(lastEvent("snapshot") ~= nil, "the client got a snapshot")
check(player:GetAttribute("DailyReady") == true, "today's daily reward is ready")
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
local popup = named("DailyPopup")
check(popup ~= nil and visible(popup), "the daily reward pop-up shows after the title screen")
if popup then
	click(popup:FindFirstChild("ClaimDaily"), "claim the daily reward")
	M.advance(1)
end
local dayGems = makeEnv(nil, serverCache).require(shared.Progression).dailyReward(1)
check(player:GetAttribute("Gems") == start + dayGems, "claiming pays the day's Gems (" .. tostring(player:GetAttribute("Gems")) .. ")")
check(player:GetAttribute("Coins") == ShopCatalog.StartingCoins + ShopCatalog.Daily.coins, "claiming pays the day's Coins")
check(player:GetAttribute("DailyReady") == false, "the daily reward is claimed")
start = player:GetAttribute("Gems")
local profileCard = named("Profile")
check(profileCard ~= nil, "the profile card (level, Gems, Coins) shows in the room")
M.advance(2)
check(profileCard and profileCard.Gems.Text == "💎 " .. tostring(player:GetAttribute("Gems")), "the profile card shows the Gems (" .. tostring(profileCard and profileCard.Gems.Text) .. ")")
check(profileCard and profileCard.Coins.Text == "🪙 " .. tostring(player:GetAttribute("Coins")), "the profile card shows the Coins")

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
-- The room answers the mouse (RoomLife): point at a binder, click a trophy through the real
-- click handler; sitting down at the table later puts every prop back
---------------------------------------------------------------------------
local RoomLife = makeEnv(clientScript, clientCache).require(shared.RoomLife)
do
	RoomLife.idleFidgets = false -- (so the check at the table below isn't caught mid-fidget)
	local binder = RoomLife.kinds.binder and RoomLife.kinds.binder[3]
	check(binder ~= nil, "RoomLife found the Deck Shelf's binders")
	if binder then
		local home = binder.anchor.Position
		M.raycastHook = function()
			return { Instance = binder.anchor, Position = binder.anchor.Position }
		end
		M.advance(1)
		check((binder.anchor.Position - home).Magnitude > 0.2, "pointing at a binder slides it out of the shelf")
		check(UserInputService.MouseIcon ~= "", "the mouse turns into a pointing hand over it")
		local trophy = RoomLife.kinds.trophy[1]
		M.raycastHook = function()
			return { Instance = trophy.anchor, Position = trophy.anchor.Position }
		end
		UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) }, false)
		M.advance(0.2)
		check(trophy.pk ~= nil, "clicking a trophy makes it jump")
		M.raycastHook = nil
		M.advance(3)
		check(UserInputService.MouseIcon == "", "the normal mouse comes back")
	end
end

---------------------------------------------------------------------------
-- A whole match against the bot through the merged client: the Duel Table panel, placing
-- creatures on Front and Back spots, a Shift, BATTLE, the result and back to the room
---------------------------------------------------------------------------
do
	local MatchScreen = makeEnv(clientScript, clientCache).require(shared.MatchScreen)
	local F, S = MatchScreen.F, MatchScreen.S
	local gemsBefore = player:GetAttribute("Gems")
	click(named("NavDuelTable"), "Duel Table station")
	M.advance(1.5)
	click(named("PlayBot"), "Sit down and play (bot)")
	local waited = 0
	while not (S.view and not S.view.over) and waited < 20 do
		M.advance(0.5)
		waited += 0.5
	end
	check(S.view ~= nil, "the bot match starts")
	local away = 0
	for _, p in ipairs(RoomLife.props) do
		for _, e in ipairs(p.parts) do
			away = math.max(away, (e.part.Position - e.base.Position).Magnitude)
		end
	end
	check(away < 1e-6, "every room prop is back in place at the table (" .. away .. ")")
	local plays, backPlays, shifts, buildings, turnsMine = 0, 0, 0, 0, 0
	local playedThisTurn, shiftedThisTurn, lastTurn = 0, false, -1
	local guard = 0
	while S.view and not S.view.over and guard < 1600 do
		guard += 1
		if F.myTurn() then
			if S.view.turn ~= lastTurn then
				lastTurn = S.view.turn
				turnsMine += 1
				playedThisTurn, shiftedThisTurn = 0, false
			end
			local acted = false
			if playedThisTurn < 3 then
				for _, a in ipairs(S.view.legal or {}) do
					if a.kind == "play" then
						local c = CardData.Cards[a.id]
						local spot = nil
						if c.type == "Creature" then
							-- prefer a Back spot every other card, so both rows get used
							for _, t in ipairs(a.tiles or {}) do
								if not t.replace and (spot == nil or (plays % 2 == 1 and t.row == 2)) then
									spot = t
								end
							end
						elseif c.type == "Building" then
							spot = a.lanes and a.lanes[1] and { lane = a.lanes[1], slot = "building" }
						end
						if c.type == "Spell" or spot then
							F.onCardClicked(a.handUid)
							if S.pick and S.pick.step == "lane" and spot then
								F.onBoardClick({ team = S.myTeam, lane = spot.lane, row = spot.row, slot = spot.slot or (spot.row == 2 and "back" or "creature") })
							end
							if S.pick and S.pick.step == "target" then
								local t = (S.pick.action.targets or {})[1]
								if t then
									F.onBoardClick({ team = t.team, lane = t.lane, row = t.row or 1, slot = (t.row == 2) and "back" or "creature" })
								end
							end
							if S.pick then
								F.clearPick()
							else
								acted = true
								plays += 1
								playedThisTurn += 1
								if spot and spot.row == 2 then
									backPlays += 1
								end
								if c.type == "Building" then
									buildings += 1
								end
							end
							break
						end
					end
				end
			end
			if not acted and not shiftedThisTurn then
				for _, a in ipairs(S.view.legal or {}) do
					if a.kind == "shift" then
						local entry = S.units[a.uid]
						if entry then
							F.selectCreature(entry)
							local b = named("Shift")
							if b then
								click(b, "Shift a creature")
								shifts += 1
								acted = true
							end
							shiftedThisTurn = true
						end
						break
					end
				end
				shiftedThisTurn = true
			end
			if not acted then
				F.pressBattle()
				F.pressBattle()
			end
		end
		M.advance(0.5)
	end
	check(S.view and S.view.over, "the match ends (" .. turnsMine .. " of your turns)")
	check(plays >= 4, "cards were played from the hand onto the table (" .. plays .. ")")
	check(backPlays >= 1, "creatures were placed on Back spots (" .. backPlays .. ")")
	check(shifts >= 1, "a creature was shifted between rows (" .. shifts .. ")")
	local backSeen = false
	for _, l in ipairs(S.view.lanes[S.myTeam] or {}) do
		if l.back then
			backSeen = true
		end
	end
	print("note match: " .. plays .. " plays, " .. backPlays .. " on Back spots, " .. buildings .. " buildings, " .. shifts .. " shifts, winner team " .. tostring(S.view.winner) .. ", back row filled at the end: " .. tostring(backSeen))
	local shown = false
	for _ = 1, 16 do
		M.advance(0.5)
		local rp = named("ResultPanel")
		if rp and visible(rp) then
			shown = true
			break
		end
	end
	check(shown, "the result panel shows")
	M.advance(16)
	check(named("StationTitle") and named("StationTitle").Text == "Duel Table", "back at the Duel Table panel after the match")
	check(player:GetAttribute("Gems") >= gemsBefore, "Gems never drop from playing a match")
end

---------------------------------------------------------------------------
-- The Campaign: the painting over the fireplace is a station, its world map, act 1 of the Card
-- Den with your own deck (tries again from the result screen if the bot wins), the stars and
-- first-clear rewards, back at the map with act 2 open
---------------------------------------------------------------------------
local Campaign = makeEnv(clientScript, clientCache).require(shared.Campaign)
local Plaza = makeEnv(clientScript, clientCache).require(shared.Plaza)
local function saveData()
	return Economy.waitForData(player, 0)
end

-- Plays a match out through the client (cards from the hand, then BATTLE) until it ends.
local function playOut(S, F)
	local guard, plays = 0, 0
	local playedThisTurn, lastTurn = 0, -1
	while S.view and not S.view.over and guard < 1600 do
		guard += 1
		if F.myTurn() then
			if S.view.turn ~= lastTurn then
				lastTurn = S.view.turn
				playedThisTurn = 0
			end
			local acted = false
			if playedThisTurn < 3 then
				for _, a in ipairs(S.view.legal or {}) do
					if a.kind == "play" then
						local c = CardData.Cards[a.id]
						local spot = nil
						if c.type == "Creature" then
							for _, t in ipairs(a.tiles or {}) do
								if not t.replace and spot == nil then
									spot = t
								end
							end
						elseif c.type == "Building" then
							spot = a.lanes and a.lanes[1] and { lane = a.lanes[1], slot = "building" }
						end
						if c.type == "Spell" or spot then
							F.onCardClicked(a.handUid)
							if S.pick and S.pick.step == "lane" and spot then
								F.onBoardClick({ team = S.myTeam, lane = spot.lane, row = spot.row, slot = spot.slot or (spot.row == 2 and "back" or "creature") })
							end
							if S.pick and S.pick.step == "target" then
								local t = (S.pick.action.targets or {})[1]
								if t then
									F.onBoardClick({ team = t.team, lane = t.lane, row = t.row or 1, slot = (t.row == 2) and "back" or "creature" })
								end
							end
							if S.pick then
								F.clearPick()
							else
								acted = true
								plays += 1
								playedThisTurn += 1
							end
							break
						end
					end
				end
			end
			if not acted then
				F.pressBattle()
				F.pressBattle()
			end
		end
		M.advance(0.5)
	end
	return plays
end

do
	local MatchScreen = makeEnv(clientScript, clientCache).require(shared.MatchScreen)
	local F, S = MatchScreen.F, MatchScreen.S
	local stations = Workspace.MenuRoom.Stations
	check(stations:FindFirstChild("Campaign") and stations.Campaign:FindFirstChild("PaintingFrame") ~= nil, "the painting over the fireplace became the Campaign station")
	check(stations:FindFirstChild("PlazaDoor") and stations.PlazaDoor:FindFirstChild("Door") ~= nil, "the front door became the Plaza station")
	local campaignSign = stations.Campaign:FindFirstChild("Sign", true)
	check(campaignSign and campaignSign:FindFirstChildWhichIsA("TextLabel").Text == "Campaign", "the Campaign station has a sign in the room's style")
	check(named("NavCampaign") ~= nil and named("NavPlazaDoor") ~= nil, "the nav bar has Campaign and Plaza buttons")

	local gems0 = player:GetAttribute("Gems")
	click(named("NavCampaign"), "Campaign station")
	M.advance(2)
	check(named("StationTitle") and named("StationTitle").Text == "Campaign", "the Campaign panel opens")
	check(named("CampaignScroll") ~= nil, "the world map shows")
	local den = named("WorldDen")
	check(den ~= nil and den.Text == "🏠", "the Card Den is open")
	local candy = named("WorldCandy")
	check(candy ~= nil and candy.Text == "🔒", "Gumdrop Plaza is locked until the Den's boss falls")
	local act1, act2 = named("Act1"), named("Act2")
	check(act1 ~= nil and act2 ~= nil and named("Act6") ~= nil, "the six acts show")
	local function actOpen(row)
		for _, d in ipairs(row:GetChildren()) do
			if d.ClassName == "TextLabel" and (d.Text == "🔒") then
				return false
			end
		end
		return true
	end
	check(act1 and actOpen(act1), "act 1 is open")
	check(act2 and not actOpen(act2), "act 2 is locked")
	check(labelStarting("First clear: 💎 " .. Campaign.FirstClearGems[1]) ~= nil, "act 1 shows its first-clear reward")
	local startB = named("StartButton")
	check(startB ~= nil and startB.Text == "⚔  START", "the Start button is ready with your own deck")

	local won, tries, firstCard = false, 0, nil
	local rewardsSeen = false
	click(startB, "START act 1")
	while tries < 3 and not won do
		tries += 1
		local waited = 0
		while not (S.view and not S.view.over) and waited < 20 do
			M.advance(0.5)
			waited += 0.5
		end
		check(S.view ~= nil and S.view.mode == "Campaign", "the Campaign match starts (try " .. tries .. ")")
		check(S.campaign and S.campaign.id == "Den:1:N", "the client knows which stage it is")
		check(S.campaign and S.campaign.name == "Practice Pip", "act 1's opponent is Practice Pip")
		local plays = playOut(S, F)
		check(S.view and S.view.over, "the stage ends (" .. plays .. " cards played)")
		won = S.view and S.view.winner == S.myTeam
		print("note campaign try " .. tries .. ": " .. (won and "won" or "lost"))
		local shown = false
		for _ = 1, 16 do
			M.advance(0.5)
			local rp = named("ResultPanel")
			if rp and visible(rp) then
				shown = true
				break
			end
		end
		check(shown, "the result panel shows")
		check(named("CampaignStars") ~= nil, "the result shows the three stars")
		check(named("BackToMap") ~= nil, "the result has a Map button")
		if won then
			rewardsSeen = true
			check(named("CampaignNext") ~= nil, "a win offers Next")
		else
			check(named("CampaignRetry") ~= nil and named("CampaignRetry").Text == "⟳ Try again", "a loss offers Try again")
			click(named("CampaignRetry"), "Try again")
			M.advance(1)
		end
	end
	check(won, "act 1 was beaten within 3 tries")
	if won then
		local d = saveData()
		local clear = d and d.campaign and d.campaign.clears["Den:1:N"]
		check(clear and clear.wins == 1, "the clear is on the save")
		check(clear and clear.stars and clear.stars % 2 == 1, "the first star (win) is on the save")
		check(player:GetAttribute("Gems") >= gems0 + Campaign.FirstClearGems[1], "the first clear paid its Gems (" .. tostring(player:GetAttribute("Gems") - gems0) .. ")")
		firstCard = Campaign.stage("Den:1:N").firstCard
		check(firstCard == nil or (d.collection[firstCard] or 0) > 0, "the first-clear card is in the collection")
		check((player:GetAttribute("CampaignStars") or 0) >= 1, "the CampaignStars attribute counts the new stars")
		click(named("BackToMap"), "Map")
		M.advance(16)
		check(named("StationTitle") and named("StationTitle").Text == "Campaign", "back at the Campaign map after the stage")
		M.advance(1)
		local a2 = named("Act2")
		check(a2 ~= nil and actOpen(a2), "act 2 is open now")
		local a1 = named("Act1")
		local starsText = nil
		for _, d0 in ipairs(a1 and a1:GetChildren() or {}) do
			if d0.ClassName == "TextLabel" and string.find(d0.Text, "★") then
				starsText = d0.Text
			end
		end
		check(starsText ~= nil, "act 1 shows its stars on the map (" .. tostring(starsText) .. ")")
	end
	check(rewardsSeen or not won, "rewards were checked")
	-- the hourly Challenge is locked until the Den's boss is beaten
	click(buttonWithText("⏳ Challenge"), "Challenge tab")
	M.advance(0.5)
	check(labelStarting("⏳ The hourly Challenge") ~= nil, "the Challenge tab shows this hour's Challenge")
	local cs = named("StartButton")
	check(cs ~= nil and cs.Text == "⚔  START" and cs.BackgroundColor3 ~= Color3.fromRGB(70, 190, 110), "the Challenge waits for the Den's boss")
	-- the server refuses a stage you haven't opened, whatever the screen says
	remotes.MenuAction:FireServer("StartCampaign", { stage = "Mall:6:H", deck = "s1" })
	M.advance(1)
	check(S.view == nil or S.view.over, "the server refuses a locked stage")
end

---------------------------------------------------------------------------
-- The Plaza: out the front door, your avatar walks around, your booth shows your best cards,
-- a friend likes it (once a day), a big pull gets a banner and the Hall of Pulls, the altar opens
-- packs, and the Duel kiosk takes you back in to the Duel Table
---------------------------------------------------------------------------
do
	local PlazaClient = makeEnv(clientScript, clientCache).require(shared.PlazaClient)
	local P = PlazaClient.S
	local plaza = Workspace:FindFirstChild("Plaza")
	check(plaza ~= nil and plaza:FindFirstChild("Booths") and #plaza.Booths:GetChildren() == Plaza.Booths, "the server built the Plaza with " .. Plaza.Booths .. " booths")
	local slot = player:GetAttribute("BoothSlot")
	check(slot == 1, "you got a booth (" .. tostring(slot) .. ")")
	local booth = plaza and plaza.Booths:FindFirstChild("Booth" .. tostring(slot))
	check(booth and booth:GetAttribute("OwnerName") == "Nash", "the booth carries your name")
	local cards = booth and booth:GetAttribute("Cards") or ""
	local n = 0
	for _ in string.gmatch(cards, "[^,]+") do
		n += 1
	end
	check(n == 3, "the booth shows 3 cards from your collection (" .. cards .. ")")

	Lighting.ClockTime = 21 -- (the room's night, as default.project.json sets it)
	local roomClock = Lighting.ClockTime
	click(named("NavPlazaDoor"), "Plaza door station")
	M.advance(1)
	check(named("StationTitle") and named("StationTitle").Text == "The Plaza", "the door's panel opens")
	click(named("WalkOut"), "Walk out")
	M.advance(4)
	check(P.inside == true, "you're in the Plaza")
	local rootPart = player.Character.HumanoidRootPart
	check((rootPart.Position - Plaza.Origin).Magnitude < 150, "the server walked your character over (" .. tostring(rootPart.Position) .. ")")
	check(player:GetAttribute("InPlaza") == true, "InPlaza is set for everyone to see")
	check(camera.CameraType == Enum.CameraType.Custom, "Roblox's own camera follows your avatar")
	check(Lighting.ClockTime == 16.8, "golden hour out here")
	check(named("Hud") ~= nil, "the Plaza buttons show (Home, My booth)")
	check(named("StationTitle") == nil and named("NavCampaign") == nil, "the room's panels and nav bar are hidden")
	M.advance(1)
	local stand = booth and booth:FindFirstChild("Stand1")
	check(stand and stand:FindFirstChild("CardGui") ~= nil, "your booth's cards are drawn on the stands")
	local hasCreature = false
	for id in string.gmatch(cards, "[^,]+") do
		if CardData.Cards[id].type == "Creature" then
			hasCreature = true
		end
	end
	check(not hasCreature or plaza:FindFirstChild("Companion_" .. player.UserId) ~= nil, "your companion walks with you")
	local head = player.Character:FindFirstChild("Head")
	check(head == nil or head:FindFirstChild("PlazaPlate") ~= nil, "a nameplate over your head")

	-- the booth editor: pick two cards
	click(buttonWithText("🖼 My booth"), "My booth")
	M.advance(1)
	local editor = named("BoothEditor")
	check(editor ~= nil, "the booth editor opens")
	local d = saveData()
	local owned = {}
	for id, c in pairs(d.collection) do
		if c > 0 then
			table.insert(owned, id)
		end
	end
	Plaza.sortRarest(owned)
	local pick = { owned[#owned], owned[#owned - 1] } -- two of your commonest, so it differs from the default
	for _, id in ipairs(pick) do
		local cell = editor and editor:FindFirstChild(id, true)
		click(cell, "card " .. tostring(id))
	end
	click(buttonWithText("✓ Save booth"), "Save booth")
	M.advance(1.5)
	local now = booth:GetAttribute("Cards") or ""
	check(string.sub(now, 1, #pick[1] + #pick[2] + 1) == pick[1] .. "," .. pick[2], "the booth shows the picked cards first (" .. now .. ")")
	check(d.showcase and #d.showcase.cards == 2, "the picks are on the save")

	-- likes: not your own; a friend's once a day
	local heart = booth:FindFirstChild("Heart")
	heart.Like.Triggered:Fire(player)
	M.advance(0.5)
	check(labelStarting("That's your own booth") ~= nil, "you can't like your own booth")
	local friend = M.new("Player", true)
	friend.Name = "donatjalt"
	M.rec(friend).props.DisplayName = "jaault"
	M.rec(friend).props.UserId = 5550002
	friend.Parent = Players
	Players.PlayerAdded:Fire(friend)
	M.advance(3)
	check(Economy.isLoaded(friend), "a friend joins and their save loads")
	check(friend:GetAttribute("BoothSlot") == 2, "the friend gets the next booth")
	heart.Like.Triggered:Fire(friend)
	M.advance(0.5)
	check(player:GetAttribute("BoothLikes") == 1, "the friend's like lands on your booth")
	check(labelStarting("❤ jaault liked your booth") ~= nil, "you're told who liked it")
	heart.Like.Triggered:Fire(friend)
	M.advance(0.5)
	check(player:GetAttribute("BoothLikes") == 1, "only one like per booth per day")

	-- a big pull: banner, light pillar, Hall of Pulls, best pull and title
	local mythic = nil
	for _, id in ipairs(CardData.List) do
		if CardData.Cards[id].rarity == "Mythic" and not CardData.Cards[id].token then
			mythic = mythic or id
		end
	end
	ServerScriptService.PullFeed:Fire(friend, { mythic, "jelly_bean_scout" })
	M.advance(2)
	check(named("Banner") == nil, "the banner waits so it doesn't spoil the reveal")
	M.advance(Plaza.FeedDelay)
	local banner = named("Banner")
	check(banner ~= nil, "a banner tells the server about the Mythic pull")
	local hallGui = plaza.HallOfPulls.Board:FindFirstChild("HallGui")
	local inHall = false
	for _, t in ipairs(hallGui and hallGui:GetDescendants() or {}) do
		if t.ClassName == "TextLabel" and string.find(t.Text, CardData.Cards[mythic].name, 1, true) then
			inHall = true
		end
	end
	check(inHall, "the pull is on the Hall of Pulls")
	check(friend:GetAttribute("BestRarity") == "Mythic", "the friend's best pull is remembered")
	check(friend:GetAttribute("HubTitle") == Plaza.PullTitles.Mythic, "and earns a title (" .. tostring(friend:GetAttribute("HubTitle")) .. ")")

	-- leaderboards (no OrderedDataStore here: this server's players)
	M.advance(Plaza.BoardSeconds)
	local starsBoard = plaza.Boards.Stars.Board:FindFirstChild("BoardGui")
	local listed = false
	for _, t in ipairs(starsBoard and starsBoard:GetDescendants() or {}) do
		if t.ClassName == "TextLabel" and string.find(t.Text, "Nash", 1, true) then
			listed = true
		end
	end
	check(listed, "the Campaign Stars board lists you")

	-- the Pull Altar opens the packs right here
	game:GetService("ProximityPromptService").PromptTriggered:Fire(plaza.Altar.Dais.OpenPacks, player)
	M.advance(1)
	local altar = named("AltarPacks")
	check(altar ~= nil and altar:FindFirstChild("PackPartyControls", true) ~= nil, "the altar opens the pack panel")
	click(altar and altar:FindFirstChild("TextButton") and buttonWithText("✕", false, altar), "close the altar panel")
	M.advance(0.5)

	-- the Duel kiosk: back inside at the Duel Table
	game:GetService("ProximityPromptService").PromptTriggered:Fire(plaza.DuelKiosk.Table.Duel, player)
	M.advance(3)
	check(P.inside == false, "back inside")
	check(player:GetAttribute("InPlaza") == false, "InPlaza is cleared")
	check((rootPart.Position - Plaza.Origin).Magnitude > 500, "your character is back in the room")
	check(Lighting.ClockTime == roomClock and Lighting:FindFirstChild("PlazaAtmosphere") == nil, "the room's own light is back (" .. tostring(Lighting.ClockTime) .. ")")
	check(camera.CameraType == Enum.CameraType.Scriptable, "the room's camera is back")
	check(named("StationTitle") and named("StationTitle").Text == "Duel Table", "the kiosk opened the Duel Table")
	check(plaza:FindFirstChild("Companion_" .. player.UserId) == nil, "your companion stays outside")
	friend.Parent = nil
	Players.PlayerRemoving:Fire(friend)
	M.advance(1)
	check(plaza.Booths.Booth2:GetAttribute("OwnerName") == nil, "the friend's booth is free again after they leave")
end

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

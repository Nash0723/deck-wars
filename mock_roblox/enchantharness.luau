-- Enchants inside the fake Roblox: the Enchanting Crystal in the Park (and the Pull Altar's new
-- spot), the enchant window (pick a card, roll, the roll animation, keep new or old), the glow on
-- cards, the aura on the table and every match event's effect.
-- Usage (from the repo root): luaurun mock_roblox/enchantharness.luau mock_roblox

local M = require("RobloxMock")
local SRC = "src/"

for k, v in pairs(M.env) do
	_G[k] = v
end

local game = M.service("Game", "DataModel")
local Workspace = M.service("Workspace")
local ReplicatedStorage = M.service("ReplicatedStorage")
local RunService = M.service("RunService")
local Players = M.service("Players")
local ServerScriptService = M.service("ServerScriptService")
local ServerStorage = M.service("ServerStorage")
local SoundService = M.service("SoundService")
local TweenService = M.service("TweenService")
local Debris = M.service("Debris")
local UserInputService = M.service("UserInputService")
local GuiService = M.service("GuiService")
local Lighting = M.service("Lighting")
for _, s in ipairs({ Workspace, ReplicatedStorage, RunService, Players, ServerScriptService, ServerStorage, SoundService, TweenService, Debris, UserInputService, GuiService, Lighting }) do
	s.Parent = game
end
local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.CFrame = CFrame.lookAt(Vector3.new(0, 16, 12), Vector3.new(0, 4.2, 1.25))
camera.Parent = Workspace
Workspace.CurrentCamera = camera
M.onFrame = function()
	RunService.RenderStepped:Fire(1 / 30)
	RunService.Heartbeat:Fire(1 / 30)
end

local player = M.new("Player", true)
player.Name = "Nash"
player.Parent = Players
M.localPlayer = player
M.rec(Players).props.LocalPlayer = player
local playerGui = M.new("PlayerGui", true)
playerGui.Name = "PlayerGui"
playerGui.Parent = player

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
		if cache[mod] == nil then
			local f = __loadchunk(__readfile(r.sourcePath), r.sourcePath, makeEnv(mod, cache))
			cache[mod] = f()
		end
		return cache[mod]
	end
	return env
end
local function moduleFrom(path, name, parent)
	local m = Instance.new("ModuleScript")
	m.Name = name
	M.rec(m).sourcePath = path
	m.Parent = parent
	return m
end
local shared = Instance.new("Folder")
shared.Name = "DeckWars"
shared.Parent = ReplicatedStorage
local mods = {}
for _, n in ipairs({ "CardData", "CardLevels", "DeckRules", "Enchants", "EnchantFx", "EnchantUI", "Juice", "UIKit", "Settings", "VfxAssets", "LayerFx", "Park", "ShopCatalog", "StarterDecks", "Rng", "MatchEngine" }) do
	mods[n] = moduleFrom(SRC .. "shared/" .. n .. ".luau", n, shared)
end
local serverFolder = Instance.new("Folder")
serverFolder.Name = "DeckWarsServer"
serverFolder.Parent = ServerStorage
for _, n in ipairs({ "EconomyManager", "ProfileStore" }) do
	mods[n] = moduleFrom(SRC .. "econ/" .. n .. ".luau", n, serverFolder)
end
mods.ParkKit = moduleFrom(SRC .. "park/ParkKit.luau", "ParkKit", ServerScriptService)
mods.ParkBuilder = moduleFrom(SRC .. "park/ParkBuilder.luau", "ParkBuilder", ServerScriptService)
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local MenuAction = Instance.new("RemoteEvent")
MenuAction.Name = "MenuAction"
MenuAction.Parent = remotes

local serverCache, clientCache = {}, {}
local serverReq = makeEnv(nil, serverCache).require
local clientReq = makeEnv(nil, clientCache).require

local function check(cond, msg)
	if not cond then
		M.report("error", "CHECK FAILED: " .. msg)
	else
		print("ok   " .. msg)
	end
end
local function findIn(root, pred)
	for _, d in ipairs(root:GetDescendants()) do
		if pred(d) then
			return d
		end
	end
	return nil
end
local function named(root, name)
	return findIn(root, function(d)
		return d.Name == name
	end)
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
	M.advance(0.05)
end

---------------------------------------------------------------------------
-- The Park: the crystal in the middle, the altar by the Hall of Pulls
---------------------------------------------------------------------------
do
	local ParkBuilder = serverReq(mods.ParkBuilder)
	local Park = serverReq(mods.Park)
	ParkBuilder.UseTerrain = false
	local root = ParkBuilder.build(Workspace)
	check(root ~= nil and root.Parent == Workspace, "the Park builds")
	local shrine = root:FindFirstChild("EnchantShrine")
	check(shrine ~= nil, "the Enchanting Crystal is there")
	local base = shrine and shrine:FindFirstChild("Base")
	local promptP = base and base:FindFirstChild("Enchant")
	check(promptP ~= nil and promptP.ClassName == "ProximityPrompt", "the crystal's floor has the Enchant prompt")
	local O = Park.Origin
	check(base and (Vector3.new(base.Position.X, 0, base.Position.Z) - Vector3.new(O.X, 0, O.Z)).Magnitude < 0.5, "the crystal stands in the middle of the park (the island)")
	local crystal = shrine and shrine:FindFirstChild("Crystal")
	check(crystal and crystal:FindFirstChild("Core") and #crystal:GetChildren() >= 5, "the crystal has a heart, glass bodies and points")
	local core = crystal and crystal:FindFirstChild("Core")
	check(core and core.Position.Y - O.Y > 6, "the crystal floats (" .. tostring(core and core.Position.Y - O.Y) .. " studs up)")
	local orbit, fallen = shrine and shrine:FindFirstChild("Orbit"), shrine and shrine:FindFirstChild("Fallen")
	check(orbit and #orbit:GetChildren() >= 6, "broken shards float round it")
	local onGround = 0
	for _, d in ipairs(fallen and fallen:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Name == "Body" and d.Position.Y - O.Y < 2.5 then
			onGround += 1
		end
	end
	check(onGround >= 8, "broken shards lie on the ground (" .. onGround .. ")")
	local runes = shrine and shrine:FindFirstChild("Runes")
	check(runes and #runes:GetChildren() == 24, "a ring of 24 runes on the floor")
	local maxR = 0
	for _, d in ipairs(shrine:GetDescendants()) do
		if d:IsA("BasePart") then
			maxR = math.max(maxR, (Vector3.new(d.Position.X, 0, d.Position.Z) - Vector3.new(O.X, 0, O.Z)).Magnitude)
		end
	end
	check(maxR < Park.IslandRadius - 1, "everything of the crystal stays on the island (" .. string.format("%.1f", maxR) .. " < " .. Park.IslandRadius - 1 .. ")")
	local altar = root:FindFirstChild("Altar")
	local dais = altar and altar:FindFirstChild("Dais")
	check(dais and dais:FindFirstChild("OpenPacks"), "the Pull Altar still opens packs")
	local hall = root:FindFirstChild("HallOfPulls")
	local frame = hall and hall:FindFirstChild("Frame")
	local dHall = (dais and frame) and (Vector3.new(dais.Position.X, 0, dais.Position.Z) - Vector3.new(frame.Position.X, 0, frame.Position.Z)).Magnitude or 999
	check(dais and (dais.Position - O).Magnitude > 50 and dHall < 22, "the Pull Altar moved in front of the Hall of Pulls (" .. string.format("%.1f", dHall) .. " studs from it)")
	local pack = altar and altar:FindFirstChild("FloatingPack")
	check(pack and dais and math.abs(pack.Position.X - dais.Position.X) < 0.01 and pack.Position.Y > dais.Position.Y, "the altar's floating pack moved with it")
end

---------------------------------------------------------------------------
-- The server side of the window (what MenuServer does), on the real EconomyManager
---------------------------------------------------------------------------
local EconomyManager = serverReq(mods.EconomyManager)
local ProfileStore = serverReq(mods.ProfileStore)
local nextRand = 0.01
EconomyManager.init({
	dataStore = ProfileStore.memoryStore(),
	jobId = "harness",
	clock = function()
		return 1000000
	end,
	wait = function() end,
	warn = function() end,
	random = function()
		return nextRand
	end,
})
EconomyManager.load(player)
EconomyManager.grantCards(player, { "pretzel_guard", "couch_golem", "snack_break" }, "test")
EconomyManager.waitForData(player).coins = 2000
local function snapshot()
	local en = EconomyManager.getEnchants(player)
	return { cards = EconomyManager.getCollection(player), decks = {}, slots = 3, enchants = en.enchants, enchantPity = en.pity, enchantPending = en.pending }
end
MenuAction.OnServerEvent:Connect(function(p, what, options)
	options = type(options) == "table" and options or {}
	if what == "GetDecks" then
		MenuAction:FireClient(p, "Decks", snapshot())
	elseif what == "Enchant" then
		local ok, r = EconomyManager.enchantCard(p, options.id, options.mode)
		local result = { what = what, ok = ok }
		if ok then
			result.id, result.enchant, result.rarity, result.old, result.pending = r.card, r.enchant, r.rarity, r.old, r.pending
		else
			result.why = r
		end
		MenuAction:FireClient(p, "CardResult", result)
		MenuAction:FireClient(p, "Decks", snapshot())
	elseif what == "EnchantChoose" then
		local ok, r = EconomyManager.chooseEnchant(p, options.keep == "new")
		MenuAction:FireClient(p, "CardResult", { what = what, ok = ok, kept = ok and r.kept or nil, why = (not ok) and r or nil })
		MenuAction:FireClient(p, "Decks", snapshot())
	end
end)

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "ParkGui"
gui.Parent = playerGui
local made = 0
local function makeCard(parent, id, size)
	made += 1
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.Size = size or UDim2.fromOffset(120, 168)
	f.Parent = parent
	local l = Instance.new("TextLabel")
	l.Name = "Title"
	l.Text = id
	l.Parent = f
	return f
end
local EnchantUI = clientReq(mods.EnchantUI)
local EnchantFx = clientReq(mods.EnchantFx)
local Enchants = clientReq(mods.Enchants)
EnchantUI.init({ gui = gui, makeCard = makeCard, toast = function() end })
local errors0 = M.errors
EnchantUI.open()
M.advance(0.5)
local win = gui:FindFirstChild("EnchantWindow")
check(win ~= nil and EnchantUI.isOpen(), "the crystal's prompt opens the enchant window")
local cards = win and named(win, "Cards")
local cell = cards and cards:FindFirstChild("Cell_pretzel_guard")
check(cell ~= nil and cards:FindFirstChild("Cell_snack_break") ~= nil, "your creatures and spells are listed")
click(cell, "Cell_pretzel_guard")
M.advance(0.2)
local button = named(win, "EnchantButton")
check(button ~= nil and named(win, "LuckyButton") ~= nil, "Enchant and Lucky buttons")
check(named(win, "Pity") and string.find(named(win, "Pity").Text, "Epic", 1, true) ~= nil, "it shows how close the next sure Epic is")
local coins0 = EconomyManager.getBalance(player, "Coins")
nextRand = 0.01 -- a Common rune
click(button, "EnchantButton")
M.advance(0.3)
check(EnchantUI.S.rolling == true, "the roll animation plays")
local stage = named(win, "Stage")
local rollRim = stage and named(stage, "RollRim")
check(rollRim ~= nil, "the card's rim flickers through the colours")
M.advance(8)
check(EnchantUI.S.rolling == false, "the roll lands")
check(EconomyManager.getBalance(player, "Coins") == coins0 - Enchants.Cost.Coins, "the roll cost " .. Enchants.Cost.Coins .. " Coins")
local en = EconomyManager.getEnchants(player).enchants.pretzel_guard
check(Enchants.rarityOf(en) == "Common", "a Common rune went on (" .. tostring(en) .. ")")
stage = named(win, "Stage")
local big = stage and stage:FindFirstChild("BigCard")
check(big and big:FindFirstChild("EnchantRim") and big:FindFirstChild("EnchantGem"), "the big card glows with its enchant")
local info = named(win, "EnchantInfo")
check(info and named(info, "Name") and string.find(named(info, "Name").Text, Enchants.get(en).name, 1, true), "the enchant's name and text show")
local gridCell = named(win, "Cell_pretzel_guard")
check(gridCell and named(gridCell, "EnchantRim") ~= nil, "the card glows in the list too")
-- roll again: a Secret, which waits for the choice
nextRand = 0.9999
click(named(win, "EnchantButton"), "EnchantButton again")
M.advance(10)
local keepNew, keepOld = named(win, "KeepNew"), named(win, "KeepOld")
check(keepNew ~= nil and keepOld ~= nil, "rolling an enchanted card asks: keep new or old")
check(EconomyManager.getEnchants(player).enchants.pretzel_guard == en, "the old rune stays until you choose")
click(keepNew, "KeepNew")
M.advance(0.5)
local en2 = EconomyManager.getEnchants(player).enchants.pretzel_guard
check(Enchants.rarityOf(en2) == "Secret", "keep new: the Secret rune is on (" .. tostring(en2) .. ")")
check(named(win, "KeepNew") == nil and named(win, "EnchantButton") ~= nil, "back to the buttons")
-- out of Coins
EconomyManager.waitForData(player).coins = 0
click(named(win, "EnchantButton"), "EnchantButton broke")
M.advance(0.5)
local note = named(win, "Note")
check(note and string.find(note.Text, "Coins", 1, true), "not enough Coins: it says so")
EnchantUI.close()
M.advance(1)
check(not EnchantUI.isOpen(), "the window closes")
check(M.errors == errors0, "the enchant window: no script errors")

---------------------------------------------------------------------------
-- Cards, the aura on the table, the match events
---------------------------------------------------------------------------
do
	local errs = M.errors
	for _, r in ipairs(Enchants.Rarities) do
		local f = makeCard(gui, "pretzel_guard")
		local eid = Enchants.pool("pretzel_guard", r)[1]
		local rim = EnchantFx.decorateCard(f, eid)
		check(rim ~= nil and f:FindFirstChild("EnchantGem"), r .. " enchants put a rim and a gem on the card")
		local glow = rim and rim:FindFirstChild("Glow")
		M.advance(0.3)
		local want = Enchants.Colors[r]
		if r ~= "Secret" and glow then
			local c = glow.Color
			check(math.abs(c.R * 255 - want[1]) < 2 and math.abs(c.G * 255 - want[2]) < 2 and math.abs(c.B * 255 - want[3]) < 2, r .. " rim is the " .. r .. " colour")
		end
	end
	-- Secret cycles
	local f = makeCard(gui, "couch_golem")
	local glow = EnchantFx.decorateCard(f, "starborn"):FindFirstChild("Glow")
	local c1 = glow.Color
	M.advance(1.5)
	check(glow.Color ~= c1, "the Secret rim shifts colour")
	check(EnchantFx.decorateCard(makeCard(gui, "couch_golem"), nil) == nil, "no enchant, no rim")
	-- the aura follows its creature and leaves with it
	local folder = Instance.new("Folder")
	folder.Parent = Workspace
	local model = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Anchored = true
	body.Size = Vector3.new(1.4, 2, 1.2)
	body.CFrame = CFrame.new(3, 5, 2)
	body.Parent = model
	model.PrimaryPart = body
	model.Parent = folder
	local aura = EnchantFx.aura(model, "titan_blood", folder, 2, true)
	check(aura ~= nil and folder:FindFirstChild("EnchantAura"), "an enchanted creature gets an aura")
	M.advance(0.2)
	check(math.abs(aura.ring.Position.X - 3) < 0.01 and aura.ring.Position.Y < 4.2, "the rune ring lies at its feet")
	model:PivotTo(CFrame.new(-2, 5, 0))
	M.advance(0.1)
	check(math.abs(aura.ring.Position.X + 2) < 0.01, "the aura follows the creature")
	local n = EnchantFx.count()
	model:Destroy()
	M.advance(0.1)
	check(EnchantFx.count() == n - 1 and folder:FindFirstChild("EnchantAura") == nil, "the aura goes with the creature")
	-- every match event
	local entry = { home = CFrame.new(0, 4.5, 0), height = 2 }
	local other = { home = CFrame.new(0, 4.5, -3), height = 2 }
	local log = {}
	local api = {
		units = { [1] = entry, [2] = other },
		fx = function(name, pos, opts)
			table.insert(log, name)
			return nil
		end,
		unitPosition = function(e)
			return e.home.Position + Vector3.new(0, 1.2, 0)
		end,
		groundOf = function(e)
			return e.home.Position
		end,
		heroPos = function()
			return Vector3.new(-8, 4.5, 4)
		end,
		floatText = function(_, text)
			table.insert(log, "text:" .. text)
		end,
		step = function() end,
		sound = function() end,
	}
	for _, e in ipairs({
		{ what = "arrive", uid = 1, enchant = "starborn" },
		{ what = "arrive", uid = 1, enchant = "thick_hide" },
		{ what = "thorns", uid = 1, target = 2, enchant = "thorns" },
		{ what = "leech", uid = 1, enchant = "vampire", team = 1 },
		{ what = "rebirth", uid = 1, enchant = "phoenix" },
		{ what = "cast", seat = 1, team = 1, enchant = "wellspring" },
		{ what = "arrive", uid = 99, enchant = "fury" }, -- a creature the screen no longer has
	}) do
		EnchantFx.matchEvent(e, api)
	end
	local texts = 0
	for _, l in ipairs(log) do
		if string.sub(l, 1, 5) == "text:" then
			texts += 1
		end
	end
	check(texts == 6, "every enchant event shows its name (" .. texts .. ")")
	check(M.errors == errs, "cards, auras and match effects: no script errors")
end

for _, line in ipairs(M.log) do
	if string.sub(line, 1, 6) == "error:" and not string.find(line, "CHECK FAILED", 1, true) then
		print("LOGGED " .. line)
	end
end
print(string.format("MOCK RESULT: %d errors, %d warnings", M.errors, M.warnings))

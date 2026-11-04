-- Plays Deck Wars end to end inside the fake Roblox: menu, sitting down, full matches
-- against every bot difficulty with all six decks, tile clicks in 3D (summon, walk, attack,
-- hit the hero), leaving mid-match and the turn timer.
-- Usage: luaurun harness.luau <mockdir>   (run from the scratchpad folder)

local M = require("RobloxMock")
local SRC = "src/"

for k, v in pairs(M.env) do
	_G[k] = v
end
local typeof = M.typeof

---------------------------------------------------------------------------
-- Build the DataModel like Rojo's project file does
---------------------------------------------------------------------------
local game = M.service("Game", "DataModel")
local Workspace = M.service("Workspace")
local ReplicatedStorage = M.service("ReplicatedStorage")
local ServerScriptService = M.service("ServerScriptService")
local Players = M.service("Players")
local TweenService = M.service("TweenService")
local UserInputService = M.service("UserInputService")
local RunService = M.service("RunService")
local Debris = M.service("Debris")
local StarterGui = M.service("StarterGui")
local Lighting = M.service("Lighting")
local StarterPlayer = M.service("StarterPlayer")
local SoundService = M.service("SoundService")
local ServerStorage = M.service("ServerStorage")
local DataStoreService = M.service("DataStoreService")
local MarketplaceService = M.service("MarketplaceService")
local PolicyService = M.service("PolicyService")
for _, s in ipairs({ Workspace, ReplicatedStorage, ServerScriptService, Players, TweenService, UserInputService, RunService, Debris, StarterGui, Lighting, StarterPlayer, SoundService, ServerStorage, DataStoreService, MarketplaceService, PolicyService }) do
	s.Parent = game
end

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
Workspace.CurrentCamera = camera

local buildWorld = require("WorldData")
M.build(buildWorld(), Workspace)

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
for _, n in ipairs({ "CardData", "MatchEngine", "BotBrain", "Rng", "StarterDecks", "CreatureModelData", "CreatureBuilder", "Settings", "Juice", "TitleScreen", "ShopCatalog", "Cosmetics", "ShopUI", "DeckRules", "DeckBuilderUI" }) do
	moduleFrom(SRC .. "shared/" .. n .. ".luau", n, shared)
end
-- The economy (Gems, Coins, Shop): server modules in ServerStorage and its remotes
local econFolder = Instance.new("Folder")
econFolder.Name = "DeckWarsServer"
econFolder.Parent = ServerStorage
for _, n in ipairs({ "EconomyManager", "DevAccess", "ProfileStore" }) do
	moduleFrom(SRC .. "econ/" .. n .. ".luau", n, econFolder)
end
-- the deck saving module (it keeps decks in the EconomyManager profile)
moduleFrom(SRC .. "server/PlayerDecks.luau", "PlayerDecks", ServerScriptService)
local econRemotes = Instance.new("Folder")
econRemotes.Name = "EconomyRemotes"
econRemotes.Parent = ReplicatedStorage
for _, n in ipairs({ "ShopAction", "EconomyEvent", "DevAction" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = econRemotes
end
M.userIds = { DNash2307 = 5550001, donatjalt = 5550002 } -- (the local test player is neither)
-- Pack Brawl (the Pack Party corner's pull cinematic)
local pb = Instance.new("Folder")
pb.Name = "PackBrawl"
pb.Parent = ReplicatedStorage
for _, n in ipairs({ "Kit", "PullRates", "Casting", "Scripts", "Rig", "Moves", "Arena", "Fighters", "CamRig", "Fx", "Sfx", "Poses", "Director", "Reveal", "PackTease", "PackParty" }) do
	moduleFrom(SRC .. "packbrawl/" .. n .. ".luau", n, pb)
end
local pullRemotes = Instance.new("Folder")
pullRemotes.Name = "PullRemotes"
pullRemotes.Parent = ReplicatedStorage
for _, n in ipairs({ "PullRequest", "PullResult" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = pullRemotes
end
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "MatchEvent", "MatchAction", "MenuAction" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end

-- The local player and their character
local player = M.new("Player", true)
player.Name = "Nash"
M.rec(player).props.DisplayName = "Nash"
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
M.rec(pm).mockValue = {
	GetControls = function()
		return {
			Disable = function() end,
			Enable = function() end,
		}
	end,
}
pm.Parent = playerScripts

local character = Instance.new("Model")
character.Name = "Nash"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.Parent = character
character.PrimaryPart = root
character.Parent = Workspace
player.Character = character

---------------------------------------------------------------------------
-- Script loading
---------------------------------------------------------------------------
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
			local src = __readfile(r.sourcePath)
			local f = __loadchunk(src, r.sourcePath, makeEnv(mod, cache))
			cache[mod] = f()
		end
		return cache[mod]
	end
	return env
end

local serverCache, clientCache = {}, {}
local function runScript(path, scriptInst, cache)
	local src = __readfile(path)
	local f = __loadchunk(src, path, makeEnv(scriptInst, cache))
	task.spawn(f)
end

local serverScript = Instance.new("Script")
serverScript.Name = "MatchServer"
serverScript.Parent = ServerScriptService
local clientScript = Instance.new("LocalScript")
clientScript.Name = "DeckWarsClient"
clientScript.Parent = playerScripts

M.onFrame = function()
	RunService.RenderStepped:Fire(1 / 30)
	RunService.Heartbeat:Fire(1 / 30)
end

runScript(SRC .. "server/MatchServer.server.luau", serverScript, serverCache)
local pullServerScript = Instance.new("Script")
pullServerScript.Name = "PullServer"
pullServerScript.Parent = ServerScriptService
runScript(SRC .. "pullserver/PullServer.server.luau", pullServerScript, serverCache)
local econServerScript = Instance.new("Script")
econServerScript.Name = "EconomyServer"
econServerScript.Parent = ServerScriptService
runScript(SRC .. "server/EconomyServer.server.luau", econServerScript, serverCache)
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
		if i:IsA("ScreenGui") and not i.Enabled == false then
			-- ScreenGui.Enabled defaults to true in Roblox; our mock default is false, so ignore it
		end
		i = i.Parent
	end
	return true
end

local function find(pred)
	for _, d in ipairs(playerGui:GetDescendants()) do
		if pred(d) and visible(d) then
			return d
		end
	end
	return nil
end
local function findAll(pred)
	local out = {}
	for _, d in ipairs(playerGui:GetDescendants()) do
		if pred(d) and visible(d) then
			table.insert(out, d)
		end
	end
	return out
end
local function buttonWithText(text, prefix)
	return find(function(d)
		return d.ClassName == "TextButton" and (d.Text == text or (prefix and string.sub(d.Text, 1, #text) == text))
	end)
end
local function labelWithText(text)
	return find(function(d)
		return d.ClassName == "TextLabel" and d.Text == text
	end)
end
local function click(b, what)
	assert(b, "button not found: " .. tostring(what))
	local ok, why = M.clickable(b)
	if ok then
		b.Activated:Fire()
	else
		M.report("error", "can't click " .. tostring(what) .. ": " .. why)
	end
	M.advance(0.1)
end

local function check(cond, msg)
	if not cond then
		M.report("error", "CHECK FAILED: " .. msg)
	else
		print("ok   " .. msg)
	end
end

-- Watch what the server sends the client
local MatchEvent = remotes.MatchEvent
local results, ended, updates, errorsFromServer = {}, 0, 0, {}
local lastUpdate = nil -- the newest update the server sent (to replay command animations against a real board)
-- Pacing probe: when each update was sent and when the client said it finished playing it.
local probe = { match = 0, sent = {}, acked = {}, order = {} }
local sentKinds = {} -- what the client actually sent the server, by action kind
local eventKinds = {} -- events the client was asked to animate, by type (for the new command events)
remotes.MatchAction.OnServerEvent:Connect(function(_, action)
	if type(action) == "table" and action.kind == "ack" and type(action.seq) == "number" then
		probe.acked[probe.match .. ":" .. action.seq] = time()
	elseif type(action) == "table" and type(action.kind) == "string" then
		sentKinds[action.kind] = (sentKinds[action.kind] or 0) + 1
		if action.kind == "attack" and action.hero then
			sentKinds.heroAttack = (sentKinds.heroAttack or 0) + 1
		end
		if action.kind == "move" and action.swap then
			sentKinds.swap = (sentKinds.swap or 0) + 1
		end
	end
end)
MatchEvent.OnClientEvent:Connect(function(payload)
	if payload.kind == "update" then
		if payload.started then
			probe.match += 1
		end
		if payload.seq then
			local key = probe.match .. ":" .. payload.seq
			probe.sent[key] = time()
			table.insert(probe.order, { key = key, events = #(payload.events or {}), match = probe.match })
		end
		updates += 1
		if not payload.synthetic then
			lastUpdate = payload
		end
		for _, ev in ipairs(payload.events or {}) do
			local k = ev.type == "spawn" and ev.raised and "raised" or ev.type
			eventKinds[k] = (eventKinds[k] or 0) + 1
		end
		if payload.result then
			table.insert(results, payload.result)
		end
	elseif payload.kind == "ended" then
		ended += 1
	elseif payload.kind == "error" then
		table.insert(errorsFromServer, payload.message)
	end
end)

---------------------------------------------------------------------------
-- Scenario 0: the title screen (logo slam, PLAY flies the camera into the room)
---------------------------------------------------------------------------
do
	local errors0 = M.errors
	local title = playerGui:FindFirstChild("DeckWarsTitle")
	check(title ~= nil, "the title screen shows on join")
	check(labelWithText("DECK WARS") == nil, "the menu stays hidden behind the title")
	local deck = title and title:FindFirstChild("Deck", true)
	check(deck ~= nil and deck.Position.X.Offset > -100, "DECK has slammed into place")
	local camY0 = camera.CFrame.Position
	M.advance(1)
	check((camera.CFrame.Position - camY0).Magnitude > 0.01, "the camera drifts across the room behind the title")
	-- the room ignores keys and clicks while the title is up
	UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.D, UserInputType = Enum.UserInputType.Keyboard }, false)
	M.advance(0.2)
	check(labelWithText("Deck Shelf") == nil, "station keys do nothing on the title screen")
	local play = title and title:FindFirstChild("Play", true)
	check(play ~= nil, "PLAY button shows")
	click(play, "PLAY")
	M.advance(0.6)
	check(labelWithText("DECK WARS") ~= nil, "the menu comes in after PLAY")
	M.advance(2.6)
	check(playerGui:FindFirstChild("DeckWarsTitle") == nil, "the title screen is gone")
	check((camera.CFrame.Position - Vector3.new(0, 15, 22)).Magnitude < 0.5, "the camera has flown in to the room overview")
	local scales = findAll(function(d)
		return d.ClassName == "UIScale" and d.Name == "JuiceScale" and d.Parent and d.Parent:IsA("TextButton") and d.Parent.Parent and d.Parent.Parent.Name ~= "" and d.Parent.Text == "Pack Party"
	end)
	check(#scales == 1 and math.abs(scales[1].Scale - 1) < 0.01, "the station buttons have popped in to full size")
	check(M.errors == errors0, "title screen: no script errors")
end

---------------------------------------------------------------------------
-- Scenario 1: menu navigation, including a click on the 3D room
---------------------------------------------------------------------------
check(labelWithText("DECK WARS") ~= nil, "menu title shows")
for _, name in ipairs({ "Deck Shelf", "Pack Party", "Shop", "Trophy Wall", "Settings", "Back" }) do
	click(buttonWithText(name), name)
	M.advance(1.2)
end
local CardDataForCheck = makeEnv(clientScript, clientCache).require(ReplicatedStorage.DeckWars.CardData)
check(labelWithText("Your collection") == nil, "collection hides after Back")

-- Click the Pack Party machine in 3D
local machine = Workspace.MenuRoom.Stations.PackParty.MachineBase
M.raycastHook = function()
	return { Instance = machine, Position = machine.Position }
end
UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(300, 300, 0) }, false)
M.advance(1.2)
check(labelWithText("Pack Party") ~= nil, "clicking the prize machine opens Pack Party")
M.raycastHook = nil

---------------------------------------------------------------------------
-- Scenario 1b: open a pack in the Pack Party corner (Pack Brawl plays, then the reveal)
---------------------------------------------------------------------------
do
	local errors0 = M.errors
	local mainGui = nil
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g:FindFirstChild("PackArea", true) then
			mainGui = g
		end
	end
	check(mainGui ~= nil, "Pack Party shows the pack buttons")
	check(buttonWithText("Open 1 pack") ~= nil and buttonWithText("Open 10 packs") ~= nil, "Open 1 / Open 10 buttons show")
	click(buttonWithText("Open 1 pack"), "Open 1 pack")
	M.advance(0.4)
	-- the pack is in your hands first: tap it three times
	local tease = playerGui:FindFirstChild("PackTease")
	check(tease ~= nil, "the pack rises up to be tapped open")
	check(Workspace:FindFirstChild("PackBrawlScene") == nil, "the brawl waits for the pack to be opened")
	M.advance(0.4)
	for k = 1, 3 do
		if tease and tease.Parent then
			click(tease:FindFirstChild("TapPack"), "tap the pack")
			M.advance(0.25)
		end
	end
	check(tease and #tease:FindFirstChild("Pack"):GetChildren() > 0 and tease:FindFirstChild("Crack", true) ~= nil, "taps crack the pack open")
	M.advance(1.6)
	check(playerGui:FindFirstChild("PackTease") == nil, "the pack flies off into the ring")
	local scene = Workspace:FindFirstChild("PackBrawlScene")
	check(scene ~= nil, "opening a pack starts the Pack Brawl")
	check(mainGui and mainGui.Enabled == false, "the menu hides during the brawl")
	-- the room camera must not fight the cinematic's camera
	local camBefore = camera.CFrame
	M.advance(0.5)
	check((camera.CFrame.Position - Vector3.new(9.5, 9.5, -9.5)).Magnitude > 50, "the cinematic has the camera (not the room camera)")
	local t = 0
	while not playerGui:FindFirstChild("PackBrawlReveal") and t < 30 do
		M.advance(0.5)
		t += 0.5
	end
	local reveal = playerGui:FindFirstChild("PackBrawlReveal")
	check(reveal ~= nil, string.format("the brawl reaches the card reveal (%.1f s)", t))
	if reveal then
		M.advance(1.5)
		click(reveal:FindFirstChild("Tap"), "Tap")
		M.advance(1)
	end
	check(playerGui:FindFirstChild("PackBrawlReveal") == nil, "the reveal closes")
	check(Workspace:FindFirstChild("PackBrawlScene") == nil, "the Brawl Box is cleaned up")
	check(mainGui and mainGui.Enabled == true, "the menu comes back after the reveal")
	M.advance(2)
	check((camera.CFrame.Position - Vector3.new(9.5, 9.5, -9.5)).Magnitude < 3, "the camera is back at the Pack Party corner")
	check(find(function(d)
		return d.ClassName == "TextLabel" and string.sub(d.Text, 1, 10) == "Last pull:"
	end) ~= nil, "the status line names the pulled card")
	check(M.errors == errors0, "Pack Party: no script errors")
	-- back to the overview for the match scenarios
	click(buttonWithText("Back"), "Back")
	M.advance(1.5)
end

---------------------------------------------------------------------------
-- Scenario 1c: A / D (and the arrow keys) walk between the stations, and the Settings station
---------------------------------------------------------------------------
do
	local errors0 = M.errors
	local SettingsMod = makeEnv(clientScript, clientCache).require(ReplicatedStorage.DeckWars.Settings)
	local saves = {}
	remotes.MenuAction.OnServerEvent:Connect(function(_, what, data)
		if what == "SaveSettings" then
			table.insert(saves, data)
		end
	end)
	local function key(k)
		UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = k }, false)
		M.advance(1.4)
	end
	local function camNear(x, y, z)
		return (camera.CFrame.Position - Vector3.new(x, y, z)).Magnitude < 1.5
	end
	local function named(name)
		return find(function(d)
			return d.Name == name
		end)
	end
	check(SettingsMod.get("sfx") == 8, "settings start at the defaults (no saved settings in the mock)")
	key(Enum.KeyCode.D)
	check(labelWithText("Practice decks") ~= nil and camNear(0, 16, 23), "D from the overview goes to the Duel Table")
	key(Enum.KeyCode.Right)
	check(camNear(-9, 8, 0) and labelWithText("Deck Shelf") ~= nil, "Right goes on to the Deck Shelf")
	key(Enum.KeyCode.A)
	check(labelWithText("Practice decks") ~= nil, "A goes back to the Duel Table")
	key(Enum.KeyCode.Left)
	check(camNear(-13, 6.2, -13) and labelWithText("Sound effects") ~= nil, "Left from the Duel Table wraps around to Settings")
	key(Enum.KeyCode.D)
	check(labelWithText("Practice decks") ~= nil, "D from Settings wraps around to the Duel Table")
	key(Enum.KeyCode.A)
	-- change a few settings
	click(named("Toggle_actionCam"), "Action camera toggle")
	check(SettingsMod.get("actionCam") == false and named("Toggle_actionCam").Text == "Off", "Action camera turns off")
	click(named("shake_Off"), "Screen shake Off")
	click(named("speed_Fast"), "Table speed Fast")
	click(named("sfx_Down"), "Sound effects -")
	click(named("music_Up"), "Music +")
	check(SettingsMod.get("shake") == "Off" and SettingsMod.get("speed") == "Fast", "choice buttons change the settings")
	check(named("Value_sfx").Text == "70%" and SettingsMod.get("music") == 7, "volume buttons step by 10%")
	M.advance(2)
	local last = saves[#saves]
	check(#saves == 1 and last and last.actionCam == false and last.sfx == 7, "changes are sent to the server once, a moment later (" .. #saves .. " saves)")
	-- the menu hides the in-match copy, but it follows along
	local matchCopy = nil
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d.Name == "Toggle_actionCam" and d ~= named("Toggle_actionCam") then
			matchCopy = d
		end
	end
	check(matchCopy ~= nil and matchCopy.Text == "Off", "the in-match settings window shows the same values")
	click(named("ResetSettings"), "Reset to defaults")
	check(SettingsMod.get("actionCam") == true and SettingsMod.get("speed") == "Normal" and named("Toggle_actionCam").Text == "On", "Reset puts the defaults back")
	key(Enum.KeyCode.S)
	check(camNear(0, 15, 22) and labelWithText("Practice decks") == nil and labelWithText("Sound effects") == nil, "S goes back to the overview")
	key(Enum.KeyCode.Down)
	check(camNear(0, 15, 22), "Down at the overview stays put")
	check(M.errors == errors0, "keyboard + settings: no script errors")
end

---------------------------------------------------------------------------
-- Scenario 1d: the Deck Shelf (starter collection, building, saving and deleting a deck)
---------------------------------------------------------------------------
do
	local errors0 = M.errors
	local function named(name)
		return find(function(d)
			return d.Name == name
		end)
	end
	local function textOf(name)
		local g = named(name)
		return g and g.Text or ""
	end
	click(buttonWithText("Deck Shelf"), "Deck Shelf")
	M.advance(1.5)
	check(labelWithText("Your collection") ~= nil, "the Deck Shelf shows your collection")
	check(find(function(d)
		return d.ClassName == "TextLabel" and string.find(d.Text, "cards found", 1, true) ~= nil and string.sub(d.Text, 1, 2) == "8 "
	end) ~= nil, "a new player owns the 8 different starter cards")
	check(labelWithText("Starter Deck") ~= nil, "the Starter Deck is in slot 1")
	check(named("New_2") ~= nil and named("Edit_1") ~= nil, "slot 1 can be edited, slot 2 is empty")
	click(named("New_2"), "+ New")
	check(named("DeckName") ~= nil and textOf("DeckName") == "Deck 2", "the editor opens on a new deck")
	click(named("Theme_Snack"), "Snack theme")
	click(named("Theme_Critter"), "Critter theme")
	click(named("Theme_Junk"), "Junk theme")
	check(string.find(textOf("Note"), "at most 2 themes", 1, true) ~= nil, "a third theme is refused: " .. textOf("Note"))
	check(string.find(textOf("Lane_1"), "Soda Swamp", 1, true) ~= nil and string.find(textOf("Lane_4"), "Pillow Peaks", 1, true) ~= nil, "the lanes split between the two themes")
	click(named("Lane_1"), "lane 1")
	check(string.find(textOf("Lane_1"), "Pillow Peaks", 1, true) ~= nil, "tapping a lane switches its terrain")
	check(string.sub(textOf("Count"), 1, 7) == "Cards 0", "the new deck starts empty")
	click(named("FillUp"), "Fill up")
	check(string.sub(textOf("Count"), 1, 8) == "Cards 20", "Fill up adds 20 cards from the starter collection: " .. textOf("Count"))
	check(textOf("Problems") == "✔ Ready to play", "the filled deck is ready: " .. textOf("Problems"))
	click(named("Row_jelly_bean_scout"), "remove a Jelly Bean Scout")
	check(string.sub(textOf("Count"), 1, 8) == "Cards 19" and string.find(textOf("Problems"), "Add 1 more card", 1, true) ~= nil, "taking a card out shows what is missing")
	local add = named("Cell_jelly_bean_scout")
	add = add and add:FindFirstChild("Add")
	click(add, "add Jelly Bean Scout")
	check(string.sub(textOf("Count"), 1, 8) == "Cards 20", "tapping a card in the pool adds it back")
	click(add, "add a 4th Jelly Bean Scout")
	check(string.sub(textOf("Count"), 1, 8) == "Cards 20" and textOf("Note") ~= "", "you can't add more copies than you own: " .. textOf("Note"))
	local box = named("DeckName")
	box.Text = "Sweet Mice"
	box.FocusLost:Fire(true)
	click(named("SaveDeck"), "Save")
	M.advance(1)
	check(string.find(textOf("Note"), "Saved", 1, true) ~= nil, "saving says so: " .. textOf("Note"))
	check(labelWithText("Sweet Mice") ~= nil, "the saved deck shows in slot 2")
	click(named("CloseEditor"), "close the editor")
	check(labelWithText("Your collection") ~= nil, "closing the editor shows the collection again")
	-- the Duel Table lists your ready decks
	click(buttonWithText("Duel Table"), "Duel Table")
	M.advance(1.5)
	check(named("MyDeck_1") ~= nil and named("MyDeck_2") ~= nil, "the Duel Table lists your decks")
	check(string.find(textOf("About"), "Snack + Critter", 1, true) ~= nil, "your first ready deck is picked: " .. textOf("About"))
	-- delete slot 2 (tap twice)
	click(buttonWithText("Deck Shelf"), "Deck Shelf")
	M.advance(1.5)
	click(named("Delete_2"), "delete (first tap)")
	check(labelWithText("Sweet Mice") ~= nil, "one tap doesn't delete")
	click(named("Delete_2"), "delete (second tap)")
	M.advance(1)
	check(labelWithText("Sweet Mice") == nil and labelWithText("Empty slot 2") ~= nil, "two taps delete the deck")
	click(buttonWithText("Back"), "Back")
	M.advance(1.5)
	check(M.errors == errors0, "Deck Shelf: no script errors")
end

---------------------------------------------------------------------------
-- Scenario 2: full matches
---------------------------------------------------------------------------
local function myTurn()
	return labelWithText("Your turn!") ~= nil
end

local function handHolders()
	return findAll(function(d)
		if d.ClassName ~= "TextButton" or d.Text ~= "" then
			return false
		end
		local card = d:FindFirstChildOfClass("Frame")
		return card ~= nil
	end)
end

local function cardOf(holder)
	local mover = holder:FindFirstChild("Mover")
	return mover and mover:FindFirstChild("Card") or holder:FindFirstChildOfClass("Frame")
end

local function isPlayable(holder)
	local card = cardOf(holder)
	for _, c in ipairs(card:GetChildren()) do
		if c.ClassName == "Frame" and c.ZIndex == 5 and c.Visible then
			return false
		end
	end
	return true
end

local boardParts = Workspace.MenuRoom.Stations.DuelTable.Board
local stats = { plays = 0, endTurns = 0, prompts = 0, tileClicks = 0, picks = 0, heroClicks = 0, bigMoves = 0, cancels = 0, terrains = 0, commands = 0, greyCommands = 0 }

-- Tiles whose glow is showing (the fill plate of a glowing frame), as Tile_ parts.
local function glowingTiles()
	local out = {}
	local glowFolder = Workspace:FindFirstChild("TableGlow")
	if not glowFolder then
		return out
	end
	for _, g in ipairs(glowFolder:GetChildren()) do
		if g.Name == "TileGlow" and g.Transparency < 0.99 and g.Size.X > 1 and g.Size.Z > 1 then
			local best, bestDist = nil, 1e9
			for _, t in ipairs(boardParts:GetChildren()) do
				if string.sub(t.Name, 1, 5) == "Tile_" then
					local dx, dz = t.Position.X - g.Position.X, t.Position.Z - g.Position.Z
					local d = dx * dx + dz * dz
					if d < bestDist then
						best, bestDist = t, d
					end
				end
			end
			if best then
				table.insert(out, best)
			end
		end
	end
	return out
end

-- Click a part on the table (the mouse ray "hits" it).
local function clickPart(part)
	M.raycastHook = function()
		return { Instance = part, Position = part.Position }
	end
	UserInputService.InputBegan:Fire({ UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(400, 400, 0) }, false)
	M.raycastHook = nil
	M.advance(0.1)
end

local function promptLabel()
	return find(function(d)
		return d.ClassName == "TextLabel" and d.Parent and d.Parent.Name == "PromptBar" and d.Text ~= ""
	end)
end

local samePrompt, lastPrompt = 0, nil
local function handlePrompt()
	local text = promptLabel()
	if not text then
		samePrompt, lastPrompt = 0, nil
		return false
	end
	stats.prompts += 1
	if text.Text == lastPrompt then
		samePrompt += 1
	else
		samePrompt, lastPrompt = 0, text.Text
	end
	if samePrompt > 4 then
		stats.cancels += 1
		click(buttonWithText("Cancel"), "Cancel")
		return true
	end
	if text.Text == "Pick the new terrain" then
		local options = findAll(function(d)
			return d.ClassName == "TextButton" and d.Text ~= "Cancel" and d.Parent and d.Parent:FindFirstChildOfClass("UIGridLayout") ~= nil
		end)
		if #options == 0 then
			M.report("error", "terrain prompt has no options")
			click(buttonWithText("Cancel"), "Cancel")
			return true
		end
		stats.terrains += 1
		click(options[math.random(1, #options)], "terrain option")
		return true
	end
	-- A picked creature's command buttons (Defend, its Chant): sometimes press one.
	-- Grey chant buttons only explain why they can't be used.
	local commands = findAll(function(d)
		return d.ClassName == "TextButton" and d.Parent and d.Parent:FindFirstChildOfClass("UIGridLayout") ~= nil
			and (string.sub(d.Text, 1, #"🛡") == "🛡" or string.sub(d.Text, 1, #"✨") == "✨")
	end)
	local walking = string.find(text.Text, "walk", 1, true) ~= nil
	if #commands > 0 and math.random() < (walking and 0.12 or 0.45) then
		local b = commands[math.random(1, #commands)]
		if b.TextTransparency > 0.3 then
			stats.greyCommands += 1
		else
			stats.commands += 1
		end
		click(b, "command button")
		return true
	end
	-- A creature that can reach the enemy half can hit the hero: sometimes click the hero.
	if string.find(text.Text, "hero", 1, true) and math.random() < 0.6 then
		stats.heroClicks += 1
		clickPart(boardParts.HeroGlow_Far)
		return true
	end
	local tiles = glowingTiles()
	if #tiles == 0 then
		M.report("error", "prompt with no glowing tiles: " .. text.Text)
		click(buttonWithText("Cancel"), "Cancel")
		return true
	end
	stats.tileClicks += 1
	clickPart(tiles[math.random(1, #tiles)])
	return true
end

local function takeTurnStep()
	if handlePrompt() then
		return
	end
	if not myTurn() then
		return
	end
	local big = find(function(d)
		return d.ClassName == "TextButton" and string.find(d.Text, "READY!") ~= nil
	end)
	if big and math.random() < 0.5 then
		stats.bigMoves += 1
		click(big, "big move")
		return
	end
	local playable = {}
	for _, h in ipairs(handHolders()) do
		if isPlayable(h) then
			table.insert(playable, h)
		end
	end
	local ready = glowingTiles() -- your creatures that can still walk or attack
	local r = math.random()
	if #playable > 0 and r < 0.45 then
		stats.plays += 1
		click(playable[math.random(1, #playable)], "hand card")
	elseif #ready > 0 and r < 0.92 then
		stats.picks += 1
		clickPart(ready[math.random(1, #ready)])
	else
		stats.endTurns += 1
		click(buttonWithText("END TURN"), "END TURN")
	end
end

local function startMatch(deckPrefix, difficulty)
	click(buttonWithText("Duel Table"), "Duel Table")
	M.advance(1.2)
	click(buttonWithText(deckPrefix, true), deckPrefix)
	click(buttonWithText(difficulty), difficulty)
	click(buttonWithText("Sit down and play!"), "Sit down and play!")
	M.advance(2)
	check(buttonWithText("END TURN") ~= nil, "match screen opens (" .. deckPrefix .. ", " .. difficulty .. ")")
	check(Workspace.MenuRoom.Stations.DuelTable:FindFirstChild("BotOpponent") ~= nil, "bot sits at the far chair")
	check(humanoid.SeatPart == Workspace.MenuRoom.Stations.DuelTable.Seat_Near, "player is seated")
end

-- How low the camera went (the seats are about 16 studs up; action shots are much lower).
local camStats = { minY = math.huge, closeSamples = 0, samples = 0, minFov = math.huge }
local function sampleCamera()
	local y = camera.CFrame.Position.Y
	camStats.samples += 1
	camStats.minY = math.min(camStats.minY, y)
	camStats.minFov = math.min(camStats.minFov, camera.FieldOfView)
	if y < 11 then
		camStats.closeSamples += 1
	end
end

local function playToEnd(maxSeconds, idle)
	local endedBefore = ended
	local t = 0
	while ended == endedBefore and t < maxSeconds do
		if not idle then
			takeTurnStep()
		end
		M.advance(0.4)
		sampleCamera()
		t += 0.4
	end
	return ended > endedBefore, t
end

math.randomseed(7)
local games = {
	{ "Sugar Rush", "Easy" },
	{ "Scrap Heap", "Medium" },
	{ "Storm Front", "Hard" },
	{ "Critter Crew", "Hard" },
	{ "Haunted Mall", "Medium" },
	{ "Robo Rumble", "Easy" },
	{ "Starter Deck", "Medium" }, -- your own saved deck (slot 1)
}
for i, g in ipairs(games) do
	startMatch(g[1], g[2])
	if i == 1 then
		local camButton = find(function(d)
			return d.Name == "ActionCamButton"
		end)
		check(camButton ~= nil and camButton.Text == "🎥 Action cam: On", "the action camera starts on")
		if camButton then
			click(camButton, "action cam off")
			check(camButton.Text == "🎥 Action cam: Off", "the action camera button turns it off")
			click(camButton, "action cam on")
			check(camButton.Text == "🎥 Action cam: On", "and back on")
		end
	end
	local done, t = playToEnd(3600, false)
	check(done, string.format("match %d finished and returned to the room (%.0f virtual seconds)", i, t))
	check(labelWithText("DECK WARS") ~= nil, "menu is back after match " .. i)
	check(#Workspace.LiveBoard:GetChildren() == 0, "board cleared after match " .. i)
	check(Workspace.MenuRoom.Stations.DuelTable:FindFirstChild("BotOpponent") == nil, "bot removed after match " .. i)
end
print(string.format("Camera: lowest %.1f studs up, %d of %d samples in an action shot, narrowest zoom %.0f", camStats.minY, camStats.closeSamples, camStats.samples, camStats.minFov))
check(camStats.closeSamples > 0 and camStats.minY < 11, "the action camera moved in close during the matches")

---------------------------------------------------------------------------
-- Scenario 2b: every new command animation plays on a real board without errors
-- (Raise, Gust's bump and push, a guarded block, swaps) even if the random matches above
-- never happened to use them.
---------------------------------------------------------------------------
startMatch("Haunted Mall", "Easy")
do
	click(buttonWithText("⚙ Settings"), "⚙ Settings")
	check(labelWithText("Table speed") ~= nil, "the settings window opens in a match")
	click(buttonWithText("Done"), "Done")
	check(labelWithText("Table speed") == nil, "Done closes the settings window")
end
do
	local mine, theirs, view = nil, nil, nil
	local t = 0
	while t < 900 and not mine do
		takeTurnStep()
		M.advance(0.4)
		t += 0.4
		view = lastUpdate and lastUpdate.view
		if view then
			for _, u in ipairs(view.units) do
				if u.kind == "creature" and u.owner == view.you and not mine then
					-- needs an empty tile next to it for the raised creature
					for dc = -1, 1 do
						for dr = -1, 1 do
							local c, r = u.col + dc, u.row + dr
							if not mine and (dc ~= 0 or dr ~= 0) and c >= 1 and c <= view.cols and r >= 1 and r <= view.rows then
								local taken = false
								for _, o in ipairs(view.units) do
									if o.col == c and o.row == r then
										taken = true
									end
								end
								if not taken then
									mine = { unit = u, free = { col = c, row = r } }
								end
							end
						end
					end
				elseif u.owner ~= view.you then
					theirs = u
				end
			end
		end
	end
	check(mine ~= nil, "found one of your creatures to replay the command animations on")
	if mine then
		-- wait until the screen is idle, then replay the latest real update with extra events
		local w = 0
		while w < 60 and lastUpdate and (labelWithText("Your turn!") == nil) do
			M.advance(0.5)
			w += 0.5
		end
		local u = mine.unit
		local events = {
			{ type = "chant", uid = u.uid, player = view.you, chant = "raise", energy = 0 },
			{ type = "spawn", player = view.you, uid = 987654, card = "skeleton_mascot", col = mine.free.col, row = mine.free.row, hp = 1, raised = true },
			{ type = "defend", uid = u.uid, player = view.you },
			{ type = "blocked", uid = u.uid },
			{ type = "bump", uid = u.uid },
			{ type = "damage", uid = u.uid, amount = 1, hp = math.max(1, u.hp - 1) },
			{ type = "push", uid = 987654, from = mine.free, to = { col = u.col, row = u.row } },
			{ type = "swap", uid = u.uid, other = 987654, player = view.you, from = { col = u.col, row = u.row }, to = mine.free },
			{ type = "guardDown", uid = u.uid },
		}
		if theirs then
			table.insert(events, { type = "chant", uid = u.uid, player = view.you, chant = "gust", target = theirs.uid, energy = 0 })
			table.insert(events, { type = "attack", uid = u.uid, player = view.you, target = theirs.uid, targetPlayer = 3 - view.you, amount = 1, counter = 1, guarded = true })
		end
		-- the raised Skeleton Mascot pops again and just fades away
		table.insert(events, { type = "pop", player = view.you, uid = 987654, col = u.col, row = u.row, faded = true })
		local warningsBefore = M.warnings
		local errorsBefore = M.errors
		local payload = table.clone(lastUpdate)
		payload.events = events
		payload.synthetic = true
		payload.started = nil
		payload.result = nil
		remotes.MatchEvent:FireClient(player, payload)
		M.advance(25)
		check(M.warnings == warningsBefore and M.errors == errorsBefore, "Raise, Defend, Blocked, Bump, Push, Swap, Guard down, aimed chant and fade-away animations play without errors")
		check(labelWithText("Skeleton Mascot fades away for good") ~= nil, "the log says the raised creature faded away")
		local p = camera.CFrame.Position
		local nearSeat = (p - Vector3.new(0, 16, 12)).Magnitude < 0.8 or (p - Vector3.new(0, 15.6, 13.4)).Magnitude < 0.8
		check(nearSeat, string.format("the camera glides back to your seat after the action shots (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z))
		local backsInHand = 0
		for _, h in ipairs(handHolders()) do
			if h:FindFirstChild("CardBack", true) then
				backsInHand += 1
			end
		end
		check(backsInHand == 0, "new hand cards have flipped face up")
		local oppHand = find(function(d)
			return d.Name == "OppHand"
		end)
		local nowView = lastUpdate.view
		local opp = nowView.players[3 - nowView.you]
		check(oppHand ~= nil and #oppHand:GetChildren() == opp.handCount, string.format("the opponent's card backs match its hand (%d backs, %d cards)", oppHand and #oppHand:GetChildren() or -1, opp.handCount))
		if not u.defending then
			-- other creatures may really be defending in this match: each of those keeps its own
			-- hexagon (6 bars), so only the replayed creature's bars must be gone
			local othersDefending = 0
			for _, o in ipairs(lastUpdate.view.units) do
				if o.uid ~= u.uid and o.defending then
					othersDefending += 1
				end
			end
			local bars = 0
			for _, d in ipairs(Workspace.LiveBoard:GetDescendants()) do
				if d.Name == "GuardBar" then
					bars += 1
				end
			end
			check(bars == 6 * othersDefending, string.format("the guard hexagon is gone after Guard down (%d bars left, %d other defenders)", bars, othersDefending))
		end

		-- Scenario 2c: the combo animations (Power, Soak, Zap, Scrap, Upload, Sandwich, Combo,
		-- a spell's cast orb and the heal glow) on the same board.
		local me = view.you
		local free = mine.free
		local combo = {
			{ type = "spawn", player = me, uid = 987655, card = "tin_can_tom", col = free.col, row = free.row },
			{ type = "power", uid = u.uid, amount = 1, power = 1, reason = "sweet" },
			{ type = "soak", uid = u.uid },
			{ type = "damage", uid = u.uid, amount = 3, hp = math.max(1, u.hp - 1), soaked = true, zap = true },
			{ type = "scrap", col = free.col, row = free.row, total = 2, added = 2 },
			{ type = "scrapPick", uid = 987655, amount = 2, from = { { col = free.col, row = free.row, amount = 2 } }, atk = 4, hp = 4 },
			{ type = "upload", from = 424242, to = u.uid, col = free.col, row = free.row },
			{ type = "power", uid = u.uid, amount = 2, power = 3, reason = "upload" },
			{ type = "play", player = me, card = "moth_mailman", cost = 0, combo = true, col = free.col, row = free.row },
			{ type = "play", player = me, card = "water_balloon", cost = 0 },
			{ type = "heal", uid = u.uid, amount = 1, hp = u.hp },
		}
		if theirs then
			table.insert(combo, { type = "attack", uid = u.uid, player = me, target = theirs.uid, targetPlayer = 3 - me, amount = 2, sandwich = 987655 })
		end
		warningsBefore, errorsBefore = M.warnings, M.errors
		local payload2 = table.clone(lastUpdate)
		payload2.view = table.clone(lastUpdate.view)
		payload2.view.scrap = { { col = free.col, row = free.row, n = 2 } } -- a heap stays on the table afterwards
		payload2.events = combo
		payload2.synthetic = true
		payload2.started = nil
		payload2.result = nil
		-- how far a creature's parts are from where they were built (relative to its pivot): 0 at
		-- rest, more while its arms and legs move. nil for models without data.
		local ModelData = makeEnv(shared, clientCache).require(shared:FindFirstChild("CreatureModelData"))
		local function offRest(m)
			local spec = m:IsA("Model") and ModelData[m.Name]
			local root = spec and m.PrimaryPart
			if not root then
				return nil
			end
			local list = {}
			for _, d in ipairs(m:GetChildren()) do
				if d:IsA("BasePart") and d ~= root and d.Name ~= "Base" and d.Name ~= "BaseRing" then
					table.insert(list, d)
				end
			end
			if #list ~= #spec.parts then
				return nil
			end
			-- the model's scale: the middle of how far each part sits from the root against the data
			-- (most parts ride on the body, so a moving arm doesn't throw it off)
			local ratios = {}
			for i, sp in ipairs(spec.parts) do
				local r = math.sqrt(sp[6] ^ 2 + sp[7] ^ 2 + sp[8] ^ 2)
				if r > 0.3 then
					table.insert(ratios, root.CFrame:ToObjectSpace(list[i].CFrame).Position.Magnitude / r)
				end
			end
			if #ratios == 0 then
				return nil
			end
			for _, q in ipairs(ratios) do
				if q ~= q then
					return math.huge, m.Name .. " (scale is NaN)"
				end
			end
			table.sort(ratios)
			local sc = ratios[math.floor(#ratios / 2) + 1]
			local worstErr, at = 0, ""
			for i, sp in ipairs(spec.parts) do
				local off = root.CFrame:ToObjectSpace(list[i].CFrame).Position
				local err = (off - Vector3.new(sp[6], sp[7], sp[8]) * sc).Magnitude
				if err ~= err then
					-- a NaN position counts as flown apart, never as "in place"
					err = math.huge
				end
				if err > worstErr then
					worstErr, at = err, m.Name .. " " .. sp[2]
				end
			end
			return worstErr, at
		end
		local logBefore = labelWithText("Combo! Moth Mailman")
		remotes.MatchEvent:FireClient(player, payload2)
		local maxScrap, sawPower, sawSoak, maxPosed = 0, false, false, 0
		for _ = 1, 120 do
			M.advance(0.25)
			for _, m in ipairs(Workspace.LiveBoard:GetChildren()) do
				local err, at = offRest(m)
				if err and err > maxPosed then
					maxPosed = err
				end
			end
			local n = 0
			for _, d in ipairs(Workspace.LiveBoard:GetDescendants()) do
				if d.Name == "Scrap" then
					n += 1
				elseif d.Name == "Keywords" and d:IsA("TextLabel") then
					if string.find(d.Text, "⚡", 1, true) then
						sawPower = true
					end
					if string.find(d.Text, "💧", 1, true) then
						sawSoak = true
					end
				end
			end
			maxScrap = math.max(maxScrap, n)
		end
		check(M.warnings == warningsBefore and M.errors == errorsBefore, "Power, Soak, Zap, Scrap, Upload, Sandwich, Combo, cast and heal animations play without errors")
		check(maxScrap >= 4, "Scrap heaps show on the tile (" .. maxScrap .. " pieces at most)")
		check(sawPower and sawSoak, "the status line under a creature shows ⚡ Power and 💧 Soaked")
		check(logBefore == nil and labelWithText("Combo! Moth Mailman") ~= nil, "the log calls out the Combo")
		local bases = 0
		for _, m in ipairs(Workspace.LiveBoard:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChild("Base") and m:FindFirstChild("BaseRing") then
				bases += 1
			end
		end
		check(bases > 0, "creatures stand on round bases (" .. bases .. " on the table)")
		-- after all that punching, kicking and flinching, every creature's arms, legs and head are
		-- back exactly where they were built (relative to the model's pivot)
		local checkedModels, worst, worstAt = 0, 0, ""
		for _, m in ipairs(Workspace.LiveBoard:GetChildren()) do
			local err, at = offRest(m)
			if err then
				checkedModels += 1
				if err > worst then
					worst, worstAt = err, at
				end
			end
		end
		check(maxPosed > 0.05 and maxPosed < 10, string.format("creatures move their arms, legs and heads during the fight, without flying apart (parts moved up to %.2f studs)", maxPosed))
		check(checkedModels > 0 and worst < 0.02, string.format("after the fights every creature's limbs are back in place (%d checked, worst %.3f studs at %s)", checkedModels, worst, worstAt))
		local vignette = playerGui:FindFirstChild("DeckWarsVignette")
		check(vignette ~= nil and vignette.Enabled == true, "the dark screen edges are on during a match")
	end
end
click(buttonWithText("Leave"), "Leave")
M.advance(1)

---------------------------------------------------------------------------
-- Scenario 3: leave mid-match
---------------------------------------------------------------------------
startMatch("Sugar Rush", "Medium")
M.advance(5)
click(buttonWithText("Leave"), "Leave")
M.advance(1)
check(labelWithText("DECK WARS") ~= nil, "Leave returns to the room")

---------------------------------------------------------------------------
-- Scenario 4: idle player, the turn timer ends their turns and the match still ends
---------------------------------------------------------------------------
startMatch("Robo Rumble", "Hard")
local done = playToEnd(7200, true)
check(done, "idle match ends through the turn timer")

---------------------------------------------------------------------------
-- Scenario 5: bad data from a cheating client is ignored
---------------------------------------------------------------------------
startMatch("Storm Front", "Easy")
local MatchAction = remotes.MatchAction
local ok = pcall(function()
	MatchAction:FireServer({ kind = "play", handUid = 99999, tile = { col = 7, row = 99 } })
	MatchAction:FireServer("nonsense")
	MatchAction:FireServer({ kind = "play", target = { col = 0 / 0, row = "x", terrain = "Lava" } })
	MatchAction:FireServer({ kind = "move", uid = 1, to = { col = 1e9, row = -5 } })
	MatchAction:FireServer({ kind = "attack", uid = "me", hero = "yes" })
	MatchAction:FireServer({ kind = "bigmove", col = math.huge })
	MatchAction:FireServer({ kind = "brawl" })
	MatchAction:FireServer({ kind = "defend", uid = -5 })
	MatchAction:FireServer({ kind = "defend" })
	MatchAction:FireServer({ kind = "chant", uid = "x", target = { col = 99, row = 0 / 0 } })
	MatchAction:FireServer({ kind = "chant", uid = 3, target = "nope" })
	local MenuAction = remotes.MenuAction
	MenuAction:FireServer("SaveDeck", { slot = "x", deck = { cards = { 1, 2, 3 } } })
	MenuAction:FireServer("SaveDeck", { slot = 2, deck = { name = 5, themes = "Snack", cards = { "jelly_bean_scout", {} }, lanes = 7 } })
	MenuAction:FireServer("SaveDeck", { slot = 0 / 0, deck = {} })
	MenuAction:FireServer("SaveDeck", "nope")
	MenuAction:FireServer("DeleteDeck", { slot = -1 })
	MenuAction:FireServer("GetDecks", { 1, 2 })
end)
M.advance(2)
check(ok, "server survives junk actions")
click(buttonWithText("Leave"), "Leave")
M.advance(1)

print("")
print(string.format("Updates sent: %d, results: %s", updates, table.concat(results, ", ")))
print(string.format("Player actions: %d card clicks, %d creature picks, %d tile clicks, %d hero clicks, %d terrain picks, %d big moves, %d command buttons (%d grey), %d end turns, %d cancels (%d prompts seen)",
	stats.plays, stats.picks, stats.tileClicks, stats.heroClicks, stats.terrains, stats.bigMoves, stats.commands, stats.greyCommands, stats.endTurns, stats.cancels, stats.prompts))
do
	local parts = {}
	for _, k in ipairs({ "play", "move", "swap", "attack", "heroAttack", "defend", "chant", "bigmove", "endturn" }) do
		table.insert(parts, k .. " " .. (sentKinds[k] or 0))
	end
	print("Actions the client sent: " .. table.concat(parts, ", "))
end
do
	local parts = {}
	for _, k in ipairs({ "defend", "guardDown", "blocked", "chant", "swap", "bump", "push", "raised", "heal", "buff" }) do
		table.insert(parts, k .. " " .. (eventKinds[k] or 0))
	end
	print("Command events animated (yours and the bot's): " .. table.concat(parts, ", "))
	parts = {}
	for _, k in ipairs({ "power", "soak", "scrap", "scrapPick", "upload" }) do
		table.insert(parts, k .. " " .. (eventKinds[k] or 0))
	end
	print("Combo events animated (including the replayed ones): " .. table.concat(parts, ", "))
end
check((sentKinds.defend or 0) > 0, "the Defend button sends a defend command")
check((sentKinds.chant or 0) > 0, "chant buttons send chant commands")
print(string.format("Server rejected %d actions (expected for junk / random clicks): %s", #errorsFromServer, table.concat(errorsFromServer, " | ")))
-- Pacing report
do
	local total, count, longest, overlaps, unacked = 0, 0, 0, 0, 0
	for i, u in ipairs(probe.order) do
		local a = probe.acked[u.key]
		if a then
			local d = a - probe.sent[u.key]
			total += d
			count += 1
			longest = math.max(longest, d)
			local nextU = probe.order[i + 1]
			if nextU and nextU.match == u.match and probe.sent[nextU.key] < a - 0.05 then
				overlaps += 1
				print(string.format("  overlap: update %s (%d events) played %.1f s, next update %s (%d events) sent %.1f s before it finished", u.key, u.events, d, nextU.key, nextU.events, a - probe.sent[nextU.key]))
			end
		else
			unacked += 1
		end
	end
	print(string.format("Pacing: %d updates played back, average %.1f s, longest %.1f s; %d sent before the previous one finished; %d never confirmed (match ended or left)", count, count > 0 and total / count or 0, longest, overlaps, unacked))
end
print(string.format("MOCK RESULT: %d errors, %d warnings", M.errors, M.warnings))

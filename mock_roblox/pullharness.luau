-- Plays the Pack Brawl pull cinematic inside the fake Roblox: every tier through the test
-- panel, skip, hold-to-fast-forward, a 10-pull with the card fan, and cleanup checks.
-- Usage (from the repo root): luaurun mock_roblox/pullharness.luau mock_roblox
-- Optional globals: SNAP = 1 prints scene snapshots for preview/brawl.py; SEEDS = n extra
-- direct plays per tier with random cards (default 2).

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
for _, s in ipairs({ Workspace, ReplicatedStorage, ServerScriptService, ServerStorage, Players, TweenService, UserInputService, RunService, Debris, StarterGui, Lighting, StarterPlayer, SoundService }) do
	s.Parent = game
end

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
Workspace.CurrentCamera = camera
camera.CameraType = Enum.CameraType.Custom
camera.FieldOfView = 70

-- a small Duel Table in the room, which biome pulls copy as their ring
do
	local room = Instance.new("Model")
	room.Name = "MenuRoom"
	local stations = Instance.new("Folder")
	stations.Name = "Stations"
	stations.Parent = room
	local duel = Instance.new("Model")
	duel.Name = "DuelTable"
	duel.Parent = stations
	local function p(name, size, pos)
		local x = Instance.new("Part")
		x.Name = name
		x.Anchored = true
		x.Size = size
		x.CFrame = CFrame.new(pos)
		x.Parent = duel
		return x
	end
	p("TableTop", Vector3.new(25, 1.2, 22), Vector3.new(0, 3.4, 0))
	p("Felt", Vector3.new(23.4, 0.1, 20.4), Vector3.new(0, 4.05, 0))
	p("Rim", Vector3.new(25, 0.4, 0.6), Vector3.new(0, 4.1, 11))
	for c = 1, 4 do
		for r = 1, 6 do
			p("Tile_" .. c .. "_" .. r, Vector3.new(2.5, 0.2, 2.3), Vector3.new(-3.9 + (c - 1) * 2.6, 4.32, -6 + (r - 1) * 2.4))
		end
	end
	p("Leg", Vector3.new(1, 2.8, 1), Vector3.new(11, 1.4, 9))
	p("ChairBase", Vector3.new(4, 1, 4), Vector3.new(0, 1, 14))
	local seat = Instance.new("Seat")
	seat.Name = "Seat_Near"
	seat.Anchored = true
	seat.Parent = duel
	room.Parent = Workspace
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
for _, n in ipairs({ "CardData", "MatchEngine", "BotBrain", "Rng", "StarterDecks", "CreatureModelData", "CreatureBuilder", "Settings", "Juice", "ShopCatalog", "Backdrops" }) do
	moduleFrom(SRC .. "shared/" .. n .. ".luau", n, shared)
end
local pb = Instance.new("Folder")
pb.Name = "PackBrawl"
pb.Parent = ReplicatedStorage
for _, n in ipairs({ "Kit", "PullRates", "Casting", "Scripts", "Rig", "Moves", "Arena", "Fighters", "CamRig", "Fx", "Sfx", "Poses", "Director", "Reveal", "PackTease", "Packs", "PackShelf", "PackParty", "BiomeFx", "BiomeStage" }) do
	moduleFrom(SRC .. "packbrawl/" .. n .. ".luau", n, pb)
end
local remotes = Instance.new("Folder")
remotes.Name = "PullRemotes"
remotes.Parent = ReplicatedStorage
for _, n in ipairs({ "PullRequest", "PullResult" }) do
	local r = Instance.new("RemoteEvent")
	r.Name = n
	r.Parent = remotes
end
-- sound templates, all with an id so the sound path is exercised
local sounds = Instance.new("Folder")
sounds.Name = "PackBrawlSounds"
sounds.Parent = SoundService
local SfxNames = { "rip", "pop", "bonk", "slap", "thud", "heavy", "land", "burrow", "twang", "whoosh", "whistle", "crater", "beam", "tick", "boom", "wind", "choir", "charge", "glass", "heartbeat", "fakesting", "brawl", "theme", "sting_Common", "sting_Rare", "sting_Epic", "sting_Mythic", "sting_Legendary", "sting_Secret" }
for _, n in ipairs(SfxNames) do
	local s = Instance.new("Sound")
	s.Name = n
	s.SoundId = "rbxassetid://1"
	s.Volume = 0.6
	s.PlaybackSpeed = 1
	s.Parent = sounds
end
-- a Lighting post effect from the place, which the cinematic must switch off and back on
local placeBloom = Instance.new("BloomEffect")
placeBloom.Name = "PlaceBloom"
placeBloom.Enabled = true
placeBloom.Parent = Lighting
Lighting.ClockTime = 20
Lighting.Brightness = 1

local player = M.new("Player", true)
player.Name = "Nash"
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
local controlsOn = true
M.rec(pm).mockValue = {
	GetControls = function()
		return {
			Disable = function()
				controlsOn = false
			end,
			Enable = function()
				controlsOn = true
			end,
		}
	end,
}
pm.Parent = playerScripts

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
serverScript.Name = "PullServer"
serverScript.Parent = ServerScriptService
local clientScript = Instance.new("LocalScript")
clientScript.Name = "PackBrawlClient"
clientScript.Parent = playerScripts

M.onFrame = function()
	RunService.RenderStepped:Fire(1 / 30)
	RunService.Heartbeat:Fire(1 / 30)
end

runScript(SRC .. "pullserver/PullServer.server.luau", serverScript, serverCache)
runScript(SRC .. "pullclient/PackBrawlClient.client.luau", clientScript, clientCache)
M.advance(1)

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
local function button(name)
	return findIn(playerGui, function(d)
		return d.ClassName == "TextButton" and d.Name == name
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
	M.advance(0.05)
end

-- Server results, to know which card came out
local lastResult
remotes.PullResult.OnClientEvent:Connect(function(r)
	lastResult = r
end)

---------------------------------------------------------------------------
-- Snapshots for the preview renderer
---------------------------------------------------------------------------
local SNAPSHOT = rawget(_G, "SNAP") == 1
local function cfParts(cf)
	local p = rawget(cf, "_p")
	local r = rawget(cf, "_r")
	return string.format("%.3f|%.3f|%.3f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f", p.X, p.Y, p.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end
local function snapshot(name)
	if not SNAPSHOT then
		return
	end
	local scene = Workspace:FindFirstChild("PackBrawlScene")
	if not scene then
		return
	end
	print("SNAP|" .. name)
	for _, d in ipairs(scene:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.98 then
			local shape = "B"
			if d.ClassName == "WedgePart" then
				shape = "W"
			elseif d:FindFirstChildOfClass("SpecialMesh") then
				shape = "E"
			elseif d.Shape == Enum.PartType.Ball then
				shape = "S"
			elseif d.Shape == Enum.PartType.Cylinder then
				shape = "C"
			end
			local c = d.Color
			print(string.format("PART|%s|%s|%.3f|%.3f|%.3f|%d|%d|%d|%.2f|%s", shape, cfParts(d.CFrame), d.Size.X, d.Size.Y, d.Size.Z, math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), d.Transparency, d.Material.Name))
		end
	end
	print(string.format("CAM|%s|%.2f", cfParts(camera.CFrame), camera.FieldOfView))
	local gui = playerGui:FindFirstChild("PackBrawlGui")
	if gui then
		for _, n in ipairs({ "Flash", "Black" }) do
			local f = gui:FindFirstChild(n)
			if f and f.BackgroundTransparency < 1 then
				local c = f.BackgroundColor3
				print(string.format("OVER|%d|%d|%d|%.2f", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255), 1 - f.BackgroundTransparency))
			end
		end
	end
	print("END")
end

---------------------------------------------------------------------------
-- Plays one pull through the panel and checks everything around it
---------------------------------------------------------------------------
local CardData = require("CardData")
local Scripts = require("Scripts")
local Casting = require("Casting")

local STEP = 1 / 30 + 1e-7 -- exactly one frame per step
local function waitFor(pred, maxT)
	local t = 0
	while not pred() and t < maxT do
		M.advance(STEP)
		t += STEP
	end
	return pred(), t
end

local function scene()
	return Workspace:FindFirstChild("PackBrawlScene")
end

local function playThrough(label, startFn, opts)
	opts = opts or {}
	local errors0 = M.errors
	local sounds0 = M.soundsPlayed or 0
	lastResult = nil
	M.advance(1.6) -- server cooldown
	startFn()
	-- the Pack Tease: tap the pack open (or wait and let it open by itself)
	local tease = waitFor(function()
		return playerGui:FindFirstChild("PackTease") ~= nil
	end, 2)
	check(tease, label .. ": the pack rises up to be tapped open")
	if tease then
		local g = playerGui:FindFirstChild("PackTease")
		check(scene() == nil, label .. ": the brawl waits for the pack")
		M.advance(0.6)
		if opts.autoOpen then
			local opened = waitFor(function()
				return playerGui:FindFirstChild("PackTease") == nil
			end, 9)
			check(opened, label .. ": an untouched pack opens by itself")
		else
			for _ = 1, 3 do
				if g.Parent then
					click(g:FindFirstChild("TapPack"), "tap the pack")
					M.advance(0.3)
				end
			end
			local tierShown = g:FindFirstChild("Tease") and g.Tease.Text or ""
			local real = lastResult and CardData.get(lastResult.cards[lastResult.best]).rarity
			local shownTier = string.match(tierShown, "^(%a+) OR BETTER$")
			local order = { COMMON = 1, RARE = 2, EPIC = 3, MYTHIC = 4, LEGENDARY = 5, SECRET = 6 }
			local realIdx = order[string.upper(real or "COMMON")]
			check(shownTier == nil or order[shownTier] <= realIdx, label .. ": the tease (" .. tierShown .. ") never promises more than the real pull (" .. tostring(real) .. ")")
			check(realIdx < 4 or (shownTier ~= nil and order[shownTier] == realIdx - 1), label .. ": Mythic and up tease one step short, so the brawl still surprises")
			check(g:FindFirstChild("Crack", true) ~= nil, label .. ": taps crack the pack")
		end
		waitFor(function()
			return scene() ~= nil
		end, 3)
		check(playerGui:FindFirstChild("PackTease") == nil or scene() ~= nil, label .. ": the pack flies into the ring")
	end
	if opts.afterTease then
		opts.afterTease()
	end
	local started = waitFor(function()
		return scene() ~= nil
	end, 2)
	check(started, label .. ": the Brawl Box scene appears")
	if not started then
		return
	end
	check(camera.CameraType == Enum.CameraType.Scriptable, label .. ": camera is scripted during the brawl")
	check(not controlsOn, label .. ": player controls are off during the brawl")
	check(placeBloom.Enabled == false, label .. ": the place's own bloom is switched off during the brawl")
	local id = lastResult and lastResult.cards[lastResult.best]
	local cast = Casting.build(id, lastResult.seed)
	local brawl = Scripts.build(cast)
	local fighters = #scene():GetChildren()
	local t0 = M.now()
	if opts.whileRunning then
		opts.whileRunning(brawl)
	end
	local snapAt = opts.snaps or {}
	local snapIndex = 1
	local revealed, took = waitFor(function()
		local el = M.now() - t0
		if snapAt[snapIndex] and el >= snapAt[snapIndex] then
			snapshot(string.format("%s_%05.2f", label, el))
			snapIndex += 1
		end
		return playerGui:FindFirstChild("PackBrawlReveal") ~= nil
	end, 40)
	local elapsed = M.now() - t0
	check(revealed, string.format("%s: %s (%s%s) plays and reaches the card reveal after %.2f s (script %.2f s)", label, id, cast.tier, cast.fakeOut and ", fake ending" or "", elapsed, brawl.length))
	if opts.expect then
		check(opts.expect(elapsed, brawl), label .. ": timing is as expected")
	end
	check(scene() == nil and playerGui:FindFirstChild("PackBrawlGui") == nil, label .. ": scene and cinematic GUI are cleaned up")
	check(camera.CameraType == Enum.CameraType.Custom and camera.FieldOfView == 70, label .. ": camera is given back")
	check(controlsOn and placeBloom.Enabled and Lighting.ClockTime == 20 and camera:FindFirstChild("PackBrawlGrade") == nil, label .. ": controls, lighting and post effects are restored")
	check(SoundService:FindFirstChild("PackBrawl") == nil, label .. ": sounds are cleaned up")
	if not opts.skipSoundCheck then
		check((M.soundsPlayed or 0) > sounds0, label .. ": sounds played")
	end
	-- the reveal: tap too early does nothing, then tap to continue
	local reveal = playerGui:FindFirstChild("PackBrawlReveal")
	if reveal then
		local def = CardData.get(id)
		local stageF = reveal:FindFirstChild("Stage")
		check(stageF ~= nil and stageF:FindFirstChild("Pack") ~= nil, label .. ": the reveal starts with the pack")
		local ripped = waitFor(function()
			return reveal:FindFirstChild("RipLight", true) ~= nil
		end, 2)
		check(ripped, label .. ": the pack rips open with light pouring out")
		local stats = stageF and stageF:FindFirstChild("StatCard")
		if opts.watchReveal then
			local hint = reveal:FindFirstChild("Hint")
			local settled = waitFor(function()
				return hint.TextTransparency < 0.5
			end, 6)
			check(settled, label .. ": left alone, the reveal ends on the stat card with 'Tap to continue'")
			check(stageF:FindFirstChild("Pack") == nil, label .. ": the empty pack has fallen away")
		else
			click(reveal:FindFirstChild("Tap"), "Tap")
			check(playerGui:FindFirstChild("PackBrawlReveal") ~= nil, label .. ": an early tap jumps to the stat card, it doesn't close the reveal")
			M.advance(0.3)
		end
		local front = reveal:FindFirstChild("Front", true)
		check(front and front.Visible, label .. ": the card has flipped face up")
		check(stats and stats.Position.X.Scale < 0.9, label .. ": the stat card is on screen")
		local atkRow = stats and stats:FindFirstChild("Attack")
		local costRow = stats and stats:FindFirstChild("Cost")
		check(costRow and costRow.Value.Text == tostring(def.cost), label .. ": the stat card shows the cost (" .. tostring(costRow and costRow.Value.Text) .. ")")
		if def.type == "Creature" then
			check(atkRow and atkRow.Value.Text == tostring(def.atk), label .. ": the stat card shows the attack (" .. tostring(atkRow and atkRow.Value.Text) .. ")")
		else
			check(atkRow == nil, label .. ": no attack bar for a " .. def.type)
		end
		M.advance(1)
		click(reveal:FindFirstChild("Tap"), "Tap")
		M.advance(1)
		check(playerGui:FindFirstChild("PackBrawlReveal") == nil, label .. ": tapping closes the card reveal")
		if opts.fan then
			local fan = playerGui:FindFirstChild("PackBrawlFan")
			check(fan ~= nil, label .. ": the 10-card fan appears")
			if fan then
				click(button("RevealAll"), "Reveal all")
				M.advance(1.5)
				local fronts = 0
				for _, d in ipairs(fan:GetDescendants()) do
					if d.Name == "Front" and d:IsA("GuiObject") and d.Visible then
						fronts += 1
					end
				end
				check(fronts == 10, label .. ": Reveal all flips all 10 cards (" .. fronts .. ")")
				click(button("Done"), "Done")
				M.advance(1)
				check(playerGui:FindFirstChild("PackBrawlFan") == nil, label .. ": the fan closes")
			end
		end
		check(playerGui:FindFirstChild("PackBrawlReveal") == nil, label .. ": the reveal closes and the game is back")
		local panel = playerGui:FindFirstChild("PackPartyTest")
		check(panel and panel.Enabled, label .. ": the test panel is back")
	end
	check(M.errors == errors0, label .. ": no script errors")
	return elapsed, brawl, fighters
end

local TIERS = { "Common", "Rare", "Epic", "Mythic", "Legendary", "Secret" }
local SNAPS = {
	Common = { 0.5, 1.2, 2.6, 3.4 },
	Rare = { 1.3, 2.3, 3.7, 5.0 },
	Epic = { 2.3, 4.1, 5.05, 6.5 },
	Mythic = { 3.9, 5.2, 6.5, 7.1, 8.5 },
	Legendary = { 3.0, 4.5, 6.9, 8.2, 10.5 },
	Secret = { 4.0, 6.5, 8.7, 9.3, 12.0 },
}

-- 1) every tier through the preview buttons, at normal speed
for _, tier in ipairs(TIERS) do
	playThrough(tier, function()
		click(button("Preview_" .. tier), "Preview " .. tier)
	end, {
		snaps = SNAPS[tier],
		expect = function(elapsed, brawl)
			-- hit-stops and slow motion add a little real time
			return elapsed >= brawl.length - 0.1 and elapsed <= brawl.length + 1.5
		end,
	})
end

-- 2) skip: Rare jumps straight to the reveal; Secret jumps to the flash first
playThrough("Skip Rare", function()
	click(button("Preview_Rare"), "Preview Rare")
end, {
	whileRunning = function()
		M.advance(1.0)
		local gui = playerGui:FindFirstChild("PackBrawlGui")
		local skip = gui and gui:FindFirstChild("Skip")
		check(skip and skip.Visible, "Skip button shows after 0.5 s")
		click(skip, "Skip")
	end,
	expect = function(elapsed)
		return elapsed < 1.6
	end,
	skipSoundCheck = true,
})
playThrough("Skip Secret", function()
	click(button("Preview_Secret"), "Preview Secret")
end, {
	whileRunning = function(brawl)
		M.advance(1.0)
		local skip = playerGui:FindFirstChild("PackBrawlGui"):FindFirstChild("Skip")
		click(skip, "Skip")
		-- second skip goes to the reveal
		M.advance(1.0)
		local gui = playerGui:FindFirstChild("PackBrawlGui")
		check(gui ~= nil, "Secret skip lands on the flash, not the reveal")
		if gui then
			click(gui:FindFirstChild("Skip"), "Skip again")
		end
	end,
	expect = function(elapsed)
		return elapsed < 3
	end,
	skipSoundCheck = true,
})

-- 3) hold to fast-forward
local fakeInput = { UserInputType = Enum.UserInputType.MouseButton1, KeyCode = Enum.KeyCode.Q }
playThrough("Fast-forward Legendary", function()
	click(button("Preview_Legendary"), "Preview Legendary")
end, {
	afterTease = function()
		UserInputService.InputBegan:Fire(fakeInput, false)
	end,
	expect = function(elapsed, brawl)
		return elapsed < brawl.length / 3 + 1.2
	end,
})
UserInputService.InputEnded:Fire(fakeInput, false)

-- 4) a 10-pull with the card fan
playThrough("10-pull", function()
	click(button("Open10"), "Open 10")
end, { fan = true })
check(lastResult and #lastResult.cards == 10, "10-pull gives 10 cards")

check(lastResult and lastResult.packId == "brawl" and lastResult.price == 900, "the 10-pull came from the Brawl Pack and cost 900 Gems")
check(player:GetAttribute("Gems") == 100, "Gems after the 10-pull: 1000 - 900 = 100 (" .. tostring(player:GetAttribute("Gems")) .. ")")

-- 5) pick a themed pack and open one (nobody taps the pack: it opens by itself; the reveal plays out)
do
	local PackPartyM = makeEnv(clientScript, clientCache).require(pb:WaitForChild("PackParty"))
	click(button("Dot_spooky"), "the Spooky pack's dot")
	check(PackPartyM.selected() == "spooky", "clicking a dot picks that pack")
	check(findIn(playerGui, function(d)
		return d.Name == "PackName" and d.Text == "Midnight Mall Pack"
	end) ~= nil, "the panel shows the Midnight Mall Pack")
	local rows = 0
	local fam = {}
	for _, d in ipairs(playerGui:GetDescendants()) do
		local cid = string.match(d.Name, "^Row_(.+)$")
		if cid then
			rows += 1
			fam[CardData.get(cid).family] = true
		end
	end
	check(rows > 20 and fam.Spooky and fam.Any and not fam.Snack, "the contents list holds Spooky and shared cards (" .. rows .. " rows), no other family's")
	click(button("NextPack"), "next pack")
	check(PackPartyM.selected() == "robo", "▶ goes to the next pack on the shelf")
	click(button("PrevPack"), "previous pack")
	check(PackPartyM.selected() == "spooky", "◀ goes back")
end
playThrough("Open 1 Spooky", function()
	click(button("Open1"), "Open 1")
end, { autoOpen = true, watchReveal = true })
if lastResult then
	local def = CardData.get(lastResult.cards[1])
	check(lastResult.packId == "spooky", "the pull came from the Spooky pack")
	check(def.family == "Spooky" or def.family == "Any" or def.rarity == "Secret", "a Spooky pack gives a Spooky or shared card (" .. def.name .. ")")
end
check(player:GetAttribute("Gems") == 0, "Gems after Open 1: 0")

-- 5b) out of Gems: the pull is refused, nothing plays, the panel says why
do
	M.advance(1.6)
	local errors0 = M.errors
	click(button("Open1"), "Open 1 with no Gems")
	M.advance(0.5)
	check(playerGui:FindFirstChild("PackTease") == nil and Workspace:FindFirstChild("PackBrawlScene") == nil, "with no Gems nothing opens")
	check(findIn(playerGui, function(d)
		return d.Name == "PackStatus" and string.find(d.Text, "Not enough Gems", 1, true) ~= nil
	end) ~= nil, "the panel says there aren't enough Gems")
	-- a client that skips the check: the server refuses too, and takes nothing
	lastResult = nil
	remotes.PullRequest:FireServer(1, nil, "robo")
	M.advance(0.5)
	check(lastResult and lastResult.error == "gems", "the server refuses a pull it can't charge for")
	check(player:GetAttribute("Gems") == 0, "and the Gems stay at 0")
	-- free rolls and forced tiers are for Studio / developers only: here (AllowTierPreview) they work
	local panel = playerGui:FindFirstChild("PackPartyTest")
	check(panel and panel.Enabled, "the panel stays up after a refused pull")
	check(M.errors == errors0, "refused pulls: no script errors")
end

-- 6) more tiers, so buildings, spells, Secrets and fake endings all get played
local extra = rawget(_G, "SEEDS") or 2
for round = 1, extra do
	for _, tier in ipairs(TIERS) do
		playThrough(tier .. " #" .. (round + 1), function()
			click(button("Preview_" .. tier), "Preview " .. tier)
		end, { skipSoundCheck = true })
	end
end

-- 7) every pullable card plays its full cinematic (all poses, ultimates, buildings and spells)
-- Plays one card's brawl straight through the Director. Also checks that once the
-- winner's victory pose starts, every knocked-out creature is gone from the ring.
local function playDirect(env, id, seed, world)
	local Director = env.require(pb:WaitForChild("Director"))
	local CScripts = env.require(pb:WaitForChild("Scripts"))
	local CCasting = env.require(pb:WaitForChild("Casting"))
	local errors0 = M.errors
	local brawl = CScripts.build(CCasting.build(id, seed))
	brawl.world = world
	local poseT
	for _, c in ipairs(brawl.cues) do
		if c.k == "pose" then
			poseT = c.t
		end
	end
	local done = false
	local d = Director.play(brawl, function()
		done = true
	end)
	local clear = nil
	if poseT then
		waitFor(function()
			return done or d.t >= poseT + 0.1
		end, brawl.length + 3)
		if not done then
			clear = true
			for i, f in ipairs(d.fighters) do
				if i ~= brawl.winner and f.state ~= "gone" then
					clear = false
				end
			end
		end
	end
	local ok = waitFor(function()
		return done
	end, brawl.length + 3)
	local clean = ok and M.errors == errors0 and scene() == nil and camera.CameraType == Enum.CameraType.Custom
	return clean, clear
end

do
	local env = makeEnv(clientScript, clientCache)
	local PullRates = env.require(pb:WaitForChild("PullRates"))
	for _, tier in ipairs(TIERS) do
		local id = PullRates.Pool[tier][1]
		local clean, clear = playDirect(env, id, 77)
		check(clean, tier .. " (" .. id .. "): plays cleanly through the Director")
		check(clear == true, tier .. " (" .. id .. "): only the winner is left in the ring for the victory pose")
	end
end

if rawget(_G, "ALLCARDS") == 1 then
	local env = makeEnv(clientScript, clientCache)
	local PullRates = env.require(pb:WaitForChild("PullRates"))
	local count, bad, crowded = 0, {}, {}
	for _, tier in ipairs(TIERS) do
		for k, id in ipairs(PullRates.Pool[tier]) do
			local clean, clear = playDirect(env, id, 1000 + k * 37)
			if not clean then
				table.insert(bad, id)
			end
			if clear ~= true then
				table.insert(crowded, id)
			end
			count += 1
		end
	end
	check(#bad == 0, string.format("every pullable card plays its whole brawl cleanly (%d cards; problems: %s)", count, table.concat(bad, ", ")))
	check(#crowded == 0, string.format("every pullable card's victory pose has the ring to itself (%d cards; crowded: %s)", count, table.concat(crowded, ", ")))
end


-- 7b) biome pulls: every world with every tier, on the Duel Table copy inside that world; the
-- world escalates, the table rises, and afterwards the sky, fog and light are back as they were
do
	local env = makeEnv(clientScript, clientCache)
	local PullRates = env.require(pb:WaitForChild("PullRates"))
	local BiomeFx = env.require(pb:WaitForChild("BiomeFx"))
	local BiomeStage = env.require(pb:WaitForChild("BiomeStage"))
	check(BiomeStage.available(), "the biome stage finds the match worlds")
	local sky0 = Lighting:FindFirstChildOfClass("Sky")
	local ambient0, bright0 = Lighting.Ambient, Lighting.Brightness
	for wi, world in ipairs(BiomeFx.Worlds) do
		for _, tier in ipairs(TIERS) do
			local id = PullRates.Pool[tier][1 + (wi % #PullRates.Pool[tier])]
			local seen = { level = 0, sank = false, stage = false }
			local conn = RunService.Heartbeat:Connect(function()
				local sc = scene()
				local st = sc and sc:FindFirstChild("BiomeStage")
				if st then
					seen.stage = true
					if st:FindFirstChild("SkyEye") then
						seen.level = math.max(seen.level, 4)
					elseif st:FindFirstChild("LandmarkPillar") then
						seen.level = math.max(seen.level, 3)
					end
					local col = st:FindFirstChild("PodiumColumn")
					if col and col.Transparency == 0 then
						seen.sank = true
					end
				end
			end)
			local clean, clear = playDirect(env, id, 500 + wi, world)
			conn:Disconnect()
			local wantLevel = math.min(PullRates.Rank[tier] - 1, 4)
			local skyBack = Lighting:FindFirstChild("BiomeStageSky") == nil and Lighting:FindFirstChild("BiomeStageAtmosphere") == nil and Lighting:FindFirstChildOfClass("Sky") == sky0
			local lightBack = Lighting.Ambient == ambient0 and Lighting.Brightness == bright0
			check(clean and seen.stage, string.format("%s %s (%s): plays on the table inside the world and cleans up", world, tier, id))
			check(clear == true and seen.sank, string.format("%s %s: only the winner is left, and the table rises", world, tier))
			check(wantLevel < 3 or seen.level >= wantLevel, string.format("%s %s: the world reaches level %d (saw %d)", world, tier, wantLevel, seen.level))
			check(skyBack and lightBack, string.format("%s %s: sky, fog and light are put back", world, tier))
		end
	end
end

-- 8) with the real EconomyManager (the economy update) in ServerStorage: the pull server pays
-- with it, saves the cards in it and uses its Luck charges
do
	local errors0 = M.errors
	local econ = Instance.new("Folder")
	econ.Name = "DeckWarsServer"
	econ.Parent = ServerStorage
	for _, n in ipairs({ "ProfileStore", "EconomyManager", "DevAccess" }) do
		moduleFrom(SRC .. "econ/" .. n .. ".luau", n, econ)
	end
	local senv = makeEnv(serverScript, serverCache)
	local EM = senv.require(econ.EconomyManager)
	EM.init({ memoryOnly = true })
	EM.load(player)
	local start = EM.getBalance(player, "Gems")
	check(player:GetAttribute("Gems") == start and start > 0, "the EconomyManager's Gems show on the player (" .. tostring(start) .. ")")
	local PackPartyM = makeEnv(clientScript, clientCache).require(pb:WaitForChild("PackParty"))
	PackPartyM.select("robo")
	M.advance(1.6)
	lastResult = nil
	remotes.PullRequest:FireServer(1, nil, "robo")
	M.advance(0.3)
	check(lastResult and lastResult.packId == "robo" and lastResult.error == nil, "a paid Overclock pull goes through the EconomyManager")
	-- (the result is playing as a cinematic now; let it finish)
	waitFor(function()
		return playerGui:FindFirstChild("PackBrawlReveal") ~= nil
	end, 40)
	local rv = playerGui:FindFirstChild("PackBrawlReveal")
	if rv then
		click(rv:FindFirstChild("Tap"), "Tap")
		M.advance(0.5)
		click(rv:FindFirstChild("Tap"), "Tap")
		M.advance(1)
	end
	check(EM.getBalance(player, "Gems") == start - 100, "100 Gems were spent from the save")
	check(player:GetAttribute("Gems") == start - 100, "and the player's Gems show it")
	local card = lastResult and lastResult.cards[1]
	check(card and EM.ownsCard(player, card) >= 1, "the pulled card is in the saved collection (" .. tostring(card) .. ")")
	check(lastResult and lastResult.isNew[1] == true and lastResult.uniqueOwned == 1, "it is marked NEW (first card owned)")
	-- a Luck charge is used by a paid pull
	EM.devLuck(player, 1)
	M.advance(1.6)
	lastResult = nil
	remotes.PullRequest:FireServer(1, nil, "snack")
	M.advance(0.3)
	check(lastResult and lastResult.error == nil and EM.takePullLuck(player) == 1, "a paid pull uses up the Luck charge")
	waitFor(function()
		return playerGui:FindFirstChild("PackBrawlReveal") ~= nil
	end, 40)
	rv = playerGui:FindFirstChild("PackBrawlReveal")
	if rv then
		click(rv:FindFirstChild("Tap"), "Tap")
		M.advance(0.5)
		click(rv:FindFirstChild("Tap"), "Tap")
		M.advance(1)
	end
	check(M.errors == errors0, "EconomyManager pulls: no script errors")
end

local played = {}
for _, n in ipairs(M.soundLog or {}) do
	played[n] = true
end
local missing = {}
for _, n in ipairs(SfxNames) do
	if not played[n] then
		table.insert(missing, n)
	end
end
print("Sounds never played in this run: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
print(string.format("MOCK RESULT: %d errors, %d warnings", M.errors, M.warnings))

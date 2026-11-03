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
for _, s in ipairs({ Workspace, ReplicatedStorage, ServerScriptService, Players, TweenService, UserInputService, RunService, Debris, StarterGui, Lighting, StarterPlayer, SoundService }) do
	s.Parent = game
end

local camera = Instance.new("Camera")
camera.Name = "Camera"
camera.Parent = Workspace
Workspace.CurrentCamera = camera
camera.CameraType = Enum.CameraType.Custom
camera.FieldOfView = 70

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
for _, n in ipairs({ "CardData", "MatchEngine", "BotBrain", "Rng", "StarterDecks", "CreatureModelData", "CreatureBuilder" }) do
	moduleFrom(SRC .. "shared/" .. n .. ".luau", n, shared)
end
local pb = Instance.new("Folder")
pb.Name = "PackBrawl"
pb.Parent = ReplicatedStorage
for _, n in ipairs({ "Kit", "PullRates", "Casting", "Scripts", "Rig", "Moves", "Arena", "Fighters", "CamRig", "Fx", "Sfx", "Poses", "Director", "Reveal", "PackParty" }) do
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
		click(reveal:FindFirstChild("Tap"), "Tap")
		check(playerGui:FindFirstChild("PackBrawlReveal") ~= nil, label .. ": an early tap does not skip the card")
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
	UserInputService.InputBegan:Fire(fakeInput, false)
end, {
	expect = function(elapsed, brawl)
		return elapsed < brawl.length / 3 + 1.2
	end,
})
UserInputService.InputEnded:Fire(fakeInput, false)

-- 4) a 10-pull with the card fan
playThrough("10-pull", function()
	click(button("Open 10 packs") or findIn(playerGui, function(d)
		return d.ClassName == "TextButton" and d.Text == "Open 10 packs"
	end), "Open 10")
end, { fan = true })
check(lastResult and #lastResult.cards == 10, "10-pull gives 10 cards")

-- 5) a single random pull
playThrough("Open 1", function()
	click(findIn(playerGui, function(d)
		return d.ClassName == "TextButton" and d.Text == "Open 1 pack"
	end), "Open 1")
end)

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
local function playDirect(env, id, seed)
	local Director = env.require(pb:WaitForChild("Director"))
	local CScripts = env.require(pb:WaitForChild("Scripts"))
	local CCasting = env.require(pb:WaitForChild("Casting"))
	local errors0 = M.errors
	local brawl = CScripts.build(CCasting.build(id, seed))
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

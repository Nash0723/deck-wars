-- Sound effects for pulls: the pack-opening fight (PullCinematic) and the reveal card
-- (DeckWarsClient). Client only.
--
-- Every clip is a free Creator Store sound. Most come from the two licensed libraries Roblox
-- hosts (Pro Sound Effects and APM Music); the few community uploads are marked. Swap an id
-- here and every cue that uses it follows.
--
-- `volume` evens out how loud each clip was recorded (levels were measured in Studio with an
-- AudioAnalyzer), so quiet and loud recordings sit together at volume 1.
-- `from` skips the silence at the start of a clip, so its hit lands on the cue.
-- `length` is the clip's length, for the risers that have to stop dead on a beat.
-- `minor` sounds are dropped while the player holds to fast-forward, so it doesn't turn to mush.

local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local TableSounds = {}

TableSounds.List = {
	-- Hits
	punch = { id = 7468131335, volume = 0.7 }, -- cartoon punch (community upload)
	punch2 = { id = 2758722672, volume = 0.9, from = 0.25 }, -- cartoon punch (community upload)
	heavy = { id = 82235785832022, volume = 0.55 }, -- heavy punch (community upload)
	bonk = { id = 9125745977, volume = 1.4 }, -- Pro Sound Effects: bonk
	bonk2 = { id = 132937320140224, volume = 1.3 }, -- cartoon bonk (community upload)
	thud = { id = 9113480915, volume = 1.4 }, -- Pro Sound Effects: body fall thud
	thudSmall = { id = 9113480917, volume = 2.2 }, -- Pro Sound Effects: body fall thud (short)
	slam = { id = 9113525391, volume = 1.3 }, -- Pro Sound Effects: body impact
	splash = { id = 140727221118804, volume = 0.9 }, -- cartoon splash (community upload)
	boom = { id = 138533090376585, volume = 0.8 }, -- explosion (community upload)
	glass = { id = 9114615010, volume = 1.2, from = 0.28 }, -- Pro Sound Effects: glass smash
	strike = { id = 2892927523, volume = 1.6 }, -- bowling roll and strike (community upload)
	pins = { id = 4692687595, volume = 1.6, from = 0.1 }, -- bowling strike (community upload)

	-- Movement
	whoosh = { id = 9126229255, volume = 0.4 }, -- Pro Sound Effects: whoosh
	whooshShort = { id = 9120972321, volume = 1.4, minor = true }, -- Pro Sound Effects: whoosh
	swish = { id = 9116403294, volume = 2.0, minor = true }, -- Pro Sound Effects: magic swish
	swishLong = { id = 9116400811, volume = 1.6 }, -- Pro Sound Effects: magic swish
	zip = { id = 127438224839678, volume = 0.7 }, -- cartoon whoosh (community upload)
	rise = { id = 9125805579, volume = 1.5 }, -- Pro Sound Effects: rising whoosh (peaks at 0.78 s)
	fall = { id = 9119198140, volume = 5 }, -- Pro Sound Effects: slide whistle, falling
	boing = { id = 6075441854, volume = 1.0 }, -- boing, rising (community upload)
	boing2 = { id = 2772396665, volume = 0.9 }, -- boing (community upload)

	-- Energy
	zap = { id = 9114277757, volume = 2.0, minor = true }, -- Pro Sound Effects: electric zap
	zapBig = { id = 9114277402, volume = 1.5, from = 0.13 }, -- Pro Sound Effects: electric zap
	charge = { id = 9125974435, volume = 3.5 }, -- Pro Sound Effects: energy charge-up
	riserMetal = { id = 1837834352, volume = 0.8, length = 4.0 }, -- APM: reverse build, hard stop
	riserNoise = { id = 1837834264, volume = 0.8, length = 4.0 }, -- APM: reverse build, hard stop
	gong = { id = 9125585534, volume = 0.8 }, -- Pro Sound Effects: gong
	metalSting = { id = 9126006776, volume = 5, from = 0.45 }, -- Pro Sound Effects: booming metal sting
	scratch = { id = 112792997660073, volume = 0.9, from = 0.22 }, -- record scratch (community upload)

	-- Crowd and sparkle
	crowdBed = { id = 9120974700, volume = 0.45, from = 0.6, loop = NumberRange.new(0.6, 4.0) }, -- Pro Sound Effects: wrestling crowd
	cheer = { id = 9120974365, volume = 1.0, from = 0.5 }, -- Pro Sound Effects: wrestling crowd surge
	cheerBig = { id = 9120974507, volume = 1.1, from = 0.5 }, -- Pro Sound Effects: wrestling crowd surge
	horn = { id = 9114402205, volume = 1.1, from = 0.1 }, -- Pro Sound Effects: dual air horns
	ding = { id = 6912794869, volume = 0.8 }, -- glockenspiel (Truss Studios)

	-- Victory stings, one per tier (APM Music)
	sting1 = { id = 9040476898, volume = 0.45 }, -- "Early Bird - Hit1"
	sting2 = { id = 1842122182, volume = 0.45 },
	sting3 = { id = 1839996313, volume = 0.45 }, -- "Feet Do Not Fail Me (sting b)"
	sting4 = { id = 9047102381, volume = 0.5 }, -- "Game Day Warrior Sting 1"
	sting5 = { id = 9047101692, volume = 0.5 }, -- "Bring The Heat Sting 2"
	sting6 = { id = 1844584698, volume = 0.55 }, -- "Winner"
}

-- One master volume for everything here, so the openings can be balanced against the game.
local MASTER_VOLUME = 0.6

local bank = nil -- name -> template Sound, built the first time a sound is needed

local function getBank()
	if bank then
		return bank
	end
	bank = {}
	local folder = Instance.new("Folder")
	folder.Name = "TableSounds"
	local group = Instance.new("SoundGroup")
	group.Name = "Pulls"
	group.Volume = MASTER_VOLUME
	group.Parent = folder
	for name, info in pairs(TableSounds.List) do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = "rbxassetid://" .. info.id
		s.Volume = info.volume or 1
		s.SoundGroup = group
		if info.loop then
			s.Looped = true
			s.PlaybackRegionsEnabled = true
			s.LoopRegion = info.loop
		end
		s.Parent = folder
		bank[name] = s
	end
	folder.Parent = SoundService
	TableSounds.folder = folder
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(folder:GetChildren())
		end)
	end)
	return bank
end

-- Starts loading every clip, so the first opening isn't silent. Safe to call any time.
function TableSounds.preload()
	pcall(getBank)
end

-- A folder for one opening's sounds: destroying it silences them all.
function TableSounds.newFolder(name)
	getBank()
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = TableSounds.folder
	return folder
end

function TableSounds.isMinor(name)
	local info = TableSounds.List[name]
	return info ~= nil and info.minor == true
end

-- Plays a sound once and cleans it up. opts (all optional): volume (times the clip's own),
-- pitch, from (seconds into the clip), parent (defaults to the shared folder).
-- Returns the playing Sound, or nil if the name is unknown.
function TableSounds.play(name, opts)
	local template = getBank()[name]
	if not template then
		warn("[TableSounds] No sound called " .. tostring(name))
		return nil
	end
	opts = opts or {}
	local info = TableSounds.List[name]
	local s = template:Clone()
	s.Volume = template.Volume * (opts.volume or 1)
	s.PlaybackSpeed = opts.pitch or 1
	s.TimePosition = opts.from or info.from or 0
	s.Parent = opts.parent or TableSounds.folder
	s:Play()
	if not s.Looped then
		s.Ended:Once(function()
			s:Destroy()
		end)
		-- Backup, in case Ended never comes (the clip failed to load, say).
		Debris:AddItem(s, (info.length or 8) / math.max(0.2, s.PlaybackSpeed) + 2)
	end
	return s
end

return TableSounds

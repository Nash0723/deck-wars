-- Pack Brawl sound. Each cue plays a Sound template from SoundService.PackBrawlSounds by name.
-- The templates ship with an empty SoundId: upload the files in assets/sounds (our own sounds)
-- or pick Creator Store sounds, and paste each id into the matching Sound's SoundId.
-- A template with no SoundId is simply silent, so the cinematic works before any upload.

local SoundService = game:GetService("SoundService")
local Kit = require(script.Parent:WaitForChild("Kit"))

-- The player's volume settings (ReplicatedStorage.DeckWars.Settings); full volume if it is missing.
local Settings = nil
pcall(function()
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("DeckWars")
	local m = shared and shared:FindFirstChild("Settings")
	if m then
		Settings = require(m)
	end
end)
local function volumeOf(key)
	return Settings and Settings.volume(key) or 1
end

local MUSIC = { brawl = true, theme = true }
local SFX_VOLUME, MUSIC_VOLUME = 0.8, 0.8

local Sfx = {}
Sfx.__index = Sfx

-- Every sound the cinematic asks for (also the list of templates in the place file).
Sfx.Names = {
	"rip", "pop", "bonk", "slap", "thud", "heavy", "land", "burrow", "twang", "whoosh", "whistle",
	"crater", "beam", "tick", "boom", "wind", "choir", "charge", "glass", "heartbeat", "fakesting",
	"brawl", "theme",
	"sting_Common", "sting_Rare", "sting_Epic", "sting_Mythic", "sting_Legendary", "sting_Secret",
}

function Sfx.new(parentForGroup)
	local self = setmetatable({}, Sfx)
	self.templates = SoundService:FindFirstChild("PackBrawlSounds")
	self.group = Kit.make("SoundGroup", { Name = "PackBrawl", Volume = SFX_VOLUME * volumeOf("sfx") }, parentForGroup or SoundService)
	self.musicGroup = Kit.make("SoundGroup", { Name = "PackBrawlMusic", Volume = MUSIC_VOLUME * volumeOf("music") }, parentForGroup or SoundService)
	self.playing = {}
	self.music = nil
	self.speed = 1
	self.muted = false
	return self
end

function Sfx:play(name, volume, startAt)
	if self.muted or not self.templates then
		return nil
	end
	local tpl = self.templates:FindFirstChild(name)
	if not tpl or tpl.SoundId == "" then
		return nil
	end
	local s = tpl:Clone()
	s.SoundGroup = MUSIC[name] and self.musicGroup or self.group
	if volume then
		s.Volume = volume
	end
	s.PlaybackSpeed = tpl.PlaybackSpeed * self.speed
	s.Parent = self.group
	if startAt then
		s.TimePosition = startAt
	end
	s:Play()
	table.insert(self.playing, s)
	-- cleanup of finished one-shots
	if #self.playing > 24 then
		local old = table.remove(self.playing, 1)
		if old ~= self.music then
			old:Destroy()
		end
	end
	return s
end

function Sfx:playMusic(name, startAt)
	self:stopMusic()
	self.music = self:play(name, nil, startAt)
	if self.music then
		self.music.Looped = name == "brawl"
	end
end

function Sfx:stopMusic()
	if self.music then
		self.music:Stop()
		self.music = nil
	end
end

-- Fast-forward plays sounds faster too, so they stay in sync.
function Sfx:setSpeed(x)
	self.speed = x
	for _, s in ipairs(self.playing) do
		if s.Parent then
			local tpl = self.templates and self.templates:FindFirstChild(s.Name)
			s.PlaybackSpeed = (tpl and tpl.PlaybackSpeed or 1) * x
		end
	end
end

-- Hard cut (Mythic time stop, Secret blackout).
function Sfx:cut()
	for _, s in ipairs(self.playing) do
		s:Stop()
	end
end

-- Fades everything out (skip) and cleans up.
function Sfx:fadeOut(dur, fx)
	self.muted = true
	local g, m = self.group, self.musicGroup
	local start, startMusic = g.Volume, m.Volume
	fx:anim(dur, function(a)
		g.Volume = start * (1 - a)
		m.Volume = startMusic * (1 - a)
	end, function()
		self:cut()
	end)
end

function Sfx:destroy()
	self:cut()
	self.group:Destroy()
	self.musicGroup:Destroy()
end

return Sfx

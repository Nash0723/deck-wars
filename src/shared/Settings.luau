-- Player settings: sound volumes, camera, animation speed, Pack Brawl length and graphics.
-- One copy lives on each player's computer (the client script, Pack Brawl's sound and director
-- read it there). The server only checks and saves it (DataStore) so it is the same next visit.
--
--   Settings.get(key)            -> current value
--   Settings.set(key, value)     -> change one value (ignored if not allowed); tells every listener
--   Settings.load(tbl)           -> replace everything with saved values (bad entries become defaults)
--   Settings.reset()             -> back to the defaults
--   Settings.onChanged(fn)       -> fn(key, value, fromLoad) on every change
--   Settings.sanitize(tbl)       -> a clean copy with only known keys and allowed values (server uses it)

local Settings = {}

-- Volumes go 0 to 10. Choices are listed in the order the buttons show them.
Settings.Defaults = {
	sfx = 8, -- sound effects volume
	music = 6, -- music volume
	actionCam = true, -- camera swoops in for attacks, chants and spells
	lean = true, -- with the action camera off, the camera still leans in a little toward fights
	shake = "Full", -- camera shake: Off, Low, Full
	speed = "Normal", -- table animation speed: Slow, Normal, Fast
	packFights = "Full", -- Pack Brawl fights: Full, or Quick (always fast-forwarded)
	graphics = "High", -- High (shadows, glow, lamp shadows) or Low (for slower phones and laptops)
	blur = true, -- soft background blur behind the table
}

Settings.Choices = {
	shake = { "Off", "Low", "Full" },
	speed = { "Slow", "Normal", "Fast" },
	packFights = { "Full", "Quick" },
	graphics = { "High", "Low" },
}

Settings.VolumeMax = 10

-- What the numbers behind some choices are (used by the client).
Settings.ShakeScale = { Off = 0, Low = 0.45, Full = 1 }
Settings.Pace = { Slow = 1.3, Normal = 1.0, Fast = 0.75 } -- multiplies every table animation's length

local function allowed(key, value)
	local default = Settings.Defaults[key]
	if default == nil then
		return false
	end
	if key == "sfx" or key == "music" then
		return type(value) == "number" and value == value and value >= 0 and value <= Settings.VolumeMax and math.floor(value) == value
	end
	if type(default) == "boolean" then
		return type(value) == "boolean"
	end
	local choices = Settings.Choices[key]
	if choices and type(value) == "string" then
		for _, c in ipairs(choices) do
			if c == value then
				return true
			end
		end
	end
	return false
end
Settings.allowed = allowed

function Settings.sanitize(tbl)
	local out = {}
	for key, default in pairs(Settings.Defaults) do
		local v = nil
		if type(tbl) == "table" then
			v = tbl[key] -- (not `and tbl[key] or nil`: that would turn a saved `false` into nil)
		end
		if allowed(key, v) then
			out[key] = v
		else
			out[key] = default
		end
	end
	return out
end

Settings.Values = Settings.sanitize(nil)

local listeners = {}

function Settings.onChanged(fn)
	table.insert(listeners, fn)
end

local function tell(key, value, fromLoad)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, key, value, fromLoad)
		if not ok then
			warn("Settings listener failed: " .. tostring(err))
		end
	end
end

function Settings.get(key)
	return Settings.Values[key]
end

function Settings.set(key, value)
	if not allowed(key, value) or Settings.Values[key] == value then
		return false
	end
	Settings.Values[key] = value
	tell(key, value, false)
	return true
end

function Settings.load(tbl)
	local clean = Settings.sanitize(tbl)
	for key, value in pairs(clean) do
		if Settings.Values[key] ~= value then
			Settings.Values[key] = value
			tell(key, value, true)
		end
	end
end

function Settings.reset()
	for key, value in pairs(Settings.Defaults) do
		Settings.set(key, value)
	end
end

-- 0..1 loudness for a volume setting
function Settings.volume(key)
	return (Settings.Values[key] or 0) / Settings.VolumeMax
end

return Settings

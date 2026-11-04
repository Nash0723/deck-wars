-- ProfileStore: session-locked player saves on one DataStore (the idea behind ProfileService,
-- kept small enough to read). Server only.
--
-- Why session locking: a player can leave one server and join another before the first server
-- has finished saving. Without a lock the new server could load the OLD save, and then both
-- servers write, so Gems get lost or duplicated. Here every save record carries a lock
-- { job = game.JobId, session = unique id, at = os.time() }. A server only writes a record it
-- holds the lock on (checked inside UpdateAsync, so it's atomic), a new server waits for the
-- old one to let go, and a lock that hasn't been refreshed for StaleSeconds (the old server
-- crashed) can be taken over.
--
--   local store = ProfileStore.new(dataStore, { template = {...}, jobId = game.JobId })
--   local profile, why = store:load("u" .. player.UserId)  -- yields; why = "locked" | "error"
--   profile.Data.coins += 10   -- change Data freely
--   profile:save()            -- autosave calls this; returns ok, why ("stolen" | "error")
--   profile:release()         -- on leave: last save + unlock
--   profile:onStolen(fn)      -- another server took the save over: stop using this profile
--
-- Record layout in the DataStore: { data = <your table>, meta = { lock, created, saved, loads } }.
-- Data must be DataStore-safe: strings, finite numbers, booleans, and tables that are either
-- arrays or have only string keys.

local ProfileStore = {}
ProfileStore.__index = ProfileStore

local Profile = {}
Profile.__index = Profile

ProfileStore.StaleSeconds = 240 -- a lock older than this (no save refreshed it) counts as dead
ProfileStore.LoadAttempts = 6 -- tries before giving up on a locked/erroring save
ProfileStore.RetryDelay = 4 -- seconds between tries

local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = deepCopy(x)
	end
	return out
end
ProfileStore.deepCopy = deepCopy

local function isArray(t)
	return type(t) == "table" and (next(t) == nil or t[1] ~= nil)
end

-- Fill in keys the template has and the save doesn't (new fields added in an update).
-- Only goes into dictionaries; arrays and existing values are left alone.
local function reconcile(data, template)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and not isArray(v) and next(v) ~= nil then
			reconcile(data[k], v)
		end
	end
	return data
end
ProfileStore.reconcile = reconcile

local sessionCounter = 0

function ProfileStore.new(dataStore, opts)
	opts = opts or {}
	local self = setmetatable({}, ProfileStore)
	self.store = dataStore
	self.template = opts.template or {}
	self.jobId = opts.jobId or "local"
	self.clock = opts.clock or os.time
	self.wait = opts.wait or (task and task.wait) or function() end
	self.warn = opts.warn or warn
	self.staleSeconds = opts.staleSeconds or ProfileStore.StaleSeconds
	self.loadAttempts = opts.loadAttempts or ProfileStore.LoadAttempts
	self.retryDelay = opts.retryDelay or ProfileStore.RetryDelay
	self.memoryOnly = opts.memoryOnly or false
	self.active = {} -- [key] = profile (loaded in this server and not released yet)
	return self
end

-- A DataStore look-alike that lives only in this server's memory. Used in Studio when the place
-- has no API access (nothing is saved after you stop the test) and by the tests.
function ProfileStore.memoryStore()
	local data = {}
	local store = { data = data, failNext = 0 }
	local function maybeFail()
		if store.failNext > 0 then
			store.failNext -= 1
			error("memory store: simulated DataStore error")
		end
	end
	function store.UpdateAsync(_, key, transform)
		maybeFail()
		local new = transform(deepCopy(data[key]), nil)
		if new ~= nil then
			data[key] = deepCopy(new)
		end
		return deepCopy(new)
	end
	function store.GetAsync(_, key)
		maybeFail()
		return deepCopy(data[key])
	end
	function store.SetAsync(_, key, value)
		maybeFail()
		data[key] = deepCopy(value)
	end
	function store.RemoveAsync(_, key)
		maybeFail()
		local old = data[key]
		data[key] = nil
		return old
	end
	return store
end

local function update(self, key, transform)
	return pcall(function()
		return self.store:UpdateAsync(key, transform)
	end)
end

-- Loads (and locks) the save under `key`. Yields. Returns the profile, or nil and a reason:
-- "locked" (another server still holds it) or "error" (DataStore kept failing).
function ProfileStore:load(key)
	assert(type(key) == "string" and #key > 0, "ProfileStore:load needs a key")
	-- The same player rejoining this same server: wait for the old profile to finish releasing.
	local waited = 0
	while self.active[key] and waited < self.loadAttempts * self.retryDelay do
		self.wait(0.5)
		waited += 0.5
	end
	if self.active[key] then
		return nil, "locked"
	end
	sessionCounter += 1
	local session = string.format("%s:%d:%d", tostring(self.jobId), self.clock(), sessionCounter)
	local lastReason = "error"
	for attempt = 1, self.loadAttempts do
		local outcome, record = nil, nil
		local ok, err = update(self, key, function(old)
			outcome, record = nil, nil
			local now = self.clock()
			local rec
			if type(old) == "table" and type(old.data) == "table" and type(old.meta) == "table" then
				rec = old
			elseif type(old) == "table" and old.data == nil and old.meta == nil then
				-- an older save that was just the data table (or nothing at all)
				rec = { data = (next(old) ~= nil) and old or deepCopy(self.template), meta = { created = now, loads = 0 } }
			else
				rec = { data = deepCopy(self.template), meta = { created = now, loads = 0 } }
			end
			local lock = rec.meta.lock
			if type(lock) == "table" and lock.job ~= self.jobId and type(lock.at) == "number" and now - lock.at < self.staleSeconds then
				outcome = "locked"
				return nil -- don't write: someone else is using this save
			end
			outcome = (type(lock) == "table") and "took" or "ok"
			rec.meta.lock = { job = self.jobId, session = session, at = now }
			rec.meta.loads = (tonumber(rec.meta.loads) or 0) + 1
			record = rec
			return rec
		end)
		if ok and record then
			if outcome == "took" then
				self.warn("ProfileStore: took over a stale save lock for " .. key)
			end
			local profile = setmetatable({
				Key = key,
				Data = reconcile(record.data, self.template),
				Meta = { created = record.meta.created, loads = record.meta.loads },
				_store = self,
				_session = session,
				_active = true,
				_stolen = {},
				_saving = false,
			}, Profile)
			self.active[key] = profile
			return profile
		end
		lastReason = (ok and outcome == "locked") and "locked" or "error"
		if not ok then
			self.warn("ProfileStore: load of " .. key .. " failed (try " .. attempt .. "): " .. tostring(err))
		end
		if attempt < self.loadAttempts then
			self.wait(self.retryDelay)
		end
	end
	return nil, lastReason
end

function Profile:isActive()
	return self._active
end

function Profile:onStolen(fn)
	table.insert(self._stolen, fn)
end

local function markStolen(self)
	if not self._active then
		return
	end
	self._active = false
	local store = self._store
	if store.active[self.Key] == self then
		store.active[self.Key] = nil
	end
	for _, fn in ipairs(self._stolen) do
		task.spawn(fn)
	end
end

-- One write. release = true also unlocks. Returns ok, reason.
local function write(self, release)
	local store = self._store
	local outcome = nil
	local data = self.Data
	local ok, err = update(store, self.Key, function(old)
		outcome = nil
		if type(old) ~= "table" or type(old.meta) ~= "table" or type(old.meta.lock) ~= "table" or old.meta.lock.session ~= self._session then
			outcome = "stolen"
			return nil
		end
		local now = store.clock()
		old.data = data
		old.meta.saved = now
		if release then
			old.meta.lock = nil
		else
			old.meta.lock.at = now
		end
		outcome = "ok"
		return old
	end)
	if not ok then
		store.warn("ProfileStore: save of " .. self.Key .. " failed: " .. tostring(err))
		return false, "error"
	end
	if outcome == "stolen" then
		store.warn("ProfileStore: " .. self.Key .. " was opened by another server; this server stops saving it")
		markStolen(self)
		return false, "stolen"
	end
	return true
end

-- Saves now (also refreshes the lock). Safe to call often; overlapping calls wait their turn.
function Profile:save()
	if not self._active then
		return false, "inactive"
	end
	while self._saving do
		self._store.wait(0.1)
	end
	if not self._active then
		return false, "inactive"
	end
	self._saving = true
	local ok, why = write(self, false)
	self._saving = false
	return ok, why
end

-- Last save and unlock. Tries a few times if the DataStore errors.
function Profile:release()
	if not self._active then
		return false, "inactive"
	end
	while self._saving do
		self._store.wait(0.1)
	end
	if not self._active then
		return false, "inactive"
	end
	self._saving = true
	local ok, why = false, "error"
	for attempt = 1, 3 do
		ok, why = write(self, true)
		if ok or why == "stolen" then
			break
		end
		if attempt < 3 then
			self._store.wait(2)
		end
	end
	self._saving = false
	self._active = false
	local store = self._store
	if store.active[self.Key] == self then
		store.active[self.Key] = nil
	end
	return ok, why
end

-- Saves every active profile (spread out over `spread` seconds). For the autosave loop.
function ProfileStore:saveAll(spread)
	local list = {}
	for _, p in pairs(self.active) do
		table.insert(list, p)
	end
	local gap = (#list > 0 and spread) and spread / #list or 0
	for _, p in ipairs(list) do
		if p._active then
			task.spawn(function()
				p:save()
			end)
		end
		if gap > 0 then
			self.wait(gap)
		end
	end
end

-- Releases every active profile and waits until they're done (for BindToClose).
function ProfileStore:releaseAll(timeout)
	local pending = 0
	for _, p in pairs(self.active) do
		pending += 1
		task.spawn(function()
			p:release()
			pending -= 1
		end)
	end
	local waited = 0
	while pending > 0 and waited < (timeout or 25) do
		self.wait(0.2)
		waited += 0.2
	end
	return pending == 0
end

return ProfileStore

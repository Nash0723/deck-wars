-- Deck Wars rules engine: lanes with two rows.
--
-- Every player (a "seat") owns 4 lanes on their team's side of the table. A 1v1 match has two
-- seats (one per team); a 2v2 match has four, and each team's two players sit side by side,
-- so a team's side is 8 lanes wide and the two teammates share one pool of hit points.
-- Lane i on one side faces lane i on the other side.
--
-- Each lane has two tiles on each side: the Front row (toward the middle of the table) and the
-- Back row behind it, and behind the Back row one building slot.
--   lane.creature = the creature in the Front row, lane.back = the creature in the Back row.
--   unit.row = 1 (Front) or 2 (Back).
--
-- On your turn you get magic, draw a card, then play creatures into your tiles, buildings into
-- your slots and spells, Spark creatures (use their ability; a Sparked creature skips its
-- attack) and Shift creatures between the rows. Pressing BATTLE ends your turn: each Front
-- creature hits the first enemy in its lane (the Front one, else the Back one, else the enemy
-- hero). Back row creatures are the reserve: they don't attack (unless Ranged) and enemy attacks
-- reach them only through an empty Front tile. After your battle, a Back creature whose Front
-- tile is empty steps up into it. A Ranged creature in the Back row shoots the weakest enemy in
-- its lane or the lanes next to it, in either row.
--
-- The server and the bot use this module; nothing here touches Roblox instances, so the tests
-- run it headless. Everything that happens is recorded as events for the screens to animate.
--
--   local m = MatchEngine.new({ setup1, setup2 }, seed)        -- 1v1
--   local m = MatchEngine.new({ s1, s2, s3, s4 }, seed)        -- 2v2: seats 1 and 3 vs 2 and 4
--   setup = { deck = { card ids }, hero = "bonk", family = "Snack", name = "Nash",
--             lanes = { "Snack", "Snack", "Critter", "Critter" } } -- lanes: optional terrains
--   m:act(seat, action) --> true or false, "why not"
--     { kind = "play", handUid, lane, row = 1 | 2, target = { team, lane, row } }
--     { kind = "spark", uid }, { kind = "shift", uid }, { kind = "bigmove", target }, { kind = "battle" }
--   m:listActions(seat), m:viewFor(seat), m:takeEvents()

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local Rng = req("Rng")

local MatchEngine = {}
MatchEngine.__index = MatchEngine

local LANES = CardData.Lanes
local ROWS = CardData.Rows or 2 -- 1 = Front, 2 = Back
local MAX_TURNS = 80 -- safety: after this many turns the team with more hit points wins
local SHIFT_COST = CardData.ShiftCost or 1
local CARRY = CardData.CarryOverkill ~= false

local function card(id)
	return CardData.Cards[id]
end

local function deepCopy(v, seen)
	if type(v) ~= "table" then
		return v
	end
	seen = seen or {}
	if seen[v] then
		return seen[v]
	end
	local out = {}
	seen[v] = out
	for k, x in pairs(v) do
		out[deepCopy(k, seen)] = deepCopy(x, seen)
	end
	return setmetatable(out, getmetatable(v))
end

local function dominantFamily(deck)
	local counts = {}
	for _, id in ipairs(deck) do
		local c = card(id)
		if c and c.family ~= "Any" then
			counts[c.family] = (counts[c.family] or 0) + 1
		end
	end
	local best, n = "Snack", -1
	for _, fam in ipairs(CardData.Families) do
		if (counts[fam] or 0) > n then
			best, n = fam, counts[fam] or 0
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Setting up
---------------------------------------------------------------------------

function MatchEngine.new(setups, seed)
	assert(#setups == 2 or #setups == 4, "A match has 2 or 4 seats")
	local self = setmetatable({}, MatchEngine)
	self.rng = Rng.new(seed)
	self.nextUid = 0
	self.events = {}
	self.silent = false
	self.turn = 0 -- turns taken so far by everyone
	self.current = 1
	self.over = false
	self.winner = nil -- team 1, team 2, or 0 for a draw
	self.teamMode = #setups == 4
	self.order = {}
	self.seats = {}
	self.teams = { { seats = {} }, { seats = {} } }
	for s, setup in ipairs(setups) do
		table.insert(self.order, s)
		local team = (s % 2 == 1) and 1 or 2
		local deck = table.clone(setup.deck)
		self.rng:shuffle(deck)
		table.insert(self.teams[team].seats, s)
		self.seats[s] = {
			team = team,
			slot = #self.teams[team].seats, -- 1st or 2nd player of the team: which 4 lanes they own
			name = setup.name or ("Player " .. s),
			hero = setup.hero or "bonk",
			family = setup.family or dominantFamily(setup.deck),
			deck = deck,
			hand = {},
			discard = {},
			lost = {}, -- creatures that popped, newest last (The Mannequin Duke brings one back)
			fatigue = 0,
			magic = 0,
			maxMagic = 0,
			turns = 0,
			dealt = 0, -- damage dealt to enemies, charges the Big Move
			bigMoveUsed = false,
			played = 0, -- cards played this turn (for Combo)
			terrains = type(setup.lanes) == "table" and table.clone(setup.lanes) or nil, -- the deck's lane terrains
		}
	end
	local hp = self.teamMode and CardData.TeamMaxHp or CardData.HeroMaxHp
	self.width = LANES * #self.teams[1].seats -- lanes on each side
	self.lanes = {}
	for t = 1, 2 do
		self.teams[t].hp = hp
		self.teams[t].maxHp = hp
		self.lanes[t] = {}
		for i = 1, self.width do
			local owner = self.teams[t].seats[math.ceil(i / LANES)]
			local seat = self.seats[owner]
			local k = (i - 1) % LANES + 1
			local land = seat.terrains and seat.terrains[k]
			if not (type(land) == "string" and CardData.Terrains[land]) then
				land = seat.family
			end
			-- creature = the Front row, back = the Back row, building = the slot behind them
			self.lanes[t][i] = { owner = owner, landscape = land, scrap = 0, creature = nil, back = nil, building = nil }
		end
	end
	self:emit({ type = "start", landscapes = self:landscapeCopy() })
	-- Going first is an edge, so the first player starts with FirstHandPenalty cards fewer
	-- (and skips their first draw, see CardData.FirstTurnDraw), and the first player of the
	-- other team gets SecondPlayerCard.
	-- In 2v2 that goes for both players of each team.
	local firstTeam = self.seats[self.order[1]].team
	for _, s in ipairs(self.order) do
		local goesFirst = self.seats[s].team == firstTeam
		local n = CardData.StartHand - (goesFirst and (CardData.FirstHandPenalty or 0) or 0)
		for _ = 1, n do
			self:draw(s)
		end
		if not goesFirst and CardData.SecondPlayerCard then
			self:addToHand(s, CardData.SecondPlayerCard)
		end
	end
	self:startTurn(self.order[1])
	return self
end

-- A copy for the bot to try things on. A seed keeps it from seeing the real dice rolls.
function MatchEngine:clone(seed)
	local events = self.events
	self.events = {}
	local c = deepCopy(self)
	self.events = events
	c.rng = Rng.new(seed or self.rng.state)
	c.silent = true
	return c
end

function MatchEngine:emit(event)
	if not self.silent then
		table.insert(self.events, event)
	end
end

function MatchEngine:takeEvents()
	local e = self.events
	self.events = {}
	return e
end

function MatchEngine:uid()
	self.nextUid += 1
	return self.nextUid
end

function MatchEngine:landscapeCopy()
	local out = {}
	for t = 1, 2 do
		out[t] = {}
		for i = 1, self.width do
			out[t][i] = self.lanes[t][i].landscape
		end
	end
	return out
end

function MatchEngine:enemyTeam(team)
	return 3 - team
end

-- The lanes a seat owns: indices on its team's side.
function MatchEngine:lanesOf(s)
	local seat = self.seats[s]
	local first = (seat.slot - 1) * LANES + 1
	local out = {}
	for i = first, first + LANES - 1 do
		table.insert(out, i)
	end
	return out
end

function MatchEngine:ownsLane(s, lane)
	local seat = self.seats[s]
	local l = self.lanes[seat.team][lane]
	return l ~= nil and l.owner == s
end

function MatchEngine:neighbourLanes(lane)
	local out = {}
	if lane > 1 then
		table.insert(out, lane - 1)
	end
	if lane < self.width then
		table.insert(out, lane + 1)
	end
	return out
end

---------------------------------------------------------------------------
-- Cards in hand
---------------------------------------------------------------------------

function MatchEngine:addToHand(s, id, costMod, costOverride)
	local seat = self.seats[s]
	if #seat.hand >= CardData.MaxHand then
		table.insert(seat.discard, id)
		self:emit({ type = "burn", seat = s, id = id })
		return nil
	end
	local entry = { uid = self:uid(), id = id, costMod = costMod or 0, costOverride = costOverride }
	table.insert(seat.hand, entry)
	self:emit({ type = "draw", seat = s, id = id, uid = entry.uid, cost = costOverride, costMod = costMod })
	return entry
end

function MatchEngine:draw(s)
	local seat = self.seats[s]
	local id = table.remove(seat.deck)
	if not id then
		-- An empty deck hurts more every time.
		seat.fatigue += 1
		self:emit({ type = "fatigue", seat = s, amount = seat.fatigue })
		self:damageTeam(seat.team, seat.fatigue, nil)
		return nil
	end
	return self:addToHand(s, id)
end

function MatchEngine:findHand(s, uid)
	for i, e in ipairs(self.seats[s].hand) do
		if e.uid == uid then
			return e, i
		end
	end
	return nil
end

function MatchEngine:scrapOnSide(team)
	local n = 0
	for _, l in ipairs(self.lanes[team]) do
		n += l.scrap
	end
	return n
end

function MatchEngine:costOf(s, entry)
	if entry.costOverride then
		return entry.costOverride
	end
	local c = card(entry.id)
	local cost = c.cost + (entry.costMod or 0)
	if entry.id == "scrapheap_titan" then
		cost -= math.min(3, self:scrapOnSide(self.seats[s].team))
	end
	if c.type == "Spell" then
		-- Mall Cop Phantom: enemy spells cost 1 more (each Phantom).
		local enemy = self:enemyTeam(self.seats[s].team)
		for _, o in ipairs(self:allCreatures(enemy)) do
			if o.id == "mall_cop_phantom" then
				cost += 1
			end
		end
	end
	return math.max(0, cost)
end

---------------------------------------------------------------------------
-- Units and tiles
--
-- A tile is (team, lane, row): row 1 is the Front row, row 2 the Back row.
---------------------------------------------------------------------------

local function rowKey(row)
	return row == 2 and "back" or "creature"
end

-- The creature on a tile, or nil.
function MatchEngine:unitAt(team, lane, row)
	local l = self.lanes[team] and self.lanes[team][lane]
	return l and l[rowKey(row)]
end

function MatchEngine:setAt(team, lane, row, u)
	self.lanes[team][lane][rowKey(row)] = u
	if u then
		u.lane = lane
		u.row = row
	end
end

-- The first creature an attack down this lane meets: the Front one, else the Back one.
function MatchEngine:firstIn(team, lane)
	local l = self.lanes[team] and self.lanes[team][lane]
	return l and (l.creature or l.back)
end

-- Both creatures of a lane, Front first.
function MatchEngine:laneCreatures(team, lane)
	local out = {}
	local l = self.lanes[team] and self.lanes[team][lane]
	if l then
		if l.creature then
			table.insert(out, l.creature)
		end
		if l.back then
			table.insert(out, l.back)
		end
	end
	return out
end

function MatchEngine:allCreatures(team)
	local out = {}
	for t = 1, 2 do
		if team == nil or team == t then
			for _, l in ipairs(self.lanes[t]) do
				if l.creature then
					table.insert(out, l.creature)
				end
				if l.back then
					table.insert(out, l.back)
				end
			end
		end
	end
	return out
end

-- A seat's creatures, wherever they stand on its team's side (something may have pushed one
-- into a teammate's lane).
function MatchEngine:creaturesOf(s)
	local out = {}
	for _, u in ipairs(self:allCreatures(self.seats[s].team)) do
		if u.owner == s then
			table.insert(out, u)
		end
	end
	return out
end

function MatchEngine:findUnit(uid)
	for t = 1, 2 do
		for _, l in ipairs(self.lanes[t]) do
			if l.creature and l.creature.uid == uid then
				return l.creature
			end
			if l.back and l.back.uid == uid then
				return l.back
			end
			if l.building and l.building.uid == uid then
				return l.building
			end
		end
	end
	return nil
end

function MatchEngine:laneOf(u)
	return self.lanes[u.team][u.lane]
end

-- Is this creature still standing where it thinks it is?
function MatchEngine:isOnBoard(u)
	return u.kind == "creature" and self:unitAt(u.team, u.lane, u.row) == u
end

-- The enemy creature "across": the first one in the facing lane (Front before Back).
function MatchEngine:across(u)
	return self:firstIn(self:enemyTeam(u.team), u.lane)
end

function MatchEngine:buildingIn(u)
	local l = self:laneOf(u)
	return l and l.building
end

-- The creatures next to it: the same row in the lanes beside it, and the other row of its own lane.
function MatchEngine:neighbours(u)
	local out = {}
	for _, n in ipairs(self:neighbourLanes(u.lane)) do
		local o = self:unitAt(u.team, n, u.row)
		if o then
			table.insert(out, o)
		end
	end
	local o = self:unitAt(u.team, u.lane, u.row == 1 and 2 or 1)
	if o then
		table.insert(out, o)
	end
	return out
end

-- New creatures don't attack in the battle of the turn they arrive, unless they have Zoom.
function MatchEngine:isNew(u)
	return u.playedTurn == self.turn and not self:hasKeyword(u, "Zoom")
end

function MatchEngine:hasKeyword(u, kw)
	local c = card(u.id)
	if c.keywords[kw] or u.given[kw] then
		return true
	end
	local b = self:buildingIn(u)
	if b then
		if kw == "Sturdy" and b.id == "bouncy_castle" then
			return true
		elseif kw == "Splash" and b.id == "wind_turbine" then
			return true
		elseif kw == "Haunt" and b.id == "spooky_crypt" then
			return true
		end
	end
	if kw == "Sturdy" and c.family == "Critter" then
		for _, o in ipairs(self:neighbours(u)) do
			if o.id == "sergeant_snail" then
				return true
			end
		end
	end
	return false
end

function MatchEngine:keywordsOf(u)
	local out = {}
	for _, kw in ipairs(CardData.Keywords) do
		if self:hasKeyword(u, kw) then
			table.insert(out, kw)
		end
	end
	return out
end

function MatchEngine:maxHpOf(u)
	return card(u.id).hp + u.hpBonus
end

function MatchEngine:healthOf(u)
	return self:maxHpOf(u) - u.damage
end

function MatchEngine:isHome(u)
	local c = card(u.id)
	return c.family ~= "Any" and self:laneOf(u).landscape == c.family
end

function MatchEngine:attackOf(u)
	local c = card(u.id)
	local atk = c.atk + u.atkBonus + u.power + u.tempAtk
	if self:isHome(u) then
		atk += CardData.HomeBonus
	end
	if self:hasKeyword(u, "Pack") then
		local pack = 0
		for _, o in ipairs(self:neighbours(u)) do
			if card(o.id).family == "Critter" then
				pack += 1
			end
		end
		atk += math.min(CardData.PackMax, pack)
	end
	local b = self:buildingIn(u)
	if b and b.id == "charging_station" then
		atk += 1
	end
	-- Fog Bank: enemy creatures across and next to it have -2 attack.
	local enemy = self:enemyTeam(u.team)
	for _, lane in ipairs({ u.lane - 1, u.lane, u.lane + 1 }) do
		for _, o in ipairs(self:laneCreatures(enemy, lane)) do
			if o.id == "fog_bank" then
				atk -= 2
			end
		end
	end
	atk -= u.boo
	return math.max(0, atk)
end

-- What the screens show about a creature or building.
function MatchEngine:snapshot(u)
	local c = card(u.id)
	if u.kind == "building" then
		return { uid = u.uid, id = u.id, kind = "building", owner = u.owner, team = u.team, lane = u.lane }
	end
	return {
		uid = u.uid,
		id = u.id,
		kind = "creature",
		owner = u.owner,
		team = u.team,
		lane = u.lane,
		row = u.row,
		atk = self:attackOf(u),
		baseAtk = c.atk,
		hp = self:healthOf(u),
		maxHp = self:maxHpOf(u),
		power = u.power,
		soaked = u.soaked,
		shield = u.shield,
		frozen = u.frozen,
		sparked = u.sparked,
		shifted = u.shifted,
		new = self:isNew(u),
		home = self:isHome(u),
		keywords = self:keywordsOf(u),
		sparkCost = c.sparkCost,
	}
end

function MatchEngine:refresh(u)
	if u and u.kind == "creature" and self:findUnit(u.uid) then
		self:emit({ type = "stats", unit = self:snapshot(u) })
	end
end

-- Every creature's numbers can change when something nearby changes, so after most actions
-- the screens get fresh numbers for all of them.
function MatchEngine:refreshAll()
	for _, u in ipairs(self:allCreatures()) do
		self:emit({ type = "stats", unit = self:snapshot(u) })
	end
end

local function newCreature(self, s, id, lane, row)
	return {
		uid = self:uid(),
		id = id,
		kind = "creature",
		owner = s,
		team = self.seats[s].team,
		lane = lane,
		row = row,
		atkBonus = 0,
		hpBonus = 0,
		damage = 0,
		power = 0,
		tempAtk = 0,
		boo = 0,
		booBy = nil,
		soaked = false,
		shield = false,
		frozen = false,
		sparked = false,
		shifted = false,
		given = {},
		playedTurn = self.turn,
	}
end

-- Which row a creature lands in when the card doesn't say: the Front if it's free, else the Back,
-- else the Front (over the creature there).
function MatchEngine:freeRow(team, lane, wanted)
	if wanted == 1 or wanted == 2 then
		return wanted
	end
	if not self:unitAt(team, lane, 1) then
		return 1
	end
	if not self:unitAt(team, lane, 2) then
		return 2
	end
	return 1
end

-- Puts a creature onto a tile (opts.row; without it, the first free row of the lane). A creature
-- already there goes to the discard pile quietly (you may play over your own creature).
function MatchEngine:spawn(s, lane, id, opts)
	opts = opts or {}
	local team = self.seats[s].team
	local row = self:freeRow(team, lane, opts.row)
	local replaced = nil
	local old = self:unitAt(team, lane, row)
	if old then
		replaced = old.uid
		if not card(old.id).token then
			table.insert(self.seats[old.owner].discard, old.id)
		end
		self:setAt(team, lane, row, nil)
	end
	local u = newCreature(self, s, id, lane, row)
	if opts.damage then
		u.damage = opts.damage
	end
	self:setAt(team, lane, row, u)
	self:emit({ type = "summon", unit = self:snapshot(u), replaced = replaced, how = opts.how })
	self:landIn(u)
	return u
end

-- A Junk creature that lands in a lane picks up its Scrap.
function MatchEngine:landIn(u)
	local l = self:laneOf(u)
	if card(u.id).family == "Junk" and l.scrap > 0 then
		local n = l.scrap
		l.scrap = 0
		self:emit({ type = "scrap", team = u.team, lane = u.lane, amount = 0 })
		self:buff(u, n * CardData.ScrapGain, n * CardData.ScrapGain, "scrap")
	end
end

function MatchEngine:build(s, lane, id)
	local team = self.seats[s].team
	local l = self.lanes[team][lane]
	local replaced = nil
	if l.building then
		replaced = l.building.uid
		table.insert(self.seats[l.building.owner].discard, l.building.id)
	end
	l.building = { uid = self:uid(), id = id, kind = "building", owner = s, team = team, lane = lane }
	self:emit({ type = "build", unit = self:snapshot(l.building), replaced = replaced })
	return l.building
end

function MatchEngine:destroyBuilding(b)
	local l = self.lanes[b.team][b.lane]
	if l.building == b then
		l.building = nil
		table.insert(self.seats[b.owner].discard, b.id)
		self:emit({ type = "wreck", uid = b.uid })
	end
end

-- Moves a creature to an empty tile of its side. Without a row it keeps its row if that tile is
-- free, else takes the other one. Returns false when there is no room.
function MatchEngine:moveCreature(u, lane, how, row)
	local fromLane, fromRow = u.lane, u.row
	local l = self.lanes[u.team][lane]
	if not l then
		return false
	end
	if row == nil then
		if lane == fromLane then
			row = fromRow == 1 and 2 or 1
		elseif not self:unitAt(u.team, lane, fromRow) then
			row = fromRow
		else
			row = fromRow == 1 and 2 or 1
		end
	end
	if self:unitAt(u.team, lane, row) then
		return false
	end
	self:setAt(u.team, fromLane, fromRow, nil)
	self:setAt(u.team, lane, row, u)
	-- A creature moved into a lane another teammate owns stays under its own player's control.
	self:emit({ type = "move", uid = u.uid, team = u.team, from = fromLane, to = lane, fromRow = fromRow, toRow = row, how = how })
	if lane ~= fromLane then
		self:landIn(u)
	end
	return true
end

-- Two creatures on the same side trade places (Tornado Twins, Shift).
function MatchEngine:swapCreatures(a, b, how)
	local la, ra, lb, rb = a.lane, a.row, b.lane, b.row
	self:setAt(a.team, la, ra, nil)
	self:setAt(b.team, lb, rb, nil)
	self:setAt(a.team, lb, rb, a)
	self:setAt(b.team, la, ra, b)
	self:emit({ type = "move", uid = a.uid, team = a.team, from = la, to = lb, fromRow = ra, toRow = rb, how = how or "swap" })
	self:emit({ type = "move", uid = b.uid, team = b.team, from = lb, to = la, fromRow = rb, toRow = ra, how = how or "swap" })
end

-- Empty tiles: { lane = i, row = r }, Front tiles first.
function MatchEngine:emptyTilesOf(s)
	local out = {}
	local team = self.seats[s].team
	for row = 1, ROWS do
		for _, i in ipairs(self:lanesOf(s)) do
			if not self:unitAt(team, i, row) then
				table.insert(out, { lane = i, row = row })
			end
		end
	end
	return out
end

function MatchEngine:emptyTilesOnSide(team)
	local out = {}
	for row = 1, ROWS do
		for i = 1, self.width do
			if not self:unitAt(team, i, row) then
				table.insert(out, { lane = i, row = row })
			end
		end
	end
	return out
end

-- Lanes of a seat with no creature at all (both tiles empty).
function MatchEngine:emptyLanesOf(s)
	local out = {}
	local team = self.seats[s].team
	for _, i in ipairs(self:lanesOf(s)) do
		if not self:firstIn(team, i) then
			table.insert(out, i)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Buffs, damage and healing
---------------------------------------------------------------------------

function MatchEngine:buff(u, atk, hp, reason)
	u.atkBonus += atk
	u.hpBonus += hp
	self:emit({ type = "buff", uid = u.uid, atk = atk, hp = hp, reason = reason })
	self:refresh(u)
end

function MatchEngine:addPower(u, amount, reason)
	local before = u.power
	u.power = math.clamp(u.power + amount, 0, CardData.PowerMax)
	if u.power ~= before then
		self:emit({ type = "power", uid = u.uid, amount = u.power - before, power = u.power, reason = reason })
		self:refresh(u)
	end
end

function MatchEngine:soak(u)
	if not u.soaked then
		u.soaked = true
		self:emit({ type = "soak", uid = u.uid })
		self:refresh(u)
	end
end

function MatchEngine:giveKeyword(u, kw)
	u.given[kw] = true
	self:emit({ type = "keyword", uid = u.uid, keyword = kw })
	self:refresh(u)
end

-- Removes all buffs and Power (Laundry Bot).
function MatchEngine:wash(u)
	u.atkBonus = 0
	u.hpBonus = 0
	u.power = 0
	u.given = {}
	u.tempAtk = 0
	if u.damage >= self:maxHpOf(u) then
		u.damage = self:maxHpOf(u) - 1
	end
	self:emit({ type = "wash", uid = u.uid })
	self:refresh(u)
end

-- Deals damage to a creature. source = { unit = attacker or nil, seat = who did it }.
-- Returns how much it really took.
function MatchEngine:damageCreature(u, amount, source)
	if amount <= 0 or not self:findUnit(u.uid) then
		return 0
	end
	if u.shield then
		u.shield = false
		self:emit({ type = "blocked", uid = u.uid })
		self:refresh(u)
		return 0
	end
	if u.soaked then
		amount += CardData.SoakBonus
		if source and source.unit and self:hasKeyword(source.unit, "Zap") then
			amount += CardData.ZapBonus
		end
		u.soaked = false
	end
	if self:hasKeyword(u, "Sturdy") then
		amount -= 1
	end
	amount = math.max(0, amount)
	if amount == 0 then
		self:emit({ type = "damage", uid = u.uid, amount = 0, hp = self:healthOf(u) })
		return 0
	end
	u.damage += amount
	self:emit({ type = "damage", uid = u.uid, amount = amount, hp = self:healthOf(u), soak = source and source.soak })
	if source and source.seat and self.seats[source.seat] and self.seats[source.seat].team ~= u.team then
		self.seats[source.seat].dealt += amount
	end
	self:refresh(u)
	return amount
end

function MatchEngine:damageTeam(team, amount, sourceSeat)
	if amount <= 0 or self.over then
		return
	end
	local t = self.teams[team]
	t.hp -= amount
	self:emit({ type = "heroDamage", team = team, amount = amount, hp = t.hp })
	if sourceSeat and self.seats[sourceSeat] and self.seats[sourceSeat].team ~= team then
		self.seats[sourceSeat].dealt += amount
	end
	self:checkWin()
end

function MatchEngine:healTeam(team, amount)
	local t = self.teams[team]
	local before = t.hp
	t.hp = math.min(t.maxHp, t.hp + amount)
	self:emit({ type = "heroHeal", team = team, amount = t.hp - before, hp = t.hp })
end

-- Heals a creature. Hot Sauce Imp gets 2 Power from every heal (it says so on the card).
function MatchEngine:healCreature(u, amount)
	local before = u.damage
	u.damage = math.max(0, u.damage - amount)
	self:emit({ type = "heal", uid = u.uid, amount = before - u.damage, hp = self:healthOf(u) })
	if u.id == "hot_sauce_imp" then
		self:addPower(u, 2, "heal")
	end
	self:refresh(u)
end

-- Takes popped creatures off the board and runs what happens when they pop, until nothing more pops.
function MatchEngine:resolvePops()
	local guard = 0
	while guard < 50 do
		guard += 1
		local popped = nil
		for _, u in ipairs(self:allCreatures()) do
			if u.damage >= self:maxHpOf(u) then
				popped = u
				break
			end
		end
		if not popped then
			return
		end
		self:pop(popped)
	end
end

function MatchEngine:pop(u, quiet)
	local l = self:laneOf(u)
	if not self:isOnBoard(u) then
		return
	end
	local c = card(u.id)
	local owner = self.seats[u.owner]
	local atk = self:attackOf(u)
	self:setAt(u.team, u.lane, u.row, nil)
	self:emit({ type = "pop", uid = u.uid })
	if c.token then
		-- tokens just vanish
	else
		table.insert(owner.discard, u.id)
		table.insert(owner.lost, u.id)
	end
	if quiet or u.raised then
		return
	end
	-- Junk leaves Scrap in its lane.
	if c.family == "Junk" then
		local gain = u.id == "tin_can_tom" and 2 or 1
		l.scrap = math.min(CardData.ScrapMax, l.scrap + gain)
		self:emit({ type = "scrap", team = u.team, lane = u.lane, amount = l.scrap })
	end
	-- Mushroom Witch (anywhere on your side) hurts the enemy hero.
	for _, o in ipairs(self:allCreatures(u.team)) do
		if o.id == "mushroom_witch" then
			self:damageTeam(self:enemyTeam(u.team), 1, o.owner)
		end
	end
	-- Grudge: it hits the enemy creature across (or the enemy hero) on the way out.
	if self:hasKeyword(u, "Grudge") and atk > 0 then
		local foe = self:across(u)
		self:emit({ type = "grudge", uid = u.uid, target = foe and foe.uid, team = self:enemyTeam(u.team) })
		if foe then
			self:damageCreature(foe, atk, { seat = u.owner })
		else
			self:damageTeam(self:enemyTeam(u.team), atk, u.owner)
		end
	end
	-- Haunt: a Ghost rises where it fell.
	if self:hasKeyword(u, "Haunt") and not self:unitAt(u.team, u.lane, u.row) then
		local g = self:spawn(u.owner, u.lane, "ghost", { how = "haunt", row = u.row })
		g.playedTurn = -1
	end
end

function MatchEngine:checkWin()
	if self.over then
		return
	end
	local dead1, dead2 = self.teams[1].hp <= 0, self.teams[2].hp <= 0
	if dead1 or dead2 then
		self.over = true
		if dead1 and dead2 then
			self.winner = 0
		else
			self.winner = dead1 and 2 or 1
		end
		self:emit({ type = "win", winner = self.winner })
	end
end

---------------------------------------------------------------------------
-- Turns
---------------------------------------------------------------------------

function MatchEngine:startTurn(s)
	self.turn += 1
	self.current = s
	local seat = self.seats[s]
	seat.turns += 1
	seat.played = 0
	local extra = 0
	local team = seat.team
	for _, i in ipairs(self:lanesOf(s)) do
		local b = self.lanes[team][i].building
		if b and b.id == "lemonade_stand" then
			extra = 1
		end
	end
	seat.maxMagic = math.min(CardData.MaxMagic, CardData.StartMagic + seat.turns - 1)
	seat.magic = seat.maxMagic + extra + (seat.magicBonus or 0) -- magicBonus: a campaign rule (Surge)
	-- Your creatures wake up; "until your next turn" effects you caused wear off.
	for _, u in ipairs(self:allCreatures()) do
		if u.owner == s then
			u.sparked = false
			u.shifted = false
			u.tempAtk = 0
		end
		if u.booBy == s then
			u.boo = 0
			u.booBy = nil
		end
	end
	self:emit({ type = "turn", seat = s, turn = self.turn, magic = seat.magic, maxMagic = seat.maxMagic })
	local first = self.turn == 1
	if not first or CardData.FirstTurnDraw then
		self:draw(s)
	end
	if self.over then
		return
	end
	-- Start-of-turn abilities, lane by lane: your creatures and the buildings in your lanes.
	local enemy = self:enemyTeam(team)
	for i, l in ipairs(self.lanes[team]) do
		for _, u in ipairs(self:laneCreatures(team, i)) do
			if u.owner == s and self:isOnBoard(u) then
				local c = card(u.id)
				if c.charge then
					self:addPower(u, c.charge, "charge")
				end
				if l.building and l.building.id == "charging_station" then
					self:addPower(u, 1, "charge")
				end
				if u.id == "stormlord_nimbus" then
					self:emit({ type = "ability", uid = u.uid, id = u.id })
					for _, foe in ipairs(self:allCreatures(enemy)) do
						self:damageCreature(foe, 1, { unit = u, seat = s })
					end
				elseif u.id == "microwave_mage" then
					self:emit({ type = "ability", uid = u.uid, id = u.id })
					for _, lane in ipairs({ i - 1, i, i + 1 }) do
						local foe = self:firstIn(enemy, lane)
						if foe then
							self:damageCreature(foe, 1, { unit = u, seat = s })
						end
					end
				elseif u.id == "omega_microwave" then
					self:emit({ type = "ability", uid = u.uid, id = u.id })
					for _, foe in ipairs(self:allCreatures(enemy)) do
						self:damageCreature(foe, 3, { unit = u, seat = s })
					end
				end
			end
		end
		local b = l.building
		if b and b.owner ~= s then
			b = nil
		end
		if b then
			local inLane = self:laneCreatures(team, i)
			if b.id == "snack_bar" and #inLane > 0 then
				self:emit({ type = "ability", uid = b.uid, id = b.id })
				for _, o in ipairs(inLane) do
					self:healCreature(o, 2)
				end
			elseif b.id == "bunny_burrow" and #inLane < ROWS then
				self:emit({ type = "ability", uid = b.uid, id = b.id })
				local p = self:spawn(s, i, "pigeon", { how = "burrow" })
				p.playedTurn = -1
			elseif b.id == "disco_cactus" and #inLane > 0 then
				local roll = self.rng:int(1, 2)
				self:emit({ type = "roll", seat = s, id = b.id, result = roll == 1 and "Power" or "Heal 2" })
				for _, o in ipairs(inLane) do
					if roll == 1 then
						self:addPower(o, 1, "disco")
					else
						self:healCreature(o, 2)
					end
				end
			elseif b.id == "scrap_catapult" then
				local foe = self.rng:pick(self:allCreatures(enemy))
				self:emit({ type = "ability", uid = b.uid, id = b.id, target = foe and foe.uid })
				if foe then
					self:damageCreature(foe, 2, { seat = s })
				end
			elseif b.id == "haunted_arcade" then
				local tile = self.rng:pick(self:emptyTilesOf(s))
				if tile then
					self:emit({ type = "ability", uid = b.uid, id = b.id })
					local g = self:spawn(s, tile.lane, "ghost", { how = "arcade", row = tile.row })
					g.playedTurn = -1
				end
			elseif b.id == "rocket_lunchbox" then
				self:emit({ type = "ability", uid = b.uid, id = b.id })
				self:damageTeam(enemy, 2, s)
			end
		end
		self:resolvePops()
		if self.over then
			return
		end
	end
	self:refreshAll()
end

function MatchEngine:nextSeat()
	for i, s in ipairs(self.order) do
		if s == self.current then
			return self.order[i % #self.order + 1]
		end
	end
	return self.order[1]
end

-- BATTLE: lane by lane from left to right, your Front creatures attack (and Ranged creatures in
-- your Back row), unless Sparked, Shifted, frozen or new. Then Back creatures whose Front tile
-- is empty step up into it, and the turn passes.
function MatchEngine:battle(s)
	local seat = self.seats[s]
	local team = seat.team
	local enemy = self:enemyTeam(team)
	local noBattle = self.turn == 1 and not CardData.FirstTurnBattle
	self:emit({ type = "battle", seat = s, skipped = noBattle })
	if not noBattle then
		for i = 1, self.width do
			for row = 1, ROWS do
				if self.over then
					break
				end
				local u = self:unitAt(team, i, row)
				if u and u.owner == s and (row == 1 or self:hasKeyword(u, "Ranged")) then
					if u.frozen then
						u.frozen = false
						self:emit({ type = "thaw", uid = u.uid })
						self:refresh(u)
					elseif not u.sparked and not u.shifted and not self:isNew(u) then
						self:attack(u, enemy)
					end
				end
			end
		end
	end
	if self.over then
		return
	end
	-- "This turn" boosts (Hamster Wheel Hero) end with the battle.
	for _, u in ipairs(self:creaturesOf(s)) do
		u.tempAtk = 0
	end
	self:stepUp(s)
	self:endTurn()
end

-- After your battle, each of your Back creatures with an empty Front tile steps up into it.
function MatchEngine:stepUp(s)
	local team = self.seats[s].team
	local moved = false
	for i = 1, self.width do
		local b = self:unitAt(team, i, 2)
		if b and b.owner == s and not self:unitAt(team, i, 1) then
			self:moveCreature(b, i, "stepUp", 1)
			moved = true
		end
	end
	if moved then
		self:refreshAll()
	end
end

-- Who a creature hits. From the Front row (Ranged or not): the first enemy in its lane. A Ranged
-- creature in the Back row shoots the weakest enemy creature in its lane or the lanes next to
-- it, in either row. nil means the enemy hero (only when nothing at all stands in the way).
function MatchEngine:attackTarget(u)
	local enemy = self:enemyTeam(u.team)
	if u.row == 2 and self:hasKeyword(u, "Ranged") then
		local best, bestHp = nil, math.huge
		for _, lane in ipairs({ u.lane, u.lane - 1, u.lane + 1 }) do
			for _, o in ipairs(self:laneCreatures(enemy, lane)) do
				local hp = self:healthOf(o)
				if hp < bestHp then
					best, bestHp = o, hp
				end
			end
		end
		return best
	end
	return self:across(u)
end

-- Damage rolling down an enemy lane (melee overkill, Strike): it hits the Front creature, what
-- it doesn't need to pop it rolls on to the Back creature, and then to the hero.
-- Returns the creatures it hit, in order.
function MatchEngine:rollDownLane(team, lane, amount, source, first)
	local hit = {}
	local left = amount
	local list = self:laneCreatures(team, lane)
	if first then
		-- start from this creature (and roll on to the ones behind it)
		while #list > 0 and list[1] ~= first do
			table.remove(list, 1)
		end
	end
	for k, o in ipairs(list) do
		if left <= 0 then
			break
		end
		local hp = self:healthOf(o)
		self:damageCreature(o, left, source)
		table.insert(hit, o)
		if self:healthOf(o) > 0 or not CARRY then
			return hit -- it held on (or overkill is off): nothing rolls on
		end
		left = math.max(0, left - hp)
		if left > 0 then
			self:emit({ type = "overkill", uid = o.uid, team = team, lane = lane, amount = left, toHero = list[k + 1] == nil })
		end
	end
	if left > 0 then
		self:damageTeam(team, left, source and source.seat)
	end
	return hit
end

function MatchEngine:attack(u, enemy)
	local atk = self:attackOf(u)
	if atk <= 0 then
		return
	end
	local target = self:attackTarget(u)
	self:emit({ type = "attack", uid = u.uid, team = u.team, lane = u.lane, row = u.row, target = target and target.uid, targetLane = target and target.lane or u.lane, targetRow = target and target.row or nil, hero = target == nil and enemy or nil, amount = atk })
	if target then
		local targetLane = target.lane
		local defenderLane = self.lanes[enemy][targetLane]
		local source = { unit = u, seat = u.owner }
		local hp = self:healthOf(target)
		self:damageCreature(target, atk, source)
		-- Melee overkill rolls on down the lane (to the Back creature, then the hero).
		local melee = not (u.row == 2 and self:hasKeyword(u, "Ranged"))
		if CARRY and melee and self:healthOf(target) <= 0 then
			local left = atk - hp
			local behind = target.row == 1 and self:unitAt(enemy, targetLane, 2) or nil
			if left > 0 then
				self:emit({ type = "overkill", uid = target.uid, team = enemy, lane = targetLane, amount = left, toHero = behind == nil })
				if behind then
					self:rollDownLane(enemy, targetLane, left, { seat = u.owner }, behind)
				else
					self:damageTeam(enemy, left, u.owner)
				end
			end
		end
		if card(u.id).soaks and self:findUnit(target.uid) then
			self:soak(target)
		end
		if target.id == "burrito_bouncer" then
			self:emit({ type = "ability", uid = target.uid, id = target.id })
			self:damageCreature(u, 1, { unit = target, seat = target.owner })
		end
		if defenderLane.building and defenderLane.building.id == "spiked_fence" then
			self:emit({ type = "ability", uid = defenderLane.building.uid, id = "spiked_fence" })
			self:damageCreature(u, 1, { seat = defenderLane.building.owner })
		end
		if self:hasKeyword(u, "Splash") then
			for _, o in ipairs(self:neighbours(target)) do
				self:damageCreature(o, 1, { unit = u, seat = u.owner, splash = true })
			end
		end
	else
		local defenderLane = self.lanes[enemy][u.lane]
		self:damageTeam(enemy, atk, u.owner)
		if defenderLane.building and defenderLane.building.id == "spiked_fence" then
			self:emit({ type = "ability", uid = defenderLane.building.uid, id = "spiked_fence" })
			self:damageCreature(u, 1, { seat = defenderLane.building.owner })
		end
	end
	self:resolvePops()
end

function MatchEngine:endTurn()
	if self.turn >= MAX_TURNS and not self.over then
		local a, b = self.teams[1].hp, self.teams[2].hp
		self.over = true
		self.winner = a > b and 1 or (b > a and 2 or 0)
		self:emit({ type = "win", winner = self.winner, timeout = true })
		return
	end
	self:startTurn(self:nextSeat())
end

---------------------------------------------------------------------------
-- Playing cards
---------------------------------------------------------------------------

local LANE_KINDS = { lane = true, enemyLane = true }

-- Is `target` ({ team, lane, row }) a fine target of this kind for seat s? Lane kinds ignore the
-- row; creature kinds need the tile's creature (without a row: the first one in the lane).
function MatchEngine:validTarget(s, kind, target, self_uid)
	if type(target) ~= "table" then
		return false
	end
	local t, lane, row = target.team, target.lane, target.row
	if (t ~= 1 and t ~= 2) or type(lane) ~= "number" or not self.lanes[t][lane] then
		return false
	end
	if row ~= nil and row ~= 1 and row ~= 2 then
		return false
	end
	local myTeam = self.seats[s].team
	local u = self:targetUnit(target)
	if kind == "lane" then
		return true
	elseif kind == "enemyLane" then
		return t ~= myTeam
	elseif kind == "anyCreature" then
		return u ~= nil
	elseif kind == "enemyCreature" then
		return u ~= nil and t ~= myTeam
	elseif kind == "otherFriendlyCreature" then
		return u ~= nil and t == myTeam and u.uid ~= self_uid
	elseif kind == "enemyCreatureCost3" then
		return u ~= nil and t ~= myTeam and card(u.id).cost <= 3
	elseif kind == "enemyCreatureAtk3" then
		return u ~= nil and t ~= myTeam and self:attackOf(u) <= 3
	end
	return false
end

function MatchEngine:targetsFor(s, kind, self_uid)
	local out = {}
	for t = 1, 2 do
		for lane = 1, self.width do
			if LANE_KINDS[kind] then
				local target = { team = t, lane = lane }
				if self:validTarget(s, kind, target, self_uid) then
					table.insert(out, target)
				end
			else
				for row = 1, ROWS do
					local target = { team = t, lane = lane, row = row }
					if self:validTarget(s, kind, target, self_uid) then
						table.insert(out, target)
					end
				end
			end
		end
	end
	return out
end

function MatchEngine:targetUnit(target)
	if type(target) ~= "table" or not (self.lanes[target.team] and self.lanes[target.team][target.lane]) then
		return nil
	end
	if target.row == 1 or target.row == 2 then
		return self:unitAt(target.team, target.lane, target.row)
	end
	return self:firstIn(target.team, target.lane)
end

-- Blows a side's creatures onto random tiles of that side (Tornado Twins, Total Chaos).
function MatchEngine:scatter(team, units, how)
	local tiles = {}
	for row = 1, ROWS do
		for i = 1, self.width do
			table.insert(tiles, { lane = i, row = row })
		end
	end
	self.rng:shuffle(tiles)
	local from = {}
	for k, o in ipairs(units) do
		from[k] = { o.lane, o.row }
		self:setAt(team, o.lane, o.row, nil)
	end
	for k, o in ipairs(units) do
		self:setAt(team, tiles[k].lane, tiles[k].row, o)
		self:emit({ type = "move", uid = o.uid, team = team, from = from[k][1], to = o.lane, fromRow = from[k][2], toRow = o.row, how = how })
	end
end

local ROLL_KEYWORDS = { "Zoom", "Ranged", "Sturdy", "Splash", "Haunt", "Pack", "Zap", "Grudge" }

-- "When played" abilities.
function MatchEngine:onPlay(u, target, combo)
	local s = u.owner
	local seat = self.seats[s]
	local team = u.team
	local enemy = self:enemyTeam(team)
	local c = card(u.id)
	if c.snackTime then
		self:healTeam(team, c.snackTime)
	end
	local id = u.id
	if id == "pretzel_guard" then
		if combo then
			for _, o in ipairs(self:allCreatures(team)) do
				if o ~= u then
					self:healCreature(o, 1)
				end
			end
		end
	elseif id == "pancake_paladin" then
		for _, o in ipairs(self:neighbours(u)) do
			self:healCreature(o, 2)
		end
	elseif id == "spaghetti_hydra" or id == "roomba_rex" then
		if combo then
			self:addPower(u, 2, "combo")
		end
	elseif id == "queen_parfait" then
		for _, o in ipairs(self:allCreatures(team)) do
			if o ~= u then
				self:healCreature(o, o.damage)
			end
		end
	elseif id == "dumpster_diver" then
		local spells = {}
		for i, cid in ipairs(seat.discard) do
			if card(cid).type == "Spell" then
				table.insert(spells, i)
			end
		end
		local pick = self.rng:pick(spells)
		if pick then
			local cid = table.remove(seat.discard, pick)
			self:addToHand(s, cid)
		end
		if combo then
			for _, n in ipairs(self:neighbourLanes(u.lane)) do
				local l = self.lanes[team][n]
				if l.scrap > 0 then
					local amount = l.scrap
					l.scrap = 0
					self:emit({ type = "scrap", team = team, lane = n, amount = 0 })
					self:buff(u, amount, amount, "scrap")
				end
			end
		end
	elseif id == "rusty_shopping_cart" then
		-- It also picks up the Scrap in the lanes next to it (its own lane's Scrap it picks up anyway).
		for _, n in ipairs(self:neighbourLanes(u.lane)) do
			local l = self.lanes[team][n]
			if l.scrap > 0 then
				local amount = l.scrap
				l.scrap = 0
				self:emit({ type = "scrap", team = team, lane = n, amount = 0 })
				self:buff(u, amount, amount, "scrap")
			end
		end
	elseif id == "glitter_gremlin" then
		self:gremlinRoll(u)
	elseif id == "the_junk_king" then
		for t = 1, 2 do
			for _, l in ipairs(self.lanes[t]) do
				if l.building then
					self:destroyBuilding(l.building)
				end
			end
		end
	elseif id == "grumpy_cloud" then
		if combo then
			for _, foe in ipairs(self:allCreatures(enemy)) do
				self:soak(foe)
			end
		else
			local foe = self.rng:pick(self:allCreatures(enemy))
			if foe then
				self:damageCreature(foe, 1, { unit = u, seat = s })
				if self:findUnit(foe.uid) then
					self:soak(foe)
				end
			end
		end
	elseif id == "hailstone_hopper" or id == "sheet_ghost" or id == "hamster_wheel_hero" then
		if combo then
			self:giveKeyword(u, "Zoom")
		end
	elseif id == "lightning_llama" then
		local foes = self:allCreatures(enemy)
		local roll = self.rng:int(1, 2)
		if roll == 1 and #foes > 0 then
			local foe = self.rng:pick(foes)
			self:emit({ type = "roll", seat = s, id = id, result = "Zap a creature" })
			self:damageCreature(foe, 2, { unit = u, seat = s })
		else
			self:emit({ type = "roll", seat = s, id = id, result = "Zap the hero" })
			self:damageTeam(enemy, 2, s)
		end
	elseif id == "tornado_twins" then
		local foes = self:allCreatures(enemy)
		self:scatter(enemy, foes, "blow")
		for _, foe in ipairs(foes) do
			self:soak(foe)
		end
	elseif id == "moth_mailman" then
		self:draw(s)
		if combo then
			self:draw(s)
		end
	elseif id == "pillow_bunny" then
		local friend = self:targetUnit(target)
		if not (friend and friend.team == team and friend ~= u) then
			local others = {}
			for _, o in ipairs(self:allCreatures(team)) do
				if o ~= u then
					table.insert(others, o)
				end
			end
			friend = self.rng:pick(others)
		end
		if friend then
			self:buff(friend, combo and 1 or 0, 2, "bunny")
		end
	elseif id == "pigeon_squad" then
		for _, n in ipairs(self:neighbourLanes(u.lane)) do
			local l = self.lanes[team][n]
			if l.owner == s and not self:unitAt(team, n, u.row) then
				local p = self:spawn(s, n, "pigeon", { how = "squad", row = u.row })
				p.playedTurn = -1
			end
		end
	elseif id == "big_momma_moose" then
		for _, o in ipairs(self:allCreatures(team)) do
			if o ~= u and card(o.id).family == "Critter" then
				self:buff(o, 1, 1, "moose")
			end
		end
	elseif id == "captain_confetti" then
		for _, o in ipairs(self:allCreatures(team)) do
			self:giveKeyword(o, self.rng:pick(ROLL_KEYWORDS))
		end
	elseif id == "haunted_vending_machine" then
		local pool = {}
		for _, cid in ipairs(CardData.List) do
			if card(cid).cost == 1 then
				table.insert(pool, cid)
			end
		end
		for _ = 1, combo and 2 or 1 do
			local cid = self.rng:pick(pool)
			self:emit({ type = "roll", seat = s, id = id, result = card(cid).name })
			self:addToHand(s, cid)
		end
	elseif id == "escalator_wraith" then
		local foe = self:targetUnit(target)
		if not (foe and foe.team == enemy and card(foe.id).cost <= 3) then
			local cheap = {}
			for _, o in ipairs(self:allCreatures(enemy)) do
				if card(o.id).cost <= 3 then
					table.insert(cheap, o)
				end
			end
			foe = self.rng:pick(cheap)
		end
		if foe then
			self:returnToHand(foe)
		end
	elseif id == "the_mannequin_duke" then
		self:raiseLost(s, u)
	elseif id == "toaster_knight" then
		local foe = self.rng:pick(self:allCreatures(enemy))
		if foe then
			self:emit({ type = "ability", uid = u.uid, id = id, target = foe.uid })
			self:damageCreature(foe, combo and 2 or 1, { unit = u, seat = s })
		end
	elseif id == "laundry_bot_3000" then
		local foe = self:targetUnit(target)
		if not (foe and foe.team == enemy) then
			foe = self:across(u) or self.rng:pick(self:allCreatures(enemy))
		end
		if foe then
			self:wash(foe)
		end
	elseif id == "mega_blender_prime" then
		local foes = self:allCreatures(enemy)
		if self.rng:int(1, 2) == 1 and #foes > 0 then
			local foe = self.rng:pick(foes)
			self:emit({ type = "roll", seat = s, id = id, result = "Blend a creature" })
			self:pop(foe)
		else
			self:emit({ type = "roll", seat = s, id = id, result = "4 damage to the hero" })
			self:damageTeam(enemy, 4, s)
		end
	end
end

function MatchEngine:gremlinRoll(u)
	local roll = self.rng:int(1, 3)
	if roll == 1 then
		self:emit({ type = "roll", seat = u.owner, id = u.id, result = "Zoom" })
		self:giveKeyword(u, "Zoom")
	elseif roll == 2 then
		self:emit({ type = "roll", seat = u.owner, id = u.id, result = "Sturdy" })
		self:giveKeyword(u, "Sturdy")
	else
		self:emit({ type = "roll", seat = u.owner, id = u.id, result = "+2 attack" })
		self:buff(u, 2, 0, "roll")
	end
end

function MatchEngine:returnToHand(u)
	if not self:isOnBoard(u) then
		return
	end
	self:setAt(u.team, u.lane, u.row, nil)
	self:emit({ type = "bounce", uid = u.uid })
	if not card(u.id).token then
		self:addToHand(u.owner, u.id)
	end
end

-- Brings back the last creature this seat lost into an empty lane (The Mannequin Duke).
function MatchEngine:raiseLost(s, near)
	local seat = self.seats[s]
	local id = table.remove(seat.lost)
	if not id then
		return
	end
	for i = #seat.discard, 1, -1 do
		if seat.discard[i] == id then
			table.remove(seat.discard, i)
			break
		end
	end
	local tiles = self:emptyTilesOf(s)
	local tile = tiles[1]
	if near then
		-- next to the one raising it if there's room: its other row first, then the lanes beside it
		for _, t in ipairs(tiles) do
			if t.lane == near.lane then
				tile = t
				break
			end
		end
		if tile and tile.lane ~= near.lane then
			for _, t in ipairs(tiles) do
				if math.abs(t.lane - near.lane) == 1 and t.row == near.row then
					tile = t
					break
				end
			end
		end
	end
	if tile then
		local r = self:spawn(s, tile.lane, id, { how = "raise", row = tile.row })
		r.playedTurn = -1
	end
end

function MatchEngine:castSpell(s, id, target, entry)
	local seat = self.seats[s]
	local team = seat.team
	local enemy = self:enemyTeam(team)
	local u = self:targetUnit(target)
	self:emit({ type = "spell", seat = s, id = id, target = target and { team = target.team, lane = target.lane }, targetUid = u and u.uid })
	if id == "spare_battery" or id == "scrap" then
		seat.magic += 1
		self:emit({ type = "magic", seat = s, magic = seat.magic })
	elseif id == "wrong_turn" then
		local tile = self.rng:pick(self:emptyTilesOnSide(u.team))
		if tile then
			self:moveCreature(u, tile.lane, "push", tile.row)
		else
			self:damageCreature(u, 2, { seat = s })
		end
	elseif id == "water_balloon" then
		self:soak(u)
		self:damageCreature(u, 1, { seat = s })
	elseif id == "snack_break" then
		self:healTeam(team, 4)
	elseif id == "coin_flip_fury" then
		if self.rng:chance(0.5) then
			self:emit({ type = "roll", seat = s, id = id, result = "Heads: 5 damage!" })
			self:damageCreature(u, 5, { seat = s })
		else
			self:emit({ type = "roll", seat = s, id = id, result = "Tails: ouch, 2 to you" })
			self:damageTeam(team, 2, nil)
		end
	elseif id == "sneeze_storm" then
		for _, foe in ipairs(self:allCreatures(enemy)) do
			self:damageCreature(foe, 1, { seat = s })
		end
	elseif id == "bubble_wrap" then
		u.shield = true
		self:emit({ type = "shield", uid = u.uid })
		self:refresh(u)
	elseif id == "pep_talk" then
		self:buff(u, 2, 2, "pep")
	elseif id == "terrain_shift" then
		local l = self.lanes[target.team][target.lane]
		l.landscape = seat.family
		self:emit({ type = "landscape", team = target.team, lane = target.lane, family = seat.family })
		self:draw(s)
	elseif id == "pothole" then
		self:pop(u)
	elseif id == "mystery_box" then
		for _ = 1, 2 do
			self:addToHand(s, self.rng:pick(CardData.List), -1)
		end
	elseif id == "earthquake_dance" then
		for _, o in ipairs(self:allCreatures()) do
			self:damageCreature(o, 3, { seat = s })
		end
	elseif id == "total_chaos" then
		for t = 1, 2 do
			self:scatter(t, self:allCreatures(t), "chaos")
			for i, l in ipairs(self.lanes[t]) do
				l.landscape = self.rng:pick(CardData.Families)
				self:emit({ type = "landscape", team = t, lane = i, family = l.landscape })
			end
		end
	end
end

---------------------------------------------------------------------------
-- Sparks
---------------------------------------------------------------------------

function MatchEngine:spark(s, u)
	local team = u.team
	local enemy = self:enemyTeam(team)
	local seat = self.seats[s]
	local foe = self:across(u)
	local id = u.id
	local function nextTo()
		return self:neighbours(u)
	end
	-- the first enemy in its lane and in the lanes next to it
	local function frontThree()
		local out = {}
		for _, lane in ipairs({ u.lane - 1, u.lane, u.lane + 1 }) do
			local o = self:firstIn(enemy, lane)
			if o then
				table.insert(out, o)
			end
		end
		return out
	end
	if id == "jelly_bean_scout" then
		self:healTeam(team, 2)
	elseif id == "pretzel_guard" or id == "sergeant_snail" then
		for _, o in ipairs(nextTo()) do
			self:healCreature(o, 2)
		end
	elseif id == "pancake_paladin" then
		for _, o in ipairs(self:allCreatures(team)) do
			self:healCreature(o, 1)
		end
	elseif id == "hot_sauce_imp" then
		self:healCreature(u, 1)
	elseif id == "spaghetti_hydra" then
		for _, o in ipairs(self:allCreatures(enemy)) do
			self:damageCreature(o, 1, { unit = u, seat = s })
		end
	elseif id == "burrito_bouncer" or id == "couch_golem" then
		self:healCreature(u, 3)
	elseif id == "queen_parfait" then
		self:healTeam(team, 3)
		for _, o in ipairs(self:allCreatures(team)) do
			if card(o.id).family == "Snack" then
				self:addPower(o, 1, "parfait")
			end
		end
	elseif id == "tin_can_tom" then
		if foe then
			self:damageCreature(foe, 2, { unit = u, seat = s })
		end
		self:pop(u)
	elseif id == "rusty_shopping_cart" then
		local total = 0
		for _, i in ipairs(self:lanesOf(s)) do
			local l = self.lanes[team][i]
			if i ~= u.lane and l.scrap > 0 then
				total += l.scrap
				l.scrap = 0
				self:emit({ type = "scrap", team = team, lane = i, amount = 0 })
			end
		end
		if total > 0 then
			self:buff(u, total, total, "scrap")
		end
	elseif id == "dumpster_diver" then
		if #seat.discard > 0 then
			local cid = table.remove(seat.discard, self.rng:int(1, #seat.discard))
			self:addToHand(s, cid)
		end
	elseif id == "glitter_gremlin" then
		self:gremlinRoll(u)
	elseif id == "scrapheap_titan" then
		local l = self:laneOf(u)
		if l.scrap > 0 then
			local n = l.scrap
			l.scrap = 0
			self:emit({ type = "scrap", team = team, lane = u.lane, amount = 0 })
			self:buff(u, 2 * n, 2 * n, "scrap")
		end
	elseif id == "the_junk_king" then
		if foe and self:healthOf(foe) <= 3 then
			local fl = self:laneOf(foe)
			self:pop(foe, true)
			fl.scrap = math.min(CardData.ScrapMax, fl.scrap + 2)
			self:emit({ type = "scrap", team = foe.team, lane = foe.lane, amount = fl.scrap })
		end
	elseif id == "drizzle_sprite" then
		if foe then
			self:soak(foe)
		end
	elseif id == "grumpy_cloud" then
		for _, o in ipairs(frontThree()) do
			self:soak(o)
		end
	elseif id == "hailstone_hopper" then
		for _, o in ipairs(frontThree()) do
			self:damageCreature(o, 1, { unit = u, seat = s })
		end
	elseif id == "fog_bank" then
		if foe then
			foe.frozen = true
			self:emit({ type = "freeze", uid = foe.uid })
			self:refresh(foe)
		end
	elseif id == "lightning_llama" then
		if foe then
			self:damageCreature(foe, 3, { unit = u, seat = s })
		end
	elseif id == "tornado_twins" then
		if foe then
			local others = {}
			for _, o in ipairs(self:allCreatures(enemy)) do
				if o ~= foe then
					table.insert(others, o)
				end
			end
			local other = self.rng:pick(others)
			if other then
				self:swapCreatures(foe, other)
			else
				local tile = self.rng:pick(self:emptyTilesOnSide(enemy))
				if tile then
					self:moveCreature(foe, tile.lane, "blow", tile.row)
				end
			end
		end
	elseif id == "stormlord_nimbus" then
		for _, o in ipairs(self:allCreatures(enemy)) do
			self:soak(o)
			self:damageCreature(o, 1, { unit = u, seat = s })
		end
	elseif id == "pocket_mouse" or id == "pigeon" then
		-- the empty tile of yours furthest from it (Front tiles first when it's a tie)
		local best = nil
		for _, t in ipairs(self:emptyTilesOf(s)) do
			if not best or math.abs(t.lane - u.lane) > math.abs(best.lane - u.lane) then
				best = t
			end
		end
		if best then
			self:moveCreature(u, best.lane, "scurry", best.row)
		end
	elseif id == "moth_mailman" then
		self:draw(s)
	elseif id == "pillow_bunny" then
		for _, o in ipairs(nextTo()) do
			self:buff(o, 0, 2, "bunny")
		end
	elseif id == "hamster_wheel_hero" then
		for _, o in ipairs(self:allCreatures(team)) do
			if o ~= u and o.owner == s then
				o.tempAtk += 1
				self:refresh(o)
			end
		end
	elseif id == "pigeon_squad" then
		local tile = self.rng:pick(self:emptyTilesOf(s))
		if tile then
			local p = self:spawn(s, tile.lane, "pigeon", { how = "squad", row = tile.row })
			p.playedTurn = -1
		end
	elseif id == "big_momma_moose" then
		for _, o in ipairs(self:allCreatures(team)) do
			if o ~= u then
				self:buff(o, 1, 1, "moose")
			end
		end
	elseif id == "captain_confetti" then
		for _, o in ipairs(self:allCreatures(team)) do
			self:giveKeyword(o, self.rng:pick(ROLL_KEYWORDS))
		end
	elseif id == "sheet_ghost" or id == "ghost" then
		if foe then
			foe.boo += (id == "ghost") and 1 or 2
			foe.booBy = s
			self:emit({ type = "boo", uid = foe.uid })
			self:refresh(foe)
		end
	elseif id == "skeleton_mascot" then
		if foe then
			self:damageCreature(foe, 1, { unit = u, seat = s })
		end
	elseif id == "haunted_vending_machine" then
		local pool = {}
		for _, cid in ipairs(CardData.List) do
			if card(cid).cost == 1 then
				table.insert(pool, cid)
			end
		end
		self:addToHand(s, self.rng:pick(pool))
	elseif id == "mushroom_witch" then
		local n = 0
		for _, cid in ipairs(seat.discard) do
			if card(cid).type == "Creature" then
				n += 1
			end
		end
		if n > 0 then
			self:damageTeam(enemy, math.min(3, n), s)
		end
	elseif id == "mall_cop_phantom" then
		if foe and card(foe.id).cost <= 2 then
			self:returnToHand(foe)
		end
	elseif id == "escalator_wraith" then
		if foe then
			-- it rides to a random empty tile on its side (often the Back row, out of the fight)
			local tile = self.rng:pick(self:emptyTilesOnSide(enemy))
			if tile then
				self:moveCreature(foe, tile.lane, "escalator", tile.row)
			end
		end
	elseif id == "the_mannequin_duke" then
		self:raiseLost(s, u)
	elseif id == "bolt_bug" or id == "mecha_fridge" then
		for _, o in ipairs(nextTo()) do
			self:addPower(o, 1, "charge")
		end
	elseif id == "roomba_rex" then
		self:addPower(u, 2, "spark")
	elseif id == "toaster_knight" then
		if foe then
			self:damageCreature(foe, 2, { unit = u, seat = s })
		end
	elseif id == "laundry_bot_3000" then
		if foe then
			self:wash(foe)
		end
	elseif id == "microwave_mage" then
		if foe then
			self:damageCreature(foe, 2, { unit = u, seat = s })
		end
	elseif id == "mega_blender_prime" then
		if foe then
			self:damageCreature(foe, 5, { unit = u, seat = s })
		end
	elseif id == "omega_microwave" then
		for _, o in ipairs(self:allCreatures(enemy)) do
			self:damageCreature(o, 4, { unit = u, seat = s })
		end
	end
end

---------------------------------------------------------------------------
-- Big Moves
---------------------------------------------------------------------------

function MatchEngine:bigMoveReady(s)
	local seat = self.seats[s]
	return not seat.bigMoveUsed and seat.dealt >= CardData.BigMoveCharge
end

function MatchEngine:bigMove(s, target)
	local seat = self.seats[s]
	local enemy = self:enemyTeam(seat.team)
	seat.bigMoveUsed = true
	self:emit({ type = "bigmove", seat = s, hero = seat.hero, target = target and { team = target.team, lane = target.lane } })
	if seat.hero == "bonk" then
		local spells = {}
		for _, id in ipairs(CardData.List) do
			if card(id).type == "Spell" then
				table.insert(spells, id)
			end
		end
		self:addToHand(s, self.rng:pick(spells), nil, 0)
	else
		-- Strike: the ball bowls down the lane, through the Front creature and on to the Back one,
		-- and what's left hits the hero.
		self:rollDownLane(enemy, target.lane, 4, { seat = s })
	end
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Does what a seat asked for. Returns true, or false and a short reason.
function MatchEngine:act(s, action)
	if self.over then
		return false, "The match is over"
	end
	if s ~= self.current then
		return false, "It's not your turn"
	end
	if type(action) ~= "table" then
		return false, "Bad action"
	end
	local seat = self.seats[s]
	local kind = action.kind
	if kind == "battle" or kind == "endturn" then
		self:battle(s)
		return true
	elseif kind == "play" then
		local entry, index = self:findHand(s, action.handUid)
		if not entry then
			return false, "That card isn't in your hand"
		end
		local c = card(entry.id)
		local cost = self:costOf(s, entry)
		if cost > seat.magic then
			return false, "Not enough magic"
		end
		local target = action.target
		if c.type == "Creature" or c.type == "Building" then
			local lane = action.lane
			if type(lane) ~= "number" or not self:ownsLane(s, lane) then
				return false, "Pick one of your lanes"
			end
			if c.type == "Creature" and action.row ~= nil and action.row ~= 1 and action.row ~= 2 then
				return false, "Pick the Front or the Back row"
			end
			if c.target and target ~= nil and not self:validTarget(s, c.target, target) then
				return false, "That's not a target for this card"
			end
		else
			if c.targetRequired and not self:validTarget(s, c.target, target) then
				return false, "Pick a target"
			end
			if not c.targetRequired then
				target = nil
			end
		end
		local combo = seat.played > 0
		seat.magic -= cost
		table.remove(seat.hand, index)
		seat.played += 1
		local row = c.type == "Creature" and self:freeRow(seat.team, action.lane, action.row) or nil
		self:emit({ type = "play", seat = s, id = entry.id, handUid = entry.uid, cost = cost, lane = action.lane, row = row, magic = seat.magic })
		if c.type == "Creature" then
			local u = self:spawn(s, action.lane, entry.id, { how = "play", row = row })
			self:onPlay(u, target, combo)
		elseif c.type == "Building" then
			self:build(s, action.lane, entry.id)
		else
			if not c.token then
				table.insert(seat.discard, entry.id)
			end
			self:castSpell(s, entry.id, target, entry)
		end
		self:resolvePops()
		self:refreshAll()
		return true
	elseif kind == "spark" then
		local u = self:findUnit(action.uid)
		if not u or u.kind ~= "creature" or u.owner ~= s then
			return false, "That's not your creature"
		end
		if u.sparked then
			return false, "It already Sparked this turn"
		end
		local cost = card(u.id).sparkCost or 0
		if cost > seat.magic then
			return false, "Not enough magic"
		end
		seat.magic -= cost
		u.sparked = true
		self:emit({ type = "spark", seat = s, uid = u.uid, id = u.id, cost = cost, magic = seat.magic })
		self:spark(s, u)
		self:resolvePops()
		self:refreshAll()
		return true
	elseif kind == "shift" then
		-- Shift: the creature trades rows within its lane (with the creature in the other tile,
		-- if there is one of yours). It skips its attack this turn.
		local u = self:findUnit(action.uid)
		if not u or u.kind ~= "creature" or u.owner ~= s then
			return false, "That's not your creature"
		end
		local ok, why = self:canShift(s, u)
		if not ok then
			return false, why
		end
		seat.magic -= SHIFT_COST
		u.shifted = true
		local other = self:unitAt(u.team, u.lane, u.row == 1 and 2 or 1)
		self:emit({ type = "shift", seat = s, uid = u.uid, cost = SHIFT_COST, magic = seat.magic })
		if other then
			self:swapCreatures(u, other, "shift")
		else
			self:moveCreature(u, u.lane, "shift", u.row == 1 and 2 or 1)
		end
		self:refreshAll()
		return true
	elseif kind == "bigmove" then
		if not self:bigMoveReady(s) then
			return false, "Your Big Move isn't ready"
		end
		local hero = CardData.Heroes[seat.hero]
		if hero and hero.target and not self:validTarget(s, hero.target, action.target) then
			return false, "Pick a lane"
		end
		self:bigMove(s, action.target)
		self:resolvePops()
		self:refreshAll()
		return true
	end
	return false, "Unknown action"
end

-- Can seat s Shift this creature now? (once per turn, SHIFT_COST magic, the other tile is empty
-- or holds one of its own creatures)
function MatchEngine:canShift(s, u)
	if u.shifted then
		return false, "It already shifted this turn"
	end
	if SHIFT_COST > self.seats[s].magic then
		return false, "Not enough magic"
	end
	local other = self:unitAt(u.team, u.lane, u.row == 1 and 2 or 1)
	if other and other.owner ~= s then
		return false, "Your teammate's creature is in the way"
	end
	return true
end

-- Everything a seat can do right now, grouped for the screens:
--   { kind = "play", handUid, lanes = {...}, targets = {...}, needsTarget }
--   (creatures: tiles = { { lane, row } ... }: every tile of yours, empty ones first)
--   { kind = "spark", uid }, { kind = "shift", uid }, { kind = "bigmove", targets }, { kind = "battle" }
function MatchEngine:listActions(s)
	local out = {}
	if self.over or s ~= self.current then
		return out
	end
	local seat = self.seats[s]
	local team = seat.team
	for _, entry in ipairs(seat.hand) do
		local c = card(entry.id)
		if self:costOf(s, entry) <= seat.magic then
			local a = { kind = "play", handUid = entry.uid, id = entry.id }
			if c.type == "Creature" or c.type == "Building" then
				a.lanes = self:lanesOf(s)
				if c.type == "Creature" then
					a.tiles = {}
					for _, t in ipairs(self:emptyTilesOf(s)) do
						table.insert(a.tiles, t)
					end
					for row = 1, ROWS do
						for _, i in ipairs(a.lanes) do
							if self:unitAt(team, i, row) then
								table.insert(a.tiles, { lane = i, row = row, replace = true })
							end
						end
					end
				end
				if c.target then
					a.targets = self:targetsFor(s, c.target)
				end
			else
				if c.targetRequired then
					a.targets = self:targetsFor(s, c.target)
					a.needsTarget = true
				end
			end
			if not (a.needsTarget and #a.targets == 0) then
				table.insert(out, a)
			end
		end
	end
	for _, u in ipairs(self:creaturesOf(s)) do
		local c = card(u.id)
		if not u.sparked and (c.sparkCost or 0) <= seat.magic then
			table.insert(out, { kind = "spark", uid = u.uid })
		end
		if self:canShift(s, u) then
			table.insert(out, { kind = "shift", uid = u.uid })
		end
	end
	if self:bigMoveReady(s) then
		local hero = CardData.Heroes[seat.hero]
		local a = { kind = "bigmove" }
		if hero and hero.target then
			a.targets = self:targetsFor(s, hero.target)
		end
		table.insert(out, a)
	end
	table.insert(out, { kind = "battle" })
	return out
end

-- The match as seat s may see it (the other hands are just counts).
function MatchEngine:viewFor(s)
	local v = {
		you = s,
		team = s and self.seats[s] and self.seats[s].team or 1,
		teamMode = self.teamMode,
		width = self.width,
		lanesPerSeat = LANES,
		rows = ROWS,
		shiftCost = SHIFT_COST,
		current = self.current,
		turn = self.turn,
		over = self.over,
		winner = self.winner,
		seats = {},
		teams = {},
		lanes = {},
		hand = {},
	}
	for t = 1, 2 do
		v.teams[t] = { hp = self.teams[t].hp, maxHp = self.teams[t].maxHp, seats = table.clone(self.teams[t].seats) }
		v.lanes[t] = {}
		for i, l in ipairs(self.lanes[t]) do
			v.lanes[t][i] = {
				owner = l.owner,
				landscape = l.landscape,
				scrap = l.scrap,
				creature = l.creature and self:snapshot(l.creature), -- Front row
				back = l.back and self:snapshot(l.back), -- Back row
				building = l.building and self:snapshot(l.building),
			}
		end
	end
	for i, seat in ipairs(self.seats) do
		v.seats[i] = {
			name = seat.name,
			team = seat.team,
			slot = seat.slot,
			hero = seat.hero,
			family = seat.family,
			magic = seat.magic,
			maxMagic = seat.maxMagic,
			handCount = #seat.hand,
			deckCount = #seat.deck,
			discardCount = #seat.discard,
			dealt = seat.dealt,
			bigMoveUsed = seat.bigMoveUsed,
			bigMoveReady = self:bigMoveReady(i),
			lanes = self:lanesOf(i),
		}
	end
	if s and self.seats[s] then
		for _, e in ipairs(self.seats[s].hand) do
			table.insert(v.hand, { uid = e.uid, id = e.id, cost = self:costOf(s, e), baseCost = card(e.id).cost })
		end
	end
	return v
end

return MatchEngine

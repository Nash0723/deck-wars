-- Deck Wars match engine (tile board).
-- Pure game rules with no Roblox parts or GUIs, so the server runs it and tests can too.
--
-- The board is a grid of tiles, CardData.Cols wide (4 lanes) and CardData.Rows deep (6).
-- Rows are counted from player 1's side: rows 1-3 are player 1's half (Backline, Midline,
-- Frontline), rows 4-6 player 2's (Frontline, Midline, Backline).
-- Creatures are summoned on their owner's Backline and Midline, walk 1 tile (2 if Fast) up, down,
-- left or right, and attack an enemy on one of the 8 tiles around them (2 tiles away if Ranged).
-- Behind each Backline is a building row with one slot per lane: row 0 for player 1 and
-- row Rows + 1 for player 2. Buildings stand there and help a lane (their column) or a row.
-- Creatures never walk into a building row, but enemies close enough can attack a building.
--
-- Basic use:
--   local match = MatchEngine.new({ deck = {...}, hero = "bonk", family = "Snack" }, { ... }, seed)
--   match:act(1, { kind = "play", handUid = 12, tile = { col = 3, row = 1 } })
--   match:act(1, { kind = "move", uid = 40, to = { col = 3, row = 2 } })
--   match:act(1, { kind = "attack", uid = 40, target = { col = 3, row = 4 } }) -- or hero = true
--   match:act(1, { kind = "defend", uid = 40 })
--   match:act(1, { kind = "chant", uid = 40, target = { col = 2, row = 4 } }) -- target only for aimed chants
--   match:act(1, { kind = "endturn" })
--
-- Creature commands: each turn a creature can walk (or swap places with one of your creatures
-- next to it, by "moving" onto it), then do ONE of: Attack, Defend or its family's Chant.
--   local events = match:takeEvents()   -- for animations
--   local view = match:viewFor(1)       -- what player 1 is allowed to see

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local Rng = req("Rng")

local COLS = CardData.Cols
local ROWS = CardData.Rows
local HOME_ROWS = CardData.HomeRows
local SUMMON_ROWS = CardData.SummonRows
local HERO_ROWS = CardData.HeroAttackRows or 1 -- how many of the enemy's back rows a creature can hit the hero from
local KEYWORDS = CardData.Keywords
local STEPS = { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }
-- Combos and build-up (numbers live in CardData).
local POWER_MAX = CardData.PowerMax or 3
local SANDWICH_BONUS = CardData.SandwichBonus or 1
local SOAK_BONUS = CardData.SoakBonus or 1
local ZAP_BONUS = CardData.ZapBonus or 2
local PACK_MAX = CardData.PackMax or 2
local SCRAP_MAX = CardData.ScrapMax or 3
local SCRAP_GAIN = CardData.ScrapGain or 1

local MatchEngine = {}
MatchEngine.__index = MatchEngine

local function other(p)
	return 3 - p
end

local function key(col, row)
	return col * 16 + row
end

local function onBoard(col, row)
	return type(col) == "number" and type(row) == "number" and col >= 1 and col <= COLS and row >= 1 and row <= ROWS and col % 1 == 0 and row % 1 == 0
end

local function tileOk(t)
	return type(t) == "table" and onBoard(t.col, t.row)
end

-- The board plus both building rows (row 0 and row ROWS + 1).
local function inGrid(col, row)
	return type(col) == "number" and type(row) == "number" and col >= 1 and col <= COLS and row >= 0 and row <= ROWS + 1 and col % 1 == 0 and row % 1 == 0
end

-- Player p's building row: 0 behind player 1's Backline, ROWS + 1 behind player 2's.
local function buildRowOf(p)
	return p == 1 and 0 or ROWS + 1
end

-- Which of player p's rows `row` is: 1 = Backline, 2 = Midline, 3 = Frontline (nil if not p's half).
local function lineOf(p, row)
	if p == 1 then
		if row >= 1 and row <= HOME_ROWS then
			return row
		end
	elseif row > ROWS - HOME_ROWS and row <= ROWS then
		return ROWS + 1 - row
	end
	return nil
end
local LINE_INDEX = { Backline = 1, Midline = 2, Frontline = 3 }

-- Distance in tiles, counting diagonal steps as 1 (so "next to" means the 8 tiles around).
local function dist(a, b)
	return math.max(math.abs(a.col - b.col), math.abs(a.row - b.row))
end

local function inHalf(p, row)
	if p == 1 then
		return row <= HOME_ROWS
	end
	return row > ROWS - HOME_ROWS
end

local function inSummonRows(p, row)
	if p == 1 then
		return row <= SUMMON_ROWS
	end
	return row > ROWS - SUMMON_ROWS
end

local function backRowOf(p)
	return p == 1 and 1 or ROWS
end

-- Can player p's creature standing on `row` attack the enemy hero?
local function canHitHeroFrom(p, row)
	if p == 1 then
		return row > ROWS - HERO_ROWS
	end
	return row <= HERO_ROWS
end

local function deepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in pairs(value) do
		copy[deepCopy(k, seen)] = deepCopy(v, seen)
	end
	return setmetatable(copy, getmetatable(value))
end

local function dominantFamily(deck)
	local counts = {}
	for _, id in ipairs(deck) do
		local d = CardData.Cards[id]
		if d and d.type == "Creature" then
			counts[d.family] = (counts[d.family] or 0) + 1
		end
	end
	local best, bestN = CardData.Families[1], -1
	for _, fam in ipairs(CardData.Families) do
		if (counts[fam] or 0) > bestN then
			best, bestN = fam, counts[fam] or 0
		end
	end
	return best
end

MatchEngine.other = other
MatchEngine.dist = dist
MatchEngine.buildRowOf = buildRowOf
MatchEngine.lineOf = lineOf
MatchEngine.inGrid = inGrid
MatchEngine.inHalf = inHalf
MatchEngine.backRowOf = backRowOf
MatchEngine.canHitHeroFrom = canHitHeroFrom

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function MatchEngine.new(setupA, setupB, seed)
	local self = setmetatable({}, MatchEngine)
	self.rng = Rng.new(seed)
	self.nextUid = 0
	self.events = {}
	self.silent = false
	self.turn = 0
	self.current = 1
	self.over = false
	self.winner = nil -- 1, 2 or 0 for a draw
	self.grid = {}
	self.terrain = {}
	self.scrap = {} -- [col][row] = how much Scrap lies on the tile (Junk picks it up)
	for col = 1, COLS do
		self.grid[col] = {}
		self.terrain[col] = {}
		self.scrap[col] = {}
	end
	self.players = {}
	for p, setup in ipairs({ setupA, setupB }) do
		local deck = table.clone(setup.deck)
		self.rng:shuffle(deck)
		self.players[p] = {
			hero = setup.hero or "bonk",
			family = setup.family or (type(setup.themes) == "table" and setup.themes[1]) or dominantFamily(setup.deck),
			hp = CardData.HeroMaxHp,
			maxEnergy = 0,
			energy = 0,
			deck = deck,
			hand = {},
			discard = {},
			lost = {}, -- ids of creatures that popped, newest last
			fatigue = 0,
			dealt = 0, -- damage dealt to enemies, charges the Big Move
			bigMoveUsed = false,
			played = {}, -- [family] = cards of that family played this turn (for Combo)
		}
	end
	-- Terrain: every lane of a player's half has the terrain the deck picked for it
	-- (setup.lanes, left to right as seen from that player's chair). Without lanes, all four
	-- lanes are the deck's own family. A creature on its family's terrain gets +1 attack.
	for p, setup in ipairs({ setupA, setupB }) do
		local pl = self.players[p]
		pl.themes = {}
		for _, fam in ipairs(type(setup.themes) == "table" and setup.themes or { pl.family }) do
			if CardData.Terrains[fam] then
				table.insert(pl.themes, fam)
			end
		end
		if #pl.themes == 0 then
			pl.themes = { pl.family }
		end
		pl.lanes = {}
		for i = 1, COLS do
			local fam = type(setup.lanes) == "table" and setup.lanes[i] or nil
			pl.lanes[i] = CardData.Terrains[fam] and fam or pl.family
		end
		for col = 1, COLS do
			local lane = p == 1 and pl.lanes[col] or pl.lanes[COLS + 1 - col]
			for row = 1, ROWS do
				if lineOf(p, row) then
					self.terrain[col][row] = lane
				end
			end
		end
	end
	self:emit({ type = "start", terrain = self:terrainCopy() })
	for p = 1, 2 do
		for _ = 1, (p == 1 and 4 or 5) do
			self:draw(p)
		end
	end
	-- A bonus card for the second player: off unless CardData.SecondPlayerCard names one.
	-- (setupB.extraCard can force it: true = that card or a Spare Battery, false = none, or a card id.)
	local bonus = setupB.extraCard
	if bonus == nil then
		bonus = CardData.SecondPlayerCard
	elseif bonus == true then
		bonus = CardData.SecondPlayerCard or "spare_battery"
	end
	if type(bonus) == "string" then
		self:addToHand(2, bonus)
	end
	self:startTurn(1)
	return self
end

-- A copy for the bot to try moves on. Pass a seed so the bot can't see the real dice rolls.
function MatchEngine:clone(seed)
	local c = setmetatable({}, MatchEngine)
	c.rng = Rng.new(seed or self.rng.state)
	c.nextUid = self.nextUid
	c.events = {}
	c.silent = true
	c.turn = self.turn
	c.current = self.current
	c.over = self.over
	c.winner = self.winner
	c.grid = {}
	c.terrain = {}
	c.scrap = {}
	for col = 1, COLS do
		c.scrap[col] = table.clone(self.scrap[col])
		local srcCol, dstCol = self.grid[col], {}
		for row = 0, ROWS + 1 do
			local u = srcCol[row]
			if u then
				local nu = table.clone(u)
				nu.keywords = table.clone(u.keywords)
				dstCol[row] = nu
			end
		end
		c.grid[col] = dstCol
		c.terrain[col] = table.clone(self.terrain[col])
	end
	c.players = {}
	for p = 1, 2 do
		local pl = self.players[p]
		local np = table.clone(pl)
		np.deck = table.clone(pl.deck)
		np.hand = {}
		for i, e in ipairs(pl.hand) do
			np.hand[i] = table.clone(e)
		end
		np.discard = table.clone(pl.discard)
		np.lost = table.clone(pl.lost)
		np.played = table.clone(pl.played)
		np.themes = table.clone(pl.themes)
		np.lanes = table.clone(pl.lanes)
		c.players[p] = np
	end
	return c
end

-- A full deep copy (slower, used by tests to check clone() copies everything that matters).
function MatchEngine:deepClone()
	local c = deepCopy(self)
	c.events = {}
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

function MatchEngine:terrainCopy()
	local t = {}
	for col = 1, COLS do
		t[col] = table.clone(self.terrain[col])
	end
	return t
end

---------------------------------------------------------------------------
-- Cards in hand
---------------------------------------------------------------------------

function MatchEngine:addToHand(p, id, costMod, costOverride)
	local pl = self.players[p]
	if #pl.hand >= CardData.MaxHand then
		table.insert(pl.discard, id)
		self:emit({ type = "burn", player = p, card = id })
		return nil
	end
	local entry = { uid = self:uid(), id = id, costMod = costMod or 0, costOverride = costOverride }
	table.insert(pl.hand, entry)
	self:emit({ type = "draw", player = p, card = id, uid = entry.uid })
	return entry
end

function MatchEngine:draw(p)
	local pl = self.players[p]
	if #pl.deck == 0 then
		pl.fatigue += 1
		self:emit({ type = "fatigue", player = p, amount = pl.fatigue })
		self:damageHero(p, pl.fatigue, nil)
		return
	end
	local id = table.remove(pl.deck)
	self:addToHand(p, id)
end

function MatchEngine:findHand(p, uid)
	for i, entry in ipairs(self.players[p].hand) do
		if entry.uid == uid then
			return entry, i
		end
	end
	return nil
end

function MatchEngine:countOnBoard(p, id)
	local n = 0
	for _, u in ipairs(self:allUnits()) do
		if u.owner == p and u.id == id and u.hp > 0 then
			n += 1
		end
	end
	return n
end

function MatchEngine:costOf(p, entry)
	local def = CardData.get(entry.id)
	local cost = entry.costOverride or def.cost
	cost += entry.costMod
	if entry.id == "scrapheap_titan" then
		cost -= math.min(3, self:scrapTotal())
	end
	if def.type == "Spell" then
		cost += self:countOnBoard(other(p), "mall_cop_phantom")
	end
	return math.max(0, cost)
end

---------------------------------------------------------------------------
-- The board
---------------------------------------------------------------------------

function MatchEngine:at(col, row)
	if not inGrid(col, row) then
		return nil
	end
	return self.grid[col][row]
end

function MatchEngine:isEmpty(col, row)
	return onBoard(col, row) and self.grid[col][row] == nil
end

-- Every creature and building, always in the same order (row by row, building rows included).
function MatchEngine:allUnits(kind)
	local list = {}
	for row = 0, ROWS + 1 do
		for col = 1, COLS do
			local u = self.grid[col][row]
			if u and (kind == nil or u.kind == kind) then
				table.insert(list, u)
			end
		end
	end
	return list
end

function MatchEngine:unitsOf(p, kind)
	local list = {}
	for _, u in ipairs(self:allUnits(kind)) do
		if u.owner == p then
			table.insert(list, u)
		end
	end
	return list
end

function MatchEngine:findUnit(uid)
	if type(uid) ~= "number" then
		return nil
	end
	for col = 1, COLS do
		for row = 0, ROWS + 1 do
			local u = self.grid[col][row]
			if u and u.uid == uid then
				return u
			end
		end
	end
	return nil
end

-- The 8 tiles around a tile (fewer at the edges).
function MatchEngine:neighbors(col, row)
	local list = {}
	for dr = -1, 1 do
		for dc = -1, 1 do
			if (dc ~= 0 or dr ~= 0) and onBoard(col + dc, row + dr) then
				table.insert(list, { col = col + dc, row = row + dr })
			end
		end
	end
	return list
end

function MatchEngine:emptyNeighbors(col, row)
	local list = {}
	for _, n in ipairs(self:neighbors(col, row)) do
		if self.grid[n.col][n.row] == nil then
			table.insert(list, n)
		end
	end
	return list
end

-- How many units with this card id, owned by `owner`, stand next to the tile.
function MatchEngine:countNear(col, row, owner, id)
	local n = 0
	for _, t in ipairs(self:neighbors(col, row)) do
		local u = self.grid[t.col][t.row]
		if u and u.owner == owner and u.id == id and u.hp > 0 then
			n += 1
		end
	end
	return n
end

-- Player p's building with this card id standing in lane `col` (nil if none).
function MatchEngine:laneBuilding(p, col, id)
	local b = self.grid[col] and self.grid[col][buildRowOf(p)]
	if b and b.kind == "building" and b.owner == p and b.id == id and b.hp > 0 then
		return b
	end
	return nil
end

-- How many of player p's buildings with this id stand anywhere in their building row.
function MatchEngine:buildingCount(p, id)
	local n = 0
	for col = 1, COLS do
		if self:laneBuilding(p, col, id) then
			n += 1
		end
	end
	return n
end

-- Does a row building of c's owner reach c? (c must stand on that row of its owner's half.)
function MatchEngine:rowBuildingHelps(c, id)
	local def = CardData.Cards[id]
	return lineOf(c.owner, c.row) == LINE_INDEX[def.area] and self:buildingCount(c.owner, id) > 0
end

-- The enemy creature nearest to player p's building row in lane `col`, looking up the lane.
function MatchEngine:firstEnemyInLane(p, col)
	local r0, r1, stepBy = 1, ROWS, 1
	if p == 2 then
		r0, r1, stepBy = ROWS, 1, -1
	end
	for row = r0, r1, stepBy do
		local u = self.grid[col][row]
		if u and u.owner ~= p and u.kind == "creature" and u.hp > 0 then
			return u
		end
	end
	return nil
end

-- Empty tiles of player p's half in lane `col`, Backline first.
function MatchEngine:emptyLaneTiles(p, col)
	local list = {}
	for line = 1, HOME_ROWS do
		local row = p == 1 and line or ROWS + 1 - line
		if self:isEmpty(col, row) then
			table.insert(list, { col = col, row = row })
		end
	end
	return list
end

function MatchEngine:placeUnit(u, col, row)
	assert(self.grid[col][row] == nil, "tile is taken")
	u.col = col
	u.row = row
	self.grid[col][row] = u
end

function MatchEngine:removeUnit(u)
	if self.grid[u.col] and self.grid[u.col][u.row] == u then
		self.grid[u.col][u.row] = nil
	end
end

---------------------------------------------------------------------------
-- Creature stats (with terrain and buildings counted in)
---------------------------------------------------------------------------

function MatchEngine:hasKeyword(c, kw)
	if c.kind ~= "creature" then
		return false
	end
	if c.keywords[kw] then
		return true
	end
	-- Pack is the Critter family's rule: every Critter has it.
	if kw == "Pack" and c.family == "Critter" then
		return true
	end
	if kw == "Sturdy" then
		if c.family == "Critter" and self:countNear(c.col, c.row, c.owner, "sergeant_snail") > 0 then
			return true
		end
		return self:rowBuildingHelps(c, "bouncy_castle") -- Frontline
	elseif kw == "Haunt" then
		return self:laneBuilding(c.owner, c.col, "spooky_crypt") ~= nil
	elseif kw == "Fast" then
		return self:laneBuilding(c.owner, c.col, "wind_turbine") ~= nil
	end
	return false
end

function MatchEngine:attackOf(c)
	if c.kind ~= "creature" then
		return 0
	end
	local a = c.atk
	if self.terrain[c.col][c.row] == c.family then
		a += 1
	end
	if self:laneBuilding(c.owner, c.col, "charging_station") then
		a += c.family == "Robo" and 2 or 1
	end
	a += c.power or 0
	if self:hasKeyword(c, "Pack") then
		a += math.min(PACK_MAX, self:packCount(c))
	end
	a -= 2 * self:countNear(c.col, c.row, other(c.owner), "fog_bank")
	return math.max(0, a)
end

-- How many friendly Critters stand next to c (for Pack).
function MatchEngine:packCount(c)
	local n = 0
	for _, t in ipairs(self:neighbors(c.col, c.row)) do
		local f = self.grid[t.col][t.row]
		if f and f ~= c and f.owner == c.owner and f.kind == "creature" and f.family == "Critter" and f.hp > 0 then
			n += 1
		end
	end
	return n
end

function MatchEngine:speedOf(c)
	return self:hasKeyword(c, "Fast") and 2 or 1
end

function MatchEngine:rangeOf(c)
	return self:hasKeyword(c, "Ranged") and 2 or 1
end

function MatchEngine:canMove(u)
	return u.kind == "creature" and u.hp > 0 and u.owner == self.current and not u.moved and not u.attacked and not u.sick
end

function MatchEngine:canAttack(u)
	return u.kind == "creature" and u.hp > 0 and u.owner == self.current and not u.attacked and not u.sick
end

-- Tiles a creature can walk to this turn. Returns a map (key -> path) and a list of
-- { col, row, path } in a fixed order. A path is the tiles stepped on, ending at the goal.
function MatchEngine:reachable(u)
	local map, list = {}, {}
	local seen = { [key(u.col, u.row)] = true }
	local frontier = { { col = u.col, row = u.row, path = {} } }
	for _ = 1, self:speedOf(u) do
		local nextFrontier = {}
		for _, node in ipairs(frontier) do
			for _, d in ipairs(STEPS) do
				local col, row = node.col + d[1], node.row + d[2]
				local k = key(col, row)
				if not seen[k] and self:isEmpty(col, row) then
					seen[k] = true
					local path = table.clone(node.path)
					table.insert(path, { col = col, row = row })
					map[k] = path
					local entry = { col = col, row = row, path = path }
					table.insert(list, entry)
					table.insert(nextFrontier, entry)
				end
			end
		end
		frontier = nextFrontier
	end
	return map, list
end

-- Enemies this creature can attack from where it stands, and whether it can hit the hero.
function MatchEngine:attackTargets(u)
	local list = {}
	local range = self:rangeOf(u)
	-- (the rows reach into the enemy's building row too: buildings can be hit)
	for row = math.max(0, u.row - range), math.min(ROWS + 1, u.row + range) do
		for col = math.max(1, u.col - range), math.min(COLS, u.col + range) do
			local t = self.grid[col][row]
			if t and t.owner ~= u.owner and t.hp > 0 then
				table.insert(list, t)
			end
		end
	end
	return list, canHitHeroFrom(u.owner, u.row)
end

-- Tiles where player p may summon a creature: empty tiles on their Backline and Midline,
-- plus their whole half of a lane with a Bunny Burrow.
function MatchEngine:canSummonAt(p, col, row)
	if not self:isEmpty(col, row) then
		return false
	end
	if inSummonRows(p, row) then
		return true
	end
	return inHalf(p, row) and self:laneBuilding(p, col, "bunny_burrow") ~= nil
end

-- Buildings go in your building row: an empty slot, or one of your own buildings (it is
-- knocked down and replaced).
function MatchEngine:canBuildAt(p, col, row)
	if not inGrid(col, row) or row ~= buildRowOf(p) then
		return false
	end
	local there = self.grid[col][row]
	return there == nil or (there.owner == p and there.kind == "building")
end

function MatchEngine:summonTiles(p)
	local list = {}
	for row = 1, ROWS do
		for col = 1, COLS do
			if self:canSummonAt(p, col, row) then
				table.insert(list, { col = col, row = row })
			end
		end
	end
	return list
end

function MatchEngine:buildTiles(p)
	local list = {}
	local row = buildRowOf(p)
	for col = 1, COLS do
		if self:canBuildAt(p, col, row) then
			table.insert(list, { col = col, row = row })
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Making creatures and buildings
---------------------------------------------------------------------------

function MatchEngine:spawn(p, col, row, id, opts)
	local def = CardData.get(id)
	local u = {
		uid = self:uid(),
		id = id,
		kind = "creature",
		family = def.family,
		owner = p,
		col = col,
		row = row,
		atk = def.atk,
		hp = def.hp,
		maxHp = def.hp,
		keywords = table.clone(def.keywords),
		chargeLeft = def.charge or 0,
		power = 0, -- +1 attack each (Charge, Power Up, Sweet Tooth, Grudge, Upload)
		soaked = false, -- takes extra damage from the next hit
		bubble = false,
		token = def.token or false,
		sick = not def.keywords.Zoom, -- new creatures wait a turn unless they have Zoom
		moved = false,
		attacked = false, -- true once it has used its command (attack, defend or chant) this turn
		defending = false,
	}
	if opts and opts.hp then
		u.hp = math.clamp(opts.hp, 1, u.maxHp)
	end
	self:placeUnit(u, col, row)
	self:emit({
		type = "spawn",
		player = p,
		uid = u.uid,
		card = id,
		col = col,
		row = row,
		fromHand = opts and opts.fromHand or nil,
		hp = u.hp < u.maxHp and u.hp or nil,
		raised = opts and opts.raised or nil,
	})
	self:arrive(u)
	return u
end

function MatchEngine:build(p, col, row, id)
	local def = CardData.get(id)
	local old = self.grid[col][row]
	if old then
		-- Building over one of your own buildings knocks the old one down first.
		self:removeUnit(old)
		old.hp = 0
		table.insert(self.players[p].discard, old.id)
		self:emit({ type = "destroyed", player = p, uid = old.uid, col = col, row = row, replaced = true })
		self:buildingRubble(old)
	end
	local u = {
		uid = self:uid(),
		id = id,
		kind = "building",
		family = def.family,
		owner = p,
		col = col,
		row = row,
		atk = 0,
		hp = def.hp,
		maxHp = def.hp,
		keywords = {},
		chargeLeft = 0,
		power = 0,
		soaked = false,
		bubble = false,
		token = false,
		sick = false,
		moved = true,
		attacked = true,
		defending = false,
	}
	self:placeUnit(u, col, row)
	self:emit({ type = "build", player = p, uid = u.uid, card = id, col = col, row = row })
	if id == "bunny_burrow" then
		local spot = self:emptyLaneTiles(p, col)[1]
		if spot then
			self:spawn(p, spot.col, spot.row, "pigeon")
		end
	end
	return u
end

-- A building that breaks leaves Scrap on the Backline tile in front of it.
function MatchEngine:buildingRubble(b)
	local row = b.owner == 1 and 1 or ROWS
	if onBoard(b.col, row) then
		self:dropScrap(b.col, row, 1)
	end
end

function MatchEngine:giveKeyword(c, kw)
	c.keywords[kw] = true
	if kw == "Zoom" then
		c.sick = false
	end
	self:emit({ type = "buff", uid = c.uid, keyword = kw })
end

function MatchEngine:buff(c, atk, hp)
	c.atk += atk
	c.maxHp += hp
	c.hp += hp
	self:emit({ type = "buff", uid = c.uid, atk = atk, hp = hp })
end

---------------------------------------------------------------------------
-- Combos and build-up: Power, Soak and Scrap
---------------------------------------------------------------------------

-- Gives a creature Power (+1 attack each, up to POWER_MAX). Returns how much it really got.
function MatchEngine:addPower(c, amount, reason)
	if not c or c.kind ~= "creature" or c.hp <= 0 or amount <= 0 then
		return 0
	end
	local before = c.power or 0
	c.power = math.min(POWER_MAX, before + amount)
	local got = c.power - before
	if got > 0 then
		self:emit({ type = "power", uid = c.uid, amount = got, power = c.power, reason = reason })
	end
	return got
end

-- Soaks an enemy creature: it takes SOAK_BONUS more damage from the next hit.
function MatchEngine:soak(c)
	if c and c.kind == "creature" and c.hp > 0 and not c.soaked then
		c.soaked = true
		self:emit({ type = "soak", uid = c.uid })
	end
end

function MatchEngine:scrapAt(col, row)
	return (self.scrap[col] and self.scrap[col][row]) or 0
end

function MatchEngine:scrapTotal()
	local n = 0
	for col = 1, COLS do
		for _, v in pairs(self.scrap[col]) do
			n += v
		end
	end
	return n
end

-- Leaves Scrap on a tile (a popped Junk creature or building).
function MatchEngine:dropScrap(col, row, amount)
	local cur = self:scrapAt(col, row)
	local new = math.min(SCRAP_MAX, cur + amount)
	if new > cur then
		self.scrap[col][row] = new
		self:emit({ type = "scrap", col = col, row = row, total = new, added = new - cur })
	end
end

-- A Junk creature picks up all the Scrap on these tiles: +SCRAP_GAIN/+SCRAP_GAIN for each.
function MatchEngine:pickUpScrap(u, tiles)
	if u.kind ~= "creature" or u.family ~= "Junk" or u.hp <= 0 then
		return 0
	end
	local total, from = 0, {}
	for _, t in ipairs(tiles) do
		local n = self:scrapAt(t.col, t.row)
		if n > 0 then
			total += n
			self.scrap[t.col][t.row] = nil
			table.insert(from, { col = t.col, row = t.row, amount = n })
		end
	end
	if total > 0 then
		local gain = total * SCRAP_GAIN
		u.atk += gain
		u.maxHp += gain
		u.hp += gain
		self:emit({ type = "scrapPick", uid = u.uid, amount = gain, from = from, atk = self:attackOf(u), hp = u.hp })
	end
	return total
end

-- Called when a creature arrives on a tile (summoned, walked, swapped, pushed or thrown by
-- Total Chaos). `path` lists the tiles it walked over on the way. Junk picks up Scrap.
function MatchEngine:arrive(u, path)
	if u.kind ~= "creature" or u.family ~= "Junk" then
		return
	end
	local tiles = {}
	if path then
		for _, t in ipairs(path) do
			table.insert(tiles, { col = t.col, row = t.row })
		end
	end
	table.insert(tiles, { col = u.col, row = u.row })
	if u.id == "rusty_shopping_cart" then
		for _, n in ipairs(self:neighbors(u.col, u.row)) do
			table.insert(tiles, n)
		end
	end
	self:pickUpScrap(u, tiles)
end

-- Moves a creature up to `steps` tiles back toward its owner's side (stops at anything in the way).
function MatchEngine:push(u, steps)
	local dir = u.owner == 1 and -1 or 1
	local row = u.row
	for _ = 1, steps do
		if self:isEmpty(u.col, row + dir) then
			row += dir
		else
			break
		end
	end
	if row ~= u.row then
		local from = { col = u.col, row = u.row }
		self:removeUnit(u)
		self:placeUnit(u, u.col, row)
		self:emit({ type = "push", uid = u.uid, from = from, to = { col = u.col, row = row } })
		self:arrive(u)
	end
end

---------------------------------------------------------------------------
-- Damage, healing, popping
---------------------------------------------------------------------------

-- source = { player = p, creature = c?, reflect = bool? }
function MatchEngine:damageUnit(u, amount, source)
	if amount <= 0 or u.hp <= 0 then
		return 0
	end
	local soakHit, zapHit = nil, nil
	if u.kind == "creature" then
		if u.bubble then
			u.bubble = false
			self:emit({ type = "bubble", uid = u.uid })
			return 0
		end
		if u.soaked then
			-- Soaked: the next hit deals more (Zap creatures even more), then it dries off.
			u.soaked = false
			soakHit = true
			amount += SOAK_BONUS
			local src = source and source.creature
			if src and src.kind == "creature" and self:hasKeyword(src, "Zap") then
				amount += ZAP_BONUS
				zapHit = true
			end
		end
		if self:hasKeyword(u, "Sturdy") then
			amount -= 1
		end
		if u.defending then
			amount -= CardData.DefendArmor or 1
		end
		if amount <= 0 then
			self:emit({ type = "blocked", uid = u.uid, soaked = soakHit })
			return 0
		end
	end
	u.hp -= amount
	self:emit({ type = "damage", uid = u.uid, amount = amount, hp = u.hp, soaked = soakHit, zap = zapHit })
	if source and source.player and source.player ~= u.owner then
		self.players[source.player].dealt += amount
	end
	if u.id == "burrito_bouncer" and source and source.creature and not source.reflect and source.creature.hp > 0 then
		self:damageUnit(source.creature, 1, { player = u.owner, creature = u, reflect = true })
	end
	return amount
end

-- Destroys a unit outright (Pothole, Junk King, Mega Blender). It pops in resolvePops.
function MatchEngine:destroyUnit(u)
	if u.hp > 0 then
		u.hp = 0
		self:emit({ type = "damage", uid = u.uid, amount = 99, hp = 0 })
	end
end

function MatchEngine:damageHero(p, amount, sourcePlayer)
	if amount <= 0 then
		return
	end
	local pl = self.players[p]
	pl.hp -= amount
	self:emit({ type = "heroDamage", player = p, amount = amount, hp = pl.hp })
	if sourcePlayer and sourcePlayer ~= p then
		self.players[sourcePlayer].dealt += amount
	end
end

function MatchEngine:healHero(p, amount)
	local pl = self.players[p]
	local before = pl.hp
	pl.hp = math.min(CardData.HeroMaxHp, pl.hp + amount)
	if pl.hp > before then
		self:emit({ type = "heroHeal", player = p, amount = pl.hp - before, hp = pl.hp })
	end
end

function MatchEngine:healCreature(c, amount)
	if c.hp <= 0 then
		return
	end
	local before = c.hp
	c.hp = math.min(c.maxHp, c.hp + amount)
	if c.hp > before then
		self:emit({ type = "heal", uid = c.uid, amount = c.hp - before, hp = c.hp })
	end
	-- Sweet Tooth: Snacks get Power from every heal, even at full health.
	if c.kind == "creature" and c.family == "Snack" and amount > 0 then
		self:addPower(c, c.id == "hot_sauce_imp" and 2 or 1, "sweet")
	end
end

function MatchEngine:resolvePops()
	local again = true
	while again do
		again = false
		-- Find everything at 0 health first, so auras (like the Spooky Crypt) still count.
		local dying = {}
		for _, u in ipairs(self:allUnits()) do
			if u.hp <= 0 then
				table.insert(dying, { unit = u, haunt = self:hasKeyword(u, "Haunt") })
			end
		end
		for _, d in ipairs(dying) do
			again = true
			local u = d.unit
			local p = u.owner
			local pl = self.players[p]
			self:removeUnit(u)
			if u.kind == "building" then
				table.insert(pl.discard, u.id)
				self:emit({ type = "destroyed", player = p, uid = u.uid, col = u.col, row = u.row })
				self:buildingRubble(u)
			else
				-- A raised creature only fades away when it pops again: no Ghost, no pop effects.
				local faded = (u.raised and CardData.RaisedFades) or nil
				self:emit({ type = "pop", player = p, uid = u.uid, col = u.col, row = u.row, faded = faded })
				if not u.token then
					table.insert(pl.discard, u.id)
					table.insert(pl.lost, u.id)
				end
				if not faded then
					-- Scrap: popped Junk leaves Scrap on its tile (Tin Can Tom leaves 2).
					if u.family == "Junk" and not u.token then
						self:dropScrap(u.col, u.row, u.id == "tin_can_tom" and 2 or 1)
					end
					-- Upload: a Robo's Power jumps to a friendly Robo next to it.
					if u.family == "Robo" and (u.power or 0) > 0 then
						local best = nil
						for _, n in ipairs(self:neighbors(u.col, u.row)) do
							local r = self.grid[n.col][n.row]
							if r and r.owner == p and r.kind == "creature" and r.family == "Robo" and r.hp > 0 and r.power < POWER_MAX then
								if not best or r.power < best.power then
									best = r
								end
							end
						end
						if best then
							self:emit({ type = "upload", from = u.uid, to = best.uid, col = u.col, row = u.row })
							self:addPower(best, u.power, "upload")
						end
					end
					for _, w in ipairs(self:unitsOf(p, "creature")) do
						if w.hp > 0 then
							if w.id == "mushroom_witch" then
								self:damageHero(other(p), 1, p)
							end
							-- Grudge: gets 1 Power whenever another friendly creature pops.
							if self:hasKeyword(w, "Grudge") then
								self:addPower(w, 1, "grudge")
							end
						end
					end
					if d.haunt and self:isEmpty(u.col, u.row) then
						self:spawn(p, u.col, u.row, "ghost")
					end
				end
			end
		end
	end
	self:checkWin()
end

function MatchEngine:checkWin()
	if self.over then
		return
	end
	local dead1 = self.players[1].hp <= 0
	local dead2 = self.players[2].hp <= 0
	if dead1 or dead2 then
		self.over = true
		if dead1 and dead2 then
			self.winner = 0
		else
			self.winner = dead1 and 2 or 1
		end
		self:emit({ type = "gameOver", winner = self.winner })
	end
end

---------------------------------------------------------------------------
-- Turns
---------------------------------------------------------------------------

-- What a creature or building does at the start of its owner's turn.
function MatchEngine:startOfTurnAbility(p, u)
	local enemy = other(p)
	local id = u.id
	if id == "stormlord_nimbus" or id == "omega_microwave" then
		local targets = self:unitsOf(enemy, "creature")
		if #targets > 0 then
			self:emit({ type = "ability", uid = u.uid })
			local dmg = id == "omega_microwave" and 3 or 1
			for _, e in ipairs(targets) do
				self:damageUnit(e, dmg, { player = p, creature = u })
			end
		end
	elseif id == "microwave_mage" then
		local targets = {}
		for _, e in ipairs(self:unitsOf(enemy, "creature")) do
			if dist(u, e) == 1 then
				table.insert(targets, e)
			end
		end
		if #targets > 0 then
			self:emit({ type = "ability", uid = u.uid })
			for _, e in ipairs(targets) do
				self:damageUnit(e, 1, { player = p, creature = u })
			end
		end
	elseif id == "spiked_fence" then
		-- Fires a spike up its lane at the nearest enemy creature.
		local e = self:firstEnemyInLane(p, u.col)
		if e then
			self:emit({ type = "shot", uid = u.uid, target = e.uid })
			self:damageUnit(e, 1, { player = p })
		end
	elseif id == "wind_turbine" then
		local e = self:firstEnemyInLane(p, u.col)
		if e and not e.soaked then
			self:emit({ type = "ability", uid = u.uid })
			self:soak(e)
		end
	elseif id == "snack_bar" or id == "disco_cactus" then
		-- Snack Bar heals your creatures in its lane; Disco Cactus helps your Midline (a row).
		local friends = {}
		for _, f in ipairs(self:unitsOf(p, "creature")) do
			if (id == "snack_bar" and f.col == u.col) or (id == "disco_cactus" and lineOf(p, f.row) == 2) then
				table.insert(friends, f)
			end
		end
		if #friends > 0 then
			self:emit({ type = "ability", uid = u.uid })
			local boost = false
			if id == "disco_cactus" then
				boost = self.rng:chance(0.5)
				self:emit({ type = "roll", source = u.uid, result = boost and "+1 attack" or "heal 2" })
			end
			for _, f in ipairs(friends) do
				if boost then
					self:buff(f, 1, 0)
				else
					self:healCreature(f, 2)
				end
			end
		end
	elseif id == "scrap_catapult" then
		local e = self:firstEnemyInLane(p, u.col) or self.rng:pick(self:unitsOf(enemy, "creature"))
		if e then
			self:emit({ type = "shot", uid = u.uid, target = e.uid })
			self:damageUnit(e, 2, { player = p })
		end
	elseif id == "haunted_arcade" then
		local spot = self.rng:pick(self:emptyLaneTiles(p, u.col))
		if spot then
			self:emit({ type = "ability", uid = u.uid })
			local ghost = self:spawn(p, spot.col, spot.row, "ghost")
			ghost.keywords.Haunt = true
		end
	elseif id == "rocket_lunchbox" then
		-- A rocket flies up its lane: 3 damage to the first enemy creature in its way, the rest hits the hero.
		self:laneStrike(p, u.col, 3, u)
	end
end

-- Something rolls or flies up lane `col` from player p's side: `amount` damage to the first
-- enemy creature in its way, and whatever that creature can't soak up hits the enemy hero.
-- (Granny Bolt's Strike and the Rocket Lunchbox.)
function MatchEngine:laneStrike(p, col, amount, source)
	local enemy = other(p)
	local pl = self.players[p]
	local first = self:firstEnemyInLane(p, col)
	if source then
		self:emit({ type = "shot", uid = source.uid, target = first and first.uid or "hero", targetPlayer = enemy })
	end
	local dmg = amount
	if first then
		local absorbed = math.min(dmg, math.max(first.hp, 0))
		first.hp -= absorbed
		self:emit({ type = "damage", uid = first.uid, amount = absorbed, hp = first.hp })
		pl.dealt += absorbed
		dmg -= absorbed
		if dmg > 0 and source then
			self:emit({ type = "shot", uid = source.uid, target = "hero", targetPlayer = enemy })
		end
	end
	self:damageHero(enemy, dmg, p)
end

function MatchEngine:startTurn(p)
	if self.over then
		return
	end
	self.turn += 1
	self.current = p
	local pl = self.players[p]
	pl.played = {}
	pl.maxEnergy = math.min(CardData.MaxEnergy, pl.maxEnergy + 1)
	pl.energy = pl.maxEnergy
	if self:buildingCount(p, "lemonade_stand") > 0 then
		pl.energy += 1
	end
	self:emit({ type = "turn", player = p, turn = self.turn, energy = pl.energy, maxEnergy = pl.maxEnergy })
	-- Everyone draws every turn. If CardData.FirstTurnDraw is turned off, the first player skips their very first draw.
	if self.turn > 1 or CardData.FirstTurnDraw then
		self:draw(p)
	end
	self:checkWin()
	if self.over then
		return
	end

	-- Creatures that were already on the board can act again. Charge creatures power up.
	for _, u in ipairs(self:unitsOf(p, "creature")) do
		u.sick = false
		u.moved = false
		u.attacked = false
		if u.defending then
			u.defending = false
			self:emit({ type = "guardDown", uid = u.uid })
		end
		if u.chargeLeft > 0 then
			u.chargeLeft -= 1
			self:addPower(u, 1, "charge")
		end
	end

	-- Start-of-turn abilities, in board order.
	for _, u in ipairs(self:unitsOf(p)) do
		if u.hp > 0 and self.grid[u.col][u.row] == u and not self.over then
			self:startOfTurnAbility(p, u)
		end
	end
	self:resolvePops()
	if not self.over and self.turn > 100 then
		-- Safety valve so a match can never go on forever.
		self.over = true
		local h1, h2 = self.players[1].hp, self.players[2].hp
		self.winner = (h1 > h2 and 1) or (h2 > h1 and 2) or 0
		self:emit({ type = "gameOver", winner = self.winner, reason = "turnLimit" })
	end
end

function MatchEngine:endTurn(p)
	self:emit({ type = "endTurn", player = p })
	self:startTurn(other(p))
end

---------------------------------------------------------------------------
-- Moving and fighting
---------------------------------------------------------------------------

function MatchEngine:moveUnit(p, action)
	local u = self:findUnit(action.uid)
	if not u or u.owner ~= p or u.kind ~= "creature" then
		return false, "Pick one of your creatures"
	end
	if not self:canMove(u) then
		return false, "That creature can't move right now"
	end
	if not tileOk(action.to) then
		return false, "Pick a tile"
	end
	local friend = self:at(action.to.col, action.to.row)
	if friend then
		-- Moving onto one of your creatures next to it: they swap places.
		if not table.find(self:swapTargets(u), friend) then
			return false, "It can't walk there"
		end
		local from, to = { col = u.col, row = u.row }, { col = friend.col, row = friend.row }
		self:removeUnit(u)
		self:removeUnit(friend)
		self:placeUnit(u, to.col, to.row)
		self:placeUnit(friend, from.col, from.row)
		u.moved = true
		self:emit({ type = "swap", uid = u.uid, other = friend.uid, player = p, from = from, to = to })
		self:arrive(u)
		self:arrive(friend)
		return true
	end
	local map = self:reachable(u)
	local path = map[key(action.to.col, action.to.row)]
	if not path then
		return false, "It can't walk there"
	end
	local from = { col = u.col, row = u.row }
	self:removeUnit(u)
	self:placeUnit(u, action.to.col, action.to.row)
	u.moved = true
	self:emit({ type = "move", uid = u.uid, player = p, from = from, path = path })
	self:arrive(u, path)
	return true
end

function MatchEngine:attackWith(p, action)
	local u = self:findUnit(action.uid)
	if not u or u.owner ~= p or u.kind ~= "creature" then
		return false, "Pick one of your creatures"
	end
	if not self:canAttack(u) then
		return false, "That creature can't attack right now"
	end
	local enemy = other(p)
	local atk = self:attackOf(u)
	if action.hero == true then
		if not canHitHeroFrom(p, u.row) then
			return false, "Walk into the enemy's half to hit their hero"
		end
		u.attacked = true
		u.moved = true
		self:emit({ type = "attack", uid = u.uid, player = p, target = "hero", targetPlayer = enemy, amount = atk })
		self:damageHero(enemy, atk, p)
		self:resolvePops()
		return true
	end
	if type(action.target) ~= "table" or not inGrid(action.target.col, action.target.row) then
		return false, "Pick something to attack"
	end
	local target = self:at(action.target.col, action.target.row)
	if not target or target.owner == p or target.hp <= 0 then
		return false, "Pick an enemy to attack"
	end
	local d = dist(u, target)
	if d > self:rangeOf(u) then
		return false, "That's too far away"
	end
	-- Fighters next to each other hit each other at the same time.
	local counter = 0
	if d == 1 and target.kind == "creature" then
		counter = self:attackOf(target)
		if target.defending then
			counter += CardData.DefendCounter or 1
		end
	end
	-- Sandwich: another of your creatures stands right behind the target (in line with the attack).
	local sandwich = self:sandwichPartner(u, target)
	if sandwich then
		atk += SANDWICH_BONUS
	end
	u.attacked = true
	u.moved = true
	self:emit({
		type = "attack",
		uid = u.uid,
		player = p,
		target = target.uid,
		targetPlayer = enemy,
		amount = atk,
		counter = counter > 0 and counter or nil,
		ranged = d > 1 or nil,
		guarded = target.defending or nil,
		sandwich = sandwich and sandwich.uid or nil,
	})
	local splash = self:hasKeyword(u, "Splash")
	self:damageUnit(target, atk, { player = p, creature = u })
	if CardData.get(u.id).soaks and target.hp > 0 then
		self:soak(target)
	end
	if counter > 0 then
		self:damageUnit(u, counter, { player = enemy, creature = target })
	end
	if splash then
		for _, n in ipairs(self:neighbors(target.col, target.row)) do
			local e = self.grid[n.col][n.row]
			if e and e ~= target and e.owner == enemy and e.kind == "creature" and e.hp > 0 then
				self:damageUnit(e, 1, { player = p, creature = u })
			end
		end
	end
	self:resolvePops()
	return true
end

-- The friendly creature standing right behind `target` as seen from attacker u, if any.
function MatchEngine:sandwichPartner(u, target)
	local dc = target.col - u.col
	local dr = target.row - u.row
	dc = dc > 0 and 1 or (dc < 0 and -1 or 0)
	dr = dr > 0 and 1 or (dr < 0 and -1 or 0)
	local b = self:at(target.col + dc, target.row + dr)
	if b and b ~= u and b.owner == u.owner and b.kind == "creature" and b.hp > 0 then
		return b
	end
	return nil
end

---------------------------------------------------------------------------
-- Commands: swap, defend and chant
---------------------------------------------------------------------------

-- Your creatures on the 4 tiles next to u (up, down, left, right). u can swap places with them.
function MatchEngine:swapTargets(u)
	local out = {}
	for _, d in ipairs(STEPS) do
		local f = self:at(u.col + d[1], u.row + d[2])
		if f and f ~= u and f.owner == u.owner and f.kind == "creature" and f.hp > 0 then
			table.insert(out, f)
		end
	end
	return out
end

function MatchEngine:chantOf(u)
	if u.kind ~= "creature" then
		return nil
	end
	return CardData.Chants[u.family]
end

-- Where u's chant can be aimed: tiles for aimed chants, { false } for chants without a target.
-- Empty when there is nothing it could do right now (energy is checked in chantProblem).
function MatchEngine:chantTargets(u)
	local out = {}
	local chant = self:chantOf(u)
	if not chant then
		return out
	end
	local id = chant.id
	if chant.target then
		for _, e in ipairs(self:allUnits()) do
			if e.owner ~= u.owner and e.hp > 0 and dist(u, e) <= (chant.range or 2) and (chant.target == "enemy" or e.kind == "creature") then
				table.insert(out, { col = e.col, row = e.row })
			end
		end
	elseif id == "picnic" then
		-- Worth it if anyone here is hurt, or a Snack here can still get Power (Sweet Tooth).
		local useful = false
		for _, f in ipairs(self:unitsOf(u.owner, "creature")) do
			if f == u or dist(u, f) == 1 then
				if f.hp < f.maxHp or (f.family == "Snack" and f.power < POWER_MAX) then
					useful = true
				end
			end
		end
		if useful then
			table.insert(out, false)
		end
	elseif id == "power_up" then
		if u.power < POWER_MAX then
			table.insert(out, false)
		end
	elseif id == "call_a_friend" then
		if #self:emptyNeighbors(u.col, u.row) > 0 then
			table.insert(out, false)
		end
	elseif id == "raise" then
		local pl = self.players[u.owner]
		if #pl.lost > 0 and pl.raisedTurn ~= self.turn and #self:emptyNeighbors(u.col, u.row) > 0 then
			table.insert(out, false)
		end
	else
		table.insert(out, false)
	end
	return out
end

-- Why u can't chant right now (nil if it can, apart from having already acted).
function MatchEngine:chantProblem(u)
	local chant = self:chantOf(u)
	if not chant then
		return "It has no chant"
	end
	if self.players[u.owner].energy < chant.cost then
		return "Needs " .. chant.cost .. " energy"
	end
	if #self:chantTargets(u) == 0 then
		local id = chant.id
		if id == "raise" and #self.players[u.owner].lost == 0 then
			return "Nothing has popped yet"
		elseif id == "raise" and self.players[u.owner].raisedTurn == self.turn then
			return "Only one Raise each turn"
		elseif id == "raise" or id == "call_a_friend" then
			return "No room next to it"
		elseif id == "picnic" then
			return "Nobody here needs it"
		elseif id == "power_up" then
			return "Already at full Power"
		end
		return "No enemy in reach"
	end
	return nil
end

function MatchEngine:canChant(u)
	return self:canAttack(u) and self:chantProblem(u) == nil
end

-- Defend: until your next turn it takes less damage and hits back harder.
function MatchEngine:defendWith(p, action)
	local u = self:findUnit(action.uid)
	if not u or u.owner ~= p or u.kind ~= "creature" then
		return false, "Pick one of your creatures"
	end
	if not self:canAttack(u) then
		return false, "That creature can't act right now"
	end
	u.attacked = true
	u.moved = true
	u.defending = true
	self:emit({ type = "defend", uid = u.uid, player = p })
	return true
end

function MatchEngine:chantWith(p, action)
	local u = self:findUnit(action.uid)
	if not u or u.owner ~= p or u.kind ~= "creature" then
		return false, "Pick one of your creatures"
	end
	if not self:canAttack(u) then
		return false, "That creature can't act right now"
	end
	local problem = self:chantProblem(u)
	if problem then
		return false, problem
	end
	local chant = self:chantOf(u)
	local target = nil
	if chant.target then
		if not tileOk(action.target) then
			return false, "Pick a target for " .. chant.name
		end
		for _, t in ipairs(self:chantTargets(u)) do
			if t.col == action.target.col and t.row == action.target.row then
				target = self.grid[t.col][t.row]
			end
		end
		if not target then
			return false, chant.name .. " can't reach that"
		end
	end
	local pl = self.players[p]
	local id = chant.id
	local amount = chant.amount or 1
	pl.energy -= chant.cost
	u.attacked = true
	u.moved = true
	self:emit({ type = "chant", uid = u.uid, player = p, chant = id, target = target and target.uid or nil, energy = pl.energy })
	if id == "picnic" then
		self:healCreature(u, amount)
		for _, f in ipairs(self:unitsOf(p, "creature")) do
			if f ~= u and dist(u, f) == 1 then
				self:healCreature(f, amount)
			end
		end
	elseif id == "scrap_toss" then
		self:damageUnit(target, amount, { player = p, creature = u })
	elseif id == "gust" then
		local back = target.owner == 1 and -1 or 1
		if self:isEmpty(target.col, target.row + back) then
			self:push(target, 1)
		else
			self:emit({ type = "bump", uid = target.uid })
			self:damageUnit(target, amount, { player = p, creature = u })
		end
		if target.hp > 0 then
			self:soak(target)
		end
	elseif id == "call_a_friend" then
		local spot = self.rng:pick(self:emptyNeighbors(u.col, u.row))
		self:spawn(p, spot.col, spot.row, "pigeon")
	elseif id == "raise" then
		local lastId = table.remove(pl.lost)
		for i = #pl.discard, 1, -1 do
			if pl.discard[i] == lastId then
				table.remove(pl.discard, i)
				break
			end
		end
		local spot = self.rng:pick(self:emptyNeighbors(u.col, u.row))
		local back = self:spawn(p, spot.col, spot.row, lastId, { hp = amount, raised = true })
		back.token = true -- it only comes back once: if it pops again, it's gone for good
		back.raised = true
		pl.raisedTurn = self.turn
	elseif id == "power_up" then
		self:addPower(u, amount, "chant")
	end
	self:resolvePops()
	return true
end

---------------------------------------------------------------------------
-- Playing cards
---------------------------------------------------------------------------

-- Returns true if `t` is a valid target for the card's target type.
function MatchEngine:validTarget(p, def, tile, t)
	local kind = def.target
	if not kind then
		return true
	end
	if t == nil then
		return not def.targetRequired
	end
	if not tileOk(t) then
		return false
	end
	local enemy = other(p)
	local u = self.grid[t.col][t.row]
	local isCreature = u ~= nil and u.kind == "creature" and u.hp > 0
	if kind == "otherFriendlyCreature" then
		return isCreature and u.owner == p
	elseif kind == "enemyCreature" then
		return isCreature and u.owner == enemy
	elseif kind == "enemyCreatureCost3" then
		return isCreature and u.owner == enemy and CardData.get(u.id).cost <= 3
	elseif kind == "enemyCreatureAtk3" then
		return isCreature and u.owner == enemy and self:attackOf(u) <= 3
	elseif kind == "anyCreature" then
		return isCreature
	elseif kind == "tileAndTerrain" then
		return CardData.Terrains[t.terrain] ~= nil
	end
	return false
end

local function randomCards(self, filter, n)
	local pool = {}
	for _, id in ipairs(CardData.List) do
		local d = CardData.Cards[id]
		if d.rarity ~= "Secret" and filter(d) then
			table.insert(pool, id)
		end
	end
	local out = {}
	for _ = 1, n do
		local id = self.rng:pick(pool)
		if id then
			table.insert(out, id)
		end
	end
	return out
end

function MatchEngine:cleanse(u)
	local d = CardData.get(u.id)
	u.atk = d.atk
	u.maxHp = d.hp
	u.hp = math.min(u.hp, u.maxHp)
	u.keywords = table.clone(d.keywords)
	u.bubble = false
	u.chargeLeft = 0
	u.power = 0
	self:emit({ type = "cleanse", uid = u.uid })
end

function MatchEngine:pingRandomEnemy(p, source, amount)
	local e = self.rng:pick(self:unitsOf(other(p), "creature"))
	if e then
		self:emit({ type = "shot", uid = source.uid, target = e.uid })
		self:damageUnit(e, amount, { player = p, creature = source })
	end
	return e
end

-- What a creature does when it is played from hand. `combo` is true when another card of
-- its family was already played this turn.
function MatchEngine:onPlay(p, c, t, combo)
	local enemy = other(p)
	local pl = self.players[p]
	local def = CardData.get(c.id)
	if def.snackTime then
		self:healHero(p, def.snackTime)
	end
	local id = c.id
	if id == "pretzel_guard" then
		if combo then
			for _, f in ipairs(self:unitsOf(p, "creature")) do
				if f ~= c and f.family == "Snack" then
					self:healCreature(f, 1)
				end
			end
		end
	elseif id == "pancake_paladin" then
		for _, f in ipairs(self:unitsOf(p, "creature")) do
			if f ~= c and dist(c, f) == 1 then
				self:healCreature(f, 2)
			end
		end
	elseif id == "spaghetti_hydra" or id == "roomba_rex" then
		if combo then
			self:addPower(c, 2, "combo")
		end
	elseif id == "hailstone_hopper" or id == "sheet_ghost" or id == "hamster_wheel_hero" then
		if combo then
			self:giveKeyword(c, "Zoom")
		end
	elseif id == "queen_parfait" then
		for _, f in ipairs(self:unitsOf(p, "creature")) do
			self:healCreature(f, f.maxHp)
		end
	elseif id == "dumpster_diver" then
		if combo then
			local tiles = { { col = c.col, row = c.row } }
			for _, n in ipairs(self:neighbors(c.col, c.row)) do
				table.insert(tiles, n)
			end
			self:pickUpScrap(c, tiles)
		end
		local spells = {}
		for i, cid in ipairs(pl.discard) do
			local d = CardData.Cards[cid]
			if d and d.type == "Spell" and not d.token then
				table.insert(spells, i)
			end
		end
		local i = self.rng:pick(spells)
		if i then
			local cid = table.remove(pl.discard, i)
			self:addToHand(p, cid)
		end
	elseif id == "glitter_gremlin" then
		local r = self.rng:int(1, 3)
		if r == 1 then
			self:emit({ type = "roll", source = c.uid, result = "Fast" })
			self:giveKeyword(c, "Fast")
		elseif r == 2 then
			self:emit({ type = "roll", source = c.uid, result = "Sturdy" })
			self:giveKeyword(c, "Sturdy")
		else
			self:emit({ type = "roll", source = c.uid, result = "+2 attack" })
			self:buff(c, 2, 0)
		end
	elseif id == "the_junk_king" then
		for _, b in ipairs(self:allUnits("building")) do
			self:destroyUnit(b)
		end
	elseif id == "grumpy_cloud" then
		local e = self:pingRandomEnemy(p, c, 1)
		if combo then
			for _, f in ipairs(self:unitsOf(enemy, "creature")) do
				self:soak(f)
			end
		elseif e then
			self:soak(e)
		end
	elseif id == "toaster_knight" then
		self:pingRandomEnemy(p, c, combo and 2 or 1)
	elseif id == "lightning_llama" then
		local options = { "hero" }
		for _, e in ipairs(self:unitsOf(enemy, "creature")) do
			table.insert(options, e)
		end
		local pick = self.rng:pick(options)
		if pick == "hero" then
			self:emit({ type = "roll", source = c.uid, result = "hero" })
			self:damageHero(enemy, 2, p)
		else
			self:emit({ type = "roll", source = c.uid, result = pick.id, target = pick.uid })
			self:damageUnit(pick, 2, { player = p, creature = c })
		end
	elseif id == "tornado_twins" then
		-- Blow every enemy creature 1 tile back, starting with the ones nearest their own edge.
		local list = self:unitsOf(enemy, "creature")
		table.sort(list, function(a, b)
			if a.row ~= b.row then
				if enemy == 1 then
					return a.row < b.row
				end
				return a.row > b.row
			end
			return a.col < b.col
		end)
		self:emit({ type = "ability", uid = c.uid })
		for _, e in ipairs(list) do
			self:push(e, 1)
			self:soak(e)
		end
	elseif id == "moth_mailman" then
		self:draw(p)
		if combo then
			self:draw(p)
		end
	elseif id == "pillow_bunny" then
		if t then
			self:buff(self.grid[t.col][t.row], combo and 1 or 0, 2)
		end
	elseif id == "pigeon_squad" then
		for _ = 1, 2 do
			local spot = self.rng:pick(self:emptyNeighbors(c.col, c.row))
			if spot then
				self:spawn(p, spot.col, spot.row, "pigeon")
			end
		end
	elseif id == "big_momma_moose" then
		for _, f in ipairs(self:unitsOf(p, "creature")) do
			if f.family == "Critter" then
				self:buff(f, 1, 1)
			end
		end
	elseif id == "haunted_vending_machine" then
		local got = randomCards(self, function(d)
			return d.cost == 1
		end, combo and 2 or 1)
		for _, cid in ipairs(got) do
			self:emit({ type = "roll", source = c.uid, result = cid })
			self:addToHand(p, cid)
		end
	elseif id == "escalator_wraith" then
		if t then
			local e = self.grid[t.col][t.row]
			self:removeUnit(e)
			self:emit({ type = "bounce", player = enemy, uid = e.uid })
			if not e.token then
				self:addToHand(enemy, e.id)
			end
		end
	elseif id == "the_mannequin_duke" then
		local lastId = pl.lost[#pl.lost]
		local spot = lastId and self.rng:pick(self:emptyNeighbors(c.col, c.row))
		if lastId and spot then
			table.remove(pl.lost)
			for i = #pl.discard, 1, -1 do
				if pl.discard[i] == lastId then
					table.remove(pl.discard, i)
					break
				end
			end
			self:spawn(p, spot.col, spot.row, lastId)
		end
	elseif id == "laundry_bot_3000" then
		if t then
			self:cleanse(self.grid[t.col][t.row])
		end
	elseif id == "mega_blender_prime" then
		local targets = self:unitsOf(enemy, "creature")
		if #targets > 0 and self.rng:chance(0.5) then
			local e = self.rng:pick(targets)
			self:emit({ type = "roll", source = c.uid, result = "destroy", target = e.uid })
			self:destroyUnit(e)
		else
			self:emit({ type = "roll", source = c.uid, result = "hero" })
			self:damageHero(enemy, 4, p)
		end
	elseif id == "captain_confetti" then
		for _, f in ipairs(self:unitsOf(p, "creature")) do
			self:giveKeyword(f, KEYWORDS[self.rng:int(1, #KEYWORDS)])
		end
	end
end

function MatchEngine:castSpell(p, id, t)
	local enemy = other(p)
	local pl = self.players[p]
	local u = t and tileOk(t) and self.grid[t.col][t.row] or nil
	if id == "spare_battery" or id == "scrap" then
		pl.energy += 1
	elseif id == "wrong_turn" then
		self:push(u, 2)
	elseif id == "water_balloon" then
		self:push(u, 1)
		self:soak(u)
	elseif id == "snack_break" then
		self:healHero(p, 4)
	elseif id == "coin_flip_fury" then
		if self.rng:chance(0.5) then
			self:emit({ type = "roll", result = "heads" })
			self:damageUnit(u, 5, { player = p })
		else
			self:emit({ type = "roll", result = "tails" })
			self:damageHero(p, 2, nil)
		end
	elseif id == "sneeze_storm" then
		for _, e in ipairs(self:unitsOf(enemy, "creature")) do
			self:damageUnit(e, 1, { player = p })
		end
	elseif id == "bubble_wrap" then
		u.bubble = true
		self:emit({ type = "buff", uid = u.uid, keyword = "Bubble" })
	elseif id == "pep_talk" then
		self:buff(u, 2, 2)
	elseif id == "terrain_shift" then
		local tiles = { { col = t.col, row = t.row } }
		for _, n in ipairs(self:neighbors(t.col, t.row)) do
			table.insert(tiles, n)
		end
		for _, n in ipairs(tiles) do
			self.terrain[n.col][n.row] = t.terrain
		end
		self:emit({ type = "terrain", tiles = tiles, terrain = t.terrain })
	elseif id == "pothole" then
		self:destroyUnit(u)
	elseif id == "mystery_box" then
		for _, cid in ipairs(randomCards(self, function()
			return true
		end, 2)) do
			self:addToHand(p, cid, -1)
		end
	elseif id == "earthquake_dance" then
		for _, c in ipairs(self:allUnits("creature")) do
			self:damageUnit(c, 3, { player = p })
		end
	elseif id == "total_chaos" then
		local creatures = self:allUnits("creature")
		for _, c in ipairs(creatures) do
			self:removeUnit(c)
		end
		local free = {}
		for row = 1, ROWS do
			for col = 1, COLS do
				if self.grid[col][row] == nil then
					table.insert(free, { col = col, row = row })
				end
			end
		end
		self.rng:shuffle(free)
		local moves = {}
		for i, c in ipairs(creatures) do
			local spot = free[i]
			self:placeUnit(c, spot.col, spot.row)
			table.insert(moves, { uid = c.uid, col = spot.col, row = spot.row })
		end
		local landed = creatures
		for col = 1, COLS do
			for row = 1, ROWS do
				self.terrain[col][row] = self.rng:pick(CardData.Families)
			end
		end
		self:emit({ type = "chaos", moves = moves, terrain = self:terrainCopy() })
		for _, c in ipairs(landed) do
			self:arrive(c)
		end
	end
end

function MatchEngine:playCard(p, action)
	local pl = self.players[p]
	local entry, index = self:findHand(p, action.handUid)
	if not entry then
		return false, "That card isn't in your hand"
	end
	local def = CardData.get(entry.id)
	local cost = self:costOf(p, entry)
	if cost > pl.energy then
		return false, "Not enough energy"
	end
	local tile = action.tile
	if def.type == "Creature" then
		if not tileOk(tile) or not self:canSummonAt(p, tile.col, tile.row) then
			return false, "Pick a glowing tile on your side"
		end
	elseif def.type == "Building" then
		if type(tile) ~= "table" or not self:canBuildAt(p, tile.col, tile.row) then
			return false, "Pick a slot in your building row"
		end
	else
		tile = nil
	end
	local t = action.target
	if t ~= nil and type(t) ~= "table" then
		return false, "Bad target"
	end
	if not self:validTarget(p, def, tile, t) then
		return false, "Pick a valid target"
	end

	pl.energy -= cost
	table.remove(pl.hand, index)
	-- Combo: another card of the same family was already played this turn.
	local combo = self:comboReady(p, def)
	if def.family ~= "Any" then
		pl.played[def.family] = (pl.played[def.family] or 0) + 1
	end
	self:emit({ type = "play", player = p, card = entry.id, uid = entry.uid, col = tile and tile.col, row = tile and tile.row, cost = cost, combo = (combo and def.combo) or nil })

	if def.type == "Creature" then
		local c = self:spawn(p, tile.col, tile.row, entry.id, { fromHand = true })
		self:onPlay(p, c, t, combo)
	elseif def.type == "Building" then
		self:build(p, tile.col, tile.row, entry.id)
	else
		self:castSpell(p, entry.id, t)
		if not def.token then
			table.insert(pl.discard, entry.id)
		end
	end
	self:resolvePops()
	return true
end

-- True if a card of this family was already played this turn (so a Combo bonus happens).
function MatchEngine:comboReady(p, def)
	return def.family ~= "Any" and (self.players[p].played[def.family] or 0) > 0
end

function MatchEngine:bigMoveReady(p)
	local pl = self.players[p]
	return not pl.bigMoveUsed and pl.dealt >= CardData.BigMoveCharge
end

function MatchEngine:useBigMove(p, action)
	local pl = self.players[p]
	if not self:bigMoveReady(p) then
		return false, "Big Move isn't ready"
	end
	local enemy = other(p)
	if pl.hero == "granny_bolt" then
		local col = action.col
		if not onBoard(col, 1) then
			return false, "Pick a column"
		end
		pl.bigMoveUsed = true
		self:emit({ type = "bigMove", player = p, hero = pl.hero, col = col })
		-- The ball rolls from your side up the lane and stops at the first enemy creature.
		self:laneStrike(p, col, 4, nil)
	else
		pl.bigMoveUsed = true
		self:emit({ type = "bigMove", player = p, hero = pl.hero })
		local got = randomCards(self, function(d)
			return d.type == "Spell"
		end, 1)
		if got[1] then
			self:addToHand(p, got[1], 0, 0)
		end
	end
	self:resolvePops()
	return true
end

-- The one entry point for players and bots. Returns ok, errorMessage.
function MatchEngine:act(p, action)
	if self.over then
		return false, "The match is over"
	end
	if p ~= self.current then
		return false, "It's not your turn"
	end
	if type(action) ~= "table" then
		return false, "Bad action"
	end
	if action.kind == "play" then
		return self:playCard(p, action)
	elseif action.kind == "move" then
		return self:moveUnit(p, action)
	elseif action.kind == "attack" then
		return self:attackWith(p, action)
	elseif action.kind == "defend" then
		return self:defendWith(p, action)
	elseif action.kind == "chant" then
		return self:chantWith(p, action)
	elseif action.kind == "bigmove" then
		return self:useBigMove(p, action)
	elseif action.kind == "endturn" then
		self:endTurn(p)
		return true
	end
	return false, "Unknown action"
end

---------------------------------------------------------------------------
-- Listing legal moves (used by the bot and to light up tiles in the UI)
---------------------------------------------------------------------------

function MatchEngine:targetsFor(p, def, tile)
	local kind = def.target
	if not kind then
		return { false }
	end
	local out = {}
	if kind == "tileAndTerrain" then
		for row = 1, ROWS do
			for col = 1, COLS do
				for _, fam in ipairs(CardData.Families) do
					if self.terrain[col][row] ~= fam then
						table.insert(out, { col = col, row = row, terrain = fam })
					end
				end
			end
		end
	else
		for _, u in ipairs(self:allUnits("creature")) do
			local t = { col = u.col, row = u.row }
			if self:validTarget(p, def, tile, t) then
				table.insert(out, t)
			end
		end
	end
	if #out == 0 and not def.targetRequired then
		table.insert(out, false)
	end
	return out
end

function MatchEngine:listActions(p)
	local actions = {}
	if self.over or p ~= self.current then
		return actions
	end
	local pl = self.players[p]
	local summon, build = nil, nil
	for _, entry in ipairs(pl.hand) do
		local def = CardData.get(entry.id)
		if self:costOf(p, entry) <= pl.energy then
			local tiles
			if def.type == "Creature" then
				summon = summon or self:summonTiles(p)
				tiles = summon
			elseif def.type == "Building" then
				build = build or self:buildTiles(p)
				tiles = build
			else
				tiles = { false }
			end
			for _, tile in ipairs(tiles) do
				for _, t in ipairs(self:targetsFor(p, def, tile or nil)) do
					table.insert(actions, {
						kind = "play",
						handUid = entry.uid,
						tile = tile and { col = tile.col, row = tile.row } or nil,
						target = t or nil,
					})
				end
			end
		end
	end
	for _, u in ipairs(self:unitsOf(p, "creature")) do
		if self:canMove(u) then
			local _, list = self:reachable(u)
			for _, node in ipairs(list) do
				table.insert(actions, { kind = "move", uid = u.uid, to = { col = node.col, row = node.row } })
			end
			for _, f in ipairs(self:swapTargets(u)) do
				table.insert(actions, { kind = "move", uid = u.uid, to = { col = f.col, row = f.row }, swap = true })
			end
		end
		if self:canAttack(u) then
			local targets, hero = self:attackTargets(u)
			for _, t in ipairs(targets) do
				table.insert(actions, { kind = "attack", uid = u.uid, target = { col = t.col, row = t.row } })
			end
			if hero then
				table.insert(actions, { kind = "attack", uid = u.uid, hero = true })
			end
			table.insert(actions, { kind = "defend", uid = u.uid })
			if self:chantProblem(u) == nil then
				for _, t in ipairs(self:chantTargets(u)) do
					table.insert(actions, { kind = "chant", uid = u.uid, target = t and { col = t.col, row = t.row } or nil })
				end
			end
		end
	end
	if self:bigMoveReady(p) then
		if pl.hero == "granny_bolt" then
			for col = 1, COLS do
				table.insert(actions, { kind = "bigmove", col = col })
			end
		else
			table.insert(actions, { kind = "bigmove" })
		end
	end
	table.insert(actions, { kind = "endturn" })
	return actions
end

---------------------------------------------------------------------------
-- What a player is allowed to see (the other hand stays hidden)
---------------------------------------------------------------------------

function MatchEngine:unitView(u)
	local kws = {}
	if u.kind == "creature" then
		for _, kw in ipairs(KEYWORDS) do
			if self:hasKeyword(u, kw) then
				table.insert(kws, kw)
			end
		end
		if u.bubble then
			table.insert(kws, "Bubble")
		end
	end
	return {
		uid = u.uid,
		id = u.id,
		kind = u.kind,
		owner = u.owner,
		col = u.col,
		row = u.row,
		atk = self:attackOf(u),
		hp = u.hp,
		maxHp = u.maxHp,
		keywords = kws,
		canMove = self:canMove(u),
		canAttack = self:canAttack(u),
		sick = u.kind == "creature" and u.sick or nil,
		defending = u.defending or nil,
		power = (u.power or 0) > 0 and u.power or nil,
		soaked = u.soaked or nil,
		charge = (u.chargeLeft or 0) > 0 and u.chargeLeft or nil,
		chantNote = (u.kind == "creature" and self:canAttack(u)) and self:chantProblem(u) or nil,
	}
end

function MatchEngine:viewFor(viewer)
	local view = {
		you = viewer,
		current = self.current,
		turn = self.turn,
		over = self.over,
		winner = self.winner,
		cols = COLS,
		rows = ROWS,
		terrain = self:terrainCopy(),
		units = {},
		players = {},
		scrap = {}, -- { col, row, n } for every tile with Scrap on it
	}
	for col = 1, COLS do
		for row = 1, ROWS do
			local n = self:scrapAt(col, row)
			if n > 0 then
				table.insert(view.scrap, { col = col, row = row, n = n })
			end
		end
	end
	for _, u in ipairs(self:allUnits()) do
		table.insert(view.units, self:unitView(u))
	end
	for p = 1, 2 do
		local pl = self.players[p]
		local pv = {
			hero = pl.hero,
			family = pl.family,
			hp = pl.hp,
			energy = pl.energy,
			maxEnergy = pl.maxEnergy,
			deckCount = #pl.deck,
			handCount = #pl.hand,
			discardCount = #pl.discard,
			bigMoveCharge = math.min(pl.dealt, CardData.BigMoveCharge),
			bigMoveReady = self:bigMoveReady(p),
			bigMoveUsed = pl.bigMoveUsed,
		}
		if p == viewer then
			local playable = {}
			for _, a in ipairs(self:listActions(p)) do
				if a.kind == "play" then
					playable[a.handUid] = true
				end
			end
			pv.hand = {}
			for _, entry in ipairs(pl.hand) do
				local def = CardData.get(entry.id)
				table.insert(pv.hand, {
					uid = entry.uid,
					id = entry.id,
					cost = self:costOf(p, entry),
					playable = playable[entry.uid] == true,
					combo = (def.combo and self.current == p and self:comboReady(p, def)) or nil,
				})
			end
		end
		view.players[p] = pv
	end
	return view
end

return MatchEngine

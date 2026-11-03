-- Deck Wars bot for the tile board.
-- Easy picks random moves (but still likes attacking).
-- Medium tries every legal action and keeps the one that leaves the best board. For a move it
--   also looks at the best attack the creature could make from its new tile.
-- Hard does the same, and also thinks about what the enemy could hit on their next turn.
-- Defend and chants are scored the same way: a braced creature next to enemies is worth a bit
-- more, and a chant's heal, damage, push, pigeon, raised creature or +1 attack shows up on the board.
-- The bot tries moves on copies of the match with fresh dice, so it can't see real rolls.
-- Combos: trying moves on copies shows it Combo and Sandwich bonuses; on top of that it values
-- Power (in attack), Grudge and Zap creatures, soaked enemies and Scrap for a Junk deck.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local Rng = req("Rng")
local CardData = req("CardData")

local ROWS = CardData.Rows
local COLS = CardData.Cols

local BotBrain = {}

local HERO_ROWS = CardData.HeroAttackRows or 1

-- Can player p's creature on this row hit the enemy hero?
local function heroRow(p, row)
	if p == 1 then
		return row > ROWS - HERO_ROWS
	end
	return row <= HERO_ROWS
end

-- How far a creature has walked toward the enemy (0 on its own back row).
local function advance(u)
	if u.owner == 1 then
		return u.row - 1
	end
	return ROWS - u.row
end

local function unitValue(m, u)
	if u.kind == "building" then
		return 3 + u.hp * 0.5
	end
	local atk = m:attackOf(u)
	local v = atk * 1.6 + u.hp * 1.0 + 1.5
	if m:hasKeyword(u, "Sturdy") then
		v += 1
	end
	if m:hasKeyword(u, "Ranged") then
		v += 1
	end
	if m:hasKeyword(u, "Fast") then
		v += 0.5
	end
	if m:hasKeyword(u, "Haunt") then
		v += 1
	end
	if m:hasKeyword(u, "Grudge") then
		v += 0.6
	end
	if m:hasKeyword(u, "Zap") then
		v += 0.4
	end
	if u.bubble then
		v += 1
	end
	if u.soaked then
		v -= 0.8 -- the next hit on it deals more
	end
	v += u.chargeLeft * 0.8
	if u.token then
		v -= 0.5
	end
	return v
end

-- Tiles a creature could reach on its next turn, ignoring whether it has moved already.
local function nextTurnReach(m, u)
	local speed = m:speedOf(u)
	local out = { { col = u.col, row = u.row } }
	local seen = { [u.col * 16 + u.row] = true }
	local frontier = { out[1] }
	for _ = 1, speed do
		local nxt = {}
		for _, n in ipairs(frontier) do
			for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
				local c, r = n.col + d[1], n.row + d[2]
				local k = c * 16 + r
				if not seen[k] and m:isEmpty(c, r) then
					seen[k] = true
					local t = { col = c, row = r }
					table.insert(out, t)
					table.insert(nxt, t)
				end
			end
		end
		frontier = nxt
	end
	return out
end

-- What player `attacker` could do on their next turn with the creatures on the board:
-- the biggest hit on each of the defender's units, and total damage to the defender's hero.
local function threats(m, attacker)
	local onUnit = {} -- [uid] = biggest single hit it could take
	local hero = 0
	for _, e in ipairs(m:unitsOf(attacker, "creature")) do
		local atk = m:attackOf(e)
		if atk > 0 then
			local range = m:rangeOf(e)
			local canHero = false
			local reach = nextTurnReach(m, e)
			for _, t in ipairs(reach) do
				if heroRow(attacker, t.row) then
					canHero = true
				end
			end
			if canHero then
				hero += atk
			end
			for _, u in ipairs(m:unitsOf(3 - attacker)) do
				for _, t in ipairs(reach) do
					if math.max(math.abs(t.col - u.col), math.abs(t.row - u.row)) <= range then
						if (onUnit[u.uid] or 0) < atk then
							onUnit[u.uid] = atk
						end
						break
					end
				end
			end
		end
	end
	return onUnit, hero
end

local function boardScore(m, p, careful)
	if m.over then
		if m.winner == p then
			return 1e6
		elseif m.winner == 0 then
			return 0
		end
		return -1e6
	end
	local q = 3 - p
	local me, them = m.players[p], m.players[q]
	local s = (me.hp - them.hp) * 2.2
	-- Low health is scarier than the raw difference suggests.
	if me.hp <= 8 then
		s -= (9 - me.hp) * 2.5
	end
	if them.hp <= 8 then
		s += (9 - them.hp) * 2.5
	end
	for _, u in ipairs(m:allUnits()) do
		local v = unitValue(m, u)
		if u.kind == "creature" then
			local atk = m:attackOf(u)
			v += advance(u) * 0.2 * (1 + atk * 0.35)
			if heroRow(u.owner, u.row) then
				v += atk * 0.9 -- standing where it can hit the hero
			end
			if u.defending then
				-- Braced (takes less damage, hits back harder): worth something while enemies are close.
				for _, e in ipairs(m:unitsOf(3 - u.owner, "creature")) do
					if math.max(math.abs(e.col - u.col), math.abs(e.row - u.row)) <= 2 then
						v += 0.6
						break
					end
				end
			end
		end
		if u.owner == p then
			s += v
		else
			s -= v
		end
	end
	s += #me.hand * 1.0 - #them.hand * 0.5
	-- Scrap on the board is worth something to a Junk deck (its creatures pick it up).
	local scrap = m:scrapTotal()
	if scrap > 0 then
		if me.family == "Junk" then
			s += scrap * 0.7
		end
		if them.family == "Junk" then
			s -= scrap * 0.7
		end
	end
	if m:bigMoveReady(p) then
		s += 3
	end
	if careful then
		-- What could the enemy hit next turn? Units that would pop are worth less, and
		-- open paths to our hero are dangerous.
		local onUnit, heroHit = threats(m, q)
		for _, u in ipairs(m:unitsOf(p)) do
			local hit = onUnit[u.uid]
			if hit then
				local eff = hit
				if m:hasKeyword(u, "Sturdy") then
					eff -= 1
				end
				if u.defending then
					eff -= CardData.DefendArmor or 1
				end
				if u.bubble then
					eff = 0
				end
				if eff >= u.hp then
					s -= unitValue(m, u) * 0.45
				elseif eff > 0 then
					s -= eff * 0.25
				end
			end
		end
		s -= heroHit * 1.3
		if heroHit >= me.hp then
			s -= 60
		end
		-- And our own chances next turn, worth a bit less since they move first.
		local myOnUnit, myHero = threats(m, p)
		s += myHero * 0.5
		for _, e in ipairs(m:unitsOf(q)) do
			local hit = myOnUnit[e.uid]
			if hit and hit >= e.hp then
				s += unitValue(m, e) * 0.15
			end
		end
	end
	return s
end

local function simulate(match, p, action, rng)
	local sim = match:clone(rng:int(1, 2147483646))
	local ok = sim:act(p, action)
	if not ok then
		return nil
	end
	return sim
end

-- Score after an action. For a move, also try the best attack the creature could make next.
local function scoreAction(match, p, action, rng, careful)
	local sim = simulate(match, p, action, rng)
	if not sim then
		return nil
	end
	local best = boardScore(sim, p, careful)
	if action.kind == "move" and not sim.over then
		local u = sim:findUnit(action.uid)
		if u and sim:canAttack(u) then
			local targets, hero = sim:attackTargets(u)
			local follow = {}
			for _, t in ipairs(targets) do
				table.insert(follow, { kind = "attack", uid = u.uid, target = { col = t.col, row = t.row } })
			end
			if hero then
				table.insert(follow, { kind = "attack", uid = u.uid, hero = true })
			end
			for _, a in ipairs(follow) do
				local sim2 = simulate(sim, p, a, rng)
				if sim2 then
					local s2 = boardScore(sim2, p, careful)
					if s2 > best then
						best = s2
					end
				end
			end
		end
	end
	return best
end

-- Returns the next action for player p. Call again after each action until it returns endturn.
function BotBrain.chooseAction(match, p, difficulty, rng)
	rng = rng or Rng.new()
	local actions = match:listActions(p)
	if #actions <= 1 then
		return { kind = "endturn" }
	end

	if difficulty == "Easy" then
		local attacks, others = {}, {}
		for _, a in ipairs(actions) do
			if a.kind == "attack" then
				table.insert(attacks, a)
			elseif a.kind ~= "endturn" then
				table.insert(others, a)
			end
		end
		if #attacks > 0 and rng:chance(0.6) then
			return rng:pick(attacks)
		end
		if #others == 0 or rng:chance(0.18) then
			return { kind = "endturn" }
		end
		return rng:pick(others)
	end

	local careful = difficulty == "Hard"
	local best, bestScore = { kind = "endturn" }, boardScore(match, p, careful)
	for _, a in ipairs(actions) do
		if a.kind ~= "endturn" then
			local score = scoreAction(match, p, a, rng, careful)
			if score and score > bestScore + 0.05 then
				best, bestScore = a, score
			end
		end
	end
	return best
end

BotBrain.boardScore = boardScore

return BotBrain

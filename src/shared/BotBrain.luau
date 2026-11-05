-- The bot for the lane rules (Bot Bonkers, and empty seats in 2v2 and tournaments).
-- Lanes have a Front and a Back row: the bot tries each free tile for a creature, and Shifts.
--
-- It picks one action at a time: it tries every legal move on a copy of the match, lets that
-- copy fight its battle, scores what's left (hit points, creatures, how hard the enemy will hit
-- back) and does the best one. When nothing beats fighting right away, it presses BATTLE.
-- Easy plays a random card now and then; Medium is greedy but a bit sloppy; Hard is greedy.

local function req(name)
	if script then
		return require(script.Parent:WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")

local BotBrain = {}

local WIN = 1e6

local function creatureValue(m, u)
	return m:attackOf(u) * 2 + m:healthOf(u) + (u.shield and 2 or 0)
end

-- How good the match looks for `team` right now (higher is better).
local function score(m, team)
	local enemy = 3 - team
	if m.over then
		if m.winner == team then
			return WIN
		elseif m.winner == enemy then
			return -WIN
		end
		return 0
	end
	local mine, theirs = m.teams[team].hp, m.teams[enemy].hp
	local s = (mine - theirs) * 6
	-- A hero close to dying matters more.
	s += math.max(0, 12 - theirs) * 3 - math.max(0, 12 - mine) * 3
	for _, u in ipairs(m:allCreatures(team)) do
		s += creatureValue(m, u)
	end
	for _, u in ipairs(m:allCreatures(enemy)) do
		s -= creatureValue(m, u)
	end
	-- Buildings and cards in hand are worth a little.
	for t = 1, 2 do
		for _, l in ipairs(m.lanes[t]) do
			if l.building then
				s += (t == team) and 3 or -3
			end
		end
	end
	for _, seat in ipairs(m.seats) do
		s += (seat.team == team and 1 or -1) * #seat.hand * 1.5
	end
	-- How much the enemy will hit our hero in their next battle (open lanes hurt).
	local threat = 0
	for _, u in ipairs(m:allCreatures(enemy)) do
		local attacks = u.row == 1 or m:hasKeyword(u, "Ranged")
		if attacks and not m:attackTarget(u) then
			threat += m:attackOf(u)
		end
	end
	s -= threat * 4
	if threat >= mine then
		s -= 5000
	end
	return s
end

-- Turns the grouped list from listActions into single concrete actions.
local function expand(m, seat, list)
	local out = {}
	for _, a in ipairs(list) do
		if a.kind == "play" then
			local c = CardData.Cards[a.id]
			if c.type == "Creature" or c.type == "Building" then
				local team = m.seats[seat].team
				local spots = {}
				if c.type == "Creature" then
					for _, t in ipairs(a.tiles or {}) do
						local here = m:unitAt(team, t.lane, t.row)
						-- Only play over your own creature if it's hurt or small.
						if not here or (m:healthOf(here) <= 1 or m:attackOf(here) < c.atk - 1) then
							table.insert(spots, t)
						end
					end
				else
					for _, lane in ipairs(a.lanes) do
						if not m.lanes[team][lane].building then
							table.insert(spots, { lane = lane })
						end
					end
				end
				for _, spot in ipairs(spots) do
					if a.targets and #a.targets > 0 then
						for k, t in ipairs(a.targets) do
							if k > 4 then
								break
							end
							table.insert(out, { kind = "play", handUid = a.handUid, lane = spot.lane, row = spot.row, target = t })
						end
					else
						table.insert(out, { kind = "play", handUid = a.handUid, lane = spot.lane, row = spot.row })
					end
				end
			elseif a.needsTarget then
				for _, t in ipairs(a.targets) do
					table.insert(out, { kind = "play", handUid = a.handUid, target = t })
				end
			else
				table.insert(out, { kind = "play", handUid = a.handUid })
			end
		elseif a.kind == "spark" then
			table.insert(out, { kind = "spark", uid = a.uid })
		elseif a.kind == "shift" then
			table.insert(out, { kind = "shift", uid = a.uid })
		elseif a.kind == "bigmove" then
			if a.targets then
				for _, t in ipairs(a.targets) do
					table.insert(out, { kind = "bigmove", target = t })
				end
			else
				table.insert(out, { kind = "bigmove" })
			end
		end
	end
	return out
end

-- Tries an action on a copy, fights the battle, and scores the result.
-- An action that gives magic (Spare Battery) is only worth what that magic buys, so for those
-- it also tries the best card to play next (one step deeper, no further).
local function tryAction(m, seat, action, seed, deeper)
	local copy = m:clone(seed)
	local team = m.seats[seat].team
	if action.kind ~= "battle" then
		local ok = copy:act(seat, action)
		if not ok then
			return nil
		end
	end
	local gained = not copy.over and copy.current == seat and copy.seats[seat].magic > m.seats[seat].magic
	local follow = nil
	if gained and not deeper then
		for _, a in ipairs(expand(copy, seat, copy:listActions(seat))) do
			if a.kind == "play" then
				local s = tryAction(copy, seat, a, seed, true)
				if s and (not follow or s > follow) then
					follow = s
				end
			end
		end
	end
	if not copy.over and copy.current == seat then
		copy:act(seat, { kind = "battle" })
	end
	local s = score(copy, team)
	return follow and math.max(s, follow) or s
end

-- Picks the next action for `seat`. rng: an Rng (only used for Easy and Medium's sloppiness).
function BotBrain.chooseAction(m, seat, difficulty, rng)
	local list = m:listActions(seat)
	local actions = expand(m, seat, list)
	if #actions == 0 then
		return { kind = "battle" }
	end
	if difficulty == "Easy" then
		-- Plays something random most of the time, then fights.
		if rng and rng:chance(0.7) then
			local plays = {}
			for _, a in ipairs(actions) do
				if a.kind == "play" then
					table.insert(plays, a)
				end
			end
			local pick = rng:pick(plays)
			if pick then
				return pick
			end
		end
		return { kind = "battle" }
	end
	local seed = m.rng.state + 7
	local best, bestScore = { kind = "battle" }, tryAction(m, seat, { kind = "battle" }, seed)
	local margin = difficulty == "Medium" and 2 or 0.5
	for _, a in ipairs(actions) do
		if not (difficulty == "Medium" and a.kind == "spark" and rng and rng:chance(0.4)) then
			local s = tryAction(m, seat, a, seed)
			if s then
				if difficulty == "Medium" and rng then
					s += (rng:next() - 0.5) * 6
				end
				if s > bestScore + margin then
					best, bestScore = a, s
				end
			end
		end
	end
	return best
end

-- Plays a whole turn for `seat` right away (tests and bot-only tournament matches).
function BotBrain.playTurn(m, seat, difficulty, rng)
	local guard = 0
	while not m.over and m.current == seat and guard < 40 do
		guard += 1
		local a = BotBrain.chooseAction(m, seat, difficulty, rng)
		local ok = m:act(seat, a)
		if not ok then
			m:act(seat, { kind = "battle" })
		end
	end
	if not m.over and m.current == seat then
		m:act(seat, { kind = "battle" })
	end
end

BotBrain.score = score
BotBrain.expand = expand

return BotBrain

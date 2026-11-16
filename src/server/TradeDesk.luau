-- TradeDesk: trading cards at the Park's Trading Post, step by step. Server only. The rules (what
-- can be offered, storage, who may trade) are in ReplicatedStorage.DeckWars.Trade; this keeps the
-- requests and the open trades. ParkServer passes it the "Trade..." actions from ParkAction and
-- sends what it says through ParkEvent.
--
-- How a trade goes
--   1. Ask.     "TradeInvite" { userId }: both players stand at the Trading Post. The other player
--               gets a request ("tradeInvite") and answers with "TradeAnswer" { userId, accept }.
--   2. Offer.   Each puts up to Trade.MaxOffer cards in: "TradeOffer" { offer, n }.
--   3. Lock in. "TradeLock" { offer, n, seen }: seen is the version of the other player's offer
--               this player was looking at. If their offer changed since, the lock is refused, so
--               nobody locks in on cards they haven't seen. Any change unlocks both.
--   4. Confirm. With both locked the offers can't change. After Trade.ConfirmDelay seconds each
--               sends "TradeConfirm"; when both have, the cards change hands and both saves are
--               saved right away.
--   "TradeUnlock" steps back to offering. "TradeCancel", walking away from the Trading Post,
--   leaving the park or the game, or Trade.IdleSeconds without a move calls the trade off.
--
-- What players are sent (ParkEvent payloads):
--   { kind = "tradeInvite", from = userId, name, seconds }     someone asks you
--   { kind = "tradeInviteGone" }                               that request is over
--   { kind = "tradeAsked", name, seconds }                     your request went out
--   { kind = "tradeOpen", with = { userId, name }, cards = Trade.tradable, max, room, delay }
--   { kind = "trade", state = "offering" | "confirm", confirmIn = seconds,
--     mine = { offer, locked, confirmed, version, n }, theirs = { offer, locked, confirmed, version } }
--   { kind = "tradeDone", name, got = offer, gave = offer }
--   { kind = "tradeClosed", text }                             called off (text: why, or nil)
--   { kind = "toast", text }
--
-- TradeDesk.init(deps) with:
--   send(player, payload)      deliver a payload to a player's screen
--   dataOf(player)             the live save table, or nil while it hasn't loaded
--   near(player)               is the player at the Trading Post right now?
--   playerById(userId)         the player in this server with that UserId, or nil
--   changed(player)            the save changed (mark it dirty, refresh what others see)
--   save(player)               save this player's profile now
--   now()                      seconds, for timers       clock()  Unix time, for the UTC day
-- Players are only used as keys and for UserId and DisplayName, so the tests pass plain tables.

local function req(name)
	if script then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		return require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild(name))
	end
	return require(name)
end

local CardData = req("CardData")
local Trade = req("Trade")

local TradeDesk = {}

local deps = nil
local sessions = {} -- [player] = session (both players of a trade point at the same one)
local invites = {} -- [asked player] = { from = player, at = seconds }
local outgoing = {} -- [asking player] = the player they asked
local cooldown = {} -- [player] = { [other player] = may ask again at }
local lastInvite = {} -- [player] = seconds
local buckets = {} -- [player] = { from = seconds, count = n } (how fast actions may come)

local ACTIONS = { TradeInvite = true, TradeAnswer = true, TradeOffer = true, TradeLock = true, TradeUnlock = true, TradeConfirm = true, TradeCancel = true }
local ACTIONS_PER_WINDOW, WINDOW = 14, 2 -- at most this many trade actions in this many seconds

local function now()
	return deps.now()
end

-- The practice partner (see TradeDesk.practice) is a plain table, never a Player.
local function isBot(player)
	return typeof(player) == "table" and player.bot == true
end

local function nameOf(player)
	return tostring(player.DisplayName or player.Name or "Someone")
end

local function dataOf(player)
	if isBot(player) then
		return player.data
	end
	return deps.dataOf(player)
end

local function send(player, payload)
	if not isBot(player) then
		deps.send(player, payload)
	end
end

local function toast(player, text)
	send(player, { kind = "toast", text = text })
end

-- Can this player trade right now? Returns true, or false and a short reason code.
local function ready(player)
	if isBot(player) then
		return true
	end
	local d = dataOf(player)
	if not d then
		return false, "save"
	end
	if sessions[player] then
		return false, "busy"
	end
	if not deps.near(player) then
		return false, "far"
	end
	return Trade.eligible(d, deps.clock())
end

local MINE = {
	save = "Your cards haven't loaded yet. Try again in a moment.",
	busy = "Finish the trade you're in first.",
	far = "Stand at the Trading Post to trade.",
	level = "Reach level " .. Trade.MinLevel .. " to trade.",
	daily = "You've made " .. Trade.MaxPerDay .. " trades today. Come back tomorrow.",
}
local function theirs(code, name)
	if code == "save" then
		return name .. "'s cards haven't loaded yet."
	elseif code == "busy" then
		return name .. " is in another trade."
	elseif code == "far" then
		return name .. " isn't at the Trading Post."
	elseif code == "level" then
		return name .. " needs level " .. Trade.MinLevel .. " to trade."
	end
	return name .. " has no trades left today."
end

local function sides(s, player)
	if s.a.player == player then
		return s.a, s.b
	end
	return s.b, s.a
end

local function view(s, player)
	local mine, other = sides(s, player)
	return {
		kind = "trade",
		state = s.state,
		confirmIn = s.state == "confirm" and math.max(0, s.confirmAt - now()) or nil,
		mine = { offer = mine.offer, locked = mine.locked, confirmed = mine.confirmed, version = mine.version, n = mine.n },
		theirs = { offer = other.offer, locked = other.locked, confirmed = other.confirmed, version = other.version },
	}
end

local function push(s)
	send(s.a.player, view(s, s.a.player))
	send(s.b.player, view(s, s.b.player))
end

-- Calls a trade off. textFor(player) -> what that player is told (nil: nothing).
local function close(s, textFor)
	for _, side in ipairs({ s.a, s.b }) do
		if sessions[side.player] == s then
			sessions[side.player] = nil
		end
		send(side.player, { kind = "tradeClosed", text = textFor and textFor(side.player) or nil })
	end
end

local function clearInvite(asked, tell)
	local inv = invites[asked]
	if inv then
		invites[asked] = nil
		if outgoing[inv.from] == asked then
			outgoing[inv.from] = nil
		end
		if tell then
			send(asked, { kind = "tradeInviteGone" })
		end
	end
	return inv
end

local function open(a, b, practice)
	local s = {
		state = "offering",
		practice = practice or nil,
		started = now(),
		touched = now(),
		a = { player = a, offer = {}, locked = false, confirmed = false, version = 0, n = 0 },
		b = { player = b, offer = {}, locked = false, confirmed = false, version = 0, n = 0 },
	}
	sessions[a] = s
	sessions[b] = s
	for _, side in ipairs({ s.a, s.b }) do
		local _, other = sides(s, side.player)
		local d = dataOf(side.player)
		send(side.player, {
			kind = "tradeOpen",
			with = { userId = other.player.UserId, name = nameOf(other.player) },
			cards = Trade.tradable(d),
			max = Trade.MaxOffer,
			room = math.max(0, Trade.limit(d) - Trade.kept(d)),
			delay = Trade.ConfirmDelay,
		})
	end
	push(s)
	return s
end

-- Starts a trade between two players who both said yes (checks both again first).
local function start(a, b)
	for _, pair in ipairs({ { a, b }, { b, a } }) do
		local ok, code = ready(pair[1])
		if not ok then
			toast(pair[1], MINE[code])
			toast(pair[2], theirs(code, nameOf(pair[1])))
			return nil
		end
	end
	clearInvite(a, true)
	clearInvite(b, true)
	return open(a, b)
end

-- Sets a player's offer from what their screen sent. Returns true if the trade can go on.
local function applyOffer(s, player, options)
	local mine, other = sides(s, player)
	local offer, why = Trade.cleanOffer(options.offer)
	if offer then
		local d = dataOf(player)
		local ok, problem = false, MINE.save
		if d then
			ok, problem = Trade.checkOffer(d, offer)
		end
		if not ok then
			offer, why = nil, problem
		end
	end
	if not offer then
		toast(player, why)
		return false
	end
	if not Trade.sameOffer(mine.offer, offer) then
		mine.offer = offer
		mine.version += 1
		mine.locked = false
		other.locked = false
	end
	return true
end

local function backToOffering(s)
	s.state = "offering"
	s.confirmAt = nil
	for _, side in ipairs({ s.a, s.b }) do
		side.locked = false
		side.confirmed = false
	end
end

-- Why a swap can't happen, said to `player`.
local function swapProblem(s, player, why, side)
	if side == nil then
		return why
	end
	local who = side == "a" and s.a.player or s.b.player
	if who == player then
		return "You: " .. why
	end
	return nameOf(who) .. ": " .. why
end

local function finish(s)
	local dA, dB = dataOf(s.a.player), dataOf(s.b.player)
	if not (dA and dB) then
		close(s, function()
			return "A save wasn't ready, so nothing was traded."
		end)
		return
	end
	local ok, why, side = Trade.swap(dA, s.a.offer, dB, s.b.offer, deps.clock())
	if not ok then
		backToOffering(s)
		for _, each in ipairs({ s.a, s.b }) do
			toast(each.player, swapProblem(s, each.player, why, side))
		end
		push(s)
		return
	end
	sessions[s.a.player] = nil
	sessions[s.b.player] = nil
	for _, each in ipairs({ s.a, s.b }) do
		local mine, other = sides(s, each.player)
		if not isBot(each.player) then
			deps.changed(each.player)
			send(each.player, { kind = "tradeDone", name = nameOf(other.player), got = other.offer, gave = mine.offer })
		end
	end
	for _, each in ipairs({ s.a, s.b }) do
		if not isBot(each.player) then
			deps.save(each.player)
		end
	end
end

local function act(player, what, options)
	if what == "TradeInvite" then
		local target = deps.playerById(options.userId)
		if not target or target == player then
			toast(player, "That player isn't here.")
			return
		end
		local ok, code = ready(player)
		if not ok then
			toast(player, MINE[code])
			return
		end
		ok, code = ready(target)
		if not ok then
			toast(player, theirs(code, nameOf(target)))
			return
		end
		local t = now()
		local mineIn = invites[player]
		if mineIn and mineIn.from == target and t - mineIn.at <= Trade.InviteSeconds then
			start(target, player) -- (they had already asked: that's a yes from both)
			return
		end
		if lastInvite[player] and t - lastInvite[player] < 2 then
			toast(player, "One moment...")
			return
		end
		local wait = cooldown[player] and cooldown[player][target]
		if wait and t < wait then
			toast(player, nameOf(target) .. " said no a moment ago. Ask again in a little while.")
			return
		end
		local pending = invites[target]
		if pending and pending.from ~= player and t - pending.at <= Trade.InviteSeconds then
			toast(player, nameOf(target) .. " is answering someone else. Try again in a moment.")
			return
		end
		if outgoing[player] and outgoing[player] ~= target then
			clearInvite(outgoing[player], true) -- (one request at a time)
		end
		invites[target] = { from = player, at = t }
		outgoing[player] = target
		lastInvite[player] = t
		send(target, { kind = "tradeInvite", from = player.UserId, name = nameOf(player), seconds = Trade.InviteSeconds })
		send(player, { kind = "tradeAsked", name = nameOf(target), seconds = Trade.InviteSeconds })
	elseif what == "TradeAnswer" then
		local inv = invites[player]
		if not inv or inv.from.UserId ~= options.userId or now() - inv.at > Trade.InviteSeconds then
			send(player, { kind = "tradeInviteGone" })
			if options.accept == true then
				toast(player, "That request has run out.")
			end
			return
		end
		if options.accept ~= true then
			clearInvite(player, false)
			cooldown[inv.from] = cooldown[inv.from] or {}
			cooldown[inv.from][player] = now() + Trade.DeclineCooldown
			toast(inv.from, nameOf(player) .. " doesn't want to trade right now.")
			return
		end
		start(inv.from, player)
		clearInvite(player, true) -- (if it couldn't start, the request is still used up)
	else
		local s = sessions[player]
		if not s then
			send(player, { kind = "tradeClosed" })
			return
		end
		local mine, other = sides(s, player)
		s.touched = now()
		if type(options.n) == "number" then
			mine.n = options.n -- (their screen takes our copy of the offer from this edit on)
		end
		if what == "TradeCancel" then
			close(s, function(who)
				return who == player and "Trade cancelled." or (nameOf(player) .. " cancelled the trade.")
			end)
			return
		elseif what == "TradeOffer" then
			if s.state == "offering" then
				applyOffer(s, player, options)
			end
		elseif what == "TradeLock" then
			if s.state == "offering" and applyOffer(s, player, options) then
				if options.seen ~= other.version then
					toast(player, nameOf(other.player) .. " changed their cards. Have another look.")
				elseif #mine.offer + #other.offer == 0 then
					toast(player, "Put a card in first.")
				else
					mine.locked = true
					if other.locked then
						local dA, dB = dataOf(s.a.player), dataOf(s.b.player)
						local ok, why, side = false, MINE.save, nil
						if dA and dB then
							ok, why, side = Trade.canSwap(dA, s.a.offer, dB, s.b.offer)
						end
						if ok then
							s.state = "confirm"
							s.confirmAt = now() + Trade.ConfirmDelay
							s.a.confirmed, s.b.confirmed = false, false
						else
							backToOffering(s)
							for _, each in ipairs({ s.a, s.b }) do
								toast(each.player, swapProblem(s, each.player, why, side))
							end
						end
					end
				end
			end
		elseif what == "TradeUnlock" then
			if s.state == "confirm" then
				backToOffering(s)
				toast(other.player, nameOf(player) .. " wants to change the trade.")
			else
				mine.locked = false
			end
		elseif what == "TradeConfirm" then
			if s.state == "confirm" and now() >= s.confirmAt - 0.05 then
				mine.confirmed = true
				if other.confirmed then
					finish(s)
					return
				end
			end
		end
		push(s)
	end
end

-- A "Trade..." action from a player's screen. Returns true when it was one (handled or not).
function TradeDesk.handle(player, what, options)
	if not ACTIONS[what] or not deps then
		return false
	end
	options = type(options) == "table" and options or {}
	local t = now()
	local b = buckets[player]
	if not b or t - b.from >= WINDOW then
		b = { from = t, count = 0 }
		buckets[player] = b
	end
	b.count += 1
	if b.count > ACTIONS_PER_WINDOW then
		-- too fast: the action is dropped, and their screen gets the trade as it stands
		local s = sessions[player]
		if s and b.count == ACTIONS_PER_WINDOW + 1 then
			send(player, view(s, player))
		end
		return true
	end
	act(player, what, options)
	return true
end

-- The practice partner's moves (see TradeDesk.practice): it puts two cards in, locks in a moment
-- after you do, and confirms once the wait is over.
local function botStep(s, bot, t)
	local mine, other = sides(s, bot)
	if s.state == "offering" then
		if #mine.offer == 0 and not mine.offered and t - s.started >= 1.5 then
			mine.offered = true
			local offer = {}
			for _, c in ipairs(Trade.tradable(bot.data)) do
				if #offer < 2 then
					table.insert(offer, { id = c.id, level = c.level })
				end
			end
			act(bot, "TradeOffer", { offer = offer })
		elseif other.locked and not mine.locked and t - s.touched >= 0.8 then
			act(bot, "TradeLock", { offer = mine.offer, seen = other.version })
		end
	elseif s.state == "confirm" and not mine.confirmed and t >= s.confirmAt + 0.5 then
		act(bot, "TradeConfirm", {})
	end
end

-- Call a few times a second: requests run out, and trades end when someone walks away or
-- nobody has moved for a long time.
function TradeDesk.step()
	if not deps then
		return
	end
	local t = now()
	for asked, inv in pairs(invites) do
		if t - inv.at > Trade.InviteSeconds then
			clearInvite(asked, true)
			toast(inv.from, nameOf(asked) .. " didn't answer.")
		end
	end
	local seen = {}
	for _, s in pairs(sessions) do
		if not seen[s] then
			seen[s] = true
			local gone = nil
			for _, side in ipairs({ s.a, s.b }) do
				if not isBot(side.player) and not s.practice and not deps.near(side.player) then
					gone = gone or side.player
				end
			end
			if gone then
				close(s, function(who)
					return who == gone and "You walked away from the Trading Post, so the trade was called off." or (nameOf(gone) .. " walked away, so the trade was called off.")
				end)
			elseif t - s.touched > Trade.IdleSeconds then
				close(s, function()
					return "The trade took too long and was called off."
				end)
			else
				for _, side in ipairs({ s.a, s.b }) do
					if isBot(side.player) and sessions[side.player] == s then
						botStep(s, side.player, t)
					end
				end
			end
		end
	end
end

-- The player left the park or the game: their trade and requests are over.
function TradeDesk.drop(player, forGood)
	local s = sessions[player]
	if s then
		close(s, function(who)
			return who ~= player and (nameOf(player) .. " left, so the trade was called off.") or nil
		end)
	end
	clearInvite(player, true)
	if outgoing[player] then
		clearInvite(outgoing[player], true)
	end
	if forGood then
		cooldown[player] = nil
		for _, list in pairs(cooldown) do
			list[player] = nil
		end
		lastInvite[player] = nil
		buckets[player] = nil
	end
end

-- A trade with a pretend partner, for developers to try the trade window on their own. The
-- partner brings a few cards of its own (made up, not from any save) and takes whatever it is
-- given, so only ParkServer's developer hook calls this. Returns the trade, or nil and why.
function TradeDesk.practice(player)
	if not deps then
		return nil, "not ready"
	end
	if sessions[player] then
		return nil, "busy"
	end
	if not dataOf(player) then
		return nil, "save"
	end
	local bot = { bot = true, UserId = -77, DisplayName = "Practice Partner", Name = "PracticePartner" }
	bot.data = { level = Trade.MinLevel, collection = {}, cardLevels = {}, decks = {} }
	local wanted = { Common = 1, Rare = 1, Epic = 1 }
	for _, id in ipairs(CardData.List) do
		local c = CardData.Cards[id]
		if not c.token and wanted[c.rarity] and wanted[c.rarity] > 0 then
			wanted[c.rarity] -= 1
			bot.data.collection[id] = 1
		end
	end
	return open(player, bot, true)
end

-- (for the tests and the server's own checks)
function TradeDesk.sessionOf(player)
	return sessions[player]
end

function TradeDesk.init(d)
	deps = d
	sessions, invites, outgoing, cooldown, lastInvite, buckets = {}, {}, {}, {}, {}, {}
	return TradeDesk
end

return TradeDesk

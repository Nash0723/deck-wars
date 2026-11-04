-- Deck Wars: every player's card collection and saved decks, on the server.
--
-- The collection and decks are saved in the player's one saved profile, which the
-- EconomyManager module keeps (Gems, Coins, cards and decks together, so two DataStores
-- never fight over the same player). This module only asks it for:
--   EconomyManager.waitForData(player)  -> the live profile table (or nil while it can't load)
--   EconomyManager.getCollection(player) -> { [cardId] = copies }
--   EconomyManager.grantCards(player, { cardId, ... })
--   EconomyManager.getDeckSlots(player) -> how many decks the player may save
--   EconomyManager.markDirty(player)    -> "please save the profile soon"
--   and uses profile.decks (saved decks) and profile.flags.starterGranted.
-- If EconomyManager isn't in the game (yet), everything still works, but only in memory:
-- every player gets the starter collection when they join and nothing is saved.

local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local DeckRules = require(Shared:WaitForChild("DeckRules"))

local PlayerDecks = {}

local economy = nil
local function getEconomy()
	if economy then
		return economy
	end
	local mod = ServerStorage:FindFirstChild("EconomyManager", true) or ServerScriptService:FindFirstChild("EconomyManager", true)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok and type(result) == "table" then
			economy = result
		end
	end
	return economy
end

local memory = {} -- [player] = { cards = {}, decks = {}, flags = {} } when there is no EconomyManager

local function slotKey(slot)
	return "s" .. slot -- saved with string keys, so a DataStore keeps empty slots in between
end

-- The player's profile tables: cards (a copy), decks and flags (live, write into them).
local function profile(player)
	local eco = getEconomy()
	if eco and eco.waitForData then
		local data = eco.waitForData(player)
		if not data then
			return nil
		end
		data.decks = type(data.decks) == "table" and data.decks or {}
		data.flags = type(data.flags) == "table" and data.flags or {}
		local cards = eco.getCollection and eco.getCollection(player) or data.cards or {}
		return { cards = cards, decks = data.decks, flags = data.flags, slots = eco.getDeckSlots and eco.getDeckSlots(player) or DeckRules.DefaultDeckSlots }
	end
	local m = memory[player]
	if not m then
		m = { cards = {}, decks = {}, flags = {} }
		memory[player] = m
	end
	return { cards = table.clone(m.cards), decks = m.decks, flags = m.flags, slots = DeckRules.DefaultDeckSlots }
end

local function markDirty(player)
	local eco = getEconomy()
	if eco and eco.markDirty then
		eco.markDirty(player)
	end
end

local function grant(player, ids)
	local eco = getEconomy()
	if eco and eco.grantCards then
		eco.grantCards(player, ids)
		return
	end
	local m = memory[player]
	if m then
		for _, id in ipairs(ids) do
			m.cards[id] = (m.cards[id] or 0) + 1
		end
	end
end

-- Gives a new player the starter collection and the Starter Deck (once per account).
function PlayerDecks.ensureStarter(player)
	local p = profile(player)
	if not p or p.flags.starterGranted then
		return p ~= nil
	end
	p.flags.starterGranted = true
	grant(player, DeckRules.starterGrant())
	if p.decks[slotKey(1)] == nil then
		p.decks[slotKey(1)] = DeckRules.starterDeck()
	end
	markDirty(player)
	return true
end

-- What the deck builder shows: { cards = { [id] = copies }, decks = { { slot, deck, ok, problems } }, slots }.
function PlayerDecks.snapshot(player)
	PlayerDecks.ensureStarter(player)
	local p = profile(player)
	if not p then
		return nil
	end
	local list = {}
	for slot = 1, p.slots do
		local deck = p.decks[slotKey(slot)]
		if type(deck) == "table" then
			local clean = DeckRules.sanitize(deck)
			local ok, problems = DeckRules.validate(clean, p.cards)
			table.insert(list, { slot = slot, deck = clean, ok = ok, problems = problems })
		end
	end
	return { cards = p.cards, decks = list, slots = p.slots }
end

-- Saves a deck into a slot. Decks that break the rules can still be saved (so you can finish
-- them later), but only legal decks can be played. Returns ok, problems.
function PlayerDecks.saveDeck(player, slot, raw)
	local p = profile(player)
	if not p then
		return false, { "Your collection hasn't loaded yet. Try again in a moment." }
	end
	if type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > p.slots then
		return false, { "That deck slot isn't yours yet" }
	end
	local deck = DeckRules.sanitize(raw)
	if not deck then
		return false, { "That isn't a deck" }
	end
	deck.lanes = DeckRules.fixLanes(deck.themes, deck.lanes)
	p.decks[slotKey(slot)] = deck
	markDirty(player)
	local ok, problems = DeckRules.validate(deck, p.cards)
	return ok, problems
end

function PlayerDecks.deleteDeck(player, slot)
	local p = profile(player)
	if p and type(slot) == "number" and p.decks[slotKey(slot)] ~= nil then
		p.decks[slotKey(slot)] = nil
		markDirty(player)
		return true
	end
	return false
end

-- The match setup for one of the player's saved decks, checked against what they own right now.
-- Returns setup (for MatchEngine.new) and the deck, or nil and the reason.
function PlayerDecks.setupFor(player, slot)
	local p = profile(player)
	if not p then
		return nil, "Your collection hasn't loaded yet"
	end
	local deck = type(slot) == "number" and p.decks[slotKey(slot)]
	if type(deck) ~= "table" then
		return nil, "That deck slot is empty"
	end
	deck = DeckRules.sanitize(deck)
	local ok, problems = DeckRules.validate(deck, p.cards)
	if not ok then
		return nil, problems[1]
	end
	return DeckRules.setupFor(deck), deck
end

function PlayerDecks.forget(player)
	memory[player] = nil
end

return PlayerDecks

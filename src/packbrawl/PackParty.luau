-- Pack Party controls: the "Open 1 pack" / "Open 10 packs" buttons (and, in Studio, a button per
-- tier to preview its cinematic). The server rolls the pull; this plays the Pack Brawl, then the
-- reveal. Used by the main game's Pack Party corner and by the test place's panel.
--
--   PackParty.mount(parent, {
--     onStart = function() end,  -- the cinematic is about to start (hide your UI)
--     onEnd = function(result) end, -- the reveal closed (show your UI again)
--     onStatus = function(text) end, -- short status lines ("Opening...", "Last pull: ...")
--     previews = true | false,  -- tier preview buttons (default: only in Studio)
--   })
-- Mounting again (for example after the parent was cleared) replaces the old buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local here = script.Parent
local Kit = require(here:WaitForChild("Kit"))
local Casting = require(here:WaitForChild("Casting"))
local Scripts = require(here:WaitForChild("Scripts"))
local Director = require(here:WaitForChild("Director"))
local Reveal = require(here:WaitForChild("Reveal"))
local PullRates = require(here:WaitForChild("PullRates"))
local CardData = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("CardData"))

local rgb, make = Kit.rgb, Kit.make

local PackParty = {}

local state = {
	busy = false,
	playing = false,
	opts = nil,
	connected = false,
}

local function status(text)
	local o = state.opts
	if o and o.onStatus then
		o.onStatus(text)
	end
end

local function remotes()
	local r = ReplicatedStorage:WaitForChild("PullRemotes")
	return r:WaitForChild("PullRequest"), r:WaitForChild("PullResult")
end

local function onResult(result)
	local best = result.best
	local id = result.cards[best]
	local cast = Casting.build(id, result.seed)
	local brawl = Scripts.build(cast)
	state.playing = true
	local o = state.opts
	if o and o.onStart then
		o.onStart()
	end
	status("")
	Director.play(brawl, function()
		local function back()
			state.playing = false
			state.busy = false
			local def = CardData.get(id)
			status(string.format("Last pull: %s (%s). You own %d different cards.", def.name, def.rarity, result.uniqueOwned or 0))
			local oo = state.opts
			if oo and oo.onEnd then
				oo.onEnd(result)
			end
		end
		Reveal.single({
			id = id,
			isNew = result.isNew[best],
			dupes = result.dupes[best],
			onDone = function()
				if #result.cards > 1 then
					Reveal.fan({ cards = result.cards, best = best, isNew = result.isNew, onDone = back })
				else
					back()
				end
			end,
		})
	end)
end

function PackParty.isPlaying()
	return state.playing or state.busy
end

function PackParty.request(count, tier)
	if state.busy then
		return
	end
	local PullRequest = remotes()
	state.busy = true
	local o = state.opts
	if o and o.onRequest then
		o.onRequest()
	end
	status("Opening...")
	PullRequest:FireServer(count, tier)
	-- if the server ignores us (cooldown), unlock again
	task.delay(3, function()
		if state.busy and not state.playing then
			state.busy = false
			status("Too fast! Try again in a moment.")
			local oo = state.opts
			if oo and oo.onEnd then
				oo.onEnd(nil)
			end
		end
	end)
end

local function button(parent, name, text, pos, size, color, textColor)
	local b = make("TextButton", { Name = name, Position = pos, Size = size, BackgroundColor3 = color, Text = text, Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = textColor or rgb(30, 25, 40) }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
	return b
end

-- Builds the buttons inside `parent` (a Frame at least about 340 x 150 pixels).
function PackParty.mount(parent, opts)
	state.opts = opts or {}
	if not state.connected then
		state.connected = true
		local _, PullResult = remotes()
		PullResult.OnClientEvent:Connect(onResult)
	end
	local previews = state.opts.previews
	if previews == nil then
		previews = RunService:IsStudio()
	end
	local holder = make("Frame", { Name = "PackPartyControls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, parent)
	local open1 = button(holder, "Open1", "Open 1 pack", UDim2.fromOffset(0, 0), UDim2.new(0.5, -5, 0, 44), rgb(255, 194, 26))
	local open10 = button(holder, "Open 10 packs", "Open 10 packs", UDim2.new(0.5, 5, 0, 0), UDim2.new(0.5, -5, 0, 44), rgb(255, 150, 90))
	open1.Activated:Connect(function()
		PackParty.request(1)
	end)
	open10.Activated:Connect(function()
		PackParty.request(10)
	end)
	make("TextLabel", {
		Name = "Odds",
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Text = "Odds: " .. string.format("Common %g%%  Rare %g%%  Epic %g%%  Mythic %g%%  Legendary %g%%  Secret %g%%", PullRates.Odds.Common, PullRates.Odds.Rare, PullRates.Odds.Epic, PullRates.Odds.Mythic, PullRates.Odds.Legendary, PullRates.Odds.Secret),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = rgb(190, 185, 205),
		TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)
	if previews then
		make("TextLabel", { Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = "Studio only: preview a tier's cinematic", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = rgb(160, 155, 180), TextXAlignment = Enum.TextXAlignment.Left }, holder)
		local n = #PullRates.Tiers
		for k, tier in ipairs(PullRates.Tiers) do
			local light = tier == "Rare" or tier == "Epic" or tier == "Mythic"
			local b = button(holder, "Preview_" .. tier, tier, UDim2.new((k - 1) / n, 2, 0, 108), UDim2.new(1 / n, -4, 0, 36), Kit.TierColor[tier], light and rgb(255, 255, 255) or nil)
			b.TextSize = 13
			b.Activated:Connect(function()
				PackParty.request(1, tier)
			end)
		end
	end
	return holder
end

return PackParty

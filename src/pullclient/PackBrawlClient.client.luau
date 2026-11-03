-- Pack Brawl test panel: open packs, preview each tier's cinematic, see the reveal.
-- In the full game this hooks onto the Pack Party corner of the menu room instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackBrawl = ReplicatedStorage:WaitForChild("PackBrawl")
local Kit = require(PackBrawl:WaitForChild("Kit"))
local Casting = require(PackBrawl:WaitForChild("Casting"))
local Scripts = require(PackBrawl:WaitForChild("Scripts"))
local Director = require(PackBrawl:WaitForChild("Director"))
local Reveal = require(PackBrawl:WaitForChild("Reveal"))
local PullRates = require(PackBrawl:WaitForChild("PullRates"))
local CardData = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("CardData"))
local remotes = ReplicatedStorage:WaitForChild("PullRemotes")
local PullRequest = remotes:WaitForChild("PullRequest")
local PullResult = remotes:WaitForChild("PullResult")

local rgb, make = Kit.rgb, Kit.make
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = make("ScreenGui", { Name = "PackPartyTest", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 10 }, playerGui)
local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(720, 170), BackgroundColor3 = rgb(24, 20, 38), BackgroundTransparency = 0.1 }, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Thickness = 3, Color = rgb(242, 230, 201) }, panel)
make("TextLabel", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 8), BackgroundTransparency = 1, Text = "PACK PARTY  ·  Pack Brawl test", Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = rgb(242, 230, 201), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local status = make("TextLabel", { Name = "Status", Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 40), BackgroundTransparency = 1, Text = "Open a pack, or preview a tier.", Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = rgb(210, 205, 225), TextXAlignment = Enum.TextXAlignment.Left }, panel)

local busy = false
local playing = false
local function setBusy(b)
	busy = b
	gui.Enabled = not b
end

local function button(text, x, y, w, color, textColor)
	local b = make("TextButton", { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 40), BackgroundColor3 = color, Text = text, Font = Enum.Font.FredokaOne, TextSize = 18, TextColor3 = textColor or rgb(30, 25, 40) }, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
	return b
end

local function request(count, tier)
	if busy then
		return
	end
	setBusy(true)
	status.Text = "Opening..."
	PullRequest:FireServer(count, tier)
	-- if the server ignores us (cooldown), unlock again
	task.delay(3, function()
		if busy and not playing then
			setBusy(false)
			status.Text = "Too fast! Try again in a moment."
		end
	end)
end

local open1 = button("Open 1 pack", 10, 70, 170, rgb(255, 194, 26))
local open10 = button("Open 10 packs", 190, 70, 170, rgb(255, 150, 90))
open1.Activated:Connect(function()
	request(1)
end)
open10.Activated:Connect(function()
	request(10)
end)
make("TextLabel", { Position = UDim2.fromOffset(372, 70), Size = UDim2.fromOffset(330, 40), BackgroundTransparency = 1, Text = "Odds: " .. string.format("C %g%%  R %g%%  E %g%%  M %g%%  L %g%%  S %g%%", PullRates.Odds.Common, PullRates.Odds.Rare, PullRates.Odds.Epic, PullRates.Odds.Mythic, PullRates.Odds.Legendary, PullRates.Odds.Secret), Font = Enum.Font.GothamMedium, TextSize = 13, TextWrapped = true, TextColor3 = rgb(190, 185, 205), TextXAlignment = Enum.TextXAlignment.Left }, panel)
for k, tier in ipairs(PullRates.Tiers) do
	local b = button(tier, 10 + (k - 1) * 117, 120, 110, Kit.TierColor[tier], (tier == "Rare" or tier == "Epic" or tier == "Mythic") and rgb(255, 255, 255) or nil)
	b.Name = "Preview_" .. tier
	b.Activated:Connect(function()
		request(1, tier)
	end)
end


PullResult.OnClientEvent:Connect(function(result)
	local best = result.best
	local id = result.cards[best]
	local cast = Casting.build(id, result.seed)
	local brawl = Scripts.build(cast)
	playing = true
	status.Text = ""
	Director.play(brawl, function()
		local function back()
			playing = false
			setBusy(false)
			local def = CardData.get(id)
			status.Text = string.format("Last pull: %s (%s). You own %d different cards.", def.name, def.rarity, result.uniqueOwned or 0)
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
end)

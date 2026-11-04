-- Deck Wars developer panel. This LocalScript sits in ServerStorage.DevControls, which only the
-- server can see; EconomyServer copies it into a player's PlayerGui only when DevAccess says
-- they're a developer. Normal players never receive it.
-- Every button still goes through the server, which checks DevAccess again, so a hacked
-- client can't use these remotes either.
--
-- Free Roll: plays a real Pack Brawl pull of the chosen rarity (or true odds) without spending
-- Gems. The normal "Open" buttons at the Pack Party stay as they are (they cost Gems and roll
-- the real odds), so you can still test true probability.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local Juice = require(Shared:WaitForChild("Juice"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local remotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local DevAction = remotes:WaitForChild("DevAction")
local EconomyEvent = remotes:WaitForChild("EconomyEvent")

local rgb, make = Juice.rgb, Juice.make
local gui = script.Parent
local player = Players.LocalPlayer

local TIERS = { "Common", "Rare", "Epic", "Mythic", "Legendary", "Secret" }
local TIER_COLOR = {
	Common = rgb(170, 165, 150),
	Rare = rgb(61, 165, 255),
	Epic = rgb(166, 77, 255),
	Mythic = rgb(255, 59, 92),
	Legendary = rgb(255, 194, 26),
	Secret = rgb(255, 255, 255),
}
local INK = rgb(18, 14, 28)
local PANEL = rgb(24, 20, 38)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(170, 164, 190)

local function corner(o, r)
	make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end

local function label(parent, text, props)
	local l = make("TextLabel", { BackgroundTransparency = 1, Text = text, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18) }, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent, text, color, onClick, props)
	local b = make("TextButton", { Text = text, Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = INK, BackgroundColor3 = color, AutoButtonColor = false, Size = UDim2.fromOffset(90, 32) }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 8)
	make("UIStroke", { Thickness = 2, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	Juice.button(b, { grow = 1.04 })
	b.Activated:Connect(onClick)
	return b
end

-- The panel (hidden until the DEV tab is clicked or F7 is pressed)
local tab = button(gui, "DEV", rgb(255, 120, 60), function() end, {
	Name = "DevTab",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 0, 0.5, 0),
	Size = UDim2.fromOffset(46, 74),
	TextSize = 16,
})
local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 54, 0.5, 0), Size = UDim2.fromOffset(330, 470), BackgroundColor3 = PANEL, BackgroundTransparency = 0.04, Visible = false }, gui)
corner(panel, 14)
make("UIStroke", { Thickness = 3, Color = rgb(255, 120, 60) }, panel)
make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 10) }, panel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local order = 0
local function nextOrder()
	order += 1
	return order
end

label(panel, "DEV CONTROLS", { Font = Enum.Font.FredokaOne, TextSize = 22, Size = UDim2.new(1, 0, 0, 26), TextColor3 = rgb(255, 160, 90), LayoutOrder = nextOrder() })
label(panel, "You: " .. tostring(gui:GetAttribute("Who") or player.Name), { Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = DIM, LayoutOrder = nextOrder() })
local status = label(panel, "Free rolls don't cost Gems. Pack Party's Open buttons still cost Gems and use the real odds.", { Name = "Status", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder() })

local function say(text, good)
	status.Text = text
	status.TextColor3 = good == false and rgb(255, 130, 120) or (good and rgb(140, 230, 150) or DIM)
end

-- Ask the main client to open the Pack Party and pull.
local function freeRoll(count, tier)
	local scripts = player:FindFirstChild("PlayerScripts")
	local client = scripts and scripts:FindFirstChild("DeckWarsClient")
	local hook = client and client:FindFirstChild("ClientHook")
	if not hook then
		say("The game's client isn't ready yet.", false)
		return
	end
	local ok, res, why = pcall(function()
		return hook:Invoke("freeRoll", count, tier)
	end)
	if ok and res then
		say("Free roll: " .. (tier or "true odds") .. (count == 10 and " x10" or ""), true)
	else
		say("Can't roll now: " .. tostring(ok and why or res), false)
	end
end

local function row(height)
	local r = make("Frame", { Size = UDim2.new(1, 0, 0, height or 32), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, r)
	return r
end

label(panel, "Free Roll / Test Rarity", { Font = Enum.Font.FredokaOne, TextSize = 17, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder() })
local tierGrid = make("Frame", { Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, panel)
make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -4, 0, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tierGrid)
for i, tier in ipairs(TIERS) do
	local light = tier == "Rare" or tier == "Epic" or tier == "Mythic"
	button(tierGrid, tier, TIER_COLOR[tier], function()
		freeRoll(1, tier)
	end, { Name = "Free_" .. tier, LayoutOrder = i, TextColor3 = light and rgb(255, 255, 255) or INK })
end
local odds = row()
button(odds, "Free 1 (real odds)", rgb(255, 214, 102), function()
	freeRoll(1, nil)
end, { Name = "Free_1", Size = UDim2.new(0.5, -3, 1, 0) })
button(odds, "Free 10 (real odds)", rgb(255, 170, 90), function()
	freeRoll(10, nil)
end, { Name = "Free_10", Size = UDim2.new(0.5, -3, 1, 0) })

label(panel, "Wallet", { Font = Enum.Font.FredokaOne, TextSize = 17, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder() })
local wallet = row()
button(wallet, "+1,000 💎", rgb(110, 200, 255), function()
	DevAction:FireServer("GiveGems", 1000)
end, { Name = "GiveGems", Size = UDim2.new(1 / 3, -4, 1, 0) })
button(wallet, "+10,000 🪙", rgb(255, 200, 70), function()
	DevAction:FireServer("GiveCoins", 10000)
end, { Name = "GiveCoins", Size = UDim2.new(1 / 3, -4, 1, 0) })
button(wallet, "🍀 10 lucky", rgb(140, 220, 120), function()
	DevAction:FireServer("Luck", 10)
end, { Name = "Luck", Size = UDim2.new(1 / 3, -4, 1, 0) })

label(panel, "Shop and save", { Font = Enum.Font.FredokaOne, TextSize = 17, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder() })
local shopRow = row()
button(shopRow, "New shop day", rgb(200, 180, 255), function()
	DevAction:FireServer("NewDay")
end, { Name = "NewDay", Size = UDim2.new(0.5, -3, 1, 0) })
local armedUntil = 0
local reset
reset = button(shopRow, "Reset my save", rgb(255, 110, 110), function()
	if os.clock() > armedUntil then
		armedUntil = os.clock() + 3
		reset.Text = "Sure? Tap again"
		task.delay(3, function()
			if os.clock() >= armedUntil then
				reset.Text = "Reset my save"
			end
		end)
		return
	end
	armedUntil = 0
	reset.Text = "Reset my save"
	DevAction:FireServer("ResetSave")
end, { Name = "ResetSave", Size = UDim2.new(0.5, -3, 1, 0) })

local balance = label(panel, "", { Name = "Balance", Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = nextOrder() })
local function showBalance()
	balance.Text = string.format("%s %s   %s %s   (F7 shows/hides this panel)", ShopCatalog.Icon.Gems, ShopCatalog.format(player:GetAttribute("Gems") or 0), ShopCatalog.Icon.Coins, ShopCatalog.format(player:GetAttribute("Coins") or 0))
end
player:GetAttributeChangedSignal("Gems"):Connect(showBalance)
player:GetAttributeChangedSignal("Coins"):Connect(showBalance)
showBalance()

EconomyEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "dev" and type(payload) == "table" then
		say(payload.message or "", payload.ok)
	end
end)

local function toggle()
	panel.Visible = not panel.Visible
	if panel.Visible then
		Juice.popIn(panel, 0, { twist = 0, sound = false, time = 0.3 })
	end
end
tab.Activated:Connect(toggle)
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F7 and not UserInputService:GetFocusedTextBox() then
		toggle()
	end
end)

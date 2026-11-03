-- Pack Brawl test panel: open packs, preview each tier's cinematic, see the reveal.
-- The buttons come from PackParty.luau, the same ones the main game's Pack Party corner uses.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PackBrawl = ReplicatedStorage:WaitForChild("PackBrawl")
local Kit = require(PackBrawl:WaitForChild("Kit"))
local PackParty = require(PackBrawl:WaitForChild("PackParty"))

local rgb, make = Kit.rgb, Kit.make
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = make("ScreenGui", { Name = "PackPartyTest", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 10 }, playerGui)
local panel = make("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(720, 220), BackgroundColor3 = rgb(24, 20, 38), BackgroundTransparency = 0.1 }, gui)
make("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
make("UIStroke", { Thickness = 3, Color = rgb(242, 230, 201) }, panel)
make("TextLabel", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 8), BackgroundTransparency = 1, Text = "PACK PARTY  ·  Pack Brawl test", Font = Enum.Font.FredokaOne, TextSize = 24, TextColor3 = rgb(242, 230, 201), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local status = make("TextLabel", { Name = "Status", Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 40), BackgroundTransparency = 1, Text = "Open a pack, or preview a tier.", Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = rgb(210, 205, 225), TextXAlignment = Enum.TextXAlignment.Left }, panel)
local area = make("Frame", { Name = "Controls", Position = UDim2.fromOffset(10, 68), Size = UDim2.new(1, -20, 1, -76), BackgroundTransparency = 1 }, panel)

PackParty.mount(area, {
	previews = true,
	onRequest = function()
		gui.Enabled = false
	end,
	onStart = function()
		gui.Enabled = false
	end,
	onEnd = function()
		gui.Enabled = true
	end,
	onStatus = function(text)
		status.Text = text
	end,
})

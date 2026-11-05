-- The Trophy Road box at the Trophy Wall. Client only.
--
-- Every match you finish earns trophies (Progression.trophiesFor; a win against a Hard bot or
-- people earns the most) and they never go down. The road is a row of stops: Coins, Gems and
-- three match backgrounds you can't buy (Sunset Grasslands, Ember Caldera, Cosmic Void). Reach a
-- stop, tap it to claim. The server keeps the count (PlayerData: attributes "Trophies" and
-- "RoadClaimed" = "1,2,5") and pays out (MenuAction "ClaimRoad").
--
--   TrophyRoadUI.render(parent, layoutOrder, kit) -> the box (kit: { BODY_FONT, MenuAction })

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local here = script.Parent
local Progression = require(here:WaitForChild("Progression"))
local ShopCatalog = require(here:WaitForChild("ShopCatalog"))
local Backdrops = require(here:WaitForChild("Backdrops"))
local Juice = require(here:WaitForChild("Juice"))

local rgb, make, tween = Juice.rgb, Juice.make, Juice.tween

local TrophyRoadUI = {}

local GOLD = rgb(255, 214, 102)
local TROPHY = rgb(255, 176, 70)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(176, 170, 196)
local GOOD = rgb(80, 200, 120)
local TILE = rgb(44, 38, 64)
local INK = rgb(16, 12, 26)
local WHITE = Color3.new(1, 1, 1)
local TITLE_FONT = Enum.Font.FredokaOne

local STOP_W = 78 -- width of one stop on the track
local hooked = false

local function corner(obj, r)
	make("UICorner", { CornerRadius = r and UDim.new(0, r) or UDim.new(1, 0) }, obj)
end

local function claimedSet()
	local out = {}
	local raw = Players.LocalPlayer:GetAttribute("RoadClaimed")
	if type(raw) == "string" then
		for n in string.gmatch(raw, "%d+") do
			out[tonumber(n)] = true
		end
	end
	return out
end

-- What a stop gives, as an icon and a short line.
function TrophyRoadUI.reward(stop)
	if stop.cosmetic then
		local c = ShopCatalog.CosmeticById[stop.cosmetic]
		local info = c and Backdrops.ByKey[c.backdrop or ""]
		return info and info.emoji or "🎁", c and c.name or "Reward", info and info.colors or nil
	elseif stop.gems then
		return "💎", "+" .. ShopCatalog.format(stop.gems) .. " Gems", nil
	end
	return "🪙", "+" .. ShopCatalog.format(stop.coins or 0) .. " Coins", nil
end

local function hookToasts()
	if hooked then
		return
	end
	hooked = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	remotes:WaitForChild("LobbyEvent").OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" or payload.kind ~= "claimed" or payload.what ~= "road" or not payload.ok then
			return
		end
		local ShopUI = require(here:WaitForChild("ShopUI"))
		local stop = Progression.TrophyRoad[tonumber(payload.index) or 0]
		if stop then
			local icon, line = TrophyRoadUI.reward(stop)
			local extra = stop.cosmetic and "  (wear it at the Deck Shelf > Backgrounds)" or ""
			ShopUI.toast("🏆 Trophy Road: " .. line .. extra, "good", { big = true, icon = icon, time = 5 })
		end
		Juice.sound("chime", 1.3, 0.5)
		local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
		local gui = pg and pg:FindFirstChild("DeckWarsToasts")
		if gui then
			Juice.confetti(gui, 0.5, 0.3, 36)
		end
	end)
end

function TrophyRoadUI.render(parent, order, kit)
	hookToasts()
	local player = Players.LocalPlayer
	local road = Progression.TrophyRoad
	local box = make("Frame", { Name = "TrophyRoad", Size = UDim2.new(1, -8, 0, 164), BackgroundColor3 = TILE, LayoutOrder = order or 0, BorderSizePixel = 0 }, parent)
	corner(box, 12)
	make("UIStroke", { Thickness = 1.5, Color = TROPHY, Transparency = 0.45 }, box)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(rgb(255, 255, 255), rgb(200, 190, 215)) }, box)
	local title = make("TextLabel", { Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24), Font = TITLE_FONT, TextSize = 20, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Text = "🏆 Trophy Road" }, box)
	local count = make("TextLabel", { Name = "Count", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 24), Font = TITLE_FONT, TextSize = 18, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right, Text = "" }, box)
	local sub = make("TextLabel", { Name = "Sub", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 16), Font = kit and kit.BODY_FONT or Enum.Font.GothamMedium, TextSize = 12, TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, box)
	local T = Progression.Trophies
	sub.Text = "Every finished match earns trophies: a win " .. T.win.Easy .. "-" .. T.win.Hard .. " (" .. T.pvpWin .. " against people), a loss " .. T.finish .. "."
	-- the track: a scrolling row of stops on a line that fills up as you go
	local track = make("ScrollingFrame", {
		Name = "Track",
		Position = UDim2.fromOffset(8, 52),
		Size = UDim2.new(1, -16, 0, 106),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.X,
		CanvasSize = UDim2.fromOffset(#road * STOP_W + 20, 0),
		ElasticBehavior = Enum.ElasticBehavior.Never,
	}, box)
	local lineBack = make("Frame", { Position = UDim2.fromOffset(10 + STOP_W / 2, 30), Size = UDim2.fromOffset((#road - 1) * STOP_W, 6), BackgroundColor3 = INK, BorderSizePixel = 0 }, track)
	corner(lineBack, 3)
	local lineFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = TROPHY, BorderSizePixel = 0 }, lineBack)
	corner(lineFill, 3)
	make("UIGradient", { Color = ColorSequence.new(rgb(255, 214, 120), rgb(255, 140, 60)) }, lineFill)
	local stops = {}
	for i, stop in ipairs(road) do
		local x = 10 + (i - 1) * STOP_W
		local holder = make("Frame", { Name = "Stop" .. i, Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(STOP_W, 104), BackgroundTransparency = 1 }, track)
		local icon, line, colors = TrophyRoadUI.reward(stop)
		local bubble = make("TextButton", { Name = "Bubble", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(stop.cosmetic and 54 or 46, stop.cosmetic and 54 or 46), BackgroundColor3 = rgb(60, 54, 84), AutoButtonColor = false, Text = icon, TextScaled = true, Font = Enum.Font.GothamBold, TextColor3 = WHITE, BorderSizePixel = 0, ZIndex = 3 }, holder)
		if stop.cosmetic then
			bubble.Position = UDim2.new(0.5, 0, 0, 2)
		end
		corner(bubble)
		make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, bubble)
		local stroke = make("UIStroke", { Thickness = 2.5, Color = INK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bubble)
		if colors then
			make("UIGradient", { Rotation = 90, Color = ColorSequence.new(colors[1], colors[2]) }, bubble)
		end
		local at = make("TextLabel", { Name = "At", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 16), Font = TITLE_FONT, TextSize = 14, TextColor3 = WHITE, Text = tostring(stop.at) .. " 🏆" }, holder)
		local what = make("TextLabel", { Name = "What", BackgroundTransparency = 1, Position = UDim2.fromOffset(2, 78), Size = UDim2.new(1, -4, 0, 24), Font = kit and kit.BODY_FONT or Enum.Font.GothamMedium, TextSize = 10, TextWrapped = true, TextColor3 = DIM, Text = line, TextYAlignment = Enum.TextYAlignment.Top }, holder)
		bubble.Activated:Connect(function()
			local have = player:GetAttribute("Trophies") or 0
			if claimedSet()[i] then
				return
			end
			if have >= stop.at then
				local MenuAction = kit and kit.MenuAction or ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MenuAction")
				MenuAction:FireServer("ClaimRoad", { index = i })
				Juice.pop(bubble, 1.25, 0.4)
			else
				Juice.shake(bubble, 4, 0.25)
			end
		end)
		Juice.button(bubble, { grow = 1.08 })
		stops[i] = { bubble = bubble, stroke = stroke, at = at, what = what, stop = stop }
	end

	local function refresh()
		local have = player:GetAttribute("Trophies") or 0
		local claimed = claimedSet()
		local nextStop = nil
		for _, st in ipairs(road) do
			if have < st.at then
				nextStop = st
				break
			end
		end
		count.Text = ShopCatalog.format(have) .. " 🏆"
		title.Text = "🏆 Trophy Road" .. (nextStop and ("  ·  next at " .. nextStop.at) or "  ·  complete!")
		-- the line fills to where you are between the stops
		local fill = 0
		for i = 1, #road - 1 do
			local a, b = road[i].at, road[i + 1].at
			if have >= b then
				fill = i
			elseif have > a then
				fill = (i - 1) + (have - a) / (b - a)
				break
			else
				break
			end
		end
		if have < road[1].at then
			fill = 0
		end
		tween(lineFill, 0.5, { Size = UDim2.fromScale(math.clamp(fill / math.max(1, #road - 1), 0, 1), 1) })
		local focus = nil
		for i, s in ipairs(stops) do
			local done = claimed[i]
			local ready = not done and have >= s.stop.at
			s.stroke.Color = ready and GOLD or (done and GOOD or INK)
			s.stroke.Thickness = ready and 3.5 or 2.5
			s.bubble.BackgroundColor3 = done and GOOD:Lerp(TILE, 0.45) or (ready and rgb(120, 90, 40) or rgb(60, 54, 84))
			s.bubble.TextTransparency = (done or ready or s.stop.cosmetic) and 0 or 0.35
			s.at.Text = done and "✓ claimed" or (ready and "Claim!" or (tostring(s.stop.at) .. " 🏆"))
			s.at.TextColor3 = done and GOOD or (ready and GOLD or WHITE)
			if ready and not focus then
				focus = i
			end
			if not focus and not done and have < s.stop.at then
				focus = i
			end
		end
		-- keep the next thing to do in view
		if focus then
			local x = math.max(0, (focus - 2) * STOP_W)
			track.CanvasPosition = Vector2.new(x, 0)
		end
	end
	local conns = {}
	for _, attr in ipairs({ "Trophies", "RoadClaimed" }) do
		table.insert(conns, player:GetAttributeChangedSignal(attr):Connect(function()
			if not box.Parent then
				for _, c in ipairs(conns) do
					c:Disconnect()
				end
				return
			end
			refresh()
		end))
	end
	refresh()
	return box
end

return TrophyRoadUI

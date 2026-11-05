-- How the Shop's cosmetics look: board themes (the duel table's felt, rim, frame and inlays),
-- card backs, and emote bubbles. Client only. What you OWN is decided by the server
-- (EconomyManager); this module only paints what the server says is equipped.
--
--   Cosmetics.setEquipped({ board = "board_ember", cardback = "back_gold" })
--   Cosmetics.styleBack(frame, small)          -- restyles a card back made by the client
--   Cosmetics.previewBack(parent, backId)      -- a little card back for the Shop
--   Cosmetics.emote(adornee, emoteId)          -- pops an emote bubble over a part

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local ShopCatalog = require(script.Parent:WaitForChild("ShopCatalog"))

local Cosmetics = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

---------------------------------------------------------------------------
-- Board themes
---------------------------------------------------------------------------
-- Which table parts each theme slot paints (by part name inside Stations.DuelTable).
Cosmetics.BoardSlots = {
	felt = { "Felt" },
	rim = { "Rim", "TableTop", "Apron" },
	frame = { "BoardFrame", "Stretcher" },
	trim = { "Inlay", "RimCorner", "FrameCap", "HalfwayLine", "HalfwayMark" },
}
-- nil = keep the part's original look (Walnut Classic is the table as built).
Cosmetics.Boards = {
	board_walnut = {},
	board_midnight = {
		felt = { rgb(30, 40, 96), Enum.Material.Fabric },
		rim = { rgb(26, 26, 38), Enum.Material.Wood },
		frame = { rgb(44, 46, 66), Enum.Material.Wood },
		trim = { rgb(205, 214, 232), Enum.Material.Metal },
	},
	board_emerald = {
		felt = { rgb(18, 112, 72), Enum.Material.Fabric },
		rim = { rgb(20, 20, 22), Enum.Material.SmoothPlastic },
		frame = { rgb(28, 28, 32), Enum.Material.SmoothPlastic },
		trim = { rgb(236, 186, 64), Enum.Material.Metal },
	},
	board_ember = {
		felt = { rgb(64, 24, 18), Enum.Material.Fabric },
		rim = { rgb(42, 27, 21), Enum.Material.Wood },
		frame = { rgb(58, 32, 24), Enum.Material.Wood },
		trim = { rgb(255, 122, 40), Enum.Material.Neon },
	},
	board_frost = {
		felt = { rgb(150, 200, 232), Enum.Material.Fabric },
		rim = { rgb(226, 216, 196), Enum.Material.Wood },
		frame = { rgb(236, 229, 212), Enum.Material.Wood },
		trim = { rgb(120, 222, 255), Enum.Material.Neon },
	},
	board_starlight = {
		felt = { rgb(26, 18, 56), Enum.Material.Fabric },
		rim = { rgb(32, 22, 52), Enum.Material.Wood },
		frame = { rgb(48, 32, 84), Enum.Material.Wood },
		trim = { rgb(196, 124, 255), Enum.Material.Neon },
	},
}

local equipped = { board = ShopCatalog.DefaultEquipped.board, cardback = ShopCatalog.DefaultEquipped.cardback, backdrop = ShopCatalog.DefaultEquipped.backdrop }
local listeners = {}

local function duelTable()
	local room = workspace:FindFirstChild("MenuRoom")
	local st = room and room:FindFirstChild("Stations")
	return st and st:FindFirstChild("DuelTable")
end

-- Paints the duel table with a theme (missing parts are skipped, so a rebuilt table still works).
function Cosmetics.applyBoard(tableModel, themeId)
	if not tableModel then
		return
	end
	local theme = Cosmetics.Boards[themeId] or Cosmetics.Boards.board_walnut
	local slotOf = {}
	for slot, names in pairs(Cosmetics.BoardSlots) do
		for _, n in ipairs(names) do
			slotOf[n] = slot
		end
	end
	for _, d in ipairs(tableModel:GetDescendants()) do
		local slot = d:IsA("BasePart") and slotOf[d.Name]
		if slot then
			-- remember the built look the first time, so Walnut Classic can put it back
			if d:GetAttribute("BaseColor") == nil then
				d:SetAttribute("BaseColor", d.Color)
				d:SetAttribute("BaseMaterial", d.Material.Name)
			end
			local look = theme[slot]
			if look then
				d.Color = look[1]
				d.Material = look[2]
			else
				d.Color = d:GetAttribute("BaseColor")
				local mat = Enum.Material[d:GetAttribute("BaseMaterial")]
				if mat then
					d.Material = mat
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Card backs
---------------------------------------------------------------------------
Cosmetics.Backs = {
	back_indigo = { base = rgb(46, 52, 128), a = rgb(120, 130, 230), b = rgb(70, 40, 120), stroke = rgb(240, 200, 90), text = rgb(255, 225, 120) },
	back_crimson = { base = rgb(120, 20, 30), a = rgb(222, 62, 62), b = rgb(88, 10, 24), stroke = rgb(255, 210, 110), text = rgb(255, 232, 150) },
	back_jade = { base = rgb(20, 90, 60), a = rgb(84, 204, 142), b = rgb(14, 66, 48), stroke = rgb(232, 242, 204), text = rgb(232, 255, 222) },
	back_gold = { base = rgb(180, 130, 30), a = rgb(255, 232, 132), b = rgb(168, 108, 20), stroke = rgb(255, 250, 222), text = rgb(92, 56, 10), shine = true },
	back_void = { base = rgb(25, 10, 45), a = rgb(150, 60, 255), b = rgb(10, 0, 30), stroke = rgb(190, 140, 255), text = rgb(222, 192, 255), spin = true },
}

local spinning = setmetatable({}, { __mode = "k" }) -- gradients that turn slowly (Void Spiral)
local spinConn = nil
local function startSpin()
	if spinConn then
		return
	end
	spinConn = RunService.RenderStepped:Connect(function(dt)
		for g in pairs(spinning) do
			if g.Parent then
				g.Rotation = (g.Rotation + dt * 40) % 360
			else
				spinning[g] = nil
			end
		end
	end)
end

-- Paints a card back frame (made by the client's makeCardBack: a Frame with a UIStroke, a
-- UIGradient and a TextLabel) in the given or equipped style.
function Cosmetics.styleBack(frame, small, backId)
	local s = Cosmetics.Backs[backId or equipped.cardback] or Cosmetics.Backs.back_indigo
	frame.BackgroundColor3 = s.base
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = s.stroke
	end
	local grad = frame:FindFirstChildOfClass("UIGradient")
	if grad then
		grad.Color = ColorSequence.new(s.a, s.b)
		if s.spin then
			spinning[grad] = true
			startSpin()
		else
			spinning[grad] = nil
		end
	end
	local text = frame:FindFirstChildOfClass("TextLabel")
	if text then
		text.TextColor3 = s.text
	end
	if s.shine and not frame:FindFirstChild("Foil") then
		local foil = make("Frame", { Name = "Foil", Size = UDim2.new(0.35, 0, 1.4, 0), Position = UDim2.fromScale(-0.5, -0.2), Rotation = 20, BackgroundColor3 = rgb(255, 255, 255), BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = frame.ZIndex + 1 }, frame)
		frame.ClipsDescendants = true
		task.spawn(function()
			while foil.Parent do
				foil.Position = UDim2.fromScale(-0.5, -0.2)
				TweenService:Create(foil, TweenInfo.new(1.1, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(1.3, -0.2) }):Play()
				task.wait(3.5)
			end
		end)
	end
	return frame
end

-- A small card back for the Shop tiles.
function Cosmetics.previewBack(parent, backId, size)
	local back = make("Frame", { Name = "BackPreview", Size = size or UDim2.fromOffset(64, 90), BackgroundColor3 = rgb(46, 52, 128) }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, back)
	make("UIStroke", { Thickness = 3, Color = rgb(240, 200, 90) }, back)
	make("UIGradient", { Rotation = 60, Color = ColorSequence.new(rgb(120, 130, 230), rgb(70, 40, 120)) }, back)
	make("TextLabel", { Size = UDim2.fromScale(0.86, 0.4), Position = UDim2.fromScale(0.07, 0.3), BackgroundTransparency = 1, Text = "DECK\nWARS", Font = Enum.Font.FredokaOne, TextScaled = true, TextColor3 = rgb(255, 225, 120) }, back)
	return Cosmetics.styleBack(back, true, backId)
end

-- A little picture of a board theme for the Shop tiles (felt inside a rim, with trim lines).
function Cosmetics.previewBoard(parent, themeId, size)
	local theme = Cosmetics.Boards[themeId] or {}
	local rim = (theme.rim and theme.rim[1]) or rgb(92, 58, 36)
	local felt = (theme.felt and theme.felt[1]) or rgb(40, 88, 56)
	local trim = (theme.trim and theme.trim[1]) or rgb(214, 172, 92)
	local frame = (theme.frame and theme.frame[1]) or rgb(150, 110, 70)
	local box = make("Frame", { Name = "BoardPreview", Size = size or UDim2.fromOffset(96, 66), BackgroundColor3 = rim }, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, box)
	local f = make("Frame", { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = felt }, box)
	make("UICorner", { CornerRadius = UDim.new(0, 5) }, f)
	make("UIStroke", { Thickness = 2, Color = trim }, f)
	local b = make("Frame", { Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.19, 0.19), BackgroundColor3 = felt:Lerp(rgb(0, 0, 0), 0.25) }, f)
	make("UIStroke", { Thickness = 2, Color = frame }, b)
	make("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = trim, BorderSizePixel = 0 }, b)
	return box
end

---------------------------------------------------------------------------
-- What's equipped
---------------------------------------------------------------------------
function Cosmetics.equipped()
	return equipped
end

-- Called with the server's snapshot.equipped. Repaints the table at once.
function Cosmetics.setEquipped(eq)
	if type(eq) ~= "table" then
		return
	end
	local boardChanged = eq.board ~= nil and eq.board ~= equipped.board
	local backChanged = eq.cardback ~= nil and eq.cardback ~= equipped.cardback
	local worldChanged = eq.backdrop ~= nil and eq.backdrop ~= equipped.backdrop
	equipped.board = eq.board or equipped.board
	equipped.cardback = eq.cardback or equipped.cardback
	equipped.backdrop = eq.backdrop or equipped.backdrop
	if boardChanged or not Cosmetics._painted then
		Cosmetics._painted = true
		Cosmetics.applyBoard(duelTable(), equipped.board)
	end
	if boardChanged or backChanged or worldChanged or not Cosmetics._told then
		Cosmetics._told = true
		for _, fn in ipairs(listeners) do
			task.spawn(fn, equipped)
		end
	end
end

function Cosmetics.onChanged(fn)
	table.insert(listeners, fn)
end

---------------------------------------------------------------------------
-- Emotes
---------------------------------------------------------------------------
-- Pops a speech bubble with the emote over `adornee` (a BasePart) for a few seconds.
function Cosmetics.emote(adornee, emoteId, opts)
	local c = ShopCatalog.CosmeticById[emoteId]
	if not c or c.kind ~= "emote" or not adornee then
		return nil
	end
	opts = opts or {}
	local old = adornee:FindFirstChild("EmoteBubble")
	if old then
		old:Destroy()
	end
	local bb = make("BillboardGui", { Name = "EmoteBubble", Size = UDim2.fromOffset(190, 74), StudsOffset = Vector3.new(0, opts.height or 3.2, 0), AlwaysOnTop = true, LightInfluence = 0, Adornee = adornee }, adornee)
	local bubble = make("Frame", { Name = "Bubble", Size = UDim2.fromScale(1, 1), BackgroundColor3 = opts.color or rgb(255, 250, 238) }, bb)
	make("UICorner", { CornerRadius = UDim.new(0, 18) }, bubble)
	make("UIStroke", { Thickness = 3, Color = rgb(28, 20, 40) }, bubble)
	local scale = make("UIScale", { Scale = 0.2 }, bubble)
	make("TextLabel", { Name = "Icon", Size = UDim2.new(0, 58, 1, -8), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1, Text = c.icon or "💬", TextScaled = true, Font = Enum.Font.FredokaOne }, bubble)
	make("TextLabel", { Name = "Words", Size = UDim2.new(1, -76, 1, -12), Position = UDim2.fromOffset(68, 6), BackgroundTransparency = 1, Text = c.name, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = rgb(36, 26, 50), TextXAlignment = Enum.TextXAlignment.Left }, bubble)
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(opts.time or 2.6, function()
		if bb.Parent then
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
			task.wait(0.3)
			bb:Destroy()
		end
	end)
	return bb
end

return Cosmetics

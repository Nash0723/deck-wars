-- The Plaza on your screen: walking out of the room's front door into the shared square, your
-- avatar with Roblox's own camera and controls, nameplates and companions over everyone, the cards
-- on the booths, likes, the Pull Altar (opens packs right there), the Hall of Pulls, the
-- leaderboards and the big-pull banners (those show in the room too). Client only.
--
--   PlazaClient.init(ctx)        once, from DeckWarsClient (ctx: see the bottom of DeckWarsClient)
--   PlazaClient.doorPanel(body)  the front door station's panel (who's out there, "Walk out")
--   PlazaClient.enter() / PlazaClient.leave(instant, thenStation)
--   PlazaClient.isInside()
--
-- The server (PlazaServer) owns booths, likes and showcases; this only shows its attributes and
-- events. The place itself is Workspace.Plaza (see PlazaBuilder for the names it uses).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")

local here = script.Parent
local Plaza = require(here:WaitForChild("Plaza"))
local CardData = require(here:WaitForChild("CardData"))
local Juice = require(here:WaitForChild("Juice"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotes = ReplicatedStorage:WaitForChild("PlazaRemotes")
local PlazaAction = remotes:WaitForChild("PlazaAction")
local PlazaEvent = remotes:WaitForChild("PlazaEvent")

local rgb, make = Juice.rgb, Juice.make
local INK = rgb(18, 14, 28)
local PANEL = rgb(30, 25, 46)
local TILE = rgb(42, 36, 62)
local GOLD = rgb(255, 214, 102)
local TEXT = rgb(236, 232, 246)
local DIM = rgb(170, 164, 190)
local GOOD = rgb(70, 190, 110)
local HEART = rgb(240, 80, 110)
local TITLE_FONT = Enum.Font.FredokaOne
local BODY_FONT = Enum.Font.GothamMedium

local function rarityColor(rarity)
	local c = CardData.RarityColors[rarity]
	return c and rgb(c[1], c[2], c[3]) or TEXT
end

local PlazaClient = {}

local S = {
	ctx = nil,
	inside = false,
	busy = false, -- walking in or out
	gui = nil, -- the Plaza's own ScreenGui (HUD, booth editor, pack panel)
	banners = nil, -- the banner ScreenGui (also used in the room)
	hall = {},
	boards = {},
	state = nil, -- the "state" event (your booth's cards, titles)
	savedLight = nil,
	plates = {}, -- [player] = BillboardGui
	pets = {}, -- [player] = { model, id, pos }
	boothDrawn = {}, -- [slot] = "cards string" drawn
	editor = nil,
	packPanel = nil,
}

local function corner(p, r)
	return make("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

local function stroke(p, color, t)
	return make("UIStroke", { Color = color or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end

local function text(parent, str, props)
	local t = make("TextLabel", { BackgroundTransparency = 1, Text = str, Font = BODY_FONT, TextSize = 14, TextColor3 = TEXT, TextWrapped = true, Size = UDim2.new(1, 0, 0, 18) }, parent)
	for k, v in pairs(props or {}) do
		t[k] = v
	end
	return t
end

local function button(parent, str, color, onClick, props)
	local b = make("TextButton", { AutoButtonColor = false, BackgroundColor3 = color, Text = str, Font = TITLE_FONT, TextSize = 17, TextColor3 = TEXT, Size = UDim2.fromOffset(120, 40) }, parent)
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	corner(b, 10)
	stroke(b, INK, 2)
	Juice.button(b)
	b.Activated:Connect(onClick)
	return b
end

local function toast(msg)
	if S.ctx and S.ctx.toast then
		S.ctx.toast(msg)
	end
end

local function plazaModel()
	return workspace:FindFirstChild("Plaza")
end

---------------------------------------------------------------------------
-- Light: golden hour out here, the room's own light back inside
---------------------------------------------------------------------------

local PLAZA_LIGHT = {
	ClockTime = 16.8,
	Brightness = 2.4,
	Ambient = rgb(92, 84, 92),
	OutdoorAmbient = rgb(140, 128, 140),
	ColorShift_Top = rgb(255, 214, 170),
	ColorShift_Bottom = rgb(60, 50, 60),
	EnvironmentDiffuseScale = 0.5,
	EnvironmentSpecularScale = 0.5,
	ExposureCompensation = 0.1,
	FogEnd = 1400,
	FogStart = 300,
	FogColor = rgb(250, 210, 170),
}

local function swapLight(on)
	if on and not S.savedLight then
		local saved = { props = {}, effects = {}, made = {} }
		for k, v in pairs(PLAZA_LIGHT) do
			saved.props[k] = Lighting[k]
			Lighting[k] = v
		end
		local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
		if dof then
			saved.effects[dof] = { FarIntensity = dof.FarIntensity }
			dof.FarIntensity = 0.05
		end
		local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		if cc then
			saved.effects[cc] = { Saturation = cc.Saturation, Contrast = cc.Contrast }
			cc.Saturation = 0.08
			cc.Contrast = 0.08
		end
		if not Lighting:FindFirstChildOfClass("Atmosphere") then
			table.insert(saved.made, make("Atmosphere", { Name = "PlazaAtmosphere", Density = 0.28, Offset = 0.2, Color = rgb(255, 222, 190), Decay = rgb(140, 110, 120), Glare = 0.3, Haze = 1.2 }, Lighting))
		end
		if not Lighting:FindFirstChildOfClass("Sky") then
			table.insert(saved.made, make("Sky", { Name = "PlazaSky", SunAngularSize = 14, MoonAngularSize = 8 }, Lighting))
		end
		S.savedLight = saved
	elseif not on and S.savedLight then
		local saved = S.savedLight
		S.savedLight = nil
		for k, v in pairs(saved.props) do
			Lighting[k] = v
		end
		for inst, props in pairs(saved.effects) do
			for k, v in pairs(props) do
				inst[k] = v
			end
		end
		for _, inst in ipairs(saved.made) do
			inst:Destroy()
		end
	end
end

---------------------------------------------------------------------------
-- Fades and the front door
---------------------------------------------------------------------------

local function fade(to, seconds)
	local f = S.fader
	if not f then
		return
	end
	f.Visible = true
	local tw = TweenService:Create(f, TweenInfo.new(seconds, Enum.EasingStyle.Quad), { BackgroundTransparency = to })
	tw:Play()
	tw.Completed:Wait()
	if to >= 1 then
		f.Visible = false
	end
end

-- The front door swings open on its hinge (local only), then closes behind you.
local function swingDoor(open, seconds)
	local room = workspace:FindFirstChild("MenuRoom")
	local st = room and room:FindFirstChild("Stations")
	local door = st and st:FindFirstChild("PlazaDoor")
	local main = door and door:FindFirstChild("Door")
	if not main then
		return
	end
	S.doorParts = S.doorParts or {}
	if not S.doorHinge then
		S.doorHinge = main.CFrame * CFrame.new(-main.Size.X / 2, 0, 0) -- (the knob is on the other side)
		for _, p in ipairs(door:GetChildren()) do
			if p:IsA("BasePart") and (p.Name == "Door" or p.Name == "DoorPanel" or p.Name == "DoorKnob" or p.Name == "DoorKnobPlate") then
				S.doorParts[p] = S.doorHinge:ToObjectSpace(p.CFrame)
			end
		end
	end
	local hinge = S.doorHinge
	local angle = open and math.rad(-100) or 0
	local start = time()
	local from = S.doorAngle or 0
	while true do
		local a = math.clamp((time() - start) / seconds, 0, 1)
		local e = a * a * (3 - 2 * a)
		local now = from + (angle - from) * e
		for p, rel in pairs(S.doorParts) do
			p.CFrame = hinge * CFrame.Angles(0, now, 0) * rel
		end
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	S.doorAngle = angle
end

local function controls(on)
	pcall(function()
		local PlayerModule = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		local c = PlayerModule:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end)
end

---------------------------------------------------------------------------
-- Booths: the three cards on the stands, the sign
---------------------------------------------------------------------------

local function drawBooth(m)
	local slot = m:GetAttribute("Slot")
	local cards = m:GetAttribute("Cards") or ""
	local owner = m:GetAttribute("OwnerName")
	local key = cards .. "|" .. tostring(owner) .. "|" .. tostring(m:GetAttribute("Likes")) .. "|" .. tostring(m:GetAttribute("Title"))
	if S.boothDrawn[slot] == key then
		return
	end
	S.boothDrawn[slot] = key
	local ids = {}
	for id in string.gmatch(cards, "[^,]+") do
		table.insert(ids, id)
	end
	for i = 1, Plaza.ShowcaseSize do
		local stand = m:FindFirstChild("Stand" .. i)
		if stand then
			local old = stand:FindFirstChild("CardGui")
			if old then
				old:Destroy()
			end
			local id = ids[i]
			if id and CardData.Cards[id] and S.ctx.makeCard then
				local sg = make("SurfaceGui", { Name = "CardGui", Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 45, LightInfluence = 0.2, Brightness = 1.2 }, stand)
				local holder = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, sg)
				local ok = pcall(S.ctx.makeCard, holder, id, UDim2.fromScale(1, 1))
				if not ok then
					text(holder, CardData.Cards[id].name, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextColor3 = rarityColor(CardData.Cards[id].rarity) })
				end
			end
		end
	end
	local sign = m:FindFirstChild("Sign")
	local sg = sign and sign:FindFirstChild("SignGui")
	if sg then
		local ownerLabel = sg:FindFirstChild("Owner")
		local info = sg:FindFirstChild("Info")
		if ownerLabel then
			ownerLabel.Text = owner and (owner .. "'s booth") or "Free booth"
		end
		if info then
			local title = m:GetAttribute("Title")
			local likes = m:GetAttribute("Likes")
			info.Text = owner and (((title and title ~= "") and ("«" .. title .. "»   ") or "") .. "❤ " .. tostring(likes or 0)) or "Waiting for a player"
		end
	end
end

local function watchBooths()
	local root = plazaModel()
	local booths = root and root:FindFirstChild("Booths")
	if not booths then
		return
	end
	for _, m in ipairs(booths:GetChildren()) do
		if m:IsA("Model") and not m:GetAttribute("_watched") then
			m:SetAttribute("_watched", true)
			m.AttributeChanged:Connect(function()
				drawBooth(m)
			end)
			drawBooth(m)
		end
	end
end

---------------------------------------------------------------------------
-- Hall of Pulls and leaderboards (SurfaceGuis drawn here)
---------------------------------------------------------------------------

local function boardGui(part, name)
	local sg = part:FindFirstChild(name)
	if sg then
		sg:Destroy()
	end
	sg = make("SurfaceGui", { Name = name, Face = Enum.NormalId.Front, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 30, LightInfluence = 0 }, part)
	local f = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(26, 20, 36), BorderSizePixel = 0 }, sg)
	make("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, f)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, f)
	return f
end

local function drawHall()
	local root = plazaModel()
	local hall = root and root:FindFirstChild("HallOfPulls")
	local board = hall and hall:FindFirstChild("Board")
	if not board then
		return
	end
	local f = boardGui(board, "HallGui")
	text(f, "✨ HALL OF PULLS ✨", { Font = TITLE_FONT, TextSize = 46, Size = UDim2.new(1, 0, 0, 54), TextColor3 = GOLD, LayoutOrder = 0 })
	if #S.hall == 0 then
		text(f, "No big pulls yet. Open a pack at the altar: Mythic and up land here!", { TextSize = 24, Size = UDim2.new(1, 0, 0, 60), TextColor3 = DIM, LayoutOrder = 1 })
	end
	for i, e in ipairs(S.hall) do
		local card = CardData.Cards[e.card]
		local row = text(f, (e.far and "🌍 " or "") .. tostring(e.name) .. "  pulled  " .. (card and card.name or "?") .. "  (" .. tostring(e.rarity) .. ")", {
			TextSize = 26,
			Size = UDim2.new(1, 0, 0, 34),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = rarityColor(e.rarity),
			LayoutOrder = i,
		})
		row.TextTruncate = Enum.TextTruncate.AtEnd
		row.TextWrapped = false
	end
end

local function drawBoards()
	local root = plazaModel()
	local folder = root and root:FindFirstChild("Boards")
	if not folder then
		return
	end
	for _, def in ipairs(Plaza.Boards) do
		local m = folder:FindFirstChild(def.key)
		local board = m and m:FindFirstChild("Board")
		if board then
			local f = boardGui(board, "BoardGui")
			text(f, def.emoji .. " " .. def.name, { Font = TITLE_FONT, TextSize = 34, Size = UDim2.new(1, 0, 0, 44), TextColor3 = GOLD, LayoutOrder = 0 })
			local rows = S.boards[def.key] or {}
			if #rows == 0 then
				text(f, "Updates every 2 minutes.", { TextSize = 20, TextColor3 = DIM, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 })
			end
			for i, r in ipairs(rows) do
				local medal = ({ "🥇", "🥈", "🥉" })[i] or (i .. ".")
				local row = make("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = i }, f)
				text(row, medal .. "  " .. tostring(r.name), { Size = UDim2.new(0.75, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 22, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = i <= 3 and GOLD:Lerp(TEXT, 0.4) or TEXT })
				text(row, tostring(r.value), { Size = UDim2.new(0.25, 0, 1, 0), Position = UDim2.fromScale(0.75, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 22, Font = TITLE_FONT, TextColor3 = GOLD })
			end
		end
	end
end

---------------------------------------------------------------------------
-- Nameplates and companions (for everyone in the Plaza, drawn on this screen only)
---------------------------------------------------------------------------

local function plateFor(p)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return nil
	end
	local plate = S.plates[p]
	if plate and plate.Parent == head then
		return plate
	end
	if plate then
		plate:Destroy()
	end
	plate = make("BillboardGui", { Name = "PlazaPlate", Size = UDim2.fromOffset(220, 64), StudsOffset = Vector3.new(0, 2.6, 0), AlwaysOnTop = false, LightInfluence = 0, MaxDistance = 90, Adornee = head }, head)
	text(plate, "", { Name = "Title", Size = UDim2.new(1, 0, 0, 18), TextSize = 14, Font = BODY_FONT, TextColor3 = GOLD, TextStrokeTransparency = 0.4 })
	text(plate, p.DisplayName, { Name = "PName", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 18), Font = TITLE_FONT, TextSize = 22, TextStrokeTransparency = 0.2 })
	text(plate, "", { Name = "Info", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 44), TextSize = 13, TextColor3 = DIM, TextStrokeTransparency = 0.5 })
	S.plates[p] = plate
	return plate
end

local function updatePlate(p)
	local plate = plateFor(p)
	if not plate then
		return
	end
	local title = p:GetAttribute("HubTitle")
	plate.Title.Text = (title and title ~= "") and ("«" .. title .. "»") or ""
	local best = p:GetAttribute("BestRarity")
	plate.PName.TextColor3 = (best and best ~= "" and Plaza.Rank[best] and Plaza.Rank[best] >= Plaza.Rank.Mythic) and rarityColor(best):Lerp(TEXT, 0.25) or TEXT
	plate.Info.Text = "Lv " .. tostring(p:GetAttribute("Level") or 1) .. "   ★ " .. tostring(p:GetAttribute("CampaignStars") or 0) .. "   ❤ " .. tostring(p:GetAttribute("BoothLikes") or 0)
end

local function dropPet(p)
	local pet = S.pets[p]
	if pet then
		if pet.model then
			pet.model:Destroy()
		end
		S.pets[p] = nil
	end
end

local function petFor(p, root)
	local id = p:GetAttribute("Companion")
	if type(id) ~= "string" or id == "" or not CardData.Cards[id] then
		dropPet(p)
		return nil
	end
	local pet = S.pets[p]
	if pet and pet.id == id and pet.model and pet.model.Parent then
		return pet
	end
	dropPet(p)
	if not S.ctx.buildModel then
		return nil
	end
	local ok, model = pcall(S.ctx.buildModel, id)
	if not ok or not model then
		return nil
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	-- about knee-to-hip high next to an avatar, whatever size the table model is
	if S.ctx.setScale then
		local okBox, _, size = pcall(model.GetBoundingBox, model)
		if okBox and size and size.Y > 0 then
			pcall(S.ctx.setScale, model, math.clamp(3.2 / size.Y, 0.2, 4))
		end
	end
	model.Name = "Companion_" .. p.UserId
	model.Parent = plazaModel() or workspace
	pet = { model = model, id = id, pos = root.Position + Vector3.new(3, 0, 3), phase = math.random() * 6 }
	S.pets[p] = pet
	return pet
end

local function updatePeople(dt)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local there = p:GetAttribute("InPlaza") == true and root ~= nil
		if there then
			updatePlate(p)
			local pet = petFor(p, root)
			if pet then
				-- trot along behind and to the side, hopping a little while it moves
				local behind = root.CFrame * CFrame.new(2.6, 0, 3.2)
				local target = Vector3.new(behind.X, root.Position.Y - 2.6, behind.Z)
				local before = pet.pos
				pet.pos = pet.pos:Lerp(target, math.clamp(dt * 4, 0, 1))
				local speed = (pet.pos - before).Magnitude / math.max(dt, 1 / 240)
				pet.phase += dt * (speed > 1 and 12 or 2)
				local hop = speed > 1 and math.abs(math.sin(pet.phase)) * 0.6 or math.sin(pet.phase) * 0.08
				local look = Vector3.new(root.Position.X, pet.pos.Y, root.Position.Z)
				if (look - pet.pos).Magnitude < 0.5 then
					look = pet.pos + root.CFrame.LookVector
				end
				local _, size = pet.model:GetBoundingBox()
				pet.model:PivotTo(CFrame.lookAt(pet.pos + Vector3.new(0, size.Y / 2 + hop, 0), look + Vector3.new(0, size.Y / 2 + hop, 0)))
			end
		else
			if S.plates[p] then
				S.plates[p]:Destroy()
				S.plates[p] = nil
			end
			dropPet(p)
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	if S.plates[p] then
		S.plates[p]:Destroy()
		S.plates[p] = nil
	end
	dropPet(p)
end)

---------------------------------------------------------------------------
-- Banners for big pulls (in the Plaza and in the room, never over a match or a pack)
---------------------------------------------------------------------------

local function banner(e)
	local mode = S.ctx.getMode and S.ctx.getMode()
	if mode ~= "menu" and mode ~= "plaza" then
		return
	end
	local card = CardData.Cards[e.card]
	if not card or not S.banners then
		return
	end
	local color = rarityColor(e.rarity)
	local b = make("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = UDim2.fromOffset(560, 70), BackgroundColor3 = PANEL }, S.banners)
	corner(b, 14)
	stroke(b, color, 3)
	make("UIGradient", { Color = ColorSequence.new(color:Lerp(PANEL, 0.55), PANEL), Rotation = 90 }, b)
	text(b, (e.far and "🌍 Somewhere in Deck Wars" or "✨ In this server") .. ": " .. tostring(e.name) .. " pulled", { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), TextColor3 = DIM, TextSize = 15 })
	text(b, card.name .. "  ·  " .. card.rarity .. "!", { Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 30), Font = TITLE_FONT, TextSize = 26, TextColor3 = color })
	Juice.sound(e.rarity == "Secret" and "choir" or "twang", 1, 0.4)
	TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	task.delay(5.5, function()
		if b.Parent then
			TweenService:Create(b, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
			task.wait(0.45)
			b:Destroy()
		end
	end)
	-- a pillar of light over the altar for pulls in this server
	if not e.far and S.inside then
		local root = plazaModel()
		local altar = root and root:FindFirstChild("Altar")
		local pillar = altar and altar:FindFirstChild("LightPillar")
		if pillar then
			pillar.Color = color
			pillar.Transparency = 0.25
			TweenService:Create(pillar, TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		end
	end
end

-- Secret (and Shiny) pulls in the chat, for everyone in every server. Your own pull waits until
-- your pack opening is over, so the chat never spoils it.
local function chatPost(e)
	if not Plaza.chatWorthy(e) then
		return
	end
	local card = CardData.Cards[e.card]
	if not card then
		return
	end
	local color = e.shiny and Color3.fromRGB(255, 236, 140) or (e.rarity == "Secret" and Color3.fromRGB(255, 110, 220)) or rarityColor(e.rarity)
	local line = Plaza.chatLine(e, card.name, string.format("%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5)))
	local ok = pcall(function()
		local TextChatService = game:GetService("TextChatService")
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if not general then
			error("no RBXGeneral")
		end
		general:DisplaySystemMessage(line)
	end)
	if not ok then
		-- the old chat
		pcall(function()
			game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", { Text = string.gsub(line, "<[^>]+>", ""), Color = color })
		end)
	end
	S.lastChat = line -- (for tests)
end

local function whenNotOpening(fn)
	task.spawn(function()
		local ok, PackParty = pcall(function()
			return require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
		end)
		local waited = 0
		while ok and PackParty.isPlaying() and waited < 90 do
			task.wait(0.5)
			waited += 0.5
		end
		fn()
	end)
end

---------------------------------------------------------------------------
-- The HUD, the booth editor and the pack panel
---------------------------------------------------------------------------

local function showHud(on)
	if S.hud then
		S.hud.Visible = on
	end
end

local function closeEditor()
	if S.editor then
		S.editor:Destroy()
		S.editor = nil
	end
end

local function openEditor()
	closeEditor()
	local st = S.state
	local f = make("Frame", { Name = "BoothEditor", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(560, 470), BackgroundColor3 = PANEL }, S.gui)
	S.editor = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	text(f, "🖼 Your booth", { Font = TITLE_FONT, TextSize = 24, Size = UDim2.new(1, -60, 0, 32), Position = UDim2.fromOffset(16, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	button(f, "✕", rgb(110, 60, 70), closeEditor, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 10) })
	if not st or st.loading then
		text(f, "Loading your cards...", { Position = UDim2.fromOffset(16, 60), Size = UDim2.new(1, -32, 0, 20), TextColor3 = DIM })
		PlazaAction:FireServer("State")
		return
	end
	local picked = table.clone(st.picked or {})
	text(f, "Pick up to 3 cards to show off (none = your 3 rarest). Your first creature walks with you. Likes so far: ❤ " .. tostring(st.likes or 0), { Position = UDim2.fromOffset(16, 44), Size = UDim2.new(1, -32, 0, 36), TextColor3 = DIM, TextXAlignment = Enum.TextXAlignment.Left })
	-- your title
	local titles = st.titles or {}
	local titleIndex = table.find(titles, st.title) or #titles
	local titleRow = make("Frame", { Size = UDim2.new(1, -32, 0, 34), Position = UDim2.fromOffset(16, 84), BackgroundTransparency = 1 }, f)
	local titleLabel = text(titleRow, "", { Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(40, 0), Font = TITLE_FONT, TextSize = 17, TextColor3 = GOLD, BackgroundColor3 = TILE, BackgroundTransparency = 0 })
	corner(titleLabel, 8)
	local function showTitle()
		titleLabel.Text = #titles == 0 and "No titles yet: win star chests in the Campaign or pull a Rare+" or ("Title: «" .. tostring(titles[titleIndex]) .. "»")
	end
	showTitle()
	for dir, x in pairs({ [-1] = 0, [1] = 1 }) do
		button(titleRow, dir < 0 and "◀" or "▶", TILE, function()
			if #titles == 0 then
				return
			end
			titleIndex = (titleIndex - 1 + dir) % #titles + 1
			showTitle()
		end, { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(x, x == 1 and -34 or 0, 0, 0) })
	end
	-- your cards, rarest first
	local grid = make("ScrollingFrame", { Size = UDim2.new(1, -32, 1, -190), Position = UDim2.fromOffset(16, 126), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, f)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(80, 112), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local cells = {}
	local function mark()
		for id, cell in pairs(cells) do
			local n = table.find(picked, id)
			cell.Badge.Visible = n ~= nil
			cell.Badge.Text = n and tostring(n) or ""
		end
	end
	for i, id in ipairs(st.owned or {}) do
		if i > 120 then
			break
		end
		local cell = make("TextButton", { Name = id, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, LayoutOrder = i }, grid)
		if S.ctx.makeCard then
			local card = S.ctx.makeCard(cell, id, UDim2.fromScale(1, 1), nil, true)
			if card then
				for _, d in ipairs(card:GetDescendants()) do
					if d:IsA("GuiObject") then
						d.Active = false
					end
				end
			end
		end
		local badge = text(cell, "", { Name = "Badge", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -24, 0, -6), BackgroundColor3 = GOLD, BackgroundTransparency = 0, TextColor3 = INK, Font = TITLE_FONT, TextSize = 18, ZIndex = 10, Visible = false })
		corner(badge, 14)
		cells[id] = cell
		cell.Activated:Connect(function()
			local n = table.find(picked, id)
			if n then
				table.remove(picked, n)
			elseif #picked < Plaza.ShowcaseSize then
				table.insert(picked, id)
			else
				toast("A booth holds 3 cards: tap one to take it off first.")
			end
			Juice.sound("pop", 1.1, 0.3)
			mark()
		end)
	end
	if #(st.owned or {}) == 0 then
		text(grid, "No cards yet: open a pack!", { TextColor3 = DIM })
	end
	mark()
	button(f, "✓ Save booth", GOOD, function()
		PlazaAction:FireServer("SetShowcase", { cards = picked })
		if #titles > 0 and titles[titleIndex] ~= st.title then
			task.delay(0.3, function()
				PlazaAction:FireServer("SetTitle", { title = titles[titleIndex] })
			end)
		end
		closeEditor()
		toast("Booth saved!")
	end, { Size = UDim2.new(0.5, -20, 0, 44), Position = UDim2.new(0.25, 10, 1, -56) })
end

local function closePacks()
	if S.packPanel then
		S.packPanel:Destroy()
		S.packPanel = nil
	end
end

local function openPacks()
	if S.packPanel then
		return
	end
	local PackParty = require(ReplicatedStorage:WaitForChild("PackBrawl"):WaitForChild("PackParty"))
	if PackParty.isPlaying() then
		return
	end
	closeEditor()
	local f = make("Frame", { Name = "AltarPacks", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 10), Size = UDim2.fromOffset(400, 560), BackgroundColor3 = PANEL }, S.gui)
	S.packPanel = f
	corner(f, 14)
	stroke(f, GOLD, 2)
	text(f, "✨ Pull Altar", { Font = TITLE_FONT, TextSize = 24, Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(14, 10), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	button(f, "✕", rgb(110, 60, 70), closePacks, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -46, 0, 8) })
	local area = make("Frame", { Name = "PackArea", Size = UDim2.new(1, -24, 1, -62), Position = UDim2.fromOffset(12, 52), BackgroundTransparency = 1 }, f)
	PackParty.mount(area, {
		noDive = true, -- (the Dive starts from the room's pack corner)
		isActive = function()
			return S.inside and area.Parent ~= nil
		end,
		onStart = function()
			controls(false)
			S.gui.Enabled = false
			if S.ctx.gui then
				S.ctx.gui.Enabled = false
			end
			if S.ctx.topGui then
				S.ctx.topGui.Enabled = false
			end
		end,
		onEnd = function()
			S.gui.Enabled = true
			if S.ctx.gui then
				S.ctx.gui.Enabled = true
			end
			if S.ctx.topGui then
				S.ctx.topGui.Enabled = true
			end
			if S.inside then
				controls(true)
				camera.CameraType = Enum.CameraType.Custom
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					camera.CameraSubject = hum
				end
			end
		end,
	})
end

local function buildGui()
	local pg = player:WaitForChild("PlayerGui")
	S.gui = make("ScreenGui", { Name = "PlazaUI", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 7, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = true }, pg)
	S.banners = make("ScreenGui", { Name = "PlazaBanners", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30 }, pg)
	S.fader = make("Frame", { Name = "Fader", Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(0, 0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 50 }, make("ScreenGui", { Name = "PlazaFade", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60 }, pg))
	local hud = make("Frame", { Name = "Hud", Size = UDim2.new(0, 420, 0, 52), Position = UDim2.fromOffset(16, 64), BackgroundTransparency = 1, Visible = false }, S.gui)
	S.hud = hud
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, hud)
	button(hud, "🏠 Home", rgb(150, 90, 60), function()
		PlazaClient.leave(false)
	end, { Size = UDim2.fromOffset(120, 46), LayoutOrder = 1 })
	button(hud, "🖼 My booth", rgb(70, 60, 120), function()
		if S.editor then
			closeEditor()
		else
			PlazaAction:FireServer("State")
			openEditor()
		end
	end, { Size = UDim2.fromOffset(140, 46), LayoutOrder = 2 })
	local hint = text(S.gui, "WASD to walk · E to use · walk up to a booth's ❤ to like it", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(520, 22), TextColor3 = rgb(255, 245, 225), TextStrokeTransparency = 0.4, Visible = false })
	S.hint = hint
end

---------------------------------------------------------------------------
-- Walking in and out
---------------------------------------------------------------------------

function PlazaClient.isInside()
	return S.inside
end

function PlazaClient.enter()
	local ctx = S.ctx
	if S.inside or S.busy or not ctx or ctx.getMode() ~= "menu" then
		return
	end
	if not plazaModel() then
		toast("The Plaza is still being built. Try again in a moment.")
		return
	end
	S.busy = true
	ctx.closeStation()
	ctx.menuVisible(false)
	-- the door swings open and the camera walks you through it
	task.spawn(swingDoor, true, 0.7)
	ctx.glideCamera(Vector3.new(-14, 6.2, 20), Vector3.new(-14, 5.8, 30), 0.9, 60)
	task.wait(0.55)
	fade(0, 0.4)
	ctx.setMode("plaza")
	S.inside = true
	PlazaAction:FireServer("Enter")
	-- wait for the server to walk the character over (or give up after a few seconds)
	local t0 = time()
	while time() - t0 < 4 do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - Plaza.Origin).Magnitude < 200 then
			break
		end
		task.wait(0.05)
	end
	swapLight(true)
	ctx.hideCharacter(false)
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
	camera.FieldOfView = 70
	controls(true)
	watchBooths()
	drawHall()
	drawBoards()
	showHud(true)
	S.hint.Visible = true
	task.spawn(swingDoor, false, 0.1)
	fade(1, 0.6)
	S.busy = false
end

-- Back to the room. instant = no fade (a match is starting). thenStation = a station to open after.
function PlazaClient.leave(instant, thenStation)
	local ctx = S.ctx
	if not S.inside or (S.busy and not instant) then
		return
	end
	S.busy = true
	closeEditor()
	closePacks()
	showHud(false)
	S.hint.Visible = false
	if not instant then
		fade(0, 0.4)
	end
	PlazaAction:FireServer("Leave")
	controls(false)
	swapLight(false)
	S.inside = false
	for p in pairs(S.pets) do
		dropPet(p)
	end
	for p, plate in pairs(S.plates) do
		plate:Destroy()
		S.plates[p] = nil
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if not instant then
		ctx.setMode("menu")
		ctx.menuVisible(true)
		ctx.moveCamera("PlazaDoor", true)
		if thenStation then
			ctx.selectStation(thenStation)
		else
			ctx.goBack()
		end
		task.wait(0.2)
		fade(1, 0.5)
	end
	S.busy = false
end

---------------------------------------------------------------------------
-- The front door's station panel
---------------------------------------------------------------------------

function PlazaClient.doorPanel(body)
	local list = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	text(list, "Step outside into the Plaza: everyone in this server walks around as their avatar.", { Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 })
	local lines = {
		"🖼  Your booth shows off your 3 best cards. Like other booths once a day ❤",
		"✨  Open packs at the Pull Altar. Mythic and up gets a banner for the whole server.",
		"🏆  Hall of Pulls and leaderboards: Campaign stars, levels and likes.",
		"🐾  Your favourite creature walks with you.",
	}
	for i, l in ipairs(lines) do
		text(list, l, { Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = DIM, LayoutOrder = 1 + i })
	end
	local count = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InPlaza") == true then
			count += 1
		end
	end
	text(list, count == 1 and "1 player is out there now." or (count .. " players are out there now."), { Size = UDim2.new(1, 0, 0, 22), Font = TITLE_FONT, TextSize = 17, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 10 })
	local go = button(list, "🏙  Walk out", GOOD, function()
		PlazaClient.enter()
	end, { Name = "WalkOut", Size = UDim2.new(1, 0, 0, 52), TextSize = 24, LayoutOrder = 11 })
	Juice.shine(go, 3, UDim.new(0, 10))
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function PlazaClient.init(ctx)
	S.ctx = ctx
	buildGui()
	PlazaEvent.OnClientEvent:Connect(function(e)
		if type(e) ~= "table" then
			return
		end
		if e.kind == "entered" then
			S.hall = type(e.hall) == "table" and e.hall or S.hall
			S.boards = type(e.boards) == "table" and e.boards or S.boards
			drawHall()
			drawBoards()
		elseif e.kind == "hall" then
			S.hall = type(e.hall) == "table" and e.hall or {}
			drawHall()
		elseif e.kind == "boards" then
			S.boards = type(e.boards) == "table" and e.boards or {}
			drawBoards()
		elseif e.kind == "bigPull" then
			if e.userId == player.UserId and not e.far then
				whenNotOpening(function()
					chatPost(e)
					banner(e)
				end)
			else
				chatPost(e)
				banner(e)
			end
		elseif e.kind == "state" then
			S.state = e
			if S.editor then
				openEditor()
			end
		elseif e.kind == "liked" then
			toast("❤ You liked " .. tostring(e.name) .. "'s booth!")
			Juice.sound("pop", 1.3, 0.5)
			local root = plazaModel()
			local m = root and root.Booths:FindFirstChild("Booth" .. tostring(e.slot))
			local heart = m and m:FindFirstChild("Heart")
			if heart then
				local size = heart.Size
				heart.Size = size * 1.6
				TweenService:Create(heart, TweenInfo.new(0.6, Enum.EasingStyle.Elastic), { Size = size }):Play()
			end
		elseif e.kind == "likedBy" then
			toast("❤ " .. tostring(e.name) .. " liked your booth! (" .. tostring(e.likes or "") .. ")")
		elseif e.kind == "toast" then
			toast(tostring(e.text))
		end
	end)
	-- The prompts out here: the altar, the gates and the Duel kiosk (likes are the server's).
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or not S.inside or S.busy then
			return
		end
		if prompt.Name == "OpenPacks" then
			openPacks()
		elseif prompt.Name == "GoHome" then
			PlazaClient.leave(false)
		elseif prompt.Name == "Campaign" then
			PlazaClient.leave(false, "Campaign")
		elseif prompt.Name == "Duel" then
			PlazaClient.leave(false, "DuelTable")
		end
	end)
	-- Escape closes the booth editor and the altar panel.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not S.inside then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			closeEditor()
			closePacks()
		end
	end)
	-- Every frame out here: the floating pack, the nameplates and the companions.
	local spin = 0
	RunService.RenderStepped:Connect(function(dt)
		if not S.inside then
			return
		end
		spin += dt
		local root = plazaModel()
		local altar = root and root:FindFirstChild("Altar")
		local pack = altar and altar:FindFirstChild("FloatingPack")
		if pack then
			S.packBase = S.packBase or pack.CFrame
			pack.CFrame = S.packBase * CFrame.new(0, math.sin(spin * 1.3) * 0.6, 0) * CFrame.Angles(0, spin * 0.7, math.sin(spin * 0.9) * 0.08)
		end
		updatePeople(dt)
	end)
	-- the booths change while you're inside too (new picks, likes)
	task.spawn(function()
		local root = workspace:WaitForChild("Plaza", 30)
		if root then
			watchBooths()
		end
	end)
end

PlazaClient.S = S
return PlazaClient

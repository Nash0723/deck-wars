-- Two new stations in the room, made from props that are already there:
--   Stations.PlazaDoor  the front door: walk out into the Plaza (PlazaClient)
--   Stations.Campaign   the painting over the Duel Table: the Campaign map (CampaignUI)
-- The parts keep their names, sizes and places; they only move into a station Model so the room's
-- hover glow, clicks and nav buttons treat them like the other stations. Each gets a "Sign".
-- If a station Model with that name already exists (built by hand in Studio), it is left alone.

local room = workspace:WaitForChild("MenuRoom")
local stations = room:WaitForChild("Stations")

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function gather(names)
	local found = {}
	for _, d in ipairs(room:GetDescendants()) do
		if d:IsA("BasePart") and names[d.Name] and not d:IsDescendantOf(stations) then
			table.insert(found, d)
		end
	end
	return found
end

local function sign(model, text, position)
	local anchor = make("Part", {
		Name = "SignAnchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(position),
	}, model)
	local gui = make("BillboardGui", { Name = "Sign", Size = UDim2.new(6.4, 0, 1.45, 0), AlwaysOnTop = false, LightInfluence = 0, MaxDistance = 80 }, anchor)
	make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = text, TextScaled = true, TextColor3 = Color3.new(1, 1, 1) }, gui)
end

local function station(name, partNames, signText, signAt)
	if stations:FindFirstChild(name) then
		return stations[name]
	end
	local parts = gather(partNames)
	if #parts == 0 then
		warn("[HubRoom] none of the parts for the " .. name .. " station are in the room")
		return nil
	end
	local model = make("Model", { Name = name }, nil)
	for _, p in ipairs(parts) do
		p.Parent = model
	end
	sign(model, signText, signAt)
	model.Parent = stations
	return model
end

station("PlazaDoor", {
	Door = true,
	DoorPanel = true,
	DoorKnob = true,
	DoorKnobPlate = true,
	DoorFrameL = true,
	DoorFrameR = true,
	DoorFrameTop = true,
}, "PLAZA", Vector3.new(-14, 13.2, 23.2))

station("Campaign", {
	PaintingFrame = true,
	PaintingSky = true,
	PaintingHill = true,
	PaintingSun = true,
	PaintingCastle = true,
	PaintingTower = true,
}, "CAMPAIGN", Vector3.new(0, 14, -22.2))

-- A soft gold glow round the painting, so it reads as something to click.
do
	local campaign = stations:FindFirstChild("Campaign")
	local frame = campaign and campaign:FindFirstChild("PaintingFrame")
	if frame and not campaign:FindFirstChild("MapGlow") then
		local glow = make("Part", {
			Name = "MapGlow",
			Anchored = true,
			CanCollide = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(255, 214, 120),
			Transparency = 0.55,
			Size = Vector3.new(frame.Size.X + 0.5, frame.Size.Y + 0.5, 0.06),
			-- just behind the frame and just in front of the chimney, so only a rim shows
			CFrame = frame.CFrame * CFrame.new(0, 0, -0.04),
		}, campaign)
		make("PointLight", { Color = Color3.fromRGB(255, 210, 140), Range = 8, Brightness = 0.8, Shadows = false }, glow)
	end
end

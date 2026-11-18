--!strict
-- CozyLife: small touches for the cozy corner in the room (workspace.MenuRoom.Cozy).
-- The sleeping cat by the fire lets a sleepy "z" float up now and then, and the reading
-- lamp's light breathes a little, like a real bulb. Everything here runs on this client only,
-- and it pauses while the room is hidden (a match world or the Park is up).

local TweenService = game:GetService("TweenService")

local CozyLife = {}

local started = false

local function snooze(at: Attachment)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Zzz"
	bb.Size = UDim2.fromOffset(40, 40)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.MaxDistance = 70
	bb.StudsOffsetWorldSpace = Vector3.new(0.3, 0, 0)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.FredokaOne
	t.Text = "z"
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 244, 220)
	t.TextStrokeColor3 = Color3.fromRGB(70, 44, 30)
	t.TextStrokeTransparency = 0.4
	t.TextTransparency = 1
	t.Rotation = -12
	t.Parent = bb
	bb.Adornee = at
	bb.Parent = at
	local up = TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(bb, up, {
		StudsOffsetWorldSpace = Vector3.new(1.1 + math.random() * 0.5, 2.2, 0),
		Size = UDim2.fromOffset(64, 64),
	}):Play()
	TweenService:Create(t, TweenInfo.new(0.5), { TextTransparency = 0.05, TextStrokeTransparency = 0.4 }):Play()
	TweenService:Create(t, up, { Rotation = 14 }):Play()
	task.delay(1.6, function()
		TweenService:Create(t, TweenInfo.new(1.0), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(2.7, function()
		bb:Destroy()
	end)
end

-- awake(): true while the room is on screen (the caller passes a function so this can check it).
function CozyLife.start(room: Instance, awake: () -> boolean)
	if started then
		return
	end
	started = true
	task.spawn(function()
		local cozy = room:WaitForChild("Cozy", 20)
		if not cozy then
			return
		end
		local cat = cozy:FindFirstChild("CozyCatBed")
		local at = cat and cat:FindFirstChild("Snooze")
		local lamp = cozy:FindFirstChild("CozyLamp")
		local bulb = lamp and lamp:FindFirstChild("Bulb")
		local light = bulb and bulb:FindFirstChildWhichIsA("PointLight")
		local base = light and light.Brightness or 0
		local n = 0
		while cozy.Parent do
			task.wait(0.9)
			n += 1
			if awake() then
				-- z z z: three in a row, then a rest
				if at and at:IsA("Attachment") and n % 6 < 3 then
					snooze(at)
				end
				if light then
					local b = base * (0.92 + math.random() * 0.12)
					TweenService:Create(light, TweenInfo.new(0.9, Enum.EasingStyle.Sine), { Brightness = b }):Play()
				end
			end
		end
	end)
end

return CozyLife

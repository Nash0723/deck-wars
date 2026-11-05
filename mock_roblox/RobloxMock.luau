-- A small fake Roblox for running Deck Wars scripts headlessly.
-- Checks every property name, read-only flag, value type and enum item against Roblox's
-- reflection database, so typos and wrong types show up as errors.

local DB = require("ReflectionDB")
local M = { errors = 0, warnings = 0, log = {} }

local function report(kind, msg)
	if kind == "error" then
		M.errors += 1
	else
		M.warnings += 1
	end
	table.insert(M.log, kind .. ": " .. msg)
	print(string.upper(kind) .. ": " .. msg)
end
M.report = report

---------------------------------------------------------------------------
-- Scheduler (virtual time)
---------------------------------------------------------------------------
local now = 1000
local queue = {}
local seq = 0
function M.now()
	return now
end

local function resume(th, ...)
	local ok, err = coroutine.resume(th, ...)
	if not ok then
		report("error", "script error: " .. tostring(err) .. "\n" .. debug.traceback(th))
	end
end
M.resume = resume

local function schedule(t, th, args)
	seq += 1
	table.insert(queue, { time = t, seq = seq, thread = th, args = args or table.pack() })
end

local task = {}
function task.spawn(f, ...)
	local th = type(f) == "thread" and f or coroutine.create(f)
	resume(th, ...)
	return th
end
function task.defer(f, ...)
	local th = type(f) == "thread" and f or coroutine.create(f)
	schedule(now, th, table.pack(...))
	return th
end
function task.delay(t, f, ...)
	local th = type(f) == "thread" and f or coroutine.create(f)
	schedule(now + (t or 0), th, table.pack(...))
	return th
end
function task.wait(t)
	local th = coroutine.running()
	assert(coroutine.isyieldable(), "task.wait called outside a yieldable thread")
	local start = now
	schedule(now + math.max(t or 0.03, 0.001), th)
	coroutine.yield()
	return now - start
end
function task.cancel() end
M.task = task

-- Run everything due up to now + dt, firing frame signals every 1/30 s.
function M.advance(dt)
	local target = now + dt
	while true do
		table.sort(queue, function(a, b)
			if a.time == b.time then
				return a.seq < b.seq
			end
			return a.time < b.time
		end)
		local nextFrame = math.floor(now * 30 + 1e-6) / 30 + 1 / 30
		local item = queue[1]
		if item and item.time <= target and item.time <= nextFrame then
			table.remove(queue, 1)
			now = math.max(now, item.time)
			if coroutine.status(item.thread) == "suspended" then
				resume(item.thread, table.unpack(item.args, 1, item.args.n))
			end
		elseif nextFrame <= target then
			now = nextFrame
			if M.onFrame then
				M.onFrame()
			end
		else
			now = target
			break
		end
	end
end

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
local function newSignal(name)
	return setmetatable({ conns = {}, waiting = {}, name = name }, Signal)
end
function Signal:Connect(fn)
	assert(type(fn) == "function", "Connect needs a function for " .. tostring(self.name))
	local c = { fn = fn, Connected = true }
	function c.Disconnect(conn)
		(conn or c).Connected = false
	end
	table.insert(self.conns, c)
	return c
end
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end
function Signal:Fire(...)
	for _, c in ipairs(table.clone(self.conns)) do
		if c.Connected then
			task.spawn(c.fn, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, th in ipairs(w) do
		resume(th, ...)
	end
end
M.newSignal = newSignal

---------------------------------------------------------------------------
-- Datatypes
---------------------------------------------------------------------------
local function typed(t, mt)
	return setmetatable(t, mt)
end

local Vector3 = {}
local V3MT = { __type = "Vector3" }
function Vector3.new(x, y, z)
	return typed({ X = x or 0, Y = y or 0, Z = z or 0 }, V3MT)
end
V3MT.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	elseif k == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	elseif k == "Cross" then
		return function(a, b)
			return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			return a + (b - a) * t
		end
	end
	error(tostring(k) .. " is not a valid member of Vector3", 2)
end
V3MT.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3MT.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3MT.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b)
	return Vector3.new(a.X / b, a.Y / b, a.Z / b)
end
V3MT.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
V3MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3MT.__tostring = function(v)
	return string.format("%g, %g, %g", v.X, v.Y, v.Z)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.yAxis = Vector3.new(0, 1, 0)

local Vector2 = {}
local V2MT = { __type = "Vector2" }
function Vector2.new(x, y)
	assert(x == nil or type(x) == "number", "Vector2.new needs numbers")
	assert(y == nil or type(y) == "number", "Vector2.new needs numbers")
	return typed({ X = x or 0, Y = y or 0 }, V2MT)
end
V2MT.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return Vector2.new(v.X / m, v.Y / m)
	elseif k == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			return Vector2.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
		end
	end
	error(tostring(k) .. " is not a valid member of Vector2", 2)
end
local function v2check(a, b, op)
	assert(typeof(a) == "Vector2" and (typeof(b) == "Vector2" or ((op == "*" or op == "/") and type(b) == "number")), "bad Vector2 " .. op)
end
V2MT.__add = function(a, b)
	v2check(a, b, "+")
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2MT.__sub = function(a, b)
	v2check(a, b, "-")
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2MT.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	v2check(a, b, "*")
	if type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
V2MT.__div = function(a, b)
	v2check(a, b, "/")
	if type(b) == "number" then
		return Vector2.new(a.X / b, a.Y / b)
	end
	return Vector2.new(a.X / b.X, a.Y / b.Y)
end
V2MT.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end
V2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
Vector2.zero = Vector2.new(0, 0)

local CFrame = {}
local CFMT = { __type = "CFrame" }
local function cfRaw(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return typed({ _p = Vector3.new(x, y, z), _r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } }, CFMT)
end
function CFrame.new(a, b, c, ...)
	if a == nil then
		return cfRaw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if typeof(a) == "Vector3" then
		if typeof(b) == "Vector3" then
			return CFrame.lookAt(a, b)
		end
		return cfRaw(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local rest = { ... }
	if #rest == 9 then
		return cfRaw(a, b, c, table.unpack(rest))
	end
	assert(type(a) == "number" and type(b) == "number" and type(c) == "number", "CFrame.new bad arguments")
	return cfRaw(a, b, c, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end
function CFrame.fromMatrix(pos, rx, ry, rz)
	rz = rz or rx:Cross(ry).Unit
	return cfRaw(pos.X, pos.Y, pos.Z, rx.X, ry.X, rz.X, rx.Y, ry.Y, rz.Y, rx.Z, ry.Z, rz.Z)
end
function CFrame.lookAt(pos, target, up)
	assert(typeof(pos) == "Vector3" and typeof(target) == "Vector3", "CFrame.lookAt needs Vector3s")
	up = up or Vector3.new(0, 1, 0)
	local fwd = (target - pos).Unit
	local right = fwd:Cross(up).Unit
	local up2 = right:Cross(fwd)
	return CFrame.fromMatrix(pos, right, up2, -fwd)
end
local function rotMul(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	local r = rotMul(rotMul(X, Y), Z)
	return cfRaw(0, 0, 0, table.unpack(r))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromAxisAngle(axis, angle)
	assert(typeof(axis) == "Vector3", "CFrame.fromAxisAngle needs a Vector3 axis")
	assert(type(angle) == "number", "CFrame.fromAxisAngle needs a number angle")
	local m = axis.Magnitude
	assert(m > 1e-9, "CFrame.fromAxisAngle got a zero axis")
	local x, y, z = axis.X / m, axis.Y / m, axis.Z / m
	local c, s = math.cos(angle), math.sin(angle)
	local t = 1 - c
	return cfRaw(0, 0, 0,
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c)
end
CFrame.identity = CFrame.new()
local function cfApply(cf, v)
	local r = cf._r
	return Vector3.new(
		r[1] * v.X + r[2] * v.Y + r[3] * v.Z + cf._p.X,
		r[4] * v.X + r[5] * v.Y + r[6] * v.Z + cf._p.Y,
		r[7] * v.X + r[8] * v.Y + r[9] * v.Z + cf._p.Z
	)
end
CFMT.__mul = function(a, b)
	if typeof(b) == "Vector3" then
		return cfApply(a, b)
	end
	assert(typeof(b) == "CFrame", "CFrame * expects CFrame or Vector3")
	local r = rotMul(a._r, b._r)
	local p = cfApply(a, b._p)
	return cfRaw(p.X, p.Y, p.Z, table.unpack(r))
end
CFMT.__add = function(a, v)
	assert(typeof(v) == "Vector3", "CFrame + expects Vector3")
	local r = a._r
	return cfRaw(a._p.X + v.X, a._p.Y + v.Y, a._p.Z + v.Z, table.unpack(r))
end
CFMT.__sub = function(a, v)
	return CFMT.__add(a, -v)
end
CFMT.__index = function(cf, k)
	local r = rawget(cf, "_r")
	if k == "Position" or k == "p" then
		return rawget(cf, "_p")
	elseif k == "X" then
		return rawget(cf, "_p").X
	elseif k == "Y" then
		return rawget(cf, "_p").Y
	elseif k == "Z" then
		return rawget(cf, "_p").Z
	elseif k == "LookVector" then
		return Vector3.new(-r[3], -r[6], -r[9])
	elseif k == "RightVector" then
		return Vector3.new(r[1], r[4], r[7])
	elseif k == "UpVector" then
		return Vector3.new(r[2], r[5], r[8])
	elseif k == "Rotation" then
		return cfRaw(0, 0, 0, table.unpack(r))
	elseif k == "Inverse" then
		return function(c)
			local q = c._r
			local t = { q[1], q[4], q[7], q[2], q[5], q[8], q[3], q[6], q[9] }
			local inv = cfRaw(0, 0, 0, table.unpack(t))
			local p = cfApply(inv, -c._p)
			return cfRaw(p.X, p.Y, p.Z, table.unpack(t))
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			local p = a._p + (b._p - a._p) * t
			local rr = t < 0.5 and a._r or b._r
			return cfRaw(p.X, p.Y, p.Z, table.unpack(rr))
		end
	elseif k == "PointToWorldSpace" then
		return function(c, v)
			return cfApply(c, v)
		end
	elseif k == "ToObjectSpace" then
		return function(c, other)
			return c:Inverse() * other
		end
	elseif k == "ToWorldSpace" then
		return function(c, other)
			return c * other
		end
	end
	error(tostring(k) .. " is not a valid member of CFrame", 2)
end

local Color3 = {}
local C3MT = { __type = "Color3" }
C3MT.__index = function(c, k)
	if k == "Lerp" then
		return function(a, b, t)
			assert(typeof(b) == "Color3", "Color3:Lerp needs a Color3")
			return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	elseif k == "ToHSV" then
		return function()
			return 0, 0, 0
		end
	end
	error(tostring(k) .. " is not a valid member of Color3", 2)
end
C3MT.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function Color3.new(r, g, b)
	return typed({ R = r or 0, G = g or 0, B = b or 0 }, C3MT)
end
function Color3.fromRGB(r, g, b)
	assert(type(r) == "number" and type(g) == "number" and type(b) == "number", "Color3.fromRGB needs numbers")
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.fromHSV(h, s, v)
	assert(type(h) == "number" and type(s) == "number" and type(v) == "number", "Color3.fromHSV needs numbers")
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return Color3.new(r, g, b)
end

local UDim = {}
local UDMT = { __type = "UDim" }
UDMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of UDim", 2)
end
function UDim.new(s, o)
	return typed({ Scale = s or 0, Offset = o or 0 }, UDMT)
end
local UDim2 = {}
local UD2MT = { __type = "UDim2" }
UD2MT.__index = function(u, k)
	if k == "Width" then
		return rawget(u, "X")
	elseif k == "Height" then
		return rawget(u, "Y")
	end
	error(tostring(k) .. " is not a valid member of UDim2", 2)
end
UD2MT.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
function UDim2.new(xs, xo, ys, yo)
	if typeof(xs) == "UDim" then
		return typed({ X = xs, Y = xo }, UD2MT)
	end
	for _, v in ipairs({ xs or 0, xo or 0, ys or 0, yo or 0 }) do
		assert(type(v) == "number", "UDim2.new needs numbers")
	end
	return typed({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UD2MT)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end

local function simple(typeName, fields)
	local mt = { __type = typeName }
	mt.__index = function(_, k)
		error(tostring(k) .. " is not a valid member of " .. typeName, 2)
	end
	return function(...)
		local args = { ... }
		local t = {}
		for i, f in ipairs(fields) do
			t[f] = args[i]
		end
		t._args = args
		return setmetatable(t, mt)
	end
end
local NumberRange = { new = simple("NumberRange", { "Min", "Max" }) }
local NumberSequenceKeypoint = { new = simple("NumberSequenceKeypoint", { "Time", "Value", "Envelope" }) }
local NumberSequence = { new = simple("NumberSequence", { "Keypoints" }) }
local ColorSequenceKeypoint = { new = simple("ColorSequenceKeypoint", { "Time", "Value" }) }
local ColorSequence = { new = simple("ColorSequence", { "Keypoints" }) }
local TweenInfo = {
	new = function(time, style, dir, ...)
		local t = simple("TweenInfo", { "Time", "EasingStyle", "EasingDirection" })(time or 1, style, dir)
		if style ~= nil then
			assert(typeof(style) == "EnumItem" and style.EnumType == "EasingStyle", "TweenInfo style must be an EasingStyle")
		end
		if dir ~= nil then
			assert(typeof(dir) == "EnumItem" and dir.EnumType == "EasingDirection", "TweenInfo direction must be an EasingDirection")
		end
		return t
	end,
}
local RaycastParamsMT = { __type = "RaycastParams" }
local RaycastParams = {
	new = function()
		return setmetatable({ FilterType = nil, FilterDescendantsInstances = {} }, RaycastParamsMT)
	end,
}
RaycastParamsMT.__newindex = function(t, k, v)
	if k ~= "FilterType" and k ~= "FilterDescendantsInstances" and k ~= "IgnoreWater" and k ~= "CollisionGroup" then
		error(k .. " is not a valid member of RaycastParams", 2)
	end
	rawset(t, k, v)
end

---------------------------------------------------------------------------
-- Enums
---------------------------------------------------------------------------
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__tostring = function(e)
	return "Enum." .. e.EnumType .. "." .. e.Name
end
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, enumName)
		local items = DB.Enums[enumName]
		if not items then
			error(tostring(enumName) .. " is not a valid member of Enums", 2)
		end
		if not enumCache[enumName] then
			local list = {}
			enumCache[enumName] = setmetatable({}, {
				__index = function(_, itemName)
					if itemName == "GetEnumItems" then
						return function()
							return list
						end
					end
					local v = items[itemName]
					if v == nil then
						error(tostring(itemName) .. " is not a valid EnumItem of Enum." .. enumName, 2)
					end
					local item = rawget(list, itemName)
					if not item then
						item = setmetatable({ Name = itemName, Value = v, EnumType = enumName }, EnumItemMT)
						rawset(list, itemName, item)
					end
					return item
				end,
			})
		end
		return enumCache[enumName]
	end,
})

---------------------------------------------------------------------------
-- typeof
---------------------------------------------------------------------------
local InstanceMT = {}
local function typeof(v)
	local mt = getmetatable(v)
	if type(v) == "table" and mt then
		if mt == InstanceMT then
			return "Instance"
		end
		if type(mt) == "table" and rawget(mt, "__type") then
			return rawget(mt, "__type")
		end
	end
	return type(v)
end
M.typeof = typeof

---------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------
local data = setmetatable({}, { __mode = "k" }) -- proxy -> internal record

local function classInfo(className)
	return DB.Classes[className]
end
local function isA(className, target)
	local c = className
	while c do
		if c == target then
			return true
		end
		local info = classInfo(c)
		c = info and info.super
	end
	return false
end
local function findProp(className, prop)
	local c = className
	while c do
		local info = classInfo(c)
		if not info then
			return nil
		end
		local p = info.props[prop]
		if p then
			return p
		end
		c = info.super
	end
	return nil
end

local EVENTS = {
	Activated = true, MouseEnter = true, MouseLeave = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true, Completed = true,
	OnServerEvent = true, OnClientEvent = true, CharacterAdded = true, PlayerRemoving = true, PlayerAdded = true,
	InputBegan = true, InputEnded = true, RenderStepped = true, Heartbeat = true, Changed = true, ChildAdded = true,
	Touched = true, Died = true, FocusLost = true, Focused = true,
	AttributeChanged = true, InputChanged = true, ChildRemoved = true, DescendantAdded = true, MouseButton2Click = true,
	Triggered = true, PromptTriggered = true, Event = true,
}

local function defaultFor(t)
	if t == "Bool" then
		return false
	elseif t == "Float32" or t == "Float64" or t == "Int32" or t == "Int64" then
		return 0
	elseif t == "String" or t == "Content" or t == "ContentId" then
		return ""
	elseif t == "Vector3" then
		return Vector3.new()
	elseif t == "Vector2" then
		return Vector2.new()
	elseif t == "CFrame" then
		return CFrame.new()
	elseif t == "Color3" then
		return Color3.new()
	elseif t == "UDim2" then
		return UDim2.new()
	elseif t == "UDim" then
		return UDim.new()
	end
	return nil
end

local function checkType(className, prop, t, value)
	local ok = true
	if value == nil then
		ok = (t == "Ref")
	elseif t == "Bool" then
		ok = type(value) == "boolean"
	elseif t == "Float32" or t == "Float64" or t == "Int32" or t == "Int64" then
		ok = type(value) == "number"
	elseif t == "String" or t == "Content" or t == "ContentId" then
		ok = type(value) == "string"
	elseif t == "Ref" then
		ok = typeof(value) == "Instance"
	elseif string.sub(t, 1, 5) == "Enum:" then
		local en = string.sub(t, 6)
		if typeof(value) == "EnumItem" then
			ok = value.EnumType == en
		else
			ok = (type(value) == "string" and DB.Enums[en][value] ~= nil) or type(value) == "number"
		end
	elseif t == "Vector3" or t == "Vector2" or t == "CFrame" or t == "Color3" or t == "UDim" or t == "UDim2" or t == "NumberRange" or t == "NumberSequence" or t == "ColorSequence" then
		ok = typeof(value) == t
	end
	if not ok then
		error(string.format("Bad value for %s.%s: expected %s, got %s", className, prop, t, typeof(value)), 3)
	end
end

local Instance = {}
local services = {}

local function new(className, isService)
	local info = classInfo(className)
	if not info then
		error("Unable to create an Instance of type \"" .. tostring(className) .. "\"", 2)
	end
	if not isService and not info.creatable then
		error("Unable to create an Instance of type \"" .. className .. "\" (not creatable)", 2)
	end
	local proxy = setmetatable({}, InstanceMT)
	data[proxy] = { className = className, name = className, children = {}, props = {}, signals = {}, changed = {}, parent = nil, destroyed = false }
	return proxy
end

local methods = {}

local function rec(inst)
	local r = data[inst]
	if not r then
		error("not an Instance", 3)
	end
	return r
end

local function setParent(inst, parent)
	local r = rec(inst)
	if r.destroyed then
		error("The Parent property of " .. r.name .. " is locked", 3)
	end
	if r.parent then
		local siblings = rec(r.parent).children
		for i, c in ipairs(siblings) do
			if c == inst then
				table.remove(siblings, i)
				break
			end
		end
	end
	r.parent = parent
	if parent then
		table.insert(rec(parent).children, inst)
	end
end

local function fireChanged(inst, prop)
	local r = rec(inst)
	local s = r.changed[prop]
	if s then
		s:Fire()
	end
end

-- Callback members (functions you assign), not properties.
local CALLBACKS = { OnInvoke = true, OnServerInvoke = true, OnClientInvoke = true, ProcessReceipt = true }

InstanceMT.__index = function(inst, key)
	local r = rec(inst)
	if CALLBACKS[key] then
		return r.callbacks and r.callbacks[key]
	end
	if key == "Name" then
		return r.name
	elseif key == "Parent" then
		return r.parent
	elseif key == "ClassName" then
		return r.className
	end
	if r.props[key] ~= nil then
		return r.props[key]
	end
	local m = methods[key]
	if m then
		return m
	end
	if EVENTS[key] then
		if not r.signals[key] then
			r.signals[key] = newSignal(key)
		end
		return r.signals[key]
	end
	-- computed properties
	if key == "Position" and isA(r.className, "BasePart") then
		return (r.props.CFrame or CFrame.new()).Position
	end
	local p = findProp(r.className, key)
	if p then
		local info = classInfo(r.className)
		local d = info and info.defaults and info.defaults[key]
		if d ~= nil then
			if type(d) ~= "table" then
				return d
			elseif d[1] == "Color3" then
				return Color3.new(d[2], d[3], d[4])
			elseif d[1] == "Vector3" then
				return Vector3.new(d[2], d[3], d[4])
			elseif d[1] == "Vector2" then
				return Vector2.new(d[2], d[3])
			elseif d[1] == "UDim2" then
				return UDim2.new(d[2], d[3], d[4], d[5])
			elseif d[1] == "UDim" then
				return UDim.new(d[2], d[3])
			elseif d[1] == "Enum" then
				return Enum[d[2]][d[3]]
			end
		end
		return defaultFor(p[1])
	end
	for _, c in ipairs(r.children) do
		if rec(c).name == key then
			return c
		end
	end
	error(tostring(key) .. " is not a valid member of " .. r.className .. " \"" .. r.name .. "\"", 2)
end

InstanceMT.__newindex = function(inst, key, value)
	local r = rec(inst)
	if CALLBACKS[key] then
		assert(value == nil or type(value) == "function", key .. " must be a function")
		r.callbacks = r.callbacks or {}
		r.callbacks[key] = value
		return
	end
	if key == "Name" then
		assert(type(value) == "string", "Name must be a string")
		r.name = value
		return
	elseif key == "Parent" then
		if value ~= nil and typeof(value) ~= "Instance" then
			error("Parent must be an Instance", 2)
		end
		setParent(inst, value)
		return
	end
	-- callbacks (BindableFunction.OnInvoke, RemoteFunction.OnServerInvoke / OnClientInvoke)
	if (key == "OnInvoke" and r.className == "BindableFunction")
		or ((key == "OnServerInvoke" or key == "OnClientInvoke") and r.className == "RemoteFunction") then
		if value ~= nil and type(value) ~= "function" then
			error(key .. " must be a function", 2)
		end
		r.callbacks = r.callbacks or {}
		r.callbacks[key] = value
		return
	end
	if key == "Position" and isA(r.className, "BasePart") then
		checkType(r.className, key, "Vector3", value)
		local cf = r.props.CFrame or CFrame.new()
		r.props.CFrame = cf.Rotation + value
		fireChanged(inst, "CFrame")
		return
	end
	local p = findProp(r.className, key)
	if not p then
		error(tostring(key) .. " is not a valid member of " .. r.className .. " \"" .. r.name .. "\"", 2)
	end
	if p[2] then
		error("Unable to assign property " .. key .. ". Property is read only", 2)
	end
	checkType(r.className, key, p[1], value)
	local old = r.props[key]
	r.props[key] = value
	if old ~= value then
		fireChanged(inst, key)
	end
end
InstanceMT.__tostring = function(inst)
	return rec(inst).name
end

function methods.GetChildren(self)
	return table.clone(rec(self).children)
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(i)
		for _, c in ipairs(rec(i).children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rec(self).children) do
		if rec(c).name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rec(self).children) do
			local f = methods.FindFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.WaitForChild(self, name, timeout)
	local c = methods.FindFirstChild(self, name)
	if not c then
		if timeout ~= nil then
			return nil -- (with a timeout Roblox gives up and returns nil; nothing appears later here)
		end
		error("Infinite yield possible on WaitForChild(\"" .. tostring(name) .. "\") in " .. rec(self).name, 2)
	end
	return c
end
function methods.FindFirstChildOfClass(self, cls)
	for _, c in ipairs(rec(self).children) do
		if rec(c).className == cls then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildWhichIsA(self, cls, recursive)
	for _, c in ipairs(rec(self).children) do
		if isA(rec(c).className, cls) then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rec(self).children) do
			local f = methods.FindFirstChildWhichIsA(c, cls, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function methods.IsA(self, cls)
	assert(classInfo(cls), "IsA: unknown class " .. tostring(cls))
	return isA(rec(self).className, cls)
end
function methods.IsDescendantOf(self, other)
	local p = rec(self).parent
	while p do
		if p == other then
			return true
		end
		p = rec(p).parent
	end
	return false
end
function methods.Destroy(self)
	local r = rec(self)
	if r.destroyed then
		return
	end
	for _, c in ipairs(table.clone(r.children)) do
		methods.Destroy(c)
	end
	setParent(self, nil)
	r.destroyed = true
end
function methods.ClearAllChildren(self)
	for _, c in ipairs(table.clone(rec(self).children)) do
		methods.Destroy(c)
	end
end
function methods.Clone(self)
	local r = rec(self)
	local c = new(r.className, true)
	local cr = rec(c)
	cr.name = r.name
	for k, v in pairs(r.props) do
		cr.props[k] = v
	end
	for _, child in ipairs(r.children) do
		local cc = methods.Clone(child)
		setParent(cc, c)
	end
	return c
end
function methods.GetPropertyChangedSignal(self, prop)
	local r = rec(self)
	if not findProp(r.className, prop) and prop ~= "Name" and prop ~= "Parent" then
		error("GetPropertyChangedSignal: " .. tostring(prop) .. " is not a property of " .. r.className, 2)
	end
	if not r.changed[prop] then
		r.changed[prop] = newSignal(prop .. "Changed")
	end
	return r.changed[prop]
end
-- Attributes: stored, type-checked like Roblox (no tables, functions or Instances).
local ATTR_TYPES = { boolean = true, number = true, string = true, Color3 = true, Vector3 = true, Vector2 = true, UDim = true, UDim2 = true, CFrame = true, NumberRange = true, NumberSequence = true, ColorSequence = true, BrickColor = true, Rect = true }
function methods.GetAttribute(self, name)
	assert(type(name) == "string", "GetAttribute needs a name")
	local a = rec(self).attrs
	return a and a[name]
end
function methods.SetAttribute(self, name, value)
	assert(type(name) == "string" and #name > 0 and #name <= 100, "SetAttribute needs a name")
	if value ~= nil and not ATTR_TYPES[typeof(value)] then
		error("SetAttribute: " .. typeof(value) .. " is not a supported attribute type (" .. name .. ")", 2)
	end
	local r = rec(self)
	r.attrs = r.attrs or {}
	local old = r.attrs[name]
	r.attrs[name] = value
	if old ~= value and r.attrSignals and r.attrSignals[name] then
		r.attrSignals[name]:Fire()
	end
	if old ~= value and r.signals and r.signals.AttributeChanged then
		r.signals.AttributeChanged:Fire(name)
	end
end
function methods.GetAttributes(self)
	return table.clone(rec(self).attrs or {})
end
function methods.GetAttributeChangedSignal(self, name)
	local r = rec(self)
	r.attrSignals = r.attrSignals or {}
	if not r.attrSignals[name] then
		r.attrSignals[name] = newSignal("AttributeChanged")
	end
	return r.attrSignals[name]
end
function methods.GetFullName(self)
	local parts = {}
	local i = self
	while i do
		table.insert(parts, 1, rec(i).name)
		i = rec(i).parent
	end
	return table.concat(parts, ".")
end

-- PVInstance / Model
local function parts(self)
	local out = {}
	if isA(rec(self).className, "BasePart") then
		table.insert(out, self)
	end
	for _, d in ipairs(methods.GetDescendants(self)) do
		if isA(rec(d).className, "BasePart") then
			table.insert(out, d)
		end
	end
	return out
end
function methods.GetPivot(self)
	local r = rec(self)
	if isA(r.className, "BasePart") then
		return r.props.CFrame or CFrame.new()
	end
	assert(isA(r.className, "Model"), "GetPivot on " .. r.className)
	local pp = r.props.PrimaryPart
	if pp then
		return rec(pp).props.CFrame or CFrame.new()
	end
	return r.props.WorldPivot or CFrame.new()
end
-- Roblox keeps part rotations orthonormal. Without this, the tiny rounding error of
-- delta = cf * cur:Inverse() doubles on every PivotTo, and a model that is moved every frame
-- (idle breathing) flies apart to infinity within a second of simulated frames.
local function orthonormal(cf)
	local r = cf._r
	local x1, x2, x3 = r[1], r[4], r[7]
	local lx = math.sqrt(x1 * x1 + x2 * x2 + x3 * x3)
	if lx < 1e-12 then
		return cf
	end
	x1, x2, x3 = x1 / lx, x2 / lx, x3 / lx
	local y1, y2, y3 = r[2], r[5], r[8]
	local d = x1 * y1 + x2 * y2 + x3 * y3
	y1, y2, y3 = y1 - d * x1, y2 - d * x2, y3 - d * x3
	local ly = math.sqrt(y1 * y1 + y2 * y2 + y3 * y3)
	if ly < 1e-12 then
		return cf
	end
	y1, y2, y3 = y1 / ly, y2 / ly, y3 / ly
	local z1, z2, z3 = x2 * y3 - x3 * y2, x3 * y1 - x1 * y3, x1 * y2 - x2 * y1
	local p = cf._p
	return cfRaw(p.X, p.Y, p.Z, x1, y1, z1, x2, y2, z2, x3, y3, z3)
end
function methods.PivotTo(self, cf)
	assert(typeof(cf) == "CFrame", "PivotTo needs a CFrame")
	local r = rec(self)
	local cur = orthonormal(methods.GetPivot(self))
	local delta = orthonormal(cf) * cur:Inverse()
	for _, p in ipairs(parts(self)) do
		local pr = rec(p)
		pr.props.CFrame = orthonormal(delta * (pr.props.CFrame or CFrame.new()))
	end
	if isA(r.className, "Model") then
		r.props.WorldPivot = cf
	end
end
-- The box round a model's parts (axis-aligned in the model's pivot; good enough for sizes).
function methods.GetBoundingBox(self)
	assert(isA(rec(self).className, "Model"), "GetBoundingBox is a Model method")
	local lo, hi = nil, nil
	for _, p in ipairs(parts(self)) do
		local pr = rec(p)
		local c = (pr.props.CFrame or CFrame.new()).Position
		local half = (pr.props.Size or Vector3.new(4, 1, 2)) / 2
		local a, b = c - half, c + half
		lo = lo and Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) or a
		hi = hi and Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) or b
	end
	if not lo then
		return methods.GetPivot(self), Vector3.new()
	end
	local scale = rec(self).scale or 1
	return CFrame.new((lo + hi) / 2), (hi - lo) * scale
end
function methods.ScaleTo(self, s)
	assert(type(s) == "number" and s > 0, "ScaleTo needs a positive number")
	assert(isA(rec(self).className, "Model"), "ScaleTo is a Model method")
	rec(self).scale = s
end
function methods.GetScale(self)
	return rec(self).scale or 1
end

-- Specific classes
function methods.GetService(self, name)
	local s = services[name]
	if not s then
		error("GetService: unknown service " .. tostring(name), 2)
	end
	return s
end
function methods.Raycast(self, origin, dir, params)
	assert(typeof(origin) == "Vector3" and typeof(dir) == "Vector3", "Raycast needs Vector3s")
	if params ~= nil then
		assert(typeof(params) == "RaycastParams", "Raycast params must be RaycastParams")
	end
	if M.raycastHook then
		return M.raycastHook(origin, dir, params)
	end
	return nil
end
function methods.GetServerTimeNow()
	return now
end
function methods.ViewportPointToRay(self, x, y)
	assert(type(x) == "number" and type(y) == "number", "ViewportPointToRay needs numbers")
	return setmetatable({ Origin = Vector3.new(0, 10, 20), Direction = Vector3.new(0, -0.3, -1).Unit }, { __type = "Ray" })
end
function methods.ScreenPointToRay(self, x, y)
	return methods.ViewportPointToRay(self, x, y)
end
-- Projects a world point with the camera's CFrame and FieldOfView onto a 1280x720 viewport.
function methods.WorldToViewportPoint(self, p)
	assert(rec(self).className == "Camera", "WorldToViewportPoint is a Camera method")
	assert(typeof(p) == "Vector3", "WorldToViewportPoint needs a Vector3")
	local cf = rec(self).props.CFrame or CFrame.new()
	local fov = rec(self).props.FieldOfView or 70
	local d = p - cf.Position
	local x, y, z = d:Dot(cf.RightVector), d:Dot(cf.UpVector), d:Dot(cf.LookVector)
	if z <= 0.001 then
		return Vector3.new(0, 0, z), false
	end
	local w, h = 1280, 720
	local t = math.tan(math.rad(fov) / 2)
	local sx = w / 2 + (x / z) / (t * w / h) * w / 2
	local sy = h / 2 - (y / z) / t * h / 2
	return Vector3.new(sx, sy, z), sx >= 0 and sx <= w and sy >= 0 and sy <= h
end
methods.WorldToScreenPoint = methods.WorldToViewportPoint
function methods.Sit(self, humanoid)
	assert(rec(self).className == "Seat", "Sit on non-seat")
	rec(self).props.Occupant = humanoid
	rec(humanoid).props.SeatPart = self
end
function methods.Invoke(self, ...)
	local r = rec(self)
	assert(r.className == "BindableFunction", "Invoke on " .. r.className)
	local cb = r.callbacks and r.callbacks.OnInvoke
	if not cb then
		error("BindableFunction \"" .. r.name .. "\" has no OnInvoke callback", 2)
	end
	return cb(...)
end
function methods.FireServer(self, ...)
	assert(rec(self).className == "RemoteEvent", "FireServer on " .. rec(self).className)
	local args = M.remoteCopy(table.pack(...))
	local sig = self.OnServerEvent
	task.defer(function()
		sig:Fire(M.localPlayer, table.unpack(args, 1, args.n))
	end)
end
function methods.FireAllClients(self, ...)
	assert(rec(self).className == "RemoteEvent", "FireAllClients on " .. rec(self).className)
	local args = M.remoteCopy(table.pack(...))
	local sig = self.OnClientEvent
	task.defer(function()
		sig:Fire(table.unpack(args, 1, args.n))
	end)
end
-- BindableEvent:Fire (server to server, no copying across the network)
function methods.Fire(self, ...)
	assert(rec(self).className == "BindableEvent", "Fire on " .. rec(self).className)
	self.Event:Fire(...)
end
function methods.FireClient(self, player, ...)
	assert(rec(self).className == "RemoteEvent", "FireClient on " .. rec(self).className)
	assert(typeof(player) == "Instance" and rec(player).className == "Player", "FireClient needs a Player first")
	local args = M.remoteCopy(table.pack(...))
	local sig = self.OnClientEvent
	task.defer(function()
		sig:Fire(table.unpack(args, 1, args.n))
	end)
end
function methods.Create(self, inst, info, goals)
	assert(rec(self).className == "TweenService", "Create is a TweenService method")
	assert(typeof(inst) == "Instance", "Tween target must be an Instance")
	assert(typeof(info) == "TweenInfo", "Tween needs TweenInfo")
	for k, v in pairs(goals) do
		local p = findProp(rec(inst).className, k)
		if not p and not (k == "Position" and isA(rec(inst).className, "BasePart")) then
			error("Tween goal " .. k .. " is not a property of " .. rec(inst).className, 2)
		end
		if p then
			checkType(rec(inst).className, k, p[1], v)
		end
	end
	local tween = new("Tween", true)
	rec(tween).tween = { inst = inst, info = info, goals = goals }
	return tween
end
function methods.Play(self)
	if rec(self).className == "Sound" then
		assert(rec(self).props.SoundId ~= nil and rec(self).props.SoundId ~= "", "Play on a Sound with no SoundId")
		rec(self).props.IsPlaying = true
		M.soundsPlayed = (M.soundsPlayed or 0) + 1
		M.soundLog = M.soundLog or {}
		table.insert(M.soundLog, rec(self).name)
		return
	end
	local t = rec(self).tween
	assert(t, "Play on non-tween")
	task.delay(t.info.Time, function()
		local tr = rec(t.inst)
		if not tr.destroyed then
			for k, v in pairs(t.goals) do
				t.inst[k] = v
			end
		end
		self.Completed:Fire(Enum.PlaybackState.Completed)
	end)
end
function methods.Cancel() end
function methods.Stop(self)
	assert(rec(self).className == "Sound", "Stop on " .. rec(self).className)
	rec(self).props.IsPlaying = false
end
function methods.AddItem(self, inst, t)
	assert(rec(self).className == "Debris", "AddItem is a Debris method")
	task.delay(t or 10, function()
		methods.Destroy(inst)
	end)
end
function methods.Emit(self, n)
	assert(rec(self).className == "ParticleEmitter", "Emit on " .. rec(self).className)
	assert(type(n) == "number", "Emit needs a number")
end
function methods.SetCoreGuiEnabled(self, t, on)
	assert(typeof(t) == "EnumItem" and t.EnumType == "CoreGuiType", "SetCoreGuiEnabled needs a CoreGuiType")
end
-- TextChannel:DisplaySystemMessage (the chat's system lines are logged in M.chatLog)
M.chatLog = {}
function methods.DisplaySystemMessage(self, text)
	assert(rec(self).className == "TextChannel", "DisplaySystemMessage on " .. rec(self).className)
	assert(type(text) == "string", "DisplaySystemMessage needs a string")
	table.insert(M.chatLog, text)
end
function methods.GetMouseLocation()
	return Vector2.new(640, 360)
end
function methods.GetFocusedTextBox()
	return nil
end
function methods.GetPlayers()
	return { M.localPlayer }
end
function methods.IsServer()
	return true
end
function methods.IsClient()
	return true
end
-- the simulated game counts as Studio (tier preview buttons show up)
function methods.IsStudio()
	return true
end

---------------------------------------------------------------------------
-- Economy services: DataStores, Marketplace, Policy, player lookups, kicks
---------------------------------------------------------------------------
M.userIds = {} -- username -> UserId for Players:GetUserIdFromNameAsync
M.kicked = {} -- [player] = message
M.prompts = {} -- { { player, productId } }
M.closeFns = {} -- game:BindToClose functions
M.policy = { ArePaidRandomItemsRestricted = false }
M.dataStores = {} -- [name] = { data = { [key] = value }, failNext = n, writes = n }

-- DataStores only take what Roblox can save: no functions, NaN/inf, mixed or sparse tables.
local function checkSaveable(v, path, depth)
	depth = depth or 0
	if depth > 40 then
		error("DataStore: value nested too deep at " .. path, 4)
	end
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("DataStore: can't save NaN/inf at " .. path, 4)
		end
	elseif t == "function" or t == "thread" or t == "userdata" then
		error("DataStore: can't save a " .. typeof(v) .. " at " .. path, 4)
	elseif t == "table" then
		local n, hasNum, hasStr = 0, false, false
		for k, x in pairs(v) do
			n += 1
			if type(k) == "number" then
				hasNum = true
			elseif type(k) == "string" then
				hasStr = true
			else
				error("DataStore: table key of type " .. type(k) .. " at " .. path, 4)
			end
			checkSaveable(x, path .. "." .. tostring(k), depth + 1)
		end
		if hasNum and hasStr then
			error("DataStore: can't save a mixed table at " .. path, 4)
		end
		if hasNum then
			for i = 1, n do
				if v[i] == nil then
					error("DataStore: can't save a sparse array at " .. path, 4)
				end
			end
		end
	end
end
local function deep(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = deep(x)
	end
	return o
end
function methods.GetDataStore(self, name)
	assert(rec(self).className == "DataStoreService", "GetDataStore is a DataStoreService method")
	assert(type(name) == "string", "GetDataStore needs a name")
	local st = M.dataStores[name]
	if not st then
		st = { data = {}, failNext = 0, writes = 0 }
		M.dataStores[name] = st
		local function maybeFail()
			if st.failNext > 0 then
				st.failNext -= 1
				error("502: API Services rejected request (simulated)")
			end
		end
		function st.GetAsync(_, key)
			assert(type(key) == "string", "DataStore key must be a string")
			maybeFail()
			return deep(st.data[key])
		end
		function st.SetAsync(_, key, value)
			maybeFail()
			checkSaveable(value, key)
			st.writes += 1
			st.data[key] = deep(value)
		end
		function st.UpdateAsync(_, key, fn)
			assert(type(key) == "string" and type(fn) == "function", "UpdateAsync(key, fn)")
			maybeFail()
			local new = fn(deep(st.data[key]), nil)
			if new ~= nil then
				checkSaveable(new, key)
				st.writes += 1
				st.data[key] = deep(new)
			end
			return deep(new)
		end
	end
	return st
end
function methods.GetUserIdFromNameAsync(self, name)
	local id = M.userIds[name]
	if not id then
		error("HTTP 400 (Bad Request): unknown user " .. tostring(name))
	end
	return id
end
function methods.GetPlayerByUserId(self, id)
	for _, p in ipairs(methods.GetPlayers()) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
function methods.Kick(self, message)
	M.kicked[self] = message or ""
	report("warning", "kicked " .. tostring(self) .. ": " .. tostring(message))
end
function methods.BindToClose(self, fn)
	table.insert(M.closeFns, fn)
end
function methods.PromptProductPurchase(self, player, productId)
	assert(typeof(player) == "Instance" and type(productId) == "number", "PromptProductPurchase(player, id)")
	table.insert(M.prompts, { player = player, productId = productId })
end
function methods.GetPolicyInfoForPlayerAsync(self, player)
	return table.clone(M.policy)
end
function methods.Invoke(self, ...)
	assert(rec(self).className == "BindableFunction", "Invoke is a BindableFunction method")
	local fn = rec(self).callbacks and rec(self).callbacks.OnInvoke
	if not fn then
		error("BindableFunction has no OnInvoke", 2)
	end
	return fn(...)
end

function Instance.new(className, parent)
	local i = new(className)
	if parent then
		i.Parent = parent
	end
	return i
end

-- What a real click needs. Roblox only fires Activated on a button that is Active, inside
-- GuiObjects that are all Visible and Interactable, in an enabled ScreenGui. The harnesses
-- click through this so a button players can't use fails the test.
function M.clickable(b)
	if not b:IsA("GuiButton") then
		return false, b.ClassName .. " is not a button"
	end
	if not b.Active then
		return false, "Active is false, so Roblox never fires Activated"
	end
	local node = b
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false, node:GetFullName() .. " is hidden"
			end
			if node.Interactable == false then
				return false, node:GetFullName() .. " is not Interactable"
			end
		elseif node:IsA("LayerCollector") then
			if not node.Enabled then
				return false, node:GetFullName() .. " is disabled"
			end
			return true
		end
		node = node.Parent
	end
	return false, "not inside a ScreenGui"
end

-- Build from a description table (used for the room)
function M.build(desc, parent)
	local inst = new(desc.ClassName, true)
	inst.Name = desc.Name
	for k, v in pairs(desc.Properties or {}) do
		inst[k] = v
	end
	for _, c in ipairs(desc.Children or {}) do
		M.build(c, inst)
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Remote events copy their arguments and reject things Roblox can't send.
function M.remoteCopy(v, path)
	path = path or "arg"
	local t = typeof(v)
	if t == "function" or t == "thread" then
		error("Remote can't send a " .. t .. " at " .. path, 3)
	end
	if t ~= "table" then
		return v
	end
	local n, hasNum, hasStr = 0, false, false
	for k in pairs(v) do
		n += 1
		if type(k) == "number" then
			hasNum = true
		elseif type(k) == "string" then
			hasStr = true
		else
			error("Remote table key of type " .. type(k) .. " at " .. path, 3)
		end
	end
	if hasNum and hasStr and path ~= "arg" then
		error("Remote can't send a mixed table at " .. path, 3)
	end
	if hasNum and not hasStr then
		for i = 1, n do
			if v[i] == nil then
				error("Remote array has a hole at " .. path .. "[" .. i .. "] (Roblox would cut it short)", 3)
			end
		end
	end
	local out = {}
	for k, val in pairs(v) do
		if k ~= "n" or path ~= "arg" then
			out[k] = M.remoteCopy(val, path .. "." .. tostring(k))
		end
	end
	if path == "arg" then
		out.n = v.n
	end
	return out
end

-- Globals for scripts
M.env = {
	Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3, UDim = UDim, UDim2 = UDim2,
	NumberRange = NumberRange, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, TweenInfo = TweenInfo,
	RaycastParams = RaycastParams, Enum = Enum, Instance = Instance, task = task, typeof = typeof,
	Random = {
		new = function(seed)
			local st = math.floor(seed or 12345) % 2147483647
			if st <= 0 then
				st = 1
			end
			local function nxt()
				st = (st * 48271) % 2147483647
				return st / 2147483647
			end
			return {
				NextNumber = function(_, lo, hi)
					lo, hi = lo or 0, hi or 1
					return lo + (hi - lo) * nxt()
				end,
				NextInteger = function(_, lo, hi)
					return lo + math.floor(nxt() * (hi - lo + 1))
				end,
			}
		end,
	},
	warn = function(...)
		local parts = {}
		for _, v in ipairs({ ... }) do
			table.insert(parts, tostring(v))
		end
		report("warning", "warn(): " .. table.concat(parts, " "))
	end,
	tick = function()
		return now
	end,
	time = function()
		return now
	end,
	wait = function(t)
		return task.wait(t)
	end,
}

function M.service(name, className)
	local s = new(className or name, true)
	s.Name = name
	services[name] = s
	return s
end
M.new = new
M.rec = rec
M.isA = isA
M.methods = methods

return M

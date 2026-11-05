-- Prints snapshots of creatures frozen at moments of their fighting moves, for preview/brawl.py.
-- Rough check of the rigs (are the arms, legs and heads moving the right way?), no Roblox needed.
-- Usage:
--   luaurun -D IDS="toaster_knight,lightning_llama" preview/rig_poses.luau src/packbrawl src/shared > poses.log
--   python3 preview/brawl.py poses.log out/
-- Optional: -D MOVES="jab@0.12,kick@0.2" (move@seconds; "sig" = the creature's signature move).
local Rig = require("Rig")
local Moves = require("Moves")
local Data = require("CreatureModelData")

local function split(s)
	local out = {}
	for w in string.gmatch(s, "[^,]+") do
		table.insert(out, w)
	end
	return out
end
local ids = split(rawget(_G, "IDS") or "toaster_knight")
local moves = split(rawget(_G, "MOVES") or "stance@0,jab@0.12,hook@0.2,uppercut@0.2,kick@0.2,block@0.15,stagger@0.06,sig@0.3,sig@0.45")

local function cross(a, b)
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end
local function norm(a)
	local l = math.sqrt(a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2)
	return { a[1] / l, a[2] / l, a[3] / l }
end

for _, id in ipairs(ids) do
	local rig = Rig.get(id)
	local spec = Data[id]
	local h = rig.height
	for _, mv in ipairs(moves) do
		local name, at = mv:match("([^@]+)@?([%d%.]*)")
		local t = tonumber(at) or 0
		local pose
		if name == "stance" then
			pose = Moves.stance(0, 0, rig)
		elseif name == "limp" then
			pose = Moves.limp(0, 0)
		elseif name == "run" then
			pose = Moves.run(t, 0, 1, rig)
		else
			local key = name == "sig" and id or name
			local m = Moves.get(key)
			if not m then
				m = Moves.get(Moves.pickAttack(rig, 3, 0, id, false))
			end
			pose = Moves.sample(m, t)
			if m.headStagger and rig.has.heads > 1 then
				pose = table.clone(pose)
				pose.headLag = {}
				for n = 2, rig.has.heads do
					pose.headLag[n] = Moves.sample(m, math.max(t - m.headStagger * (n - 1), 0)).head
				end
			end
		end
		pose = table.clone(pose)
		pose.leadSide = rig.weaponSide == -1 and "L" or "R"
		local solved = Rig.solve(rig, pose)
		print("SNAP|" .. id .. "_" .. name .. "_" .. t)
		for i, p in ipairs(spec.parts) do
			local rp = rig.parts[i]
			local tf = solved[rig.partBone[i]]
			local m = rp.rot
			local x, y, z = rp.pos[1], rp.pos[2], rp.pos[3]
			if tf then
				m = Rig.mmul(tf.m, rp.rot)
				x, y, z = Rig.mvec(tf.m, x, y, z)
				x, y, z = x + tf.t[1], y + tf.t[2], z + tf.t[3]
			end
			if p[16] < 0.98 then
				print(string.format("PART|%s|%.3f|%.3f|%.3f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.3f|%.3f|%.3f|%d|%d|%d|%.2f|%s",
					p[1], x, y, z, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9], p[3], p[4], p[5], p[12], p[13], p[14], p[16], p[15]))
			end
		end
		-- floor
		print(string.format("PART|B|0|-0.05|0|1|0|0|0|1|0|0|0|1|%.2f|0.1|%.2f|70|60|90|0.00|SmoothPlastic", h * 4, h * 4))
		-- camera: front three-quarter view from the lead (right) side
		local target = { 0, h * 0.5, 0 }
		local cam = { h * 1.15, h * 0.75, -h * 1.6 }
		local back = norm({ cam[1] - target[1], cam[2] - target[2], cam[3] - target[3] })
		local right = norm(cross({ 0, 1, 0 }, back))
		local up = cross(back, right)
		print(string.format("CAM|%.3f|%.3f|%.3f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|50", cam[1], cam[2], cam[3], right[1], up[1], back[1], right[2], up[2], back[2], right[3], up[3], back[3]))
		print("END")
	end
end

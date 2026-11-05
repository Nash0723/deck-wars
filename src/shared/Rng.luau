--!strict
-- Small seeded random number generator (xorshift32).
-- Same seed = same results, which makes matches replayable and testable.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number?): Rng
	local s = math.floor(seed or (os.time() * 1000 + math.random(1, 999))) % 4294967296
	if s == 0 then
		s = 2463534242
	end
	return setmetatable({ state = s }, Rng)
end

function Rng.next(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / 4294967296
end

-- Whole number from lo to hi, both included.
function Rng.int(self: Rng, lo: number, hi: number): number
	return lo + math.floor(self:next() * (hi - lo + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[self:int(1, #list)]
end

function Rng.shuffle<T>(self: Rng, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return Rng

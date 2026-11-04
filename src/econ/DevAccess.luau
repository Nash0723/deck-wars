-- Who counts as a Deck Wars developer (free rolls, test currency, the DevControls panel).
-- Server only: this module lives in ServerStorage, so players' game clients can't even read it.
--
-- The check is always by numeric UserId, which can't be faked from a client. Usernames are only
-- used to LOOK UP the UserId once when the server starts (Players:GetUserIdFromNameAsync).
-- Best: paste the numeric ids into UserIds below (find them in the address bar of the
-- player's Roblox profile page: roblox.com/users/<UserId>/profile), then the lookup isn't needed.

local DevAccess = {}

-- Numeric UserIds that are developers. Fill these in when you know them.
DevAccess.UserIds = {
	-- [123456789] = true, -- DNash2307
	-- [987654321] = true, -- donatjalt
}

-- Usernames looked up at server start. A name that was renamed or doesn't exist just fails
-- the lookup (it never matches anyone).
DevAccess.Usernames = { "DNash2307", "donatjalt" }

-- The experience's owner (when it's owned by a user, not a group) is always a developer.
DevAccess.OwnerIsDev = true

-- In Studio tests with fake players (Player1, Player2 in a local server have UserIds -1, -2),
-- turn this on to give them the dev tools too. It can never be on in a live game.
DevAccess.StudioTestPlayersAreDevs = false

local resolved = {} -- [userId] = username, from the lookups
local lookupDone = false
local lookupStarted = false

local function services()
	return game:GetService("Players"), game:GetService("RunService")
end

-- Looks up the usernames' UserIds (once). Yields; safe to call many times.
function DevAccess.resolve()
	if lookupDone then
		return
	end
	if lookupStarted then
		local waited = 0
		while not lookupDone and waited < 15 do
			task.wait(0.1)
			waited += 0.1
		end
		return
	end
	lookupStarted = true
	local Players = services()
	for _, name in ipairs(DevAccess.Usernames) do
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(name)
		end)
		if ok and type(id) == "number" and id > 0 then
			resolved[id] = name
		else
			warn("DevAccess: couldn't look up the UserId of " .. name .. " (" .. tostring(id) .. ")")
		end
	end
	lookupDone = true
end

-- true if this player is a developer. Never yields: call DevAccess.resolve() once at server
-- start (EconomyServer does) so the username lookups are finished.
function DevAccess.isDev(player): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	local id = player.UserId
	if DevAccess.UserIds[id] or resolved[id] then
		return true
	end
	if DevAccess.OwnerIsDev and game.CreatorType == Enum.CreatorType.User and id > 0 and id == game.CreatorId then
		return true
	end
	local _, RunService = services()
	if DevAccess.StudioTestPlayersAreDevs and RunService:IsStudio() and id <= 0 then
		return true
	end
	return false
end

-- For the panel's status line.
function DevAccess.describe(player): string
	local id = player.UserId
	if DevAccess.UserIds[id] then
		return "whitelisted UserId " .. id
	elseif resolved[id] then
		return "whitelisted as " .. resolved[id] .. " (UserId " .. id .. ")"
	elseif DevAccess.OwnerIsDev and game.CreatorType == Enum.CreatorType.User and id == game.CreatorId then
		return "experience owner (UserId " .. id .. ")"
	end
	return "Studio test player (UserId " .. id .. ")"
end

return DevAccess

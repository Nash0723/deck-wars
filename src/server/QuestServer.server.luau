-- The Quest Hall's server (the hall itself is on the north lawn of the Park: ParkBuilder). Quests
-- are finished anywhere but claimed here, at Quill's counter, so you walk out to the Park for
-- your rewards. Answers ReplicatedStorage.QuestRemotes.QuestAction:
--
--   "State"                   -> QuestEvent { kind = "state", book }   (anywhere: the room's
--                                Trophy Wall shows your quests too, read only)
--   "Claim"  { key }          -> QuestEvent { kind = "claimed", ok, key, reward | why, book }
--   "Swap"   { key }          -> QuestEvent { kind = "swapped", ok, key, old, new | why, book }
--   "Chest"  { index }        -> QuestEvent { kind = "chest", ok, index, reward | why, book }
--   "DevNewDay" / "DevNewWeek" (developers only: DevAccess) -> a fresh day or week of quests
--
-- Claiming, swapping and opening chests only work at the hall: you have to be in the Park
-- (InPark) and within Quests.ClaimDistance of Park.QuestHall.Desk. The rules and the save are in
-- QuestBook (through PlayerData, which also pays XP and level-ups).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("DeckWars")
local Quests = require(Shared:WaitForChild("Quests"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local remotes = ReplicatedStorage:WaitForChild("QuestRemotes")
local QuestAction = remotes:WaitForChild("QuestAction")
local QuestEvent = remotes:WaitForChild("QuestEvent")

-- Developers (DevAccess, server only) get the hall's "New day" and "New week" buttons.
local DevAccess = nil
do
	local folder = ServerStorage:FindFirstChild("DeckWarsServer")
	local mod = folder and folder:FindFirstChild("DevAccess")
	if mod then
		local ok, m = pcall(require, mod)
		DevAccess = ok and m or nil
	end
end

local GAP = 0.25 -- seconds between two requests from one player
local last = {} -- [player] = time of the last request

local function deskPart()
	local park = workspace:FindFirstChild("Park")
	local hall = park and park:FindFirstChild("QuestHall")
	return hall and hall:FindFirstChild("Desk")
end

-- Is the player standing at the Quest Hall? (In the Park, near Quill's counter.)
local function atHall(player)
	if player:GetAttribute("InPark") ~= true then
		return false, "Walk out to the Quest Hall in the Park to claim it."
	end
	local desk = deskPart()
	if not desk then
		return true -- (a park built by hand without the hall: anywhere in the Park will do)
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false, "Walk up to Quill's counter."
	end
	if (root.Position - desk.Position).Magnitude > Quests.ClaimDistance + 6 then
		return false, "Walk up to Quill's counter in the Quest Hall."
	end
	return true
end

local function isDev(player)
	if not DevAccess or not DevAccess.isDev then
		return false
	end
	local ok, yes = pcall(DevAccess.isDev, player)
	return ok and yes == true
end

local function send(player, payload)
	payload.book = payload.book or PlayerData.questSnapshot(player)
	QuestEvent:FireClient(player, payload)
end

QuestAction.OnServerEvent:Connect(function(player, what, options)
	if type(what) ~= "string" then
		return
	end
	options = type(options) == "table" and options or {}
	local now = os.clock()
	if last[player] and now - last[player] < GAP then
		return
	end
	last[player] = now
	if what == "State" then
		send(player, { kind = "state" })
	elseif what == "Claim" then
		local key = type(options.key) == "string" and string.sub(options.key, 1, 64) or nil
		local here, whyNot = atHall(player)
		if not here then
			send(player, { kind = "claimed", ok = false, key = key, why = whyNot })
			return
		end
		local r, why = PlayerData.claimQuest(player, key)
		send(player, { kind = "claimed", ok = r ~= nil, key = key, reward = r, why = why })
	elseif what == "Swap" then
		local key = type(options.key) == "string" and string.sub(options.key, 1, 64) or nil
		local here, whyNot = atHall(player)
		if not here then
			send(player, { kind = "swapped", ok = false, key = key, why = whyNot })
			return
		end
		local r, why = PlayerData.swapQuest(player, key)
		send(player, { kind = "swapped", ok = r ~= nil, key = key, old = r and r.old, new = r and r.new, why = why })
	elseif what == "Chest" then
		local index = tonumber(options.index)
		index = index and math.floor(index) or nil
		local here, whyNot = atHall(player)
		if not here then
			send(player, { kind = "chest", ok = false, index = index, why = whyNot })
			return
		end
		local r, why = PlayerData.openQuestChest(player, index)
		send(player, { kind = "chest", ok = r ~= nil, index = index, reward = r, why = why })
	elseif what == "DevNewDay" or what == "DevNewWeek" then
		if not isDev(player) then
			return
		end
		if what == "DevNewDay" then
			PlayerData.debugNewDay(player)
		else
			PlayerData.debugNewWeek(player)
		end
		send(player, { kind = "state", note = what == "DevNewDay" and "New daily quests." or "A new week: new weekly quests, Renown back to 0." })
	end
end)

-- Developers see the hall's dev buttons (the check stays on the server either way).
local function onJoin(player)
	task.spawn(function()
		if DevAccess and DevAccess.resolve then
			pcall(DevAccess.resolve)
		end
		if player.Parent then
			player:SetAttribute("QuestDev", isDev(player))
		end
	end)
end
Players.PlayerAdded:Connect(onJoin)
for _, player in ipairs(Players:GetPlayers()) do
	onJoin(player)
end

Players.PlayerRemoving:Connect(function(player)
	last[player] = nil
end)

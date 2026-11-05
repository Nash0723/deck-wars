-- Parties: play with your friends.
--
-- The 👥 Party button (top right of the room) opens a panel where you invite people in this server,
-- or bring Roblox friends in with Roblox's own invite prompt. When the party leader opens a table at
-- the Duel Table (or sits down at one), everyone in the party sits down with them. Invites you get
-- pop up at the top of the screen with Join / No thanks, even in the middle of a match.
-- Client only. DeckWarsClient calls PartyScreen.init(ctx) once.

local PartyScreen = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local UIKit = require(ReplicatedStorage:WaitForChild("DeckWars"):WaitForChild("UIKit"))

local INVITE_SHOW_SECONDS = 55 -- an invite leaves the screen a little before the server closes it (60 s)
local PURPLE = Color3.fromRGB(120, 80, 170)
local GOLD = Color3.fromRGB(255, 220, 90)
local DIM = Color3.fromRGB(190, 185, 210)

function PartyScreen.init(ctx)
	local make, corner, label, button, panel = ctx.make, ctx.corner, ctx.label, ctx.button, ctx.panel
	local WHITE, BODY_FONT = ctx.WHITE, ctx.BODY_FONT
	local player = ctx.player
	local ui = ctx.ui
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	local MenuAction = Remotes:WaitForChild("MenuAction")
	local LobbyEvent = Remotes:WaitForChild("LobbyEvent")

	local P = {
		party = nil, -- { leaderId, members = { { userId, name, leader } }, max } or nil
		invites = {}, -- invites to you, oldest first: { fromUserId, fromName, size, at }
		friends = {}, -- [userId] = true / false once Roblox has told us
		asking = {}, -- [userId] = true while we ask
		sent = {}, -- [userId] = when you invited them
	}

	local function send(what, options)
		MenuAction:FireServer(what, options or {})
	end

	local function toast(text)
		if ctx.toast then
			ctx.toast(text)
		end
	end

	function PartyScreen.party()
		return P.party
	end
	function PartyScreen.isLeader()
		return P.party ~= nil and P.party.leaderId == player.UserId
	end
	function PartyScreen.hasMember(userId)
		for _, m in ipairs(P.party and P.party.members or {}) do
			if m.userId == userId then
				return true
			end
		end
		return false
	end
	local function leaderName()
		for _, m in ipairs(P.party and P.party.members or {}) do
			if m.leader then
				return m.name
			end
		end
		return "?"
	end
	PartyScreen.leaderName = leaderName

	---------------------------------------------------------------------------
	-- The panel
	---------------------------------------------------------------------------

	ui.partyButton = button(ui.menuUI, "👥 Party", PURPLE, function()
		PartyScreen.toggle()
	end, { Name = "PartyButton", Size = UDim2.fromOffset(140, 40), Position = UDim2.new(1, -24, 0, 66), AnchorPoint = Vector2.new(1, 0), TextScaled = false, TextSize = 19 })

	ui.partyPanel = panel(ui.menuUI, UDim2.fromOffset(360, 410), UDim2.fromOffset(24, 212))
	ui.partyPanel.Name = "PartyPanel"
	ui.partyPanel.Visible = false
	local partyTitle = label(ui.partyPanel, "👥 Party", { Size = UDim2.new(1, -130, 0, 32), Position = UDim2.fromOffset(14, 12), TextScaled = false, TextSize = 24, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
	if ctx.headingStyle then
		partyTitle.TextColor3 = Color3.new(1, 1, 1)
		ctx.headingStyle(partyTitle)
	end
	UIKit.rim(ui.partyPanel)
	UIKit.closeButton(ui.partyPanel, function()
		UIKit.close(ui.partyPanel)
	end, { Name = "CloseParty", Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -12, 0, 12), AnchorPoint = Vector2.new(1, 0) })
	local body = make("Frame", { Name = "PartyBody", Size = UDim2.new(1, -28, 1, -62), Position = UDim2.fromOffset(14, 54), BackgroundTransparency = 1 }, ui.partyPanel)

	local function row(parent, text, order, name)
		local r = make("Frame", { Name = name or "Row", Size = UDim2.new(1, -8, 0, 32), BackgroundColor3 = Color3.fromRGB(25, 22, 38), LayoutOrder = order }, parent)
		corner(r, 8)
		local l = label(r, text, { Name = "Who", Size = UDim2.new(1, -140, 1, -8), Position = UDim2.fromOffset(8, 4), Font = BODY_FONT, TextXAlignment = Enum.TextXAlignment.Left })
		local buttons = make("Frame", { Size = UDim2.new(0, 132, 1, -6), Position = UDim2.new(1, -4, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 }, r)
		make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, buttons)
		return r, l, buttons
	end

	local function small(parent, text, color, fn, width, order, name)
		return button(parent, text, color, fn, { Name = name, Size = UDim2.new(0, width, 1, 0), LayoutOrder = order })
	end

	local function list(name, height, order)
		local scroll = make("ScrollingFrame", { Name = name, Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, LayoutOrder = order }, body)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
		return scroll
	end

	-- Ask Roblox (once per person) whether someone is your friend; friends go to the top of the list.
	local function lookUpFriend(userId)
		if P.friends[userId] ~= nil or P.asking[userId] then
			return
		end
		P.asking[userId] = true
		task.spawn(function()
			local ok, yes = pcall(function()
				return player:IsFriendsWith(userId)
			end)
			P.asking[userId] = nil
			P.friends[userId] = ok and yes == true
			if P.friends[userId] then
				PartyScreen.render()
			end
		end)
	end

	-- Roblox's own invite prompt: pick friends who aren't here yet. When they come in from the
	-- invite they land in your party (the invite carries your user id).
	local function inviteFriends()
		if RunService:IsStudio() then
			toast("Roblox friend invites only work in the published game, not in Studio.")
			return
		end
		local ok, can = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not (ok and can) then
			toast("Roblox won't let you send invites right now.")
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = "Come play Deck Wars with me!"
		options.LaunchData = "party:" .. player.UserId
		local shown = pcall(function()
			SocialService:PromptGameInvite(player, options)
		end)
		if shown then
			send("InvitedFriends")
		end
	end

	function PartyScreen.render()
		local party = P.party
		ui.partyButton.Text = party and ("👥 Party (" .. #party.members .. ")") or "👥 Party"
		if not ui.partyPanel.Visible then
			return
		end
		for _, c in ipairs(body:GetChildren()) do
			c:Destroy()
		end
		make("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, body)
		local lead = PartyScreen.isLeader()
		local status
		if not party then
			status = "No party yet. Invite people below: when your party's leader opens a table at the Duel Table, everyone sits down together."
		elseif lead then
			status = "You lead the party (" .. #party.members .. "/" .. party.max .. "). Open a table at the Duel Table and your party sits down with you."
		else
			status = leaderName() .. " leads the party (" .. #party.members .. "/" .. party.max .. "). When they open a table, you sit down with them."
		end
		label(body, status, { Name = "PartyStatus", Size = UDim2.new(1, 0, 0, 46), Font = BODY_FONT, TextWrapped = true, TextColor3 = DIM, LayoutOrder = 1 })

		if party then
			local members = list("Members", math.min(#party.members, 4) * 35, 2)
			for i, m in ipairs(party.members) do
				local you = m.userId == player.UserId
				local _, _, buttons = row(members, (m.leader and "👑 " or "") .. m.name .. (you and " (you)" or ""), i, "Member_" .. m.userId)
				if lead and not you then
					small(buttons, "Lead", Color3.fromRGB(90, 80, 140), function()
						send("PartyLead", { userId = m.userId })
					end, 56, 1, "PartyLead_" .. m.userId)
					small(buttons, "Kick", Color3.fromRGB(110, 60, 70), function()
						send("PartyKick", { userId = m.userId })
					end, 56, 2, "PartyKick_" .. m.userId)
				end
			end
			button(body, "Leave the party", Color3.fromRGB(110, 60, 70), function()
				send("PartyLeave")
			end, { Name = "PartyLeave", Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3 })
		end

		button(body, "📨 Invite Roblox friends to the game", Color3.fromRGB(60, 150, 90), inviteFriends, { Name = "InviteFriends", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 4 })
		label(body, "Players in this server", { Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 5 })
		local others = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				lookUpFriend(p.UserId)
				table.insert(others, p)
			end
		end
		table.sort(others, function(a, b)
			local fa, fb = P.friends[a.UserId] == true, P.friends[b.UserId] == true
			if fa ~= fb then
				return fa
			end
			return a.DisplayName < b.DisplayName
		end)
		local scroll = list("ServerPlayers", party and 104 or 174, 6)
		for i, p in ipairs(others) do
			local friend = P.friends[p.UserId] == true
			local _, nameLabel, buttons = row(scroll, (friend and "⭐ " or "") .. p.DisplayName, i, "Player_" .. p.UserId)
			if friend then
				nameLabel.TextColor3 = GOLD
			end
			if PartyScreen.hasMember(p.UserId) then
				label(buttons, "In party", { Size = UDim2.new(0, 80, 1, 0), Font = BODY_FONT, TextColor3 = Color3.fromRGB(150, 255, 170) })
			elseif P.sent[p.UserId] and time() - P.sent[p.UserId] < 60 then
				label(buttons, "Invited ✓", { Size = UDim2.new(0, 80, 1, 0), Font = BODY_FONT, TextColor3 = DIM })
			else
				small(buttons, "Invite", Color3.fromRGB(70, 130, 220), function()
					P.sent[p.UserId] = time()
					send("PartyInvite", { userId = p.UserId })
					PartyScreen.render()
				end, 80, 1, "Invite_" .. p.UserId)
			end
		end
		if #others == 0 then
			label(scroll, "Nobody else is here yet. Invite your Roblox friends with the green button!", { Size = UDim2.new(1, -8, 0, 44), Font = BODY_FONT, TextWrapped = true, TextColor3 = DIM })
		end
	end

	function PartyScreen.toggle()
		ui.partyPanel.Visible = not ui.partyPanel.Visible
		if ui.partyPanel.Visible then
			-- The bracket and the collection use the same side of the screen.
			if ui.bracketPanel then
				ui.bracketPanel.Visible = false
			end
			if ui.collectionUI then
				ui.collectionUI.Visible = false
			end
			send("RequestParty")
		end
		PartyScreen.render()
	end

	Players.PlayerAdded:Connect(function()
		PartyScreen.render()
	end)
	Players.PlayerRemoving:Connect(function(p)
		task.defer(PartyScreen.render)
		-- Their invites to you go too.
		for i = #P.invites, 1, -1 do
			if P.invites[i].fromUserId == p.UserId then
				table.remove(P.invites, i)
			end
		end
		PartyScreen.showInvite()
	end)

	---------------------------------------------------------------------------
	-- Invites to you: a card at the top of the screen
	---------------------------------------------------------------------------

	ui.invitePopup = make("Frame", {
		Name = "PartyInvite",
		Size = UDim2.fromOffset(460, 118),
		Position = UDim2.new(0.5, 0, 0, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(35, 30, 50),
		Visible = false,
		ZIndex = 70,
	}, ctx.gui)
	corner(ui.invitePopup, 14)
	make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(190, 140, 255) }, ui.invitePopup)
	ui.inviteText = label(ui.invitePopup, "", { Name = "InviteText", Size = UDim2.new(1, -24, 0, 54), Position = UDim2.fromOffset(12, 8), TextWrapped = true })

	local function answer(accept)
		local inv = table.remove(P.invites, 1)
		if inv then
			send("PartyAnswer", { fromUserId = inv.fromUserId, accept = accept })
		end
		PartyScreen.showInvite()
	end
	button(ui.invitePopup, "Join", Color3.fromRGB(60, 180, 90), function()
		answer(true)
	end, { Name = "PartyJoin", Size = UDim2.new(0.5, -18, 0, 40), Position = UDim2.new(0, 12, 1, -50) })
	button(ui.invitePopup, "No thanks", Color3.fromRGB(110, 60, 70), function()
		answer(false)
	end, { Name = "PartyDecline", Size = UDim2.new(0.5, -18, 0, 40), Position = UDim2.new(0.5, 6, 1, -50) })

	-- Show the oldest open invite (dropping ones that ran out), or hide the card.
	function PartyScreen.showInvite()
		while P.invites[1] and time() - P.invites[1].at > INVITE_SHOW_SECONDS do
			table.remove(P.invites, 1)
		end
		local inv = P.invites[1]
		ui.invitePopup.Visible = inv ~= nil
		if inv then
			local others = inv.size and inv.size > 1 and (" (" .. inv.size .. " in it)") or ""
			ui.inviteText.Text = "👥 " .. inv.fromName .. " invited you to their party" .. others .. ". Join and sit down at their tables together!"
			task.delay(INVITE_SHOW_SECONDS + 0.5, PartyScreen.showInvite)
		end
	end

	LobbyEvent.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "party" then
			P.party = payload.party
			if P.party then
				-- Invites from people already in your party don't matter any more.
				for i = #P.invites, 1, -1 do
					if PartyScreen.hasMember(P.invites[i].fromUserId) then
						table.remove(P.invites, i)
					end
				end
				PartyScreen.showInvite()
			end
			PartyScreen.render()
			if ctx.onPartyChanged then
				ctx.onPartyChanged()
			end
		elseif payload.kind == "invite" then
			for i = #P.invites, 1, -1 do
				if P.invites[i].fromUserId == payload.fromUserId then
					table.remove(P.invites, i)
				end
			end
			table.insert(P.invites, { fromUserId = payload.fromUserId, fromName = tostring(payload.fromName), size = payload.size, at = time() })
			PartyScreen.showInvite()
		end
	end)

	send("RequestParty")
	PartyScreen.P = P
	return PartyScreen
end

return PartyScreen

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextService = game:GetService("TextService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PhaseChanged = Remotes:WaitForChild("PhaseChanged")
local TimerChanged = Remotes:WaitForChild("TimerChanged")
local PromptChosen = Remotes:WaitForChild("PromptChosen")
local ClearBoards = Remotes:WaitForChild("ClearBoards")
local RoundEnded = Remotes:WaitForChild("RoundEnded")
local ShowVotingDrawing = Remotes:WaitForChild("ShowVotingDrawing")
local GetCurrentPrompt = Remotes:WaitForChild("GetCurrentPrompt")

local Settings = require(ReplicatedStorage.GameSettings)
local PromptModule = require(ReplicatedStorage.PromptModule)

local CurrentRound = 0
local CurrentPhase = "Lobby"

local SubmitPrompt = Remotes:WaitForChild("SubmitPrompt")
local PromptChooserSelected = Remotes:WaitForChild("PromptChooserSelected")

local chosenPrompt = nil

local activePlayers = {}

local TotalScores = {}
local RoundScores = {}
local votes = {}
local sabotages = {} 
local PendingTimeAdds = {}
local sabotageImmunity = {}

local drawingParticipants = {}

local timeLeft = 0

local drawingDone = {}
local forceEndDrawing = false

local function BroadcastPhase(phase)
	table.clear(activePlayers)

	for _, player in ipairs(Players:GetPlayers()) do
		activePlayers[player.UserId] = true

		Remotes.SetActivePlayer:FireClient(
			player,
			true
		)
	end
	
	CurrentPhase = phase
	PhaseChanged:FireAllClients(phase)
end

local function GetActivePlayers()
	local result = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if activePlayers[player.UserId] then
			table.insert(result, player)
		end
	end
	return result
end

local function TeleportPlayersToStage(dis, targetPlayer)
	local players

	if targetPlayer then
		players = {targetPlayer}
	else
		players = GetActivePlayers()
	end

	local framePosition = workspace.Frame.Position
	local facingDirection = workspace.Frame.CFrame.LookVector

	local spacing = 5
	local totalWidth = spacing * (#players - 1)
	local startOffset = -totalWidth / 2

	for i, player in ipairs(players) do
		local character = player.Character
		if not character then continue end

		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local offset = workspace.Frame.CFrame.RightVector * (startOffset + (i - 1) * spacing)
		local standPos = framePosition + facingDirection * dis + offset + Vector3.new(0, -20, 0)

		root.CFrame = CFrame.lookAt(standPos, framePosition)
	end
end

local function getFilterResult(text, fromUserId)
	local filterResult
	local success, errorMessage = pcall(function()
		filterResult = TextService:FilterStringAsync(text, fromUserId)
	end)

	if success then
		return filterResult
	else
		warn("Error generating TextFilterResult:", errorMessage)
	end
end

Remotes.FilterText.OnServerInvoke = function(player, text)
	if text == "" then return text end

	local filterResult = getFilterResult(text, player.UserId)
	if not filterResult then return text end

	local success, filteredText = pcall(function()
		return filterResult:GetNonChatStringForBroadcastAsync()
	end)

	return success and filteredText or text
end

local function AssignSabotages()
	table.clear(sabotages)
	local players = GetActivePlayers()
	if #players < 2 then return end

	local shuffled = table.clone(players)
	
	print("Assigning sabotages")
	
	-- keep shuffling until nobody is assigned to themselves
	local valid = false
	while not valid do
		for i = #shuffled, 2, -1 do
			local j = math.random(1, i)
			shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
		end
		valid = true
		for i, player in ipairs(players) do
			if shuffled[i].UserId == player.UserId then
				valid = false
				break
			end
		end
	end

	for i, player in ipairs(players) do
		local target = shuffled[i]
		sabotages[player.UserId] = target.UserId
		Remotes.ShowSabotageScreen:FireClient(player, target.DisplayName)
	end
end

Remotes.TriggerSabotage.OnServerEvent:Connect(function(player, sabotageType)
	local targetId = sabotages[player.UserId]
	if not targetId then return end
	
	if sabotageImmunity[targetId] then
		sabotageImmunity[targetId] = nil
		sabotages[player.UserId] = nil
		return
	end
	
	local target = Players:GetPlayerByUserId(targetId)
	if not target then return end
	Remotes.ApplySabotage:FireClient(target, sabotageType)
	sabotages[player.UserId] = nil
	
	print(player.DisplayName .. " --> " .. target.DisplayName)
end)

local function GetRandomChooser()

	local players = GetActivePlayers()

	if #players == 0 then
		return nil
	end

	return players[math.random(1, #players)]
end

local function ChoosePrompt()

	if not PromptModule.UsePlayerPrompts then
		return PromptModule:GetFallbackPrompt()
	end

	local chooser = GetRandomChooser()

	if not chooser then
		return PromptModule:GetFallbackPrompt()
	end

	chosenPrompt = nil

	PromptChooserSelected:FireAllClients(chooser.UserId)
	
	task.wait(7.5)

	ReplicatedStorage.Remotes.ShowPromptUI:FireAllClients(
		chooser.UserId,
		game.PrivateServerId ~= ""
	)
	
	BroadcastPhase("Choosing Prompt")

	local connection

	connection = SubmitPrompt.OnServerEvent:Connect(function(player, prompt)

		if player ~= chooser then
			return
		end

		if typeof(prompt) ~= "string" then
			return
		end

		chosenPrompt = PromptModule:ProcessPrompt(player, prompt)
	end)

	local timeout = 15

	while timeout > 0 do

		if chosenPrompt then
			break
		end
		
		TimerChanged:FireAllClients(timeout)
		
		task.wait(1)
		timeout -= 1
	end
	
	TimerChanged:FireAllClients(0)

	task.wait(0.25)
	
	connection:Disconnect()

	if not chosenPrompt then
		chosenPrompt = PromptModule:GetFallbackPrompt()
	end
	
	PromptChosen:FireAllClients(chosenPrompt)
end

local function RunTimer(length)
	for i = length, 0, -1 do
		TimerChanged:FireAllClients(i)
		task.wait(1)
	end
end

local function StartVotingRound()
	drawingParticipants = {}

	for _, player in ipairs(GetActivePlayers()) do
		drawingParticipants[player.UserId] = true
	end
	
	BroadcastPhase("Voting")
	
	local drawings = {}

	local drawingConnection = Remotes.SubmitDrawing.OnServerEvent:Connect(function(player, data)
		drawings[player.UserId] = data
	end)
	
	task.wait(0.2)

	local expected = 0
	for _ in pairs(drawingParticipants) do
		expected += 1
	end

	local timeout = 5
	while timeout > 0 do
		local count = 0

		for _ in pairs(drawings) do
			count += 1
		end

		if count >= expected then
			break
		end

		task.wait(0.1)
		timeout -= 0.1
	end
	
	table.clear(RoundScores)
	local players = GetActivePlayers()
	
	local voteConnection = Remotes.SubmitVote.OnServerEvent:Connect(function(player, rating)
		if typeof(rating) ~= "number" then
			return
		end

		rating = math.clamp(math.floor(rating), 1, 5)
		
		votes[player.UserId] = rating
	end)
	
	for _, artist in ipairs(players) do
		local userId = artist.UserId
		
		local drawing = drawings[userId]
		if not drawingParticipants[userId] then
			continue
		end
		
		table.clear(votes)
		
		-- tell all clients whose drawing to show
		ShowVotingDrawing:FireAllClients(userId, drawing)
		game.ReplicatedStorage.SendReport:Fire(drawing)

		local timer = 10

		while timer > 0 do

			TimerChanged:FireAllClients(timer)

			task.wait(1)

			timer -= 1
		end
		
		TimerChanged:FireAllClients(0)

		task.wait(0.25)
		
		local total = 0
		local count = 0

		for _, rating in pairs(votes) do

			total += rating
			count += 1
		end

		local average = 0

		if count > 0 then
			average = total / count
		end

		RoundScores[userId] = average

		TotalScores[userId] =
			(TotalScores[userId] or 0) + average
		
		task.wait(2)
	end
	
	voteConnection:Disconnect()
	drawingConnection:Disconnect()
end

function BuildLeaderboard(scoreTable)
	local leaderboard = {}

	for userId, score in pairs(scoreTable) do

		local player = Players:GetPlayerByUserId(userId)

		if player then
			table.insert(leaderboard,{
				Name = player.DisplayName,
				Score = score,
				UserId = userId
			})
		end
	end

	table.sort(leaderboard,function(a,b)
		return a.Score > b.Score
	end)

	return leaderboard
end

local podiums = {
	workspace.Podium.one,
	workspace.Podium.two,
	workspace.Podium.three,
}

local function TeleportToPodiums(leaderboard)
	for place, entry in ipairs(leaderboard) do
		if place > 3 then break end

		local podium = podiums[place]
		local player = Players:GetPlayerByUserId(entry.UserId)
		if not player or not player.Character then continue end

		local root = player.Character:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		root.CFrame = CFrame.new(podium.Position + Vector3.new(0, podium.Size.Y / 2 + 3, 0))
	end
end

local function AwardWins(scoreTable, statName)
	local topScore = -1
	local winner = nil

	for userId, score in pairs(scoreTable) do
		if score > topScore then
			topScore = score
			winner = Players:GetPlayerByUserId(userId)
		end
	end

	if winner then
		local leaderstats = winner:FindFirstChild("leaderstats")
		if leaderstats then
			leaderstats[statName].Value += 1
		end
		
		if statName == "Round Wins" then
			pcall(function()
				game:GetService("BadgeService"):AwardBadgeAsync(
					winner.UserId,
					2019199448157753
				)
			end)
		end
	end
end

Remotes.DrawingDone.OnServerEvent:Connect(function(player)
	if not activePlayers[player.UserId] then return end
	if drawingDone[player.UserId] then return end

	drawingDone[player.UserId] = true

	-- check if everyone is done
	for _, p in ipairs(GetActivePlayers()) do
		if not drawingDone[p.UserId] then
			return
		end
	end

	-- everyone is done → force end drawing early
	forceEndDrawing = true
end)

ReplicatedStorage.AddDrawingTime.Event:Connect(function(amount)
	if CurrentPhase == "Drawing" then
		timeLeft += 30
		ReplicatedStorage.Remotes.TimeAddedAnnouncement:FireAllClients(amount)
	else
		table.insert(PendingTimeAdds, 30)
	end
end)

ReplicatedStorage.GiveSabotageImmunity.Event:Connect(function(userId)
	sabotageImmunity[userId] = true
end)

Remotes.GetCurrentPhase.OnServerInvoke = function(player)
	return CurrentPhase
end

GetCurrentPrompt.OnServerInvoke = function(player)
	return chosenPrompt
end

local function StartRound()
	CurrentRound += 1

	print("Starting Round", CurrentRound)
	workspace.Frame.SurfaceGui.ImageLabel.Image = ""
	
	if CurrentRound > 1 then
		BroadcastPhase("Round ".. CurrentRound .. " Starting!")
		RunTimer(5)
	end
	
	ChoosePrompt()
	
	if CurrentRound > 1 and #GetActivePlayers() > 1 then
		BroadcastPhase("Sabotage")
		AssignSabotages()
		RunTimer(10)
	end
	
	TeleportPlayersToStage(35)
	workspace.BlockF.SurfaceGui.Frame.Visible = true
	BroadcastPhase("Drawing")
	ClearBoards:FireAllClients()
	
	drawingDone = {}
	for _, player in ipairs(GetActivePlayers()) do
		drawingDone[player.UserId] = false
	end
	
	forceEndDrawing = false

	timeLeft = Settings.DrawingTime
	
	for _, playerId in ipairs(PendingTimeAdds) do
		timeLeft += 30
	end

	table.clear(PendingTimeAdds)

	while timeLeft > 0 do
		if forceEndDrawing then
			break
		end

		TimerChanged:FireAllClients(timeLeft)
		task.wait(1)
		timeLeft -= 1
	end

	TimerChanged:FireAllClients(0)
	
	table.clear(sabotages)
	
	TeleportPlayersToStage(35)
	StartVotingRound()
	workspace.Frame.SurfaceGui.ImageLabel.Image = ""
	
	workspace.BlockF.SurfaceGui.Frame.Visible = false
	TeleportPlayersToStage(150)
	BroadcastPhase("Results")
	AwardWins(RoundScores, "Round Wins")
	
	local roundLeaderboard = BuildLeaderboard(RoundScores)
	local overallLeaderboard = BuildLeaderboard(TotalScores)
	
	Remotes.ShowResults:FireAllClients(
		roundLeaderboard,
		overallLeaderboard
	)

	RunTimer(10)
end

local function StartGame()
	CurrentRound = 0 
	
	table.clear(TotalScores)
	table.clear(RoundScores)
	
	for round = 1, Settings.TotalRounds do
		StartRound()
	end
	
	AwardWins(TotalScores, "Total Wins")
	TeleportToPodiums(BuildLeaderboard(TotalScores))
	
	wait(5)

	BroadcastPhase("Lobby")
end

Players.PlayerAdded:Connect(function(player)
	TotalScores[player.UserId] = 0
	
	
	PhaseChanged:FireClient(player, CurrentPhase)
	
	local spectator = (
		CurrentPhase ~= "Lobby"
			and CurrentPhase ~= "Intermission"
			and CurrentPhase ~= "Starting"
	)

	if spectator then
		activePlayers[player.UserId] = false

		Remotes.SetActivePlayer:FireClient(
			player,
			false
		)
		
		if CurrentPhase == "Drawing" and timeLeft > 30 then
			Remotes.OfferMidGameJoin:FireClient(player)
		end
	else
		activePlayers[player.UserId] = true 

		Remotes.SetActivePlayer:FireClient(
			player,
			true
		)
	end
end)

Remotes.AcceptMidGameJoin.OnServerEvent:Connect(function(player)
	if CurrentPhase ~= "Drawing" then return end
	if timeLeft <= 30 then return end -- too late

	activePlayers[player.UserId] = true
	Remotes.SetActivePlayer:FireClient(player, true)

	-- give them a clean canvas
	Remotes.ClearBoards:FireClient(player)
	Remotes.PromptChosen:FireClient(player, chosenPrompt)
	PhaseChanged:FireClient(player, CurrentPhase)
	TeleportPlayersToStage(35, player)
end)

Players.PlayerRemoving:Connect(function(player)

	activePlayers[player.UserId] = nil

	TotalScores[player.UserId] = nil

end)

while true do
	BroadcastPhase("Lobby")

	repeat
		BroadcastPhase("Lobby")
		task.wait(1)
	until #Players:GetPlayers() >= Settings.MinPlayers
	
	BroadcastPhase("Intermission")	
	RunTimer(10)

	BroadcastPhase("Starting")
	RunTimer(5)

	StartGame()
end


local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local DataStore = DataStoreService:GetDataStore("LeaderstatsData01")

local function LoadData(player)
	local success, data = pcall(function()
		return DataStore:GetAsync(player.UserId)
	end)

	local roundWins = 0
	local totalWins = 0

	if success and data then
		roundWins = data.RoundWins or 0
		totalWins = data.TotalWins or 0
	end

	return roundWins, totalWins
end

local function SaveData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local success, err = pcall(function()
		DataStore:SetAsync(player.UserId, {
			RoundWins = leaderstats["Round Wins"].Value,
			TotalWins = leaderstats["Total Wins"].Value,
		})
	end)

	if not success then
		warn("Failed to save data for", player.Name, err)
	end
end

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local roundWins = Instance.new("NumberValue")
	roundWins.Name = "Round Wins"
	roundWins.Parent = leaderstats

	local totalWins = Instance.new("NumberValue")
	totalWins.Name = "Total Wins"
	totalWins.Parent = leaderstats

	local rw, tw = LoadData(player)
	roundWins.Value = rw
	totalWins.Value = tw
end)

Players.PlayerRemoving:Connect(function(player)
	SaveData(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		SaveData(player)
	end
end)

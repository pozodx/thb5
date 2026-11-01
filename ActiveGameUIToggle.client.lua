-- ActiveGameUIToggle.client.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local roundStartedRemote = ReplicatedStorage:WaitForChild("RoundStarted")
local roundEndedRemote = ReplicatedStorage:WaitForChild("RoundEndedForClients")

local screenGui = playerGui:WaitForChild("LobbyUI")
local otherFolder = screenGui:WaitForChild("Other")

local sideButtons = otherFolder:WaitForChild("SideButtons")
local killerChance = otherFolder:WaitForChild("KillerChance")
local objective1 = otherFolder:WaitForChild("Objective1")
local objective2 = otherFolder:WaitForChild("Objective2")

local function setActiveGameState(isActive)
	sideButtons.Visible = not isActive
	killerChance.Visible = not isActive
	objective1.Visible = isActive
	objective2.Visible = isActive
end

roundStartedRemote.OnClientEvent:Connect(function()
	setActiveGameState(true)
end)

roundEndedRemote.OnClientEvent:Connect(function()
	setActiveGameState(false)
end)

setActiveGameState(false)
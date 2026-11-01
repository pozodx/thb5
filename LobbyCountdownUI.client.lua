-- LobbyCountdownUI.client.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lobbyCountdownRemote = ReplicatedStorage:WaitForChild("LobbyCountdownUpdate")

local stageGui = playerGui:WaitForChild("StageUI")
stageGui.Enabled = false
local screenGui = playerGui:WaitForChild("LobbyCountdownGui")
local frame = screenGui:WaitForChild("Frame")
local countdownLabel = frame:WaitForChild("CountdownLabel")

-- The match timer UI, shown once the lobby countdown hits 0
local timerGui = playerGui:WaitForChild("TimerGui")
timerGui.Enabled = false

lobbyCountdownRemote.OnClientEvent:Connect(function(secondsRemaining)
	if secondsRemaining <= 0 then
		screenGui.Enabled = false
		timerGui.Enabled = true
		stageGui.Enabled = true
	else
		screenGui.Enabled = true
		timerGui.Enabled = false
		stageGui.Enabled = false
		countdownLabel.Text = "Starting in: " .. secondsRemaining
	end
end)
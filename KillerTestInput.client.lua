-- KillerTestInput.client.lua
-- TEMPORARY: press K to toggle Killer role.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:WaitForChild("TestKillerToggle")

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		remoteEvent:FireServer()
	end
end)
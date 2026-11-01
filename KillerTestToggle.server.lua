-- KillerTestToggle.server.lua
-- TEMPORARY: press K to toggle yourself as Killer.
-- Delete this once real role assignment exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteEvent = ReplicatedStorage:FindFirstChild("TestKillerToggle")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "TestKillerToggle"
	remoteEvent.Parent = ReplicatedStorage
end

remoteEvent.OnServerEvent:Connect(function(player)
	local isKiller = player:GetAttribute("IsKiller") or false
	player:SetAttribute("IsKiller", not isKiller)
	print(player.Name .. " is now " .. (not isKiller and "the KILLER" or "a survivor"))
end)
-- LobbyService.server.lua
-- 60s countdown loop. When it hits 0: pick a weighted-random killer from
-- everyone currently in the server, reset the round, open the gates.
-- When the match timer expires, roles reset and the countdown restarts.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerStateService = require(ReplicatedStorage.Shared.PlayerStateService)
local StageManager = require(ServerScriptService.Server.StageManager)
local GateService = require(ServerScriptService.Server.GateService)
local EscapeService = require(ServerScriptService.Server.EscapeService) -- starts escape-gate/escape-detection logic

local COUNTDOWN_SECONDS = 10
local DEFAULT_KILLER_CHANCE = 1 -- keep in sync with KillerChanceService.server.lua

local matchTimerScript = ServerScriptService.Server:WaitForChild("MatchTimerService")
local startRoundEvent = matchTimerScript:WaitForChild("MatchTimer_StartRound")
local roundEndedEvent = matchTimerScript:WaitForChild("MatchTimer_RoundEnded")

local KillerSelectionService = require(ServerScriptService.Server.KillerSelectionService)

local lobbyCountdownRemote = ReplicatedStorage:FindFirstChild("LobbyCountdownUpdate")
if not lobbyCountdownRemote then
	lobbyCountdownRemote = Instance.new("RemoteEvent")
	lobbyCountdownRemote.Name = "LobbyCountdownUpdate"
	lobbyCountdownRemote.Parent = ReplicatedStorage
end

local roundStartedRemote = ReplicatedStorage:FindFirstChild("RoundStarted")
if not roundStartedRemote then
	roundStartedRemote = Instance.new("RemoteEvent")
	roundStartedRemote.Name = "RoundStarted"
	roundStartedRemote.Parent = ReplicatedStorage
end

local roundEndedRemote = ReplicatedStorage:FindFirstChild("RoundEndedForClients")
if not roundEndedRemote then
	roundEndedRemote = Instance.new("RemoteEvent")
	roundEndedRemote.Name = "RoundEndedForClients"
	roundEndedRemote.Parent = ReplicatedStorage
end

local function resetPlayerForNewRound(player)
	player:SetAttribute("IsKiller", false)
	PlayerStateService.SetState(player, PlayerStateService.States.Healthy)
end

-- Picks a killer weighted by each player's KillerChance (0-3): a
-- player with KillerChance=3 is 3x as likely to be picked as one with
-- 1, and KillerChance=0 excludes them entirely. If EVERYONE has set
-- themselves to 0 (empty pool), falls back to uniform random among
-- everyone anyway, so a round can still start.
local function pickWeightedKiller(players)
	local pool = {}
	for _, player in ipairs(players) do
		local chance = player:GetAttribute("KillerChance")
		if chance == nil then
			chance = DEFAULT_KILLER_CHANCE
		end
		for _ = 1, chance do
			table.insert(pool, player)
		end
	end

	if #pool == 0 then
		return players[math.random(1, #players)]
	end

	return pool[math.random(1, #pool)]
end

local function startRound()
	local allPlayers = Players:GetPlayers()
	if #allPlayers == 0 then
		print("LobbyService: no players in server, restarting countdown.")
		return false
	end

	for _, player in ipairs(allPlayers) do
		resetPlayerForNewRound(player)
	end

	local killerPlayer = pickWeightedKiller(allPlayers)
	killerPlayer:SetAttribute("IsKiller", true)
	print(killerPlayer.Name .. " is the killer this round.")

	KillerSelectionService.RunSelection(killerPlayer)

	StageManager.ResetRound()
	GateService.ResetForNewRound() -- snap gates closed in case last round's escape gates were left open
	startRoundEvent:Fire()
	roundStartedRemote:FireAllClients()
	GateService.OpenGates()

	return true
end

local function endRound()
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("IsKiller", false)
	end
	roundEndedRemote:FireAllClients()
	print("LobbyService: round ended.")
end

roundEndedEvent.Event:Connect(function()
	endRound()
end)

task.spawn(function()
	while true do
		for remaining = COUNTDOWN_SECONDS, 0, -1 do
			lobbyCountdownRemote:FireAllClients(remaining)
			task.wait(1)
		end

		local started = startRound()
		if started then
			roundEndedEvent.Event:Wait()
		end
	end
end)

print("LobbyService loaded.")
-- GeneratorService.server.lua
-- Custom E-hold system (GeneratorInteract remote) instead of ProximityPrompt.
-- Snaps the player to the nearest side, plays Main/Side generator animation.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)
local StageManager = require(script.Parent.StageManager)

local REPAIR_RATE_PER_SECOND = 5
local REGRESS_RATE_PER_SECOND = 0.75 -- how fast an unattended generator loses progress; tune to taste
local MAX_PROGRESS = 100
local MAX_INTERACT_DISTANCE = 7

local generatorsFolder = Workspace:WaitForChild("Generators")
local generatorData = {}

local activeGeneratorForPlayer = {}

local interactRemote = ReplicatedStorage:FindFirstChild("GeneratorInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "GeneratorInteract"
	interactRemote.Parent = ReplicatedStorage
end

local function findMainPart(generatorModel)
	if generatorModel.PrimaryPart then
		return generatorModel.PrimaryPart
	end
	for _, descendant in ipairs(generatorModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function findNearestSnap(generatorModel, player)
	local snapFolder = generatorModel:FindFirstChild("SnapPoints")
	if not snapFolder then
		return nil
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end

	local nearest, nearestDist = nil, math.huge
	for _, attachment in ipairs(snapFolder:GetChildren()) do
		if attachment:IsA("Attachment") then
			local dist = (attachment.WorldPosition - root.Position).Magnitude
			if dist < nearestDist then
				nearest = attachment
				nearestDist = dist
			end
		end
	end
	return nearest
end

local function getAnimNameForSnap(attachmentName)
	if attachmentName == "Front" or attachmentName == "Back" then
		return "MainGenerator"
	elseif attachmentName == "Left" or attachmentName == "Right" then
		return "SideGenerator"
	end
	return nil
end

local function stopRepairing(generatorModel, player)
	local data = generatorData[generatorModel]
	if data then
		data.repairingPlayers[player] = nil
	end
	ProgressBarService.Hide(player)
	ActionAnimationService.Stop(player)
	if activeGeneratorForPlayer[player] == generatorModel then
		activeGeneratorForPlayer[player] = nil
	end
end

local function setupGenerator(generatorModel)
	generatorData[generatorModel] = {
		progress = 0,
		repairingPlayers = {},
		botRepairers = {}, -- [botId] = true -- bots tracked separately, no PlayerGui/animation calls
		completed = false,
	}
	generatorModel:SetAttribute("Completed", false)
end

interactRemote.OnServerEvent:Connect(function(player, generatorModel, action)
	if not generatorModel or not generatorModel:IsDescendantOf(generatorsFolder) then
		return
	end
	if player:GetAttribute("IsKiller") then
		return
	end
	local data = generatorData[generatorModel]
	if not data or data.completed then
		return
	end
	if not StageManager.IsStageActive("Generators") then
		return
	end

	if action == "start" then
		if activeGeneratorForPlayer[player] then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(generatorModel)
		if not root or not mainPart then
			return
		end
		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return
		end

		local snap = findNearestSnap(generatorModel, player)
		if snap and character then
			character:PivotTo(snap.WorldCFrame)
			local animName = getAnimNameForSnap(snap.Name)
			if animName then
				ActionAnimationService.Play(player, animName)
			end
		end

		data.repairingPlayers[player] = true
		activeGeneratorForPlayer[player] = generatorModel
	elseif action == "stop" then
		stopRepairing(generatorModel, player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	for generatorModel, data in pairs(generatorData) do
		data.repairingPlayers[player] = nil
	end
	activeGeneratorForPlayer[player] = nil
end)

-- === Bot support ===
-- Purely additive: bots aren't real Players, so they can't call the
-- interactRemote above at all (that requires an actual client firing
-- FireServer). This BindableFunction is a parallel entry point bots call
-- directly (same server, no remote needed). None of the logic above is
-- touched -- real players are completely unaffected by this.
local botRepairAction = Instance.new("BindableFunction")
botRepairAction.Name = "BotRepairAction"
botRepairAction.Parent = script

botRepairAction.OnInvoke = function(action, botId, generatorModel, botCharacter)
	local data = generatorData[generatorModel]
	if not data or data.completed then
		return false
	end
	if not StageManager.IsStageActive("Generators") then
		return false
	end

	if action == "start" then
		local root = botCharacter and botCharacter:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(generatorModel)
		if not root or not mainPart then
			return false
		end
		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return false
		end
		data.botRepairers[botId] = true
		return true
	elseif action == "stop" then
		data.botRepairers[botId] = nil
		return true
	end
	return false
end

-- Exposes the SAME internal findMainPart() real players' interactRemote
-- handler already uses successfully every round. Bots call this instead
-- of guessing at PrimaryPart/GetPivot/SnapPoints independently -- those
-- three separate guesses all kept landing on the wrong position, while
-- this exact function is proven correct by real player use.
local getMainPartPosition = Instance.new("BindableFunction")
getMainPartPosition.Name = "GetMainPartPosition"
getMainPartPosition.Parent = script

getMainPartPosition.OnInvoke = function(generatorModel)
	local mainPart = findMainPart(generatorModel)
	if mainPart then
		return mainPart.Position
	end
	return nil
end
-- === End bot support ===

RunService.Heartbeat:Connect(function(deltaTime)
	for generatorModel, data in pairs(generatorData) do
		if not data.completed then
			local repairerCount = 0
			for _ in pairs(data.repairingPlayers) do
				repairerCount += 1
			end
			for _ in pairs(data.botRepairers) do
				repairerCount += 1
			end

			if repairerCount > 0 then
				data.progress = math.min(MAX_PROGRESS, data.progress + (REPAIR_RATE_PER_SECOND * repairerCount * deltaTime))
                generatorModel:SetAttribute("Progress", data.progress)
				for player in pairs(data.repairingPlayers) do
					ProgressBarService.Update(player, "Repairing", data.progress)
				end

				if data.progress >= MAX_PROGRESS then
					data.completed = true
					generatorModel:SetAttribute("Completed", true)
					local mainPart = findMainPart(generatorModel)
					if mainPart then
						mainPart.Color = Color3.fromRGB(0, 255, 0)
					end
					for player in pairs(data.repairingPlayers) do
						stopRepairing(generatorModel, player)
					end
					data.botRepairers = {}
					print(generatorModel.Name .. " has been repaired!")
					StageManager.NotifyObjectiveCompleted("Generators")
				end
			elseif data.progress > 0 then
				data.progress = math.max(0, data.progress - (REGRESS_RATE_PER_SECOND * deltaTime))
				generatorModel:SetAttribute("Progress", data.progress)
			end
		end
	end
end)

local REQUIRED_GENERATOR_COUNT = 3

local totalGenerators = 0
for _, generatorModel in ipairs(generatorsFolder:GetChildren()) do
	if generatorModel:IsA("Model") then
		setupGenerator(generatorModel)
		totalGenerators += 1
	end
end

if totalGenerators < REQUIRED_GENERATOR_COUNT then
	warn("GeneratorService: only " .. totalGenerators .. " generator(s) placed in Workspace.Generators, but " .. REQUIRED_GENERATOR_COUNT .. " are required -- add " .. (REQUIRED_GENERATOR_COUNT - totalGenerators) .. " more or the Generators stage can NEVER be completed this round.")
end

StageManager.SetRequiredCount("Generators", REQUIRED_GENERATOR_COUNT)

print("GeneratorService loaded (custom prompt). Tracking " .. totalGenerators .. " generator(s), " .. REQUIRED_GENERATOR_COUNT .. " required.")
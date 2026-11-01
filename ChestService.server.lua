-- ChestService.server.lua
-- Custom E-hold system (no ProximityPrompt, no floating label).
-- Fuse chests: hold E -> ChestStruggle loops the whole time -> at 100%,
-- chest fades out and player is instantly holding a fuse (no separate
-- open animation, no fuse spawned on the ground).
-- Item chests: same loop, but spawns a Flashlight/Toolbox on the ground.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressBarService = require(ReplicatedStorage.Shared.ProgressBarService)
local ActionAnimationService = require(ReplicatedStorage.Shared.ActionAnimationService)
local FuseService = require(script.Parent.FuseService)

local SEARCH_RATE_PER_SECOND = 8
local MAX_INTERACT_DISTANCE = 8
local FADE_OUT_TIME = 0.6

local chestsFolder = Workspace:WaitForChild("Chests")
local templatesFolder = ReplicatedStorage:WaitForChild("Templates")

local chestData = {} -- [chestModel] = { progress = 0, completed = false, searcher = nil }
local activeSearch = {} -- [player] = { chestModel, phase = "searching" }

local interactRemote = ReplicatedStorage:FindFirstChild("ChestInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "ChestInteract"
	interactRemote.Parent = ReplicatedStorage
end

local cancelRemote = ReplicatedStorage:FindFirstChild("CancelTimedAction")
if not cancelRemote then
	cancelRemote = Instance.new("RemoteEvent")
	cancelRemote.Name = "CancelTimedAction"
	cancelRemote.Parent = ReplicatedStorage
end

local function findMainPart(chestModel)
	for _, descendant in ipairs(chestModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function stopSearch(player)
	local search = activeSearch[player]
	if not search then
		return
	end
	local data = chestData[search.chestModel]
	if data and data.searcher == player then
		data.searcher = nil
	end
	ActionAnimationService.Stop(player)
	ProgressBarService.Hide(player)
	activeSearch[player] = nil
end

local function fadeOutChest(chestModel)
	for _, part in ipairs(chestModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			local tween = TweenService:Create(
				part,
				TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			)
			tween:Play()
		end
	end
	task.delay(FADE_OUT_TIME, function()
		if chestModel and chestModel.Parent then
			chestModel:Destroy()
		end
	end)
end

local function giveFuseDirectly(player)
	if FuseService.IsHoldingFuse(player) then
		return -- already holding one
	end

	local template = templatesFolder:FindFirstChild("FuseTemplate")
	if not template then
		warn("No FuseTemplate found in ReplicatedStorage.Templates")
		return
	end

	local newFuse = template:Clone()
	newFuse.Parent = Workspace.Fuses
	FuseService.PickUp(player, newFuse)
	print(player.Name .. " received a fuse directly from a chest")
end

local function spawnItemReward(chestModel, spawnPosition)
	local itemName = (math.random(2) == 1) and "FlashlightTemplate" or "ToolboxTemplate"
	local template = templatesFolder:FindFirstChild(itemName)
	if not template then
		warn("No " .. itemName .. " found in ReplicatedStorage.Templates")
		return
	end
	local newItem = template:Clone()
	newItem.Parent = Workspace

	local templateCFrame = template:GetPivot()
	local rotationOnly = templateCFrame - templateCFrame.Position
	local finalCFrame = CFrame.new(spawnPosition) * rotationOnly

	if newItem:IsA("Model") then
		newItem:PivotTo(finalCFrame)
	elseif newItem:IsA("BasePart") then
		newItem.CFrame = finalCFrame
	end
	print(chestModel.Name .. " spawned a " .. itemName)
end

local function beginOpenPhase(player, chestModel)
	local search = activeSearch[player]
	if not search or search.chestModel ~= chestModel then
		return
	end

	local data = chestData[chestModel]
	if not data or data.completed then
		return
	end
	data.completed = true
	chestModel:SetAttribute("Completed", true)

	local chestType = chestModel:GetAttribute("ChestType")
	local mainPart = findMainPart(chestModel)
	local spawnPosition = mainPart and mainPart.Position or chestModel:GetPivot().Position

	ProgressBarService.Hide(player)
	ActionAnimationService.Stop(player)
	fadeOutChest(chestModel)

	if chestType == "Fuse" then
		giveFuseDirectly(player)
	elseif chestType == "Item" then
		spawnItemReward(chestModel, spawnPosition)
	else
		warn("Unknown or missing ChestType on " .. chestModel.Name .. ": " .. tostring(chestType))
	end

	activeSearch[player] = nil
end

local function setupChest(chestModel)
	chestData[chestModel] = { progress = 0, completed = false, searcher = nil }
	chestModel:SetAttribute("Completed", false)
end

interactRemote.OnServerEvent:Connect(function(player, chestModel, action)
	if not chestModel or not chestModel:IsDescendantOf(chestsFolder) then
		return
	end
	if player:GetAttribute("IsKiller") then
		return
	end
	local data = chestData[chestModel]
	if not data or data.completed then
		return
	end

	if action == "start" then
		if activeSearch[player] then
			return
		end
		if data.searcher and data.searcher ~= player then
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local mainPart = findMainPart(chestModel)
		if not root or not mainPart then
			return
		end
		if (root.Position - mainPart.Position).Magnitude > MAX_INTERACT_DISTANCE then
			return
		end

		local snapFolder = chestModel:FindFirstChild("SnapPoints")
		local snap = snapFolder and snapFolder:FindFirstChild("Front")
		if snap and character then
			character:PivotTo(snap.WorldCFrame)
		end

		data.searcher = player
		activeSearch[player] = { chestModel = chestModel, phase = "searching" }

		ActionAnimationService.Play(player, "ChestStruggle")
	elseif action == "stop" then
		stopSearch(player)
	end
end)

cancelRemote.OnServerEvent:Connect(function(player)
	if activeSearch[player] then
		stopSearch(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if activeSearch[player] then
		stopSearch(player)
	end
end)

RunService.Heartbeat:Connect(function(deltaTime)
	for player, search in pairs(activeSearch) do
		if search.phase == "searching" then
			local chestModel = search.chestModel
			local data = chestData[chestModel]
			data.progress = math.min(100, data.progress + SEARCH_RATE_PER_SECOND * deltaTime)

			ProgressBarService.Update(player, "Searching", data.progress)

			if data.progress >= 100 then
				beginOpenPhase(player, chestModel)
			end
		end
	end
end)

local totalChests = 0
for _, chestModel in ipairs(chestsFolder:GetChildren()) do
	if chestModel:IsA("Model") then
		setupChest(chestModel)
		totalChests += 1
	end
end

print("ChestService loaded. Tracking " .. totalChests .. " chest(s).")
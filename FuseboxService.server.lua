-- FuseboxService.server.lua
-- Door: real ProximityPrompt, rotates open on its HingeAttachment.
-- Interior: custom E-press system (FuseboxInteract remote), inserts fuses.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FuseService = require(script.Parent.FuseService)
local StageManager = require(script.Parent.StageManager)

local fuseBoxesFolder = Workspace:WaitForChild("FuseBoxes")

local REQUIRED_FUSES = 4
local MAX_INTERACT_DISTANCE = 8
local DOOR_OPEN_ANGLE = 100
local DOOR_OPEN_TIME = 0.6

local interactRemote = ReplicatedStorage:FindFirstChild("FuseboxInteract")
if not interactRemote then
	interactRemote = Instance.new("RemoteEvent")
	interactRemote.Name = "FuseboxInteract"
	interactRemote.Parent = ReplicatedStorage
end

-- fuseboxData[fuseboxModel] = { insertedCount = 0, opened = false }
local fuseboxData = {}

local function findPrompt(instance)
	if instance:IsA("BasePart") then
		local direct = instance:FindFirstChildOfClass("ProximityPrompt")
		if direct then
			return direct
		end
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			return descendant
		end
	end
	return nil
end

-- Rotates a door part open around its HingeAttachment
local function openDoor(doorPart)
	local hinge = doorPart:FindFirstChild("HingeAttachment")
	if not hinge then
		warn(doorPart.Name .. " has no HingeAttachment, skipping door animation.")
		return
	end

	local hingeCFrame0 = hinge.WorldCFrame
	local offset = hingeCFrame0:ToObjectSpace(doorPart.CFrame)

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.min(elapsed / DOOR_OPEN_TIME, 1)
		local currentAngle = DOOR_OPEN_ANGLE * alpha

		doorPart.CFrame = hingeCFrame0 * CFrame.Angles(0, math.rad(currentAngle), 0) * offset

		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

local function setupFusebox(fuseboxModel)
	fuseboxData[fuseboxModel] = { insertedCount = 0, opened = false }
	fuseboxModel:SetAttribute("Opened", false)

	local doorPart = fuseboxModel:FindFirstChild("FuseboxDoor")
	if not doorPart then
		warn(fuseboxModel.Name .. " has no FuseboxDoor")
		return
	end

	local doorPrompt = findPrompt(doorPart)
	if not doorPrompt then
		warn(fuseboxModel.Name .. "'s FuseboxDoor has no ProximityPrompt")
		return
	end

	doorPrompt.Triggered:Connect(function(player)
		local data = fuseboxData[fuseboxModel]
		if not data or data.opened then
			return
		end
		if player:GetAttribute("IsKiller") then
			return
		end
		if not StageManager.IsStageActive("Fuseboxes") then
			return
		end

		data.opened = true
		fuseboxModel:SetAttribute("Opened", true)
		doorPrompt.Enabled = false
		openDoor(doorPart)
		print(fuseboxModel.Name .. " opened")
	end)
end

interactRemote.OnServerEvent:Connect(function(player, fuseboxModel)
	print("[Fusebox] Interior interact received for:", fuseboxModel, "from", player.Name)
	if not fuseboxModel or not fuseboxModel:IsDescendantOf(fuseBoxesFolder) then
		print("  Rejected: invalid fusebox")
		return
	end
	if player:GetAttribute("IsKiller") then
		return
	end
	local data = fuseboxData[fuseboxModel]
	if not data or not data.opened then
		print("  Rejected: not opened yet. data.opened =", data and data.opened)
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local interior = fuseboxModel:FindFirstChild("Interior")
	if not root or not interior then
		print("  Rejected: missing root or interior")
		return
	end
	local distance = (root.Position - interior.Position).Magnitude
	print("  Distance to interior:", distance)
	if distance > MAX_INTERACT_DISTANCE then
		print("  Rejected: too far")
		return
	end

	print("  IsHoldingFuse:", FuseService.IsHoldingFuse(player), "insertedCount:", data.insertedCount)
	if data.insertedCount >= REQUIRED_FUSES then
		print("  Rejected: already full")
		return
	end
	if not FuseService.IsHoldingFuse(player) then
		print("  Rejected: not holding a fuse")
		return
	end

	local fuseInstance = FuseService.GetHeldFuseModel(player)
	FuseService.ClearHeldFuse(player)
	if fuseInstance then
		fuseInstance:Destroy()
	end

	data.insertedCount += 1
	print(fuseboxModel.Name .. ": " .. data.insertedCount .. "/" .. REQUIRED_FUSES .. " fuses inserted")

	local compartmentsFolder = interior:FindFirstChild("Compartments") or fuseboxModel:FindFirstChild("Compartments")
	if compartmentsFolder then
		local slot = compartmentsFolder:FindFirstChild("Fuse" .. data.insertedCount)
		if slot and slot:IsA("BasePart") then
			slot.Material = Enum.Material.Neon
			slot.Transparency = 0
		end
	end

	if data.insertedCount >= REQUIRED_FUSES then
		print(fuseboxModel.Name .. " fully powered!")
		StageManager.NotifyObjectiveCompleted("Fuseboxes")
	end
end)

-- === Bot support ===
-- Real players open the door via a ProximityPrompt, which is a client-
-- driven interaction bots can't trigger (no client at all). This bridge
-- runs the exact same opening logic directly.
local botOpenDoor = Instance.new("BindableFunction")
botOpenDoor.Name = "BotOpenDoor"
botOpenDoor.Parent = script

botOpenDoor.OnInvoke = function(fuseboxModel)
	local data = fuseboxData[fuseboxModel]
	if not data or data.opened then
		return false
	end
	if not StageManager.IsStageActive("Fuseboxes") then
		return false
	end

	local doorPart = fuseboxModel:FindFirstChild("FuseboxDoor")
	if not doorPart then
		return false
	end
	local doorPrompt = findPrompt(doorPart)

	data.opened = true
	fuseboxModel:SetAttribute("Opened", true)
	if doorPrompt then
		doorPrompt.Enabled = false
	end
	openDoor(doorPart)
	print(fuseboxModel.Name .. " opened (by bot)")
	return true
end

-- Mirrors the interior interact handler above, but takes the fuse
-- instance directly as a parameter instead of reading it from
-- FuseService's player-keyed state (bots aren't tracked there).
local botInsertFuse = Instance.new("BindableFunction")
botInsertFuse.Name = "BotInsertFuse"
botInsertFuse.Parent = script

botInsertFuse.OnInvoke = function(fuseboxModel, botCharacter, fuseInstance)
	local data = fuseboxData[fuseboxModel]
	if not data or not data.opened then
		return false
	end
	if data.insertedCount >= REQUIRED_FUSES then
		return false
	end

	local root = botCharacter and botCharacter:FindFirstChild("HumanoidRootPart")
	local interior = fuseboxModel:FindFirstChild("Interior")
	if not root or not interior then
		return false
	end
	if (root.Position - interior.Position).Magnitude > MAX_INTERACT_DISTANCE then
		return false
	end

	if fuseInstance then
		fuseInstance:Destroy()
	end

	data.insertedCount += 1
	print(fuseboxModel.Name .. ": " .. data.insertedCount .. "/" .. REQUIRED_FUSES .. " fuses inserted (by bot)")

	local compartmentsFolder = interior:FindFirstChild("Compartments") or fuseboxModel:FindFirstChild("Compartments")
	if compartmentsFolder then
		local slot = compartmentsFolder:FindFirstChild("Fuse" .. data.insertedCount)
		if slot and slot:IsA("BasePart") then
			slot.Material = Enum.Material.Neon
			slot.Transparency = 0
		end
	end

	if data.insertedCount >= REQUIRED_FUSES then
		print(fuseboxModel.Name .. " fully powered! (by bot)")
		StageManager.NotifyObjectiveCompleted("Fuseboxes")
	end

	return true
end

local isFuseboxFull = Instance.new("BindableFunction")
isFuseboxFull.Name = "IsFuseboxFull"
isFuseboxFull.Parent = script

isFuseboxFull.OnInvoke = function(fuseboxModel)
	local data = fuseboxData[fuseboxModel]
	if not data then
		return true -- unknown fusebox, treat as unavailable rather than erroring
	end
	return data.insertedCount >= REQUIRED_FUSES
end
-- === End bot support ===

local REQUIRED_FUSEBOX_COUNT = 3

local totalFuseboxes = 0
for _, fuseboxModel in ipairs(fuseBoxesFolder:GetChildren()) do
	if fuseboxModel:IsA("Model") then
		setupFusebox(fuseboxModel)
		totalFuseboxes += 1
	end
end

if totalFuseboxes < REQUIRED_FUSEBOX_COUNT then
	warn("FuseboxService: only " .. totalFuseboxes .. " fusebox(es) placed in Workspace.FuseBoxes, but " .. REQUIRED_FUSEBOX_COUNT .. " are required -- add " .. (REQUIRED_FUSEBOX_COUNT - totalFuseboxes) .. " more or the Fuseboxes stage can NEVER be completed this round.")
end

StageManager.SetRequiredCount("Fuseboxes", REQUIRED_FUSEBOX_COUNT)

print("FuseboxService loaded. Tracking " .. totalFuseboxes .. " fusebox(es), " .. REQUIRED_FUSEBOX_COUNT .. " required.")
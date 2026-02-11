-- src/server/services/RoomManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PhysicsService = game:GetService("PhysicsService")
local BadgeService = game:GetService("BadgeService")

local GhostRecorder = require(ServerScriptService.Server.services.GhostRecorder)
local GhostPlayback = require(ServerScriptService.Server.services.GhostPlayback)
local Types = require(ReplicatedStorage.Shared.Types)

local BADGE_IDS = {
	SitOnChair = 0,
	NoJump = 0,
	IgnoredKnife = 0,
	GameClear = 0,
}

local ROOM_TEMPLATE = ServerStorage:WaitForChild("RoomTemplate")
local GHOST_TEMPLATE = ReplicatedStorage:WaitForChild("Ghost")
local FOLLOWER_A = ServerStorage:WaitForChild("Follower_A")
local FOLLOWER_B = ServerStorage:WaitForChild("Follower_B")

local ANOMALY_CHANCE = 0.6

local EVENT_CATALOG = {
	{ Name = "None", Weight = 30 },
	{ Name = "Follower", Weight = 20 },
	{ Name = "Victim", Weight = 10 },
	{ Name = "KnifeRoom", Weight = 15 },
	{ Name = "BloodText", Weight = 10 },
	{ Name = "MemoRoom", Weight = 10 },
	{ Name = "KillerRoom", Weight = 15 },
}

local ANOMALY_CATALOG = {
	{ Name = "GhostAttack" },
	{ Name = "GhostWobble" },
	{ Name = "GhostBounce" },
	{ Name = "GhostWallRun" },
	{ Name = "GhostReverse" },
}

local GHOST_COLOR = Color3.fromRGB(100, 200, 255)
local GHOST_MATERIAL = Enum.Material.Neon
local GHOST_GROUP = "GhostGroup"

task.spawn(function()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(GHOST_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, "Default", false)
		PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, GHOST_GROUP, false)
	end)
end)

local remoteEvent = ReplicatedStorage:FindFirstChild("OnFloorChanged")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "OnFloorChanged"
	remoteEvent.Parent = ReplicatedStorage
end

local jumpscareEvent = ReplicatedStorage:FindFirstChild("OnJumpscare")
if not jumpscareEvent then
	jumpscareEvent = Instance.new("RemoteEvent")
	jumpscareEvent.Name = "OnJumpscare"
	jumpscareEvent.Parent = ReplicatedStorage
end

local requestStartEvent = ReplicatedStorage:FindFirstChild("RequestStartGame")
if not requestStartEvent then
	requestStartEvent = Instance.new("RemoteEvent")
	requestStartEvent.Name = "RequestStartGame"
	requestStartEvent.Parent = ReplicatedStorage
end

local gameClearEvent = ReplicatedStorage:FindFirstChild("OnGameClear")
if not gameClearEvent then
	gameClearEvent = Instance.new("RemoteEvent")
	gameClearEvent.Name = "OnGameClear"
	gameClearEvent.Parent = ReplicatedStorage
end

math.randomseed(os.time())

local RoomManager = {}

type PlayerState = {
	CurrentRoom: Model?,
	Level: number,
	LastGhostData: { Types.FrameData }?,
	ActiveAnomaly: string?,
	AbandonedNPC: string?,
	CurrentRoomEvent: string?,
	HasJumpedThisFloor: boolean,
}

local playerStates: { [Player]: PlayerState } = {}

local function awardBadge(player: Player, badgeId: number, badgeName: string)
	if badgeId == 0 then
		print("🏆 [テスト環境] バッジ獲得条件達成: " .. badgeName)
		return
	end
	task.spawn(function()
		pcall(function()
			if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
				BadgeService:AwardBadge(player.UserId, badgeId)
				print("🏆 本番バッジ獲得: " .. badgeName)
			end
		end)
	end)
end

local function getRandomEvent()
	local totalWeight = 0
	for _, event in ipairs(EVENT_CATALOG) do
		totalWeight += event.Weight
	end
	local randomValue = math.random() * totalWeight
	local currentWeight = 0
	for _, event in ipairs(EVENT_CATALOG) do
		currentWeight += event.Weight
		if randomValue <= currentWeight then
			return event.Name
		end
	end
	return "None"
end

local function createTamperedData(originalFrames: { Types.FrameData }, anomalyName: string): { Types.FrameData }
	local newFrames = {}
	for _, frame in ipairs(originalFrames) do
		table.insert(newFrames, table.clone(frame))
	end
	local totalFrames = #newFrames
	if totalFrames < 20 then
		return newFrames
	end

	if anomalyName == "GhostAttack" then
		local victim = nil
		for _, v in ipairs(workspace:GetChildren()) do
			if v.Name:match("Room_") and v:FindFirstChild("Victim") then
				victim = v.Victim
				break
			end
		end
		if victim then
			local entrance = victim.Parent:FindFirstChild("Entrance")
			if entrance then
				local victimRoot = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
				if victimRoot then
					local victimRelPos = entrance.CFrame:PointToObjectSpace(victimRoot.Position)
					local closestDist, closestIndex = 9999, 1
					for i, frame in ipairs(newFrames) do
						local dist = (frame.RelCFrame.Position - victimRelPos).Magnitude
						if dist < closestDist then
							closestDist, closestIndex = dist, i
						end
					end
					local attackRange = 20
					for i = math.max(1, closestIndex - attackRange), math.min(totalFrames, closestIndex + attackRange) do
						local frame = newFrames[i]
						local targetPos = victimRelPos + (frame.RelCFrame.Position - victimRelPos).Unit * 2
						local alpha = 1.0 - (math.abs(i - closestIndex) / attackRange)
						frame.RelCFrame = frame.RelCFrame:Lerp(CFrame.new(targetPos) * frame.RelCFrame.Rotation, alpha)
						frame.EquippedTool = "Knife"
						if math.abs(i - closestIndex) < 10 then
							frame.IsAttacking = true
							local lookAt = CFrame.lookAt(frame.RelCFrame.Position, victimRelPos)
							frame.RelCFrame = frame.RelCFrame:Lerp(entrance.CFrame:ToObjectSpace(lookAt), 0.5)
						end
					end
				end
			end
		end
	elseif anomalyName == "GhostWobble" then
		for _, frame in ipairs(newFrames) do
			local wobble = math.sin(frame.Time * 5) * 2.5
			frame.RelCFrame = frame.RelCFrame * CFrame.new(wobble, 0, 0)
		end
	elseif anomalyName == "GhostBounce" then
		for _, frame in ipairs(newFrames) do
			local bounce = math.abs(math.sin(frame.Time * 20)) * 2.5
			frame.RelCFrame = frame.RelCFrame * CFrame.new(0, bounce, 0)
		end
	elseif anomalyName == "GhostWallRun" then
		local startIndex = math.floor(totalFrames * 0.3)
		for i = startIndex, totalFrames do
			local frame = newFrames[i]
			local progress = (i - startIndex) * 0.4
			frame.RelCFrame = frame.RelCFrame * CFrame.new(progress, 0, 0) * CFrame.Angles(0, -math.rad(60), 0)
		end
	elseif anomalyName == "GhostReverse" then
		local reversed = {}
		for i = 1, totalFrames do
			local targetFrame = originalFrames[totalFrames - i + 1]
			local f = table.clone(newFrames[i])
			f.RelCFrame = targetFrame.RelCFrame
			f.AnimId = targetFrame.AnimId
			f.EquippedTool = targetFrame.EquippedTool
			table.insert(reversed, f)
		end
		return reversed
	end
	return newFrames
end

local function spawnRoom(player: Player, isReset: boolean)
	local state = playerStates[player]
	if not state then
		return
	end

	if state.CurrentRoom then
		state.CurrentRoom:Destroy()
	end

	local currentFollowerName = nil
	local character = player.Character
	if character then
		currentFollowerName = character:GetAttribute("FollowerName")
		character:SetAttribute("FollowerName", nil)
		character:SetAttribute("HasFollower", nil)
	end

	local roomEvent = "None"
	if state.Level == 1 then
		roomEvent = "None"
	elseif currentFollowerName then
		roomEvent = "Follower"
	else
		roomEvent = getRandomEvent()
	end

	state.CurrentRoomEvent = roomEvent
	state.HasJumpedThisFloor = false

	state.ActiveAnomaly = nil
	if not isReset and state.Level > 1 and math.random() < ANOMALY_CHANCE then
		local validAnomalies = {}
		for _, anomaly in ipairs(ANOMALY_CATALOG) do
			if anomaly.Name == "GhostAttack" then
				if roomEvent == "Victim" then
					table.insert(validAnomalies, anomaly)
				end
			else
				table.insert(validAnomalies, anomaly)
			end
		end

		if #validAnomalies > 0 then
			local anomaly = validAnomalies[math.random(1, #validAnomalies)]
			state.ActiveAnomaly = anomaly.Name
		end
	end

	print("\n========================================")
	print("🏢 [Floor: " .. string.format("%02d", state.Level) .. "]")
	print("🎭 Event  : " .. state.CurrentRoomEvent)
	if state.ActiveAnomaly then
		print("⚠️ Anomaly: YES (" .. state.ActiveAnomaly .. ")")
		print("👉 正解ルート: 後ろの扉 (Entrance) に引き返す")
	else
		print("✅ Anomaly: NO (正常な部屋)")
		print("👉 正解ルート: 奥の扉 (Exit) に進む")
	end
	print("========================================\n")

	local newRoom = ROOM_TEMPLATE:Clone()
	newRoom.Name = "Room_" .. player.Name
	newRoom.Parent = workspace
	newRoom:PivotTo(CFrame.new(0, 100, 0))
	state.CurrentRoom = newRoom

	local floor = newRoom:WaitForChild("Floor", 5)
	local floorY = floor and (floor.Position.Y + (floor.Size.Y / 2)) or newRoom:GetPivot().Position.Y
	local entrance = newRoom:WaitForChild("Entrance") :: BasePart

	local defaultVictim = newRoom:FindFirstChild("Victim")
	if defaultVictim then
		defaultVictim:Destroy()
	end

	local chairModel = newRoom:FindFirstChild("Chair", true)
	local seatPart = nil

	if chairModel and chairModel:IsA("Seat") then
		seatPart = chairModel
	elseif chairModel then
		seatPart = chairModel:FindFirstChildWhichIsA("Seat", true)
	end

	if not seatPart then
		seatPart = newRoom:FindFirstChildWhichIsA("Seat", true)
	end

	if seatPart then
		seatPart:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = seatPart.Occupant
			if occupant and occupant.Parent == character then
				awardBadge(player, BADGE_IDS.SitOnChair, "一時の休息（椅子に座る）")
			end
		end)
	end

	if roomEvent == "Victim" then
		local victimModel = FOLLOWER_A:Clone()
		if victimModel then
			victimModel.Name = "Victim"
			victimModel.Parent = newRoom
			victimModel:PivotTo(CFrame.new(newRoom:GetPivot().Position.X, floorY + 3, newRoom:GetPivot().Position.Z))
			victimModel:WaitForChild("Humanoid").Health = 100
			victimModel:WaitForChild("HumanoidRootPart").Anchored = false
			local aiScript = victimModel:FindFirstChild("FollowerAI")
			if aiScript then
				aiScript:Destroy()
			end
		end
	elseif roomEvent == "KnifeRoom" then
		local roomPos = newRoom:GetPivot().Position
		local knifePart = Instance.new("Part")
		knifePart.Name = "DroppedKnife"
		knifePart.Size = Vector3.new(0.5, 0.2, 1.5)
		knifePart.Color = Color3.fromRGB(180, 180, 180)
		knifePart.Material = Enum.Material.Metal
		knifePart.CFrame = CFrame.new(roomPos.X, floorY + 0.1, roomPos.Z)
			* CFrame.Angles(0, math.random() * math.pi, math.pi / 2)
		knifePart.Anchored = true
		knifePart.CanCollide = false
		knifePart.Parent = newRoom

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "拾う"
		prompt.ObjectText = "ナイフ"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.Parent = knifePart

		prompt.Triggered:Connect(function(triggerPlayer)
			local char = triggerPlayer.Character
			if not char then
				return
			end
			if triggerPlayer.Backpack:FindFirstChild("Knife") or char:FindFirstChild("Knife") then
				prompt:Destroy()
				return
			end
			local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
			if toolsFolder then
				local sourceKnife = toolsFolder:FindFirstChild("Knife")
				if sourceKnife then
					local newKnife = sourceKnife:Clone()
					newKnife.Parent = triggerPlayer.Backpack
					knifePart:Destroy()
				end
			end
		end)
	elseif roomEvent == "BloodText" then
		if floor then
			local phrases = {
				"逃 げ ろ",
				"振 り 向 く な",
				"こ こ は 地 獄 だ",
				"信 じ る な",
				"永 遠 に 続 く",
			}
			local surfaceGui = Instance.new("SurfaceGui")
			surfaceGui.Face = Enum.NormalId.Top
			surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surfaceGui.PixelsPerStud = 30
			surfaceGui.Parent = floor

			local textLabel = Instance.new("TextLabel")
			textLabel.Size = UDim2.new(1, 0, 1, 0)
			textLabel.BackgroundTransparency = 1
			textLabel.Font = Enum.Font.Creepster
			textLabel.Text = phrases[math.random(1, #phrases)]
			textLabel.TextColor3 = Color3.fromRGB(150, 0, 0)
			textLabel.TextScaled = true
			textLabel.TextTransparency = 0.3
			textLabel.Rotation = math.random(-10, 10)
			textLabel.Parent = surfaceGui
		end
	elseif roomEvent == "MemoRoom" then
		local roomPos = newRoom:GetPivot().Position
		local paper = Instance.new("Part")
		paper.Name = "MemoPaper"
		paper.Size = Vector3.new(1.2, 0.05, 1.5)
		paper.Color = Color3.fromRGB(230, 220, 200)
		paper.Material = Enum.Material.Fabric
		paper.CFrame = CFrame.new(roomPos.X + math.random(-3, 3), floorY + 0.05, roomPos.Z + math.random(-3, 3))
			* CFrame.Angles(0, math.random() * math.pi, 0)
		paper.Anchored = true
		paper.CanCollide = false
		paper.Parent = newRoom

		local memos = {
			"あいつらは……\n本物じゃない。\n絶対に連れて行くな。",
			"何度も同じ部屋を\n通っている気がする。\nもう疲れた……",
			"ゴーストの正体が\n分かった。\nあれは私自身だ。",
			"ナイフを見つけたら\n迷わず拾え。\nそして……",
		}
		local memoText = memos[math.random(1, #memos)]

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "読む"
		prompt.ObjectText = "古びたメモ"
		prompt.HoldDuration = 0.2
		prompt.MaxActivationDistance = 10
		prompt.Parent = paper

		prompt.Triggered:Connect(function(triggerPlayer)
			local pg = triggerPlayer:FindFirstChild("PlayerGui")
			if not pg then
				return
			end
			local oldUi = pg:FindFirstChild("MemoUI")
			if oldUi then
				oldUi:Destroy()
			end

			local sg = Instance.new("ScreenGui")
			sg.Name = "MemoUI"
			sg.ResetOnSpawn = false
			sg.Parent = pg

			local bg = Instance.new("Frame")
			bg.Size = UDim2.new(1, 0, 1, 0)
			bg.BackgroundColor3 = Color3.new(0, 0, 0)
			bg.BackgroundTransparency = 0.5
			bg.Parent = sg

			local paperBg = Instance.new("Frame")
			paperBg.AnchorPoint = Vector2.new(0.5, 0.5)
			paperBg.Position = UDim2.new(0.5, 0, 0.5, 0)
			paperBg.Size = UDim2.new(0.6, 0, 0.5, 0)
			paperBg.BackgroundColor3 = Color3.fromRGB(240, 230, 210)
			paperBg.Parent = bg

			local constraint = Instance.new("UISizeConstraint")
			constraint.MaxSize = Vector2.new(600, 500)
			constraint.Parent = paperBg

			local textLabel = Instance.new("TextLabel")
			textLabel.Size = UDim2.new(0.9, 0, 0.7, 0)
			textLabel.Position = UDim2.new(0.05, 0, 0.05, 0)
			textLabel.BackgroundTransparency = 1
			textLabel.Text = memoText
			textLabel.TextColor3 = Color3.new(0.1, 0.1, 0.1)
			textLabel.TextScaled = true
			textLabel.Font = Enum.Font.Kalam
			textLabel.Parent = paperBg

			local closeBtn = Instance.new("TextButton")
			closeBtn.AnchorPoint = Vector2.new(0.5, 1)
			closeBtn.Position = UDim2.new(0.5, 0, 0.95, 0)
			closeBtn.Size = UDim2.new(0.4, 0, 0.15, 0)
			closeBtn.Text = "閉じる"
			closeBtn.Font = Enum.Font.GothamBold
			closeBtn.TextScaled = true
			closeBtn.Modal = true
			closeBtn.Parent = paperBg

			closeBtn.MouseButton1Click:Connect(function()
				sg:Destroy()
			end)
		end)
	elseif roomEvent == "KillerRoom" then
		local roomPos = newRoom:GetPivot().Position
		local killer = FOLLOWER_B:Clone()
		killer.Name = "Killer"
		killer.Parent = newRoom

		killer:PivotTo(CFrame.new(roomPos.X, floorY + 3, roomPos.Z + 15))

		local hum = killer:WaitForChild("Humanoid")
		local root = killer:WaitForChild("HumanoidRootPart")
		hum.WalkSpeed = 15

		local ai = killer:FindFirstChild("FollowerAI")
		if ai then
			ai:Destroy()
		end

		local toolsFolder = ReplicatedStorage:FindFirstChild("Tools")
		if toolsFolder and toolsFolder:FindFirstChild("Knife") then
			local kKnife = toolsFolder.Knife:Clone()
			kKnife.Parent = killer
		end

		task.spawn(function()
			while killer.Parent and hum.Health > 0 do
				if
					character
					and character:FindFirstChild("HumanoidRootPart")
					and character:FindFirstChild("Humanoid")
				then
					local pRoot = character.HumanoidRootPart
					local pHum = character.Humanoid

					if pHum.Health > 0 then
						hum:MoveTo(pRoot.Position)
						local dist = (pRoot.Position - root.Position).Magnitude
						if dist < 4 then
							pHum:TakeDamage(15)
							task.wait(1)
						end
					end
				end
				task.wait(0.2)
			end
		end)

		if character then
			local toolConn
			local function bindWeapon()
				if toolConn then
					toolConn:Disconnect()
				end
				local tool = character:FindFirstChild("Knife")
				if tool then
					toolConn = tool.Activated:Connect(function()
						if hum.Health > 0 and character:FindFirstChild("HumanoidRootPart") then
							local pRoot = character.HumanoidRootPart
							local dist = (pRoot.Position - root.Position).Magnitude
							if dist < 6.5 then
								hum.Health = 0
								local blood = Instance.new("ParticleEmitter")
								blood.Color = ColorSequence.new(Color3.fromRGB(150, 0, 0))
								blood.Size = NumberSequence.new(1)
								blood.Parent = root
								blood:Emit(30)

								if tool then
									tool:Destroy()
								end
							end
						end
					end)
				end
			end

			character.ChildAdded:Connect(function(child)
				if child.Name == "Knife" then
					bindWeapon()
				end
			end)
			bindWeapon()
		end
	end

	local directions = { "Left", "Right", "Back" }
	local chosenDirection = directions[math.random(1, #directions)]
	local activeExit = nil

	for _, dir in ipairs(directions) do
		local wall = newRoom:FindFirstChild("Wall_" .. dir)
		local exitPart = newRoom:FindFirstChild("Exit_" .. dir)
		if dir == chosenDirection then
			if wall then
				wall:Destroy()
			end
			if exitPart then
				activeExit = exitPart
				exitPart.Transparency = 0
				exitPart.Material = Enum.Material.Neon
				exitPart.CanCollide = false
			end
		else
			if exitPart then
				exitPart:Destroy()
			end
		end
	end

	if roomEvent == "Follower" then
		local roomPos = newRoom:GetPivot().Position
		local exitBasePos = CFrame.new(0, floorY + 3, 0)
		if activeExit then
			local direction = Vector3.new(activeExit.Position.X - roomPos.X, 0, activeExit.Position.Z - roomPos.Z)
			local basePos = roomPos + direction * 0.8
			exitBasePos = CFrame.lookAt(
				CFrame.new(basePos.X, floorY + 3, basePos.Z).Position,
				Vector3.new(roomPos.X, floorY + 3, roomPos.Z)
			)
		end

		local entranceBasePos = CFrame.new(
			(entrance.CFrame * CFrame.new(3, 0, 3)).Position.X,
			floorY + 3,
			(entrance.CFrame * CFrame.new(3, 0, 3)).Position.Z
		)
		local deadBodyBasePos = CFrame.new(roomPos.X + 3, floorY, roomPos.Z + 3)

		local function spawnNPC(template, name, positionCFrame, isDead, isPartner, isChoice)
			local npc = template:Clone()
			npc.Name = isDead and (name .. "_Corpse") or name
			npc.Parent = newRoom

			if isDead then
				local hum = npc:FindFirstChild("Humanoid")
				if hum then
					hum:Destroy()
				end
				local ai = npc:FindFirstChild("FollowerAI")
				if ai then
					ai:Destroy()
				end

				for _, part in npc:GetDescendants() do
					if part:IsA("BasePart") then
						part.Color = Color3.fromRGB(100, 0, 0)
						part.Material = Enum.Material.Slate
						part.Transparency = 0
						for _, child in part:GetChildren() do
							if child:IsA("Decal") or child:IsA("Texture") then
								child:Destroy()
							end
						end
						for _, joint in part:GetChildren() do
							if joint:IsA("Motor6D") or joint:IsA("Weld") then
								joint:Destroy()
							end
						end

						local offsetX, offsetZ = (math.random() - 0.5) * 6, (math.random() - 0.5) * 6
						local randomRot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)

						part.CFrame = CFrame.new(deadBodyBasePos.X + offsetX, floorY + 0.5, deadBodyBasePos.Z + offsetZ)
							* randomRot
						part.Anchored = true
						part.CanCollide = false
					end
				end
			elseif isPartner then
				npc:PivotTo(positionCFrame)
				local ai = npc:FindFirstChild("FollowerAI")
				if ai then
					ai:Destroy()
				end

				local head = npc:FindFirstChild("Head") or npc.PrimaryPart
				if head then
					local bgui = Instance.new("BillboardGui")
					bgui.Size = UDim2.new(0, 200, 0, 50)
					bgui.StudsOffset = Vector3.new(0, 2.5, 0)
					bgui.Adornee = head
					bgui.Parent = npc

					local text = Instance.new("TextLabel")
					text.Size = UDim2.new(1, 0, 1, 0)
					text.BackgroundTransparency = 1
					text.Text = "ありがとう…\n私はここまでにします"
					text.TextColor3 = Color3.new(1, 1, 1)
					text.TextStrokeTransparency = 0.5
					text.TextScaled = true
					text.Font = Enum.Font.GothamBold
					text.Parent = bgui
				end

				for _, part in npc:GetDescendants() do
					if part:IsA("BasePart") then
						part.CollisionGroup = "Default"
					end
				end
			elseif isChoice then
				npc:PivotTo(positionCFrame)
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "SelectPrompt"
				prompt.ActionText = "連れて行く"
				prompt.ObjectText = name
				prompt.HoldDuration = 0.5
				prompt.MaxActivationDistance = 15
				prompt.Parent = npc

				for _, part in npc:GetDescendants() do
					if part:IsA("BasePart") then
						part.CollisionGroup = "Default"
					end
				end
			end
		end

		if currentFollowerName == "Follower_A" then
			spawnNPC(FOLLOWER_A, "Follower_A", entranceBasePos, false, true, false)
			spawnNPC(FOLLOWER_B, "Follower_B", deadBodyBasePos, true, false, false)
		elseif currentFollowerName == "Follower_B" then
			spawnNPC(FOLLOWER_B, "Follower_B", entranceBasePos, false, true, false)
			spawnNPC(FOLLOWER_A, "Follower_A", deadBodyBasePos, true, false, false)
		else
			spawnNPC(FOLLOWER_A, "Follower_A", exitBasePos * CFrame.new(-6, 0, 0), false, false, true)
			spawnNPC(FOLLOWER_B, "Follower_B", exitBasePos * CFrame.new(6, 0, 0), false, false, true)
		end
	end

	local spawnCFrame = entrance.CFrame * CFrame.new(0, 0, 10)
	if character then
		character:PivotTo(spawnCFrame + Vector3.new(0, 2, 0))
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		local hum = character:FindFirstChild("Humanoid")
		if hum then
			hum.Jumping:Connect(function(active)
				if active then
					state.HasJumpedThisFloor = true
				end
			end)
		end
	end

	if state.LastGhostData then
		local ghost = GHOST_TEMPLATE:Clone()
		ghost.Parent = newRoom
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.CollisionGroup = GHOST_GROUP
				part.Material = GHOST_MATERIAL
				part.Color = GHOST_COLOR
				part.Transparency = 0
				part.CastShadow = false
				local decal = part:FindFirstChildOfClass("Decal")
				if decal then
					decal.Color3 = GHOST_COLOR
				end
			end
		end

		local playbackData = state.LastGhostData
		if state.ActiveAnomaly then
			playbackData = createTamperedData(state.LastGhostData, state.ActiveAnomaly)
		end
		task.spawn(function()
			GhostPlayback.Play(ghost, playbackData, entrance, 1.0)
		end)
	end

	GhostRecorder.StartRecording(player, entrance)

	local debounce = false
	local spawnTime = os.clock()

	local function onDoorTouched(hit, doorType)
		if debounce then
			return
		end
		if os.clock() - spawnTime < 1.0 then
			return
		end

		local hitPlayer = game.Players:GetPlayerFromCharacter(hit.Parent)
		if hitPlayer == player then
			debounce = true
			RoomManager.CheckAnswer(player, doorType)
		end
	end

	if entrance then
		entrance.Touched:Connect(function(hit)
			onDoorTouched(hit, "Entrance")
		end)
	end
	if activeExit then
		activeExit.Touched:Connect(function(hit)
			onDoorTouched(hit, "Exit")
		end)
	end

	remoteEvent:FireClient(player, state.Level)
end

function RoomManager.Init()
	requestStartEvent.OnServerEvent:Connect(function(player)
		local state = playerStates[player]
		if state then
			state.Level = 1
			state.LastGhostData = nil
			state.AbandonedNPC = nil
			if player.Character then
				player.Character:SetAttribute("FollowerName", nil)
			end
			spawnRoom(player, true)
		end
	end)

	game.Players.PlayerAdded:Connect(function(player)
		playerStates[player] = {
			CurrentRoom = nil,
			Level = 1,
			LastGhostData = nil,
			ActiveAnomaly = nil,
			AbandonedNPC = nil,
			CurrentRoomEvent = "None",
			HasJumpedThisFloor = false,
		}
		player.CharacterAdded:Connect(function(character)
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if root then
				root.Anchored = true
			end
		end)
	end)

	game.Players.PlayerRemoving:Connect(function(player)
		if playerStates[player] and playerStates[player].CurrentRoom then
			playerStates[player].CurrentRoom:Destroy()
		end
		playerStates[player] = nil
		GhostRecorder.StopRecording(player)
	end)
end

function RoomManager.CheckAnswer(player: Player, doorType: string)
	local state = playerStates[player]
	if not state then
		return
	end

	local currentRecording = GhostRecorder.StopRecording(player)
	local isCorrect = false
	local isGameOver = false

	if state.ActiveAnomaly ~= nil then
		if doorType == "Entrance" then
			isCorrect = true
		else
			isCorrect = false
			isGameOver = true
		end
	else
		if doorType == "Exit" then
			isCorrect = true
		else
			isCorrect = false
		end
	end

	if isCorrect then
		if not state.HasJumpedThisFloor then
			awardBadge(player, BADGE_IDS.NoJump, "地に足をつけて（ジャンプせずにクリア）")
		end

		if state.CurrentRoomEvent == "KnifeRoom" then
			local hasKnife = player.Backpack:FindFirstChild("Knife")
				or (player.Character and player.Character:FindFirstChild("Knife"))
			if not hasKnife then
				awardBadge(player, BADGE_IDS.IgnoredKnife, "非暴力の誓い（ナイフを無視してクリア）")
			end
		end

		state.Level += 1

		-- ==========================================
		-- ★ 修正箇所：クリア時にプレイヤーを「完全無敵状態」にする
		-- ==========================================
		if state.Level >= 10 then
			awardBadge(player, BADGE_IDS.GameClear, "ループからの脱出（ゲームクリア）")

			if player.Character then
				local root = player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					root.Anchored = true
					root.AssemblyLinearVelocity = Vector3.zero
				end

				-- ★ ここで無敵バリアを張り、キラーからのダメージを強制的に無効化
				local forceField = Instance.new("ForceField")
				forceField.Visible = false -- バリア自体は見えないようにする
				forceField.Parent = player.Character
			end

			if gameClearEvent then
				gameClearEvent:FireClient(player)
			end

			return
		end

		state.LastGhostData = currentRecording
		spawnRoom(player, false)
	else
		if isGameOver then
			if jumpscareEvent then
				jumpscareEvent:FireClient(player)
			end
			if state.CurrentRoom then
				state.CurrentRoom:Destroy()
			end
			state.CurrentRoom = nil
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				player.Character.HumanoidRootPart.Anchored = true
			end
		else
			state.Level = 1
			state.LastGhostData = nil
			state.AbandonedNPC = nil
			if player.Character then
				player.Character:SetAttribute("FollowerName", nil)
			end
			spawnRoom(player, true)
		end
	end
end

return RoomManager

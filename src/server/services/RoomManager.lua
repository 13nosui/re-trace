-- src/server/services/RoomManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PhysicsService = game:GetService("PhysicsService")

local GhostRecorder = require(ServerScriptService.Server.services.GhostRecorder)
local GhostPlayback = require(ServerScriptService.Server.services.GhostPlayback)
local Types = require(ReplicatedStorage.Shared.Types)

-- 設定・定数
local ROOM_TEMPLATE = ServerStorage:WaitForChild("RoomTemplate")
local GHOST_TEMPLATE = ReplicatedStorage:WaitForChild("Ghost")
local FOLLOWER_A = ServerStorage:WaitForChild("Follower_A")
local FOLLOWER_B = ServerStorage:WaitForChild("Follower_B")

local ANOMALY_CHANCE = 0.6

local ANOMALY_CATALOG = {
	{ Name = "GhostAttack" },
	{ Name = "GhostStop" },
	{ Name = "GhostBack" },
	{ Name = "GhostWobble" },
	{ Name = "GhostNoJump" },
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

-- 通信用イベント群
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

-- ★新規追加: ゲーム開始リクエスト用イベント
local requestStartEvent = ReplicatedStorage:FindFirstChild("RequestStartGame")
if not requestStartEvent then
	requestStartEvent = Instance.new("RemoteEvent")
	requestStartEvent.Name = "RequestStartGame"
	requestStartEvent.Parent = ReplicatedStorage
end

math.randomseed(os.time())

local RoomManager = {}

type PlayerState = {
	CurrentRoom: Model?,
	Level: number,
	LastGhostData: { Types.FrameData }?,
	ActiveAnomaly: string?,
	AbandonedNPC: string?,
}

local playerStates: { [Player]: PlayerState } = {}

-- (データ改ざん関数は変更なし)
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
	elseif anomalyName == "GhostStop" then
		local startIndex, durationFrames = math.floor(totalFrames * 0.4), 20
		if startIndex + durationFrames < totalFrames then
			local stopCFrame = newFrames[startIndex].RelCFrame
			for i = 0, durationFrames do
				newFrames[startIndex + i].RelCFrame = stopCFrame
				newFrames[startIndex + i].AnimId = nil
			end
		end
	elseif anomalyName == "GhostBack" then
		local startIndex, durationFrames = math.floor(totalFrames * 0.5), 15
		if startIndex + durationFrames < totalFrames then
			for i = 0, durationFrames do
				local frame = newFrames[startIndex + i]
				frame.RelCFrame = frame.RelCFrame * CFrame.Angles(0, math.pi, 0)
			end
		end
	elseif anomalyName == "GhostWobble" then
		for _, frame in ipairs(newFrames) do
			local wobble = math.sin(frame.Time * 5) * 2.5
			frame.RelCFrame = frame.RelCFrame * CFrame.new(wobble, 0, 0)
		end
	elseif anomalyName == "GhostNoJump" then
		for _, frame in ipairs(newFrames) do
			local x, y, z = frame.RelCFrame:ToEulerAnglesYXZ()
			local pos = frame.RelCFrame.Position
			if pos.Y > 3.5 then
				frame.RelCFrame = CFrame.new(Vector3.new(pos.X, 3.0, pos.Z)) * CFrame.fromEulerAnglesYXZ(x, y, z)
			end
		end
	end
	return newFrames
end

local function spawnRoom(player: Player, isReset: boolean)
	print("--- spawnRoom Start ---")
	local state = playerStates[player]
	if not state then
		return
	end

	if state.CurrentRoom then
		state.CurrentRoom:Destroy()
	end

	state.ActiveAnomaly = nil
	if not isReset and state.Level > 1 and math.random() < ANOMALY_CHANCE then
		local anomaly = ANOMALY_CATALOG[math.random(1, #ANOMALY_CATALOG)]
		state.ActiveAnomaly = anomaly.Name
		print("⚠️ ANOMALY TRIGGERED:", anomaly.Name)
	else
		print("✅ Normal Room")
	end

	local newRoom = ROOM_TEMPLATE:Clone()
	newRoom.Name = "Room_" .. player.Name
	newRoom.Parent = workspace
	newRoom:PivotTo(CFrame.new(0, 100, 0))
	state.CurrentRoom = newRoom

	local floor = newRoom:WaitForChild("Floor", 5)
	local floorY = floor and (floor.Position.Y + (floor.Size.Y / 2)) or newRoom:GetPivot().Position.Y
	local entrance = newRoom:WaitForChild("Entrance") :: BasePart

	local currentFollowerName = nil
	local character = player.Character
	if character then
		currentFollowerName = character:GetAttribute("FollowerName")
		character:SetAttribute("FollowerName", nil)
		character:SetAttribute("HasFollower", nil)
	end

	local defaultVictim = newRoom:FindFirstChild("Victim")
	if defaultVictim then
		defaultVictim:Destroy()
	end

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

	-- プレイヤー移動（UIが消えるのと同時に動けるように、拘束を解く）
	local spawnCFrame = entrance.CFrame * CFrame.new(0, 0, 10)
	if character then
		character:PivotTo(spawnCFrame + Vector3.new(0, 2, 0))
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.Anchored = false -- ★ここで動けるようになる
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
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
	-- ★UIから「ゲーム開始」ボタンが押された時の処理
	requestStartEvent.OnServerEvent:Connect(function(player)
		local state = playerStates[player]
		if state then
			state.Level = 1
			state.LastGhostData = nil
			state.AbandonedNPC = nil
			if player.Character then
				player.Character:SetAttribute("FollowerName", nil)
			end
			spawnRoom(player, true) -- ここで初めて部屋が作られる
		end
	end)

	game.Players.PlayerAdded:Connect(function(player)
		playerStates[player] =
			{ CurrentRoom = nil, Level = 1, LastGhostData = nil, ActiveAnomaly = nil, AbandonedNPC = nil }

		-- ★ログイン直後は部屋を作らず、プレイヤーを空中に固定してタイトル画面を待たせる
		player.CharacterAdded:Connect(function(character)
			local root = character:WaitForChild("HumanoidRootPart", 5)
			if root then
				root.Anchored = true -- 動けないように固定
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
		state.Level += 1
		state.LastGhostData = currentRecording
		spawnRoom(player, false)
	else
		if isGameOver then
			if jumpscareEvent then
				jumpscareEvent:FireClient(player)
			end

			-- ★死亡時は部屋を消し、プレイヤーを固定してゲームオーバーUIを待つ
			if state.CurrentRoom then
				state.CurrentRoom:Destroy()
			end
			state.CurrentRoom = nil

			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				player.Character.HumanoidRootPart.Anchored = true
			end
			-- ここでは spawnRoom は呼ばない（UIの「タイトルへ戻る」→「開始」を待つ）
		else
			-- ただの間違い（異変なしで引き返した）の場合は即リセット
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

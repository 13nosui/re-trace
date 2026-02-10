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

-- 異変カタログ
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

-- ランダムシードの初期化（ランダム性を確保）
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

-- データ改ざん関数
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
		-- 現在の部屋にあるVictimを探す
		local victim = nil
		-- ワークスペース内の自分の部屋を探す
		for _, v in ipairs(workspace:GetChildren()) do
			if v.Name:match("Room_") and v:FindFirstChild("Victim") then
				-- ※簡易的に見つかった最初の部屋のVictimをターゲットにする
				-- （本来はプレイヤーごとの部屋を特定すべきだが、ソロプレイならこれで動く）
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
					for _, frame in ipairs(newFrames) do
						local ghostPos = frame.RelCFrame.Position
						local dist = (ghostPos - victimRelPos).Magnitude
						if dist < 15 then
							frame.EquippedTool = "Knife"
						end
						if dist < 8 then
							frame.IsAttacking = true
						end
					end
				end
			end
		end
	elseif anomalyName == "GhostStop" then
		local startIndex = math.floor(totalFrames * 0.4)
		local durationFrames = 20
		if startIndex + durationFrames < totalFrames then
			local stopCFrame = newFrames[startIndex].RelCFrame
			for i = 0, durationFrames do
				newFrames[startIndex + i].RelCFrame = stopCFrame
				newFrames[startIndex + i].AnimId = nil
			end
		end
	elseif anomalyName == "GhostBack" then
		local startIndex = math.floor(totalFrames * 0.5)
		local durationFrames = 15
		if startIndex + durationFrames < totalFrames then
			for i = 0, durationFrames do
				local frame = newFrames[startIndex + i]
				frame.RelCFrame = frame.RelCFrame * CFrame.Angles(0, math.pi, 0)
			end
		end
	elseif anomalyName == "GhostWobble" then
		for i, frame in ipairs(newFrames) do
			local time = frame.Time
			local wobble = math.sin(time * 5) * 2.5
			frame.RelCFrame = frame.RelCFrame * CFrame.new(wobble, 0, 0)
		end
	elseif anomalyName == "GhostNoJump" then
		for _, frame in ipairs(newFrames) do
			local x, y, z = frame.RelCFrame:ToEulerAnglesYXZ()
			local pos = frame.RelCFrame.Position
			if pos.Y > 3.5 then
				pos = Vector3.new(pos.X, 3.0, pos.Z)
				frame.RelCFrame = CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(x, y, z)
			end
		end
	end

	return newFrames
end

local function spawnRoom(player: Player, isReset: boolean)
	local state = playerStates[player]
	if not state then
		return
	end

	-- 1. 古い部屋の削除（重要！）
	if state.CurrentRoom then
		state.CurrentRoom:Destroy()
	end

	-- 2. 異変の抽選
	state.ActiveAnomaly = nil
	if not isReset and state.Level > 1 and math.random() < ANOMALY_CHANCE then
		local anomaly = ANOMALY_CATALOG[math.random(1, #ANOMALY_CATALOG)]
		state.ActiveAnomaly = anomaly.Name
		print("⚠️ ANOMALY TRIGGERED:", anomaly.Name)
	else
		print("✅ Normal Room")
	end

	-- 3. 新しい部屋を生成
	local newRoom = ROOM_TEMPLATE:Clone()
	newRoom.Name = "Room_" .. player.Name
	newRoom.Parent = workspace
	newRoom:PivotTo(CFrame.new(0, 100, 0))

	-- ★★★【重要】生成した部屋をstateに記録する（これがないと消せなくなる）★★★
	state.CurrentRoom = newRoom
	-- ★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★

	-- 床の基準高さを取得
	local floor = newRoom:WaitForChild("Floor", 5)
	local floorY = 0
	if floor then
		floorY = floor.Position.Y + (floor.Size.Y / 2)
	else
		floorY = newRoom:GetPivot().Position.Y
	end

	local entrance = newRoom:WaitForChild("Entrance") :: BasePart

	-- 追従フラグリセット
	local character = player.Character
	if character then
		character:SetAttribute("HasFollower", nil)
		character:SetAttribute("FollowerName", nil)
	end

	-- Victim生成
	local defaultVictim = newRoom:FindFirstChild("Victim")
	if defaultVictim then
		defaultVictim:Destroy()
	end

	local victimModel = nil
	if state.AbandonedNPC == "Follower_A" then
		victimModel = FOLLOWER_A:Clone()
	elseif state.AbandonedNPC == "Follower_B" then
		victimModel = FOLLOWER_B:Clone()
	else
		victimModel = FOLLOWER_A:Clone()
	end

	if victimModel then
		victimModel.Name = "Victim"
		victimModel.Parent = newRoom
		local centerPos = newRoom:GetPivot().Position
		victimModel:PivotTo(CFrame.new(centerPos.X, floorY + 3, centerPos.Z))

		local humanoid = victimModel:WaitForChild("Humanoid")
		local root = victimModel:WaitForChild("HumanoidRootPart")

		root.Anchored = false -- 落下させる
		humanoid.Health = 100

		local aiScript = victimModel:FindFirstChild("FollowerAI")
		if aiScript then
			aiScript:Destroy()
		end
	end

	-- 4. 出口のランダム決定
	local directions = { "Left", "Right", "Back" }
	local chosenDirection = directions[math.random(1, #directions)]
	local activeExit = nil

	for _, dir in ipairs(directions) do
		local wall = newRoom:FindFirstChild("Wall_" .. dir)
		local exitPart = newRoom:FindFirstChild("Exit_" .. dir)

		if dir == chosenDirection then
			-- 通路を開く（壁を消す）
			if wall then
				wall:Destroy()
			end

			if exitPart then
				activeExit = exitPart
				-- ★修正: 出口を見えるようにする（白く光る扉）
				exitPart.Transparency = 0
				exitPart.Material = Enum.Material.Neon -- 光らせる
				exitPart.CanCollide = false
			else
				warn("⚠️ Exit_" .. dir .. " not found!")
			end
		else
			-- 通路を閉じる（出口判定を消す）
			if exitPart then
				exitPart:Destroy()
			end
		end
	end

	-- NPC配置
	local targetBasePos = CFrame.new(0, floorY + 3, 0)
	if activeExit then
		local exitPos = activeExit.Position
		local roomPos = newRoom:GetPivot().Position
		local direction = (exitPos - roomPos)
		direction = Vector3.new(direction.X, 0, direction.Z)

		local basePos = roomPos + direction * 0.8
		targetBasePos = CFrame.new(basePos.X, floorY + 3, basePos.Z)
		targetBasePos = CFrame.lookAt(targetBasePos.Position, Vector3.new(roomPos.X, targetBasePos.Y, roomPos.Z))
	end

	-- 左のNPC
	local npc1 = FOLLOWER_A:Clone()
	npc1.Parent = newRoom
	npc1:PivotTo(targetBasePos * CFrame.new(-6, 0, 0))

	-- 右のNPC
	local npc2 = FOLLOWER_B:Clone()
	npc2.Parent = newRoom
	npc2:PivotTo(targetBasePos * CFrame.new(6, 0, 0))

	for _, npc in ipairs({ npc1, npc2 }) do
		for _, part in npc:GetDescendants() do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Default"
			end
		end
	end

	-- プレイヤー移動
	local spawnCFrame = entrance.CFrame * CFrame.new(0, 0, 10)

	if character then
		-- 高さも調整
		character:PivotTo(spawnCFrame + Vector3.new(0, 2, 0))

		-- ★追加: 慣性を消して、移動の勢いで滑らないようにする
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	-- ゴースト生成
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
			print("😈 Injecting Anomaly:", state.ActiveAnomaly)
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
	game.Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			if playerStates[player] and playerStates[player].CurrentRoom then
				playerStates[player].CurrentRoom:Destroy()
			end
			playerStates[player] = {
				CurrentRoom = nil,
				Level = 1,
				LastGhostData = nil,
				ActiveAnomaly = nil,
				AbandonedNPC = nil,
			}
			task.wait(1)
			spawnRoom(player, true)
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

	if not currentRecording or #currentRecording == 0 then
		warn("⚠️ Recording data empty")
	end

	local isCorrect = false
	local isGameOver = false

	if state.ActiveAnomaly ~= nil then
		if doorType == "Entrance" then
			isCorrect = true
			print("✅ 異変に気づいた！")
		else
			isCorrect = false
			isGameOver = true
			print("💀 GAMEOVER: 異変を見逃した...")
		end
	else
		if doorType == "Exit" then
			isCorrect = true
			print("✅ 正常なので進んだ！")
		else
			isCorrect = false
			print("❌ 正常なのに戻ってしまった...")
		end
	end

	if isCorrect then
		local followerName = player.Character and player.Character:GetAttribute("FollowerName")
		if followerName == "Follower_A" then
			state.AbandonedNPC = "Follower_B"
			print("Selected A, Abandoned B")
		elseif followerName == "Follower_B" then
			state.AbandonedNPC = "Follower_A"
			print("Selected B, Abandoned A")
		else
			if math.random() < 0.5 then
				state.AbandonedNPC = "Follower_A"
			else
				state.AbandonedNPC = "Follower_B"
			end
			print("Abandoned Random (No selection)")
		end

		state.Level += 1
		state.LastGhostData = currentRecording
		spawnRoom(player, false)
	else
		if isGameOver then
			if jumpscareEvent then
				jumpscareEvent:FireClient(player)
			end
			task.wait(2.5)
		end

		state.Level = 1
		state.LastGhostData = nil
		state.AbandonedNPC = nil
		spawnRoom(player, true)
	end
end

return RoomManager

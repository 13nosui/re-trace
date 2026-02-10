-- src/server/services/RoomManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PhysicsService = game:GetService("PhysicsService")

-- モジュールの読み込み
local GhostRecorder = require(ServerScriptService.Server.services.GhostRecorder)
local GhostPlayback = require(ServerScriptService.Server.services.GhostPlayback)
local Types = require(ReplicatedStorage.Shared.Types)

-- 設定・定数
local ROOM_TEMPLATE = ServerStorage:WaitForChild("RoomTemplate")
local GHOST_TEMPLATE = ReplicatedStorage:WaitForChild("Ghost")
local ANOMALY_CHANCE = 0.5 -- 50%の確率で異変（攻撃）
-- ★ ゴーストのスタイル定義
local GHOST_COLOR = Color3.fromRGB(100, 200, 255) -- 青白い色
local GHOST_MATERIAL = Enum.Material.Neon -- 発光するマテリアル

-- ★ 異変カタログ（シンプルに「攻撃する」のみ）
local ANOMALY_CATALOG = {
	{ Name = "GhostAttack" },
}

-- ★ コリジョングループの設定
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

-- 通信用のRemoteEvent
local remoteEvent = ReplicatedStorage:FindFirstChild("OnFloorChanged")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "OnFloorChanged"
	remoteEvent.Parent = ReplicatedStorage
end

local RoomManager = {}

type PlayerState = {
	CurrentRoom: Model?,
	Level: number,
	LastGhostData: { Types.FrameData }?,
	ActiveAnomaly: string?,
}

local playerStates: { [Player]: PlayerState } = {}

-- =========================================================
-- ★ データ改ざん関数 (異変の正体)
-- プレイヤーの動きはそのままで、Victimの近くを通ったときだけ
-- 「ナイフを持って攻撃した」ことにデータを書き換える
-- =========================================================
local function createTamperedData(originalFrames: { Types.FrameData }): { Types.FrameData }
	-- Victimの場所（Entranceからの相対座標）を計算しておく
	-- ※RoomTemplate内の配置を基準にする
	local victim = ROOM_TEMPLATE:FindFirstChild("Victim")
	local entrance = ROOM_TEMPLATE:FindFirstChild("Entrance")

	if not victim or not entrance then
		warn("⚠️ Victim or Entrance not found in RoomTemplate")
		return originalFrames
	end

	local victimRoot = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
	if not victimRoot then
		return originalFrames
	end

	-- Entranceから見たVictimの位置
	local victimRelPos = entrance.CFrame:PointToObjectSpace(victimRoot.Position)

	-- データをコピーして書き換える
	local newFrames = {}

	for _, frame in ipairs(originalFrames) do
		-- フレームを複製（元のデータを壊さないため）
		local newFrame = table.clone(frame)

		-- このフレームでのゴーストの位置
		local ghostPos = newFrame.RelCFrame.Position

		-- Victimとの距離を測る
		local dist = (ghostPos - victimRelPos).Magnitude

		-- 距離が近い場合、殺意を芽生えさせる
		if dist < 15 then
			-- 15スタッド以内ならナイフを取り出す
			newFrame.EquippedTool = "Knife"
		end

		if dist < 8 then
			-- 8スタッド以内なら攻撃しまくる
			newFrame.IsAttacking = true
		end

		table.insert(newFrames, newFrame)
	end

	return newFrames
end

-- ---------------------------------------------------------
-- 内部関数
-- ---------------------------------------------------------

local function spawnRoom(player: Player, isReset: boolean)
	local state = playerStates[player]
	if not state then
		return
	end

	-- 1. 部屋の削除
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

	-- 出口のランダム決定
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
			activeExit = exitPart
		else
			if exitPart then
				exitPart:Destroy()
			end
		end
	end

	state.CurrentRoom = newRoom
	local entrance = newRoom:WaitForChild("Entrance") :: BasePart

	-- 4. プレイヤーのテレポート
	local spawnCFrame = entrance.CFrame * CFrame.new(0, 2, 4)
	local character = player.Character
	if character then
		character:PivotTo(spawnCFrame + Vector3.new(0, 3, 0))
	end

	-- 5. ゴーストの生成
	if state.LastGhostData then
		local ghost = GHOST_TEMPLATE:Clone()
		ghost.Parent = newRoom

		-- ★ 見た目とコリジョンの設定
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				-- コリジョン設定
				part.CanCollide = false
				part.CollisionGroup = GHOST_GROUP

				-- 見た目設定（青白く光らせる）
				part.Material = GHOST_MATERIAL -- Neonにして発光させる
				part.Color = GHOST_COLOR -- 青白い色にする
				part.Transparency = 0 -- 不透明にする
				part.CastShadow = false -- ゴースト自身の影は落とさない

				-- 顔のDecalがあれば、それも青白くする（お好みで）
				local decal = part:FindFirstChildOfClass("Decal")
				if decal then
					decal.Color3 = GHOST_COLOR
				end
			end
		end

		-- ★ ここでデータを分岐させる
		local playbackData = state.LastGhostData

		if state.ActiveAnomaly == "GhostAttack" then
			-- 異変発生中なら、データを改ざんして「攻撃データ」にする
			print("😈 Injecting Malice into Ghost Data...")
			playbackData = createTamperedData(state.LastGhostData)
		end

		task.spawn(function()
			-- 改ざん済みのデータ（または正常データ）を再生
			GhostPlayback.Play(ghost, playbackData, entrance, 1.0)
		end)
	end

	-- 6. 新規録画
	GhostRecorder.StartRecording(player, entrance)

	-- 7. ドア判定
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

-- ---------------------------------------------------------
-- 公開関数
-- ---------------------------------------------------------

function RoomManager.Init()
	game.Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			playerStates[player] = {
				CurrentRoom = nil,
				Level = 1,
				LastGhostData = nil,
				ActiveAnomaly = nil,
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

	-- 判定ロジック
	local isCorrect = false

	if state.ActiveAnomaly ~= nil then
		-- 異変あり（ゴーストが勝手に攻撃した）→ 戻るのが正解
		if doorType == "Entrance" then
			isCorrect = true
			print("✅ 異変（行動の食い違い）に気づいて引き返した！")
		else
			isCorrect = false
			print("❌ ゴーストが勝手に攻撃しているのに進んでしまった...")
		end
	else
		-- 異変なし（プレイヤーと同じ行動）→ 進むのが正解
		if doorType == "Exit" then
			isCorrect = true
			print("✅ 正常なので進んだ！")
		else
			isCorrect = false
			print("❌ 正常なのに戻ってしまった...")
		end
	end

	if isCorrect then
		state.Level += 1
		state.LastGhostData = currentRecording
		spawnRoom(player, false)
	else
		state.Level = 1
		state.LastGhostData = nil
		spawnRoom(player, true)
	end
end

return RoomManager

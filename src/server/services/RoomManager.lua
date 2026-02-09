-- src/server/services/RoomManager.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- モジュールの読み込み
local GhostRecorder = require(ServerScriptService.Server.services.GhostRecorder)
local GhostPlayback = require(ServerScriptService.Server.services.GhostPlayback)
local Types = require(ReplicatedStorage.Shared.Types)

-- 設定・定数
local ROOM_TEMPLATE = ServerStorage:WaitForChild("RoomTemplate")
local GHOST_TEMPLATE = ReplicatedStorage:WaitForChild("Ghost")
local ANOMALY_CHANCE = 0.4 -- 40%の確率で何らかの異変発生

-- ★ 異変カタログ（ここを編集してバリエーションを増やす！）
-- Speed: 再生速度 (1.0が基準)
-- Scale: 体の大きさ (1.0が基準)
-- Transparency: 透明度 (0.5が基準)
-- Color: 体の色 (nilなら変化なし)
local ANOMALY_CATALOG = {
	{ Name = "FastWalk", Speed = 1.3, Scale = 1.0, Transparency = 0.5, Color = nil }, -- ちょっと速い
	{ Name = "SlowWalk", Speed = 0.75, Scale = 1.0, Transparency = 0.5, Color = nil }, -- ちょっと遅い
	{ Name = "BigGhost", Speed = 1.0, Scale = 1.25, Transparency = 0.5, Color = nil }, -- ちょっと大きい
	{ Name = "SmallGhost", Speed = 1.0, Scale = 0.75, Transparency = 0.5, Color = nil }, -- ちょっと小さい
	{ Name = "FaintGhost", Speed = 1.0, Scale = 1.0, Transparency = 0.75, Color = nil }, -- 影が薄い
	-- { Name = "RedGhost",     Speed = 1.0,  Scale = 1.0,  Transparency = 0.5, Color = Color3.fromRGB(255, 100, 100) }, -- (例) 明らかな異変
}

-- 正常時の設定
local NORMAL_SETTINGS = { Speed = 1.0, Scale = 1.0, Transparency = 0.5, Color = Color3.fromRGB(100, 255, 255) }

-- 通信用のRemoteEvent
local remoteEvent = ReplicatedStorage:FindFirstChild("OnFloorChanged")
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = "OnFloorChanged"
	remoteEvent.Parent = ReplicatedStorage
end

local RoomManager = {}

-- プレイヤーごとの状態管理
type PlayerState = {
	CurrentRoom: Model?,
	Level: number,
	LastGhostData: { Types.FrameData }?,
	ActiveAnomaly: string?, -- ★発生中の異変名 (nilなら正常)
}

local playerStates: { [Player]: PlayerState } = {}

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
	state.ActiveAnomaly = nil -- いったんリセット
	local currentSettings = NORMAL_SETTINGS

	-- レベル1以外、かつ確率に当選したら異変発生
	if not isReset and state.Level > 1 and math.random() < ANOMALY_CHANCE then
		-- カタログからランダムに1つ選ぶ
		local anomaly = ANOMALY_CATALOG[math.random(1, #ANOMALY_CATALOG)]
		state.ActiveAnomaly = anomaly.Name
		currentSettings = {
			Speed = anomaly.Speed,
			Scale = anomaly.Scale,
			Transparency = anomaly.Transparency,
			Color = anomaly.Color or NORMAL_SETTINGS.Color,
		}
		print("⚠️ ANOMALY TRIGGERED:", anomaly.Name)
	else
		-- 正常
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

	-- 5. ゴーストの生成と設定適用
	if state.LastGhostData then
		local ghost = GHOST_TEMPLATE:Clone()
		ghost.Parent = newRoom

		-- ★サイズの適用 (ScaleTo APIを使用)
		if currentSettings.Scale ~= 1.0 then
			ghost:ScaleTo(currentSettings.Scale)
		end

		-- ★見た目の適用
		for _, part in ghost:GetDescendants() do
			if part:IsA("BasePart") then
				part.Transparency = currentSettings.Transparency
				part.Color = currentSettings.Color
				part.CanCollide = false
				part.CastShadow = false
			end
		end

		-- 再生開始
		task.spawn(function()
			GhostPlayback.Play(ghost, state.LastGhostData, entrance, currentSettings.Speed)
		end)
	end

	-- 6. 新規録画の開始
	GhostRecorder.StartRecording(player, entrance)

	-- 7. ドア判定イベント
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

	if not currentRecording or #currentRecording == 0 then
		-- エラー回避：データがないときは空データを入れておく
		warn("⚠️ Recording data empty")
	end

	local isCorrect = false

	-- ==========================================
	-- ★ 正解・不正解の判定ロジック
	-- ==========================================
	if state.ActiveAnomaly ~= nil then
		-- 【異変あり (ActiveAnomalyに名前が入っている)】
		-- 正解: Entrance (戻る)
		if doorType == "Entrance" then
			isCorrect = true
			print("✅ 異変に気づいて引き返した！")
		else
			isCorrect = false
			print("❌ 異変があるのに進んでしまった...")
		end
	else
		-- 【異変なし (ActiveAnomaly == nil)】
		-- 正解: Exit (進む)
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
		spawnRoom(player, false) -- 次へ
	else
		state.Level = 1
		state.LastGhostData = nil
		spawnRoom(player, true) -- リセット
	end
end

return RoomManager

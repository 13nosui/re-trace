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
local ANOMALY_CHANCE = 0.3 -- 30%の確率で異変発生
local ANOMALY_SPEED = 3.0 -- 異変時のゴースト速度（3倍速）

-- 通信用のRemoteEventを確保
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
	IsAnomaly: boolean, -- ★現在の部屋が異変かどうか
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

	-- 2. 異変の抽選（リセット直後のLevel 1では異変なしにする）
	if isReset or state.Level == 1 then
		state.IsAnomaly = false
	else
		state.IsAnomaly = (math.random() < ANOMALY_CHANCE)
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

	-- 5. ゴーストの再生（異変なら高速再生！）
	if state.LastGhostData then
		local ghost = GHOST_TEMPLATE:Clone()
		ghost.Parent = newRoom

		-- ゴーストの外見設定
		for _, part in ghost:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 0.5
				if state.IsAnomaly then
					part.Color = Color3.fromRGB(255, 50, 50) -- 異変時は赤くする（テスト用）
				else
					part.Color = Color3.fromRGB(100, 255, 255) -- 通常は水色
				end
			end
		end

		-- ★スピード設定
		local speed = state.IsAnomaly and ANOMALY_SPEED or 1.0

		task.spawn(function()
			-- 第4引数にスピードを渡す
			GhostPlayback.Play(ghost, state.LastGhostData, entrance, speed)
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

	-- デバッグ表示（テスト中は答えを表示しておくと楽です）
	print("🚪 Level:", state.Level, "| Anomaly:", state.IsAnomaly)
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
				IsAnomaly = false,
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

	-- ★修正: データがない（nil または 空）場合の対策
	if not currentRecording or #currentRecording == 0 then
		warn("⚠️ 録画データが空です。ゴーストは生成されません。")
		-- 必要ならここで return して処理を中断したり、ダミーデータを入れたりできます
		-- 今回はこのまま進めますが、LastGhostDataにはnilが入ります
	end

	local isCorrect = false

	-- ==========================================
	-- ★ 正解・不正解の判定ロジック
	-- ==========================================
	if state.IsAnomaly then
		-- 【異変あり】→ 「戻る（Entrance）」が正解
		if doorType == "Entrance" then
			isCorrect = true
		else
			isCorrect = false -- 進んだらアウト
		end
	else
		-- 【異変なし】→ 「進む（Exit）」が正解
		if doorType == "Exit" then
			isCorrect = true
		else
			isCorrect = false -- 戻ったらアウト（振り出しへ）
		end
	end

	if isCorrect then
		print("✅ 正解！")
		state.Level += 1
		state.LastGhostData = currentRecording
		-- 次の部屋へ（Reset=false）
		spawnRoom(player, false)
	else
		print("❌ 不正解... Level 1へ")
		state.Level = 1
		state.LastGhostData = nil
		-- 最初から（Reset=true）
		spawnRoom(player, true)
	end
end

return RoomManager

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
	LastGhostData: { Types.FrameData }?, -- 前の部屋での録画データ
}

local playerStates: { [Player]: PlayerState } = {}

-- ---------------------------------------------------------
-- 内部関数
-- ---------------------------------------------------------

-- 部屋を生成し、ゴースト処理と録画を開始する
local function spawnRoom(player: Player, isReset: boolean)
	local state = playerStates[player]
	if not state then
		return
	end

	-- 1. 古い部屋があれば削除
	if state.CurrentRoom then
		state.CurrentRoom:Destroy()
	end

	-- 2. 新しい部屋を生成
	local newRoom = ROOM_TEMPLATE:Clone()
	newRoom.Name = "Room_" .. player.Name
	newRoom.Parent = workspace

	-- テスト用に上空へ配置
	newRoom:PivotTo(CFrame.new(0, 100, 0))

	-- ====================================================
	-- ★ ランダムな出口の決定ロジック
	-- ====================================================
	local directions = { "Left", "Right", "Back" }
	local chosenDirection = directions[math.random(1, #directions)] -- 3方向から1つランダムに選ぶ
	local activeExit = nil

	for _, dir in ipairs(directions) do
		local wall = newRoom:FindFirstChild("Wall_" .. dir)
		local exitPart = newRoom:FindFirstChild("Exit_" .. dir)

		if dir == chosenDirection then
			-- 【当選】この方向が正解ルート
			-- 通れるように「壁」を消す
			if wall then
				wall:Destroy()
			end
			-- 「出口」は残して、判定用に使う
			activeExit = exitPart
		else
			-- 【落選】この方向は壁
			-- 間違って判定されないように「出口」を消す
			if exitPart then
				exitPart:Destroy()
			end
			-- 「壁」はそのまま残す（通せんぼするため）
		end
	end
	-- ====================================================

	state.CurrentRoom = newRoom
	local entrance = newRoom:WaitForChild("Entrance") :: BasePart

	-- 3. プレイヤーを入り口へテレポート
	-- (Entranceの手前ではなく、奥側へ移動させるための調整)
	local spawnCFrame = entrance.CFrame * CFrame.new(0, 2, 4)
	local character = player.Character
	if character then
		character:PivotTo(spawnCFrame + Vector3.new(0, 3, 0))
	end

	-- 4. ゴーストの再生（データがあれば）
	if state.LastGhostData then
		local ghost = GHOST_TEMPLATE:Clone()
		ghost.Parent = newRoom
		-- ゴーストの色を水色にして分かりやすくする
		for _, part in ghost:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 0.5
				part.Color = Color3.fromRGB(100, 255, 255)
			end
		end

		task.spawn(function()
			GhostPlayback.Play(ghost, state.LastGhostData, entrance)
		end)
	end

	-- 5. 新規録画の開始
	GhostRecorder.StartRecording(player, entrance)

	-- 6. ドア判定のイベント設定
	local debounce = false
	local spawnTime = os.clock()

	local function onDoorTouched(hit, doorType)
		if debounce then
			return
		end

		-- スポーン直後の無敵時間（1秒）
		if os.clock() - spawnTime < 1.0 then
			return
		end

		local hitPlayer = game.Players:GetPlayerFromCharacter(hit.Parent)
		if hitPlayer == player then
			debounce = true
			RoomManager.CheckAnswer(player, doorType)
		end
	end

	-- Entranceの判定
	if entrance then
		entrance.Touched:Connect(function(hit)
			onDoorTouched(hit, "Entrance")
		end)
	end

	-- Exitの判定 (選ばれた出口のみ判定を行う)
	if activeExit then
		activeExit.Touched:Connect(function(hit)
			onDoorTouched(hit, "Exit")
		end)
	end

	print("🚪 Room Level:", state.Level, isReset and "(Reset)" or "", "Next:", chosenDirection)

	-- クライアントに階層情報を送る
	remoteEvent:FireClient(player, state.Level)
end

-- ---------------------------------------------------------
-- 公開関数
-- ---------------------------------------------------------

function RoomManager.Init()
	-- プレイヤー参加時の初期化
	game.Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			playerStates[player] = {
				CurrentRoom = nil,
				Level = 1,
				LastGhostData = nil,
			}
			task.wait(1)
			spawnRoom(player, true)
		end)
	end)

	-- プレイヤー退出時のクリーンアップ
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

	-- 録画を停止してデータを取得
	local currentRecording = GhostRecorder.StopRecording(player)

	if doorType == "Exit" then
		-- ✅ 正解（進む）
		print("✅ 正解！次の階層へ")
		state.Level += 1
		state.LastGhostData = currentRecording
		spawnRoom(player, false)
	elseif doorType == "Entrance" then
		-- ❌ 不正解（戻る/リセット）
		print("❌ 戻ります... レベル1へ")
		state.Level = 1
		state.LastGhostData = nil
		spawnRoom(player, true)
	end
end

return RoomManager

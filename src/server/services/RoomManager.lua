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
local GHOST_TEMPLATE = ReplicatedStorage:WaitForChild("Ghost") -- Step 2で作ったダミー人形

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
	-- (本来は無限に前へ生成しますが、今回は簡易的に原点付近に再生成してテレポートさせます)
	local newRoom = ROOM_TEMPLATE:Clone()
	newRoom.Name = "Room_" .. player.Name
	newRoom.Parent = workspace

	-- 部屋の配置（プレイヤーごとに少しずらすなどの処理がいずれ必要ですが、今は原点でOK）
	-- 毎回微妙に位置を変えるならここでSetPrimaryPartCFrameを使います
	newRoom:PivotTo(CFrame.new(0, 100, 0)) -- テスト用に上空100mに生成

	state.CurrentRoom = newRoom
	local entrance = newRoom:WaitForChild("Entrance") :: BasePart
	local exit = newRoom:WaitForChild("Exit") :: BasePart

	-- 3. プレイヤーを入り口へテレポート
	local spawnCFrame = entrance.CFrame * CFrame.new(0, 2, 4)
	local character = player.Character
	if character then
		character:PivotTo(spawnCFrame + Vector3.new(0, 3, 0))
	end

	-- 4. ゴーストの再生（データがあれば）
	if state.LastGhostData then
		local ghost = GHOST_TEMPLATE:Clone()
		ghost.Parent = newRoom
		-- ゴーストの色を変えてわかりやすくする（オプション）
		for _, part in ghost:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = 0.5
				part.Color = Color3.fromRGB(100, 255, 255) -- 水色
			end
		end

		-- 非同期で再生開始
		task.spawn(function()
			GhostPlayback.Play(ghost, state.LastGhostData, entrance)
		end)
	end

	-- 5. 新規録画の開始
	GhostRecorder.StartRecording(player, entrance)

	-- 6. ドア判定のイベント設定
	local debounce = false
	local spawnTime = os.clock() -- ★スポーンした時刻を記録
	local function onDoorTouched(hit, doorType)
		if debounce then
			return
		end

		-- ★追加: スポーンしてから1秒間は判定しない（無敵時間）
		if os.clock() - spawnTime < 1.0 then
			return
		end

		local hitPlayer = game.Players:GetPlayerFromCharacter(hit.Parent)
		if hitPlayer == player then
			debounce = true
			RoomManager.CheckAnswer(player, doorType)
		end
	end

	entrance.Touched:Connect(function(hit)
		onDoorTouched(hit, "Entrance")
	end)
	exit.Touched:Connect(function(hit)
		onDoorTouched(hit, "Exit")
	end)

	print("🚪 Room Level:", state.Level, isReset and "(Reset)" or "")
end

-- ---------------------------------------------------------
-- 公開関数
-- ---------------------------------------------------------

function RoomManager.Init()
	-- プレイヤー参加時の初期化
	game.Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			-- 状態をリセットしてスタート
			playerStates[player] = {
				CurrentRoom = nil,
				Level = 1,
				LastGhostData = nil,
			}
			-- 少し待ってから開始（ロード待ち）
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
		GhostRecorder.StopRecording(player) -- 念のため停止
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
		state.LastGhostData = currentRecording -- 今回の動きを次へ引き継ぐ
		spawnRoom(player, false)
	elseif doorType == "Entrance" then
		-- ❌ 不正解（戻る/リセット）
		print("❌ 戻ります... レベル1へ")
		state.Level = 1
		state.LastGhostData = nil -- データ消去（または初期データがあればそれを使う）
		spawnRoom(player, true)
	end
end

return RoomManager

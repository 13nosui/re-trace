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
local ANOMALY_CHANCE = 0.6 -- 60%の確率で何らかの異変

-- ★ 異変カタログ (種類を増やしました)
local ANOMALY_CATALOG = {
	{ Name = "GhostAttack" }, -- 勝手に攻撃する
	{ Name = "GhostStop" }, -- 急に立ち止まる
	{ Name = "GhostBack" }, -- 振り返る
	{ Name = "GhostWobble" }, -- フラフラ歩く（軌跡変化）
	{ Name = "GhostNoJump" }, -- ジャンプしない
}

-- ★ ゴーストのスタイル定義
local GHOST_COLOR = Color3.fromRGB(100, 200, 255)
local GHOST_MATERIAL = Enum.Material.Neon

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

local RoomManager = {}

type PlayerState = {
	CurrentRoom: Model?,
	Level: number,
	LastGhostData: { Types.FrameData }?,
	ActiveAnomaly: string?,
}

local playerStates: { [Player]: PlayerState } = {}

-- =========================================================
-- ★ データ改ざん関数 (異変のロジック)
-- =========================================================
local function createTamperedData(originalFrames: { Types.FrameData }, anomalyName: string): { Types.FrameData }
	-- 元データを壊さないようにディープコピー
	local newFrames = {}
	for _, frame in ipairs(originalFrames) do
		local newFrame = table.clone(frame)
		-- CFrameは値渡しなのでそのままでOKだが、テーブル構造が変わるなら注意
		table.insert(newFrames, newFrame)
	end

	local totalFrames = #newFrames
	if totalFrames < 20 then
		return newFrames
	end -- データが少なすぎるときは加工しない

	-- -----------------------------------------------------
	-- A. 攻撃の異変 (GhostAttack)
	-- -----------------------------------------------------
	if anomalyName == "GhostAttack" then
		local victim = ROOM_TEMPLATE:FindFirstChild("Victim")
		local entrance = ROOM_TEMPLATE:FindFirstChild("Entrance")
		if victim and entrance then
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

	-- -----------------------------------------------------
	-- B. 立ち止まる異変 (GhostStop)
	-- -----------------------------------------------------
	elseif anomalyName == "GhostStop" then
		-- 全体の30%〜60%のどこかで立ち止まらせる
		local startIndex = math.floor(totalFrames * 0.4)
		local durationFrames = 20 -- 約2秒間（0.1s * 20）

		if startIndex + durationFrames < totalFrames then
			local stopCFrame = newFrames[startIndex].RelCFrame
			for i = 0, durationFrames do
				-- その期間の座標を、開始時点の座標で上書きする（＝固まる）
				-- ※時間は進むので、この期間が終わるとワープするように位置修正される
				newFrames[startIndex + i].RelCFrame = stopCFrame
				-- アニメーションも停止（IDを消す）
				newFrames[startIndex + i].AnimId = nil
			end
		end

	-- -----------------------------------------------------
	-- C. 振り返る異変 (GhostBack)
	-- -----------------------------------------------------
	elseif anomalyName == "GhostBack" then
		-- 中盤で後ろを向く
		local startIndex = math.floor(totalFrames * 0.5)
		local durationFrames = 15 -- 1.5秒

		if startIndex + durationFrames < totalFrames then
			for i = 0, durationFrames do
				local frame = newFrames[startIndex + i]
				-- Y軸（水平）に180度回転させる
				frame.RelCFrame = frame.RelCFrame * CFrame.Angles(0, math.pi, 0)
			end
		end

	-- -----------------------------------------------------
	-- D. 蛇行する異変 (GhostWobble)
	-- -----------------------------------------------------
	elseif anomalyName == "GhostWobble" then
		for i, frame in ipairs(newFrames) do
			-- 時間経過に合わせて左右（X軸）に揺らす
			local time = frame.Time
			local wobble = math.sin(time * 5) * 2.5 -- 幅2.5スタッドで揺れる
			frame.RelCFrame = frame.RelCFrame * CFrame.new(wobble, 0, 0)
		end

	-- -----------------------------------------------------
	-- E. ジャンプしない異変 (GhostNoJump)
	-- -----------------------------------------------------
	elseif anomalyName == "GhostNoJump" then
		for _, frame in ipairs(newFrames) do
			local x, y, z = frame.RelCFrame:ToEulerAnglesYXZ()
			local pos = frame.RelCFrame.Position
			-- Y座標（高さ）を強制的に地面付近にする
			-- ※Entranceからの相対高さなので、プレイヤーの足の長さ等を考慮して調整
			-- ここではシンプルに「ジャンプの頂点を削る」処理
			if pos.Y > 3.5 then -- 通常歩行より高い場合
				pos = Vector3.new(pos.X, 3.0, pos.Z) -- 押さえつける
				frame.RelCFrame = CFrame.new(pos) * CFrame.fromEulerAnglesYXZ(x, y, z)
			end
		end
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

		-- ★ データの改ざん適用
		local playbackData = state.LastGhostData
		if state.ActiveAnomaly then
			print("😈 Injecting Anomaly:", state.ActiveAnomaly)
			playbackData = createTamperedData(state.LastGhostData, state.ActiveAnomaly)
		end

		task.spawn(function()
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
			-- ★修正点: 初期化する前に、もし古い部屋が残っていたら確実に消す！
			if playerStates[player] and playerStates[player].CurrentRoom then
				playerStates[player].CurrentRoom:Destroy()
			end

			-- その後で初期化する
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
	-- (以下変更なし)
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
	local isGameOver = false -- ★ゲームオーバーフラグ

	if state.ActiveAnomaly ~= nil then
		-- 異変あり
		if doorType == "Entrance" then
			isCorrect = true
			print("✅ 異変に気づいた！ (Anomaly: " .. state.ActiveAnomaly .. ")")
		else
			isCorrect = false
			isGameOver = true -- ★異変があるのに進んでしまった＝死
			print("💀 GAMEOVER: 異変を見逃した... (Anomaly: " .. state.ActiveAnomaly .. ")")
		end
	else
		-- 異変なし
		if doorType == "Exit" then
			isCorrect = true
			print("✅ 正常なので進んだ！")
		else
			isCorrect = false
			print("❌ 正常なのに戻ってしまった... (ただの間違い)")
		end
	end

	if isCorrect then
		state.Level += 1
		state.LastGhostData = currentRecording
		spawnRoom(player, false)
	else
		-- 不正解時の処理

		if isGameOver then
			-- ★ジャンプスケア発動！
			if jumpscareEvent then
				jumpscareEvent:FireClient(player)
			end

			-- 演出の間、少し待ってからリセットする
			task.wait(2.5)
		end

		state.Level = 1
		state.LastGhostData = nil
		spawnRoom(player, true)
	end
end

return RoomManager

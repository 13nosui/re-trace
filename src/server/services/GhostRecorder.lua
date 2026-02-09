-- src/server/services/GhostRecorder.lua
--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)
export type FrameData = Types.FrameData

type RecordingState = {
	StartTime: number,
	LastRecordTime: number,
	EntrancePart: BasePart,
	Frames: { FrameData },
	Connection: RBXScriptConnection?,
}

local GhostRecorder = {}

local activeRecordings: { [Player]: RecordingState } = {}
local RECORD_INTERVAL = 0.1

--- 指定したプレイヤーの記録を開始する
function GhostRecorder.StartRecording(player: Player, entrancePart: BasePart)
	-- 既存の録画があれば停止
	if activeRecordings[player] then
		GhostRecorder.StopRecording(player)
	end

	local startTime = os.clock()

	-- 初期状態の作成
	local state: RecordingState = {
		StartTime = startTime,
		LastRecordTime = 0,
		EntrancePart = entrancePart,
		Frames = {},
		Connection = nil,
	}

	-- 録画処理
	state.Connection = RunService.Heartbeat:Connect(function()
		-- プレイヤーが存在しない場合は何もしない
		if not player or not player.Character then
			return
		end

		local character = player.Character
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?

		if not rootPart or not humanoid then
			return
		end

		local currentTime = os.clock()

		-- RECORD_INTERVAL（0.1秒）ごとにデータを記録
		if currentTime - state.LastRecordTime >= RECORD_INTERVAL then
			state.LastRecordTime = currentTime
			local elapsedSinceStart = currentTime - startTime

			-- アニメーションIDの取得（簡易版）
			local animId: string? = nil
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				local tracks = animator:GetPlayingAnimationTracks()
				local bestTrack: AnimationTrack? = nil
				for _, track in tracks do
					if not bestTrack or track.WeightCurrent > bestTrack.WeightCurrent then
						bestTrack = track
					end
				end
				if bestTrack and bestTrack.Animation then
					animId = (bestTrack.Animation :: Animation).AnimationId
				end
			end

			-- フレームデータの作成
			local frame: FrameData = {
				Time = elapsedSinceStart,
				-- 入口からの相対座標を記録
				RelCFrame = entrancePart.CFrame:ToObjectSpace(rootPart.CFrame),
				AnimId = animId,
			}

			-- フレームを追加
			table.insert(state.Frames, frame)
		end
	end)

	-- テーブルに保存
	activeRecordings[player] = state
	print("📼 Start Recording for", player.Name)
end

--- 指定したプレイヤーの記録を停止し、データを返す
function GhostRecorder.StopRecording(player: Player): { FrameData }?
	local state = activeRecordings[player]
	if not state then
		warn("⚠️ StopRecording: No active recording for", player.Name)
		return nil
	end

	-- イベント接続を解除
	if state.Connection then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	local frames = state.Frames

	-- 録画データをクリア
	activeRecordings[player] = nil

	print("📼 Stop Recording for", player.Name, "| Frames:", #frames)
	return frames
end

return GhostRecorder

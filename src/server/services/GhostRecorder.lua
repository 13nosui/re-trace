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

	-- ★追加: ツール監視用
	ToolConnection: RBXScriptConnection?,
	CurrentTool: Tool?,
	AttackTriggered: boolean, -- 次のフレームで記録するためのフラグ
}

local GhostRecorder = {}

local activeRecordings: { [Player]: RecordingState } = {}
local RECORD_INTERVAL = 0.1

function GhostRecorder.StartRecording(player: Player, entrancePart: BasePart)
	if activeRecordings[player] then
		GhostRecorder.StopRecording(player)
	end

	local startTime = os.clock()

	local state: RecordingState = {
		StartTime = startTime,
		LastRecordTime = 0,
		EntrancePart = entrancePart,
		Frames = {},
		Connection = nil,
		ToolConnection = nil,
		CurrentTool = nil,
		AttackTriggered = false,
	}

	-- ★ツールの装備・解除を監視する関数
	local function connectTool(character)
		-- 既存の接続を切る
		if state.ToolConnection then
			state.ToolConnection:Disconnect()
		end
		state.CurrentTool = nil

		-- 今持っているツールを探す
		local tool = character:FindFirstChildOfClass("Tool")
		if tool then
			state.CurrentTool = tool
			-- クリック（攻撃）イベントを検知
			state.ToolConnection = tool.Activated:Connect(function()
				state.AttackTriggered = true
			end)
		end
	end

	-- キャラクターのツール変更を監視
	local character = player.Character
	if character then
		-- 初期チェック
		connectTool(character)

		-- 装備が変わったら再接続
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				connectTool(character)
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if state.CurrentTool == child then
				if state.ToolConnection then
					state.ToolConnection:Disconnect()
				end
				state.CurrentTool = nil
			end
		end)
	end

	state.Connection = RunService.Heartbeat:Connect(function()
		if not player or not player.Character then
			return
		end

		local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = player.Character:FindFirstChild("Humanoid") :: Humanoid?
		if not rootPart or not humanoid then
			return
		end

		local currentTime = os.clock()

		if currentTime - state.LastRecordTime >= RECORD_INTERVAL then
			state.LastRecordTime = currentTime
			local elapsedSinceStart = currentTime - startTime

			local animId: string? = nil
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				local tracks = animator:GetPlayingAnimationTracks()
				local bestTrack = nil
				for _, track in tracks do
					if not bestTrack or track.WeightCurrent > bestTrack.WeightCurrent then
						bestTrack = track
					end
				end
				if bestTrack then
					animId = (bestTrack.Animation :: Animation).AnimationId
				end
			end

			local equippedToolName = state.CurrentTool and state.CurrentTool.Name or nil

			local frame: FrameData = {
				Time = elapsedSinceStart,
				RelCFrame = entrancePart.CFrame:ToObjectSpace(rootPart.CFrame),
				AnimId = animId,
				EquippedTool = equippedToolName,
				IsAttacking = state.AttackTriggered, -- ★クリックしたか記録
			}

			table.insert(state.Frames, frame)

			-- フラグをリセット（次のフレームのために）
			state.AttackTriggered = false
		end
	end)

	activeRecordings[player] = state
	print("📼 Start Recording for", player.Name)
end

function GhostRecorder.StopRecording(player: Player): { FrameData }?
	local state = activeRecordings[player]
	if not state then
		return nil
	end

	if state.Connection then
		state.Connection:Disconnect()
	end
	if state.ToolConnection then
		state.ToolConnection:Disconnect()
	end -- ★解除忘れずに

	local frames = state.Frames
	activeRecordings[player] = nil
	return frames
end

return GhostRecorder

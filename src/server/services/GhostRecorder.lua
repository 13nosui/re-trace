--!strict
local RunService = Instance.new("RunService") -- Note: RunService is normally a global service, but strict typing likes this
local RunService = game:GetService("RunService")

export type FrameData = {
	Time: number, -- 録画開始からの経過時間
	RelCFrame: CFrame, -- Entranceに対する相対座標
	AnimId: string? -- 再生中のアニメーションID
}

type RecordingState = {
	StartTime: number,
	LastRecordTime: number,
	EntrancePart: BasePart,
	Frames: {FrameData},
	Connection: RBXScriptConnection?
}

local GhostRecorder = {}

local activeRecordings: { [Player]: RecordingState } = {}
local RECORD_INTERVAL = 0.1

--- 指定したプレイヤーの記録を開始する
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
		Connection = nil
	}

	state.Connection = RunService.Heartbeat:Connect(function()
		local character = player.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character:FindFirstChild("Humanoid") :: Humanoid?
		
		if not rootPart or not humanoid then return end

		local currentTime = os.clock()
		local elapsedSinceStart = currentTime - startTime

		-- 0.1秒間隔で間引く
		if currentTime - state.LastRecordTime >= RECORD_INTERVAL then
			state.LastRecordTime = currentTime

			-- 現在再生中のアニメーションを取得
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

			local frame: FrameData = {
				Time = elapsedSinceStart,
				RelCFrame = entrancePart.CFrame:ToObjectSpace(rootPart.CFrame),
				AnimId = animId
			}
			table.insert(state.Frames, frame)
		end
	end)

	activeRecordings[player] = state
end

--- 指定したプレイヤーの記録を停止し、データを返す
function GhostRecorder.StopRecording(player: Player): {FrameData}
	local state = activeRecordings[player]
	if not state then
		return {}
	end

	if state.Connection then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	local frames = state.Frames
	activeRecordings[player] = nil
	
	return frames
end

return GhostRecorder

--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

type FrameData = Types.FrameData

local GhostPlayback = {}

--- NPCsのゴースト再生を開始する
function GhostPlayback.Play(npc: Model, recording: { FrameData }, entrancePart: BasePart)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	local rootPart = npc:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not humanoid or not rootPart then
		warn("GhostPlayback: NPC model missing Humanoid or HumanoidRootPart")
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local startTime = os.clock()
	local currentFrameIndex = 1
	local currentAnimTrack: AnimationTrack? = nil
	local currentAnimId: string? = nil

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime

		-- 再生終了チェック
		if currentFrameIndex >= #recording then
			connection:Disconnect()
			if currentAnimTrack then
				currentAnimTrack:Stop()
			end
			return
		end

		-- 現在の経過時間に対応するフレームを探す
		while currentFrameIndex < #recording and recording[currentFrameIndex + 1].Time <= elapsed do
			currentFrameIndex += 1
		end

		local frameA = recording[currentFrameIndex]
		local frameB = recording[currentFrameIndex + 1]

		if not frameB then
			-- 最後のフレームに到達
			rootPart.CFrame = entrancePart.CFrame:ToWorldSpace(frameA.RelCFrame)
			connection:Disconnect()
			if currentAnimTrack then
				currentAnimTrack:Stop()
			end
			return
		end

		-- 線形補間 (Lerp)
		local duration = frameB.Time - frameA.Time
		local alpha = if duration > 0 then (elapsed - frameA.Time) / duration else 1
		alpha = math.clamp(alpha, 0, 1)

		local interpolatedRelCFrame = frameA.RelCFrame:Lerp(frameB.RelCFrame, alpha)
		rootPart.CFrame = entrancePart.CFrame:ToWorldSpace(interpolatedRelCFrame)

		-- アニメーション再生
		local targetAnimId = frameA.AnimId
		if targetAnimId ~= currentAnimId then
			if currentAnimTrack then
				currentAnimTrack:Stop()
				currentAnimTrack = nil
			end

			if targetAnimId and targetAnimId ~= "" then
				local animation = Instance.new("Animation")
				animation.AnimationId = targetAnimId
				currentAnimTrack = animator:LoadAnimation(animation)
				if currentAnimTrack then
					currentAnimTrack:Play()
				end
			end
			currentAnimId = targetAnimId
		end
	end)
end

return GhostPlayback

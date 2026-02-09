-- src/server/services/GhostPlayback.lua
--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

type FrameData = Types.FrameData

local GhostPlayback = {}

-- ★設定: ゴーストの足の長さに応じて補正を行うか
local AUTO_ADJUST_HEIGHT = true
-- 手動で微調整したい場合はここを変える（例: -0.5 とか）
local MANUAL_OFFSET_Y = 0

-- 再生関数
function GhostPlayback.Play(ghostModel: Model, data: table, originPart: BasePart, speed: number?)
	if not data or #data < 2 then
		warn("⚠️ GhostPlayback: データが不足しています")
		return
	end

	local playbackSpeed = speed or 1.0

	-- PrimaryPartの確認
	local root = ghostModel.PrimaryPart or ghostModel:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		ghostModel.PrimaryPart = root
	end
	if not ghostModel.PrimaryPart then
		warn("⚠️ GhostPlayback: PrimaryPartがありません")
		return
	end

	-- ★高さの自動補正
	-- ゴーストのHumanoidを探して、足の長さ(HipHeight)を取得
	local humanoid = ghostModel:FindFirstChild("Humanoid")
	local heightCorrection = Vector3.new(0, MANUAL_OFFSET_Y, -3.0)

	if AUTO_ADJUST_HEIGHT and humanoid then
		-- R15/R6の標準的な高さ補正（足の長さ + RootPartの半分のサイズ）
		-- これにより、RootPartの底面ではなく「足の裏」を基準に合わせようとします
		-- ※うまくいかない場合は MANUAL_OFFSET_Y で調整してください
		local hipHeight = humanoid.HipHeight
		-- 録画データ側（プレイヤー）との差分は正確にはわからないため、
		-- ここでは「ゴースト自身の足の長さ」分だけ下げてみるアプローチをとります
		-- もし埋まりすぎる場合は、ここの数値を調整してください
		heightCorrection = Vector3.new(0, -hipHeight + MANUAL_OFFSET_Y, 0)
	end

	local originCFrame = originPart.CFrame
	local startTime = os.clock()
	local dataDuration = data[#data].Time -- 全体の長さ

	-- Heartbeat接続用の変数
	local connection: RBXScriptConnection? = nil

	-- 終了処理
	local function cleanup()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		-- ゴーストを消すならここで行う（今回はRoomManagerに任せるので何もしない）
	end

	-- 毎フレーム実行されるループ（スムーズな動きを実現）
	connection = RunService.Heartbeat:Connect(function()
		-- ゴーストが消されたら終了
		if not ghostModel or not ghostModel.Parent then
			cleanup()
			return
		end

		-- 現在の再生時間
		local elapsed = (os.clock() - startTime) * playbackSpeed

		-- 再生終了判定
		if elapsed >= dataDuration then
			-- 最後のフレームに合わせて終了
			local lastFrame = data[#data]
			if lastFrame.RelCFrame then
				local target = originCFrame:ToWorldSpace(lastFrame.RelCFrame)
				ghostModel:PivotTo(target + heightCorrection)
			end
			cleanup()
			return
		end

		-- ★現在の時間に合う「前後のフレーム」を探す（線形探索）
		-- データ量が多い場合は二分探索のほうが良いが、数秒程度ならこれで十分
		local frameA, frameB
		for i = 1, #data - 1 do
			if data[i].Time <= elapsed and data[i + 1].Time >= elapsed then
				frameA = data[i]
				frameB = data[i + 1]
				break
			end
		end

		if frameA and frameB and frameA.RelCFrame and frameB.RelCFrame then
			-- AとBの間をどれくらい進んでいるか（0.0 〜 1.0）
			local duration = frameB.Time - frameA.Time
			local alpha = (elapsed - frameA.Time) / duration

			-- ★補間（Lerp）: AとBの間を滑らかにつなぐ
			local relativeCF = frameA.RelCFrame:Lerp(frameB.RelCFrame, alpha)
			local targetCFrame = originCFrame:ToWorldSpace(relativeCF)

			ghostModel:PivotTo(targetCFrame + heightCorrection)
		end
	end)
end

return GhostPlayback

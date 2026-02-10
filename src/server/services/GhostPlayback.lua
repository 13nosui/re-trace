-- src/server/services/GhostPlayback.lua
--!strict
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.Types)

type FrameData = Types.FrameData

local GhostPlayback = {}

local AUTO_ADJUST_HEIGHT = true
local MANUAL_OFFSET_Y = 0

-- 武器の格納場所（あとで作ります）
local ToolsFolder = ReplicatedStorage:WaitForChild("Tools", 5)

-- 再生関数
function GhostPlayback.Play(ghostModel: Model, data: table, originPart: BasePart, speed: number?)
	if not data or #data < 2 then
		warn("⚠️ GhostPlayback: データが不足しています")
		return
	end

	local playbackSpeed = speed or 1.0

	-- Humanoid取得
	local humanoid = ghostModel:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	-- PrimaryPart設定
	local root = ghostModel.PrimaryPart or ghostModel:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		ghostModel.PrimaryPart = root
	end
	if not ghostModel.PrimaryPart then
		return
	end

	-- 高さ補正
	local heightCorrection = Vector3.new(0, MANUAL_OFFSET_Y, 0)
	if AUTO_ADJUST_HEIGHT then
		local hipHeight = humanoid.HipHeight
		heightCorrection = Vector3.new(0, -hipHeight + MANUAL_OFFSET_Y, 0)
	end

	local originCFrame = originPart.CFrame
	local startTime = os.clock()
	local dataDuration = data[#data].Time
	local connection: RBXScriptConnection? = nil

	local function cleanup()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		if not ghostModel or not ghostModel.Parent then
			cleanup()
			return
		end

		local elapsed = (os.clock() - startTime) * playbackSpeed

		if elapsed >= dataDuration then
			cleanup()
			return
		end

		-- フレーム検索
		local frameA, frameB
		for i = 1, #data - 1 do
			if data[i].Time <= elapsed and data[i + 1].Time >= elapsed then
				frameA = data[i]
				frameB = data[i + 1]
				break
			end
		end

		if frameA and frameB and frameA.RelCFrame and frameB.RelCFrame then
			-- 移動の補間
			local duration = frameB.Time - frameA.Time
			local alpha = (elapsed - frameA.Time) / duration
			local relativeCF = frameA.RelCFrame:Lerp(frameB.RelCFrame, alpha)
			local targetCFrame = originCFrame:ToWorldSpace(relativeCF)

			ghostModel:PivotTo(targetCFrame + heightCorrection)

			-- =============================================
			-- ★ 武器（Tool）の同期処理
			-- =============================================
			local toolName = frameA.EquippedTool
			local currentTool = ghostModel:FindFirstChildOfClass("Tool")

			if toolName then
				if not currentTool or currentTool.Name ~= toolName then
					if currentTool then
						currentTool:Destroy()
					end
					if ToolsFolder then
						local sourceTool = ToolsFolder:FindFirstChild(toolName)
						if sourceTool then
							local newTool = sourceTool:Clone()
							newTool.Parent = ghostModel
							currentTool = newTool -- 更新
						end
					end
				end

				-- ★攻撃の再生
				if frameA.IsAttacking and currentTool then
					currentTool:Activate() -- これで攻撃モーションなどが再生される
				end
			else
				if currentTool then
					currentTool:Destroy()
				end
			end
			-- =============================================
		end
	end)
end

return GhostPlayback

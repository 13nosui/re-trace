local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- サーバーからのイベントを受け取る準備
local floorEvent = ReplicatedStorage:WaitForChild("OnFloorChanged")
local player = Players.LocalPlayer

-- UIの作成
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReTraceHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local floorLabel = Instance.new("TextLabel")
floorLabel.Name = "FloorLabel"
floorLabel.Parent = screenGui

-- デザイン設定
floorLabel.AnchorPoint = Vector2.new(0, 1)
floorLabel.Position = UDim2.new(0.05, 0, 0.95, 0)
floorLabel.Size = UDim2.new(0, 200, 0, 50)
floorLabel.BackgroundTransparency = 1
floorLabel.TextColor3 = Color3.new(1, 1, 1)
floorLabel.TextStrokeTransparency = 0.5
floorLabel.Font = Enum.Font.GothamMedium
floorLabel.TextSize = 32
floorLabel.TextXAlignment = Enum.TextXAlignment.Left
floorLabel.Text = "Floor: --"

-- イベント受信時の処理
floorEvent.OnClientEvent:Connect(function(currentFloor)
	floorLabel.Text = string.format("Floor: %02d", currentFloor)

	-- 1. 一人称モードに固定
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	-- 2. カメラの向きを強制的に「後ろ」に向ける
	local character = player.Character
	if character then
		local rootPart = character:WaitForChild("HumanoidRootPart", 1)
		if rootPart then
			local camera = workspace.CurrentCamera

			-- 現在の「カメラタイプ」を一時的にScriptableにする（自由に動かせるように）
			local originalType = camera.CameraType
			camera.CameraType = Enum.CameraType.Scriptable

			-- プレイヤーの足元の座標
			local rootPos = rootPart.Position
			-- 「後ろ」を見るためのターゲット座標（Z軸のプラス方向を見るかマイナスを見るかはドアの向きによりますが、今回は反転させたいので）
			-- rootPart.CFrame.LookVector * -1 で「背後」のベクトルが取れます
			local backwardLook = rootPart.CFrame.LookVector * -1
			local targetPos = rootPos + backwardLook * 10 -- 背後10スタッドの地点

			-- カメラの位置と向きを設定
			-- 位置: プレイヤーの目の位置 (Y+1.5くらい)
			-- 向き: targetPosを見る
			camera.CFrame = CFrame.lookAt(rootPos + Vector3.new(0, 1.5, 0), targetPos)

			-- 一瞬待ってからCustom（追従モード）に戻すことで、向きを維持しつつ操作可能にする
			task.wait()
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end)

return {}

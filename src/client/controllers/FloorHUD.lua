local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- サーバーからのイベントを受け取る準備
local floorEvent = ReplicatedStorage:WaitForChild("OnFloorChanged")
local player = Players.LocalPlayer

-- UIの作成（ScreenGuiとTextLabel）
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ReTraceHUD"
screenGui.ResetOnSpawn = false -- リスポーンしても消えないようにする
screenGui.Parent = playerGui

local floorLabel = Instance.new("TextLabel")
floorLabel.Name = "FloorLabel"
floorLabel.Parent = screenGui

-- デザイン設定（ミニマルに）
floorLabel.AnchorPoint = Vector2.new(0, 1) -- 左下基準
floorLabel.Position = UDim2.new(0.05, 0, 0.95, 0) -- 画面左下（少し余白あり）
floorLabel.Size = UDim2.new(0, 200, 0, 50)
floorLabel.BackgroundTransparency = 1 -- 背景透明
floorLabel.TextColor3 = Color3.new(1, 1, 1) -- 白文字
floorLabel.TextStrokeTransparency = 0.5 -- 文字の縁取り（背景に溶け込まないように）
floorLabel.Font = Enum.Font.GothamMedium -- モダンなフォント
floorLabel.TextSize = 32
floorLabel.TextXAlignment = Enum.TextXAlignment.Left
floorLabel.Text = "Floor: --" -- 初期表示

-- イベント受信時の処理
floorEvent.OnClientEvent:Connect(function(currentFloor)
	-- "01" のようにゼロ埋めして表示
	floorLabel.Text = string.format("Floor: %02d", currentFloor)
end)

return {}

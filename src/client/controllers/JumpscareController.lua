-- src/client/controllers/JumpscareController.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ★ 設定: ここを好きな怖い素材のIDに書き換えてください！
-- 例: Toolboxで "Scary Face" や "Scream" で検索し、Asset IDをコピーする
local IMAGE_ID = "rbxassetid://109235729734704" -- (例: 怖い顔の画像)
local SOUND_ID = "rbxassetid://91232411976994" -- (例: 女性の悲鳴)

-- GUIの作成 (スクリプトで自動生成します)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "JumpscareGUI"
screenGui.IgnoreGuiInset = true -- 画面端まで埋める
screenGui.Parent = playerGui
screenGui.Enabled = false -- 最初は隠しておく

local imageLabel = Instance.new("ImageLabel")
imageLabel.Size = UDim2.new(1, 0, 1, 0)
imageLabel.BackgroundColor3 = Color3.new(0, 0, 0)
imageLabel.Image = IMAGE_ID
imageLabel.ImageTransparency = 0 -- 最初は見えている状態
imageLabel.Parent = screenGui

-- 音の作成
local sound = Instance.new("Sound")
sound.SoundId = SOUND_ID
sound.Volume = 2.0 -- 爆音注意
sound.Parent = workspace

-- 事前読み込み（いざという時にロード待ちにならないように）
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ imageLabel, sound })
	end)
end)

-- イベントの受信準備
local jumpscareEvent = ReplicatedStorage:WaitForChild("OnJumpscare", 10)

if jumpscareEvent then
	jumpscareEvent.OnClientEvent:Connect(function()
		-- 1. 演出開始
		screenGui.Enabled = true
		sound:Play()

		-- カメラを激しく揺らす演出（オプション）
		local camera = workspace.CurrentCamera
		local originalCFrame = camera.CFrame
		local shakeDuration = 0.5
		local startTime = os.clock()

		task.spawn(function()
			while os.clock() - startTime < shakeDuration do
				local dx = math.random() * 2 - 1
				local dy = math.random() * 2 - 1
				camera.CFrame = camera.CFrame * CFrame.new(dx, dy, 0)
				task.wait()
			end
		end)

		-- 2. フェードアウト（2秒かけて暗転）
		-- 画像を徐々に黒くするのではなく、黒いフレームを被せるなどの処理でも良いが
		-- ここではシンプルに2.5秒後に消す
		task.wait(2.5)
		screenGui.Enabled = false
	end)
end

return {}

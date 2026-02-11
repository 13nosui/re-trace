-- src/client/controllers/GameUIController.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService") -- ★ 追加: アニメーション用

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local requestStartEvent = ReplicatedStorage:WaitForChild("RequestStartGame")
local jumpscareEvent = ReplicatedStorage:WaitForChild("OnJumpscare")
local gameClearEvent = ReplicatedStorage:WaitForChild("OnGameClear")

local oldGui = playerGui:FindFirstChild("GameUI")
if oldGui then
	oldGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameUI"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100 -- ★ 追加: 「Floor: 09」などより確実に前に出すため
screenGui.Parent = playerGui

-----------------------------------------
-- タイトル画面の作成
-----------------------------------------
local titleFrame = Instance.new("Frame")
titleFrame.Size = UDim2.new(1, 0, 1, 0)
titleFrame.BackgroundColor3 = Color3.new(0.05, 0.05, 0.05)
titleFrame.Parent = screenGui

local titleModal = Instance.new("TextButton")
titleModal.Size = UDim2.new(1, 0, 1, 0)
titleModal.BackgroundTransparency = 1
titleModal.Text = ""
titleModal.Modal = true
titleModal.ZIndex = 0
titleModal.Parent = titleFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "Re: Trace"
titleLabel.Font = Enum.Font.Creepster
titleLabel.TextColor3 = Color3.new(0.8, 0, 0)
titleLabel.TextScaled = true
titleLabel.TextWrapped = true
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
titleLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Parent = titleFrame

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MaxTextSize = 400
titleConstraint.Parent = titleLabel

local playButton = Instance.new("TextButton")
playButton.Text = "ゲーム開始 ␣"
playButton.Font = Enum.Font.GothamBold
playButton.TextColor3 = Color3.new(1, 1, 1)
playButton.TextScaled = true
playButton.AnchorPoint = Vector2.new(0.5, 0.5)
playButton.Size = UDim2.new(0.2, 0, 0.06, 0)
playButton.Position = UDim2.new(0.5, 0, 0.7, 0)
playButton.BackgroundColor3 = Color3.new(0.15, 0, 0)
playButton.Parent = titleFrame

local playStroke = Instance.new("UIStroke")
playStroke.Color = Color3.new(0.5, 0, 0)
playStroke.Thickness = 2
playStroke.Parent = playButton

-----------------------------------------
-- ゲームオーバー画面の作成
-----------------------------------------
local gameOverFrame = Instance.new("Frame")
gameOverFrame.Size = UDim2.new(1, 0, 1, 0)
gameOverFrame.BackgroundColor3 = Color3.new(0, 0, 0)
gameOverFrame.Visible = false
gameOverFrame.Parent = screenGui

local gameOverModal = Instance.new("TextButton")
gameOverModal.Size = UDim2.new(1, 0, 1, 0)
gameOverModal.BackgroundTransparency = 1
gameOverModal.Text = ""
gameOverModal.Modal = true
gameOverModal.ZIndex = 0
gameOverModal.Parent = gameOverFrame

local gameOverLabel = Instance.new("TextLabel")
gameOverLabel.Text = "GAME OVER"
gameOverLabel.Font = Enum.Font.Creepster
gameOverLabel.TextColor3 = Color3.new(1, 0, 0)
gameOverLabel.TextScaled = true
gameOverLabel.TextWrapped = true
gameOverLabel.AnchorPoint = Vector2.new(0.5, 0.5)
gameOverLabel.Size = UDim2.new(1, 0, 0.4, 0)
gameOverLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
gameOverLabel.BackgroundTransparency = 1
gameOverLabel.Parent = gameOverFrame

local gameOverConstraint = Instance.new("UITextSizeConstraint")
gameOverConstraint.MaxTextSize = 400
gameOverConstraint.Parent = gameOverLabel

local returnButton = Instance.new("TextButton")
returnButton.Text = "タイトルへ戻る ␣"
returnButton.Font = Enum.Font.GothamBold
returnButton.TextColor3 = Color3.new(1, 1, 1)
returnButton.TextScaled = true
returnButton.AnchorPoint = Vector2.new(0.5, 0.5)
returnButton.Size = UDim2.new(0.2, 0, 0.06, 0)
returnButton.Position = UDim2.new(0.5, 0, 0.7, 0)
returnButton.BackgroundColor3 = Color3.new(0.15, 0, 0)
returnButton.Parent = gameOverFrame

local returnStroke = Instance.new("UIStroke")
returnStroke.Color = Color3.new(0.5, 0, 0)
returnStroke.Thickness = 2
returnStroke.Parent = returnButton

-----------------------------------------
-- ゲームクリア（脱出成功）画面の作成
-----------------------------------------
local gameClearFrame = Instance.new("Frame")
gameClearFrame.Size = UDim2.new(1, 0, 1, 0)
gameClearFrame.BackgroundColor3 = Color3.new(1, 1, 1)
gameClearFrame.BackgroundTransparency = 1 -- ★ 最初は透明
gameClearFrame.Visible = false
gameClearFrame.Parent = screenGui

local gameClearModal = Instance.new("TextButton")
gameClearModal.Size = UDim2.new(1, 0, 1, 0)
gameClearModal.BackgroundTransparency = 1
gameClearModal.Text = ""
gameClearModal.Modal = true
gameClearModal.ZIndex = 0
gameClearModal.Parent = gameClearFrame

local gameClearLabel = Instance.new("TextLabel")
gameClearLabel.Text = "ESCAPED"
gameClearLabel.Font = Enum.Font.GothamBold
gameClearLabel.TextColor3 = Color3.new(0, 0, 0)
gameClearLabel.TextScaled = true
gameClearLabel.TextWrapped = true
gameClearLabel.TextTransparency = 1 -- ★ 最初は透明
gameClearLabel.AnchorPoint = Vector2.new(0.5, 0.5)
gameClearLabel.Size = UDim2.new(1, 0, 0.2, 0)
gameClearLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
gameClearLabel.BackgroundTransparency = 1
gameClearLabel.Parent = gameClearFrame

local gameClearConstraint = Instance.new("UITextSizeConstraint")
gameClearConstraint.MaxTextSize = 200
gameClearConstraint.Parent = gameClearLabel

local clearReturnButton = Instance.new("TextButton")
clearReturnButton.Text = "タイトルへ戻る ␣"
clearReturnButton.Font = Enum.Font.GothamBold
clearReturnButton.TextColor3 = Color3.new(1, 1, 1)
clearReturnButton.TextScaled = true
clearReturnButton.TextTransparency = 1 -- ★ 最初は透明
clearReturnButton.BackgroundTransparency = 1 -- ★ 最初は透明
clearReturnButton.AnchorPoint = Vector2.new(0.5, 0.5)
clearReturnButton.Size = UDim2.new(0.2, 0, 0.06, 0)
clearReturnButton.Position = UDim2.new(0.5, 0, 0.7, 0)
clearReturnButton.BackgroundColor3 = Color3.new(0.15, 0.15, 0.15)
clearReturnButton.Parent = gameClearFrame

local clearReturnStroke = Instance.new("UIStroke")
clearReturnStroke.Color = Color3.new(0.5, 0.5, 0.5)
clearReturnStroke.Thickness = 2
clearReturnStroke.Transparency = 1 -- ★ 最初は透明
clearReturnStroke.Parent = clearReturnButton

-----------------------------------------
-- ロジック
-----------------------------------------
local function hideInventory()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end
end

local function showInventory()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
end

local function startGame()
	if not titleFrame.Visible then
		return
	end
	titleFrame.Visible = false
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	showInventory()
	requestStartEvent:FireServer()
end

local function returnToTitle()
	gameOverFrame.Visible = false
	gameClearFrame.Visible = false

	-- ★ 次のゲームクリアに備えて透明度をリセット
	gameClearFrame.BackgroundTransparency = 1
	gameClearLabel.TextTransparency = 1
	clearReturnButton.BackgroundTransparency = 1
	clearReturnButton.TextTransparency = 1
	clearReturnStroke.Transparency = 1

	titleFrame.Visible = true
	hideInventory()
end

playButton.MouseButton1Click:Connect(startGame)
returnButton.MouseButton1Click:Connect(returnToTitle)
clearReturnButton.MouseButton1Click:Connect(returnToTitle)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Space then
		if titleFrame.Visible then
			startGame()
		elseif gameOverFrame.Visible or gameClearFrame.Visible then
			returnToTitle()
		end
	end
end)

jumpscareEvent.OnClientEvent:Connect(function()
	hideInventory()
	task.wait(2.5)
	player.CameraMode = Enum.CameraMode.Classic
	gameOverFrame.Visible = true
end)

-- ★ 変更: フェードインアニメーションの実装
gameClearEvent.OnClientEvent:Connect(function()
	hideInventory()
	player.CameraMode = Enum.CameraMode.Classic
	gameClearFrame.Visible = true

	-- 2秒かけて画面全体を真っ白にする
	local bgTween = TweenService:Create(
		gameClearFrame,
		TweenInfo.new(2.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0 }
	)
	bgTween:Play()

	bgTween.Completed:Wait() -- 真っ白になるまで待つ

	-- その後、1秒かけて文字とボタンを浮かび上がらせる
	local textTweenInfo = TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(gameClearLabel, textTweenInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(clearReturnButton, textTweenInfo, { BackgroundTransparency = 0.15, TextTransparency = 0 })
		:Play()
	TweenService:Create(clearReturnStroke, textTweenInfo, { Transparency = 0 }):Play()
end)

player.CameraMode = Enum.CameraMode.Classic

task.spawn(function()
	task.wait(0.5)
	hideInventory()
end)

return {}

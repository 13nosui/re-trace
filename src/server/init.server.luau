local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- 作成したモジュールを読み込む
-- ※Rojoの構造に合わせてパスは適宜調整されますが、通常は以下でアクセス可能です
local GhostRecorder = require(ServerScriptService.Server.services.GhostRecorder)
local GhostPlayback = require(ServerScriptService.Server.services.GhostPlayback)

local ROOM_folder = workspace:WaitForChild("CurrentRoom")
local ENTRANCE_part = ROOM_folder:WaitForChild("Entrance")
local GHOST_template = ReplicatedStorage:WaitForChild("Ghost")

-- プレイヤーが参加したらテスト開始
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		print("🎥 録画開始: 5秒間動いてください！")

		-- 1. 録画開始
		GhostRecorder.StartRecording(player, ENTRANCE_part)

		-- 5秒後に録画停止＆再生
		task.wait(5)

		print("🛑 録画終了 & 再生準備")
		local recordedData = GhostRecorder.StopRecording(player)

		-- 2. ゴーストを生成
		local ghost = GHOST_template:Clone()
		ghost.Parent = workspace
		-- ゴーストを初期位置（記録の最初のフレーム）に移動させる処理を入れるとより丁寧ですが、
		-- いったんPlay関数に任せます。

		print("👻 ゴースト再生開始")
		GhostPlayback.Play(ghost, recordedData, ENTRANCE_part)
	end)
end)

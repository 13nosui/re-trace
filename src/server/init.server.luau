local ServerScriptService = game:GetService("ServerScriptService")

-- サービスの読み込み
local RoomManager = require(ServerScriptService.Server.services.RoomManager)
-- local GhostRecorder = require(ServerScriptService.Server.services.GhostRecorder) -- 後で使います

print("🚀 ゲームサーバー起動")

-- プレイヤーが参加したときの処理
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- キャラクターがスポーンしたら、最初の部屋へ送るなどの処理をここに書く予定
		-- 現状は RoomManager が初期部屋を作ってあればOK
	end)
end)

-- ゲームループ開始（部屋の生成など）
RoomManager.Init()

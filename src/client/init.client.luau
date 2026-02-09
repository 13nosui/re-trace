local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Controllersフォルダの中身を自動で読み込む（あるいは個別にrequireする）
-- 今回は個別にrequireします
local FloorHUD = require(script.controllers.FloorHUD)

print("✅ Client initialized")

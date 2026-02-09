--!strict
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RoomManager = {}

local roomTemplate = ServerStorage:WaitForChild("RoomTemplate") :: Model
local currentRoom: Model? = nil
local isProcessingDoor = false

--- 新しい部屋を生成し、古い部屋を削除する
function RoomManager.NextRoom(player: Player?)
	if currentRoom then
		currentRoom:Destroy()
	end

	local newRoom = roomTemplate:Clone()
	newRoom.Name = "CurrentRoom"
	newRoom.Parent = Workspace
	currentRoom = newRoom

	RoomManager.SetupDoorEvents(newRoom)

	if player and player.Character then
		local entrance = newRoom:FindFirstChild("Entrance") :: BasePart?
		if entrance then
			-- Entranceの少し前方にテレポート
			local spawnCFrame = entrance.CFrame * CFrame.new(0, 0, -5)
			player.Character:SetPrimaryPartCFrame(spawnCFrame)
		end
	end
end

--- ドアの接触判定をセットアップする
function RoomManager.SetupDoorEvents(room: Model)
	local entrance = room:FindFirstChild("Entrance") :: BasePart?
	local exit = room:FindFirstChild("Exit") :: BasePart?

	local function onTouched(hit: BasePart, doorType: "Entrance" | "Exit")
		if isProcessingDoor then
			return
		end

		local character = hit.Parent
		if not character then
			return
		end
		local player = game.Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		isProcessingDoor = true
		RoomManager.CheckAnswer(player, doorType)

		task.delay(1, function()
			isProcessingDoor = false
		end)
	end

	if entrance then
		entrance.Touched:Connect(function(hit)
			onTouched(hit, "Entrance")
		end)
	end

	if exit then
		exit.Touched:Connect(function(hit)
			onTouched(hit, "Exit")
		end)
	end
end

--- プレイヤーの選択を判定する
function RoomManager.CheckAnswer(player: Player, doorType: "Entrance" | "Exit")
	if doorType == "Exit" then
		print("✅ 正解！次の部屋へ")
		RoomManager.NextRoom(player)
	else
		print("❌ 不正解... 最初から")
		-- TODO: 最初からやり直す処理（一旦テレポートのみ）
		RoomManager.NextRoom(player)
	end
end

--- 初期化処理
function RoomManager.Init()
	RoomManager.NextRoom()
end

return RoomManager

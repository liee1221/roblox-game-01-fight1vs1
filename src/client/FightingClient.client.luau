-- FightingClient (LocalScript, StarterGui)
-- Client side of Fight 1vs1: menus, HUD, 2D side-view camera, input.
-- The client only presents the game and sends intended actions; the server
-- owns combat, damage, and win/lose. Nothing here can grant a hit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FightAction = ReplicatedStorage:WaitForChild("FightAction")
local FightUpdate = ReplicatedStorage:WaitForChild("FightUpdate")

local ARENA = Config.ARENA
local WEAPONS = Config.WEAPONS
local LEVELS = Config.LEVELS

-- Match state on this client.
local inMatch = false
local laneZ = 0
local selectedLevel = 1
local selectedWeapon = "Katana"
local currentWeapon = "Katana"
local unlockedLevel = 1
local counterFlashUntil = 0

--------------------------------------------------------------------------------
-- Small UI helpers.
--------------------------------------------------------------------------------

local function new(className, props, parent)
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function corner(inst, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 10) }, inst)
	return inst
end

local function button(text, size, position, parent, bg, textColor, fontSize)
	local b = new("TextButton", {
		Text = text,
		Size = size,
		Position = position,
		BackgroundColor3 = bg or Color3.fromRGB(40, 44, 70),
		TextColor3 = textColor or Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = fontSize or 20,
		BorderSizePixel = 0,
		AutoButtonColor = true,
	}, parent)
	corner(b, 10)
	return b
end

local function label(text, size, position, parent, color, fontSize)
	return new("TextLabel", {
		Text = text,
		Size = size,
		Position = position,
		BackgroundTransparency = 1,
		TextColor3 = color or Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = fontSize or 20,
		TextWrapped = true,
	}, parent)
end

local function frame(size, position, parent, bg, transparency)
	return new("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = bg or Color3.fromRGB(20, 22, 40),
		BackgroundTransparency = transparency or 0,
		BorderSizePixel = 0,
	}, parent)
end

local function bar(parent, size, position, bg)
	local outer = frame(size, position, parent, Color3.fromRGB(15, 15, 25), 0.25)
	corner(outer, 8)
	local inner = new("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = bg,
		BorderSizePixel = 0,
	}, outer)
	corner(inner, 8)
	return outer, inner
end

--------------------------------------------------------------------------------
-- Root GUI and screens.
--------------------------------------------------------------------------------

local gui = new("ScreenGui", {
	Name = "FightGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
}, playerGui)

local MainMenu = frame(UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), gui, Color3.fromRGB(10, 10, 20), 0.35)
label("1 vs 1 Battle", UDim2.new(0, 600, 0, 80), UDim2.new(0.5, -300, 0.12, 0), MainMenu,
	Color3.fromRGB(255, 210, 40), 56)
label("1v1 Battle Hard Game", UDim2.new(0, 600, 0, 30), UDim2.new(0.5, -300, 0.24, 0), MainMenu,
	Color3.fromRGB(220, 220, 230), 20)
local StartButton = button("START", UDim2.new(0, 260, 0, 70), UDim2.new(0.5, -130, 0.55, 0),
	MainMenu, Color3.fromRGB(200, 40, 45), Color3.fromRGB(255, 255, 255), 30)
local GuideButton = button("PANDUAN", UDim2.new(0, 260, 0, 55), UDim2.new(0.5, -130, 0.68, 0),
	MainMenu, Color3.fromRGB(45, 48, 80), Color3.fromRGB(200, 200, 220), 22)

local Guide = frame(UDim2.new(0, 520, 0, 380), UDim2.new(0.5, -260, 0.5, -190), gui,
	Color3.fromRGB(22, 24, 46), 0)
Guide.Visible = false
corner(Guide, 14)
label("PANDUAN", UDim2.new(1, 0, 0, 50), UDim2.new(0, 0, 0, 10), Guide,
	Color3.fromRGB(255, 210, 40), 28)
label("Serang: Klik / Q = serangan ringan, E = pukulan kuat\nTangkis: tahan F untuk menahan serangan musuh\nCounter: tekan C tepat setelah menangkis\nUltimate: tekan R saat meter ULTIMATE penuh\nJatuh keluar arena = kalah. Kalahkan AI untuk\nmembuka level berikutnya!", UDim2.new(1, -40, 0, 200), UDim2.new(0, 20, 0, 70), Guide,
	Color3.fromRGB(230, 230, 240), 18)
local GuideClose = button("TUTUP", UDim2.new(0, 160, 0, 50), UDim2.new(0.5, -80, 1, -70),
	Guide, Color3.fromRGB(200, 40, 45), Color3.fromRGB(255, 255, 255), 20)

local LevelSelect = frame(UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), gui, Color3.fromRGB(10, 10, 20), 0.35)
LevelSelect.Visible = false
label("PILIH LEVEL", UDim2.new(0, 600, 0, 60), UDim2.new(0.5, -300, 0.08, 0), LevelSelect,
	Color3.fromRGB(255, 210, 40), 44)
local LevelCards = {}
do
	local cardW, gap = 150, 16
	local totalW = 5 * cardW + 4 * gap
	for i = 1, 5 do
		local x = (0.5 - totalW / 2 / 1280) -- placeholder, set below by scale
		local card = frame(UDim2.new(0, cardW, 0, 210), UDim2.new(0.5, -totalW / 2 + (i - 1) * (cardW + gap), 0.3, 0),
			LevelSelect, Color3.fromRGB(45, 48, 80), 0)
		corner(card, 12)
		label("LEVEL " .. i, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 14), card,
			Color3.fromRGB(255, 210, 40), 20)
		local nameLabel = label(LEVELS[i].Name, UDim2.new(1, -10, 0, 50), UDim2.new(0, 5, 0, 55), card,
			Color3.fromRGB(240, 240, 250), 16)
		local lockLabel = label("TERKUNCI", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 120), card,
			Color3.fromRGB(255, 120, 120), 18)
		lockLabel.Visible = false
		local face = label("( ^-^ )", UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 0, 155), card,
			Color3.fromRGB(255, 150, 160), 18)
		LevelCards[i] = { card = card, name = nameLabel, lock = lockLabel, face = face }
		-- Clicking an unlocked card picks that level and opens weapon select.
		local click = new("TextButton", {
			Text = "",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			TextTransparency = 1,
		}, card)
		click.MouseButton1Click:Connect(function()
			if i <= unlockedLevel then
				selectedLevel = i
				showWeaponSelect()
			end
		end)
	end
end
local LevelBack = button("KEMBALI", UDim2.new(0, 220, 0, 55), UDim2.new(0.5, -110, 0.82, 0),
	LevelSelect, Color3.fromRGB(200, 40, 45), Color3.fromRGB(255, 255, 255), 20)

local WeaponSelect = frame(UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), gui, Color3.fromRGB(10, 10, 20), 0.35)
WeaponSelect.Visible = false
label("PILIH SENJATA", UDim2.new(0, 600, 0, 60), UDim2.new(0.5, -300, 0.08, 0), WeaponSelect,
	Color3.fromRGB(255, 210, 40), 44)
label("Senjata andalanmu — pilih satu, lalu bertarung!",
	UDim2.new(0, 600, 0, 30), UDim2.new(0.5, -300, 0.17, 0), WeaponSelect,
	Color3.fromRGB(220, 220, 230), 18)
local WeaponButtons = {}
do
	local order = Config.WeaponOrder()
	for i, key in ipairs(order) do
		local def = WEAPONS[key]
		local b = button(def.DisplayName, UDim2.new(0, 220, 0, 90), UDim2.new(0.5, -110, 0.3 + (i - 1) * 0.16, 0),
			WeaponSelect, Color3.fromRGB(45, 48, 80), def.Color, 26)
		local desc = label(def.Description .. "  |  Ultimate: " .. def.UltimateName,
			UDim2.new(0, 420, 0, 24), UDim2.new(0.5, -210, 0.3 + (i - 1) * 0.16 + 0.115, 0),
			WeaponSelect, Color3.fromRGB(210, 210, 225), 15)
		WeaponButtons[key] = b
		b.MouseButton1Click:Connect(function()
			selectedWeapon = key
			currentWeapon = key
			startFight()
		end)
	end
end
local WeaponBack = button("KEMBALI", UDim2.new(0, 220, 0, 55), UDim2.new(0.5, -110, 0.82, 0),
	WeaponSelect, Color3.fromRGB(200, 40, 45), Color3.fromRGB(255, 255, 255), 20)

--------------------------------------------------------------------------------
-- HUD (visible during a fight).
--------------------------------------------------------------------------------

local HUD = frame(UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), gui, Color3.fromRGB(0, 0, 0), 1)
HUD.Visible = false

-- Player HP (top left, green) + ultimate meter under it.
local PlayerHPOuter, PlayerHPInner = bar(HUD, UDim2.new(0, 320, 0, 26), UDim2.new(0, 12, 0, 12),
	Color3.fromRGB(60, 220, 90))
local UltOuter, UltInner = bar(HUD, UDim2.new(0, 320, 0, 14), UDim2.new(0, 12, 0, 46),
	Color3.fromRGB(255, 200, 40))
label("ULTIMATE", UDim2.new(0, 320, 0, 16), UDim2.new(0, 12, 0, 62), HUD,
	Color3.fromRGB(255, 210, 40), 12)

-- Enemy HP (top right, red).
local EnemyHPOuter, EnemyHPInner = bar(HUD, UDim2.new(0, 320, 0, 26), UDim2.new(1, -332, 0, 12),
	Color3.fromRGB(235, 50, 50))
label("MUSUH", UDim2.new(0, 320, 0, 20), UDim2.new(1, -332, 0, 40), HUD,
	Color3.fromRGB(255, 120, 120), 14)

-- Center announcement ("FIGHT!", "VICTORY!", ...).
local Announce = label("", UDim2.new(0, 600, 0, 90), UDim2.new(0.5, -300, 0.35, 0), HUD,
	Color3.fromRGB(255, 60, 60), 64)
Announce.Visible = false

-- Equipped weapon label (top center).
local WeaponLabel = label("KATANA", UDim2.new(0, 300, 0, 26), UDim2.new(0.5, -150, 0, 14), HUD,
	Color3.fromRGB(140, 220, 255), 20)

-- Action buttons (bottom right): TANGKIS [F], COUNTER [C], PUKUL KUAT [E].
local BlockButton = button("TANGKIS\n[F]", UDim2.new(0, 110, 0, 60), UDim2.new(1, -380, 1, -80),
	HUD, Color3.fromRGB(50, 110, 230), Color3.fromRGB(255, 255, 255), 16)
local CounterButton = button("COUNTER\n[C]", UDim2.new(0, 110, 0, 60), UDim2.new(1, -260, 1, -80),
	HUD, Color3.fromRGB(200, 160, 40), Color3.fromRGB(255, 255, 255), 16)
local HeavyButton = button("PUKUL KUAT\n[E]", UDim2.new(0, 110, 0, 60), UDim2.new(1, -140, 1, -80),
	HUD, Color3.fromRGB(200, 40, 45), Color3.fromRGB(255, 255, 255), 16)

-- Light attack hint (bottom left).
label("Klik / Q: serangan ringan   |   R: ultimate", UDim2.new(0, 420, 0, 24), UDim2.new(0, 12, 1, -36),
	HUD, Color3.fromRGB(220, 220, 230), 14)

--------------------------------------------------------------------------------
-- End screen.
--------------------------------------------------------------------------------

local EndScreen = frame(UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), gui, Color3.fromRGB(10, 10, 20), 0.35)
EndScreen.Visible = false
local EndTitle = label("VICTORY!", UDim2.new(0, 600, 0, 80), UDim2.new(0.5, -300, 0.25, 0), EndScreen,
	Color3.fromRGB(255, 210, 40), 56)
local EndSub = label("", UDim2.new(0, 600, 0, 30), UDim2.new(0.5, -300, 0.38, 0), EndScreen,
	Color3.fromRGB(230, 230, 240), 20)
local RematchButton = button("MAIN LAGI", UDim2.new(0, 240, 0, 60), UDim2.new(0.5, -250, 0.55, 0),
	EndScreen, Color3.fromRGB(200, 40, 45), Color3.fromRGB(255, 255, 255), 22)
local LevelsButton = button("PILIH LEVEL", UDim2.new(0, 240, 0, 60), UDim2.new(0.5, 10, 0.55, 0),
	EndScreen, Color3.fromRGB(45, 48, 80), Color3.fromRGB(255, 255, 255), 22)

--------------------------------------------------------------------------------
-- Screen switching. (Defined as globals because the level/weapon buttons
-- built above call showWeaponSelect/startFight from their click handlers.)
--------------------------------------------------------------------------------

local function hideAll()
	MainMenu.Visible = false
	Guide.Visible = false
	LevelSelect.Visible = false
	WeaponSelect.Visible = false
	HUD.Visible = false
	EndScreen.Visible = false
end

function showMainMenu()
	hideAll()
	MainMenu.Visible = true
end

local function refreshLevelCards()
	for i, card in ipairs(LevelCards) do
		local locked = i > unlockedLevel
		card.lock.Visible = locked
		card.card.BackgroundColor3 = locked
			and Color3.fromRGB(35, 36, 55)
			or Color3.fromRGB(45, 48, 80)
	end
end

function showLevelSelect()
	hideAll()
	refreshLevelCards()
	LevelSelect.Visible = true
end

function showWeaponSelect()
	hideAll()
	WeaponSelect.Visible = true
end

local function setHP(inner, fraction)
	inner.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
end

local function setMeter(fraction)
	UltInner.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
end

local announceUntil = 0
local function announce(text, color)
	Announce.Text = text
	Announce.TextColor3 = color or Color3.fromRGB(255, 60, 60)
	Announce.Visible = true
	announceUntil = os.clock() + 1.1
end

function startFight()
	hideAll()
	HUD.Visible = true
	WeaponLabel.Text = (WEAPONS[selectedWeapon] or WEAPONS.Katana).DisplayName
	WeaponLabel.TextColor3 = (WEAPONS[selectedWeapon] or WEAPONS.Katana).Color
	setHP(PlayerHPInner, 1)
	setHP(EnemyHPInner, 1)
	setMeter(0)
	FightAction:FireServer("StartMatch", selectedLevel, selectedWeapon)
end

local function showEnd(won, reason, unlocked)
	hideAll()
	EndScreen.Visible = true
	if won then
		EndTitle.Text = "VICTORY!"
		EndTitle.TextColor3 = Color3.fromRGB(255, 210, 40)
		EndSub.Text = "Level " .. tostring(selectedLevel) .. " selesai! Level " .. tostring(unlocked) .. " terbuka."
	else
		EndTitle.Text = "DEFEAT"
		EndTitle.TextColor3 = Color3.fromRGB(255, 70, 70)
		if reason == "Fell" then
			EndSub.Text = "Kamu jatuh keluar arena. Coba lagi!"
		else
			EndSub.Text = "AI menang ronde ini. Coba lagi!"
		end
	end
end

--------------------------------------------------------------------------------
-- Button wiring.
--------------------------------------------------------------------------------

StartButton.MouseButton1Click:Connect(function()
	showLevelSelect()
end)

GuideButton.MouseButton1Click:Connect(function()
	Guide.Visible = true
end)

GuideClose.MouseButton1Click:Connect(function()
	Guide.Visible = false
end)

LevelBack.MouseButton1Click:Connect(function()
	showMainMenu()
end)

WeaponBack.MouseButton1Click:Connect(function()
	showLevelSelect()
end)

RematchButton.MouseButton1Click:Connect(function()
	startFight()
end)

LevelsButton.MouseButton1Click:Connect(function()
	showLevelSelect()
end)

--------------------------------------------------------------------------------
-- Combat input. Light = click / Q, Heavy = E, Block = hold F,
-- Counter = C, Ultimate = R. Buttons mirror the same actions.
--------------------------------------------------------------------------------

local blocking = false

local function setBlocking(value)
	if blocking == value then
		return
	end
	blocking = value
	FightAction:FireServer("Block", value)
	BlockButton.BackgroundColor3 = value
		and Color3.fromRGB(30, 70, 180)
		or Color3.fromRGB(50, 110, 230)
end

local function doLight()
	if inMatch then
		FightAction:FireServer("Light")
	end
end

local function doHeavy()
	if inMatch then
		FightAction:FireServer("Heavy")
	end
end

local function doCounter()
	if inMatch then
		FightAction:FireServer("Counter")
	end
end

local function doUltimate()
	if inMatch then
		FightAction:FireServer("Ultimate")
	end
end

HeavyButton.MouseButton1Click:Connect(doHeavy)
CounterButton.MouseButton1Click:Connect(doCounter)

BlockButton.MouseButton1Down:Connect(function()
	setBlocking(true)
end)
BlockButton.MouseButton1Up:Connect(function()
	setBlocking(false)
end)
BlockButton.MouseButton1Click:Connect(function()
	-- A tap on touch devices still counts as a brief block.
	setBlocking(true)
	task.delay(0.25, function()
		setBlocking(false)
	end)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not inMatch then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		doLight()
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Q then
			doLight()
		elseif input.KeyCode == Enum.KeyCode.E then
			doHeavy()
		elseif input.KeyCode == Enum.KeyCode.F then
			setBlocking(true)
		elseif input.KeyCode == Enum.KeyCode.C then
			doCounter()
		elseif input.KeyCode == Enum.KeyCode.R then
			doUltimate()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.F then
		setBlocking(false)
	end
end)

--------------------------------------------------------------------------------
-- Finding the AI: the server names every AI model "AIFighter". Pick the one
-- in this client's lane (closest Z, then closest X).
--------------------------------------------------------------------------------

local function findAI()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best = nil
	local bestScore = math.huge
	for _, model in ipairs(Workspace:GetChildren()) do
		if model.Name == "AIFighter" and model:IsA("Model") then
			local aiRoot = model:FindFirstChild("HumanoidRootPart")
			if aiRoot then
				local score = math.abs(aiRoot.Position.Z - laneZ) * 10
					+ math.abs(aiRoot.Position.X - root.Position.X)
				if score < bestScore then
					bestScore = score
					best = model
				end
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- 2D side-view camera + movement clamp. Runs every frame while in a match:
-- the camera sits behind the stage (fixed Z offset) and follows the midpoint
-- of the two fighters; the character is clamped to the lane and kept facing
-- the AI.
--------------------------------------------------------------------------------

local camera = Workspace.CurrentCamera

RunService.RenderStepped:Connect(function()
	if not inMatch then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Clamp to the stage and the lane, face the AI.
	local ai = findAI()
	local faceAngle = 0
	if ai then
		local aiRoot = ai:FindFirstChild("HumanoidRootPart")
		if aiRoot then
			faceAngle = aiRoot.Position.X >= root.Position.X and -math.pi / 2 or math.pi / 2
		end
	end
	local clampedX = math.clamp(root.Position.X, -ARENA.HalfWidth, ARENA.HalfWidth)
	root.CFrame = CFrame.new(clampedX, root.Position.Y, laneZ)
		* CFrame.Angles(0, faceAngle, 0)

	-- Side-view camera: behind the stage, looking at the fighters' midpoint.
	local midX = clampedX
	if ai then
		local aiRoot = ai:FindFirstChild("HumanoidRootPart")
		if aiRoot then
			midX = (clampedX + aiRoot.Position.X) / 2
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(midX, ARENA.FloorY + ARENA.CameraHeight, laneZ + ARENA.CameraDistance)
		* CFrame.Angles(0, 0, 0)
	camera.CFrame = CFrame.lookAt(
		Vector3.new(midX, ARENA.FloorY + ARENA.CameraHeight, laneZ + ARENA.CameraDistance),
		Vector3.new(midX, ARENA.FloorY + 2, laneZ)
	)

	if announceUntil > 0 and os.clock() >= announceUntil then
		announceUntil = 0
		Announce.Visible = false
	end
	if counterFlashUntil > 0 then
		local on = os.clock() < counterFlashUntil
		CounterButton.BackgroundColor3 = on
			and Color3.fromRGB(255, 210, 40)
			or Color3.fromRGB(200, 160, 40)
		if not on then
			counterFlashUntil = 0
		end
	end
end)

--------------------------------------------------------------------------------
-- Server updates.
--------------------------------------------------------------------------------

FightUpdate.OnClientEvent:Connect(function(kind, data)
	data = data or {}
	if kind == "ShowMenu" then
		inMatch = false
		camera.CameraType = Enum.CameraType.Custom
		showMainMenu()
	elseif kind == "MatchStart" then
		inMatch = true
		laneZ = data.laneZ or 0
		currentWeapon = data.weapon or selectedWeapon
		WeaponLabel.Text = (WEAPONS[currentWeapon] or WEAPONS.Katana).DisplayName
		WeaponLabel.TextColor3 = (WEAPONS[currentWeapon] or WEAPONS.Katana).Color
		setHP(PlayerHPInner, (data.playerHealth or 100) / 100)
		setHP(EnemyHPInner, (data.enemyHealth or 100) / 100)
		setMeter(0)
		announce("FIGHT!", Color3.fromRGB(255, 60, 60))
	elseif kind == "Health" then
		setHP(PlayerHPInner, (data.playerHealth or 0) / 100)
		setHP(EnemyHPInner, (data.enemyHealth or 0) / 100)
	elseif kind == "Ultimate" then
		setMeter((data.meter or 0) / 100)
	elseif kind == "CounterReady" then
		counterFlashUntil = os.clock() + 0.9
	elseif kind == "MatchEnd" then
		inMatch = false
		setBlocking(false)
		camera.CameraType = Enum.CameraType.Custom
		if data.unlocked then
			unlockedLevel = data.unlocked
		end
		showEnd(data.won, data.reason, data.unlocked or unlockedLevel)
	end
end)

-- If the character respawns mid-menu, keep the camera default.
player.CharacterAdded:Connect(function()
	if not inMatch then
		camera.CameraType = Enum.CameraType.Custom
	end
end)

showMainMenu()

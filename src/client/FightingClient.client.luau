--[[
	FightingClient (LocalScript)
	- Kamera 2D side-view
	- Navigasi menu (MainMenu, Panduan, LevelSelect, EndScreen)
	- Input tombol + keyboard
	- Update HUD (HP, ultimate meter, senjata)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage.Remotes
local StartLevelEvent = Remotes.StartLevel
local CombatInputEvent = Remotes.CombatInput
local EquipWeaponEvent = Remotes.EquipWeapon
local GameEvent = Remotes.GameEvent

local gui = player:WaitForChild("PlayerGui"):WaitForChild("FightingUI")
local mainMenu = gui:WaitForChild("MainMenu")
local guidePanel = gui:WaitForChild("GuidePanel")
local levelSelect = gui:WaitForChild("LevelSelect")
local endScreen = gui:WaitForChild("EndScreen")
local hud = gui:WaitForChild("HUD")

local playerHP = hud:WaitForChild("PlayerHP")
local enemyHP = hud:WaitForChild("EnemyHP")
local meterFill = hud:WaitForChild("MeterFrame"):WaitForChild("MeterBg"):WaitForChild("MeterFill")
local countdownLabel = hud:WaitForChild("CountdownLabel")
local ultimateBtn = hud:WaitForChild("ActionPanel"):WaitForChild("UltimateBtn")

-- ===== Navigasi menu =====

local function showOnly(screen)
	mainMenu.Visible = (screen == "MainMenu")
	guidePanel.Visible = (screen == "GuidePanel")
	levelSelect.Visible = (screen == "LevelSelect")
	endScreen.Visible = (screen == "EndScreen")
	hud.Visible = (screen == "HUD")
end

local function refreshLevelSelect()
	local unlocked = player:GetAttribute("UnlockedLevel") or 1
	local tiles = levelSelect:WaitForChild("Tiles")
	for i = 1, 5 do
		local tile = tiles:FindFirstChild("Level" .. i)
		if tile then
			local lockOverlay = tile:FindFirstChild("LockOverlay")
			if lockOverlay then
				lockOverlay.Visible = (i > unlocked)
			end
			tile.AutoButtonColor = (i <= unlocked)
		end
	end
end

mainMenu:WaitForChild("StartBtn").Activated:Connect(function()
	refreshLevelSelect()
	showOnly("LevelSelect")
end)

mainMenu:WaitForChild("TutorialBtn").Activated:Connect(function()
	showOnly("GuidePanel")
end)

guidePanel:WaitForChild("BackBtn").Activated:Connect(function()
	showOnly("MainMenu")
end)

levelSelect:WaitForChild("BackBtn").Activated:Connect(function()
	showOnly("MainMenu")
end)

local tiles = levelSelect:WaitForChild("Tiles")
for i = 1, 5 do
	local tile = tiles:FindFirstChild("Level" .. i)
	if tile then
		tile.Activated:Connect(function()
			local unlocked = player:GetAttribute("UnlockedLevel") or 1
			if i <= unlocked then
				showOnly("HUD")
				StartLevelEvent:FireServer(i)
			end
		end)
	end
end

-- refresh lock saat unlock berubah
player:GetAttributeChangedSignal("UnlockedLevel"):Connect(function()
	if levelSelect.Visible then refreshLevelSelect() end
end)

-- ===== Input tombol aksi =====

local function bindActionButtons()
	local actionPanel = hud:WaitForChild("ActionPanel")
	for _, btn in actionPanel:GetChildren() do
		if btn:IsA("TextButton") then
			local action = btn:GetAttribute("Action")
			if action == "Block" then
				btn.InputBegan:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
					CombatInputEvent:FireServer("BlockOn")
				end
			end)
			btn.InputEnded:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch then
					CombatInputEvent:FireServer("BlockOff")
				end
			end)
		elseif action then
			btn.Activated:Connect(function()
				CombatInputEvent:FireServer(action)
			end)
		end
		end
	end
end
bindActionButtons()

-- ===== Tombol senjata =====

local function bindWeaponButtons()
	local weaponPanel = hud:WaitForChild("WeaponPanel")
	for _, btn in weaponPanel:GetChildren() do
		if btn:IsA("TextButton") then
			btn.Activated:Connect(function()
				local weapon = btn:GetAttribute("Weapon")
				if weapon then
					EquipWeaponEvent:FireServer(weapon)
			end
		end)
	end
	end
end
bindWeaponButtons()

-- highlight senjata aktif
local function refreshWeaponHighlight()
	local current = player:GetAttribute("Weapon") or "Katana"
	local weaponPanel = hud:FindFirstChild("WeaponPanel")
	if weaponPanel then
		for _, btn in weaponPanel:GetChildren() do
			if btn:IsA("TextButton") then
				local w = btn:GetAttribute("Weapon")
				btn.BackgroundColor3 = (w == current) and Color3.fromRGB(90, 90, 130) or Color3.fromRGB(50, 50, 70)
			end
		end
	end
end
player:GetAttributeChangedSignal("Weapon"):Connect(refreshWeaponHighlight)

-- ===== Keyboard =====

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		CombatInputEvent:FireServer("Punch")
	elseif input.KeyCode == Enum.KeyCode.E then
		CombatInputEvent:FireServer("Heavy")
	elseif input.KeyCode == Enum.KeyCode.R then
		CombatInputEvent:FireServer("Kick")
	elseif input.KeyCode == Enum.KeyCode.F then
		CombatInputEvent:FireServer("BlockOn")
	elseif input.KeyCode == Enum.KeyCode.C then
		CombatInputEvent:FireServer("Counter")
	elseif input.KeyCode == Enum.KeyCode.X then
		CombatInputEvent:FireServer("Ultimate")
	elseif input.KeyCode == Enum.KeyCode.One then
		EquipWeaponEvent:FireServer("Katana")
	elseif input.KeyCode == Enum.KeyCode.Two then
		EquipWeaponEvent:FireServer("Hammer")
	elseif input.KeyCode == Enum.KeyCode.Three then
		EquipWeaponEvent:FireServer("Spear")
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.F then
		CombatInputEvent:FireServer("BlockOff")
	end
end)

-- ===== Animasi prosedural (serangan & pertahanan) =====
-- Menggerakkan sendi (Motor6D) lengan/kaki langsung tiap frame,
-- bekerja untuk karakter R15 player maupun rig AI.

local activeAnims = {}    -- model -> {t0, dur, joints, pose}
local blockingModels = {} -- model -> joints (pose tangkisan ditahan)

local function collectJoints(model)
	local joints = {}
	for _, d in model:GetDescendants() do
		-- Motor6D: rig lama/AI, AnimationConstraint: sistem sendi avatar baru
		if (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) and not joints[d.Name] then
			joints[d.Name] = d
		end
	end
	return joints
end

local function resetJoints(joints)
	for _, j in pairs(joints) do
		if j.Parent then j.Transform = CFrame.new() end
	end
end

local function ang(deg)
	return CFrame.Angles(math.rad(deg), 0, 0)
end

-- pose serangan: fungsi(joints, t) dengan t = 0..1

local function posePunch(j, t)
	local rs, re = j.RightShoulder, j.RightElbow
	if not rs then return end
	if t < 0.3 then
		rs.Transform = ang(-35 * (t / 0.3)) -- tarik tangan ke belakang
	else
		local a = (t - 0.3) / 0.7
		rs.Transform = ang(-35 + 130 * a) -- pukulan lurus ke depan
		if re then re.Transform = ang(-15 * a) end
	end
end

local function poseHeavy(j, t)
	local rs, ls = j.RightShoulder, j.LeftShoulder
	if not (rs and ls) then return end
	if t < 0.45 then
		local a = t / 0.45 -- angkat kedua tangan ke atas-belakang
		rs.Transform = ang(-160 * a)
		ls.Transform = ang(-160 * a)
	else
		local a = (t - 0.45) / 0.55 -- hantaman penuh ke depan-bawah
		rs.Transform = ang(-160 + 270 * a)
		ls.Transform = ang(-160 + 270 * a)
	end
end

local function poseKick(j, t)
	local rh = j.RightHip
	if not rh then return end
	if t < 0.3 then
		rh.Transform = ang(-25 * (t / 0.3)) -- tekuk lutut
	else
		rh.Transform = ang(-25 + 105 * ((t - 0.3) / 0.7)) -- tendangan ke depan
	end
end

local function poseCounter(j, t)
	local rs, ls = j.RightShoulder, j.LeftShoulder
	if not (rs and ls) then return end
	if t < 0.7 then
		rs.Transform = CFrame.Angles(math.rad(70), 0, math.rad(-30)) -- tangan menyilang
		ls.Transform = CFrame.Angles(math.rad(70), 0, math.rad(30))
	else
		local a = (t - 0.7) / 0.3
		rs.Transform = CFrame.Angles(math.rad(70 * (1 - a)), 0, math.rad(-30 * (1 - a)))
		ls.Transform = CFrame.Angles(math.rad(70 * (1 - a)), 0, math.rad(30 * (1 - a)))
	end
end

local function poseUltimate(j, t)
	local rs, ls = j.RightShoulder, j.LeftShoulder
	if rs then rs.Transform = ang(60 + 40 * math.sin(t * math.pi * 8)) end
	if ls then ls.Transform = ang(60 + 40 * math.cos(t * math.pi * 8)) end
end

local function applyBlockPose(joints)
	local rs, ls = joints.RightShoulder, joints.LeftShoulder
	if rs then rs.Transform = CFrame.Angles(math.rad(65), 0, math.rad(-30)) end
	if ls then ls.Transform = CFrame.Angles(math.rad(65), 0, math.rad(30)) end
end

local ANIM_DUR = {
	Punch = 0.28, Heavy = 0.55, Kick = 0.4, Counter = 0.5, Ultimate = 1.2,
}
local ANIM_POSES = {
	Punch = posePunch, Heavy = poseHeavy, Kick = poseKick,
	Counter = poseCounter, Ultimate = poseUltimate,
}

local function playAnim(model, animName)
	if not model or not model.Parent then return end
	if animName == "BlockOn" then
		activeAnims[model] = nil
		blockingModels[model] = collectJoints(model)
	elseif animName == "BlockOff" then
		local joints = blockingModels[model]
		if joints then resetJoints(joints) end
		blockingModels[model] = nil
	else
		local pose = ANIM_POSES[animName]
		if pose then
			activeAnims[model] = {
				t0 = os.clock(),
				dur = ANIM_DUR[animName] or 0.3,
				joints = collectJoints(model),
				pose = pose,
			}
		end
	end
end

-- PENTING: untuk sistem sendi baru (AnimationConstraint), Transform harus
-- ditulis saat PreSimulation (setelah Animator menulis, sebelum diterapkan).
-- Menulis di RenderStepped tidak pernah berefek karena tertimpa Animator.
RunService.PreSimulation:Connect(function()
	local now = os.clock()
	for model, rec in pairs(activeAnims) do
		local t = (now - rec.t0) / rec.dur
		if t >= 1 or not model.Parent then
			resetJoints(rec.joints)
			activeAnims[model] = nil
		else
			rec.pose(rec.joints, t)
		end
	end
	for model, joints in pairs(blockingModels) do
		if model.Parent then
			applyBlockPose(joints)
		else
			blockingModels[model] = nil
		end
	end
end)

-- ===== GameEvent dari server =====

local function announceText(text, duration)
	countdownLabel.Text = text
	task.delay(duration or 1.2, function()
		if countdownLabel.Text == text then
			countdownLabel.Text = ""
		end
	end)
end

GameEvent.OnClientEvent:Connect(function(data)
	if data.type == "Countdown" then
		countdownLabel.Text = tostring(data.value)
	elseif data.type == "Fight" then
		announceText("FIGHT!", 0.9)
	elseif data.type == "Announce" then
		announceText(data.text, 1.2)
	elseif data.type == "Anim" then
		playAnim(data.model, data.anim)
	elseif data.type == "End" then
		local resultLabel = endScreen:WaitForChild("ResultLabel")
		local subLabel = endScreen:WaitForChild("SubLabel")
		local nextBtn = endScreen:WaitForChild("NextBtn")
		local unlocked = player:GetAttribute("UnlockedLevel") or 1
		if data.result == "Victory" then
			resultLabel.Text = "MENANG!"
			resultLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
			subLabel.Text = "Kamu mengalahkan musuh level " .. data.level
			nextBtn.Visible = data.level < 5 and data.level < unlocked
		else
			resultLabel.Text = "KALAH..."
			resultLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			subLabel.Text = "Coba lagi, kamu pasti bisa!"
			nextBtn.Visible = false
		end
		showOnly("EndScreen")
	end
end)

-- ===== Tombol End Screen =====

-- simpan level terakhir yang dimainkan lewat variable sederhana
local lastLevel = 1
local tilesFolder = levelSelect:WaitForChild("Tiles")
for i = 1, 5 do
	local tile = tilesFolder:FindFirstChild("Level" .. i)
	if tile then
		tile.Activated:Connect(function()
			lastLevel = i
		end)
	end
end

endScreen:WaitForChild("RetryBtn").Activated:Connect(function()
	showOnly("HUD")
	StartLevelEvent:FireServer(lastLevel)
end)

endScreen:WaitForChild("NextBtn").Activated:Connect(function()
	showOnly("HUD")
	StartLevelEvent:FireServer(lastLevel + 1)
end)

endScreen:WaitForChild("MenuBtn").Activated:Connect(function()
	refreshLevelSelect()
	showOnly("LevelSelect")
end)

-- ===== Update HUD =====

local function setBar(fill, ratio)
	ratio = math.clamp(ratio, 0, 1)
	fill.Size = UDim2.new(ratio, 0, 1, 0)
end

task.spawn(function()
	while true do
		if hud.Visible then
			-- HP player
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then
				setBar(playerHP.BarBg.BarFill, hum.Health / math.max(hum.MaxHealth, 1))
			end
			-- HP musuh
			local ai = workspace:FindFirstChild("AIFighter")
			local ahum = ai and ai:FindFirstChildOfClass("Humanoid")
			if ahum then
				setBar(enemyHP.BarBg.BarFill, ahum.Health / math.max(ahum.MaxHealth, 1))
			end
			-- Ultimate meter
			local meter = player:GetAttribute("UltimateMeter") or 0
			setBar(meterFill, meter / 100)
			local ready = meter >= 100
			ultimateBtn.BackgroundColor3 = ready and Color3.fromRGB(255, 190, 0) or Color3.fromRGB(120, 90, 20)
		end
		task.wait(0.1)
	end
end)

-- ===== Kamera 2D side-view =====

local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable

RunService.RenderStepped:Connect(function()
	local px = 0
	local char = player.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		px = char.HumanoidRootPart.Position.X
	end
	local ax = px
	local ai = workspace:FindFirstChild("AIFighter")
	if ai and ai:FindFirstChild("HumanoidRootPart") then
		ax = ai.HumanoidRootPart.Position.X
	end
	local mid = math.clamp((px + ax) / 2, -38, 38)
	local target = CFrame.lookAt(Vector3.new(mid, 7, 30), Vector3.new(mid, 5, 0))
	cam.CFrame = cam.CFrame:Lerp(target, 0.08)
end)

showOnly("MainMenu")
refreshWeaponHighlight()
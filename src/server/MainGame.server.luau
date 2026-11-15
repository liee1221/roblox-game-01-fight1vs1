--[[
	MainGame (Server)
	- Alur level: countdown 3-2-1-FIGHT, menang/kalah, unlock level
	- Sistem combat: pukul, pukul kuat, tendang, tangkis, counter, ultimate
	- AI musuh per level
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage.GameConfig)
local Remotes = ReplicatedStorage.Remotes
local StartLevelEvent = Remotes.StartLevel
local CombatInputEvent = Remotes.CombatInput
local EquipWeaponEvent = Remotes.EquipWeapon
local GameEvent = Remotes.GameEvent

local PLAYER_START = CFrame.new(-22, 3.2, 0)
local AI_START = CFrame.new(22, 3.2, 0)

local state = {
	active = false,
	fighting = false,
	player = nil,
	ai = nil,
	level = 0,
}

-- data per petarung
local fighterData = {}

-- ===== Util =====

local function getFighterData(model)
	if model and not fighterData[model] then
		fighterData[model] = {
			cooldowns = {},
			blocking = false,
			counterUntil = 0,
			stunUntil = 0,
			meter = 0,
			weapon = "Katana",
			isAI = false,
		}
	end
	return model and fighterData[model]
end

local function syncMeter(model)
	local fd = fighterData[model]
	if fd and not fd.isAI and state.player and state.player.Character == model then
		state.player:SetAttribute("UltimateMeter", math.floor(fd.meter))
	end
end

local function playAnim(model, animName)
	if state.player then
		GameEvent:FireClient(state.player, {type = "Anim", model = model, anim = animName})
	end
end

local function announce(text)
	if state.player then
		GameEvent:FireClient(state.player, {type = "Announce", text = text})
	end
end

local function hitEffect(position, color, big)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = big and Vector3.new(4, 4, 4) or Vector3.new(1.6, 1.6, 1.6)
	p.Position = position
	p.Anchored = true
	p.CanCollide = false
	p.Parent = workspace
	Debris:AddItem(p, 0.18)
end

local function dealDamage(model, amount)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum.Health = math.max(0, hum.Health - amount)
		local fd = fighterData[model]
		if fd then
			fd.meter = math.min(Config.MeterMax, fd.meter + Config.MeterPerDamage)
			syncMeter(model)
		end
	end
end

-- ===== Visual senjata =====

local function attachWeaponVisual(character, weaponName)
	if not character then return end
	local old = character:FindFirstChild("WeaponVisual")
	if old then old:Destroy() end

	local handle = character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")
	if not handle then return end

	local folder = Instance.new("Folder")
	folder.Name = "WeaponVisual"
	folder.Parent = character

	local function wpart(size, color, material, offset)
		local p = Instance.new("Part")
		p.Size = size
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.Massless = true
		p.CanCollide = false
		p.CFrame = handle.CFrame * CFrame.new(offset)
		p.Parent = folder
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = p
		weld.Parent = p
		return p
	end

	if weaponName == "Katana" then
		wpart(Vector3.new(0.2, 0.2, 4.5), Color3.fromRGB(180, 220, 255), Enum.Material.Neon, Vector3.new(0, 0, 2.2))
		wpart(Vector3.new(0.5, 0.5, 0.7), Color3.fromRGB(40, 40, 40), Enum.Material.Metal, Vector3.new(0, 0, 0.1))
	elseif weaponName == "Hammer" then
		wpart(Vector3.new(0.4, 0.4, 2.2), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, Vector3.new(0, 0, 1.2))
		wpart(Vector3.new(1.7, 1.7, 1.7), Color3.fromRGB(130, 130, 140), Enum.Material.Metal, Vector3.new(0, 0, 2.6))
	elseif weaponName == "Spear" then
		wpart(Vector3.new(0.2, 0.2, 6.5), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, Vector3.new(0, 0, 3.2))
		wpart(Vector3.new(0.4, 0.4, 1), Color3.fromRGB(200, 200, 210), Enum.Material.Neon, Vector3.new(0, 0, 6.8))
	end
end

-- ===== Serangan =====

local function tryAttack(attacker, defender, attackName)
	if not state.fighting then return end
	local fd = getFighterData(attacker)
	local atk = Config.Attacks[attackName]
	if not fd or not atk or not defender then return end

	local now = os.clock()
	if now < fd.stunUntil then return end

	local weapon = Config.Weapons[fd.weapon]
	local cooldown = atk.Cooldown * weapon.CooldownMul
	if fd.cooldowns[attackName] and now - fd.cooldowns[attackName] < cooldown then return end
	fd.cooldowns[attackName] = now

	local hrpA = attacker:FindFirstChild("HumanoidRootPart")
	local hrpD = defender:FindFirstChild("HumanoidRootPart")
	if not (hrpA and hrpD) then return end

	-- hadapkan penyerang ke arah lawan
	hrpA.CFrame = CFrame.lookAt(hrpA.Position, Vector3.new(hrpD.Position.X, hrpA.Position.Y, hrpA.Position.Z))

	-- animasi serangan (tetap dimainkan walau meleset)
	playAnim(attacker, attackName)

	local dist = (hrpA.Position - hrpD.Position).Magnitude
	local range = atk.Range * weapon.RangeMul
	if dist > range then return end -- meleset

	local dfd = getFighterData(defender)
	local dmg = atk.Damage * weapon.DamageMul
	if fd.isAI then
		local lvl = Config.Levels[state.level]
		if lvl then dmg *= lvl.DamageMul end
	end

	if now < dfd.counterUntil then
		-- COUNTER sukses!
		dfd.counterUntil = 0
		fd.stunUntil = now + Config.CounterStun
		dealDamage(attacker, Config.CounterDamage)
		hitEffect(hrpA.Position, Color3.fromRGB(255, 255, 0), true)
		announce("COUNTER!")
	elseif dfd.blocking then
		dealDamage(defender, dmg * Config.BlockDamageMul)
		hitEffect(hrpD.Position, Color3.fromRGB(120, 180, 255))
	else
		dealDamage(defender, dmg)
		hitEffect(hrpD.Position, weapon.Color)
		-- knockback
		local dir = math.sign(hrpD.Position.X - hrpA.Position.X)
		if dir ~= 0 then
			hrpD.AssemblyLinearVelocity = Vector3.new(dir * 10, 5, 0)
		end
	end

	fd.meter = math.min(Config.MeterMax, fd.meter + Config.MeterPerHit)
	syncMeter(attacker)
end

-- ===== Ultimate per senjata =====

local function runUltimate(attacker, defender, weaponName)
	local fd = getFighterData(attacker)
	if not fd or fd.meter < Config.MeterMax or not state.fighting or not defender then return end
	fd.meter = 0
	syncMeter(attacker)
	playAnim(attacker, "Ultimate")

	local humD = defender:FindFirstChildOfClass("Humanoid")
	if not (humD and humD.Health > 0) then return end

	if weaponName == "Katana" then
		announce("BLADE RUSH!")
		for i = 1, 5 do
			if not state.fighting then break end
			local hrpA = attacker:FindFirstChild("HumanoidRootPart")
			local hrpD = defender:FindFirstChild("HumanoidRootPart")
			if not (hrpA and hrpD) then break end
			hrpA.CFrame = CFrame.lookAt(Vector3.new(hrpD.Position.X - 4, hrpA.Position.Y, 0), hrpD.Position)
			dealDamage(defender, 12)
			hitEffect(hrpD.Position, Color3.fromRGB(0, 200, 255), true)
			task.wait(0.18)
		end
	elseif weaponName == "Hammer" then
		announce("EARTHQUAKE!")
		local dfd = getFighterData(defender)
		dfd.stunUntil = os.clock() + 2.5
		local hrpD = defender:FindFirstChild("HumanoidRootPart")
		dealDamage(defender, 45)
		if hrpD then
			hitEffect(hrpD.Position - Vector3.new(0, 2, 0), Color3.fromRGB(255, 150, 50), true)
		end
	elseif weaponName == "Spear" then
		announce("THOUSAND THRUSTS!")
		for i = 1, 8 do
			if not state.fighting then break end
			local hrpD = defender:FindFirstChild("HumanoidRootPart")
			dealDamage(defender, 7)
			if hrpD then hitEffect(hrpD.Position, Color3.fromRGB(120, 255, 120)) end
			task.wait(0.1)
		end
	end
end

-- ===== Buat petarung AI =====

local function createAIFighter(levelCfg)
	local model = Instance.new("Model")
	model.Name = "AIFighter"

	local bodyColor = levelCfg.Color

	local function rpart(name, size, cf, color, collide)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = false
		p.CanCollide = collide == true
		p.CFrame = cf
		p.Parent = model
		return p
	end

	local hrp = rpart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), Color3.new(1, 1, 1), true)
	hrp.Transparency = 1
	local torso = rpart("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0), bodyColor)
	local head = rpart("Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 4.6, 0), Color3.fromRGB(255, 204, 153))
	local band = rpart("Bandana", Vector3.new(1.3, 0.35, 1.3), CFrame.new(0, 5.15, 0), Color3.fromRGB(200, 30, 30))
	local leftArm = rpart("Left Arm", Vector3.new(1, 2, 1), CFrame.new(-1.5, 3, 0), bodyColor)
	local rightArm = rpart("Right Arm", Vector3.new(1, 2, 1), CFrame.new(1.5, 3, 0), bodyColor)
	local legColor = Color3.new(bodyColor.R * 0.6, bodyColor.G * 0.6, bodyColor.B * 0.6)
	local leftLeg = rpart("Left Leg", Vector3.new(1, 2, 1), CFrame.new(-0.5, 1, 0), legColor)
	local rightLeg = rpart("Right Leg", Vector3.new(1, 2, 1), CFrame.new(0.5, 1, 0), legColor)

	-- tubuh & kepala di-weld permanen, anggota gerak pakai Motor6D agar bisa dianimasikan
	for _, p in {torso, head, band} do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hrp
		weld.Part1 = p
		weld.Parent = hrp
	end

	local function motor(name, part)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = hrp
		m.Part1 = part
		m.C0 = hrp.CFrame:Inverse() * part.CFrame
		m.Parent = hrp
	end
	motor("RightShoulder", rightArm)
	motor("LeftShoulder", leftArm)
	motor("RightHip", rightLeg)
	motor("LeftHip", leftLeg)

	local hum = Instance.new("Humanoid")
	hum.HipHeight = 2
	hum.MaxHealth = levelCfg.Health
	hum.Health = levelCfg.Health
	hum.WalkSpeed = levelCfg.WalkSpeed
	hum.Parent = model

	model.PrimaryPart = hrp
	model.Parent = workspace
	return model
end

-- ===== AI otak =====

local function startAI(aiModel, playerChar, levelCfg)
	task.spawn(function()
		local fd = getFighterData(aiModel)
		local hum = aiModel:FindFirstChildOfClass("Humanoid")
		while state.fighting and aiModel.Parent and hum and hum.Health > 0 do
			local hrpA = aiModel:FindFirstChild("HumanoidRootPart")
			local hrpD = playerChar and playerChar:FindFirstChild("HumanoidRootPart")
			if hrpA and hrpD then
				local dist = (hrpA.Position - hrpD.Position).Magnitude
			local weapon = Config.Weapons[fd.weapon]
			local maxRange = 8 * weapon.RangeMul
			local now = os.clock()
			if now < fd.stunUntil then
				-- pusing, nggak ngapa-ngapain
			elseif dist > maxRange + 2 then
				hum:MoveTo(Vector3.new(hrpD.Position.X, hrpA.Position.Y, 0))
			else
				hum:MoveTo(hrpA.Position)
				local r = math.random()
				if fd.meter >= Config.MeterMax then
				runUltimate(aiModel, playerChar, fd.weapon)
			elseif r < levelCfg.BlockChance then
				fd.blocking = true
				playAnim(aiModel, "BlockOn")
				task.wait(0.9)
				fd.blocking = false
				playAnim(aiModel, "BlockOff")
			elseif r < levelCfg.BlockChance + levelCfg.CounterChance then
				fd.counterUntil = os.clock() + Config.CounterWindow
				playAnim(aiModel, "Counter")
			else
				local roll = math.random()
				local atkName = roll < 0.5 and "Punch" or (roll < 0.8 and "Kick" or "Heavy")
				tryAttack(aiModel, playerChar, atkName)
			end
			end
			end
			task.wait(levelCfg.AttackInterval * (0.7 + math.random() * 0.6))
		end
	end)
end

-- ===== Alur level =====

local function startLevel(player, level)
	if state.active then return end
	local unlocked = player:GetAttribute("UnlockedLevel") or 1
	if level < 1 or level > #Config.Levels or level > unlocked then return end

	local levelCfg = Config.Levels[level]

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	state.active = true
	state.fighting = false
	state.level = level
	state.player = player

	-- reset HP & posisi
	hum.Health = hum.MaxHealth
	char:PivotTo(PLAYER_START)

	-- buat AI
	local ai = createAIFighter(levelCfg)
	ai:PivotTo(AI_START)
	state.ai = ai

	local pfd = getFighterData(char)
	pfd.weapon = player:GetAttribute("Weapon") or "Katana"
	pfd.meter = 0
	syncMeter(char)
	local afd = getFighterData(ai)
	afd.weapon = levelCfg.Weapon
	afd.isAI = true

	attachWeaponVisual(char, pfd.weapon)
	attachWeaponVisual(ai, levelCfg.Weapon)

	local ended = false
	local function endFight(result)
		if ended then return end
		ended = true
		state.fighting = false
		if result == "Victory" then
			local newUnlock = math.min(#Config.Levels, level + 1)
			if (player:GetAttribute("UnlockedLevel") or 1) < newUnlock then
				player:SetAttribute("UnlockedLevel", newUnlock)
			end
		end
		GameEvent:FireClient(player, {type = "End", result = result, level = level})
		task.delay(1.5, function()
			if ai then
				ai.Parent = nil
				fighterData[ai] = nil
			end
			fighterData[char] = nil
			state.ai = nil
			state.active = false
			if player.Parent then
				player:LoadCharacter()
		end
		end)
	end

	hum.Died:Connect(function() endFight("Defeat") end)
	ai:FindFirstChildOfClass("Humanoid").Died:Connect(function() endFight("Victory") end)

	-- watchdog: jatuh dari arena = kalah/ menang
	task.spawn(function()
		while state.fighting do
			local hrpA = ai:FindFirstChild("HumanoidRootPart")
			local hrpP = char:FindFirstChild("HumanoidRootPart")
			if hrpA and hrpA.Position.Y < -15 then dealDamage(ai, 9999) end
			if hrpP and hrpP.Position.Y < -15 then dealDamage(char, 9999) end
			task.wait(0.2)
		end
	end)

	-- countdown 3, 2, 1, FIGHT!
	for i = 3, 1, -1 do
		GameEvent:FireClient(player, {type = "Countdown", value = i})
		task.wait(1)
	end
	GameEvent:FireClient(player, {type = "Fight"})
	state.fighting = true
	startAI(ai, char, levelCfg)
end

-- ===== Event handlers =====

local function initPlayer(player)
	if player:GetAttribute("UnlockedLevel") == nil then player:SetAttribute("UnlockedLevel", 1) end
	if player:GetAttribute("Weapon") == nil then player:SetAttribute("Weapon", "Katana") end
	if player:GetAttribute("UltimateMeter") == nil then player:SetAttribute("UltimateMeter", 0) end
end

Players.PlayerAdded:Connect(initPlayer)
for _, p in Players:GetPlayers() do
	initPlayer(p)
end

StartLevelEvent.OnServerEvent:Connect(function(player, level)
	if typeof(level) == "number" then
		startLevel(player, math.floor(level))
	end
end)

CombatInputEvent.OnServerEvent:Connect(function(player, action)
	local char = player.Character
	local fd = getFighterData(char)
	local ai = state.ai
	if not fd or not state.fighting or not ai then return end

	if action == "BlockOn" then
		fd.blocking = true
		playAnim(char, "BlockOn")
	elseif action == "BlockOff" then
		fd.blocking = false
		playAnim(char, "BlockOff")
	elseif action == "Counter" then
		fd.counterUntil = os.clock() + Config.CounterWindow
		playAnim(char, "Counter")
	elseif action == "Ultimate" then
		runUltimate(char, ai, fd.weapon)
	elseif Config.Attacks[action] then
		tryAttack(char, ai, action)
	end
end)

EquipWeaponEvent.OnServerEvent:Connect(function(player, weaponName)
	if not Config.Weapons[weaponName] then return end
	player:SetAttribute("Weapon", weaponName)
	local char = player.Character
	local fd = getFighterData(char)
	if fd then
		fd.weapon = weaponName
		attachWeaponVisual(char, weaponName)
	end
end)

return "MainGame siap."
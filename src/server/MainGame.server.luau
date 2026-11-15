-- MainGame (Script, ServerScriptService)
-- Server side of Fight 1vs1: a 2D side-view arena fighter, player vs AI.
-- Owns the arena, the AI opponent, combat validation, damage, blocking,
-- counters, ultimates, win/lose, and level unlocks. The client only sends
-- intended actions; the server decides what actually lands.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("GameConfig"))

local ARENA = Config.ARENA
local WEAPONS = Config.WEAPONS
local LEVELS = Config.LEVELS

--------------------------------------------------------------------------------
-- RemoteEvents
--------------------------------------------------------------------------------

local FightAction = Instance.new("RemoteEvent")
FightAction.Name = "FightAction" -- client -> server: intended actions
FightAction.Parent = ReplicatedStorage

local FightUpdate = Instance.new("RemoteEvent")
FightUpdate.Name = "FightUpdate" -- server -> client: match state
FightUpdate.Parent = ReplicatedStorage

--------------------------------------------------------------------------------
-- Arena: built at runtime so the place file stays tiny.
-- One long stage on X; matches run in parallel lanes along Z.
--------------------------------------------------------------------------------

local ArenaFolder = Instance.new("Folder")
ArenaFolder.Name = "FightArena"
ArenaFolder.Parent = Workspace

local function makePart(name, size, cframe, color, material, anchored)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = anchored ~= false
	part.CanCollide = true
	part.Parent = ArenaFolder
	return part
end

local function buildArena()
	-- Main floor: dark stage with a neon center line.
	makePart("Floor", Vector3.new(ARENA.HalfWidth * 2 + 8, 2, ARENA.LaneCount * ARENA.LaneSpacing + 16),
		CFrame.new(0, ARENA.FloorY - 1, 0), Color3.fromRGB(24, 28, 52), Enum.Material.Slate)
	local center = makePart("CenterLine", Vector3.new(ARENA.HalfWidth * 2 + 8, 0.2, 0.6),
		CFrame.new(0, ARENA.FloorY + 0.1, 0), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
	center.CanCollide = false

	-- End walls so fighters cannot walk off the sides.
	makePart("WallLeft", Vector3.new(2, 24, ARENA.LaneCount * ARENA.LaneSpacing + 16),
		CFrame.new(-ARENA.HalfWidth - 4, ARENA.FloorY + 12, 0), Color3.fromRGB(30, 34, 64), Enum.Material.Slate)
	makePart("WallRight", Vector3.new(2, 24, ARENA.LaneCount * ARENA.LaneSpacing + 16),
		CFrame.new(ARENA.HalfWidth + 4, ARENA.FloorY + 12, 0), Color3.fromRGB(30, 34, 64), Enum.Material.Slate)

	-- Back wall with glowing red strips and pillars, one per lane gap.
	makePart("BackWall", Vector3.new(ARENA.HalfWidth * 2 + 8, 22, 2),
		CFrame.new(0, ARENA.FloorY + 11, -(ARENA.LaneCount * ARENA.LaneSpacing + 16) / 2 - 1),
		Color3.fromRGB(18, 20, 44), Enum.Material.Slate)
	for x = -ARENA.HalfWidth, ARENA.HalfWidth, 16 do
		local strip = makePart("NeonStrip", Vector3.new(10, 0.6, 0.4),
			CFrame.new(x, ARENA.FloorY + 8, -(ARENA.LaneCount * ARENA.LaneSpacing + 16) / 2 + 0.2),
			Color3.fromRGB(255, 60, 70), Enum.Material.Neon)
		strip.CanCollide = false
		local strip2 = makePart("NeonStripLow", Vector3.new(10, 0.6, 0.4),
			CFrame.new(x, ARENA.FloorY + 3, -(ARENA.LaneCount * ARENA.LaneSpacing + 16) / 2 + 0.2),
			Color3.fromRGB(255, 60, 70), Enum.Material.Neon)
		strip2.CanCollide = false
	end
	for i = 0, ARENA.LaneCount do
		local z = -ARENA.LaneCount * ARENA.LaneSpacing / 2 + i * ARENA.LaneSpacing
		makePart("Pillar", Vector3.new(2, 22, 2),
			CFrame.new(0, ARENA.FloorY + 11, z - ARENA.LaneSpacing / 2),
			Color3.fromRGB(30, 34, 64), Enum.Material.Slate)
	end
end

buildArena()

-- Lane Z positions, one per parallel match.
local Lanes = {}
for i = 1, ARENA.LaneCount do
	Lanes[i] = {
		z = -ARENA.LaneCount * ARENA.LaneSpacing / 2 + (i - 0.5) * ARENA.LaneSpacing,
		busy = false,
	}
end

local function takeLane()
	for i, lane in ipairs(Lanes) do
		if not lane.busy then
			lane.busy = true
			return i, lane.z
		end
	end
	return nil, nil
end

local function freeLane(index)
	if Lanes[index] then
		Lanes[index].busy = false
	end
end

--------------------------------------------------------------------------------
-- R6 fighter rig for the AI opponent, built from parts.
-- Uses the standard R6 joint layout so the Humanoid walks and fights.
--------------------------------------------------------------------------------

local function motor6d(name, part0, part1, c0, c1)
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = c1
	joint.Parent = part0
	return joint
end

local function limb(name, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = false
	part.CanCollide = true
	return part
end

-- Builds a simple R6-style fighter. `origin` is the CFrame of the feet on the
-- floor; the rig stands 5 studs tall. Returns the Model.
local function buildFighter(name, bodyColor, headColor)
	local model = Instance.new("Model")
	model.Name = name

	local root = limb("HumanoidRootPart", Vector3.new(2, 2, 1), bodyColor)
	root.CanCollide = false
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model

	local torso = limb("Torso", Vector3.new(2, 2, 1), bodyColor)
	torso.CFrame = CFrame.new(0, 3, 0)
	torso.Parent = model

	local head = limb("Head", Vector3.new(2, 1, 2), headColor)
	head.CFrame = CFrame.new(0, 4.5, 0)
	head.Parent = model

	local leftArm = limb("Left Arm", Vector3.new(1, 2, 1), bodyColor)
	leftArm.CFrame = CFrame.new(-1.5, 3, 0)
	leftArm.Parent = model

	local rightArm = limb("Right Arm", Vector3.new(1, 2, 1), bodyColor)
	rightArm.CFrame = CFrame.new(1.5, 3, 0)
	rightArm.Parent = model

	local leftLeg = limb("Left Leg", Vector3.new(1, 2, 1), bodyColor)
	leftLeg.CFrame = CFrame.new(-0.5, 1, 0)
	leftLeg.Parent = model

	local rightLeg = limb("Right Leg", Vector3.new(1, 2, 1), bodyColor)
	rightLeg.CFrame = CFrame.new(0.5, 1, 0)
	rightLeg.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.DisplayName = name
	humanoid.Parent = model

	-- Standard R6 joints (canonical C0/C1).
	motor6d("RootJoint", torso, root,
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor6d("Neck", torso, head,
		CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0),
		CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor6d("Right Shoulder", torso, rightArm,
		CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor6d("Left Shoulder", torso, leftArm,
		CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0),
		CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor6d("Right Hip", torso, rightLeg,
		CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor6d("Left Hip", torso, leftLeg,
		CFrame.new(-1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0),
		CFrame.new(-0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))

	model.PrimaryPart = root
	return model
end

--------------------------------------------------------------------------------
-- Weapon visuals: a small model welded to the fighter's right hand.
-- R15 hands are called "RightHand", R6 arms are "Right Arm".
--------------------------------------------------------------------------------

local function buildWeaponModel(weaponName)
	local def = WEAPONS[weaponName] or WEAPONS.Katana
	local model = Instance.new("Model")
	model.Name = weaponName

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.35, 1.6, 0.35)
	handle.Color = Color3.fromRGB(60, 45, 30)
	handle.Material = Enum.Material.Wood
	handle.Anchored = false
	handle.CanCollide = false
	handle.Parent = model

	if weaponName == "Katana" then
		local blade = Instance.new("Part")
		blade.Name = "Blade"
		blade.Size = Vector3.new(0.18, 3.2, 0.7)
		blade.Color = Color3.fromRGB(220, 235, 255)
		blade.Material = Enum.Material.Metal
		blade.Anchored = false
		blade.CanCollide = false
		blade.CFrame = handle.CFrame * CFrame.new(0, 2.3, 0)
		blade.Parent = model
	elseif weaponName == "Palu" then
		local headPart = Instance.new("Part")
		headPart.Name = "Head"
		headPart.Size = Vector3.new(1.4, 1.1, 1.1)
		headPart.Color = Color3.fromRGB(140, 140, 150)
		headPart.Material = Enum.Material.Metal
		headPart.Anchored = false
		headPart.CanCollide = false
		headPart.CFrame = handle.CFrame * CFrame.new(0, 1.1, 0)
		headPart.Parent = model
	else -- Tombak
		local shaft = Instance.new("Part")
		shaft.Name = "Shaft"
		shaft.Size = Vector3.new(0.25, 4.5, 0.25)
		shaft.Color = Color3.fromRGB(90, 70, 45)
		shaft.Material = Enum.Material.Wood
		shaft.Anchored = false
		shaft.CanCollide = false
		shaft.CFrame = handle.CFrame * CFrame.new(0, 1.5, 0)
		shaft.Parent = model
		local tip = Instance.new("Part")
		tip.Name = "Tip"
		tip.Size = Vector3.new(0.3, 1.0, 0.3)
		tip.Color = def.Color
		tip.Material = Enum.Material.Metal
		tip.Anchored = false
		tip.CanCollide = false
		tip.CFrame = handle.CFrame * CFrame.new(0, 4.1, 0)
		tip.Parent = model
	end

	-- Weld every part to the handle so the model moves as one piece.
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= handle then
			local weld = Instance.new("Weld")
			weld.Part0 = handle
			weld.Part1 = part
			weld.C0 = handle.CFrame:Inverse() * part.CFrame
			weld.Parent = handle
		end
	end
	model.PrimaryPart = handle
	return model
end

local function attachWeapon(character, weaponName)
	if not character then
		return nil
	end
	local arm = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not arm then
		return nil
	end
	local old = character:FindFirstChild("FightWeapon")
	if old then
		old:Destroy()
	end
	local weapon = buildWeaponModel(weaponName)
	weapon.Name = "FightWeapon"
	weapon.Parent = character
	local handle = weapon.PrimaryPart
	local weld = Instance.new("Weld")
	weld.Name = "WeaponWeld"
	weld.Part0 = arm
	weld.Part1 = handle
	-- Hold the weapon out to the side, blade pointing forward.
	weld.C0 = CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.rad(-90))
	weld.Parent = arm
	return weapon
end

local function detachWeapon(character)
	if not character then
		return
	end
	local old = character:FindFirstChild("FightWeapon")
	if old then
		old:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Match state: one match per player, each in its own lane.
--------------------------------------------------------------------------------

local Matches = {} -- [Player] = match table
local Unlocked = {} -- [Player] = highest unlocked level index (1..5)
local Wins = {} -- [Player] = total wins

local function getMatch(player)
	return Matches[player]
end

local function laneZFor(match)
	return Lanes[match.laneIndex].z
end

-- Brief slash flash at a position so hits read clearly.
local function slashEffect(position, color)
	local flash = Instance.new("Part")
	flash.Name = "SlashFlash"
	flash.Size = Vector3.new(3, 0.4, 0.4)
	flash.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(45))
	flash.Color = color or Color3.fromRGB(255, 255, 255)
	flash.Material = Enum.Material.Neon
	flash.Anchored = true
	flash.CanCollide = false
	flash.Parent = ArenaFolder
	task.delay(0.18, function()
		flash:Destroy()
	end)
end

local function applyKnockback(model, directionX, power)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(directionX * power, math.max(velocity.Y, 2), 0)
end

local function addUltimate(match, amount)
	match.meter = math.clamp(match.meter + amount, 0, 100)
	FightUpdate:FireClient(match.player, "Ultimate", { meter = match.meter })
end

local function sendHealth(match)
	FightUpdate:FireClient(match.player, "Health", {
		playerHealth = match.playerHealth,
		enemyHealth = match.enemyHealth,
	})
end

local function hurtAI(match, damage, knockDir, knockPower, isUltimate)
	if not match.active then
		return
	end
	if match.aiBlocking and math.random() < 0.5 then
		damage = damage * 0.35 -- the AI blocked part of it
	end
	match.enemyHealth = math.max(0, match.enemyHealth - damage)
	if match.aiModel then
		applyKnockback(match.aiModel, knockDir, knockPower)
		local root = match.aiModel:FindFirstChild("HumanoidRootPart")
		if root then
			slashEffect(root.Position + Vector3.new(0, 3, 0),
				(WEAPONS[match.weapon] or WEAPONS.Katana).Color)
		end
	end
	addUltimate(match, Config.PLAYER.UltimateGainOnHit)
	sendHealth(match)
	if match.enemyHealth <= 0 then
		endMatch(match, true, "KO")
	end
end

local function hurtPlayer(match, damage, knockDir, knockPower)
	if not match.active then
		return
	end
	local now = os.clock()
	if match.blocking then
		damage = damage * (1 - Config.PLAYER.BlockReduction)
		-- A blocked hit opens the counter window.
		match.counterUntil = now + Config.PLAYER.CounterWindow
		FightUpdate:FireClient(match.player, "CounterReady", {})
	end
	match.playerHealth = math.max(0, match.playerHealth - damage)
	local character = match.player.Character
	if character then
		applyKnockback(character, knockDir, knockPower)
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			slashEffect(root.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 60, 60))
		end
	end
	addUltimate(match, Config.PLAYER.UltimateGainOnTake)
	sendHealth(match)
	if match.playerHealth <= 0 then
		endMatch(match, false, "KO")
	end
end

local function cleanupMatch(match)
	if match.aiModel then
		match.aiModel:Destroy()
		match.aiModel = nil
	end
	if match.aiLoop then
		match.aiLoop = false
	end
	freeLane(match.laneIndex)
	detachWeapon(match.player.Character)
	Matches[match.player] = nil
end

function endMatch(match, won, reason)
	if not match.active then
		return
	end
	match.active = false
	local player = match.player
	local levelIndex = match.levelIndex
	if won then
		Wins[player] = (Wins[player] or 0) + 1
		Unlocked[player] = math.max(Unlocked[player] or 1, math.min(levelIndex + 1, #LEVELS))
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local winsStat = leaderstats:FindFirstChild("Wins")
			if winsStat then
				winsStat.Value = Wins[player]
			end
			local levelStat = leaderstats:FindFirstChild("Level")
			if levelStat then
				levelStat.Value = Unlocked[player]
			end
		end
	end
	FightUpdate:FireClient(player, "MatchEnd", {
		won = won,
		reason = reason,
		level = levelIndex,
		unlocked = Unlocked[player] or 1,
		wins = Wins[player] or 0,
	})
	-- Leave the scene up for a beat so the end screen lands, then clean up.
	task.delay(1.5, function()
		cleanupMatch(match)
	end)
end

local function startMatch(player, levelIndex, weaponName)
	if Matches[player] then
		return -- already in a match
	end
	levelIndex = math.clamp(levelIndex or 1, 1, #LEVELS)
	if levelIndex > (Unlocked[player] or 1) then
		return -- level still locked
	end
	if not WEAPONS[weaponName] then
		weaponName = "Katana"
	end
	local laneIndex, laneZ = takeLane()
	if not laneIndex then
		return -- stage full
	end
	local level = LEVELS[levelIndex]
	local character = player.Character
	if not character then
		freeLane(laneIndex)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		freeLane(laneIndex)
		return
	end

	-- Spawn the AI on the opposite side of the lane.
	local ai = buildFighter("AIFighter", Color3.fromRGB(70, 75, 110), Color3.fromRGB(220, 200, 170))
	ai.Parent = Workspace
	local aiHumanoid = ai:FindFirstChildOfClass("Humanoid")
	aiHumanoid.MaxHealth = level.EnemyHealth
	aiHumanoid.Health = level.EnemyHealth
	aiHumanoid.WalkSpeed = level.EnemySpeed
	ai:PivotTo(CFrame.new(ARENA.SpawnGap / 2, ARENA.FloorY, laneZ))
	attachWeapon(ai, level.EnemyWeapon)

	-- Place the player on the other side, facing the AI.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(-ARENA.SpawnGap / 2, ARENA.FloorY + 3, laneZ)
	end
	humanoid.Health = Config.PLAYER.Health
	humanoid.WalkSpeed = Config.PLAYER.WalkSpeed
	attachWeapon(character, weaponName)

	local match = {
		player = player,
		levelIndex = levelIndex,
		weapon = weaponName,
		laneIndex = laneIndex,
		laneZ = laneZ,
		aiModel = ai,
		aiHumanoid = aiHumanoid,
		enemyHealth = level.EnemyHealth,
		playerHealth = Config.PLAYER.Health,
		meter = 0,
		active = true,
		blocking = false,
		aiBlocking = false,
		counterUntil = 0,
		lastAttack = 0,
		lastHeavy = 0,
		lastAIAttack = 0,
		aiLoop = true,
		aiRetreatUntil = 0,
		aiNextThink = 0,
	}
	Matches[player] = match

	FightUpdate:FireClient(player, "MatchStart", {
		level = levelIndex,
		levelName = level.Name,
		weapon = weaponName,
		enemyName = level.Name,
		enemyHealth = level.EnemyHealth,
		playerHealth = Config.PLAYER.Health,
		laneZ = laneZ,
	})

	-- AI brain: one loop per match, cheap enough at 4 lanes.
	task.spawn(function()
		while match.aiLoop and match.active do
			runAIThink(match)
			task.wait(Config.AI.ThinkInterval)
		end
	end)
end

--------------------------------------------------------------------------------
-- Player actions (client -> server). The server validates everything:
-- match active, cooldowns, range, and facing, so a tampered client cannot
-- deal damage it should not deal.
--------------------------------------------------------------------------------

local function facingSign(match)
	-- The player stands left of the AI; attacks go right (+X). If the player
	-- somehow ends up on the other side, attacks go left instead.
	local character = match.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local aiRoot = match.aiModel and match.aiModel:FindFirstChild("HumanoidRootPart")
	if not root or not aiRoot then
		return 1
	end
	if aiRoot.Position.X >= root.Position.X then
		return 1
	else
		return -1
	end
end

local function inRange(match, range)
	local character = match.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local aiRoot = match.aiModel and match.aiModel:FindFirstChild("HumanoidRootPart")
	if not root or not aiRoot then
		return false
	end
	return math.abs(aiRoot.Position.X - root.Position.X) <= range
end

local function onFightAction(player, action, arg1, arg2)
	if action == "StartMatch" then
		startMatch(player, arg1, arg2)
		return
	end
	if action == "LeaveMatch" then
		local match = getMatch(player)
		if match then
			match.active = false
			cleanupMatch(match)
		end
		FightUpdate:FireClient(player, "ShowMenu", {})
		return
	end

	local match = getMatch(player)
	if not match or not match.active then
		return
	end
	local weapon = WEAPONS[match.weapon] or WEAPONS.Katana
	local now = os.clock()

	if action == "Light" then
		if match.blocking then
			return
		end
		if now - match.lastAttack < weapon.Cooldown then
			return
		end
		match.lastAttack = now
		if inRange(match, weapon.Range) then
			hurtAI(match, weapon.Damage, facingSign(match), weapon.Knockback, false)
		end
	elseif action == "Heavy" then
		if match.blocking then
			return
		end
		if now - match.lastHeavy < weapon.HeavyCooldown then
			return
		end
		match.lastHeavy = now
		if inRange(match, weapon.Range + 1) then
			hurtAI(match, weapon.HeavyDamage, facingSign(match), weapon.Knockback + 3, false)
		end
	elseif action == "Block" then
		match.blocking = arg1 == true
	elseif action == "Counter" then
		if now <= match.counterUntil and inRange(match, weapon.Range + 1) then
			match.counterUntil = 0
			match.aiStunnedUntil = now + Config.PLAYER.CounterStun
			hurtAI(match, Config.PLAYER.CounterDamage, facingSign(match), 8, false)
		end
	elseif action == "Ultimate" then
		if match.meter >= 100 and inRange(match, weapon.Range + 3) then
			match.meter = 0
			FightUpdate:FireClient(player, "Ultimate", { meter = 0 })
			hurtAI(match, weapon.UltimateDamage, facingSign(match), 14, true)
		end
	end
end

FightAction.OnServerEvent:Connect(onFightAction)

--------------------------------------------------------------------------------
-- AI brain: chase, attack, block, retreat. Runs per match on a think timer.
--------------------------------------------------------------------------------

function runAIThink(match)
	if not match.active or not match.aiModel then
		return
	end
	local now = os.clock()
	if match.aiStunnedUntil and now < match.aiStunnedUntil then
		return -- stunned by a counter
	end
	local level = LEVELS[match.levelIndex]
	local aiRoot = match.aiModel:FindFirstChild("HumanoidRootPart")
	local character = match.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not aiRoot or not root then
		return
	end
	local aiHumanoid = match.aiHumanoid
	if not aiHumanoid or aiHumanoid.Health <= 0 then
		return
	end

	local dx = root.Position.X - aiRoot.Position.X
	local dist = math.abs(dx)
	local dir = dx >= 0 and 1 or -1

	-- Sometimes the AI raises its guard instead of attacking.
	match.aiBlocking = math.random() < level.EnemyBlockChance and dist <= Config.AI.AttackRange + 2

	if now < match.aiRetreatUntil then
		aiHumanoid:Move(Vector3.new(-dir, 0, 0))
		return
	end
	if dist > Config.AI.AttackRange then
		-- Chase the player along X.
		aiHumanoid:Move(Vector3.new(dir * Config.AI.ChaseSpeedMultiplier, 0, 0))
	else
		aiHumanoid:Move(Vector3.new(0, 0, 0))
		if now - match.lastAIAttack >= level.EnemyCooldown then
			match.lastAIAttack = now
			local heavy = math.random() < Config.AI.HeavyChance
			local damage = heavy and level.EnemyHeavyDamage or level.EnemyDamage
			hurtPlayer(match, damage, dir, heavy and 8 or 4)
			if math.random() < Config.AI.RetreatChance then
				match.aiRetreatUntil = now + Config.AI.RetreatTime
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Watchdog: falling out of the arena loses the match; dead AI ends it.
--------------------------------------------------------------------------------

RunService.Heartbeat:Connect(function()
	for player, match in pairs(Matches) do
		if match.active then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root.Position.Y < ARENA.KillY then
				endMatch(match, false, "Fell")
			elseif match.aiHumanoid and match.aiHumanoid.Health <= 0 then
				endMatch(match, true, "KO")
			end
		end
	end
end)

--------------------------------------------------------------------------------
-- Players: leaderstats, spawn, cleanup.
--------------------------------------------------------------------------------

local function setupPlayer(player)
	Unlocked[player] = 1
	Wins[player] = 0
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local winsStat = Instance.new("IntValue")
	winsStat.Name = "Wins"
	winsStat.Value = 0
	winsStat.Parent = leaderstats
	local levelStat = Instance.new("IntValue")
	levelStat.Name = "Level"
	levelStat.Value = 1
	levelStat.Parent = leaderstats
	leaderstats.Parent = player
	FightUpdate:FireClient(player, "ShowMenu", {})
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		local match = getMatch(player)
		if match and match.active then
			endMatch(match, false, "KO")
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local match = getMatch(player)
	if match then
		match.active = false
		cleanupMatch(match)
	end
	Unlocked[player] = nil
	Wins[player] = nil
end)

-- Players who joined before this script ran.
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

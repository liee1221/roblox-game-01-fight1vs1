-- GameConfig (ModuleScript, ReplicatedStorage)
-- Shared tuning for Fight 1vs1: a 2D side-view arena fighter, player vs AI.
-- Both the server (MainGame) and the client (FightingClient) require this module,
-- so weapon numbers and level definitions stay identical on both sides.

local GameConfig = {}

-- The arena is one long stage. Fighters move along X; each match gets its own
-- lane along Z so several players can fight their own AI at the same time.
GameConfig.ARENA = {
	HalfWidth = 40, -- stage runs x = -40 .. 40
	FloorY = 0, -- top surface of the arena floor
	KillY = -25, -- falling below this height counts as a loss
	SpawnGap = 12, -- fighters start this far apart on X
	CameraHeight = 7, -- side-view camera height above the floor
	CameraDistance = 34, -- side-view camera distance behind the stage
	LaneSpacing = 9, -- distance between match lanes on Z
	LaneCount = 4, -- how many parallel lanes the stage holds
}

-- The player character. WalkSpeed is the normal Roblox speed; the client clamps
-- movement to the stage (X inside the arena, Z locked to the match lane).
GameConfig.PLAYER = {
	Health = 100,
	WalkSpeed = 16,
	JumpPower = 50,
	-- Ultimate meter (0..100). Landing hits charges it; taking hits charges it too.
	UltimateGainOnHit = 12,
	UltimateGainOnTake = 6,
	-- Blocking: incoming damage is multiplied by (1 - BlockReduction).
	BlockReduction = 0.65,
	-- Counter: blocking an enemy hit opens this window (seconds) to counter.
	CounterWindow = 0.9,
	CounterDamage = 30,
	CounterStun = 1.2,
}

-- Three weapons. Light = fast, Heavy = slow but big. Range is the max X distance
-- (studs) an attack can connect at. Knockback pushes the victim along X.
GameConfig.WEAPONS = {
	Katana = {
		DisplayName = "KATANA",
		Description = "Fast blade, long reach",
		Damage = 12,
		HeavyDamage = 22,
		Cooldown = 0.45,
		HeavyCooldown = 1.1,
		Range = 7,
		Knockback = 4,
		UltimateName = "BLADE RUSH",
		UltimateDamage = 45,
		Color = Color3.fromRGB(80, 200, 255),
	},
	Palu = {
		DisplayName = "PALU",
		Description = "Heavy hammer, huge hits",
		Damage = 18,
		HeavyDamage = 32,
		Cooldown = 0.8,
		HeavyCooldown = 1.6,
		Range = 5.5,
		Knockback = 9,
		UltimateName = "EARTHQUAKE",
		UltimateDamage = 60,
		Color = Color3.fromRGB(255, 150, 60),
	},
	Tombak = {
		DisplayName = "TOMBAK",
		Description = "Balanced spear, steady reach",
		Damage = 14,
		HeavyDamage = 26,
		Cooldown = 0.6,
		HeavyCooldown = 1.3,
		Range = 8,
		Knockback = 6,
		UltimateName = "PIERCING STORM",
		UltimateDamage = 50,
		Color = Color3.fromRGB(120, 255, 140),
	},
}

-- Five levels. Beating a level unlocks the next one. The AI gets tougher:
-- more health, harder hits, faster attacks, and it blocks more often.
GameConfig.LEVELS = {
	{
		Name = "Rookie Bot",
		EnemyHealth = 100,
		EnemyDamage = 8,
		EnemyHeavyDamage = 14,
		EnemySpeed = 10,
		EnemyCooldown = 1.5,
		EnemyBlockChance = 0.10,
		EnemyWeapon = "Katana",
	},
	{
		Name = "Iron Fist",
		EnemyHealth = 130,
		EnemyDamage = 10,
		EnemyHeavyDamage = 18,
		EnemySpeed = 11,
		EnemyCooldown = 1.3,
		EnemyBlockChance = 0.15,
		EnemyWeapon = "Palu",
	},
	{
		Name = "Blade Master",
		EnemyHealth = 160,
		EnemyDamage = 12,
		EnemyHeavyDamage = 22,
		EnemySpeed = 12,
		EnemyCooldown = 1.1,
		EnemyBlockChance = 0.20,
		EnemyWeapon = "Katana",
	},
	{
		Name = "Spear Guard",
		EnemyHealth = 190,
		EnemyDamage = 14,
		EnemyHeavyDamage = 26,
		EnemySpeed = 13,
		EnemyCooldown = 1.0,
		EnemyBlockChance = 0.25,
		EnemyWeapon = "Tombak",
	},
	{
		Name = "Shadow Champion",
		EnemyHealth = 230,
		EnemyDamage = 17,
		EnemyHeavyDamage = 30,
		EnemySpeed = 14,
		EnemyCooldown = 0.85,
		EnemyBlockChance = 0.30,
		EnemyWeapon = "Palu",
	},
}

-- AI brain tuning. ThinkInterval is how often the AI picks a new action.
GameConfig.AI = {
	ThinkInterval = 0.25,
	AttackRange = 6,
	HeavyChance = 0.25,
	RetreatChance = 0.15,
	RetreatTime = 0.7,
	ChaseSpeedMultiplier = 1.0,
}

-- Helper: the weapon list in a stable order for the weapon-select UI.
function GameConfig.WeaponOrder()
	return { "Katana", "Palu", "Tombak" }
end

-- Helper: level names in order for the level-select UI.
function GameConfig.LevelNames()
	local names = {}
	for i, level in ipairs(GameConfig.LEVELS) do
		names[i] = level.Name
	end
	return names
end

return GameConfig

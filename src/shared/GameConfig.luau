--[[
	GameConfig: konfigurasi senjata, serangan, dan level
	untuk Stick Arena 2D Fighting
]]

local Config = {}

-- ===== SENJATA =====
Config.Weapons = {
	Katana = {
		DisplayName = "KATANA",
		DamageMul = 1.2,
		RangeMul = 1.6,
		CooldownMul = 0.75,
		UltimateName = "BLADE RUSH",
		UltimateDesc = "Tebasan kilat 5x",
		Color = Color3.fromRGB(0, 200, 255),
	},
	Hammer = {
		DisplayName = "PALU",
		DamageMul = 1.6,
		RangeMul = 1.2,
		CooldownMul = 1.4,
		UltimateName = "EARTHQUAKE",
		UltimateDesc = "Gempa bumi, damage besar + stun",
		Color = Color3.fromRGB(255, 150, 50),
	},
	Spear = {
		DisplayName = "TOMBAK",
		DamageMul = 1.1,
		RangeMul = 2.0,
		CooldownMul = 1.1,
		UltimateName = "THOUSAND THRUSTS",
		UltimateDesc = "Tusukan cepat 8x",
		Color = Color3.fromRGB(120, 255, 120),
	},
}

-- ===== SERANGAN DASAR =====
Config.Attacks = {
	Punch = {Cooldown = 0.5, Range = 6, Damage = 8},
	Heavy = {Cooldown = 1.6, Range = 7, Damage = 18},
	Kick  = {Cooldown = 0.9, Range = 8, Damage = 12},
}

Config.BlockDamageMul = 0.2
Config.CounterDamage = 15
Config.CounterStun = 1.2
Config.CounterWindow = 0.7

Config.MeterMax = 100
Config.MeterPerHit = 12
Config.MeterPerDamage = 4

Config.PlayerHealth = 100

-- ===== LEVEL (AI makin kuat) =====
Config.Levels = {
	{Name = "Rookie Bot",     Health = 90,  DamageMul = 0.7,  WalkSpeed = 9,  AttackInterval = 1.5, BlockChance = 0.08, CounterChance = 0.03, Weapon = "Katana", Color = Color3.fromRGB(140, 140, 160)},
	{Name = "Iron Fist",     Health = 110, DamageMul = 0.85, WalkSpeed = 11, AttackInterval = 1.25, BlockChance = 0.12, CounterChance = 0.06, Weapon = "Hammer", Color = Color3.fromRGB(160, 100, 60)},
	{Name = "Blade Master",   Health = 130, DamageMul = 1.0,  WalkSpeed = 12, AttackInterval = 1.05, BlockChance = 0.16, CounterChance = 0.10, Weapon = "Katana", Color = Color3.fromRGB(70, 130, 200)},
	{Name = "Spear Guard",   Health = 150, DamageMul = 1.15, WalkSpeed = 13, AttackInterval = 0.9, BlockChance = 0.20, CounterChance = 0.14, Weapon = "Spear", Color = Color3.fromRGB(90, 160, 90)},
	{Name = "Shadow Champion",Health = 180, DamageMul = 1.3,  WalkSpeed = 14, AttackInterval = 0.75, BlockChance = 0.25, CounterChance = 0.18, Weapon = "Katana", Color = Color3.fromRGB(50, 50, 60)},
}

return Config
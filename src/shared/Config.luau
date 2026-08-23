--!strict
--[[
	Config — jediné místo, kde se ladí celá hra (server i klient).

	Hra: ASMR Studio. Hráč stojí u své stanice, krájí/drtí objekty,
	dostává peníze a XP, kupuje lepší nástroje a materiály a nakonec
	rebirthuje pro trvalý násobič.

	POZOR — zvuky: `SoundId` níže jsou placeholdery. Roblox od audio update
	nedovolí použít cizí nahrané zvuky, takže si vlastní ASMR zvuky nahraj
	přes Creator Dashboard a jejich ID sem doplň. Hra běží i bez nich
	(SoundService zvuk, který se nenačte, jen tiše přeskočí).
]]

local Config = {}

Config.GameName = "ASMR Studio"

-- Základní smyčka ---------------------------------------------------------
Config.Core = {
	StationCount = 12, -- kolik stanic je v hubu (= max hráčů u stolů)
	StationRadius = 46, -- poloměr kruhu, po kterém jsou stanice rozmístěné
	MaxStrikeDistance = 34, -- dál než tohle server ránu neuzná
	ComboWindow = 1.1, -- sekundy na další ránu, jinak combo padá
	ComboStep = 0.06, -- +6 % za každou ránu v kombu
	ComboBaseMax = 2.0, -- základní strop komba (upgrade ho zvedá)
	DestroyBonus = 0.35, -- bonus k hodnotě objektu za jeho dokončení
}

-- Ukládání ---------------------------------------------------------------
Config.Data = {
	StoreName = "ASMRStudio_Player_v1",
	AutosaveInterval = 120,
	MaxRetries = 4,
}

-- Nástroje (čepele) ------------------------------------------------------
-- `Id` se ukládá do DataStore -> nikdy neměnit. Pořadí = pořadí v obchodě.
-- Ceny nejsou odhad: dopočítala je simulace hráče tak, aby odemykání
-- vycházelo na 3 min / 12 min / 38 min / 1,5 h / 3,5 h / 7,5 h aktivního hraní.
Config.Tools = {
	{
		Id = "Plastic",
		Name = "Plastový nůž",
		Price = 0,
		Damage = 1,
		Cooldown = 0.30,
		Level = 1,
		Color = Color3.fromRGB(226, 232, 240),
		Material = Enum.Material.SmoothPlastic,
		SoundId = "rbxassetid://9114625691",
		Pitch = 1.0,
	},
	{
		Id = "Kitchen",
		Name = "Kuchyňský nůž",
		Price = 1170,
		Damage = 3,
		Cooldown = 0.26,
		Level = 3,
		Color = Color3.fromRGB(190, 198, 210),
		Material = Enum.Material.Metal,
		SoundId = "rbxassetid://9114625691",
		Pitch = 1.05,
	},
	{
		Id = "Cleaver",
		Name = "Řeznická sekáčka",
		Price = 41100,
		Damage = 9,
		Cooldown = 0.24,
		Level = 6,
		Color = Color3.fromRGB(160, 170, 185),
		Material = Enum.Material.Metal,
		SoundId = "rbxassetid://9114625691",
		Pitch = 0.9,
	},
	{
		Id = "Katana",
		Name = "Katana",
		Price = 3470000,
		Damage = 26,
		Cooldown = 0.20,
		Level = 10,
		Color = Color3.fromRGB(235, 240, 255),
		Material = Enum.Material.Metal,
		SoundId = "rbxassetid://9114625691",
		Pitch = 1.18,
	},
	{
		Id = "Diamond",
		Name = "Diamantová čepel",
		Price = 142000000,
		Damage = 78,
		Cooldown = 0.17,
		Level = 15,
		Color = Color3.fromRGB(130, 232, 255),
		Material = Enum.Material.Glass,
		SoundId = "rbxassetid://9114625691",
		Pitch = 1.25,
	},
	{
		Id = "Neon",
		Name = "Neonová čepel",
		Price = 6040000000,
		Damage = 240,
		Cooldown = 0.14,
		Level = 22,
		Color = Color3.fromRGB(255, 105, 220),
		Material = Enum.Material.Neon,
		SoundId = "rbxassetid://9114625691",
		Pitch = 1.35,
	},
	{
		Id = "Quantum",
		Name = "Kvantový řezák",
		Price = 108000000000,
		Damage = 900,
		Cooldown = 0.11,
		Level = 30,
		Color = Color3.fromRGB(150, 120, 255),
		Material = Enum.Material.Neon,
		SoundId = "rbxassetid://9114625691",
		Pitch = 1.45,
	},
}

-- Materiály (objekty na stanici) -----------------------------------------
-- Hodnota za bod odolnosti roste 1,6x za tier. Kdyby rostla rychleji,
-- příjem by přeskočil ceny a celý obsah by se vyčerpal za necelou hodinu.
Config.Objects = {
	{
		Id = "Soap",
		Name = "Mýdlo",
		Price = 0,
		Level = 1,
		Integrity = 15,
		Value = 33,
		Xp = 4,
		Color = Color3.fromRGB(255, 226, 168),
		Material = Enum.Material.SmoothPlastic,
		Shape = "Block",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.0,
	},
	{
		Id = "KineticSand",
		Name = "Kinetický písek",
		Price = 3330,
		Level = 2,
		Integrity = 60,
		Value = 210,
		Xp = 7,
		Color = Color3.fromRGB(226, 196, 148),
		Material = Enum.Material.Sand,
		Shape = "Cylinder",
		SoundId = "rbxassetid://9125402735",
		Pitch = 0.85,
	},
	{
		Id = "Jelly",
		Name = "Želé",
		Price = 234000,
		Level = 4,
		Integrity = 220,
		Value = 1230,
		Xp = 12,
		Color = Color3.fromRGB(255, 96, 160),
		Material = Enum.Material.Glass,
		Shape = "Ball",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.3,
	},
	{
		Id = "Chocolate",
		Name = "Čokoláda",
		Price = 10100000,
		Level = 7,
		Integrity = 900,
		Value = 8100,
		Xp = 20,
		Color = Color3.fromRGB(102, 60, 36),
		Material = Enum.Material.Slate,
		Shape = "Block",
		SoundId = "rbxassetid://9125402735",
		Pitch = 0.75,
	},
	{
		Id = "Ice",
		Name = "Led",
		Price = 356000000,
		Level = 11,
		Integrity = 3800,
		Value = 54700,
		Xp = 34,
		Color = Color3.fromRGB(186, 236, 255),
		Material = Enum.Material.Ice,
		Shape = "Block",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.4,
	},
	{
		Id = "Glass",
		Name = "Sklo",
		Price = 8500000000,
		Level = 15,
		Integrity = 16000,
		Value = 368000,
		Xp = 55,
		Color = Color3.fromRGB(214, 246, 255),
		Material = Enum.Material.Glass,
		Shape = "Cylinder",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.5,
	},
	{
		Id = "Slime",
		Name = "Slime",
		Price = 108000000000,
		Level = 20,
		Integrity = 70000,
		Value = 2590000,
		Xp = 90,
		Color = Color3.fromRGB(126, 255, 128),
		Material = Enum.Material.Neon,
		Shape = "Ball",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.1,
	},
	{
		Id = "Crystal",
		Name = "Křišťál",
		Price = 1730000000000,
		Level = 26,
		Integrity = 300000,
		Value = 17700000,
		Xp = 150,
		Color = Color3.fromRGB(168, 214, 255),
		Material = Enum.Material.Glass,
		Shape = "Block",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.6,
	},
	{
		Id = "Stardust",
		Name = "Hvězdný prach",
		Price = 5480000000000,
		Level = 33,
		Integrity = 1300000,
		Value = 122000000,
		Xp = 260,
		Color = Color3.fromRGB(196, 150, 255),
		Material = Enum.Material.Neon,
		Shape = "Ball",
		SoundId = "rbxassetid://9125402735",
		Pitch = 1.7,
	},
}

-- Vylepšení (nekonečný grind) --------------------------------------------
-- Cena úrovně n = BasePrice * Growth^(n-1)
Config.Upgrades = {
	{
		Id = "Sharpness",
		Name = "Ostrost",
		Desc = "+25 % poškození za úroveň",
		Icon = "🔪",
		MaxLevel = 40,
		BasePrice = 250,
		Growth = 1.55,
		PerLevel = 0.25,
	},
	{
		Id = "Speed",
		Name = "Rychlost",
		Desc = "-3 % prodleva mezi ranami za úroveň",
		Icon = "⚡",
		MaxLevel = 25,
		BasePrice = 600,
		Growth = 1.7,
		PerLevel = 0.03,
	},
	{
		Id = "Fortune",
		Name = "Štědrost",
		Desc = "+20 % peněz za úroveň",
		Icon = "💰",
		MaxLevel = 40,
		BasePrice = 900,
		Growth = 1.6,
		PerLevel = 0.20,
	},
	{
		Id = "Combo",
		Name = "Kombo mistr",
		Desc = "+0,25× strop komba za úroveň",
		Icon = "🔥",
		MaxLevel = 16,
		BasePrice = 3000,
		Growth = 1.9,
		PerLevel = 0.25,
	},
	{
		Id = "Auto",
		Name = "Auto-řez",
		Desc = "+1 automatická rána za sekundu",
		Icon = "🤖",
		MaxLevel = 12,
		BasePrice = 25000,
		Growth = 2.35,
		PerLevel = 1,
	},
}

-- Rebirth -----------------------------------------------------------------
Config.Rebirth = {
	BaseCost = 1500000000, -- cena prvního rebirthu (~3 h hraní, změřeno simulací)
	Growth = 6.5, -- každý další je 6,5× dražší
	BonusPerRebirth = 0.35, -- +35 % ke všem výdělkům, natrvalo
	KeepTools = true, -- nástroje zůstávají, materiály a vylepšení se resetují
}

-- Levely ------------------------------------------------------------------
Config.Level = {
	BaseXp = 120, -- XP na 2. úroveň
	-- Růst 1,28 dělal ze stropu nedosažitelnou metu (hráč uvízl na 44).
	-- 1,20 a strop 50 vychází tak, že max level padne až v pozdním grindu.
	Growth = 1.20,
	MaxLevel = 50,
}

-- Odměny za odehraný čas (grind za hraní) --------------------------------
Config.Playtime = {
	{ Minutes = 2, Coins = 1000, Label = "2 minuty" },
	{ Minutes = 5, Coins = 8000, Label = "5 minut" },
	{ Minutes = 10, Coins = 50000, Label = "10 minut" },
	{ Minutes = 20, Coins = 400000, Label = "20 minut" },
	{ Minutes = 35, Coins = 2000000, Label = "35 minut" },
	{ Minutes = 60, Coins = 12000000, Label = "1 hodina" },
	{ Minutes = 90, Coins = 40000000, Label = "1,5 hodiny" },
	{ Minutes = 120, Coins = 150000000, Label = "2 hodiny" },
	{ Minutes = 180, Coins = 600000000, Label = "3 hodiny" },
	{ Minutes = 240, Coins = 2000000000, Label = "4 hodiny" },
}

-- Vzhled ------------------------------------------------------------------
Config.Theme = {
	Background = Color3.fromRGB(16, 15, 26),
	Panel = Color3.fromRGB(30, 28, 48),
	PanelLight = Color3.fromRGB(43, 40, 66),
	Accent = Color3.fromRGB(255, 126, 219),
	Accent2 = Color3.fromRGB(126, 208, 255),
	Success = Color3.fromRGB(102, 226, 148),
	Danger = Color3.fromRGB(255, 106, 106),
	Gold = Color3.fromRGB(255, 206, 84),
	Text = Color3.fromRGB(244, 242, 255),
	TextDim = Color3.fromRGB(163, 158, 192),
}

-- Vyhledávače -------------------------------------------------------------

local function findById(list, id: string)
	for index, entry in list do
		if entry.Id == id then
			return entry, index
		end
	end
	return nil, nil
end

function Config.tool(id: string)
	return (findById(Config.Tools, id))
end

function Config.object(id: string)
	return (findById(Config.Objects, id))
end

-- Pořadí materiálu v seznamu (1 = startovní). Používá se pro velikost
-- kusu na stanici, aby pozdější materiály byly viditelně mohutnější.
function Config.objectTier(id: string): number
	local _, index = findById(Config.Objects, id)
	return index or 1
end

function Config.upgrade(id: string)
	return (findById(Config.Upgrades, id))
end

-- Cena další úrovně vylepšení (level = počet už koupených úrovní)
function Config.upgradePrice(id: string, level: number): number?
	local upgrade = Config.upgrade(id)
	if not upgrade or level >= upgrade.MaxLevel then
		return nil
	end
	return math.floor(upgrade.BasePrice * upgrade.Growth ^ level)
end

-- Kolik XP je potřeba pro postup z `level` na `level + 1`
function Config.xpForLevel(level: number): number
	return math.floor(Config.Level.BaseXp * Config.Level.Growth ^ (level - 1))
end

function Config.rebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * Config.Rebirth.Growth ^ rebirths)
end

return Config

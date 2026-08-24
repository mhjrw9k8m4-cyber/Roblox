--!strict
--[[
	Live — obsah, který se za běhu hry mění: kódy, denní odměny, questy,
	pety, vejce a placené věci.

	Je oddělený od `Config` schválně. Config drží pravidla hry, tohle drží
	obsah, který budeš měnit každý týden — nový kód po videu, nová sezóna
	petů, jiné denní odměny. Update pak znamená sáhnout do jednoho souboru.

	Proč to tady vůbec je: Roblox v roce 2026 řadí hry podle retence
	(návrat druhý den, návrat do týdne, délka sezení), ne podle počtu hráčů
	online. Všechno v tomhle souboru existuje proto, aby měl hráč důvod
	se vrátit zítra.
]]

local Live = {}

-- Kódy ---------------------------------------------------------------------
--[[
	Uplatnitelné jednou za účet. Přidávej je s každým videem nebo updatem —
	kód je nejlevnější způsob, jak přivést hráče zpátky.

	`Expires` je unixový čas; 0 znamená bez omezení.
]]
Live.Codes = {
	{ Code = "LAUNCH", Coins = 5000, Gems = 50, Expires = 0 },
	{ Code = "SMASH", Coins = 2500, Gems = 25, Expires = 0 },
	{ Code = "POWER100", Coins = 10000, Gems = 0, Expires = 0 },
	{ Code = "GEMS50", Coins = 0, Gems = 50, Expires = 0 },
	{ Code = "THANKS", Coins = 1000, Gems = 10, Expires = 0 },
}

-- Denní odměny --------------------------------------------------------------
--[[
	Sedmidenní kolotoč. Sedmý den je schválně skokově lepší — to je den,
	kvůli kterému lidi drží streak, a zároveň přesně ten okamžik, který
	rozhoduje o D7 retenci.

	`Coins` je násobek aktuálního příjmu za sekundu, ne pevné číslo.
	Pevná částka by byla v první hodině obrovská a v desáté k ničemu.
]]
Live.Daily = {
	{ Day = 1, CoinSeconds = 30, Gems = 5 },
	{ Day = 2, CoinSeconds = 60, Gems = 8 },
	{ Day = 3, CoinSeconds = 120, Gems = 12 },
	{ Day = 4, CoinSeconds = 200, Gems = 18 },
	{ Day = 5, CoinSeconds = 320, Gems = 25 },
	{ Day = 6, CoinSeconds = 500, Gems = 35 },
	{ Day = 7, CoinSeconds = 900, Gems = 75, Egg = "Golden" },
}

-- Denní úkoly ---------------------------------------------------------------
--[[
	Každý den se vylosují tři. Splnit všechny tři drží questovou sérii,
	která dává gemy navíc — dvě smyčky (denní odměna + úkoly) drží hráče
	líp než jedna.

	`Scale` říká, jestli se cíl škáluje s postupem hráče. Bez toho je
	"seber 200 pickupů" v prvním světě dřina a v šestém nic.
]]
Live.Quests = {
	{ Id = "Smash", Text = "Smash {target} walls", Type = "smash", Base = 12, Scale = 1.0, Gems = 10 },
	{ Id = "Collect", Text = "Collect {target} pickups", Type = "collect", Base = 250, Scale = 1.0, Gems = 10 },
	{ Id = "Clear", Text = "Clear {target} full laps", Type = "clear", Base = 2, Scale = 0.5, Gems = 15 },
	{ Id = "Spend", Text = "Spend {target} coins", Type = "spend", Base = 20, Scale = 0.0, Gems = 12 },
	{ Id = "Hatch", Text = "Hatch {target} pets", Type = "hatch", Base = 3, Scale = 0.0, Gems = 15 },
	{ Id = "Upgrade", Text = "Buy {target} upgrades", Type = "upgrade", Base = 5, Scale = 0.0, Gems = 10 },
}

Live.QuestsPerDay = 3
Live.QuestStreakGems = 20 -- bonus za splnění všech tří

-- Pety -----------------------------------------------------------------------
--[[
	Pet je násobič Poweru, který lítá za hráčem. V žánru je to hlavní
	dlouhodobý cíl — hráč grinduje na vejce, ne na další upgrade.

	`Power` je přírůstek k násobiči (0.25 = +25 %). Nasazených může být
	víc naráz, jejich bonusy se sčítají.
]]
Live.Rarities = {
	Common = { Name = "Common", Color = Color3.fromRGB(186, 196, 214), Weight = 100 },
	Rare = { Name = "Rare", Color = Color3.fromRGB(96, 226, 255), Weight = 34 },
	Epic = { Name = "Epic", Color = Color3.fromRGB(150, 86, 255), Weight = 10 },
	Legendary = { Name = "Legendary", Color = Color3.fromRGB(255, 196, 60), Weight = 2.4 },
	Mythic = { Name = "Mythic", Color = Color3.fromRGB(255, 86, 178), Weight = 0.4 },
}

Live.Pets = {
	-- Basic Egg
	{ Id = "Pebble", Name = "Pebble", Rarity = "Common", Power = 0.1, Egg = "Basic", Shape = "Ball" },
	{ Id = "Cube", Name = "Cube", Rarity = "Common", Power = 0.14, Egg = "Basic", Shape = "Block" },
	{ Id = "Spark", Name = "Spark", Rarity = "Rare", Power = 0.3, Egg = "Basic", Shape = "Ball" },
	{ Id = "Prism", Name = "Prism", Rarity = "Epic", Power = 0.7, Egg = "Basic", Shape = "Block" },
	{ Id = "Comet", Name = "Comet", Rarity = "Legendary", Power = 1.8, Egg = "Basic", Shape = "Ball" },

	-- Golden Egg
	{ Id = "Coin", Name = "Coinling", Rarity = "Common", Power = 0.35, Egg = "Golden", Shape = "Cylinder" },
	{ Id = "Nugget", Name = "Nugget", Rarity = "Rare", Power = 0.8, Egg = "Golden", Shape = "Block" },
	{ Id = "Crown", Name = "Crownling", Rarity = "Epic", Power = 1.9, Egg = "Golden", Shape = "Block" },
	{ Id = "Sunburst", Name = "Sunburst", Rarity = "Legendary", Power = 4.5, Egg = "Golden", Shape = "Ball" },
	{ Id = "Midas", Name = "Midas", Rarity = "Mythic", Power = 12, Egg = "Golden", Shape = "Ball" },

	-- Void Egg
	{ Id = "Shard", Name = "Void Shard", Rarity = "Rare", Power = 2.2, Egg = "Void", Shape = "Block" },
	{ Id = "Rift", Name = "Rift", Rarity = "Epic", Power = 5.5, Egg = "Void", Shape = "Ball" },
	{ Id = "Eclipse", Name = "Eclipse", Rarity = "Legendary", Power = 14, Egg = "Void", Shape = "Ball" },
	{ Id = "Singularity", Name = "Singularity", Rarity = "Mythic", Power = 40, Egg = "Void", Shape = "Ball" },
}

--[[
	Vejce. Cena je dopočítaná ze simulace tak, aby první vejce padlo
	kolem desáté minuty a Void bylo cílem na pozdní hru.
]]
Live.Eggs = {
	{ Id = "Basic", Name = "Basic Egg", Price = 25000, Color = Color3.fromRGB(214, 226, 255) },
	{ Id = "Golden", Name = "Golden Egg", Price = 4000000, Color = Color3.fromRGB(255, 196, 60) },
	{ Id = "Void", Name = "Void Egg", Price = 900000000, Color = Color3.fromRGB(150, 86, 255) },
}

Live.MaxEquippedPets = 3
Live.MaxEquippedPetsVip = 6

-- Placené věci ----------------------------------------------------------------
--[[
	ID jsou nuly — doplň je, až gamepassy a produkty vytvoříš na
	Creator Dashboardu. Dokud je tam nula, tlačítka se v UI nezobrazí,
	takže hra funguje i bez nich a nikomu neukazuje mrtvé nabídky.
]]
Live.Passes = {
	{ Id = "Coins2", Name = "×2 Coins", Desc = "Double coins forever.", GamepassId = 0, Icon = "💰" },
	{ Id = "AutoCollect", Name = "Auto Collect", Desc = "Collects pickups for you, forever.", GamepassId = 0, Icon = "🤖" },
	{ Id = "Vip", Name = "VIP", Desc = "6 pet slots, +50% power, VIP tag.", GamepassId = 0, Icon = "👑" },
	{ Id = "Lucky", Name = "Lucky Eggs", Desc = "Much better odds from every egg.", GamepassId = 0, Icon = "🍀" },
}

Live.Products = {
	{ Id = "Gems100", Name = "100 Gems", Gems = 100, ProductId = 0, Icon = "💎" },
	{ Id = "Gems550", Name = "550 Gems", Gems = 550, ProductId = 0, Icon = "💎" },
	{ Id = "CoinsSmall", Name = "Coin Boost", CoinSeconds = 600, ProductId = 0, Icon = "💰" },
	{ Id = "CoinsBig", Name = "Big Coin Boost", CoinSeconds = 3600, ProductId = 0, Icon = "💰" },
}

-- Bonusy z pasů, které se počítají do ekonomiky
Live.PassBonus = {
	Coins2 = 2, -- násobič peněz
	Vip = 1.5, -- násobič Poweru
	LuckyWeight = 4, -- o kolik se u Lucky nadlehčí vzácné pety
}

-- Badge ------------------------------------------------------------------------
-- ID doplň z Creator Dashboardu; nula = badge se prostě neudělí.
Live.Badges = {
	{ Id = "FirstSmash", Name = "First Wall", BadgeId = 0, Smashes = 1 },
	{ Id = "Hundred", Name = "100 Walls", BadgeId = 0, Smashes = 100 },
	{ Id = "Thousand", Name = "1000 Walls", BadgeId = 0, Smashes = 1000 },
	{ Id = "FirstRebirth", Name = "Reborn", BadgeId = 0, Rebirths = 1 },
	{ Id = "WorldThree", Name = "Ice Breaker", BadgeId = 0, Worlds = 3 },
	{ Id = "WorldSix", Name = "Void Walker", BadgeId = 0, Worlds = 6 },
}

-- Vyhledávače --------------------------------------------------------------------

local function findById(list, id: string)
	for index, entry in list do
		if entry.Id == id then
			return entry, index
		end
	end
	return nil, nil
end

function Live.pet(id: string)
	return (findById(Live.Pets, id))
end

function Live.egg(id: string)
	return (findById(Live.Eggs, id))
end

function Live.pass(id: string)
	return (findById(Live.Passes, id))
end

function Live.product(id: string)
	return (findById(Live.Products, id))
end

function Live.quest(id: string)
	return (findById(Live.Quests, id))
end

function Live.rarity(id: string)
	return Live.Rarities[id] or Live.Rarities.Common
end

-- Kód se porovnává bez ohledu na velikost písmen a okolní mezery
function Live.code(input: string)
	local normalized = string.upper((input:gsub("%s", "")))
	for _, entry in Live.Codes do
		if entry.Code == normalized then
			return entry
		end
	end
	return nil
end

-- Pety, které se dají vylíhnout z daného vejce
function Live.eggPool(eggId: string)
	local pool = {}
	for _, pet in Live.Pets do
		if pet.Egg == eggId then
			table.insert(pool, pet)
		end
	end
	return pool
end

return Live
